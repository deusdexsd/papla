import AppKit
import Foundation

/// Rewrites long dashes in whatever is on the clipboard at the instant you press ⌘V — so a
/// plain ⌘C stays a plain copy, and only the paste is modified.
///
/// A default (non-listen-only) event tap runs *synchronously before* the keystroke reaches the
/// frontmost app, which is what makes this work: the pasteboard is swapped for the corrected
/// version, the ⌘V is passed through untouched, the app reads the corrected text, and shortly
/// afterwards the original clipboard is put back. Only armed while the setting is on.
@MainActor
final class PasteInterceptor {
    static let shared = PasteInterceptor()

    /// Stamped on ⌘V events Papla posts itself (history panel, dictation fallback) so they're
    /// not processed twice — and so the dictation paste's own clipboard restore isn't undone.
    nonisolated static let ownEventMarker: Int64 = 0x5041_504C

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<PasteInterceptor>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    MainActor.assumeIsolated { interceptor.reenable() }
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let marker = event.getIntegerValueField(.eventSourceUserData)
                let flags = event.flags
                // 9 = V. ⌘V and ⌘⇧V; not ⌃/⌥ variants (paste-and-match-style etc.).
                if type == .keyDown, keyCode == 9, flags.contains(.maskCommand),
                   !flags.contains(.maskControl), !flags.contains(.maskAlternate),
                   marker != PasteInterceptor.ownEventMarker {
                    MainActor.assumeIsolated { interceptor.straightenPasteboard() }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("paste interceptor: tapCreate failed — Accessibility permission missing?")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    private func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Swaps the pasteboard for a corrected copy, then restores the original once the paste
    /// has had time to land. Returns without touching anything unless the clipboard is a
    /// single text item that actually contains a long dash.
    func straightenPasteboard() {
        guard Settings.shared.pasteStraightenDashes else { return }
        let pasteboard = NSPasteboard.general
        guard let items = pasteboard.pasteboardItems, items.count == 1, let item = items.first else { return }

        let types = item.types
        guard !types.contains(.fileURL),
              !types.contains(.init("org.nspasteboard.ConcealedType")),
              let text = item.string(forType: .string),
              DashTools.containsLongDash(text)
        else { return }

        var original: [NSPasteboard.PasteboardType: Data] = [:]
        for type in types {
            if let data = item.data(forType: type) { original[type] = data }
        }

        let corrected = NSPasteboardItem()
        for (type, data) in original {
            corrected.setData(DashTools.straighten(data: data, type: type) ?? data, forType: type)
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([corrected])
        ClipboardMonitor.shared.adopt()
        let ourChange = pasteboard.changeCount

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            // Someone copied something new in the meantime — that's the clipboard now.
            guard pasteboard.changeCount == ourChange else { return }
            let restored = NSPasteboardItem()
            for (type, data) in original { restored.setData(data, forType: type) }
            pasteboard.clearContents()
            pasteboard.writeObjects([restored])
            ClipboardMonitor.shared.adopt()
        }
    }
}
