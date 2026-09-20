import AppKit

/// Puts up one dimmed, click-through-proof window per connected screen and lets the user
/// drag a rectangle, screenshot-tool style. Reports back which screen the drag happened on
/// and the rectangle in that screen's own top-left-origin point space — exactly what
/// `ScreenGrabber.capture(screen:rect:)` expects, no further conversion needed.
@MainActor
final class SelectionOverlayController {
    private var windows: [SelectionWindow] = []
    private var escapeMonitor: Any?
    private var completion: ((NSScreen, CGRect)?) -> Void = { _ in }

    func begin(onComplete: @escaping ((NSScreen, CGRect)?) -> Void) {
        completion = onComplete

        windows = NSScreen.screens.map { screen in
            let window = SelectionWindow(screen: screen)
            window.onSelect = { [weak self] rect in
                self?.finish((screen, rect))
            }
            return window
        }
        windows.forEach { $0.orderFrontRegardless() }

        // A single app-wide Escape watcher rather than per-window key handling: whichever
        // of the N overlay windows happens to be key, Escape must cancel the whole flow,
        // not just dismiss the one window under the pointer.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event } // 53 = Escape
            self?.finish(nil)
            return nil
        }

        // Deliberately *not* `NSApp.activate(ignoringOtherApps:)` — that raises every one
        // of this app's windows, not just these overlays, which is exactly how the main
        // window used to jump in front of whatever you were doing the moment you pressed
        // the grab shortcut. `.nonactivatingPanel` plus the `canBecomeKey` override below
        // is the whole point: this panel can take keyboard/mouse focus for the drag and
        // Escape without the app itself becoming active or any other window following it.
        windows.first?.makeKey()
    }

    private func finish(_ result: (NSScreen, CGRect)?) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        for window in windows {
            (window.contentView as? SelectionCanvasView)?.stopAnimating()
            window.orderOut(nil)
        }
        windows = []
        completion(result)
    }
}

/// One borderless, full-screen, always-on-top panel per display. `.screenSaver` level so it
/// sits above everything, including other apps' own fullscreen windows and the menu bar.
private final class SelectionWindow: NSPanel {
    var onSelect: ((CGRect) -> Void)?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false

        let canvas = SelectionCanvasView(frame: NSRect(origin: .zero, size: screen.frame.size))
        canvas.onSelect = { [weak self] rect in self?.onSelect?(rect) }
        contentView = canvas
    }

    override var canBecomeKey: Bool { true }
}

/// The dimmed backdrop plus the drag-to-select rectangle. Coordinates are flipped
/// (top-left origin) so the rect this hands back is already in the same space
/// `ScreenGrabber` and `SCStreamConfiguration.sourceRect` expect — no y-axis math anywhere
/// else in the capture path.
private final class SelectionCanvasView: NSView {
    var onSelect: ((CGRect) -> Void)?

    private var dragStart: CGPoint?
    private var currentRect: CGRect?
    private var animationTimer: Timer?
    private static let cornerRadius: CGFloat = 12

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        NSColor.black.withAlphaComponent(0.38).setFill()
        bounds.fill()

        guard let rect = currentRect, rect.width > 0, rect.height > 0 else { return }
        let radius = min(Self.cornerRadius, min(rect.width, rect.height) / 2)

        // Punch a genuinely clear hole over the selection — this is a transparent overlay
        // window floating above the real desktop, so `.clear` reveals actual screen
        // content underneath rather than any copy of it.
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        ctx.restoreGState()

