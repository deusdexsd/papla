import AppKit
import SwiftUI

/// The floating panel while a grab is processing — same shape as dictation's `HUDPanel`
/// (non-activating, never key, parked against `Settings.hudPosition`/`hudMargin`), a
/// separate instance because it's driven by a separate controller and can in principle be
/// on screen at a different moment than dictation's.
@MainActor
final class GrabHUDPanel: NSPanel {
    init(controller: GrabController) {
        super.init(
            contentRect: NSRect(origin: .zero, size: GrabHUDView.size),
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

        contentView = NSHostingView(rootView: GrabHUDView(controller: controller))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

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
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
    }
}
