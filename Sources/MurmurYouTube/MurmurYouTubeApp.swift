import AppKit
import Combine
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
                colorController: delegate.colorController,
                timerController: delegate.timerController
            )
        }
        .defaultSize(width: 860, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(t("Pokaż plik słownika", "Show dictionary file")) {
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
                colorController: delegate.colorController,
                timerController: delegate.timerController
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
                timerController: delegate.timerController,
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
    let timerController = TimerController()
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
            timerController.activate(),
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
        installStatusItemLeftClick()
        let readyMessage = "Papla gotowa — przytrzymaj \(Settings.shared.triggerDisplayName), żeby dyktować, "
            + "albo \(Settings.shared.grabShortcut.displayName), żeby chwycić tekst z ekranu"
        Log.app.info("\(readyMessage, privacy: .public)")
    }

    /// `MenuBarExtra` gives no hook for telling clicks apart — any click opens its menu. So a
    /// local event monitor watches for a plain left click landing on the status bar window and
    /// turns it into "toggle Papla's window", swallowing it so the menu doesn't also drop down. A
    /// right click (or ctrl-click) is left alone and opens the menu as usual.
    private func installStatusItemLeftClick() {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            guard !event.modifierFlags.contains(.control), let window = event.window,
                  String(describing: type(of: window)).contains("StatusBar")
            else { return event }
            // A second click closes it again — but only if it's actually in front; a window
            // buried behind others should come forward instead of vanishing.
            if let main = NSApp.windows.first(where: { $0.title == "Papla" && !($0 is NSPanel) }),
               main.isVisible, main.isKeyWindow {
                main.close()
            } else {
                NotificationCenter.default.post(name: .openPaplaWindow, object: nil)
            }
            return nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.deactivate()
        grabController.deactivate()
        clipboardController.deactivate()
        colorController.deactivate()
        timerController.deactivate()
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
            timerController.activate()
            Log.app.info("Accessibility granted — hotkeys armed")
        }
    }
}

/// The menu bar glyph — a tiny static take on the same orb, lit while dictating. Optionally
/// grows a live countdown for the soonest running Minutnik, per "Pokazuj minutnik w pasku
/// menu" in Ustawienia — off by default, since most people only care while the search panel
/// (which already shows this) is open.
private struct OrbMenuBarIcon: View {
    let isActive: Bool
    @Environment(\.openWindow) private var openWindow
    @State private var timerStore = TimerStore.shared
    @State private var settings = Settings.shared
    @State private var now = Date()

