import SwiftUI

// The shared vocabulary of the app: cards, wells, keys, lamps, labels. Every value here
// comes from `DS`. If a component needs a number that isn't a token, the token is missing —
// add it there rather than inlining it.

// MARK: - Surfaces

/// A glass card — the panel surface everything sits on. Soft shadow, a hairline edge, a
/// faint top highlight; no grain, no fasteners.
struct BrushedPanel: View {
    var radius: CGFloat = DS.Radius.panel

    var body: some View {
        DS.Color.panel
            .clipShape(.rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(DS.Color.panelHighlight, lineWidth: DS.Border.bevel)
                    .blendMode(.plusLighter)
                    .opacity(0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(DS.Color.seam, lineWidth: DS.Border.seam)
            )
            .shadow(
                color: DS.Shadow.panel.color,
                radius: DS.Shadow.panel.radius,
                x: DS.Shadow.panel.x,
                y: DS.Shadow.panel.y
            )
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

/// A button in the app's own voice: flat glass cap, soft shadow, the orb's accent when
/// engaged. Press feedback is a scale/opacity dip, not a hardware key travel.
struct TransportKey: View {
    let title: String
    var systemImage: String?
    var isEngaged = false
    var engagedColor: Color = DS.Color.record
    var isEnabled = true
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.tight) {
                if isEngaged {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(engagedColor)
                        .transition(.scale.combined(with: .opacity))
                }
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Silkscreen(text: title, color: labelColor)
            }
            .frame(minWidth: DS.Material.keyMinWidth)
            .frame(height: DS.Material.keyHeight)
            .padding(.horizontal, DS.Space.base)
            .background(cap)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .scaleEffect(isPressed ? 0.96 : 1)
        .animation(DS.Motion.panel, value: isEngaged)
        .onLongPressGesture(minimumDuration: 0) {} onPressingChanged: { pressing in
            withAnimation(pressing ? DS.Motion.press : DS.Motion.release) { isPressed = pressing }
        }
    }

    private var labelColor: Color {
        isEngaged ? engagedColor : DS.Color.ink
    }

    private var cap: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.control)
                .fill(DS.Color.cap)
            // The caller's own color at moderate opacity when engaged — a wash, not a
            // neutral "lift", so it reads regardless of light/dark face or accent color.
            if isEngaged {
                RoundedRectangle(cornerRadius: DS.Radius.control)
                    .fill(engagedColor.opacity(0.16))
            }
            RoundedRectangle(cornerRadius: DS.Radius.control)
                .strokeBorder(isEngaged ? engagedColor.opacity(0.7) : DS.Color.seam,
                              lineWidth: isEngaged ? 1.5 : DS.Border.hairline)
        }
        .shadow(
            color: (isPressed ? DS.Shadow.pressed : DS.Shadow.raised).color,
            radius: (isPressed ? DS.Shadow.pressed : DS.Shadow.raised).radius,
            x: (isPressed ? DS.Shadow.pressed : DS.Shadow.raised).x,
            y: (isPressed ? DS.Shadow.pressed : DS.Shadow.raised).y
        )
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
