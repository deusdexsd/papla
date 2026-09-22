import AppKit
import SwiftUI

/// The colours a floating panel draws with. Every Papla popup that floats over other apps
/// (clipboard search, Minutnik's quick-entry) shares this so they read as one product: Liquid
/// Glass background, semantic system colours, the user's system accent for selection, and
/// light/dark for free — while the same view embedded in Papla's own window (`native: false`)
/// keeps Papla's own dark "brand" look instead.
@MainActor
struct PanelStyle {
    /// Every floating panel's corner radius, shared so the SwiftUI glass shape and the
    /// window's own AppKit-level layer mask (set in each `NSPanel` subclass) always agree —
    /// a mismatch between the two is exactly what read as a "double corner".
    static let cornerRadius: CGFloat = 26

    let native: Bool

    // Explicit AppKit system colours rather than SwiftUI's hierarchical `.secondary`: they
    // are the same dynamic colours every native window uses and resolve correctly in light,
    // dark and any accent, without depending on the surrounding material.
    var primary: Color { native ? Color(nsColor: .labelColor) : DS.Color.inkOnDeck }
    var secondary: Color { native ? Color(nsColor: .secondaryLabelColor) : DS.Color.inkOnDeck.opacity(0.5) }
    var tertiary: Color { native ? Color(nsColor: .tertiaryLabelColor) : DS.Color.inkOnDeck.opacity(0.3) }
    var hairline: Color { native ? Color(nsColor: .separatorColor) : DS.Color.seam }
    var accent: Color { native ? Color(nsColor: .controlAccentColor) : Brand.accent }
    var tile: Color { native ? Color(nsColor: .quaternaryLabelColor) : Brand.accent.opacity(0.14) }
    var chipOff: Color { native ? Color(nsColor: .quaternaryLabelColor) : DS.Color.inkOnDeck.opacity(0.08) }
}

/// Liquid Glass for a floating panel; nothing for a view embedded in Papla's own window (it
/// sits on Papla's own dark surface there instead). `glassEffect(_:in:)` already shapes *and*
/// clips the content to the given shape on its own — pairing it with a separate `.clipShape`
/// of the same rounded rect was two independent edges drawn on top of each other, which is
/// what read as a "double corner" instead of one clean rounded one.
struct GlassIfPanel: ViewModifier {
    let isPanel: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        if isPanel {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content
        }
    }
}
