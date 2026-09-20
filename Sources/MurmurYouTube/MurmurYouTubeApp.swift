import AppKit
import SwiftUI

@main
struct MurmurYouTubeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // The main window. A `Window` rather than a `WindowGroup`: this app has one front
        // panel, and letting ⌘N spawn a second copy makes no sense.
        Window("Papla", id: "main") {
            MainWindow(
                controller: delegate.controller,
                grabController: delegate.grabController,
                clipboardController: delegate.clipboardController,
                colorController: delegate.colorController
            )
        }
        .defaultSize(width: 860, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Pokaż plik słownika") {
                    NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
                }
            }
        }

        // Fully qualified: this app has its own `Settings` type, which otherwise shadows
        // SwiftUI's settings scene.
        SwiftUI.Settings {
            SettingsWindow(
                controller: delegate.controller,
                grabController: delegate.grabController,
                clipboardController: delegate.clipboardController,
                colorController: delegate.colorController
            )
        }

        // The only permanent presence: no Dock icon (see `LSUIElement` / `.accessory`
        // below), so this is the sole way back into the app once its window is closed.
        MenuBarExtra {
            MenuContent(
                controller: delegate.controller,
                grabController: delegate.grabController,
                clipboardController: delegate.clipboardController,
                colorController: delegate.colorController,
                openWindow: openWindow
            )
        } label: {
            OrbMenuBarIcon(isActive: delegate.controller.state.isActive || delegate.grabController.state.isBusy)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    let grabController = GrabController()
    let clipboardController = ClipboardController()
    let colorController = ColorController()
    private var hud: HUDPanel?
    private var grabHud: GrabHUDPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Background utility: no Dock icon, no app menu of its own — reached only through
        // the menu bar icon (or the main window, once opened, which still works normally).
        NSApp.setActivationPolicy(.accessory)

        hud = HUDPanel(controller: controller)
        grabHud = GrabHUDPanel(controller: grabController)

        // Evaluated separately on purpose: `||` short-circuits, and a failed dictation tap
        // must not stop the grab and clipboard shortcuts from being armed.
        let armed = [
            controller.activate(), grabController.activate(),
            clipboardController.activate(), colorController.activate(),
        ]
        if armed.contains(false) {
            Permissions.promptForAccessibility()
            // The tap can only be created once the user grants Accessibility, and there's
            // no notification for that — poll until it takes.
            retryActivation()
        }

        // Screen Recording only actually shows its system prompt the first time a capture
        // API is touched, and only once ever per code signature — asking up front means
        // that happens right after launch, when the user is already expecting a
        // permissions dance, rather than silently failing the first real grab.
        if !Permissions.hasScreenRecording {
            Permissions.promptForScreenRecording()
        }

        // Parakeet's models take ~20s to load from disk, and that cost lands on whichever
        // dictation touches them first — so the first hold after every launch would stall
        // with the HUD showing nothing. Warm them in the background instead, but only when
        // they're already downloaded (a cold download has its own explicit menu button).
        if ParakeetModels.isDownloaded {
            Task.detached(priority: .utility) {
                _ = try? await ParakeetModels.shared.manager()
            }
        }

        observeState()
        observeGrabState()
        let readyMessage = "Papla gotowa — przytrzymaj \(Settings.shared.triggerDisplayName), żeby dyktować, "
            + "albo \(Settings.shared.grabShortcut.displayName), żeby chwycić tekst z ekranu"
        Log.app.info("\(readyMessage, privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.deactivate()
        grabController.deactivate()
        clipboardController.deactivate()
        colorController.deactivate()
    }

    /// Shows and hides the HUD in step with the controller's state.
    private func observeState() {
        withObservationTracking {
            _ = controller.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.controller.state.showsHUD {
                    self.hud?.present()
                } else {
                    self.hud?.dismiss()
                }
                self.observeState()
            }
        }
    }

    private func observeGrabState() {
        withObservationTracking {
            _ = grabController.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.grabController.state.showsHUD {
                    self.grabHud?.present()
                } else {
                    self.grabHud?.dismiss()
                }
                self.observeGrabState()
            }
        }
    }

    private func retryActivation() {
        Task { @MainActor in
            while !Permissions.hasAccessibility {
                try? await Task.sleep(for: .seconds(1))
            }
            controller.activate()
            grabController.activate()
            clipboardController.activate()
            colorController.activate()
            Log.app.info("Accessibility granted — hotkeys armed")
        }
    }
}

