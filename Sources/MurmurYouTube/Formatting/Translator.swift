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

        var errorDescription: String? {
            switch self {
            case .unavailable: "Tłumaczenie niedostępne — sprawdź Ustawienia systemowe ▸ Ogólne ▸ Język i region."
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

        return try await withCheckedThrowingContinuation { continuation in
            let host = TranslationHostWindow(text: text, source: source, target: target) { result in
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
    private let text: String
    private let source: Locale.Language?
    private let target: Locale.Language
    private let completion: (Result<String, Error>) -> Void

    init(
        text: String,
        source: Locale.Language?,
        target: Locale.Language,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        self.text = text
        self.source = source
        self.target = target
        self.completion = completion
    }

    func show() {
        strongSelf = self // survives past `show()` returning

        let view = TranslationTaskView(text: text, source: source, target: target) { [weak self] result in
            self?.finish(result)
        }
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.setFrame(NSRect(x: -10_000, y: -10_000, width: 4, height: 4), display: false)
        window.setIsVisible(true)
        self.window = window
    }

    private func finish(_ result: Result<String, Error>) {
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
    let onResult: (Result<String, Error>) -> Void

    @State private var didRun = false

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(source: source, target: target) { session in
                guard !didRun else { return }
                didRun = true
                do {
                    let response = try await session.translate(text)
                    onResult(.success(response.targetText))
                } catch {
                    onResult(.failure(error))
                }
            }
    }
}
