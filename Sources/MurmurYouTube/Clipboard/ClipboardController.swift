import AppKit
import Foundation
import Observation

/// The clipboard history and Papla's floating search panel. Owns the global shortcut, the
/// panel, what "copy" and "paste" mean for each kind of item, and the paste-time dash fix.
@MainActor
@Observable
final class ClipboardController {
    private let panelHotkey = HotkeyMonitor()
    private var panel: ClipboardPanel?

    /// Bumped every time the panel is shown, so its SwiftUI content can reset the query and
    /// re-focus the search field without being torn down and rebuilt.
    private(set) var presentation = 0
    private(set) var isPanelVisible = false

    /// True while a "Tłumacz…" action started from the panel is in flight. The panel checks
    /// this before auto-hiding on `resignKey` — translation is async, and selecting it from a
    /// context menu must not make the whole panel disappear before the result comes back.
    var isTranslating = false

    // MARK: - Lifecycle

    /// - Returns: `false` if a tap couldn't be installed (missing Accessibility).
    @discardableResult
    func activate() -> Bool {
        updateMonitoring()

        panelHotkey.trigger = .custom(Settings.shared.clipboardShortcut)
        panelHotkey.onPress = { [weak self] in self?.togglePanel() }
        let hotkeyOK = panelHotkey.start()
        return updatePasteInterceptor() && hotkeyOK
    }

    func deactivate() {
        panelHotkey.stop()
        PasteInterceptor.shared.stop()
        ClipboardMonitor.shared.stop()
    }

    @discardableResult
    func reloadHotkey() -> Bool {
        panelHotkey.stop()
        return activate()
    }

    /// The ⌘V tap only exists while "zamieniaj myślniki przy wklejaniu" is on.
    @discardableResult
    func updatePasteInterceptor() -> Bool {
        if Settings.shared.pasteStraightenDashes {
            return PasteInterceptor.shared.start()
        }
        PasteInterceptor.shared.stop()
        return true
    }

    /// Applies the panel's light/dark/system choice right away, if it has been created.
    func applyAppearance() {
        panel?.appearance = Settings.shared.clipboardAppearance.nsAppearance
    }

    /// Starts or stops recording history in step with the setting.
    func updateMonitoring() {
        if Settings.shared.clipboardEnabled {
            ClipboardMonitor.shared.start()
        } else {
            ClipboardMonitor.shared.stop()
        }
    }

    // MARK: - Panel

    func togglePanel() {
        isPanelVisible ? hidePanel() : showPanel()
    }

    func showPanel() {
        if panel == nil { panel = ClipboardPanel(controller: self) }
        ScreenshotIndex.shared.refresh()
        presentation += 1
        isPanelVisible = true
        panel?.present()
    }

    func hidePanel() {
        guard isPanelVisible else { return }
        isPanelVisible = false
        panel?.dismiss()
    }

    /// The gear in the panel: closes the search and opens Papla's own window on Ustawienia.
    func openSettings() {
        hidePanel()
        WindowRouter.shared.pendingSection = .settings
        NotificationCenter.default.post(name: .openPaplaWindow, object: nil)
    }

    /// The timer badge pinned next to the search field: closes the search and opens
    /// Minutnik's own quick-entry popup.
    func openTimer() {
        hidePanel()
        NotificationCenter.default.post(name: .openTimerPanel, object: nil)
    }

    // MARK: - Items

    /// Puts an item back on the system pasteboard and bumps it to the top of the history.
    func copy(_ item: ClipboardItem) {
        // A colour from the picker's own history: copy it in the current notation, and bump
        // it there — it never enters the clipboard history.
        if item.fromColorPicker == true, let hex = item.colorHex, let color = ColorTools.parse(hex) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(ColorTools.format(color, as: Settings.shared.colorFormat), forType: .string)
            ClipboardMonitor.shared.adopt()
            ColorStore.shared.add(hex: hex)
            return
        }

        // A screenshot or recording: the file goes on the pasteboard as a file, and nothing
        // is added to the clipboard history — the file on disk is already its own record.
        if item.fromScreenshot == true {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects((item.filePaths ?? []).map { URL(fileURLWithPath: $0) as NSURL })
            ClipboardMonitor.shared.adopt()
            return
        }

        // A past dictation: its own record already lives in `RunStore` — copying it out here
        // doesn't also file a duplicate in the clipboard history.
        if item.fromTranscription == true {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(item.text ?? "", forType: .string)
            ClipboardMonitor.shared.adopt()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text, .link, .code, .color, .transcription:
            var text = item.text ?? ""
            if Settings.shared.pasteStraightenDashes, item.kind != .link { text = DashTools.straighten(text) }
            pasteboard.setString(text, forType: .string)
        case .file, .screenshot:
            let urls = (item.filePaths ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            pasteboard.writeObjects(urls)
        case .image:
            // An image that came from files goes back as those files while they still exist
            // (pastes as a file in Finder, uploads in chat apps); otherwise as the picture.
            let paths = item.filePaths ?? []
            if !paths.isEmpty, paths.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) {
                pasteboard.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
            } else if let url = ClipboardStore.shared.imageURL(for: item),
                      let image = NSImage(contentsOf: url) {
                pasteboard.writeObjects([image])
            }
        }
        ClipboardMonitor.shared.adopt()

        var bumped = item
        bumped.date = Date()
        ClipboardStore.shared.add(bumped)
    }

    /// Copies, then sends ⌘V to whatever app was in front — which is still the user's app,
    /// because the panel never activates Papla.
    func paste(_ item: ClipboardItem) {
        hidePanel()
        copy(item)
        Task { @MainActor in
            // Give the panel time to hand key focus back before the keystroke lands.
            try? await Task.sleep(for: .milliseconds(140))
            TextInjector.postCommandV()
        }
    }
}
