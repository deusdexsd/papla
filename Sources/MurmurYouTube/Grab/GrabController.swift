import AppKit
import Foundation
import Observation

/// Screen-text-grab (OCR), Papla's second trigger alongside dictation. Its own hotkey, its
/// own history, its own HUD — the only things shared with dictation are the design system,
/// the orb, `HotkeyMonitor`/`CustomShortcut` (reused as-is: a second independent
/// `HotkeyMonitor` instance arms a second `CGEventTap`), and the sound/color/HUD-position
/// settings that make sense app-wide rather than per-feature.
@MainActor
@Observable
final class GrabController {
    enum State: Equatable {
        case idle
        /// The overlay is up and the user is dragging (or about to). No HUD of its own —
        /// the dimmed screen and the drag rectangle already are the feedback.
        case selecting
        case capturing
        case recognizing
        case done(characters: Int)
        case error(String)

        var showsHUD: Bool {
            switch self {
            case .idle, .selecting: false
            case .capturing, .recognizing, .done, .error: true
            }
        }

        var isBusy: Bool {
            switch self {
            case .idle, .done, .error: false
            case .selecting, .capturing, .recognizing: true
            }
        }
    }

    private(set) var state: State = .idle

    private let hotkey = HotkeyMonitor()
    private let overlay = SelectionOverlayController()

    private var activeLanguages: [String] {
        var languages = [Settings.shared.grabPrimaryLanguage]
        if let secondary = Settings.shared.grabSecondaryLanguage, secondary != Settings.shared.grabPrimaryLanguage {
            languages.append(secondary)
        }
        return languages
    }

    // MARK: - Lifecycle

    /// - Returns: `false` if the tap couldn't be installed (missing Accessibility).
    @discardableResult
    func activate() -> Bool {
        hotkey.trigger = .custom(Settings.shared.grabShortcut)
        hotkey.onPress = { [weak self] in self?.beginGrab() }
        return hotkey.start()
    }

    func deactivate() {
        hotkey.stop()
    }

    @discardableResult
    func reloadHotkey() -> Bool {
        hotkey.stop()
        return activate()
    }

    // MARK: - Grabbing

    func beginGrab() {
        guard case .idle = state else { return }
        state = .selecting

        overlay.begin { [weak self] result in
            guard let self else { return }
            guard let (screen, rect) = result else {
                self.state = .idle
                return
            }
            Task { await self.runCapture(screen: screen, rect: rect) }
        }
    }

    /// The menu bar's "Chwyć cały ekran" — no drag needed, so it skips `.selecting`
    /// entirely and goes straight to capturing whichever screen currently has the pointer.
    func grabFullScreen() {
        guard case .idle = state else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else {
            fail(t("Nie znalazłem żadnego ekranu.", "Couldn't find a screen."))
            return
        }
        Task { await runFullScreenCapture(screen: screen) }
    }

    private func runFullScreenCapture(screen: NSScreen) async {
        state = .capturing
        do {
            let image = try await ScreenGrabber.captureFullScreen(screen)
            await recognizeAndDeliver(image: image)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func runCapture(screen: NSScreen, rect: CGRect) async {
        state = .capturing
        do {
            let image = try await ScreenGrabber.capture(screen: screen, rect: rect)
            await recognizeAndDeliver(image: image)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func recognizeAndDeliver(image: CGImage) async {
        state = .recognizing
        let started = Date()
        let languages = activeLanguages

        do {
            // Tried first, not as a fallback: a QR/2D code is a pixel pattern, not glyphs,
            // so the text recognizer below has nothing to find on one and would just
            // report "no text" — decoding the code's actual payload is unambiguously what
            // a selection centered on one is for, and it's pointless to also run the much
            // slower text pass over the same pixels once that's already the answer.
            let codes = try await OCREngine.detectCodes(image)
            if !codes.isEmpty {
                deliver(text: codes.joined(separator: "\n"), languages: ["Kod QR"], since: started)
                return
            }

            let lines = try await OCREngine.recognize(
                image,
                languages: languages,
                accurate: Settings.shared.grabAccurateRecognition
            )
            guard !lines.isEmpty else { throw OCRError.noText }

            let text = TextAssembler.assemble(
                lines,
                joinHyphenated: Settings.shared.grabJoinHyphenatedLines,
                straightenDashes: Settings.shared.grabStraightenDashes
            )
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OCRError.noText
            }

            deliver(text: text, languages: languages, since: started)
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Common tail for both a decoded code and ordinary recognized text: clipboard, the
    /// optional auto-paste, the history entry, the chime, and the brief "done" state.
    private func deliver(text: String, languages: [String], since started: Date) {
        GrabTextInjector.copyToClipboard(text)
        if Settings.shared.grabAutoPaste {
            GrabTextInjector.pasteIntoFocusedField(text)
        }

        GrabLog.record(Grab(
            date: Date(),
            text: text,
            languages: languages,
            recognizeSeconds: Date().timeIntervalSince(started)
        ))

        Sounds.playEnd()
        state = .done(characters: text.count)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if case .done = state { state = .idle }
        }
    }

    private func fail(_ message: String) {
        Log.app.error("\(message, privacy: .public)")
        state = .error(message)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if case .error = state { state = .idle }
        }
    }
}
