import SwiftUI

/// The floating indicator while a grab is being processed: the orb, plus — once there's
/// something to say — one line of text under it. Unlike dictation there's no live
/// transcript to caption, but there *is* a short-lived result ("Skopiowano 214 znaków")
/// worth showing, which the naked dictation HUD never needed.
struct GrabHUDView: View {
    @Bindable var controller: GrabController

    static let size = HUDView.size
    private static let orbSize: CGFloat = 64

    var body: some View {
        VStack(spacing: 12) {
            VisualizerView(energy: energy, isAnimating: isAnimating, isError: isError, size: Self.orbSize)

            if let message {
                Text(message)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
                    .frame(maxWidth: Self.size.width - 24)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var isError: Bool {
        if case .error = controller.state { return true }
        return false
    }

    private var isAnimating: Bool {
        switch controller.state {
        case .capturing, .recognizing: true
        case .idle, .selecting, .done, .error: false
        }
    }

    /// 0…1 "liveliness". There's no microphone level to ride here, so working states get a
    /// steady mid-level glow instead of the silence they'd otherwise show — the same reason
    /// dictation keeps its `.finishing` state visibly alive rather than freezing mid-word.
    private var energy: CGFloat {
        switch controller.state {
        case .idle, .selecting: 0
        case .capturing: 0.24
        case .recognizing: 0.40
        case .done: 0.55
        case .error: 0.28
        }
    }

    private var message: String? {
        switch controller.state {
        case .idle, .selecting, .capturing: nil
        case .recognizing: "Czytam tekst…"
        case .done(let characters):
            "Skopiowano \(characters) " + polishPlural(characters, one: "znak", few: "znaki", many: "znaków")
        case .error(let message): message
        }
    }
}
