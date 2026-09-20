import AppKit
import ApplicationServices
import Foundation

/// Puts grabbed text on the clipboard and, optionally, into whatever field currently has
/// keyboard focus. A distinct type from dictation's `TextInjector` on purpose — the
/// contracts are opposite defaults: dictation always tries to land the words in a field and
/// only falls back to the clipboard when there's nowhere to type; a grab is a clipboard
/// operation first ("it's on your clipboard, paste it where you want") with auto-paste as
/// opt-in on top, matching GrabText's own contract.
@MainActor
enum GrabTextInjector {
    static func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Only called when `Settings.grabAutoPaste` is on. The text must already be on the
    /// clipboard via `copyToClipboard` — the pasteboard fallback below reads it back from
    /// there rather than being handed the string twice.
    static func pasteIntoFocusedField(_ text: String) {
        guard !text.isEmpty else { return }

        switch insertViaAccessibility(text) {
        case .inserted:
            Log.inject.info("inserted via AX (\(text.count) chars)")
        case .unverified(let reason):
            Log.inject.info("AX insert not verified (\(reason, privacy: .public)) — pasting")
            pasteViaPasteboard(text)
        case .noTarget:
            // Nothing focused — the text is already on the clipboard from
            // `copyToClipboard`, so there's nothing further to do.
            Log.inject.info("no focused field — left on clipboard (\(text.count) chars)")
        }
    }

    private enum AXOutcome {
        case inserted
        case unverified(String)
        case noTarget
    }

    private static func insertViaAccessibility(_ text: String) -> AXOutcome {
        let systemWide = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success, let focused else {
            return .noTarget
        }

        let element = unsafeDowncast(focused as AnyObject, to: AXUIElement.self)

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        ) == .success, settable.boolValue else {
            return .unverified("selected text not settable")
        }

        guard let before = selectedRange(of: element) else {
            return .unverified("no readable selection range")
        }

        guard AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success else {
            return .unverified("set attribute failed")
        }

        guard let after = selectedRange(of: element) else {
            return .unverified("selection range unreadable after write")
        }

        let unchanged = after.location == before.location && after.length == before.length
        guard !unchanged else {
            return .unverified("selection unmoved at \(before.location)")
        }

        return .inserted
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success, let value else { return nil }

        let axValue = unsafeDowncast(value as AnyObject, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    /// The pasteboard already holds `text` (set by `copyToClipboard` before this runs), so
    /// this only needs to send ⌘V — no save/restore dance, since leaving the grabbed text
    /// on the clipboard afterward is the whole point, not a side effect to undo.
    private static func pasteViaPasteboard(_ text: String) {
        postCommandV()
        Log.inject.info("pasted (\(text.count) chars)")
    }

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        let vKey: CGKeyCode = 9 // kVK_ANSI_V

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
