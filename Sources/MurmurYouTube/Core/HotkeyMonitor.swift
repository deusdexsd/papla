import AppKit
import Carbon.HIToolbox
import Foundation

/// Which modifier key holds the mic open, for a **modifiers-only** trigger (no separate
/// key — the modifier itself is both the press and the release signal). Kept to exactly
/// the right-hand keys plus `fn`: left-hand modifiers are reserved for held-down-elsewhere
/// use (⌘-tab, etc.) without colliding with dictation.
enum PushToTalkKey: String, CaseIterable, Sendable {
    case rightOption
    case fn
    case rightCommand

    var keyCode: Int64 {
        switch self {
        case .rightOption: Int64(kVK_RightOption)   // 61
        case .fn: Int64(kVK_Function)               // 63
        case .rightCommand: Int64(kVK_RightCommand) // 54
        }
    }

    /// Device-*dependent* bit for this specific physical key.
    ///
    /// `CGEventFlags.maskAlternate` is the union mask — it's set whenever *either* Option
    /// key is down. Using it means: hold Left ⌥, tap Right ⌥, and the release is invisible
    /// (the union bit is still set by the left key), so `onRelease` never fires. The mic
    /// stays open, the HUD stays up, and the next press is swallowed too.
    ///
    /// These raw values are the NX_DEVICE* masks from IOKit's event system; they carry the
    /// left/right distinction that the public `CGEventFlags` constants discard.
    var flag: CGEventFlags {
        switch self {
        case .rightOption: CGEventFlags(rawValue: 0x40)   // NX_DEVICERALTKEYMASK
        case .rightCommand: CGEventFlags(rawValue: 0x10)  // NX_DEVICERCMDKEYMASK
        case .fn: .maskSecondaryFn                        // no left/right variant exists
        }
    }

    var displayName: String {
        switch self {
        case .rightOption: "Prawy ⌥"
        case .fn: "fn"
        case .rightCommand: "Prawy ⌘"
        }
    }

    /// Swallowing `fn` would break fn+arrow, fn+delete and the emoji picker, so we let it
    /// through. Dedicated right-hand modifiers are safe to consume.
    var shouldConsumeEvent: Bool { self != .fn }
}

extension Set<PushToTalkKey> {
    /// Display order follows `allCases`, not insertion order, so "Prawy ⌥ + fn" never
    /// reads as "fn + Prawy ⌥" depending on which one you happened to click last.
    var sortedDisplay: String {
        PushToTalkKey.allCases.filter(contains).map(\.displayName).joined(separator: " + ")
    }
}

/// A recorded "modifiers + one key" combo — ⌘⌥[, F13, whatever you actually pressed.
///
/// Deliberately generic on the modifiers (not left/right specific the way `PushToTalkKey`
/// is): the whole reason that distinction matters is the "which physical key do I watch for
/// the release" problem, and once a real, non-modifier key is in the combo, *that* key's own
/// press/release is the signal. Which physical ⌘ was held stops being observable or
/// relevant, exactly like every other app's global hotkey.
struct CustomShortcut: Codable, Equatable, Sendable {
    /// `CGEventFlags.rawValue`, masked down to just command/option/shift/control/fn — a
    /// snapshot taken once, at the moment the key was recorded.
    var modifierFlags: UInt64
    var keyCode: Int64
    /// The character (or a name, for keys that don't produce one) captured directly from
    /// the recording event — already correct for whatever keyboard layout is active,
    /// with no keycode-to-glyph table to keep in sync.
    var keyGlyph: String

    static let relevantFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl, .maskSecondaryFn]

    /// ⌃⌥⌘4 — distinct from macOS's own ⌘⇧3/4/5 screenshot shortcuts and from the ⌘⇧2 most
    /// other text-grab utilities default to, so installing this alongside one doesn't
    /// collide. Freely rebindable in Ustawienia.
    static let defaultGrabShortcut = CustomShortcut(
        modifierFlags: CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue,
        keyCode: Int64(kVK_ANSI_4),
        keyGlyph: "4"
    )

    /// ⌃⌥⌘V — open the clipboard history.
    static let defaultClipboardShortcut = CustomShortcut(
        modifierFlags: CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue,
        keyCode: Int64(kVK_ANSI_V),
        keyGlyph: "V"
    )

    /// ⌃⌥⌘C — the colour picker.
    static let defaultColorPickerShortcut = CustomShortcut(
        modifierFlags: CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue,
        keyCode: Int64(kVK_ANSI_C),
        keyGlyph: "C"
    )

    var displayName: String {
        let flags = CGEventFlags(rawValue: modifierFlags)
        var symbols = ""
        if flags.contains(.maskControl) { symbols += "⌃" }
        if flags.contains(.maskAlternate) { symbols += "⌥" }
        if flags.contains(.maskShift) { symbols += "⇧" }
        if flags.contains(.maskCommand) { symbols += "⌘" }
        if flags.contains(.maskSecondaryFn) { symbols += "fn+" }
        return symbols + keyGlyph.uppercased()
    }
}

