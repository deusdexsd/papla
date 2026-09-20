import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Papla needs three grants across its two features, and none can be worked around:
/// - **Microphone** — dictation, obviously.
/// - **Accessibility** — both features' `CGEventTap` (hotkeys) and the AX text insert.
/// - **Screen Recording** — chwytanie tekstu, to read pixels off the screen at all.
///
/// None has a programmatic grant path; the OS only shows the prompt (or, for Screen
/// Recording, doesn't reliably show one after the first launch — see
/// `openScreenRecordingSettings`), and the user must toggle it in System Settings. TCC also
/// keys on the code signature, so re-signing the app resets every grant.
@MainActor
enum Permissions {
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    static var hasMicrophone: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system Accessibility prompt if the app isn't yet trusted.
    @discardableResult
    static func promptForAccessibility() -> Bool {
        // Spelled out rather than using `kAXTrustedCheckOptionPrompt`, which imports as a
        // mutable global and so isn't usable from concurrency-checked code.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    /// Shows the system Screen Recording prompt the *first* time only — macOS remembers
    /// the refusal/grant per code signature and won't re-prompt after that, which is why
    /// the menu also offers a direct link into System Settings.
    @discardableResult
    static func promptForScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
