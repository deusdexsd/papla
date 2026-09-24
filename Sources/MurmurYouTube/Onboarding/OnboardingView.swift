import AppKit
import SwiftUI

/// First-run guide: a few steps that explain what Papla does, get the permissions and the
/// speech model out of the way, and let the basics be chosen — then the "co jest co" tour.
/// Every choice is saved the moment it is made, so closing the window halfway loses nothing.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 680),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: OnboardingView { [weak self] startTour in self?.finish(startTour: startTour) }
        )
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(startTour: Bool) {
        Settings.shared.onboardingDone = true
        window?.close()
        window = nil
        if startTour { Self.startTour() }
    }

    /// Closing with the red button counts as "later" — the guide never nags twice.
    func windowWillClose(_ notification: Notification) {
        Settings.shared.onboardingDone = true
        window = nil
    }

    static func startTour() {
        TourState.shared.isPending = true
        NotificationCenter.default.post(name: .openPaplaWindow, object: nil)
    }
}

private struct OnboardingView: View {
    let onFinish: (_ startTour: Bool) -> Void

    @State private var step = 0
    @State private var settings = Settings.shared
    private let count = 6

    @State private var accessibility = Permissions.hasAccessibility
    @State private var microphone = Permissions.hasMicrophone
    @State private var screenRecording = Permissions.hasScreenRecording
    @State private var modelReady = ParakeetModels.isDownloaded
    @State private var isDownloadingModel = false
    @State private var modelError: String?
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            DS.Color.chassis.ignoresSafeArea()
            RadialGradient(
                colors: [Brand.accent.opacity(0.22), .clear],
                center: .top, startRadius: 0, endRadius: 360
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                dots.padding(.top, 34)

                ScrollView {
                    Group {
                        switch step {
                        case 0: language
                        case 1: welcome
                        case 2: dictation
                        case 3: permissions
                        case 4: appearance
                        default: ready
                        }
                    }
                    .padding(.horizontal, 44)
                    .padding(.top, DS.Space.roomy)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                    .id(step)
                    .transition(.opacity)
                }

                footer
            }
        }
        .frame(width: 700, height: 680)
        .animation(DS.Motion.panel, value: step)
        .onReceive(ticker) { _ in
            accessibility = Permissions.hasAccessibility
            microphone = Permissions.hasMicrophone
            screenRecording = Permissions.hasScreenRecording
            modelReady = ParakeetModels.isDownloaded
        }
    }

    // MARK: - Chrome

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == step ? Brand.accent : DS.Color.ink.opacity(index < step ? 0.35 : 0.14))
                    .frame(width: index == step ? 22 : 7, height: 7)
            }
        }
    }

    private var footer: some View {
        HStack {
            if step == 0 {
                Button("Pomiń · Skip") { onFinish(false) }
                    .buttonStyle(.plain).foregroundStyle(DS.Color.inkSecondary)
            } else {
                TransportKey(title: t("Wstecz", "Back")) { step -= 1 }
            }
            Spacer()
            if step == count - 1 {
                Button(t("Bez samouczka", "No tour")) { onFinish(false) }
                    .buttonStyle(.plain).foregroundStyle(DS.Color.inkSecondary)
                    .padding(.trailing, DS.Space.base)
            }
            TransportKey(
                title: step == count - 1 ? t("Zaczynamy", "Let's go") : t("Dalej", "Next"),
                isEngaged: true, engagedColor: Brand.accent
            ) {
                if step == count - 1 { onFinish(true) } else { step += 1 }
            }
        }
        .padding(.horizontal, 44)
        .padding(.vertical, DS.Space.roomy + 2)
    }

    private func header(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        VStack(spacing: DS.Space.snug) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(LinearGradient(colors: [Brand.accent, Brand.accentWarm],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .shadow(color: Brand.accent.opacity(0.4), radius: 14, y: 6)
            Text(title).font(.system(size: 24, weight: .semibold))
            Text(subtitle)
                .font(DS.Font.body).foregroundStyle(DS.Color.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, DS.Space.roomy)
    }

    private func infoRow(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.base) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(color))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.Font.bodyEmphasis)
                Text(text).font(DS.Font.label).foregroundStyle(DS.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.ink.opacity(0.05), in: .rect(cornerRadius: DS.Radius.panel))
    }

    // MARK: - Steps

    /// Always first, and always bilingual — it's the choice that decides which language the
    /// rest of the guide is in.
    private var language: some View {
        VStack(spacing: DS.Space.snug) {
            header("globe", "Język · Language",
                   "Wybierz język aplikacji. Choose the app's language. Możesz to zmienić później w Ustawieniach · You can change it later in Settings.")
            HStack(spacing: DS.Space.snug) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    choice(title: language.displayName, detail: nil, isOn: settings.appLanguage == language) {
                        settings.appLanguage = language
                    }
                }
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: DS.Space.snug) {
            header("waveform.circle.fill", t("Cześć, tu Papla", "Hi, this is Papla"),
                   t("Dyktujesz głosem, przeszukujesz historię schowka, chwytasz tekst z ekranu i ustawiasz minutnik — z paska menu, bez okien.",
                     "You dictate by voice, search your clipboard history, grab text from the screen and set a timer — from the menu bar, no windows."))
            infoRow("lock.shield.fill", .green, t("Wszystko zostaje na Macu", "Everything stays on your Mac"),
                    t("Nagrania i teksty nie opuszczają komputera. Rozpoznawanie mowy działa lokalnie.",
                      "Recordings and text never leave the computer. Speech recognition runs locally."))
            infoRow("hand.raised.fill", .blue, t("Nic nie robię sam", "I don't do anything on my own"),
                    t("Działam tylko wtedy, gdy użyjesz skrótu albo klikniesz. Niczego nie usuwam ani nie wysyłam.",
                      "I only act when you use a shortcut or click. I don't delete or send anything."))
            infoRow("sparkles", .purple, t("Bez AI w tle", "No AI in the background"),
                    t("Emoji i poprawki opierają się na słowniku reguł, a nie na modelu, który coś zgaduje.",
                      "Emoji and corrections come from a fixed rule dictionary, not a model guessing."))
        }
    }

    private var dictation: some View {
        VStack(spacing: DS.Space.snug) {
            header("mic.fill", t("Dyktowanie", "Dictation"),
                   t("Przytrzymaj \(settings.triggerDisplayName) i mów po polsku. Puść — tekst pojawi się tam, gdzie masz kursor.",
                     "Hold \(settings.triggerDisplayName) and speak. Let go — the text appears where your cursor is."))
            infoRow("arrow.triangle.branch", Brand.accent, t("Dyktuj w podróży", "Dictate on the go"),
                    t("Jeśli kursor nie stoi w polu tekstowym, tekst trafia do schowka. Możesz więc chodzić po aplikacjach, oglądać rzeczy i mówić, a na końcu kliknąć w pole i wkleić (⌘V).",
                      "If the cursor isn't in a text field, the text goes to the clipboard. So you can move through apps, look at things and talk, then click into a field and paste (⌘V) at the end."))

            HStack(spacing: DS.Space.snug) {
                ForEach(DictationTriggerMode.allCases, id: \.self) { mode in
                    choice(title: mode.displayName, detail: mode.note, isOn: settings.triggerMode == mode) {
                        settings.triggerMode = mode
                    }
                }
            }
            .padding(.top, DS.Space.snug)

            modelRow
        }
    }

    private var modelRow: some View {
        HStack(spacing: DS.Space.base) {
            Image(systemName: modelReady ? "checkmark.circle.fill" : "arrow.down.circle")
                .font(.system(size: 20))
                .foregroundStyle(modelReady ? DS.Color.statusGood : Brand.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(t("Model mowy (Parakeet v3)", "Speech model (Parakeet v3)")).font(DS.Font.bodyEmphasis)
                Text(modelReady
                    ? t("Pobrany i gotowy.", "Downloaded and ready.")
                    : (modelError ?? t("Jednorazowe pobranie ok. 470 MB. Bez niego dyktowanie nie zadziała.",
                                       "A one-time download of about 470 MB. Dictation won't work without it.")))
                    .font(DS.Font.label).foregroundStyle(DS.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if isDownloadingModel {
                ProgressView().controlSize(.small)
            } else if !modelReady {
                TransportKey(title: t("Pobierz teraz", "Download now"), systemImage: "arrow.down.circle") {
                    downloadModel()
                }
            }
        }
        .padding(DS.Space.base)
        .background(DS.Color.ink.opacity(0.05), in: .rect(cornerRadius: DS.Radius.panel))
    }

    private var permissions: some View {
        VStack(spacing: DS.Space.snug) {
            header("lock.shield.fill", t("Uprawnienia", "Permissions"),
                   t("macOS wymaga trzech zgód. Kliknij przy każdej „Otwórz ustawienia”, włącz Paplę i wróć tutaj — status odświeża się sam.",
                     "macOS requires three permissions. Click “Open settings” for each, switch Papla on and come back — the status refreshes by itself."))
            VStack(spacing: 0) {
                PermissionRowView(title: t("Dostępność", "Accessibility"),
                                  detail: t("Skróty klawiszowe i wpisywanie tekstu.", "Keyboard shortcuts and typing text."),
                                  granted: accessibility, open: PermissionActions.accessibility)
                PermissionRowView(title: t("Mikrofon", "Microphone"),
                                  detail: t("Dyktowanie.", "Dictation."),
                                  granted: microphone) {
                    PermissionActions.microphone { microphone = Permissions.hasMicrophone }
                }
                PermissionRowView(title: t("Nagrywanie ekranu", "Screen Recording"),
                                  detail: t("Chwytanie tekstu z ekranu (OCR).", "Grabbing text from the screen (OCR)."),
                                  granted: screenRecording, open: PermissionActions.screenRecording)
            }
            .padding(DS.Space.base)
            .background(DS.Color.ink.opacity(0.05), in: .rect(cornerRadius: DS.Radius.panel))

            infoRow("info.circle.fill", Brand.accent, t("Po aktualizacji zrób to ponownie", "Do it again after an update"),
                    t("Każda nowa wersja Papli ma nowy podpis, więc macOS zapomina zgody. Wszystko jest też w Ustawienia ▸ ikona kłódki.",
                      "Every new build of Papla has a new signature, so macOS forgets the permissions. It's all also in Settings ▸ the lock icon."))
        }
    }

    private var appearance: some View {
        VStack(spacing: DS.Space.snug) {
            header("paintbrush.pointed.fill", t("Wygląd i start", "Looks and startup"),
                   t("Wybierz ikonę w pasku menu i czy Papla ma wstawać razem z systemem. Wszystko zmienisz później w Ustawieniach.",
                     "Pick the menu bar icon and whether Papla starts with your Mac. You can change it all later in Settings."))

            HStack(spacing: DS.Space.snug) {
                ForEach(MenuBarIconStyle.allCases, id: \.self) { style in
                    let isOn = settings.menuBarIconStyle == style
                    Button { settings.menuBarIconStyle = style } label: {
                        VStack(spacing: 4) {
                            Image(systemName: style.symbol(active: false)).font(.system(size: 20)).frame(height: 24)
                            Text(style.displayName).font(DS.Font.caption)
                        }
                        .foregroundStyle(isOn ? Brand.accent : DS.Color.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Space.snug)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .fill(isOn ? Brand.accent.opacity(0.14) : DS.Color.ink.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .strokeBorder(isOn ? Brand.accent : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            Toggle(isOn: Binding(
                get: { launchAtLogin },
                set: { LaunchAtLogin.set($0); launchAtLogin = LaunchAtLogin.isEnabled }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Uruchamiaj przy logowaniu", "Launch at login")).font(DS.Font.bodyEmphasis)
                    Text(t("Papla wystartuje w tle razem z Twoim kontem — ikona w pasku menu, bez okna.",
                           "Papla starts in the background with your account — a menu bar icon, no window."))
                        .font(DS.Font.label).foregroundStyle(DS.Color.inkSecondary)
                }
            }
            .toggleStyle(.switch)
            .padding(DS.Space.base)
            .background(DS.Color.ink.opacity(0.05), in: .rect(cornerRadius: DS.Radius.panel))
        }
    }

    private var ready: some View {
        VStack(spacing: DS.Space.snug) {
            header("checkmark.seal.fill", t("Gotowe", "All set"),
                   t("Oto Twoje ustawienia. Za chwilę pokażę w oknie, co jest co.",
                     "Here's your setup. Next I'll show what's what in the window."))

            VStack(alignment: .leading, spacing: 6) {
                summary(t("Mikrofon", "Microphone"), microphone)
                summary(t("Dostępność", "Accessibility"), accessibility)
                summary(t("Nagrywanie ekranu", "Screen Recording"), screenRecording)
                summary(t("Model mowy", "Speech model"), modelReady)
            }
            .padding(DS.Space.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.ink.opacity(0.05), in: .rect(cornerRadius: DS.Radius.panel))

            VStack(spacing: 0) {
                shortcutRow(t("Dyktowanie", "Dictation"), settings.triggerDisplayName)
                shortcutRow(t("Dyktowanie z tłumaczeniem", "Dictate and translate"), settings.translateShortcut.displayName)
                shortcutRow(t("Chwytanie tekstu", "Text grab"), settings.grabShortcut.displayName)
                shortcutRow(t("Wyszukiwarka", "Search"), settings.clipboardShortcut.displayName)
                shortcutRow(t("Próbnik kolorów", "Color picker"), settings.colorPickerShortcut.displayName)
                shortcutRow(t("Minutnik", "Timer"), settings.timerShortcut.displayName)
            }
            .padding(DS.Space.base)
            .background(DS.Color.ink.opacity(0.05), in: .rect(cornerRadius: DS.Radius.panel))
        }
    }

    // MARK: - Pieces

    private func summary(_ title: String, _ isOK: Bool) -> some View {
        HStack(spacing: DS.Space.snug) {
            Image(systemName: isOK ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isOK ? DS.Color.statusGood : DS.Color.inkSecondary)
            Text(title).font(DS.Font.body)
            Spacer()
            if !isOK { Text(t("do nadania później w Ustawieniach", "to set up later in Settings")).font(DS.Font.label).foregroundStyle(DS.Color.inkSecondary) }
        }
    }

    private func shortcutRow(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title).font(DS.Font.body)
            Spacer()
            Text(keys).font(DS.Font.counter).foregroundStyle(DS.Color.inkSecondary)
        }
        .padding(.vertical, 4)
    }

    private func choice(title: String, detail: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(DS.Font.bodyEmphasis)
                if let detail {
                    Text(detail).font(DS.Font.label).foregroundStyle(DS.Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .foregroundStyle(DS.Color.ink)
            .padding(DS.Space.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .fill(isOn ? Brand.accent.opacity(0.14) : DS.Color.ink.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .strokeBorder(isOn ? Brand.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func downloadModel() {
        isDownloadingModel = true
        modelError = nil
        Task {
            do {
                _ = try await ParakeetModels.shared.manager()
            } catch {
                modelError = t("Nie udało się pobrać: ", "Download failed: ") + error.localizedDescription
            }
            modelReady = ParakeetModels.isDownloaded
            isDownloadingModel = false
        }
    }
}
