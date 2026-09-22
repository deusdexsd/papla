import MurmurDictionary
import AVFoundation
import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle
        case starting
        case listening
        case finishing
        case error(String)

        var isActive: Bool {
            switch self {
            case .starting, .listening, .finishing: true
            case .idle, .error: false
            }
        }

        /// Whether the HUD panel should be on screen. Distinct from `isActive`: an error
        /// isn't "active" (nothing is being captured, a second press should be able to
        /// start fresh), but it does need to be *seen* — `fail()` holds it for 3 seconds
        /// before dropping back to `.idle`, and the panel dismissing in the same instant
        /// the message appears made every error invisible, just a flash.
        var showsHUD: Bool {
            switch self {
            case .starting, .listening, .finishing, .error: true
            case .idle: false
            }
        }
    }

    private(set) var state: State = .idle
    /// Live transcript, updated as the engine revises it. Drives the HUD.
    private(set) var transcript = ""
    /// Smoothed 0…1 mic level for the waveform.
    private(set) var level: Float = 0

    private let hotkey = HotkeyMonitor()
    private let translateHotkey = HotkeyMonitor()
    private let capture = AudioCapture()

    private enum Trigger { case normal, translate }

    /// Which trigger *started* the recording in flight — decided once, at `beginDictation()`.
    /// In `.hold` mode, only a release of this one's own key stops the recording; pressing the
    /// other trigger mid-recording never does, it only flips `wantsTranslate` (see
    /// `handleKeyPress`). In `.toggle` mode it's what a second press of the *same* trigger
    /// needs to match to stop things.
    private var startingTrigger: Trigger = .normal

    /// Whether the recording in flight (or about to start) should be translated before
    /// injecting — read by `endDictation()`, and by the HUD to pick its color palette. Starts
    /// out matching whichever trigger began the recording, but can be flipped mid-recording by
    /// pressing the *other* trigger — "ten sam skrót plus jeszcze jeden klawisz", not two
    /// fully independent start/stop shortcuts.
    private(set) var wantsTranslate = false

    private let makeEngine: @Sendable () -> any TranscriptionEngine

    /// Injected only by tests; production reads the setting per-utterance below.
    private let formatter: (any TextFormatter)?

    /// Fixed to the deterministic cleanup unless a test injects its own.
    private var activeFormatter: any TextFormatter { formatter ?? RuleBasedFormatter() }

    private var engine: (any TranscriptionEngine)?
    private var consumeTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?

    /// Timestamps for the history list: when the key went down, and when it came up.
    private var holdStarted: Date?
    private var releasedAt: Date?

    init(
        formatter: (any TextFormatter)? = nil,
        makeEngine: @escaping @Sendable () -> any TranscriptionEngine = { ParakeetEngine() }
    ) {
        self.formatter = formatter
        self.makeEngine = makeEngine
    }

    // MARK: - Lifecycle

    /// - Returns: `false` if the hotkey tap couldn't be installed (missing Accessibility).
    @discardableResult
    func activate() -> Bool {
        hotkey.trigger = Settings.shared.customShortcut.map(HotkeyMonitor.TriggerSpec.custom)
            ?? .modifiersOnly(Settings.shared.triggerKeys)
        hotkey.onPress = { [weak self] in self?.handleKeyPress(trigger: .normal) }
        hotkey.onRelease = { [weak self] in self?.handleKeyRelease(trigger: .normal) }
        let started = hotkey.start()

        // A second, independent tap for "dyktuj i przetłumacz" — its own shortcut, watched
        // alongside the normal one exactly like grab/clipboard/color already are.
        translateHotkey.trigger = .custom(Settings.shared.translateShortcut)
        translateHotkey.onPress = { [weak self] in self?.handleKeyPress(trigger: .translate) }
        translateHotkey.onRelease = { [weak self] in self?.handleKeyRelease(trigger: .translate) }
        let translateStarted = translateHotkey.start()

        return started && translateStarted
    }

    /// In `.hold` mode a press always starts a fresh recording (the matching release ends
    /// it). In `.toggle` mode the same key both starts and stops: a press while idle starts,
    /// a press while active stops — so it doubles as the "I changed my mind" cancel too.
    ///
    /// Either mode, a press on the *other* trigger while a recording is already running never
    /// starts or stops anything — it just flips `wantsTranslate` for the recording in flight,
    /// so you can decide mid-sentence that this one should (or shouldn't) be translated.
    private func handleKeyPress(trigger: Trigger) {
        if state.isActive {
            if trigger != startingTrigger {
                wantsTranslate.toggle()
            } else if Settings.shared.triggerMode == .toggle {
                endDictation()
            }
            return
        }
        beginDictation(trigger: trigger)
    }

    /// Ignored entirely in `.toggle` mode, and in `.hold` mode ignored for whichever trigger
    /// *didn't* start the recording — releasing the key you used to flip translation on or off
    /// mid-sentence must not stop the recording, only the one still being held from the start
    /// does that.
    private func handleKeyRelease(trigger: Trigger) {
        guard Settings.shared.triggerMode == .hold, trigger == startingTrigger else { return }
        endDictation()
    }

    func deactivate() {
        hotkey.stop()
        translateHotkey.stop()
        cancelDictation()
    }

    /// Re-arms the taps after the user picks a different push-to-talk key or shortcut.
    @discardableResult
    func reloadHotkey() -> Bool {
        hotkey.stop()
        translateHotkey.stop()
        return activate()
    }

    // MARK: - Button-driven recording

    /// Starts a recording from a Record button rather than the hotkey.
    func startButtonRecording() {
        guard case .idle = state else { return }
        beginDictation(trigger: .normal)
    }

    func stopButtonRecording() {
        endDictation()
    }

    // MARK: - Dictation

    private func beginDictation(trigger: Trigger) {
        guard case .idle = state else { return }
        startingTrigger = trigger
        wantsTranslate = trigger == .translate
        state = .starting
        transcript = ""
        holdStarted = Date()

        Task { @MainActor in
            do {
                guard await Permissions.requestMicrophone() else {
                    fail("Dostęp do mikrofonu jest wyłączony. Włącz go w Ustawienia systemowe ▸ Prywatność i bezpieczeństwo ▸ Mikrofon.")
                    return
                }

                let engine = makeEngine()
                self.engine = engine

                let chunks = try await engine.start()

                guard let format = await engine.preferredInputFormat() else {
                    throw TranscriptionError.noAudioFormat
                }

                // Audio must reach the engine in capture order. A stream plus a single
                // draining task guarantees that; spawning a Task per buffer would not.
                let (audioStream, audioContinuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingNewest(64)
                )
                self.audioContinuation = audioContinuation

                self.feedTask = Task.detached(priority: .userInitiated) {
                    for await chunk in audioStream {
                        await engine.feed(chunk)
                    }
                }

                try capture.start(
                    outputFormat: format,
                    onBuffer: { chunk in
                        audioContinuation.yield(chunk)
                    },
                    onLevel: { [weak self] level in
                        Task { @MainActor in self?.updateLevel(level) }
                    }
                )

                // Bail out if the user already let go while we were spinning up.
                guard case .starting = self.state else {
                    await self.teardown()
                    return
                }

                self.state = .listening
                Sounds.playStart()

                self.consumeTask = Task { @MainActor in
                    do {
                        for try await chunk in chunks {
                            self.transcript = chunk.text
                        }
                    } catch {
                        self.fail(error.localizedDescription)
                    }
                }
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func endDictation() {
        // `.finishing` is "active", so without this a second press during processing would
        // run the whole tail again — re-reading `transcript` before the first pass cleared
        // it and pasting the same utterance twice. The window is wide: Parakeet transcribes
        // inside `finish()`.
        guard state.isActive, state != .finishing else { return }
        state = .finishing
        capture.stop()
        level = 0
        releasedAt = Date()

        Task { @MainActor in
            // Drain every captured buffer into the engine before asking it to finalize,
            // or the tail of the utterance gets dropped.
            audioContinuation?.finish()
            audioContinuation = nil
            await feedTask?.value
            feedTask = nil

            await engine?.finish()
            await consumeTask?.value
            consumeTask = nil
            engine = nil

            let raw = transcript
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                state = .idle
                transcript = ""
                wantsTranslate = false
                return
            }

            let cleaned = Settings.shared.cleanupEnabled
                ? await activeFormatter.format(raw)
                : raw

            // The dictionary runs last, and runs regardless of the cleanup setting. Biasing
            // only raises the odds of the right word; this is the pass that guarantees it,
            // so it must not be something the user can accidentally switch off.
            let (corrected, corrections) = DictionaryStore.shared.corrector.apply(to: cleaned)
            if !corrections.isEmpty {
                Log.speech.info("dictionary · \(corrections.count, privacy: .public) correction(s) applied")
            }

            // Emoji are matched against the *Polish* text, so this runs before translation
            // regardless of trigger — translating an already-inserted emoji is a no-op for
            // Apple's translator (it passes non-text glyphs through), translating first would
            // just mean matching against English words the dictionary was never built for.
            let enriched = EmojiEnricher.apply(
                to: corrected,
                intensity: Settings.shared.emojiIntensity,
                disabledKeywords: Settings.shared.emojiDisabledKeywords,
                customEntries: Settings.shared.customEmojiEntries,
                atSentenceEnd: Settings.shared.emojiAtSentenceEnd,
                suppressPeriod: Settings.shared.emojiSuppressPeriod
            )

            var output = enriched
            if wantsTranslate {
                do {
                    output = try await Translator.translate(enriched, to: Settings.shared.translateTargetLanguage)
                } catch {
                    Log.speech.error("translation failed, injecting Polish original: \(error.localizedDescription, privacy: .public)")
                }
            }

            recordRun(text: output, corrections: corrections)
            TextInjector.insert(output)
            Sounds.playEnd()

            state = .idle
            transcript = ""
            wantsTranslate = false
        }
    }

    private func cancelDictation() {
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        consumeTask?.cancel()
        consumeTask = nil

        let engine = self.engine
        self.engine = nil
        Task { await engine?.finish() }

        state = .idle
        transcript = ""
        level = 0
        wantsTranslate = false
    }

    private func teardown() async {
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        await feedTask?.value
        feedTask = nil
        await engine?.finish()
        engine = nil
        consumeTask?.cancel()
        consumeTask = nil
        state = .idle
    }

    // MARK: - Helpers

    /// Files the finished utterance in the history list.
    ///
    /// `processSeconds` is measured from key release, not from capture start — that's the
    /// wait the user actually experiences.
    private func recordRun(text: String, corrections: [AppliedCorrection] = []) {
        guard let holdStarted, let releasedAt else { return }
        RunLog.record(
            DictationRun(
                date: releasedAt,
                engine: "Parakeet",
                audioSeconds: releasedAt.timeIntervalSince(holdStarted),
                processSeconds: Date().timeIntervalSince(releasedAt),
                text: text,
                corrections: corrections.isEmpty ? nil : corrections
            )
        )
        self.holdStarted = nil
        self.releasedAt = nil
    }

    /// Light smoothing so the waveform glides instead of strobing at buffer rate.
    private func updateLevel(_ new: Float) {
        level += (new - level) * 0.35
    }

    private func fail(_ message: String) {
        Log.app.error("\(message, privacy: .public)")
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        engine = nil
        consumeTask?.cancel()
        consumeTask = nil
        state = .error(message)
        level = 0
        wantsTranslate = false

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if case .error = state { state = .idle }
        }
    }
}
