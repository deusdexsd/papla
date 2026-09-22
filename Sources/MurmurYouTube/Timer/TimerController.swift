import AppKit
import Foundation
import Observation

/// Minutnik — a feature of its own, with its own shortcut, popup and history, exactly like
/// grab-text/schowek/colour picker each are. The shortcut opens a small floating quick-entry
/// panel; `TimerStore` owns what's actually running.
@MainActor
@Observable
final class TimerController {
    private let hotkey = HotkeyMonitor()
    private var panel: TimerPanel?
    private(set) var isPanelVisible = false

    init() {
        observeOpenRequests()
    }

    /// - Returns: `false` if the hotkey tap couldn't be installed (missing Accessibility).
    @discardableResult
    func activate() -> Bool {
        hotkey.trigger = .custom(Settings.shared.timerShortcut)
        hotkey.onPress = { [weak self] in self?.togglePanel() }
        return hotkey.start()
    }

    /// The clipboard search panel's timer badge asks for the popup this way, decoupled from
    /// holding a direct reference to `ClipboardController` — see `.openTimerPanel`.
    private func observeOpenRequests() {
        NotificationCenter.default.addObserver(forName: .openTimerPanel, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showPanel() }
        }
    }

    func deactivate() { hotkey.stop() }

    @discardableResult
    func reloadHotkey() -> Bool {
        hotkey.stop()
        return activate()
    }

    func togglePanel() { isPanelVisible ? hidePanel() : showPanel() }

    func showPanel() {
        if panel == nil { panel = TimerPanel(controller: self) }
        isPanelVisible = true
        panel?.present()
    }

    func hidePanel() {
        guard isPanelVisible else { return }
        isPanelVisible = false
        panel?.dismiss()
    }
}
