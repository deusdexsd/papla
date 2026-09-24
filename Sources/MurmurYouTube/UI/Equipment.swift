import SwiftUI

// The shared vocabulary of the app: cards, wells, keys, lamps, labels. Every value here
// comes from `DS`. If a component needs a number that isn't a token, the token is missing —
// add it there rather than inlining it.

// MARK: - Surfaces

/// A glass card — the panel surface everything sits on. Same Liquid Glass material as the
/// clipboard search bar and Minutnik popup (`GlassIfPanel`), so a settings panel and a
/// floating popup read as the same product instead of two different visual languages.
struct BrushedPanel: View {
    var radius: CGFloat = DS.Radius.panel

    var body: some View {
        Color.clear
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// A recessed well. Content sits *in* it — a hairline edge, nothing more.
struct Well<Content: View>: View {
    var radius: CGFloat = DS.Radius.panel
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(DS.Color.well, in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(DS.Color.seam, lineWidth: DS.Border.hairline)
            )
    }
}

/// A dark readout surface — always dark regardless of face, so lit text has something to
/// sit against.
struct DeckWindow<Content: View>: View {
    var radius: CGFloat = DS.Radius.panel
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(DS.Color.deck, in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(DS.Color.seam, lineWidth: DS.Border.hairline)
            )
    }
}

// MARK: - Labels

/// A small panel/section label — semibold, faintly tracked, quieter than body text.
struct Silkscreen: View {
    let text: String
    var large = false
    var color: Color = DS.Color.silkscreen

    var body: some View {
        Text(text)
            .font(large ? DS.Font.silkscreenLarge : DS.Font.silkscreen)
            .tracking(DS.Font.silkscreenTracking)
            .foregroundStyle(color)
    }
}

// MARK: - Indicators

/// A status lamp — a soft glow when lit, not a hard lens. Used for on/off state (a
/// dictionary entry, the record indicator).
struct Lamp: View {
    let color: Color
    var isLit: Bool
    var size: CGFloat = DS.Material.lampSize

    var body: some View {
        Circle()
            .fill(color.opacity(isLit ? 1 : DS.Material.lampUnlitOpacity))
            .overlay {
                if isLit {
                    Circle()
                        .fill(color)
                        .blur(radius: size * 0.6)
                        .opacity(DS.Material.lampGlow)
                }
            }
            .frame(width: size, height: size)
            .animation(DS.Motion.lamp, value: isLit)
    }
}

// MARK: - Controls

/// A button in the search bar's own voice: a capsule chip, quiet when off, an accent wash
/// with a ring when engaged — the same shape and type as the clipboard panel's filter chips.
struct TransportKey: View {
    let title: String
    var systemImage: String?
    var isEngaged = false
    var engagedColor: Color = DS.Color.record
    var isEnabled = true
    /// A resting tint for a button that belongs to a different family than its neighbours.
    var tint: Color?
    var help: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.tight) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(isEngaged ? DS.Color.ink : DS.Color.ink.opacity(0.75))
            .frame(minWidth: title.isEmpty ? 0 : DS.Material.keyMinWidth - DS.Space.roomy * 2)
            .padding(.horizontal, title.isEmpty ? DS.Space.base : DS.Space.roomy)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isEngaged
                    ? engagedColor.opacity(0.2)
                    : (tint?.opacity(isHovering ? 0.26 : 0.18) ?? DS.Color.ink.opacity(isHovering ? 0.12 : 0.08)))
            )
            .overlay(Capsule().strokeBorder(isEngaged ? engagedColor.opacity(0.8) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovering = $0 }
        .help(help ?? "")
        .animation(DS.Motion.panel, value: isEngaged)
    }
}

/// A monospaced readout on a dark window — timings, the transport counter.
struct Readout: View {
    let text: String
    var large = false

    var body: some View {
        Text(text)
            .font(large ? DS.Font.counterLarge : DS.Font.counter)
            .foregroundStyle(DS.Color.inkOnDeck)
    }
}
