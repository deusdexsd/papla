import AppKit
import SwiftUI

/// The floating search window for the clipboard history.
///
/// Like every other Papla panel it's `.nonactivatingPanel`, so opening it never makes Papla
/// the active app — the app you were typing in stays active underneath, which is exactly
/// what lets "Wklej" send ⌘V back to it afterwards. Unlike the HUD it *does* become key,
/// because the search field needs keystrokes.
@MainActor
final class ClipboardPanel: NSPanel {
    private weak var controller: ClipboardController?

    static let size = CGSize(width: 680, height: 560)

    init(controller: ClipboardController) {
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

        appearance = Settings.shared.clipboardAppearance.nsAppearance
        contentView = NSHostingView(rootView: ClipboardView(controller: controller, isPanel: true))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Clicking anywhere else closes it, like any popup — and it keeps the panel from
    /// lingering on screen with a search field nobody is typing into.
    override func resignKey() {
        super.resignKey()
        controller?.hidePanel()
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.hidePanel()
    }

    /// Centered on the screen the pointer is on, a little above the middle.
    func present() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main ?? NSScreen.screens.first
        if let visible = screen?.visibleFrame {
            setFrameOrigin(NSPoint(
                x: visible.midX - Self.size.width / 2,
                y: visible.midY - Self.size.height / 2 + visible.height * 0.06
            ))
        }
        appearance = Settings.shared.clipboardAppearance.nsAppearance
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
