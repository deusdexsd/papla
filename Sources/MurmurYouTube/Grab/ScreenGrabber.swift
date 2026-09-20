import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenGrabberError: Error, LocalizedError {
    case noScreenRecordingAccess
    case displayNotFound
    case emptyRegion

    var errorDescription: String? {
        switch self {
        case .noScreenRecordingAccess:
            "Brak uprawnienia Nagrywanie ekranu. Włącz je w Ustawieniach systemowych."
        case .displayNotFound:
            "Nie udało się znaleźć wybranego ekranu."
        case .emptyRegion:
            "Zaznaczony obszar jest zbyt mały."
        }
    }
}

/// Captures exactly one screen region as a `CGImage`, at full backing-store resolution.
///
/// Built on `ScreenCaptureKit`'s `SCScreenshotManager` rather than the older
/// `CGWindowListCreateImage` — the legacy call still works, but it's the one Apple has
/// been telling developers to move off since macOS 14, and there's no upside to starting a
/// new project on it.
@MainActor
enum ScreenGrabber {
    /// - Parameters:
    ///   - screen: the `NSScreen` the selection was drawn on.
    ///   - rect: the selection, in that screen's own local point space, **origin
    ///     top-left** (i.e. already flipped from AppKit's bottom-left view coordinates —
    ///     see `SelectionCanvasView`).
    static func capture(screen: NSScreen, rect: CGRect) async throws -> CGImage {
        guard rect.width >= 4, rect.height >= 4 else { throw ScreenGrabberError.emptyRegion }
        guard Permissions.hasScreenRecording else { throw ScreenGrabberError.noScreenRecordingAccess }

        guard let screenNumber = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? CGDirectDisplayID else {
            throw ScreenGrabberError.displayNotFound
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == screenNumber }) else {
            throw ScreenGrabberError.displayNotFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let configuration = SCStreamConfiguration()
        // `sourceRect` crops to the region, in points, within the filter's own coordinate
        // space (top-left origin, matching a plain `SCDisplay`'s bounds). Rendering at the
        // screen's backing scale — not just the point size — matters here specifically:
        // diacritics are a handful of extra pixels above a letter, and undersampling them
        // is its own way to lose "ą" to "a" before Vision even runs.
        configuration.sourceRect = rect
        configuration.width = Int(rect.width * screen.backingScaleFactor)
        configuration.height = Int(rect.height * screen.backingScaleFactor)
        configuration.showsCursor = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// Captures an entire display at full resolution — the menu bar's "Chwyć cały ekran",
    /// for a source with no discrete text region worth dragging a box around.
    static func captureFullScreen(_ screen: NSScreen) async throws -> CGImage {
        let rect = CGRect(origin: .zero, size: screen.frame.size)
        return try await capture(screen: screen, rect: rect)
    }
}
