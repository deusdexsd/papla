import Foundation
import Observation

extension Notification.Name {
    /// Posted by anything that wants Papla's main window on screen (the search panel's gear).
    /// Handled where the SwiftUI `openWindow` action lives — the menu bar icon.
    static let openPaplaWindow = Notification.Name("ai.pivotstudio.papla.openWindow")
    /// Posted by the clipboard search panel's timer badge — handled by `TimerController`,
    /// which owns the actual popup. Decoupled the same way as `openPaplaWindow` rather than
    /// wiring the two controllers to each other directly.
    static let openTimerPanel = Notification.Name("ai.pivotstudio.papla.openTimerPanel")
}

/// Carries "open the window on this section" from wherever the request came from to
/// `MainWindow`, which may not even exist yet when the request is made.
@MainActor
@Observable
final class WindowRouter {
    static let shared = WindowRouter()
    var pendingSection: MainWindow.Section?
}
