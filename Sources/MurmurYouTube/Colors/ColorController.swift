import AppKit
import Foundation
import Observation

/// The colour picker — a feature of its own, with its own shortcut, history and settings.
/// The system eyedropper picks a pixel; the colour goes to the clipboard in the chosen
/// notation and into `ColorStore`.
@MainActor
@Observable
final class ColorController {
    private let hotkey = HotkeyMonitor()
    /// Held for the duration of a pick — `NSColorSampler` stops working if it's released.
    private var sampler: NSColorSampler?
    private(set) var isPicking = false

    /// - Returns: `false` if the hotkey tap couldn't be installed (missing Accessibility).
    @discardableResult
    func activate() -> Bool {
        hotkey.trigger = .custom(Settings.shared.colorPickerShortcut)
        hotkey.onPress = { [weak self] in self?.pick() }
        return hotkey.start()
    }

    func deactivate() { hotkey.stop() }

    @discardableResult
    func reloadHotkey() -> Bool {
        hotkey.stop()
        return activate()
    }

    func pick() {
        guard sampler == nil else { return }
        let sampler = NSColorSampler()
        self.sampler = sampler
        isPicking = true

        sampler.show { [weak self] color in
            Task { @MainActor in
                guard let self else { return }
                self.sampler = nil
                self.isPicking = false
                guard let color else { return }

                ColorStore.shared.add(hex: ColorTools.hex(color))
                self.copy(color, as: Settings.shared.colorFormat)
                Sounds.playEnd()
            }
        }
    }

    /// Puts a colour on the clipboard in the given notation. Adopted by the clipboard monitor
    /// so a pick doesn't also land in the clipboard history — colours have their own.
    func copy(_ color: NSColor, as format: ColorFormat) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(ColorTools.format(color, as: format), forType: .string)
        ClipboardMonitor.shared.adopt()
    }
}
