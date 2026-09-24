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
    case dictation, grab, clipboard, colors, timer, dictionary, appearance, model, permissions

    var id: String { rawValue }

    /// The last three are shown as bare icons — there's no room for ten words in one row.
    var icon: String? {
        switch self {
        case .appearance: "paintbrush.pointed"
        case .model: "cpu"
        case .permissions: "lock.shield"
        default: nil
        }
    }

    @MainActor
    var title: String {
        switch self {
        case .dictation: t("Dyktowanie", "Dictation")
        case .grab: t("Chwytanie", "Grab")
        case .clipboard: t("Schowek", "Clipboard")
        case .colors: t("Kolory", "Colors")
        case .timer: t("Minutnik", "Timer")
        case .appearance: t("Wygląd", "Appearance")
        case .dictionary: t("Słownik", "Dictionary")
        case .model: t("Model", "Model")
        case .permissions: t("Uprawnienia", "Permissions")
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

            switch tab {
            case .appearance:
                VisualizerLivePreview()
            case .clipboard:
                clipboardWidthControls
            default:
                EmptyView()
            }

            if tab == .dictionary {
                DictionaryPanel()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.wide) {
                        switch tab {
                        case .dictation: dictationPanels
                        case .grab: grabPanels
                        case .clipboard: clipboardPanels
                        case .colors: colorPanels
                        case .timer: timerPanels
                        case .appearance: appearancePanels
                        case .dictionary: EmptyView()
                        case .model: ModelSettingsPanel(controller: controller)
                        case .permissions: PermissionsSettingsPanel()
                        }
                    }
                    .padding(.bottom, DS.Space.roomy)
                }
            }
        }
        .padding(.horizontal, DS.Space.wide)
        .padding(.vertical, DS.Space.roomy + 2)
        // A recorder left running behind a closed section would keep swallowing the next
        // key someone presses, anywhere in the app, forever.
        .onDisappear {
            cancelRecording()
            cancelGrabRecording()
        }
    }

    private var tabBar: some View {
        HStack(spacing: DS.Space.snug) {
            Spacer(minLength: 0)
            ForEach(SettingsTab.allCases) { candidate in
                if candidate == .appearance {
                    Rectangle().fill(DS.Color.seam).frame(width: 1, height: 20)
                        .padding(.horizontal, DS.Space.tight)
                }
                TransportKey(
                    title: candidate.icon == nil ? candidate.title : "",
                    systemImage: candidate.icon,
                    isEngaged: tab == candidate,
                    engagedColor: Brand.accent,
                    // The dictionary isn't one of the features that also live in the search
                    // bar, so it gets its own faint warm tint.
                    tint: candidate == .dictionary ? .orange : nil,
                    help: candidate.icon == nil ? nil : candidate.title
                ) {
                    withAnimation(DS.Motion.panel) { tab = candidate }
                }
            }
            KarabinerInfoButton()
                .padding(.leading, DS.Space.tight)
            Spacer(minLength: 0)
        }
    }

    /// Pinned above the scrolling panels so the live search window stays in view while the
    /// slider moves.
    private var clipboardWidthControls: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            SearchWidthPreview(controller: clipboardController, width: settings.clipboardPanelWidth)
            HStack(spacing: DS.Space.base) {
                Silkscreen(text: t("Szerokość wyszukiwarki", "Search window width"))
                Slider(value: $settings.clipboardPanelWidth, in: 600...1200, step: 20)
                Text("\(Int(settings.clipboardPanelWidth)) px")
                    .font(DS.Font.counter)
                    .foregroundStyle(DS.Color.inkSecondary)
                    .frame(width: 70, alignment: .trailing)
                TransportKey(title: t("Domyślna", "Default")) {
                    settings.clipboardPanelWidth = ClipboardPanel.defaultWidth
                }
            }
        }
    }

    // MARK: - Dyktowanie

    @ViewBuilder
    private var dictationPanels: some View {
        panel(label: t("Klawisz dyktowania", "Dictation key")) {
            if let shortcut = settings.customShortcut {
                HStack(spacing: DS.Space.snug) {
                    DeckWindow {
                        Readout(text: shortcut.displayName, large: true)
                            .padding(.horizontal, DS.Space.base)
                            .padding(.vertical, DS.Space.snug)
                    }
                    TransportKey(title: t("Zmień", "Change")) { startRecording() }
                    TransportKey(title: t("Wyczyść", "Clear")) {
                        settings.customShortcut = nil
                        controller.reloadHotkey()
                    }
                }
                note(t("Własny nagrany skrót. Lista klawiszy poniżej jest nieaktywna, "
                    + "dopóki go nie wyczyścisz.",
                    "Custom recorded shortcut. The list of keys below is disabled "
                    + "until you clear it."))
            } else if isRecordingShortcut {
                HStack(spacing: DS.Space.snug) {
                    DeckWindow {
                        Text(t("Naciśnij kombinację…", "Press a combination…"))
                            .font(DS.Font.bodyEmphasis)
                            .foregroundStyle(DS.Color.inkOnDeck)
                            .padding(.horizontal, DS.Space.base)
                            .padding(.vertical, DS.Space.snug)
                    }
                    TransportKey(title: t("Anuluj", "Cancel")) { cancelRecording() }
                }
                note(t("Wciśnij dowolną kombinację, np. ⌘⌥[ — złapię ją od razu. Esc anuluje.",
                    "Press any combination, e.g. ⌘⌥[ — it's captured instantly. Esc cancels."))
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
                    TransportKey(title: t("Nagraj własny…", "Record custom…")) { startRecording() }
                }
                note(settings.triggerKeys.count > 1
                    ? t("Trzymasz naraz wszystkie zaznaczone klawisze w dowolnym miejscu, "
                      + "żeby dyktować: \(settings.triggerKeys.sortedDisplay). Albo "
                      + "nagraj dowolną własną kombinację, jeśli żaden z tych trzech Ci "
                      + "nie pasuje.",
                      "Hold down all the selected keys at once, anywhere, to dictate: "
                      + "\(settings.triggerKeys.sortedDisplay). Or record your own custom "
                      + "combination if none of these three suits you.")
                    : t("Przytrzymaj ten klawisz w dowolnym miejscu, żeby dyktować. Zaznacz "
                      + "więcej niż jeden, żeby wymagać kombinacji trzymanej naraz — albo "
                      + "nagraj dowolną własną, jeśli żaden z tych trzech Ci nie pasuje.",
                      "Hold this key down anywhere to dictate. Select more than one to "
                      + "require a combination held at once — or record your own custom "
                      + "one if none of these three suits you."))
            }
        }

        panel(label: t("Sposób wyzwalania", "Trigger mode")) {
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

        panel(label: t("Czyszczenie", "Cleanup")) {
            Toggle(isOn: $settings.cleanupEnabled) {
                Silkscreen(text: t("Czyść transkrypcje", "Clean up transcriptions"))
            }
            .toggleStyle(.switch)
            note(t("Usuwa wypełniacze, poprawia spacje i interpunkcję. Poprawki ze "
                + "słownika działają niezależnie od tego ustawienia.",
                "Strips filler words, fixes spacing and punctuation. Dictionary "
                + "corrections apply regardless of this setting."))
        }

        panel(label: t("Interpunkcja", "Punctuation")) {
            HStack(spacing: DS.Space.snug) {
                ForEach(PunctuationStyle.allCases, id: \.self) { style in
                    TransportKey(
                        title: style.displayName,
                        isEngaged: settings.punctuationStyle == style,
                        engagedColor: Brand.accent
                    ) {
                        settings.punctuationStyle = style
                    }
                }
            }
            note(t("Normalna — kropka na końcu jak zwykle. Bez kropki na końcu — koniec z „kropką "
                + "nienawiści” w wiadomościach. Minimalna — dodatkowo bez przecinków (zostają ? i !). "
                + "Po emoji i po „XD” nigdy nie ma przecinka ani kropki, niezależnie od wyboru.",
                "Normal — a period at the end as usual. No final period — no more “hate period” in "
                + "chat messages. Minimal — also no commas (? and ! stay). Nothing ever follows an "
                + "emoji or “XD” — no comma, no period — whichever you pick."))
        }

        panel(label: t("Dyktuj i tłumacz", "Dictate and translate")) {
            ShortcutRow(label: t("Skrót", "Shortcut"), shortcut: $settings.translateShortcut) {
                controller.reloadHotkey()
            }
            HStack(spacing: DS.Space.base) {
                Silkscreen(text: t("Na język", "To language"))
                Picker(t("Na język", "To language"), selection: $settings.translateTargetLanguage) {
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
            note(t("Naciśnij ten skrót zamiast zwykłego, żeby to, co powiesz, zostało "
                + "przetłumaczone i wklejone w wybranym języku. Możesz go też nacisnąć w "
                + "trakcie zwykłego dyktowania — dogrywa albo zdejmuje tłumaczenie dla tej "
                + "wypowiedzi, bez przerywania nagrywania; start i stop dalej robi tylko "
                + "klawisz dyktowania. Orb zmienia kolor, gdy tłumaczenie jest uzbrojone — "
                + "kolory poniżej w Wygląd ▸ Kolory tłumaczenia. Działa lokalnie na Macu "
                + "(Apple Translation) — wiersz powyżej pobiera pakiet danej pary języków "
                + "raz, tutaj, żeby dyktowanie nigdy nie czekało na pobranie w tle.",
                "Press this shortcut instead of the regular one to have what you say "
                + "translated and pasted in the chosen language. You can also press it "
                + "mid-dictation — it arms or disarms translation for that utterance "
                + "without interrupting the recording; only the dictation key still "
                + "starts and stops it. The orb changes color while translation is "
                + "armed — see the colors below under Appearance ▸ Translation Colors. "
                + "It runs locally on your Mac (Apple Translation) — the row above "
                + "downloads that language pair's package once, here, so dictation "
                + "never has to wait on a background download."))
        }

        panel(label: t("Emoji", "Emoji")) {
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
                ? t("Wyłączone — transkrypcja zostaje dokładnie taka, jak ją wypowiedziałeś.",
                    "Off — the transcription stays exactly as you said it.")
                : t("Do ", "Up to ") + "\(settings.emojiIntensity) "
                  + t(polishPlural(settings.emojiIntensity, one: "emoji", few: "emoji", many: "emoji"),
                      englishPlural(settings.emojiIntensity, one: "emoji", other: "emoji"))
                  + t(" na wypowiedź, dobierane po konkretnych słowach ze stałego słownika "
                      + "poniżej — nigdy przez model językowy.",
                      " per utterance, picked by specific words from the fixed dictionary "
                      + "below — never by a language model."))

            if settings.emojiIntensity > 0 {
                Toggle(isOn: $settings.emojiAtSentenceEnd) {
                    Silkscreen(text: t("Emoji na końcu zdania, nie zaraz po słowie", "Emoji at the end of the sentence, not right after the word"))
                }
                .toggleStyle(.checkbox)
                .padding(.top, DS.Space.base)

                Toggle(isOn: $settings.emojiSuppressPeriod) {
                    Silkscreen(text: t("Nie stawiaj kropki obok emoji", "Don't put a period next to emoji"))
                }
                .toggleStyle(.checkbox)
                .padding(.top, DS.Space.snug)
                note(t("Emoji zamiast kropki, nie kropka i emoji obok siebie.",
                    "Emoji instead of a period, not a period and emoji side by side."))

                emojiFilterGrid
                    .padding(.top, DS.Space.base)

                customEmojiEditor
                    .padding(.top, DS.Space.base)

                Toggle(isOn: $settings.emojiSofteningEnabled) {
                    Silkscreen(text: t("Zmiękczaj korekty i zastrzeżenia (Twój styl)", "Soften corrections and caveats (your style)"))
                }
                .toggleStyle(.checkbox)
                .padding(.top, DS.Space.base)
                note(t("Zdanie z przeczeniem, zastrzeżeniem albo przyznaniem się do czegoś "
                    + "(\"to nie jest…\", \"po Twojej stronie…\", \"fajniej jest…\") dostaje "
                    + "jedno emoji na końcu, tak jak sam to robisz w wiadomościach. To rozpoznawanie "
                    + "tonu, nie tematu — więc bywa mniej trafne niż słownik powyżej; wyłącz "
                    + "pojedyncze wyzwalacze poniżej, jeśli któryś strzela za często.",
                    "A sentence with a negation, a caveat, or an admission "
                    + "(\"that's not…\", \"on your end…\", \"it's nicer to…\") gets "
                    + "a single emoji at the end, the way you already do it in messages. This is "
                    + "tone recognition, not topic recognition — so it's less accurate than the "
                    + "dictionary above; turn off individual triggers below if one fires too often."))

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
            Silkscreen(text: t("Własne słowa-klucze", "Custom keywords"))
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkSecondary)

            ForEach(settings.customEmojiEntries) { entry in
                HStack(spacing: DS.Space.snug) {
                    Text("\(entry.emoji) \(entry.phrase)")
                        .font(DS.Font.body)
                    if entry.placement == .sentenceEnd {
                        Text(t("na końcu zdania", "at end of sentence"))
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
                TextField(t("słowo lub fraza", "word or phrase"), text: $newEmojiPhrase)
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
                TransportKey(title: t("Dodaj", "Add")) { addCustomEmoji() }
                    .disabled(newEmojiPhrase.trimmingCharacters(in: .whitespaces).isEmpty || newEmojiGlyph.isEmpty)
            }
            .padding(.top, DS.Space.tight)

            Toggle(isOn: $newEmojiAtSentenceEnd) {
                Silkscreen(text: t("Ta fraza na końcu zdania, nie zaraz po niej", "This phrase at the end of the sentence, not right after it"))
            }
            .toggleStyle(.checkbox)
            .padding(.top, DS.Space.hair)

            note(t("Sprawdzane przed stałym słownikiem, więc możesz nadpisać jego emoji "
                + "podając to samo słowo.",
                "Checked before the fixed dictionary, so you can override its emoji "
                + "by using the same word."))
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
            Silkscreen(text: t("Słowa-klucze", "Keywords"))
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
        panel(label: t("Skrót do chwytania", "Grab shortcut")) {
            if isRecordingGrabShortcut {
                HStack(spacing: DS.Space.snug) {
                    DeckWindow {
                        Text(t("Naciśnij kombinację…", "Press a combination…"))
                            .font(DS.Font.bodyEmphasis)
                            .foregroundStyle(DS.Color.inkOnDeck)
                            .padding(.horizontal, DS.Space.base)
                            .padding(.vertical, DS.Space.snug)
                    }
                    TransportKey(title: t("Anuluj", "Cancel")) { cancelGrabRecording() }
                }
                note(t("Wciśnij dowolną kombinację, np. ⌃⌥⌘4 — złapię ją od razu. Esc anuluje.",
                    "Press any combination, e.g. ⌃⌥⌘4 — it's captured instantly. Esc cancels."))
            } else {
                HStack(spacing: DS.Space.snug) {
                    DeckWindow {
                        Readout(text: settings.grabShortcut.displayName, large: true)
                            .padding(.horizontal, DS.Space.base)
                            .padding(.vertical, DS.Space.snug)
                    }
                    TransportKey(title: t("Zmień", "Change")) { startGrabRecording() }
                }
                note(t("Osobny od klawisza dyktowania — naciśnij go w dowolnym miejscu, "
                    + "żeby zaznaczyć obszar ekranu do rozpoznania.",
                    "Separate from the dictation key — press it anywhere to select "
                    + "a screen area for recognition."))
            }
        }

        panel(label: t("Języki rozpoznawania", "Recognition languages")) {
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                languageRow(label: t("Główny", "Primary"), selection: Binding(
                    get: { settings.grabPrimaryLanguage },
                    set: { settings.grabPrimaryLanguage = $0 }
                ))
                languageRow(
                    label: t("Dodatkowy", "Secondary"),
                    selection: Binding(
                        get: { settings.grabSecondaryLanguage ?? Self.noneLanguage },
                        set: { settings.grabSecondaryLanguage = $0 == Self.noneLanguage ? nil : $0 }
                    ),
                    includeNone: true
                )
            }
            note(t("Główny język zawsze wygrywa — to on naprawia polskie ogonki. Dodatkowy "
                + "pomaga, gdy w zaznaczeniu miesza się polski z angielskim.",
                "The primary language always wins — it's the one that fixes Polish "
                + "diacritics. The secondary one helps when the selection mixes Polish "
                + "and English."))
        }

        panel(label: t("Dokładność rozpoznawania", "Recognition accuracy")) {
            HStack(spacing: DS.Space.snug) {
                TransportKey(
                    title: t("Dokładna", "Accurate"),
                    isEngaged: settings.grabAccurateRecognition,
                    engagedColor: Brand.accent
                ) { settings.grabAccurateRecognition = true }
                TransportKey(
                    title: t("Szybka", "Fast"),
                    isEngaged: !settings.grabAccurateRecognition,
                    engagedColor: Brand.accent
                ) { settings.grabAccurateRecognition = false }
            }
            note(settings.grabAccurateRecognition
                ? t("Wolniejsza o ułamek sekundy, ale to tryb szybki najczęściej gubi ogonki.",
                    "A fraction of a second slower, but the fast mode is the one that "
                    + "usually loses diacritics.")
                : t("Szybszy przebieg, gorzej radzi sobie ze znakami diakrytycznymi.",
                    "A faster pass, but worse at handling diacritical marks."))
        }

        panel(label: t("Tekst chwytania", "Grabbed text")) {
            Toggle(isOn: $settings.grabJoinHyphenatedLines) {
                Silkscreen(text: t("Łącz wyrazy dzielone myślnikiem na końcu wiersza", "Join words hyphenated at the end of a line"))
            }
            .toggleStyle(.switch)

            Toggle(isOn: $settings.grabStraightenDashes) {
                Silkscreen(text: t("Zamień długi myślnik „—” na zwykły „-”", "Replace the em dash “—” with a plain hyphen “-”"))
            }
            .toggleStyle(.switch)
            .padding(.top, DS.Space.snug)

            Toggle(isOn: $settings.grabAutoPaste) {
                Silkscreen(text: t("Wklejaj automatycznie w polu, które ma fokus", "Paste automatically into the focused field"))
            }
            .toggleStyle(.switch)
            .padding(.top, DS.Space.snug)
            note(t("Domyślnie tekst tylko ląduje w schowku — wklejasz sam, gdzie chcesz.",
                "By default the text only lands in the clipboard — you paste it yourself, "
                + "wherever you want."))
        }

        panel(label: t("Pole zaznaczenia", "Selection box")) {
            Toggle(isOn: $settings.grabAnimatedSelectionGlow) {
                Silkscreen(text: t("Ruchoma poświata w kolorach Papli", "Animated glow in Papla's colors"))
            }
            .toggleStyle(.switch)
            note(settings.grabAnimatedSelectionGlow
                ? t("Obwódka zaokrąglonego pola przelewa się między trzema kolorami z "
                  + "Ustawień ▸ Wygląd, dopóki trwa zaznaczanie. Wyłącz, jeśli wolisz "
                  + "prostą, statyczną ramkę bez dodatkowego odświeżania w tle.",
                  "The rounded box's outline flows between the three colors from "
                  + "Settings ▸ Appearance for as long as the selection lasts. Turn "
                  + "this off if you'd rather have a simple, static border with no "
                  + "extra background refresh.")
                : t("Prosta, statyczna ramka — zero dodatkowego odświeżania podczas "
                  + "przeciągania zaznaczenia.",
                  "A simple, static border — zero extra refreshing while dragging "
                  + "the selection."))
        }
    }

    // MARK: - Schowek

    @ViewBuilder
    private var clipboardPanels: some View {
        panel(label: t("Skrót", "Shortcut")) {
            ShortcutRow(label: t("Otwórz Paplę", "Open Papla"), shortcut: $settings.clipboardShortcut) {
                clipboardController.reloadHotkey()
            }
            note(t("Wywołuje wyszukiwarkę Papli — historię wszystkiego, co skopiowałeś, z "
                + "kategoriami. Zębatka w rogu okna otwiera ustawienia. Osobny od dyktowania, "
                + "chwytania i próbnika kolorów.",
                "Opens Papla's search window — the history of everything you've "
                + "copied, organized into categories. The gear in the window's corner "
                + "opens Settings. Separate from dictation, grab, and the color picker."))
        }

        panel(label: t("Historia", "History")) {
            Toggle(isOn: Binding(
                get: { settings.clipboardEnabled },
                set: {
                    settings.clipboardEnabled = $0
                    clipboardController.updateMonitoring()
                }
            )) {
                Silkscreen(text: t("Zapamiętuj skopiowane rzeczy", "Remember copied items"))
            }
            .toggleStyle(.switch)
            note(t("Wszystko, co skopiujesz przez ⌘C, trafia do historii: tekst, linki, obrazy, "
                + "kolory, kod i pliki. Samo kopiowanie działa normalnie — nic w nim nie "
                + "zmieniam. Treści z menedżerów haseł (1Password, Bitwarden, Hasła…) nigdy "
                + "nie są zapisywane.",
                "Everything you copy with ⌘C lands in the history: text, links, images, "
                + "colors, code, and files. Copying itself works normally — I don't change "
                + "anything about it. Content from password managers (1Password, Bitwarden, "
                + "Passwords…) is never saved."))

            HStack(spacing: DS.Space.base) {
                Silkscreen(text: t("Limit historii", "History limit"))
                Picker(t("Limit", "Limit"), selection: $settings.clipboardMaxItems) {
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
                Silkscreen(text: t("Zapamiętuj też obrazy", "Remember images too"))
            }
            .toggleStyle(.switch)
            .padding(.top, DS.Space.snug)
            note(t("Obrazy zajmują najwięcej miejsca na dysku — wyłącz, jeśli wolisz tylko tekst.",
                "Images take up the most disk space — turn this off if you only want text."))

            TransportKey(title: t("Wyczyść historię", "Clear history"), systemImage: "trash") {
                isConfirmingClipboardClear = true
            }
            .padding(.top, DS.Space.base)
            .confirmationDialog(
                t("Usunąć całą historię schowka?", "Delete the entire clipboard history?"),
                isPresented: $isConfirmingClipboardClear,
                titleVisibility: .visible
            ) {
                Button(t("Usuń wszystko", "Delete all"), role: .destructive) { ClipboardStore.shared.clear() }
                Button(t("Anuluj", "Cancel"), role: .cancel) {}
            } message: {
                Text(t("Tej operacji nie można cofnąć.", "This action can't be undone."))
            }
        }

        panel(label: t("Widoczne w wyszukiwarce", "Visible in search")) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(ClipboardKind.allCases, id: \.self) { kind in
                    Toggle(isOn: kindVisibilityBinding(kind)) {
                        Silkscreen(text: kind.chipTitle)
                    }
                    .toggleStyle(.switch)
                }
            }
            note(t("Wyłączenie kategorii tylko chowa ją z wyszukiwarki — jej właściwa historia "
                + "(schowek, kolory, transkrypcje…) zostaje nietknięta.",
                "Turning off a category only hides it from search — its actual history "
                + "(clipboard, colors, transcriptions…) stays untouched."))
        }

        panel(label: t("Zrzuty ekranu", "Screenshots")) {
            Toggle(isOn: Binding(
                get: { settings.screenshotsEnabled },
                set: {
                    settings.screenshotsEnabled = $0
                    ScreenshotIndex.shared.refresh()
                }
            )) {
                Silkscreen(text: t("Pokazuj zrzuty i nagrania ekranu", "Show screenshots and screen recordings"))
            }
            .toggleStyle(.switch)
            note(t("Zrzuty (⌘⇧3, ⌘⇧4) i nagrania ekranu (⌘⇧5) zrobione wbudowaną funkcją macOS "
                + "pojawiają się w wyszukiwarce w kategorii Zrzuty, z miniaturami. Papla nie "
                + "robi ich sama — tylko wyszukuje pliki w: ",
                "Screenshots (⌘⇧3, ⌘⇧4) and screen recordings (⌘⇧5) taken with macOS's "
                + "built-in tool show up in search under the Screenshots category, with "
                + "thumbnails. Papla doesn't take them itself — it only looks for files in: ")
                + ScreenshotIndex.captureDirectories()
                    .map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
                    .joined(separator: t(" oraz ", " and "))
                + t(". Przy pierwszym użyciu macOS zapyta o dostęp do folderu Pulpit.",
                    ". The first time, macOS will ask for access to your Desktop folder."))
        }

        panel(label: t("Tłumaczenie w wyszukiwarce", "Translation in search")) {
            Toggle(isOn: $settings.clipboardTranslateAddsToHistory) {
                Silkscreen(text: t("Dodaj tłumaczenie do historii", "Add translation to history"))
            }
            .toggleStyle(.switch)
            note(settings.clipboardTranslateAddsToHistory
                ? t("„Tłumacz i kopiuj” z menu kontekstowego dokłada tłumaczenie jako nowy "
                  + "wpis nad oryginałem — widzisz je od razu w liście, panel nie zamyka "
                  + "się w trakcie tłumaczenia.",
                  "“Translate and Copy” from the context menu adds the translation as "
                  + "a new entry above the original — you see it right away in the list, "
                  + "and the panel doesn't close while translating.")
                : t("„Tłumacz i kopiuj” tylko podmienia zawartość schowka — bez dopisywania "
                  + "niczego do historii.",
                  "“Translate and Copy” only swaps the clipboard's contents — without "
                  + "adding anything to the history."))
        }

        panel(label: t("Wygląd wyszukiwarki", "Search window appearance")) {
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
            note(t("Okno wyszukiwarki używa szkła i kolorów systemowych, jak natywna aplikacja "
                + "macOS. „Systemowy” podąża za jasnym/ciemnym trybem Maca.",
                "The search window uses glass and system colors, like a native macOS app. "
                + "“System” follows your Mac's light/dark mode."))
        }

        panel(label: t("Wklejanie", "Pasting")) {
            Toggle(isOn: Binding(
                get: { settings.pasteStraightenDashes },
                set: {
                    settings.pasteStraightenDashes = $0
                    clipboardController.updatePasteInterceptor()
                }
            )) {
                Silkscreen(text: t("Zamień długi myślnik „—” na zwykły „-”", "Replace the em dash “—” with a plain hyphen “-”"))
            }
            .toggleStyle(.switch)
            note(t("Zmienia się dopiero w chwili wklejania (⌘V w dowolnej aplikacji albo wklejenie "
                + "z historii Papli) — zwykłe kopiowanie zostaje nietknięte, a po wklejeniu "
                + "schowek wraca do oryginału. Formatowanie tekstu zostaje. Wymaga uprawnienia "
                + "Dostępność, tak jak skróty.",
                "Only changes at the moment of pasting (⌘V in any app, or pasting from "
                + "Papla's history) — plain copying stays untouched, and the clipboard "
                + "reverts to the original right after pasting. Text formatting is "
                + "preserved. Requires the Accessibility permission, same as the shortcuts."))
        }
    }

    // MARK: - Kolory

    @ViewBuilder
    private var colorPanels: some View {
        panel(label: t("Skrót", "Shortcut")) {
            ShortcutRow(label: t("Próbnik kolorów", "Color picker"), shortcut: $settings.colorPickerShortcut) {
                colorController.reloadHotkey()
            }
            note(t("Otwiera systemową pipetę — kliknij dowolny piksel na ekranie. Osobny od "
                + "pozostałych skrótów.",
                "Opens the system eyedropper — click any pixel on screen. Separate from "
                + "the other shortcuts."))
        }

        panel(label: t("Zapis koloru", "Color format")) {
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
            note(t("W tym zapisie kolor ląduje w schowku zaraz po wybraniu. Z historii w sekcji "
                + "Kolory skopiujesz go w dowolnym z trzech zapisów.",
                "The color lands in the clipboard in this format right after picking it. "
                + "From the history in the Colors section you can copy it in any of the "
                + "three formats."))
        }

        panel(label: t("Historia kolorów", "Color history")) {
            HStack(spacing: DS.Space.base) {
                Silkscreen(text: t("Limit historii", "History limit"))
                Picker(t("Limit", "Limit"), selection: $settings.colorMaxItems) {
                    ForEach([50, 100, 200, 500], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: settings.colorMaxItems) { ColorStore.shared.trim() }
            }
            TransportKey(title: t("Wyczyść historię kolorów", "Clear color history"), systemImage: "trash") {
                isConfirmingColorClear = true
            }
            .padding(.top, DS.Space.snug)
            .confirmationDialog(
                t("Usunąć całą historię kolorów?", "Delete the entire color history?"),
                isPresented: $isConfirmingColorClear,
                titleVisibility: .visible
            ) {
                Button(t("Usuń wszystko", "Delete all"), role: .destructive) { ColorStore.shared.clear() }
                Button(t("Anuluj", "Cancel"), role: .cancel) {}
            } message: {
                Text(t("Tej operacji nie można cofnąć.", "This action can't be undone."))
            }
        }
    }

    // MARK: - Minutnik

    @ViewBuilder
    private var timerPanels: some View {
        panel(label: t("Skrót", "Shortcut")) {
            ShortcutRow(label: t("Otwórz", "Open"), shortcut: $settings.timerShortcut) {
                timerController.reloadHotkey()
            }
            note(t("Otwiera małe okienko: „za” (odliczanie, godziny/minuty/sekundy) albo „o” "
                + "(konkretna godzina, ewentualnie inny dzień — domyślnie dziś). To samo okienko "
                + "otwiera zegar przy polu wyszukiwania w Papli. Aktywne minutniki i budziki "
                + "widać na liście pod polem, z możliwością anulowania.",
                "Opens a small window: “in” (a countdown, hours/minutes/seconds) or "
                + "“at” (a specific time, optionally a different day — today by default). "
                + "The same window is opened by the clock icon next to Papla's search "
                + "field. Active timers and alarms show up in a list under the field, "
                + "and can be canceled."))
        }

        panel(label: t("Dźwięk alarmu", "Alarm sound")) {
            Picker(t("Dźwięk", "Sound"), selection: $settings.alarmSound) {
                ForEach(SystemSound.allCases, id: \.self) { sound in
                    Text(sound.displayName).tag(sound)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            note(t("Gdy minutnik lub budzik dojdzie do zera, dzwoni bez przerwy, na okienku z "
                + "przyciskiem „Wyłącz”, dopóki go nie potwierdzisz — nie ścisza go przełącznik "
                + "dźwięku dyktowania, bo cichy alarm mija się z celem. Do tego zawsze wyskakuje "
                + "też systemowe powiadomienie.",
                "When a timer or alarm reaches zero, it rings continuously, with a window "
                + "and a “Dismiss” button, until you confirm it — the dictation sound "
                + "toggle doesn't mute it, since a silent alarm would defeat the purpose. "
                + "A system notification always pops up alongside it, too."))
        }

        panel(label: t("Pasek menu", "Menu bar")) {
            Toggle(isOn: $settings.showTimerInMenuBar) {
                Silkscreen(text: t("Pokazuj odliczanie obok ikony Papli", "Show the countdown next to Papla's icon"))
            }
            note(t("Widać najbliższy aktywny minutnik cały czas, nie tylko po otwarciu "
                + "wyszukiwarki.",
                "The nearest active timer stays visible at all times, not just when the "
                + "search window is open."))
        }
    }

    // MARK: - Wygląd

    @ViewBuilder
    private var appearancePanels: some View {
        panel(label: t("Uruchamianie", "Startup")) {
            Toggle(isOn: Binding(
                get: { launchAtLogin },
                set: {
                    LaunchAtLogin.set($0)
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            )) {
                Silkscreen(text: t("Uruchamiaj Paplę przy logowaniu", "Launch Papla at login"))
            }
            .toggleStyle(.switch)
            note(t("Papla startuje w tle razem z Twoim kontem — ikona w pasku menu, bez okna. "
                + "Możesz to też wyłączyć w Ustawieniach systemowych ▸ Ogólne ▸ Rzeczy "
                + "otwierane podczas logowania.",
                "Papla starts in the background along with your account — a menu bar "
                + "icon, no window. You can also turn this off in System Settings ▸ "
                + "General ▸ Login Items."))
        }

        panel(label: t("Pozycja wskaźnika", "Indicator position")) {
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
                    Silkscreen(text: t("Margines", "Margin"))
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
                note(t("Gdzie na ekranie pojawia się orb — dla dyktowania i dla chwytania "
                    + "tekstu naraz — i jak daleko od krawędzi. Widoczne na żywo, dopóki "
                    + "ten panel jest otwarty.",
                    "Where the orb appears on screen — for dictation and for grabbing "
                    + "text alike — and how far from the edge. Visible live for as long "
                    + "as this panel is open."))
            }
        }
        .onAppear { HUDPreview.show() }
        .onDisappear { HUDPreview.hide() }

        panel(label: t("Język", "Language")) {
            Picker(t("Język aplikacji", "App language"), selection: $settings.appLanguage) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            note(t("Zmienia tylko język interfejsu Papli — niezależny od języka systemu i od "
                    + "tego, w jakim języku dyktujesz albo tłumaczysz.",
                "Only changes Papla's own interface language — independent of your Mac's "
                    + "system language, and of what language you dictate or translate into."))
        }

        panel(label: t("Ikona w pasku menu", "Menu bar icon")) {
            HStack(spacing: DS.Space.snug) {
                ForEach(MenuBarIconStyle.allCases, id: \.self) { style in
                    let isOn = settings.menuBarIconStyle == style
                    Button {
                        settings.menuBarIconStyle = style
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: style.symbol(active: false))
                                .font(.system(size: 20))
                                .frame(height: 24)
                            Text(style.displayName).font(DS.Font.caption)
                        }
                        .foregroundStyle(isOn ? Brand.accent : DS.Color.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Space.snug)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .fill(isOn ? Brand.accent.opacity(0.14) : DS.Color.seam)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            note(t("Jak wygląda ikona Papli w pasku menu. Podczas dyktowania zmienia się na "
                + "wypełnioną wersję. Lewy klik otwiera/zamyka okno Papli, prawy — menu.",
                "How Papla's icon looks in the menu bar. It switches to a filled version while "
                + "dictating. Left click opens/closes the Papla window, right click opens the menu."))
        }

        panel(label: t("Wizualizacja", "Visualization")) {
            Picker(t("Kształt", "Shape"), selection: $settings.hudVisualizerStyle) {
                ForEach(HUDVisualizerStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            note(t("Kula — miękka, świetlista kula w duchu Siri. Fala — świetlista smuga "
                + "reagująca na poziom głosu w czasie rzeczywistym. Dotyczy HUD-u dyktowania, "
                + "miernika w oknie głównym i HUD-u chwytania tekstu naraz.",
                "Orb — a soft, glowing sphere in the spirit of Siri. Wave — a glowing streak "
                + "reacting to your voice level in real time. Applies to the dictation HUD, "
                + "the meter in the main window, and the grab HUD alike."))
        }

        panel(label: t("Kolory fali", "Wave colors")) {
            HStack(spacing: DS.Space.roomy) {
                colorSwatch(t("Pierwszy", "First"), binding: Binding(
                    get: { settings.waveformAccentPrimary.color },
                    set: { settings.waveformAccentPrimary = RGBColor($0) }
                ))
                colorSwatch(t("Drugi", "Second"), binding: Binding(
                    get: { settings.waveformAccentSecondary.color },
                    set: { settings.waveformAccentSecondary = RGBColor($0) }
                ))
                colorSwatch(t("Trzeci", "Third"), binding: Binding(
                    get: { settings.waveformAccentTertiary.color },
                    set: { settings.waveformAccentTertiary = RGBColor($0) }
                ))
                Spacer()
                TransportKey(title: t("Domyślne", "Defaults")) { settings.resetWaveformAccentColors() }
            }
            note(t("Własna paleta dla wizualizacji „Fala” — niezależna od kolorów orbu powyżej.",
                "The wave visualization's own palette — independent of the orb's colors above."))
        }

        panel(label: t("Rozpiętość nasłuchu", "Listening range")) {
            HStack(spacing: DS.Space.base) {
                Silkscreen(text: t("Mało", "Little"))
                Slider(value: $settings.orbSpread, in: 0.2...2.0, step: 0.1)
                Silkscreen(text: t("Dużo", "A lot"))
            }
            note(t("Jak mocno orb się rozwidla, gdy mówisz głośniej albo appka pracuje. "
                + "Nisko = zwarta, spokojna kula nawet przy krzyku; wysoko = rozjeżdża "
                + "się szeroko nawet na szepcie.",
                "How much the orb spreads out as you speak louder, or as the app works. "
                + "Low = a tight, calm sphere even when you shout; high = it spreads "
                + "wide even on a whisper."))
        }

        panel(label: t("Kolory", "Colors")) {
            HStack(spacing: DS.Space.roomy) {
                colorSwatch(t("Pierwszy", "First"), binding: Binding(
                    get: { settings.accentPrimary.color },
                    set: { settings.accentPrimary = RGBColor($0) }
                ))
                colorSwatch(t("Drugi", "Second"), binding: Binding(
                    get: { settings.accentSecondary.color },
                    set: { settings.accentSecondary = RGBColor($0) }
                ))
                colorSwatch(t("Trzeci", "Third"), binding: Binding(
                    get: { settings.accentTertiary.color },
                    set: { settings.accentTertiary = RGBColor($0) }
                ))
                Spacer()
                TransportKey(title: t("Domyślne", "Defaults")) { settings.resetAccentColors() }
            }
            note(t("Trzy kolory, które krążą w orbie i podświetlają zaznaczone przyciski w "
                + "całej appce — łącznie z poświatą pola zaznaczenia przy chwytaniu tekstu.",
                "Three colors that swirl in the orb and highlight selected buttons "
                + "throughout the app — including the selection box glow when grabbing text."))
        }

        panel(label: t("Kolory tłumaczenia", "Translation colors")) {
            HStack(spacing: DS.Space.roomy) {
                colorSwatch(t("Pierwszy", "First"), binding: Binding(
                    get: { settings.translateAccentPrimary.color },
                    set: { settings.translateAccentPrimary = RGBColor($0) }
                ))
                colorSwatch(t("Drugi", "Second"), binding: Binding(
                    get: { settings.translateAccentSecondary.color },
                    set: { settings.translateAccentSecondary = RGBColor($0) }
                ))
                colorSwatch(t("Trzeci", "Third"), binding: Binding(
                    get: { settings.translateAccentTertiary.color },
                    set: { settings.translateAccentTertiary = RGBColor($0) }
                ))
                Spacer()
                TransportKey(title: t("Domyślne", "Defaults")) { settings.resetTranslateAccentColors() }
            }
            note(t("Ten sam orb, ale w innych kolorach, gdy nagranie ma zostać przetłumaczone "
                + "— żeby dało się od razu, bez czytania, rozpoznać który tryb właśnie działa.",
                "The same orb, but in different colors, when the recording is going to "
                + "be translated — so you can tell at a glance, without reading, which "
                + "mode is currently active."))
        }

        panel(label: t("Dźwięk", "Sound")) {
            Toggle(isOn: $settings.soundEnabled) {
                Silkscreen(text: t("Dźwięk przy starcie i końcu", "Sound at start and end"))
            }
            .toggleStyle(.switch)

            HStack(spacing: DS.Space.base) {
                Silkscreen(text: t("Głośność", "Volume"))
                Slider(value: $settings.soundVolume, in: 0...1)
                Readout(text: "\(Int(settings.soundVolume * 100))%")
                    .foregroundStyle(DS.Color.inkSecondary)
                    .frame(width: 42, alignment: .trailing)
            }
            .padding(.top, DS.Space.snug)
            .disabled(!settings.soundEnabled)
            .opacity(settings.soundEnabled ? 1 : 0.4)

            HStack(spacing: DS.Space.base) {
                soundRow(label: t("Start", "Start"), selection: $settings.soundStart)
                soundRow(label: t("Koniec", "End"), selection: $settings.soundEnd)
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
                    Text(t("Brak", "None")).tag(Self.noneLanguage)
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
            Rectangle().fill(DS.Color.seam).frame(height: 1)
                .padding(.top, DS.Space.snug)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    @State private var status = t("Sprawdzam…", "Checking…")
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
                status = t("Pakiet gotowy — tłumaczenie działa offline",
                    "Package ready — translation works offline")
            } catch {
                status = t("Nie udało się przygotować pakietu: \(error.localizedDescription)",
                    "Couldn't prepare the package: \(error.localizedDescription)")
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
                        Text(t("Naciśnij kombinację…", "Press a combination…"))
                            .font(DS.Font.bodyEmphasis)
                            .foregroundStyle(DS.Color.inkOnDeck)
                    } else {
                        Readout(text: shortcut.displayName)
                    }
                }
                .padding(.horizontal, DS.Space.base)
                .padding(.vertical, DS.Space.snug)
            }
            TransportKey(title: isRecording ? t("Anuluj", "Cancel") : t("Zmień", "Change")) {
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


/// The "(i)" next to the settings tabs: how to put Papla on the F keys. macOS reserves bare
/// F1–F12 for brightness, volume and so on, so Papla itself can't see them — a separate,
/// third-party program (Karabiner-Elements) has to turn one into a key combination Papla can.
private struct KarabinerInfoButton: View {
    @State private var isShowing = false

    private static let rule = """
    {
        "description": "F5 to Cmd + Option + Control + Backslash",
        "manipulators": [
            {
                "from": {
                    "key_code": "f5",
                    "modifiers": { "optional": ["any"] }
                },
                "to": [
                    {
                        "key_code": "backslash",
                        "modifiers": ["left_command", "left_option", "left_control"]
                    }
                ],
                "type": "basic"
            }
        ]
    }
    """

    var body: some View {
        Button { isShowing.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 17))
                .foregroundStyle(DS.Color.inkSecondary)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(t("Jak ustawić klawisze F", "How to use the F keys"))
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DS.Space.base) {
                Text(t("Klawisze F1–F12 jako skróty", "F1–F12 keys as shortcuts"))
                    .font(DS.Font.title)
                Text(t(
                    "macOS zarezerwował gołe klawisze F (jasność, głośność, muzyka), więc Papla ich "
                    + "nie widzi. Da się to obejść osobnym programem — Karabiner-Elements. To zupełnie "
                    + "inna aplikacja, nie związana z Paplą (darmowa, pobierasz ją ze strony "
                    + "karabiner-elements.pqrs.org). Papla nic w niej nie ustawia i za nią nie odpowiada.",
                    "macOS reserves the bare F keys (brightness, volume, media), so Papla can't see "
                    + "them. A separate program — Karabiner-Elements — can work around that. It is a "
                    + "completely different app, unrelated to Papla (free, from "
                    + "karabiner-elements.pqrs.org). Papla doesn't configure it and isn't responsible for it."
                ))
                .font(DS.Font.body)
                .fixedSize(horizontal: false, vertical: true)

                Text(t("Jak to zrobić:", "How:")).font(DS.Font.bodyEmphasis)
                Text(t(
                    "1. W Karabinerze: Complex Modifications ▸ Add your own rule, wklej kod poniżej "
                    + "(przykład: F5 → ⌘⌥⌃\\).\n"
                    + "2. W Papli: Dyktowanie ▸ Nagraj własny… i wciśnij F5 — Papla zobaczy ⌘⌥⌃\\.\n"
                    + "3. Inny klawisz? Zmień \"key_code\" w części from (np. \"f6\") i w to (np. "
                    + "\"equal_sign\" dla =), potem nagraj ten skrót w Papli.",
                    "1. In Karabiner: Complex Modifications ▸ Add your own rule, paste the code below "
                    + "(example: F5 → ⌘⌥⌃\\).\n"
                    + "2. In Papla: Dictation ▸ Record custom… and press F5 — Papla will see ⌘⌥⌃\\.\n"
                    + "3. A different key? Change \"key_code\" in from (e.g. \"f6\") and in to (e.g. "
                    + "\"equal_sign\" for =), then record that shortcut in Papla."
                ))
                .font(DS.Font.body)
                .fixedSize(horizontal: false, vertical: true)

                ScrollView(.horizontal) {
                    Text(Self.rule)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(DS.Space.base)
                }
                .background(DS.Color.ink.opacity(0.06), in: .rect(cornerRadius: DS.Radius.control))

                TransportKey(title: t("Kopiuj kod", "Copy code"), systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.rule, forType: .string)
                }
            }
            .padding(DS.Space.roomy + 2)
            .frame(width: 420)
        }
    }
}


/// The dictation indicator as it will look and move, driven by a made-up speech pattern
/// (phrases with pauses, syllable-rate wobble) instead of the microphone — so shape, colors
/// and spread can be judged live without having to talk while adjusting them.
private struct VisualizerLivePreview: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phrase = sin(t * 0.85)
            let talking = phrase > -0.25
            let syllable = 0.5 + 0.5 * sin(t * 9.0) * (0.6 + 0.4 * sin(t * 3.1))
            let level = talking ? min(1, max(0, (0.35 + 0.65 * syllable) * (0.55 + 0.45 * sin(t * 1.7)))) : 0
            VisualizerView(
                energy: 0.22 + CGFloat(level) * 0.85,
                isAnimating: true,
                isError: false,
                size: 64
            )
            .frame(width: 160, height: 100)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.82), in: .rect(cornerRadius: DS.Radius.panel))
        }
    }
}

/// The real search window, live, at the width chosen — same view, same data, just scaled down
/// and inert — so what you see is exactly what will pop up. The dashed outline is the widest
/// possible setting, which keeps the scale steady while the slider moves.
private struct SearchWidthPreview: View {
    let controller: ClipboardController
    let width: Double
    private static let maxWidth: Double = 1200
    private static let height: Double = 560

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / Self.maxWidth
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                    .strokeBorder(DS.Color.seam, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                ClipboardView(controller: controller, isPanel: true, isPreview: true)
                    .frame(width: width, height: Self.height)
                    .clipShape(RoundedRectangle(cornerRadius: PanelStyle.cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                    .scaleEffect(scale)
                    .frame(width: width * scale, height: Self.height * scale)
            }
        }
        .frame(maxWidth: 560)
        .aspectRatio(Self.maxWidth / Self.height, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
        .animation(DS.Motion.panel, value: width)
    }
}