/// Listens for the next key the user presses — anywhere in this app's own windows — and
/// reports it back as a `CustomShortcut`. This is a *local* event monitor, not a
/// `CGEventTap`: recording only ever happens while the Settings window has focus, so it
/// needs no Accessibility permission and can't accidentally capture a keystroke typed into
/// another app.
///
/// **One recording at a time, and it always cleans up after itself.** The first version left
/// its monitor installed after a shortcut was captured (callers only forgot their token), so
/// the very first shortcut ever recorded — dictation's — kept swallowing every later
/// keystroke and re-assigning itself, and no other shortcut could ever be changed. Now the
/// monitor removes itself on capture and on cancel, and starting a new recording cancels the
/// previous one.
@MainActor
enum ShortcutRecorder {
    private static var monitor: Any?
    private static var currentCancel: (() -> Void)?

    /// True while a recording is in progress. The global hotkey taps stand down during it —
    /// otherwise pressing an already-assigned combination to re-record it would trigger
    /// that feature instead of being captured.
    static var isActive: Bool { monitor != nil }

    /// F1…F20 may be bound on their own; anything else needs a modifier, or a bare letter
    /// would become a global hotkey that eats that letter everywhere on the system.
    private static let functionKeyCodes: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    /// - Returns: an opaque token; pass it to `stop(_:)` to abandon the recording early
    ///   (the view disappearing). Capturing or cancelling stops it automatically.
    static func start(
        onCapture: @escaping (CustomShortcut) -> Void,
        onCancel: @escaping () -> Void
    ) -> Any? {
        cancelCurrent()
        currentCancel = onCancel

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Escape always cancels rather than becoming the shortcut — it's needed as an
            // escape hatch, and nobody wants it as a push-to-talk key anyway.
            guard event.keyCode != 53 else {
                finish()
                onCancel()
                return nil
            }

            let flags = cgFlags(from: event.modifierFlags)
            let hasModifier = !flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty
            guard hasModifier || functionKeyCodes.contains(event.keyCode) else {
                NSSound.beep()
                return nil // keep listening — this wasn't a usable shortcut
            }

            let shortcut = CustomShortcut(
                modifierFlags: flags.rawValue,
                keyCode: Int64(event.keyCode),
                keyGlyph: glyph(for: event)
            )
            finish()
            onCapture(shortcut)
            return nil // swallow — this keystroke is being recorded, not typed anywhere
        }
        return monitor
    }

    static func stop(_ token: Any?) {
        guard token != nil else { return }
        finish()
    }

    private static func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        currentCancel = nil
    }

    /// Abandons a recording that's still running so its owner can reset its UI.
    private static func cancelCurrent() {
        guard monitor != nil else { return }
        let cancel = currentCancel
        finish()
        cancel?()
    }

    private static func cgFlags(from ns: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if ns.contains(.command) { result.insert(.maskCommand) }
        if ns.contains(.option) { result.insert(.maskAlternate) }
        if ns.contains(.shift) { result.insert(.maskShift) }
        if ns.contains(.control) { result.insert(.maskControl) }
        if ns.contains(.function) { result.insert(.maskSecondaryFn) }
        return result
    }

    /// Named keys first (space, arrows, function row — `charactersIgnoringModifiers` is
    /// empty or unhelpful for these); everything else falls back to the actual character
    /// the layout produces, so "[" reads as "[" regardless of keyboard layout.
    private static func glyph(for event: NSEvent) -> String {
        let named: [UInt16: String] = [
            49: "Space", 48: "Tab", 36: "⏎", 51: "⌫", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let name = named[event.keyCode] { return name }
        let chars = event.charactersIgnoringModifiers ?? ""
        return chars.isEmpty ? "Klawisz \(event.keyCode)" : chars
    }
}

