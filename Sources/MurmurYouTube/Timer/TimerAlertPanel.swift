import AppKit
import SwiftUI

/// The "your timer is done" popup — shown centered on screen, ringing continuously (see
/// `Sounds.startAlarmLoop`) until "Wyłącz" is pressed. Deliberately doesn't auto-dismiss or
/// hide on losing key: the whole point of an alarm is that it keeps demanding attention until
/// you actually acknowledge it, unlike the quick-entry popup it's styled to match.
@MainActor
final class TimerAlertPanel: NSPanel {
    private weak var controller: TimerController?

    static let size = CGSize(width: 340, height: 190)

    init(controller: TimerController) {
        self.controller = controller
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        contentView = NSHostingView(rootView: TimerAlertView(controller: controller))

        // See `ClipboardPanel` — clips the window's own layer to the same radius the SwiftUI
        // glass shape uses, so nothing the glass material renders can peek past it as a
        // second corner.
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = PanelStyle.cornerRadius
        contentView?.layer?.masksToBounds = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let visible = screen?.visibleFrame {
            setFrameOrigin(NSPoint(
                x: visible.midX - Self.size.width / 2,
                y: visible.midY - Self.size.height / 2 + visible.height * 0.1
            ))
        }
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
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

private struct TimerAlertView: View {
    @Bindable var controller: TimerController
    private let style = PanelStyle(native: true)

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: controller.firedEntries.contains { $0.isAlarm } ? "alarm.fill" : "timer")
                .font(.system(size: 32))
                .foregroundStyle(style.accent)

            VStack(spacing: 4) {
                ForEach(controller.firedEntries) { entry in
                    Text(entry.label.isEmpty ? "Czas minął" : entry.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(style.primary)
                        .multilineTextAlignment(.center)
                }
            }

            Button {
                controller.dismissFiredAlert()
            } label: {
                Text("Wyłącz").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(22)
        .modifier(GlassIfPanel(isPanel: true, radius: PanelStyle.cornerRadius))
    }
}
