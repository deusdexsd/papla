import AppKit
import SwiftUI
@preconcurrency import Translation

/// One-shot, on-device translation for text that's already finished (a dictated utterance, a
/// clipboard entry) — not a live/streaming translation UI. Polish is always the source; the
/// target is whatever `Settings.translateTargetLanguage` is set to.
///
/// Apple's `Translation` framework only exposes a session through the SwiftUI
/// `.translationTask` modifier — there is no plain `TranslationSession(source:target:)`
/// initializer. To use it from ordinary Swift code (a hotkey handler, not a view body), this
/// hosts a single invisible SwiftUI view long enough for `.translationTask` to fire once, then
/// tears the whole thing down. The system may show its own small "downloading Polish→X"
/// sheet the first time a language pair is used — same one-time-cost shape as Parakeet's model
/// download, just Apple's own UI for it instead of Papla's.
@MainActor
enum Translator {
    enum TranslatorError: LocalizedError {
        case unavailable
        case timedOut

        var errorDescription: String? {
            switch self {
            case .timedOut:
                tSync("Tłumaczenie trwało zbyt długo.", "Translation took too long.")
            case .unavailable:
                tSync("Tłumaczenie niedostępne dla tej pary języków.",
                      "Translation isn't available for this language pair.")
            }
        }
    }

    /// Dictation's "dyktuj i przetłumacz": source is always Polish.
    static func translate(_ text: String, to target: TranslateLanguage) async throws -> String {
        try await translate(text, from: Locale.Language(identifier: "pl"), to: Locale.Language(identifier: target.rawValue))
    }

    /// The clipboard panel's "przetłumacz na polski": source is whatever the copied text
    /// turns out to be, left `nil` so the framework detects it itself.
    static func translate(_ text: String, from source: Locale.Language?, to target: Locale.Language) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }

        // Tell "pack already on this Mac" from "known pair, pack not downloaded yet" from "no such
        // pair" up front. An uninstalled pack used to fail (or stall) invisibly inside the
        // offscreen host — Apple's download sheet has nowhere to appear there — and the caller
        // just fell back to pasting the untranslated original.
        let availability = LanguageAvailability()
        let status: LanguageAvailability.Status
        if let source {
            status = await availability.status(from: source, to: target)
        } else {
            // Detection failing outright is treated as "can't vouch for it being installed" —
            // the visible path below handles both cases, the offscreen one only the first.
            status = (try? await availability.status(for: text, to: target)) ?? .supported
        }
        if status == .unsupported { throw TranslatorError.unavailable }

        if status == .installed {
            do {
                return try await run(text, source: source, target: target, needsDownload: false)
            } catch TranslatorError.timedOut {
                throw TranslatorError.timedOut
            } catch {
                // The status said "installed" but the offscreen session still refused
                // ("Unable to Translate") — retry once where the system can show its own UI.
                Log.app.error("offscreen translation failed (\(String(describing: error), privacy: .public)) — retrying visibly")
            }
        }
        return try await run(text, source: source, target: target, needsDownload: true)
    }

    private static func run(
        _ text: String, source: Locale.Language?, target: Locale.Language, needsDownload: Bool
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let host = TranslationHostWindow(
                text: text, source: source, target: target, needsDownload: needsDownload
            ) { result in
                continuation.resume(with: result)
            }
            host.show()
        }
    }
}

/// Owns the offscreen window + hosting controller for exactly one translation, then releases
/// itself. Kept as a class (not a throwaway struct) so it can hold a strong self-reference
/// while the async `.translationTask` is in flight — nothing else keeps it alive.
@MainActor
private final class TranslationHostWindow {
    private var window: NSWindow?
    private var strongSelf: TranslationHostWindow?
    private var finished = false
    private let text: String
    private let source: Locale.Language?
    private let target: Locale.Language
    private let needsDownload: Bool
    private let completion: (Result<String, Error>) -> Void

    init(
        text: String,
        source: Locale.Language?,
        target: Locale.Language,
        needsDownload: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        self.text = text
        self.source = source
        self.target = target
        self.needsDownload = needsDownload
        self.completion = completion
    }

    func show() {
        strongSelf = self // survives past `show()` returning

        let view = TranslationTaskView(
            text: text, source: source, target: target, needsDownload: needsDownload
        ) { [weak self] result in
            self?.finish(result)
        }
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        if needsDownload {
            // First use of this pair: the system's own "download language" sheet needs a real,
            // visible window to attach to, so show a small one for the duration.
            window.title = "Papla"
            window.styleMask = [.titled]
            window.level = .floating
            window.setContentSize(NSSize(width: 320, height: 110))
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.setFrame(NSRect(x: -10_000, y: -10_000, width: 4, height: 4), display: false)
            window.setIsVisible(true)
        }
        self.window = window

        // A translation that never reports back would leave the dictation stuck mid-"finishing"
        // forever — long allowance when a pack has to download, short when it's already local.
        let limit: Duration = needsDownload ? .seconds(180) : .seconds(20)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: limit)
            self?.finish(.failure(Translator.TranslatorError.timedOut))
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        window?.close()
        window = nil
        completion(result)
        strongSelf = nil
    }
}

/// The actual `.translationTask` host. Runs once (`didRun` guards against SwiftUI re-invoking
/// the task body on a spurious update) and reports back through `onResult`.
private struct TranslationTaskView: View {
    let text: String
    let source: Locale.Language?
    let target: Locale.Language
    let needsDownload: Bool
    let onResult: (Result<String, Error>) -> Void

    @State private var didRun = false

    var body: some View {
        Group {
            if needsDownload {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(t("Tłumaczenie: zatwierdź pobranie pakietu językowego w oknie systemowym.", "Translation: approve the language pack download in the system prompt."))
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(width: 320, height: 110)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .translationTask(source: source, target: target) { session in
            guard !didRun else { return }
            didRun = true
            do {
                if needsDownload { try await session.prepareTranslation() }
                let response = try await session.translate(text)
                onResult(.success(response.targetText))
            } catch {
                onResult(.failure(error))
            }
        }
    }
}