/// Watches for either a held modifier combo or a recorded custom shortcut using a
/// `CGEventTap`.
///
/// A tap is required — rather than `NSEvent.addGlobalMonitor` — because `fn` and left/right
/// modifier discrimination don't surface through the higher-level APIs, and because a
/// global monitor can observe but not *consume* an event (the keystroke would still reach
/// whatever app has focus). This needs Accessibility permission; without it
/// `CGEvent.tapCreate` returns nil.
@MainActor
final class HotkeyMonitor {
    /// What counts as "pressed". `.modifiersOnly` watches `flagsChanged` and needs every
    /// key in the set held at once; `.custom` watches ordinary key up/down for one specific
    /// key, gated on the modifiers recorded alongside it.
    enum TriggerSpec {
        case modifiersOnly(Set<PushToTalkKey>)
        case custom(CustomShortcut)
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// For `.modifiersOnly`: whether every key in the set was down as of the last event.
    /// For `.custom`: whether the recorded key is currently down.
    private var isComboActive = false

    var trigger: TriggerSpec = .modifiersOnly([.rightOption])
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    /// - Returns: `false` if the tap couldn't be created — almost always missing Accessibility permission.
    @discardableResult
    func start() -> Bool {
        stop()
        if case .modifiersOnly(let keys) = trigger, keys.isEmpty {
            Log.hotkey.error("no trigger keys configured — refusing to start")
            return false
        }

        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                // CGEvent isn't Sendable, so pull out the plain values before crossing into
                // actor-isolated code. The tap was added to the main run loop, so this
                // callback genuinely does run on the main thread.
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                let flags = event.flags
                let consume = MainActor.assumeIsolated {
                    monitor.handle(type: type, keyCode: keyCode, flags: flags, isRepeat: isRepeat)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("tapCreate failed — Accessibility permission missing?")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Log.hotkey.info("listening for \(self.triggerDescription)")
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isComboActive = false
    }

    private var triggerDescription: String {
        switch trigger {
        case .modifiersOnly(let keys): keys.sortedDisplay
        case .custom(let shortcut): shortcut.displayName
        }
    }

    // MARK: - Tap callback

    /// - Returns: `true` if the event should be swallowed rather than passed along.
    private func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        // The system disables a tap that runs too slowly or is interrupted; re-arm it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        // While a shortcut is being recorded in Ustawienia, every trigger stands down so the
        // combination reaches the recorder instead of firing whatever it's currently bound to.
        if ShortcutRecorder.isActive {
            isComboActive = false
            return false
        }

        switch trigger {
        case .modifiersOnly(let keys):
            return handleModifiersOnly(keys: keys, type: type, keyCode: keyCode, flags: flags)
        case .custom(let shortcut):
            return handleCustom(shortcut: shortcut, type: type, keyCode: keyCode, flags: flags, isRepeat: isRepeat)
        }
    }

    private func handleModifiersOnly(keys: Set<PushToTalkKey>, type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard type == .flagsChanged else { return false }

        // Only a key that's actually part of our combo can start/stop it or get consumed —
        // an unrelated modifier (Shift, Control, the *left*-hand Option) must pass straight
        // through untouched.
        guard let changedKey = keys.first(where: { $0.keyCode == keyCode }) else { return false }

        // Recomputed from the full current flag state rather than incrementally: with a
        // chord of 2-3 keys, "is the combo active" only ever means "are all of them down
        // right now", regardless of which one just changed.
        let nowActive = keys.allSatisfy { flags.contains($0.flag) }
        if nowActive != isComboActive {
            isComboActive = nowActive
            if nowActive { onPress?() } else { onRelease?() }
        }

        return changedKey.shouldConsumeEvent
    }

    private func handleCustom(shortcut: CustomShortcut, type: CGEventType, keyCode: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        guard keyCode == shortcut.keyCode else { return false }

        switch type {
        case .keyDown:
            // The modifier check is a gate evaluated once, here — not a running condition.
            // Typing an ordinary "[" without the recorded modifiers must be untouched, so a
            // mismatch means "not our event" and passes straight through.
            let relevant = (flags.rawValue & CustomShortcut.relevantFlags.rawValue)
            guard relevant == shortcut.modifierFlags else { return false }
            // Key repeat re-sends `.keyDown` for as long as the key is held; only the first
            // one is a press. Still consumed — letting repeats through would type the
            // character into whatever has focus once the modifiers no longer match by
            // coincidence.
            guard !isRepeat else { return true }
            guard !isComboActive else { return true }
            isComboActive = true
            onPress?()
            return true

        case .keyUp:
            // Not ours to swallow unless we're the one who started it — an ordinary release
            // of the same physical key (typed without the modifier gate) must pass through.
            guard isComboActive else { return false }
            isComboActive = false
            onRelease?()
            return true

        default:
            return false
        }
    }
}
