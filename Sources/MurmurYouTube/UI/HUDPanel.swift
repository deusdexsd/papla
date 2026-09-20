import AppKit
import SwiftUI

/// The floating capsule that appears while you hold the key.
///
/// The single most important property here is that this panel **never becomes key**.
/// If it did, the user's text field would lose focus and `TextInjector` would have
/// nothing to insert into. Hence `.nonactivatingPanel` plus `canBecomeKey == false`.
@MainActor
final class HUDPanel: NSPanel {
    init(controller: DictationController) {
        super.init(
            contentRect: NSRect(origin: .zero, size: HUDView.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = true

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        contentView = NSHostingView(rootView: HUDView(controller: controller))
        HUDPreview.panel = self
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Parks the panel against whichever screen edge `Settings.hudPosition` names, offset
    /// by `Settings.hudMargin` from that edge — both configurable in Ustawienia, since
    /// "bottom, centered" isn't the right spot on every setup (a second monitor, a Dock
    /// that lives on the side, a habit of watching the top of the screen instead).
    ///
    /// `NSScreen.main` is the screen with the *key window* — and an accessory app with a
    /// non-activating panel never has one, so it can be nil. Falling back to `screens.first`
    /// keeps the HUD on-screen instead of stranding it at the origin.
    func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            Log.app.error("no screen available to position HUD")
            return
        }
        let visible = screen.visibleFrame
        let size = frame.size
        let margin = Settings.shared.hudMargin

        let origin: NSPoint
        switch Settings.shared.hudPosition {
        case .bottom:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + margin)
        case .top:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - margin)
        case .left:
            origin = NSPoint(x: visible.minX + margin, y: visible.midY - size.height / 2)
        case .right:
            origin = NSPoint(x: visible.maxX - size.width - margin, y: visible.midY - size.height / 2)
        }
        setFrameOrigin(origin)
    }

    func present() {
        // Every active state change (starting → listening → finishing) calls this. Without
        // the early exit the panel would reset to alpha 0 and re-fade on each one, which
        // reads as a flicker mid-utterance.
        guard !isVisible || alphaValue < 1 else { return }

        reposition()
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // AppKit always calls this on the main thread.
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
    }

    /// Shows the orb at full opacity regardless of `controller.state` — used only while
    /// Ustawienia's position picker is on screen, so moving the edge/margin controls is
    /// immediately visible instead of something you find out about on the next dictation.
    func presentPreview() {
        reposition()
        alphaValue = 1
        orderFrontRegardless()
    }

    func dismissPreview() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
    }
}

/// A weak handle to the live `HUDPanel`, reachable from anywhere without threading the
/// instance through every view — specifically so `SettingsContent`'s position picker can
/// preview it without depending on `AppDelegate`.
@MainActor
enum HUDPreview {
    static weak var panel: HUDPanel?

    static func show() { panel?.presentPreview() }
    static func hide() { panel?.dismissPreview() }
    static func update() {
        guard let panel, panel.alphaValue > 0 else { return }
        panel.reposition()
    }
}