        drawBorder(rect.insetBy(dx: 0.5, dy: 0.5), radius: radius, in: ctx)
        drawSizeBadge(for: rect)
    }

    /// A plain single-color stroke by default. With the setting on, a genuinely blurred
    /// layer sits *under* the crisp edge and drifts slowly through Papla's three colors —
    /// the edge itself never changes color, only the soft halo behind it does.
    ///
    /// This draws the blur by hand rather than via `CGContext.setShadow`: a shadow is cast
    /// from the alpha of what's actually drawn, and a thin, half-transparent stroke casts
    /// a shadow too faint to see — which is exactly why the first attempt at this produced
    /// no visible glow at all. Several passes of the same path, each wider and fainter than
    /// the last, approximate a soft gaussian falloff directly — cheap enough to redraw
    /// 30×/second, no image filter needed for something this small.
    private func drawBorder(_ rect: NSRect, radius: CGFloat, in ctx: CGContext) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        guard MainActor.assumeIsolated({ Settings.shared.grabAnimatedSelectionGlow }) else {
            NSColor.brandAccent.setStroke()
            path.lineWidth = 1.5
            path.stroke()
            return
        }

        let glow = Self.animatedAccent(at: Date().timeIntervalSinceReferenceDate)
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        for pass in Self.glowPasses {
            glow.withAlphaComponent(pass.alpha).setStroke()
            path.lineWidth = pass.width
            path.stroke()
        }
        ctx.restoreGState()

        // The crisp edge, drawn last and on top, steady in the primary accent regardless
        // of what the glow behind it is doing.
        NSColor.brandAccent.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    /// Widest/faintest first, narrowest/strongest last — the layering that reads as a
    /// falloff instead of a set of concentric rings.
    private static let glowPasses: [(width: CGFloat, alpha: CGFloat)] = [
        (22, 0.05), (16, 0.08), (11, 0.13), (7, 0.20), (4, 0.30),
    ]

    /// Linear drift through the three accent colors, one full loop every 12 seconds — slow
    /// enough to read as an ambient breathing glow rather than something visibly cycling.
    private static func animatedAccent(at time: TimeInterval) -> NSColor {
        MainActor.assumeIsolated {
            let colors = [Settings.shared.accentPrimary, Settings.shared.accentSecondary, Settings.shared.accentTertiary]
            let cycleSeconds = 12.0
            let phase = (time.truncatingRemainder(dividingBy: cycleSeconds)) / cycleSeconds * Double(colors.count)
            let index = Int(phase) % colors.count
            let next = (index + 1) % colors.count
            let fraction = phase - Double(Int(phase))
            let a = colors[index]
            let b = colors[next]
            return NSColor(
                srgbRed: CGFloat(a.r + (b.r - a.r) * fraction),
                green: CGFloat(a.g + (b.g - a.g) * fraction),
                blue: CGFloat(a.b + (b.b - a.b) * fraction),
                alpha: 1
            )
        }
    }

    private func drawSizeBadge(for rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let padding: CGFloat = 6
        let badgeSize = CGSize(width: size.width + padding * 2, height: size.height + padding)

        // Sits just below the selection's bottom edge, clamped so it never runs off the
        // bottom of the screen for a selection dragged all the way down.
        var origin = CGPoint(x: rect.minX, y: rect.maxY + 6)
        if origin.y + badgeSize.height > bounds.maxY {
            origin.y = rect.maxY - badgeSize.height - 6
        }

        let badgeRect = CGRect(origin: origin, size: badgeSize)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 5, yRadius: 5).fill()
        text.draw(
            at: CGPoint(x: badgeRect.minX + padding, y: badgeRect.minY + padding / 2),
            withAttributes: attributes
        )
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        currentRect = CGRect(origin: point, size: .zero)
        needsDisplay = true
        startAnimatingIfNeeded()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        currentRect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        stopAnimating()
        guard let rect = currentRect, rect.width >= 4, rect.height >= 4 else { return }
        onSelect?(rect)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    /// A `Timer` is the only way to get repeated redraws for a color that drifts even while
    /// the mouse itself isn't moving — `draw(_:)` otherwise only runs when something marks
    /// the view dirty. Started on `mouseDown`, stopped on `mouseUp` *and* from
    /// `SelectionOverlayController.finish()` (the Escape-cancel path never reaches
    /// `mouseUp` at all) — a `Timer` on the run loop is kept alive by the run loop itself,
    /// not by this view, so leaving either path unhandled would leave it ticking forever.
    private func startAnimatingIfNeeded() {
        guard MainActor.assumeIsolated({ Settings.shared.grabAnimatedSelectionGlow }) else { return }
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        }
    }

    func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

private extension NSColor {
    /// Reads the user's chosen accent color straight from `Settings` — the same one the
    /// orb uses — rather than a fixed literal, so a custom color in Ustawienia shows up
    /// here too. `draw(_:)` runs on the main thread but isn't itself `@MainActor`-checked,
    /// so this hops there explicitly rather than asserting isolation.
    static var brandAccent: NSColor {
        MainActor.assumeIsolated {
            let rgb = Settings.shared.accentPrimary
            return NSColor(srgbRed: CGFloat(rgb.r), green: CGFloat(rgb.g), blue: CGFloat(rgb.b), alpha: 1)
        }
    }
}
