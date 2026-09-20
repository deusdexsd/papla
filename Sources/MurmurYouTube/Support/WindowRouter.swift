import Foundation
import Observation

extension Notification.Name {
    /// Posted by anything that wants Papla's main window on screen (the search panel's gear).
    /// Handled where the SwiftUI `openWindow` action lives — the menu bar icon.
    static let openPaplaWindow = Notification.Name("ai.pivotstudio.papla.openWindow")
}

/// Carries "open the window on this section" from wherever the request came from to
/// `MainWindow`, which may not even exist yet when the request is made.
@MainActor
@Observable
final class WindowRouter {
    static let shared = WindowRouter()
    var pendingSection: MainWindow.Section?
}
