import AppKit
import SwiftUI

/// The floating quick-entry popup for Minutnik — same recipe as `ClipboardPanel`:
/// non-activating (so the app you're in stays frontmost underneath) but key (the duration/time
/// field needs keystrokes), centered where the pointer is.
@MainActor
final class TimerPanel: NSPanel {
    private weak var controller: TimerController?

    static let size = CGSize(width: 360, height: 420)

    init(controller: TimerController) {
        self.controller = controller
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        contentView = NSHostingView(rootView: TimerView(controller: controller))

        // See `ClipboardPanel` — clips the window's own layer to the same radius the SwiftUI
        // glass shape uses, so nothing the glass material renders can peek past it as a
        // second corner.
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = PanelStyle.cornerRadius
        contentView?.layer?.masksToBounds = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        controller?.hidePanel()
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.hidePanel()
    }

    func present() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main ?? NSScreen.screens.first
        if let visible = screen?.visibleFrame {
            setFrameOrigin(NSPoint(
                x: visible.midX - Self.size.width / 2,
                y: visible.midY - Self.size.height / 2 + visible.height * 0.06
            ))
        }
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
    }
}