/// The menu bar glyph — a tiny static take on the same orb, lit while dictating.
private struct OrbMenuBarIcon: View {
    let isActive: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: isActive ? "circle.hexagongrid.fill" : "circle.hexagongrid")
            // The one view that always exists (the menu bar item itself), hence the one place
            // that can act on "open Papla's window" requests from anywhere in the app.
            .onReceive(NotificationCenter.default.publisher(for: .openPaplaWindow)) { _ in
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

private struct MenuContent: View {
    @Bindable var controller: DictationController
    @Bindable var grabController: GrabController
    @Bindable var clipboardController: ClipboardController
    @Bindable var colorController: ColorController
    let openWindow: OpenWindowAction
    @State private var settings = Settings.shared
    @State private var isPreloadingParakeet = false
    @State private var parakeetOnDisk = ParakeetModels.isDownloaded

    private var parakeetStatus: String {
        if isPreloadingParakeet { return "Wczytuję model…" }
        // Reflects what's actually on disk, not just what this menu instance has done.
        return parakeetOnDisk ? "Model mowy zainstalowany ✓" : "Pobierz model mowy…"
    }

    private func preloadParakeet() {
        guard !isPreloadingParakeet else { return }
        isPreloadingParakeet = true
        Task {
            do {
                _ = try await ParakeetModels.shared.manager()
                parakeetOnDisk = ParakeetModels.isDownloaded
            } catch {
                Log.speech.error("Parakeet preload failed: \(error.localizedDescription)")
            }
            isPreloadingParakeet = false
        }
    }

    var body: some View {
        Button("Pokaż Paplę") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Text(settings.triggerMode == .hold
            ? "Przytrzymaj \(settings.triggerDisplayName), żeby dyktować"
            : "Naciśnij \(settings.triggerDisplayName), żeby dyktować — jeszcze raz, żeby skończyć")

        if settings.customShortcut != nil {
            // Nagrywanie własnego skrótu potrzebuje okna z fokusem, nie da się tego zrobić
            // z paska menu — stąd tylko podgląd i możliwość wyczyszczenia.
            Text("Własny skrót: \(settings.triggerDisplayName)")
            Button("Wyczyść własny skrót") {
                settings.customShortcut = nil
                controller.reloadHotkey()
            }
        } else {
            Menu("Klawisze dyktowania") {
                ForEach(PushToTalkKey.allCases, id: \.self) { key in
                    Toggle(key.displayName, isOn: Binding(
                        get: { settings.triggerKeys.contains(key) },
                        set: { isOn in
                            var updated = settings.triggerKeys
                            if isOn {
                                updated.insert(key)
                            } else {
                                guard updated.count > 1 else { return }
                                updated.remove(key)
                            }
                            settings.triggerKeys = updated
                            controller.reloadHotkey()
                        }
                    ))
                }
                Divider()
                Text("Własną kombinację nagrasz w Ustawieniach (⌘,)")
            }
        }

        Picker("Sposób wyzwalania", selection: $settings.triggerMode) {
            ForEach(DictationTriggerMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }

        Toggle("Czyść tekst", isOn: $settings.cleanupEnabled)

        Toggle("Dźwięk", isOn: $settings.soundEnabled)

        Divider()

        Text("Chwytanie tekstu — \(settings.grabShortcut.displayName)")
        Button("Chwyć obszar…") { grabController.beginGrab() }
            .disabled(grabController.state.isBusy)
        Button("Chwyć cały ekran") { grabController.grabFullScreen() }
            .disabled(grabController.state.isBusy)

        Divider()

        Text("Papla (wyszukiwarka) — \(settings.clipboardShortcut.displayName)")
        Button("Otwórz wyszukiwarkę schowka…") { clipboardController.showPanel() }

        Divider()

        Text("Próbnik kolorów — \(settings.colorPickerShortcut.displayName)")
        Button("Wybierz kolor z ekranu") { colorController.pick() }

        Divider()

        // Downloading ~470 MB on the first hold would look like a hang, so offer to do it
        // deliberately instead.
        Button(parakeetStatus) { preloadParakeet() }
            .disabled(isPreloadingParakeet || parakeetOnDisk)


        if !Permissions.hasAccessibility {
            Button("Nadaj uprawnienia: Ułatwienia dostępu…") { Permissions.openAccessibilitySettings() }
        }
        if !Permissions.hasMicrophone {
            Button("Nadaj uprawnienia: Mikrofon…") { Permissions.openMicrophoneSettings() }
        }
        if !Permissions.hasScreenRecording {
            Button("Nadaj uprawnienia: Nagrywanie ekranu…") { Permissions.openScreenRecordingSettings() }
        }

        Button("Zamknij Paplę") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
