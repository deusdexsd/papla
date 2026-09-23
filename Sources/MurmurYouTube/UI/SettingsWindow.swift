import SwiftUI
@preconcurrency import Translation

/// Settings, per the brief. Opens on ⌘, via the standard `Settings` scene (so the system
/// wires up the menu item and the shortcut) as a thin wrapper around `SettingsContent`,
/// which is the same view embedded directly in the main window's own "Ustawienia" tab —
/// one no longer has to reach for a separate popup to change anything.
struct SettingsWindow: View {
    @Bindable var controller: DictationController
    @Bindable var grabController: GrabController
    @Bindable var clipboardController: ClipboardController
    @Bindable var colorController: ColorController
    @Bindable var timerController: TimerController

    var body: some View {
        ZStack {
            DS.Color.chassis.ignoresSafeArea()
            SettingsContent(
                controller: controller,
                grabController: grabController,
                clipboardController: clipboardController,
                colorController: colorController,
                timerController: timerController
            )
        }
        .frame(width: 560, height: 640)
    }
}

/// Dictation, Chwytanie, and Wygląd are three genuinely different concerns sharing one
/// screen — a single long scroll made it hard to tell which panel belonged to which
/// feature. A small tab row up top, the same `TransportKey` idiom the rest of the app uses
/// for switching sections, keeps them apart without needing three separate windows.
private enum SettingsTab: String, CaseIterable, Identifiable {
    case dictation, grab, clipboard, colors, timer, appearance

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dictation: "Dyktowanie"
        case .grab: "Chwytanie"
        case .clipboard: "Schowek"
        case .colors: "Kolory"
        case .timer: "Minutnik"
        case .appearance: "Wygląd"
        }
    }
}

/// The actual settings panels. Framed by whoever embeds it — the standalone window gives it
/// a background; the main window just drops it into its recessed well like any other
/// section.
struct SettingsContent: View {
    @Bindable var controller: DictationController
    @Bindable var grabController: GrabController
    @Bindable var clipboardController: ClipboardController
    @Bindable var colorController: ColorController
    @Bindable var timerController: TimerController
    @State private var settings = Settings.shared
    @State private var tab: SettingsTab = .dictation

    @State private var isRecordingShortcut = false
    @State private var isRecordingGrabShortcut = false
    @State private var recorderToken: Any?

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var isConfirmingClipboardClear = false
    @State private var isConfirmingColorClear = false
    @State private var newEmojiPhrase = ""
    @State private var newEmojiGlyph = ""
    @State private var newEmojiAtSentenceEnd = false

