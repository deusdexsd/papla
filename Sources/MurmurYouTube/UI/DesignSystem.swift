import SwiftUI

/// The design system for Papla.
///
/// Direction: the orb — the same glass sphere that's the app icon and the HUD indicator
/// (`SiriOrb` in HUDView.swift). Dark ground, soft glow, one blue/violet/cyan accent family
/// (`Brand`, also in HUDView.swift). No brushed metal, no hardware fasteners, no analog
/// meters — those belonged to a different app this was forked from; the window should look
/// like it belongs to the same product as the thing that appears while you're dictating.
///
/// Rules that keep this from turning into a generic dark-mode app:
/// - The accent is *only* `Brand.accent`/`accentWarm`/`accentCool` — no separate "selection
///   blue" invented elsewhere.
/// - Depth comes from soft shadows and translucency, never hard bevels.
/// - Radii stay generous and consistent — this is glass, not machined aluminum.
enum DS {

    // MARK: - Color

    @MainActor
    enum Color {
        /// The window's outer ground.
        static let chassis = face(light: 0xF3F3F7, dark: 0x0A0A0F)

        /// A grouped panel/card surface, lifted slightly off the chassis.
        static let panel = face(light: 0xFFFFFF, dark: 0x15151D)

        /// Subtle top-edge highlight on a card — a hint of glass catching light, not a bevel.
        static let panelHighlight = face(light: 0xFFFFFF, dark: 0x2A2A38)

        /// Bottom-edge shade on a card.
        static let panelShade = face(light: 0xE8E8EF, dark: 0x000000)

        /// Recessed wells — where lists sit, set into the panel.
        static let well = face(light: 0xF6F6FA, dark: 0x101016)

        /// A dark readout surface — always dark regardless of face, the way a terminal or a
        /// code block stays dark so text can be lit against it.
        static let deck = face(light: 0x18181F, dark: 0x0D0D12)

        /// Button/control surface, one step up from the panel.
        static let cap = face(light: 0xF6F6FA, dark: 0x1C1C26)

        /// A quiet divider — barely there, the way glass panels meet without a hard seam.
        static let seam = face(light: 0xE3E3EA, dark: 0x232330)

        // Text
        /// Primary readable text.
        static let ink = face(light: 0x15151C, dark: 0xF0EFF5)
        /// Supporting text — timings, counts, secondary rows.
        static let inkSecondary = face(light: 0x6B6B78, dark: 0x8E8DA0)
        /// A panel section label. Same family as `inkSecondary`, kept as its own token so a
        /// future change to one doesn't silently drag the other.
        static let silkscreen = face(light: 0x6B6B78, dark: 0x9695A8)
        /// Text on a dark readout well, regardless of face.
        static let inkOnDeck = swatch(0xEDEBF2)

        // Accent — the orb's own palette, reused as the app's only accent family.
        /// The record indicator. Warm red is still the one universal "this is recording"
        /// signal; it stays outside the orb's blue/violet/cyan family on purpose.
        static let record = swatch(0xE04A3F)
        static let recordIdle = face(light: 0xE3C6C3, dark: 0x3A2422)

        /// A selected row or engaged control — a wash of the orb's blue, not a neutral lift.
        /// Computed, not stored: `Brand.accent` is itself live off `Settings`, so a color
        /// change in Ustawienia has to reach here on every read, not just at first access.
        static var selection: SwiftUI.Color { Brand.accent }
        static var selectionEdge: SwiftUI.Color { Brand.accent }
        static var focusRing: SwiftUI.Color { Brand.accent }
        /// Row under the pointer, before selection.
        static let hover = face(light: 0xEDEDF3, dark: 0x1F1F2A)

        // Status — used sparingly, for the dictionary's own signals (on/off, a correction
        // that fired). Not UI chrome.
        static let statusGood = swatch(0x4FBE7A)
        static let statusWarning = swatch(0xE0A93E)
        static let statusBad = swatch(0xE0574A)

        // MARK: Face resolution

        private static func swatch(_ hex: UInt32) -> SwiftUI.Color { SwiftUI.Color(hex: hex) }

        /// Resolves to the light or dark value for the current appearance.
        private static func face(light: UInt32, dark: UInt32) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
        }
    }

    // MARK: - Material

    enum Material {
        // Indicator lamps — small, soft-edged, a glow rather than a hard lens.
        static let lampSize: CGFloat = 7
        static let lampGlow: Double = 0.55
        /// How far an unlit lamp sits below the lit value.
        static let lampUnlitOpacity: Double = 0.22

        // Buttons.
        static let keyHeight: CGFloat = 34
        static let keyMinWidth: CGFloat = 52
    }

    // MARK: - Type

    /// A clean system grotesk. The old design used a tracked-uppercase "silkscreen" look for
    /// panel labels; kept as a lighter touch here (small-caps-ish tracking, not full
    /// uppercase-and-tiny) since there's no equipment face to print onto anymore.
    enum Font {
        static let silkscreen = SwiftUI.Font.system(size: 11, weight: .semibold, design: .rounded)
        static let silkscreenLarge = SwiftUI.Font.system(size: 13, weight: .semibold, design: .rounded)

        static let caption = SwiftUI.Font.system(size: 10, weight: .regular)
        static let label = SwiftUI.Font.system(size: 11, weight: .regular)
        static let body = SwiftUI.Font.system(size: 13, weight: .regular)
        static let bodyEmphasis = SwiftUI.Font.system(size: 13, weight: .medium)
        static let title = SwiftUI.Font.system(size: 17, weight: .semibold, design: .rounded)

        /// Readouts and timings. Monospaced so digits don't shift as they tick.
        static let counter = SwiftUI.Font.system(size: 13, design: .monospaced).monospacedDigit()
        static let counterLarge = SwiftUI.Font.system(size: 26, weight: .medium, design: .monospaced)
            .monospacedDigit()

        static let silkscreenTracking: CGFloat = 0.3
    }

    // MARK: - Spacing

    /// A 4pt grid.
    enum Space {
        static let hair: CGFloat = 2
        static let tight: CGFloat = 4
        static let snug: CGFloat = 8
        static let base: CGFloat = 12
        static let roomy: CGFloat = 16
        static let wide: CGFloat = 24
        static let panel: CGFloat = 32
    }

    // MARK: - Radius

    /// Generous and consistent — glass, not machined edges.
    enum Radius {
        static let none: CGFloat = 0
        static let chip: CGFloat = 6
        static let control: CGFloat = 10
        static let panel: CGFloat = 16
        static let window: CGFloat = 20
    }

    // MARK: - Border

    enum Border {
        static let hairline: CGFloat = 1
        static let seam: CGFloat = 1
        static let bevel: CGFloat = 1
    }

    // MARK: - Elevation

    /// Soft, glowing shadows — depth from light, not from a machined edge.
    enum Shadow {
        static let raised = Spec(color: .black.opacity(0.18), radius: 8, x: 0, y: 2)
        static let pressed = Spec(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
        static let panel = Spec(color: .black.opacity(0.16), radius: 18, x: 0, y: 6)
        static let window = Spec(color: .black.opacity(0.35), radius: 40, x: 0, y: 14)

        struct Spec {
            let color: SwiftUI.Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
    }

    // MARK: - Motion

    enum Motion {
        static let press = Animation.easeOut(duration: 0.08)
        static let release = Animation.spring(response: 0.3, dampingFraction: 0.7)
        static let panel = Animation.easeInOut(duration: 0.2)
        static let lamp = Animation.easeOut(duration: 0.12)
    }
}

// MARK: - Hex helpers

private extension SwiftUI.Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
