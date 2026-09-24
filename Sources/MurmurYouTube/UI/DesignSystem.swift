import SwiftUI

/// The design system for Papla.
///
/// Direction: the orb — the same glass sphere that's the app icon and the HUD indicator
/// (`SiriOrb` in HUDView.swift). Dark ground, soft glow, one blue/violet/cyan accent family
/// (`Brand`, also in HUDView.swift). No brushed metal, no hardware fasteners, no analog
/// meters; the window should look
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
        static let chassis = native(.windowBackgroundColor)

        /// A grouped panel/card surface, lifted slightly off the chassis.
        static let panel = native(.controlBackgroundColor)

        /// Subtle top-edge highlight on a card — kept as its own token even though it now
        /// resolves the same as `seam`, so `BrushedPanel` doesn't need to change if this ever
        /// needs to diverge again.
        static let panelHighlight = native(.separatorColor)

        /// Bottom-edge shade on a card.
        static let panelShade = native(.separatorColor)

        /// Recessed wells — where lists sit, set into the panel.
        static let well = native(.underPageBackgroundColor)

        /// A readout surface — was "always dark regardless of face" under the old brand look;
        /// now the same native control surface as everything else, so it stops reading as a
        /// separate dark widget dropped into an otherwise light/dark-adaptive window.
        static let deck = native(.controlBackgroundColor)

        /// Button/control surface, one step up from the panel.
        static let cap = native(.controlColor)

        /// A quiet divider — the system's own hairline.
        static let seam = native(.separatorColor)

        // Text
        /// Primary readable text.
        static let ink = native(.labelColor)
        /// Supporting text — timings, counts, secondary rows.
        static let inkSecondary = native(.secondaryLabelColor)
        /// A panel section label. Same family as `inkSecondary`, kept as its own token so a
        /// future change to one doesn't silently drag the other.
        static let silkscreen = native(.secondaryLabelColor)
        /// Text on a readout surface — was fixed near-white for contrast against an
        /// always-dark deck; now `deck` itself is native/adaptive, so this just follows suit.
        static let inkOnDeck = native(.labelColor)

        // Accent — the orb's own palette, reused as the app's only accent family. Left
        // untouched by the native-chrome pass on purpose: this is Papla's own product
        // identity (the dictation HUD/orb), not window chrome, and the search bar it's being
        // matched to doesn't touch it either.
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
        /// Row under the pointer, before selection — the same formula the search bar's own
        /// row hover uses.
        static let hover = native(.labelColor).opacity(0.06)

        // Status — used sparingly, for the dictionary's own signals (on/off, a correction
        // that fired). Not UI chrome.
        static let statusGood = native(.systemGreen)
        static let statusWarning = native(.systemYellow)
        static let statusBad = native(.systemRed)

        // MARK: Face resolution

        private static func native(_ color: NSColor) -> SwiftUI.Color { SwiftUI.Color(nsColor: color) }
        private static func swatch(_ hex: UInt32) -> SwiftUI.Color { SwiftUI.Color(hex: hex) }

        /// Resolves to the light or dark value for the current appearance. Only `record`'s
        /// idle state still uses this — everything that used to be a hand-picked light/dark
        /// pair is a native semantic color now.
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

    /// Plain system type — the same fonts the search bar and Minutnik popup use, dropping the
    /// old tracked-rounded "silkscreen" look so labels read as ordinary macOS UI text rather
    /// than a distinct equipment face.
    enum Font {
        static let silkscreen = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let silkscreenLarge = SwiftUI.Font.system(size: 13, weight: .semibold)

        static let caption = SwiftUI.Font.system(size: 10, weight: .regular)
        static let label = SwiftUI.Font.system(size: 11, weight: .regular)
        static let body = SwiftUI.Font.system(size: 13, weight: .regular)
        static let bodyEmphasis = SwiftUI.Font.system(size: 13, weight: .medium)
        static let title = SwiftUI.Font.system(size: 17, weight: .semibold)

        /// Readouts and timings. Monospaced so digits don't shift as they tick.
        static let counter = SwiftUI.Font.system(size: 13, design: .monospaced).monospacedDigit()
        static let counterLarge = SwiftUI.Font.system(size: 26, weight: .medium, design: .monospaced)
            .monospacedDigit()

        static let silkscreenTracking: CGFloat = 0
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

    /// Subtle — the same restrained depth native macOS controls use, not a "raised hardware
    /// key" look.
    enum Shadow {
        static let raised = Spec(color: .black.opacity(0.10), radius: 3, x: 0, y: 1)
        static let pressed = Spec(color: .black.opacity(0.06), radius: 1, x: 0, y: 0.5)
        static let panel = Spec(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        static let window = Spec(color: .black.opacity(0.20), radius: 24, x: 0, y: 8)

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