    // `TimelineView` inside a `MenuBarExtra` label previously froze the app — its
    // per-frame invalidation doesn't play well with how NSStatusItem redraws its custom
    // view. A plain `Timer` publisher ticking a `@State` date is the well-supported way to
    // animate a menu bar label and doesn't touch that code path at all.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: settings.menuBarIconStyle.symbol(active: isActive))
            if settings.showTimerInMenuBar, let next = timerStore.entries.first {
                Text(remaining(next.fireDate)).monospacedDigit()
            }
        }
        .onReceive(ticker) { now = $0 }
        // The one view that always exists (the menu bar item itself), hence the one place
        // that can act on "open Papla's window" requests from anywhere in the app.
        .onReceive(NotificationCenter.default.publisher(for: .openPaplaWindow)) { _ in
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func remaining(_ fireDate: Date) -> String {
        let seconds = max(0, Int(fireDate.timeIntervalSince(now)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private struct MenuContent: View {
    @Bindable var controller: DictationController
    @Bindable var grabController: GrabController
    @Bindable var clipboardController: ClipboardController
    @Bindable var colorController: ColorController
    @Bindable var timerController: TimerController
    let openWindow: OpenWindowAction
    @State private var settings = Settings.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var isPreloadingParakeet = false
    @State private var parakeetOnDisk = ParakeetModels.isDownloaded

    private var parakeetStatus: String {
        if isPreloadingParakeet { return t("Wczytuję model…", "Loading model…") }
        // Reflects what's actually on disk, not just what this menu instance has done.
        return parakeetOnDisk
            ? t("Model mowy zainstalowany ✓", "Speech model installed ✓")
            : t("Pobierz model mowy…", "Download speech model…")
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
        Button(t("Pokaż wyszukiwarkę Papli", "Show Papla search")) {
            clipboardController.showPanel()
        }

        Button(t("Ustawienia Papli", "Papla settings")) {
            WindowRouter.shared.pendingSection = .settings
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Text(settings.triggerMode == .hold
            ? t("Przytrzymaj \(settings.triggerDisplayName), żeby dyktować",
                "Hold \(settings.triggerDisplayName) to dictate")
            : t("Naciśnij \(settings.triggerDisplayName), żeby dyktować — jeszcze raz, żeby skończyć",
                "Press \(settings.triggerDisplayName) to dictate — press again to stop"))

        if settings.customShortcut != nil {
            // Nagrywanie własnego skrótu potrzebuje okna z fokusem, nie da się tego zrobić
            // z paska menu — stąd tylko podgląd i możliwość wyczyszczenia.
            Text(t("Własny skrót: \(settings.triggerDisplayName)", "Custom shortcut: \(settings.triggerDisplayName)"))
            Button(t("Wyczyść własny skrót", "Clear custom shortcut")) {
                settings.customShortcut = nil
                controller.reloadHotkey()
            }
        } else {
            Menu(t("Klawisze dyktowania", "Dictation keys")) {
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
                Text(t("Własną kombinację nagrasz w Ustawieniach (⌘,)", "Record a custom combo in Settings (⌘,)"))
            }
        }

        Picker(t("Sposób wyzwalania", "Trigger mode"), selection: $settings.triggerMode) {
            ForEach(DictationTriggerMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }

        Toggle(t("Czyść tekst", "Clean up text"), isOn: $settings.cleanupEnabled)

        Toggle(t("Dźwięk", "Sound"), isOn: $settings.soundEnabled)

        Toggle(t("Uruchamiaj przy logowaniu", "Launch at login"), isOn: Binding(
            get: { launchAtLogin },
            set: {
                LaunchAtLogin.set($0)
                launchAtLogin = LaunchAtLogin.isEnabled
            }
        ))

        Divider()

        Text(t("Chwytanie tekstu — \(settings.grabShortcut.displayName)", "Text grab — \(settings.grabShortcut.displayName)"))
        Button(t("Chwyć obszar…", "Grab an area…")) { grabController.beginGrab() }
            .disabled(grabController.state.isBusy)
        Button(t("Chwyć cały ekran", "Grab the whole screen")) { grabController.grabFullScreen() }
            .disabled(grabController.state.isBusy)

        Divider()

        Text(t("Papla (wyszukiwarka) — \(settings.clipboardShortcut.displayName)", "Papla (search) — \(settings.clipboardShortcut.displayName)"))
        Button(t("Otwórz wyszukiwarkę schowka…", "Open clipboard search…")) { clipboardController.showPanel() }

        Divider()

        Text(t("Próbnik kolorów — \(settings.colorPickerShortcut.displayName)", "Color picker — \(settings.colorPickerShortcut.displayName)"))
        Button(t("Wybierz kolor z ekranu", "Pick a color from the screen")) { colorController.pick() }

        Divider()

        Text(t("Minutnik — \(settings.timerShortcut.displayName)", "Timer — \(settings.timerShortcut.displayName)"))
        Button(t("Nowy minutnik / budzik…", "New timer / alarm…")) { timerController.showPanel() }

        Divider()

        // Downloading ~470 MB on the first hold would look like a hang, so offer to do it
        // deliberately instead.
        Button(parakeetStatus) { preloadParakeet() }
            .disabled(isPreloadingParakeet || parakeetOnDisk)


        Picker(t("Język", "Language"), selection: $settings.appLanguage) {
            ForEach(AppLanguage.allCases, id: \.self) { language in
                Text(language.displayName).tag(language)
            }
        }

        Divider()

        if !Permissions.hasAccessibility {
            Button(t("Nadaj uprawnienia: Ułatwienia dostępu…", "Grant permission: Accessibility…")) { Permissions.openAccessibilitySettings() }
        }
        if !Permissions.hasMicrophone {
            Button(t("Nadaj uprawnienia: Mikrofon…", "Grant permission: Microphone…")) { Permissions.openMicrophoneSettings() }
        }
        if !Permissions.hasScreenRecording {
            Button(t("Nadaj uprawnienia: Nagrywanie ekranu…", "Grant permission: Screen Recording…")) { Permissions.openScreenRecordingSettings() }
        }

        Button(t("Zamknij Paplę", "Quit Papla")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