    private static let noneLanguage = "none"

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.base) {
            tabBar

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.wide) {
                    switch tab {
                    case .dictation: dictationPanels
                    case .grab: grabPanels
                    case .clipboard: clipboardPanels
                    case .colors: colorPanels
                    case .timer: timerPanels
                    case .appearance: appearancePanels
                    }
                }
                .padding(.bottom, DS.Space.roomy)
            }
        }
        .padding(DS.Space.panel)
        // A recorder left running behind a closed section would keep swallowing the next
        // key someone presses, anywhere in the app, forever.
        .onDisappear {
            cancelRecording()
            cancelGrabRecording()
        }
    }

    private var tabBar: some View {
        HStack(spacing: DS.Space.snug) {
            ForEach(SettingsTab.allCases) { candidate in
                TransportKey(
                    title: candidate.title,
                    isEngaged: tab == candidate,
                    engagedColor: Brand.accent
                ) {
                    withAnimation(DS.Motion.panel) { tab = candidate }
                }
            }
            Spacer()
        }
    }

    // MARK: - Dyktowanie

    @ViewBuilder
    private var dictationPanels: some View {
        panel(label: "Klawisz dyktowania") {
            if let shortcut = settings.customShortcut {
                HStack(spacing: DS.Space.snug) {
                    DeckWindow {
                        Readout(text: shortcut.displayName, large: true)
                            .padding(.horizontal, DS.Space.base)
                            .padding(.vertical, DS.Space.snug)
                    }
                    TransportKey(title: "Zmień") { startRecording() }
                    TransportKey(title: "Wyczyść") {
                        settings.customShortcut = nil
                        controller.reloadHotkey()
                    }
                }
                note("Własny nagrany skrót. Lista klawiszy poniżej jest nieaktywna, "
                    + "dopóki go nie wyczyścisz.")
            } else if isRecordingShortcut {
                HStack(spacing: DS.Space.snug) {
                    DeckWindow {
                        Text("Naciśnij kombinację…")
                            .font(DS.Font.bodyEmphasis)
                            .foregroundStyle(DS.Color.inkOnDeck)
                            .padding(.horizontal, DS.Space.base)
                            .padding(.vertical, DS.Space.snug)
                    }
                    TransportKey(title: "Anuluj") { cancelRecording() }
                }
                note("Wciśnij dowolną kombinację, np. ⌘⌥[ — złapię ją od razu. Esc anuluje.")
            } else {
                HStack(spacing: DS.Space.snug) {
                    ForEach(PushToTalkKey.allCases, id: \.self) { key in
                        TransportKey(
                            title: key.displayName,
                            isEngaged: settings.triggerKeys.contains(key),
                            engagedColor: Brand.accent
                        ) {
                            toggleTriggerKey(key)
                        }
                    }
                    TransportKey(title: "Nagraj własny…") { startRecording() }
                }
                note(settings.triggerKeys.count > 1
                    ? "Trzymasz naraz wszystkie zaznaczone klawisze w dowolnym miejscu, "
                      + "żeby dyktować: \(settings.triggerKeys.sortedDisplay). Albo "
                      + "nagraj dowolną własną kombinację, jeśli żaden z tych trzech Ci "
                      + "nie pasuje."
                    : "Przytrzymaj ten klawisz w dowolnym miejscu, żeby dyktować. Zaznacz "
                      + "więcej niż jeden, żeby wymagać kombinacji trzymanej naraz — albo "
                      + "nagraj dowolną własną, jeśli żaden z tych trzech Ci nie pasuje.")
            }
        }

        panel(label: "Sposób wyzwalania") {
            HStack(spacing: DS.Space.snug) {
                ForEach(DictationTriggerMode.allCases, id: \.self) { mode in
                    TransportKey(
                        title: mode.displayName,
                        isEngaged: settings.triggerMode == mode,
                        engagedColor: Brand.accent
                    ) {
                        settings.triggerMode = mode
                    }
                }
            }
            note(settings.triggerMode.note)
        }

        panel(label: "Czyszczenie") {
            Toggle(isOn: $settings.cleanupEnabled) {
                Silkscreen(text: "Czyść transkrypcje")
            }
            .toggleStyle(.switch)
            note("Usuwa wypełniacze, poprawia spacje i interpunkcję. Poprawki ze "
                + "słownika działają niezależnie od tego ustawienia.")
        }

        panel(label: "Dyktuj i tłumacz") {
            ShortcutRow(label: "Skrót", shortcut: $settings.translateShortcut) {
                controller.reloadHotkey()
            }
            HStack(spacing: DS.Space.base) {
                Silkscreen(text: "Na język")
                Picker("Na język", selection: $settings.translateTargetLanguage) {
                    ForEach(TranslateLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .padding(.top, DS.Space.snug)
            TranslationPrepareRow(target: settings.translateTargetLanguage)
                .padding(.top, DS.Space.base)
            note("Naciśnij ten skrót zamiast zwykłego, żeby to, co powiesz, zostało "
                + "przetłumaczone i wklejone w wybranym języku. Możesz go też nacisnąć w "
                + "trakcie zwykłego dyktowania — dogrywa albo zdejmuje tłumaczenie dla tej "
                + "wypowiedzi, bez przerywania nagrywania; start i stop dalej robi tylko "
                + "klawisz dyktowania. Orb zmienia kolor, gdy tłumaczenie jest uzbrojone — "
                + "kolory poniżej w Wygląd ▸ Kolory tłumaczenia. Działa lokalnie na Macu "
                + "(Apple Translation) — wiersz powyżej pobiera pakiet danej pary języków "
                + "raz, tutaj, żeby dyktowanie nigdy nie czekało na pobranie w tle.")
        }

        panel(label: "Emoji") {
            HStack(spacing: DS.Space.snug) {
                ForEach(0...5, id: \.self) { level in
                    TransportKey(
                        title: "\(level)",
                        isEngaged: settings.emojiIntensity == level,
                        engagedColor: Brand.accent
                    ) {
                        settings.emojiIntensity = level
                    }
                }
            }
            note(settings.emojiIntensity == 0
                ? "Wyłączone — transkrypcja zostaje dokładnie taka, jak ją wypowiedziałeś."
                : "Do \(settings.emojiIntensity) "
                  + polishPlural(settings.emojiIntensity, one: "emoji", few: "emoji", many: "emoji")
                  + " na wypowiedź, dobierane po konkretnych słowach ze stałego słownika "
                  + "poniżej — nigdy przez model językowy.")

            if settings.emojiIntensity > 0 {
                Toggle(isOn: $settings.emojiAtSentenceEnd) {
                    Silkscreen(text: "Emoji na końcu zdania, nie zaraz po słowie")
                }
                .toggleStyle(.checkbox)
                .padding(.top, DS.Space.base)

                Toggle(isOn: $settings.emojiSuppressPeriod) {
                    Silkscreen(text: "Nie stawiaj kropki obok emoji")
                }
                .toggleStyle(.checkbox)
                .padding(.top, DS.Space.snug)
                note("Emoji zamiast kropki, nie kropka i emoji obok siebie.")

                emojiFilterGrid
                    .padding(.top, DS.Space.base)

                customEmojiEditor
                    .padding(.top, DS.Space.base)

                Toggle(isOn: $settings.emojiSofteningEnabled) {
                    Silkscreen(text: "Zmiękczaj korekty i zastrzeżenia (Twój styl)")
                }
                .toggleStyle(.checkbox)
                .padding(.top, DS.Space.base)
                note("Zdanie z przeczeniem, zastrzeżeniem albo przyznaniem się do czegoś "
                    + "(\"to nie jest…\", \"po Twojej stronie…\", \"fajniej jest…\") dostaje "
                    + "jedno emoji na końcu, tak jak sam to robisz w wiadomościach. To rozpoznawanie "
                    + "tonu, nie tematu — więc bywa mniej trafne niż słownik powyżej; wyłącz "
                    + "pojedyncze wyzwalacze poniżej, jeśli któryś strzela za często.")

                if settings.emojiSofteningEnabled {
                    softeningFilterGrid
                        .padding(.top, DS.Space.snug)
                }
            }
        }
    }

    private var softeningFilterGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 130), spacing: DS.Space.tight)],
            alignment: .leading,
            spacing: DS.Space.tight
        ) {
            ForEach(EmojiEnricher.softeningEntries) { entry in
                let isOn = !settings.emojiDisabledKeywords.contains(entry.id)
                Button {
                    if isOn {
                        settings.emojiDisabledKeywords.insert(entry.id)
                    } else {
                        settings.emojiDisabledKeywords.remove(entry.id)
                    }
                } label: {
                    Text("\(entry.emoji) \(entry.phrase)")
                        .font(DS.Font.body)
                        .lineLimit(1)
                        .padding(.horizontal, DS.Space.snug)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .fill(isOn ? Brand.accent.opacity(0.14) : DS.Color.seam)
                        )
                        .opacity(isOn ? 1 : 0.4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customEmojiEditor: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            Silkscreen(text: "Własne słowa-klucze")
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkSecondary)

            ForEach(settings.customEmojiEntries) { entry in
                HStack(spacing: DS.Space.snug) {
                    Text("\(entry.emoji) \(entry.phrase)")
                        .font(DS.Font.body)
                    if entry.placement == .sentenceEnd {
                        Text("na końcu zdania")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.inkSecondary)
                    }
                    Spacer()
                    Button {
                        settings.customEmojiEntries.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DS.Color.inkSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: DS.Space.snug) {
                TextField("słowo lub fraza", text: $newEmojiPhrase)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, DS.Space.snug)
                    .padding(.vertical, 5)
                    .background(DS.Color.well, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                TextField("🙂", text: $newEmojiGlyph)
                    .textFieldStyle(.plain)
                    .frame(width: 44)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 5)
                    .background(DS.Color.well, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                TransportKey(title: "Dodaj") { addCustomEmoji() }
                    .disabled(newEmojiPhrase.trimmingCharacters(in: .whitespaces).isEmpty || newEmojiGlyph.isEmpty)
            }
            .padding(.top, DS.Space.tight)

            Toggle(isOn: $newEmojiAtSentenceEnd) {
                Silkscreen(text: "Ta fraza na końcu zdania, nie zaraz po niej")
            }
            .toggleStyle(.checkbox)
            .padding(.top, DS.Space.hair)

            note("Sprawdzane przed stałym słownikiem, więc możesz nadpisać jego emoji "
                + "podając to samo słowo.")
        }
    }

    private func addCustomEmoji() {
        let phrase = newEmojiPhrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let emoji = newEmojiGlyph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, !emoji.isEmpty else { return }
        settings.customEmojiEntries.removeAll { $0.phrase == phrase }
        settings.customEmojiEntries.append(EmojiEnricher.Entry(
            phrase: phrase, emoji: emoji,
            placement: newEmojiAtSentenceEnd ? .sentenceEnd : .inline
        ))
        newEmojiPhrase = ""
        newEmojiGlyph = ""
        newEmojiAtSentenceEnd = false
    }

    private var emojiFilterGrid: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            Silkscreen(text: "Słowa-klucze")
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkSecondary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), spacing: DS.Space.tight)],
                alignment: .leading,
                spacing: DS.Space.tight
            ) {
                ForEach(EmojiEnricher.entries) { entry in
                    let isOn = !settings.emojiDisabledKeywords.contains(entry.id)
                    Button {
                        if isOn {
                            settings.emojiDisabledKeywords.insert(entry.id)
                        } else {
                            settings.emojiDisabledKeywords.remove(entry.id)
                        }
                    } label: {
                        Text("\(entry.emoji) \(entry.phrase)")
                            .font(DS.Font.body)
                            .lineLimit(1)
                            .padding(.horizontal, DS.Space.snug)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                    .fill(isOn ? Brand.accent.opacity(0.14) : DS.Color.seam)
                            )
                            .opacity(isOn ? 1 : 0.4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Chwytanie tekstu

    @ViewBuilder
    private var grabPanels: some View {
        panel(label: "Skrót do chwytania") {
            if isRecordingGrabShortcut {
                HStack(spacing: DS.Space.snug) {
                    DeckWindow {
                        Text("Naciśnij kombinację…")
                            .font(DS.Font.bodyEmphasis)
                            .foregroundStyle(DS.Color.inkOnDeck)
                            .padding(.horizontal, DS.Space.base)
                            .padding(.vertical, DS.Space.snug)
                    }
                    TransportKey(title: "Anuluj") { cancelGrabRecording() }
                }
                note("Wciśnij dowolną kombinację, np. ⌃⌥⌘4 — złapię ją od razu. Esc anuluje.")
            } else {
                HStack(spacing: DS.Space.snug) {
                    DeckWindow {
                        Readout(text: settings.grabShortcut.displayName, large: true)
                            .padding(.horizontal, DS.Space.base)
                            .padding(.vertical, DS.Space.snug)
                    }
                    TransportKey(title: "Zmień") { startGrabRecording() }
                }
                note("Osobny od klawisza dyktowania — naciśnij go w dowolnym miejscu, "
                    + "żeby zaznaczyć obszar ekranu do rozpoznania.")
            }
        }

        panel(label: "Języki rozpoznawania") {
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                languageRow(label: "Główny", selection: Binding(
                    get: { settings.grabPrimaryLanguage },
                    set: { settings.grabPrimaryLanguage = $0 }
                ))
                languageRow(
                    label: "Dodatkowy",
                    selection: Binding(
                        get: { settings.grabSecondaryLanguage ?? Self.noneLanguage },
                        set: { settings.grabSecondaryLanguage = $0 == Self.noneLanguage ? nil : $0 }
                    ),
                    includeNone: true
                )
            }
            note("Główny język zawsze wygrywa — to on naprawia polskie ogonki. Dodatkowy "
                + "pomaga, gdy w zaznaczeniu miesza się polski z angielskim.")
        }

        panel(label: "Dokładność rozpoznawania") {
            HStack(spacing: DS.Space.snug) {
                TransportKey(
                    title: "Dokładna",
                    isEngaged: settings.grabAccurateRecognition,
                    engagedColor: Brand.accent
                ) { settings.grabAccurateRecognition = true }
                TransportKey(
                    title: "Szybka",
                    isEngaged: !settings.grabAccurateRecognition,
                    engagedColor: Brand.accent
                ) { settings.grabAccurateRecognition = false }
            }
            note(settings.grabAccurateRecognition
                ? "Wolniejsza o ułamek sekundy, ale to tryb szybki najczęściej gubi ogonki."
                : "Szybszy przebieg, gorzej radzi sobie ze znakami diakrytycznymi.")
        }

        panel(label: "Tekst chwytania") {
            Toggle(isOn: $settings.grabJoinHyphenatedLines) {
                Silkscreen(text: "Łącz wyrazy dzielone myślnikiem na końcu wiersza")
            }
            .toggleStyle(.switch)

            Toggle(isOn: $settings.grabStraightenDashes) {
                Silkscreen(text: "Zamień długi myślnik „—” na zwykły „-”")
            }
            .toggleStyle(.switch)
            .padding(.top, DS.Space.snug)

            Toggle(isOn: $settings.grabAutoPaste) {
                Silkscreen(text: "Wklejaj automatycznie w polu, które ma fokus")
            }
            .toggleStyle(.switch)
            .padding(.top, DS.Space.snug)
            note("Domyślnie tekst tylko ląduje w schowku — wklejasz sam, gdzie chcesz.")
        }

        panel(label: "Pole zaznaczenia") {
            Toggle(isOn: $settings.grabAnimatedSelectionGlow) {
                Silkscreen(text: "Ruchoma poświata w kolorach Papli")
            }
            .toggleStyle(.switch)
            note(settings.grabAnimatedSelectionGlow
                ? "Obwódka zaokrąglonego pola przelewa się między trzema kolorami z "
                  + "Ustawień ▸ Wygląd, dopóki trwa zaznaczanie. Wyłącz, jeśli wolisz "
                  + "prostą, statyczną ramkę bez dodatkowego odświeżania w tle."
                : "Prosta, statyczna ramka — zero dodatkowego odświeżania podczas "
                  + "przeciągania zaznaczenia.")
        }
    }

    // MARK: - Schowek

    @ViewBuilder
    private var clipboardPanels: some View {
        panel(label: "Skrót") {
            ShortcutRow(label: "Otwórz Paplę", shortcut: $settings.clipboardShortcut) {
                clipboardController.reloadHotkey()
            }
            note("Wywołuje wyszukiwarkę Papli — historię wszystkiego, co skopiowałeś, z "
                + "kategoriami. Zębatka w rogu okna otwiera ustawienia. Osobny od dyktowania, "
                + "chwytania i próbnika kolorów.")
        }

        panel(label: "Historia") {
            Toggle(isOn: Binding(
                get: { settings.clipboardEnabled },
                set: {
                    settings.clipboardEnabled = $0
                    clipboardController.updateMonitoring()
                }
            )) {
                Silkscreen(text: "Zapamiętuj skopiowane rzeczy")
            }
            .toggleStyle(.switch)
            note("Wszystko, co skopiujesz przez ⌘C, trafia do historii: tekst, linki, obrazy, "
                + "kolory, kod i pliki. Samo kopiowanie działa normalnie — nic w nim nie "
                + "zmieniam. Treści z menedżerów haseł (1Password, Bitwarden, Hasła…) nigdy "
                + "nie są zapisywane.")

            HStack(spacing: DS.Space.base) {
                Silkscreen(text: "Limit historii")
                Picker("Limit", selection: $settings.clipboardMaxItems) {
                    ForEach([100, 250, 500, 1000, 2000], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: settings.clipboardMaxItems) { ClipboardStore.shared.trim() }
            }
            .padding(.top, DS.Space.base)

            Toggle(isOn: $settings.clipboardKeepImages) {
                Silkscreen(text: "Zapamiętuj też obrazy")
            }
            .toggleStyle(.switch)
            .padding(.top, DS.Space.snug)
            note("Obrazy zajmują najwięcej miejsca na dysku — wyłącz, jeśli wolisz tylko tekst.")

            TransportKey(title: "Wyczyść historię", systemImage: "trash") {
                isConfirmingClipboardClear = true
            }
            .padding(.top, DS.Space.base)
            .confirmationDialog(
                "Usunąć całą historię schowka?",
                isPresented: $isConfirmingClipboardClear,
                titleVisibility: .visible
            ) {
                Button("Usuń wszystko", role: .destructive) { ClipboardStore.shared.clear() }
                Button("Anuluj", role: .cancel) {}
            } message: {
                Text("Tej operacji nie można cofnąć.")
            }
        }

        panel(label: "Widoczne w wyszukiwarce") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(ClipboardKind.allCases, id: \.self) { kind in
                    Toggle(isOn: kindVisibilityBinding(kind)) {
                        Silkscreen(text: kind.chipTitle)
                    }
                    .toggleStyle(.switch)
                }
            }
            note("Wyłączenie kategorii tylko chowa ją z wyszukiwarki — jej właściwa historia "
                + "(schowek, kolory, transkrypcje…) zostaje nietknięta.")
        }

        panel(label: "Zrzuty ekranu") {
            Toggle(isOn: Binding(
                get: { settings.screenshotsEnabled },
                set: {
                    settings.screenshotsEnabled = $0
                    ScreenshotIndex.shared.refresh()
                }
            )) {
                Silkscreen(text: "Pokazuj zrzuty i nagrania ekranu")
            }
            .toggleStyle(.switch)
            note("Zrzuty (⌘⇧3, ⌘⇧4) i nagrania ekranu (⌘⇧5) zrobione wbudowaną funkcją macOS "
                + "pojawiają się w wyszukiwarce w kategorii Zrzuty, z miniaturami. Papla nie "
                + "robi ich sama — tylko wyszukuje pliki w: "
                + ScreenshotIndex.captureDirectories()
                    .map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
                    .joined(separator: " oraz ")
                + ". Przy pierwszym użyciu macOS zapyta o dostęp do folderu Pulpit.")
        }

        panel(label: "Tłumaczenie w wyszukiwarce") {
            Toggle(isOn: $settings.clipboardTranslateAddsToHistory) {
                Silkscreen(text: "Dodaj tłumaczenie do historii")
            }
            .toggleStyle(.switch)
            note(settings.clipboardTranslateAddsToHistory
                ? "„Tłumacz i kopiuj” z menu kontekstowego dokłada tłumaczenie jako nowy "
                  + "wpis nad oryginałem — widzisz je od razu w liście, panel nie zamyka "
                  + "się w trakcie tłumaczenia."
                : "„Tłumacz i kopiuj” tylko podmienia zawartość schowka — bez dopisywania "
                  + "niczego do historii.")
        }

        panel(label: "Wygląd wyszukiwarki") {
            HStack(spacing: DS.Space.snug) {
                ForEach(PanelAppearance.allCases, id: \.self) { appearance in
                    TransportKey(
                        title: appearance.displayName,
                        isEngaged: settings.clipboardAppearance == appearance,
                        engagedColor: Brand.accent
                    ) {
                        settings.clipboardAppearance = appearance
                        clipboardController.applyAppearance()
                    }
                }
            }
            note("Okno wyszukiwarki używa szkła i kolorów systemowych, jak natywna aplikacja "
                + "macOS. „Systemowy” podąża za jasnym/ciemnym trybem Maca.")
        }

        panel(label: "Wklejanie") {
            Toggle(isOn: Binding(
                get: { settings.pasteStraightenDashes },
                set: {
                    settings.pasteStraightenDashes = $0
                    clipboardController.updatePasteInterceptor()
                }
            )) {
                Silkscreen(text: "Zamień długi myślnik „—” na zwykły „-”")
            }
            .toggleStyle(.switch)
            note("Zmienia się dopiero w chwili wklejania (⌘V w dowolnej aplikacji albo wklejenie "
                + "z historii Papli) — zwykłe kopiowanie zostaje nietknięte, a po wklejeniu "
                + "schowek wraca do oryginału. Formatowanie tekstu zostaje. Wymaga uprawnienia "
                + "Dostępność, tak jak skróty.")
        }
    }

    // MARK: - Kolory

    @ViewBuilder
    private var colorPanels: some View {
        panel(label: "Skrót") {
            ShortcutRow(label: "Próbnik kolorów", shortcut: $settings.colorPickerShortcut) {
                colorController.reloadHotkey()
            }
            note("Otwiera systemową pipetę — kliknij dowolny piksel na ekranie. Osobny od "
                + "pozostałych skrótów.")
        }

        panel(label: "Zapis koloru") {
            HStack(spacing: DS.Space.snug) {
                ForEach(ColorFormat.allCases, id: \.self) { format in
                    TransportKey(
                        title: format.displayName,
                        isEngaged: settings.colorFormat == format,
                        engagedColor: Brand.accent
                    ) { settings.colorFormat = format }
                }
                Spacer()
                DeckWindow {
                    Readout(text: settings.colorFormat.example)
                        .padding(.horizontal, DS.Space.base)
                        .padding(.vertical, DS.Space.snug)
                }
            }
            note("W tym zapisie kolor ląduje w schowku zaraz po wybraniu. Z historii w sekcji "
                + "Kolory skopiujesz go w dowolnym z trzech zapisów.")
        }

        panel(label: "Historia kolorów") {
            HStack(spacing: DS.Space.base) {
                Silkscreen(text: "Limit historii")
                Picker("Limit", selection: $settings.colorMaxItems) {
                    ForEach([50, 100, 200, 500], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: settings.colorMaxItems) { ColorStore.shared.trim() }
            }
            TransportKey(title: "Wyczyść historię kolorów", systemImage: "trash") {
                isConfirmingColorClear = true
            }
            .padding(.top, DS.Space.snug)
            .confirmationDialog(
                "Usunąć całą historię kolorów?",
                isPresented: $isConfirmingColorClear,
                titleVisibility: .visible
            ) {
                Button("Usuń wszystko", role: .destructive) { ColorStore.shared.clear() }
                Button("Anuluj", role: .cancel) {}
            } message: {
                Text("Tej operacji nie można cofnąć.")
            }
        }
    }

    // MARK: - Minutnik

    @ViewBuilder
    private var timerPanels: some View {
        panel(label: "Skrót") {
            ShortcutRow(label: "Otwórz", shortcut: $settings.timerShortcut) {
                timerController.reloadHotkey()
            }
            note("Otwiera małe okienko: „za” (odliczanie, godziny/minuty/sekundy) albo „o” "
                + "(konkretna godzina, ewentualnie inny dzień — domyślnie dziś). To samo okienko "
                + "otwiera zegar przy polu wyszukiwania w Papli. Aktywne minutniki i budziki "
                + "widać na liście pod polem, z możliwością anulowania.")
        }

        panel(label: "Dźwięk alarmu") {
            Picker("Dźwięk", selection: $settings.alarmSound) {
                ForEach(SystemSound.allCases, id: \.self) { sound in
                    Text(sound.displayName).tag(sound)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            note("Gdy minutnik lub budzik dojdzie do zera, dzwoni bez przerwy, na okienku z "
                + "przyciskiem „Wyłącz”, dopóki go nie potwierdzisz — nie ścisza go przełącznik "
                + "dźwięku dyktowania, bo cichy alarm mija się z celem. Do tego zawsze wyskakuje "
                + "też systemowe powiadomienie.")
        }

        panel(label: "Pasek menu") {
            Toggle(isOn: $settings.showTimerInMenuBar) {
                Silkscreen(text: "Pokazuj odliczanie obok ikony Papli")
            }
            note("Widać najbliższy aktywny minutnik cały czas, nie tylko po otwarciu "
                + "wyszukiwarki.")
        }
    }

    // MARK: - Wygląd

    @ViewBuilder
    private var appearancePanels: some View {
        panel(label: "Uruchamianie") {
            Toggle(isOn: Binding(
                get: { launchAtLogin },
                set: {
                    LaunchAtLogin.set($0)
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            )) {
                Silkscreen(text: "Uruchamiaj Paplę przy logowaniu")
            }
            .toggleStyle(.switch)
            note("Papla startuje w tle razem z Twoim kontem — ikona w pasku menu, bez okna. "
                + "Możesz to też wyłączyć w Ustawieniach systemowych ▸ Ogólne ▸ Rzeczy "
                + "otwierane podczas logowania.")
        }

        panel(label: "Pozycja wskaźnika") {
            VStack(alignment: .leading, spacing: DS.Space.base) {
                HStack(spacing: DS.Space.snug) {
                    ForEach(HUDPosition.allCases, id: \.self) { position in
                        TransportKey(
                            title: position.displayName,
                            isEngaged: settings.hudPosition == position,
                            engagedColor: Brand.accent
                        ) {
                            settings.hudPosition = position
                            HUDPreview.update()
                        }
                    }
                }
                HStack(spacing: DS.Space.base) {
                    Silkscreen(text: "Margines")
                    Slider(value: Binding(
                        get: { settings.hudMargin },
                        set: {
                            settings.hudMargin = $0
                            HUDPreview.update()
                        }
                    ), in: 8...160, step: 4)
                    Readout(text: "\(Int(settings.hudMargin))pt")
                        .foregroundStyle(DS.Color.inkSecondary)
                        .frame(width: 42, alignment: .trailing)
                }
                note("Gdzie na ekranie pojawia się orb — dla dyktowania i dla chwytania "
                    + "tekstu naraz — i jak daleko od krawędzi. Widoczne na żywo, dopóki "
                    + "ten panel jest otwarty.")
            }
        }
        .onAppear { HUDPreview.show() }
        .onDisappear { HUDPreview.hide() }

        panel(label: "Wizualizacja") {
            Picker("Kształt", selection: $settings.hudVisualizerStyle) {
                ForEach(HUDVisualizerStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            note("Kula — miękka, świetlista kula w duchu Siri. Fala — rząd pasków reagujących "
                + "na poziom głosu, jak wizualizacja poleceń głosowych w Tesli. Dotyczy HUD-u "
                + "dyktowania, miernika w oknie głównym i HUD-u chwytania tekstu naraz.")
        }

        panel(label: "Rozpiętość nasłuchu") {
            HStack(spacing: DS.Space.base) {
                Silkscreen(text: "Mało")
                Slider(value: $settings.orbSpread, in: 0.2...2.0, step: 0.1)
                Silkscreen(text: "Dużo")
            }
            note("Jak mocno orb się rozwidla, gdy mówisz głośniej albo appka pracuje. "
                + "Nisko = zwarta, spokojna kula nawet przy krzyku; wysoko = rozjeżdża "
                + "się szeroko nawet na szepcie.")
        }

        panel(label: "Kolory") {
            HStack(spacing: DS.Space.roomy) {
                colorSwatch("Pierwszy", binding: Binding(
                    get: { settings.accentPrimary.color },
                    set: { settings.accentPrimary = RGBColor($0) }
                ))
                colorSwatch("Drugi", binding: Binding(
                    get: { settings.accentSecondary.color },
                    set: { settings.accentSecondary = RGBColor($0) }
                ))
                colorSwatch("Trzeci", binding: Binding(
                    get: { settings.accentTertiary.color },
                    set: { settings.accentTertiary = RGBColor($0) }
                ))
                Spacer()
                TransportKey(title: "Domyślne") { settings.resetAccentColors() }
            }
            note("Trzy kolory, które krążą w orbie i podświetlają zaznaczone przyciski w "
                + "całej appce — łącznie z poświatą pola zaznaczenia przy chwytaniu tekstu.")
        }

        panel(label: "Kolory tłumaczenia") {
            HStack(spacing: DS.Space.roomy) {
                colorSwatch("Pierwszy", binding: Binding(
                    get: { settings.translateAccentPrimary.color },
                    set: { settings.translateAccentPrimary = RGBColor($0) }
                ))
                colorSwatch("Drugi", binding: Binding(
                    get: { settings.translateAccentSecondary.color },
                    set: { settings.translateAccentSecondary = RGBColor($0) }
                ))
                colorSwatch("Trzeci", binding: Binding(
                    get: { settings.translateAccentTertiary.color },
                    set: { settings.translateAccentTertiary = RGBColor($0) }
                ))
                Spacer()
                TransportKey(title: "Domyślne") { settings.resetTranslateAccentColors() }
            }
            note("Ten sam orb, ale w innych kolorach, gdy nagranie ma zostać przetłumaczone "
                + "— żeby dało się od razu, bez czytania, rozpoznać który tryb właśnie działa.")
        }

        panel(label: "Dźwięk") {
            Toggle(isOn: $settings.soundEnabled) {
                Silkscreen(text: "Dźwięk przy starcie i końcu")
            }
            .toggleStyle(.switch)

            HStack(spacing: DS.Space.base) {
                Silkscreen(text: "Głośność")
                Slider(value: $settings.soundVolume, in: 0...1)
                Readout(text: "\(Int(settings.soundVolume * 100))%")
                    .foregroundStyle(DS.Color.inkSecondary)
                    .frame(width: 42, alignment: .trailing)
            }
            .padding(.top, DS.Space.snug)
            .disabled(!settings.soundEnabled)
            .opacity(settings.soundEnabled ? 1 : 0.4)

            HStack(spacing: DS.Space.base) {
                soundRow(label: "Start", selection: $settings.soundStart)
                soundRow(label: "Koniec", selection: $settings.soundEnd)
            }
            .padding(.top, DS.Space.snug)
            .disabled(!settings.soundEnabled)
            .opacity(settings.soundEnabled ? 1 : 0.4)
        }
    }

    // MARK: - Helpers

    private func colorSwatch(_ label: String, binding: Binding<Color>) -> some View {
        VStack(spacing: DS.Space.tight) {
            ColorPicker("", selection: binding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 44, height: 24)
            Silkscreen(text: label, color: DS.Color.inkSecondary)
        }
    }

    private func soundRow(label: String, selection: Binding<SystemSound>) -> some View {
        HStack(spacing: DS.Space.tight) {
            Silkscreen(text: label)
            Picker(label, selection: selection) {
                ForEach(SystemSound.allCases, id: \.self) { sound in
                    Text(sound.displayName).tag(sound)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func languageRow(label: String, selection: Binding<String>, includeNone: Bool = false) -> some View {
        HStack(spacing: DS.Space.base) {
            Silkscreen(text: label)
                .frame(width: 70, alignment: .leading)
            Picker(label, selection: selection) {
                if includeNone {
                    Text("Brak").tag(Self.noneLanguage)
                }
                ForEach(OCRLanguage.common) { language in
                    Text(language.displayName).tag(language.code)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    /// Toggles one key's membership in the combo. Refuses to remove the last one — a
    /// button that would let you configure zero trigger keys is a dead-end, not a choice.
    private func toggleTriggerKey(_ key: PushToTalkKey) {
        var updated = settings.triggerKeys
        if updated.contains(key) {
            guard updated.count > 1 else { return }
            updated.remove(key)
        } else {
            updated.insert(key)
        }
        settings.triggerKeys = updated
        controller.reloadHotkey()
    }

    private func startRecording() {
        isRecordingShortcut = true
        recorderToken = ShortcutRecorder.start(
            onCapture: { shortcut in
                settings.customShortcut = shortcut
                isRecordingShortcut = false
                recorderToken = nil
                controller.reloadHotkey()
            },
            onCancel: {
                isRecordingShortcut = false
                recorderToken = nil
            }
        )
    }

    private func cancelRecording() {
        ShortcutRecorder.stop(recorderToken)
        recorderToken = nil
        isRecordingShortcut = false
    }

    private func startGrabRecording() {
        isRecordingGrabShortcut = true
        recorderToken = ShortcutRecorder.start(
            onCapture: { shortcut in
                settings.grabShortcut = shortcut
                isRecordingGrabShortcut = false
                recorderToken = nil
                grabController.reloadHotkey()
            },
            onCancel: {
                isRecordingGrabShortcut = false
                recorderToken = nil
            }
        )
    }

    private func cancelGrabRecording() {
        ShortcutRecorder.stop(recorderToken)
        recorderToken = nil
        isRecordingGrabShortcut = false
    }

    private func kindVisibilityBinding(_ kind: ClipboardKind) -> Binding<Bool> {
        Binding(
            get: { settings.clipboardVisibleKinds.contains(kind) },
            set: { isOn in
                if isOn { settings.clipboardVisibleKinds.insert(kind) }
                else { settings.clipboardVisibleKinds.remove(kind) }
            }
        )
    }

    private func panel<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.base) {
            Silkscreen(text: label, large: true)
            content()
        }
        .padding(DS.Space.roomy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrushedPanel())
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.label)
            .foregroundStyle(DS.Color.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}


/// A real, visible `.translationTask` — unlike `Translator`'s offscreen one-shot window, this
/// one is actually on screen, so if the system needs to show its own "pobierz pakiet
/// językowy" sheet for a language pair used for the first time, it has somewhere to anchor
/// it. Without this, that sheet has nowhere to appear and the *offscreen* translation just
/// hangs forever waiting for a confirmation the user can never see. Visiting Ustawienia once
/// per target language, before dictating with it, gets the download out of the way here.
private struct TranslationPrepareRow: View {
    let target: TranslateLanguage
    @State private var status = "Sprawdzam…"
    @State private var isWorking = true

    var body: some View {
        HStack(spacing: DS.Space.snug) {
            if isWorking { ProgressView().controlSize(.small) }
            Text(status).font(DS.Font.label).foregroundStyle(DS.Color.inkSecondary)
        }
        .translationTask(
            source: Locale.Language(identifier: "pl"),
            target: Locale.Language(identifier: target.rawValue)
        ) { session in
            isWorking = true
            do {
                try await session.prepareTranslation()
                status = "Pakiet gotowy — tłumaczenie działa offline"
            } catch {
                status = "Nie udało się przygotować pakietu: \(error.localizedDescription)"
            }
            isWorking = false
        }
    }
}

/// One labelled, re-recordable shortcut. Owns its own recording state, so any number of
/// these can sit on a screen without sharing (and fighting over) a single recorder flag.
private struct ShortcutRow: View {
    let label: String
    @Binding var shortcut: CustomShortcut
    let onChange: () -> Void

    @State private var isRecording = false
    @State private var token: Any?

    var body: some View {
        HStack(spacing: DS.Space.snug) {
            Silkscreen(text: label)
                .frame(width: 130, alignment: .leading)
            DeckWindow {
                Group {
                    if isRecording {
                        Text("Naciśnij kombinację…")
                            .font(DS.Font.bodyEmphasis)
                            .foregroundStyle(DS.Color.inkOnDeck)
                    } else {
                        Readout(text: shortcut.displayName)
                    }
                }
                .padding(.horizontal, DS.Space.base)
                .padding(.vertical, DS.Space.snug)
            }
            TransportKey(title: isRecording ? "Anuluj" : "Zmień") {
                isRecording ? cancel() : start()
            }
            Spacer()
        }
        .onDisappear { cancel() }
    }

    private func start() {
        isRecording = true
        token = ShortcutRecorder.start(
            onCapture: { captured in
                shortcut = captured
                isRecording = false
                token = nil
                onChange()
            },
            onCancel: {
                isRecording = false
                token = nil
            }
        )
    }

    private func cancel() {
        ShortcutRecorder.stop(token)
        token = nil
        isRecording = false
    }
}
