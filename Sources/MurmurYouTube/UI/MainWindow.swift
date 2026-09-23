import MurmurDictionary
import AppKit
import SwiftUI

/// Polska odmiana rzeczownika po liczebniku: 1 nagranie, 2–4 nagrania, 5+ (i 12–14) nagrań.
func polishPlural(_ count: Int, one: String, few: String, many: String) -> String {
    let mod10 = count % 10
    let mod100 = count % 100
    if count == 1 { return one }
    if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
    return many
}

/// The app's main window.
///
/// Transport strip across the top, then a recessed well below holding whichever section is
/// selected — Transcriptions, Dictionary, or Settings. Settings lives here too, not only in
/// the separate ⌘, window: reaching for a whole other window to change the trigger key was
/// one click too many for something you might tweak often.
struct MainWindow: View {
    @Bindable var controller: DictationController
    @Bindable var grabController: GrabController
    @Bindable var clipboardController: ClipboardController
    @Bindable var colorController: ColorController
    @Bindable var timerController: TimerController

    @State private var section: Section = .transcriptions
    @State private var router = WindowRouter.shared

    enum Section: String, CaseIterable, Identifiable {
        case transcriptions
        case grabs
        case clipboard
        case colors
        case dictionary
        case settings

        var id: String { rawValue }
        @MainActor
        var title: String {
            switch self {
            case .transcriptions: t("Transkrypcje", "Transcriptions")
            case .grabs: t("Chwytanie", "Grabs")
            case .clipboard: t("Schowek", "Clipboard")
            case .colors: t("Kolory", "Colors")
            case .dictionary: t("Słownik", "Dictionary")
            case .settings: t("Ustawienia", "Settings")
            }
        }
    }

    var body: some View {
        ZStack {
            DS.Color.chassis.ignoresSafeArea()

            VStack(spacing: DS.Space.base) {
                TransportPanel(controller: controller, grabController: grabController)

                sectionKeys

                Well {
                    Group {
                        switch section {
                        case .transcriptions: TranscriptionList()
                        case .grabs: GrabHistoryList()
                        case .clipboard: ClipboardView(controller: clipboardController)
                        case .colors: ColorHistoryList(controller: colorController)
                        case .dictionary: DictionaryPanel()
                        case .settings:
                            SettingsContent(
                                controller: controller,
                                grabController: grabController,
                                clipboardController: clipboardController,
                                colorController: colorController,
                                timerController: timerController
                            )
                        }
                    }
                    .padding(DS.Space.hair)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(DS.Space.roomy)
        }
        .frame(minWidth: 720, minHeight: 560)
        .onAppear { consumePendingSection() }
        .onChange(of: router.pendingSection) { consumePendingSection() }
    }

    private func consumePendingSection() {
        guard let pending = router.pendingSection else { return }
        section = pending
        router.pendingSection = nil
    }

    private var sectionKeys: some View {
        HStack(spacing: DS.Space.snug) {
            ForEach(Section.allCases) { candidate in
                TransportKey(
                    title: candidate.title,
                    isEngaged: section == candidate,
                    engagedColor: Brand.accent
                ) {
                    withAnimation(DS.Motion.panel) { section = candidate }
                }
            }
            Spacer()
        }
    }
}

// MARK: - Transport

/// Record / stop, the level meter, the counter, and a quick grab button — the top of the
/// unit, both of Papla's triggers reachable without leaving the main window.
private struct TransportPanel: View {
    @Bindable var controller: DictationController
    @Bindable var grabController: GrabController

    @State private var elapsed: TimeInterval = 0
    @State private var startedAt: Date?

    private var isRecording: Bool { controller.state.isActive }

    var body: some View {
        HStack(spacing: DS.Space.roomy) {
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                Silkscreen(text: t("Nagrywanie", "Recording"))
                HStack(spacing: DS.Space.snug) {
                    TransportKey(
                        title: isRecording ? "Stop" : t("Nagrywaj", "Record"),
                        systemImage: isRecording ? "stop.fill" : "circle.fill",
                        isEngaged: isRecording
                    ) {
                        if isRecording {
                            controller.stopButtonRecording()
                        } else {
                            controller.startButtonRecording()
                        }
                    }

                    HStack(spacing: DS.Space.tight) {
                        Lamp(color: DS.Color.record, isLit: isRecording)
                        Silkscreen(text: "Rec")
                    }
                    .padding(.leading, DS.Space.tight)
                }
            }

            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Silkscreen(text: t("Poziom", "Level"))
                VisualizerView(
                    energy: levelEnergy,
                    isAnimating: isRecording,
                    isError: false,
                    size: 54
                )
                .frame(width: 90, height: 54)
            }

            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Silkscreen(text: t("Licznik", "Counter"))
                DeckWindow {
                    Readout(text: counterText, large: true)
                        .padding(.horizontal, DS.Space.base)
                        .padding(.vertical, DS.Space.snug)
                }
            }

            VStack(alignment: .leading, spacing: DS.Space.snug) {
                Silkscreen(text: t("Chwytanie", "Capture"))
                TransportKey(
                    title: t("Chwyć obszar", "Grab Area"),
                    systemImage: "viewfinder",
                    isEnabled: !grabController.state.isBusy
                ) {
                    grabController.beginGrab()
                }
            }

            Spacer()
        }
        .padding(DS.Space.roomy)
        .background(BrushedPanel())
        .onChange(of: controller.state.isActive) { _, active in
            startedAt = active ? Date() : nil
            if !active { elapsed = 0 }
        }
        .task(id: startedAt) {
            guard let startedAt else { return }
            while !Task.isCancelled {
                elapsed = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private var levelEnergy: CGFloat {
        isRecording ? 0.22 + CGFloat(max(0, min(controller.level, 1))) * 0.85 : 0
    }

    /// Minutes and seconds, zero-padded, the way a tape counter reads.
    private var counterText: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Transcriptions

/// Past transcriptions, searchable, each copyable.
private struct TranscriptionList: View {
    @State private var store = RunStore.shared
    @State private var query = ""
    @State private var isConfirmingClear = false

    private var runs: [DictationRun] {
        let all = store.runs.reversed().map { $0 }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.text.localizedStandardContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $query, placeholder: t("Szukaj w transkrypcjach", "Search transcriptions"))

            if runs.isEmpty {
                EmptyPanel(
                    label: store.runs.isEmpty ? t("Brak nagrań", "No recordings") : t("Brak wyników", "No results"),
                    detail: store.runs.isEmpty
                        ? t("Naciśnij Nagrywaj, żeby zacząć.", "Press Record to get started.")
                        : t("Spróbuj innego wyszukiwania.", "Try a different search.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.snug) {
                        ForEach(runs) { run in
                            TranscriptionRow(run: run) {
                                withAnimation(DS.Motion.panel) { RunLog.delete(run) }
                            }
                        }
                    }
                    .padding(DS.Space.base)
                }
                footer
            }
        }
    }

    private var footer: some View {
        HStack {
            Silkscreen(
                text: "\(store.runs.count) "
                    + t(polishPlural(store.runs.count, one: "nagranie", few: "nagrania", many: "nagrań"),
                        englishPlural(store.runs.count, one: "recording", other: "recordings")),
                color: DS.Color.inkOnDeck.opacity(0.5)
            )
            Spacer()
            Button { isConfirmingClear = true } label: {
                Silkscreen(text: t("Usuń wszystko", "Delete All"), color: DS.Color.inkOnDeck.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.vertical, DS.Space.snug)
        .background(DS.Color.deck)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Color.seam).frame(height: DS.Border.seam)
        }
        // Confirmed, unlike a single row: one row is trivially re-recorded, the whole
        // history is not, and there's no undo.
        .confirmationDialog(
            t("Usunąć wszystkie \(store.runs.count) "
                + polishPlural(store.runs.count, one: "nagranie", few: "nagrania", many: "nagrań") + "?",
              "Delete all \(store.runs.count) "
                + englishPlural(store.runs.count, one: "recording", other: "recordings") + "?"),
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button(t("Usuń wszystko", "Delete All"), role: .destructive) { RunLog.clear() }
            Button(t("Anuluj", "Cancel"), role: .cancel) {}
        } message: {
            Text(t("Tej operacji nie można cofnąć.", "This can't be undone."))
        }
    }
}

private struct TranscriptionRow: View {
    let run: DictationRun
    let onDelete: () -> Void

    @State private var didCopy = false
    @State private var isHovering = false

    /// Non-nil while the "add to dictionary" sheet is open. Carries a *template* entry —
    /// never actually stored — so `DictionaryEditor` can pre-fill `hear` from the
    /// mis-transcribed text without needing a second init path.
    @State private var addingEntry: DictionaryEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            HStack(spacing: DS.Space.snug) {
                Silkscreen(text: run.engine, color: DS.Color.inkOnDeck.opacity(0.7))
                Readout(text: String(format: "%.2fs", run.processSeconds))
                    .foregroundStyle(DS.Color.inkOnDeck.opacity(0.6))
                Spacer()
                Text(run.date, style: .time)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.inkOnDeck.opacity(0.5))
                copyButton
                addToDictionaryButton
                    .opacity(isHovering ? 1 : 0)
                deleteButton
                    .opacity(isHovering ? 1 : 0)
            }

            Text(run.text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkOnDeck)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let corrections = run.corrections, !corrections.isEmpty {
                CorrectionBadges(corrections: corrections)
            }
        }
        .padding(DS.Space.base)
        .background {
            DeckWindow { Color.clear }
                .opacity(isHovering ? 0.85 : 1)
        }
        .onHover { isHovering = $0 }
        .sheet(item: $addingEntry) { template in
            DictionaryEditor(entry: template) { DictionaryStore.shared.add($0) }
        }
    }

    /// Opens the dictionary editor pre-loaded with this run's text as the "hear" side — the
    /// point is to skip retyping whatever the engine phonetically mangled a foreign phrase
    /// into. Trim it down to the offending word or two, then type the correct spelling.
    private var addToDictionaryButton: some View {
        Button {
            addingEntry = DictionaryEntry(kind: .correction, write: "", hear: run.text)
        } label: {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DS.Color.inkOnDeck.opacity(0.55))
                .padding(.horizontal, DS.Space.snug)
                .padding(.vertical, DS.Space.tight)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip)
                        .strokeBorder(DS.Color.inkOnDeck.opacity(0.3), lineWidth: DS.Border.hairline)
                )
        }
        .buttonStyle(.plain)
        .help(t("Dodaj poprawkę do słownika", "Add correction to dictionary"))
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(run.text, forType: .string)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                didCopy = false
            }
        } label: {
            Silkscreen(
                text: didCopy ? t("Skopiowano", "Copied") : t("Kopiuj", "Copy"),
                color: DS.Color.inkOnDeck.opacity(didCopy ? 1 : 0.6)
            )
            .padding(.horizontal, DS.Space.snug)
            .padding(.vertical, DS.Space.tight)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.chip)
                    .strokeBorder(DS.Color.inkOnDeck.opacity(0.3), lineWidth: DS.Border.hairline)
            )
        }
        .buttonStyle(.plain)
    }

    /// Appears on hover only, and deletes without a confirmation — a single transcript is
    /// cheap to redo, and a dialog on every row would make tidying up tedious. The
    /// irreversible one is "Delete all", which does confirm.
    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DS.Color.inkOnDeck.opacity(0.55))
                .padding(.horizontal, DS.Space.snug)
                .padding(.vertical, DS.Space.tight)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip)
                        .strokeBorder(DS.Color.inkOnDeck.opacity(0.3), lineWidth: DS.Border.hairline)
                )
        }
        .buttonStyle(.plain)
        .help(t("Usuń tę transkrypcję", "Delete this transcription"))
    }
}

/// Shows that the dictionary fired, and on what. Without this the dictionary is invisible
/// and you can't tell a rule that works from one that never matches.
private struct CorrectionBadges: View {
    let corrections: [AppliedCorrection]

    var body: some View {
        HStack(spacing: DS.Space.snug) {
            Silkscreen(text: t("Poprawiono", "Corrected"), color: DS.Color.statusWarning)
            ForEach(corrections, id: \.self) { correction in
                HStack(spacing: DS.Space.tight) {
                    Text(correction.from)
                        .strikethrough()
                        .foregroundStyle(DS.Color.inkOnDeck.opacity(0.5))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DS.Color.inkOnDeck.opacity(0.4))
                    Text(correction.to)
                        .foregroundStyle(DS.Color.inkOnDeck)
                    if correction.count > 1 {
                        Text("×\(correction.count)")
                            .foregroundStyle(DS.Color.inkOnDeck.opacity(0.5))
                    }
                }
                .font(DS.Font.caption)
                .padding(.horizontal, DS.Space.snug)
                .padding(.vertical, DS.Space.hair)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip)
                        .strokeBorder(DS.Color.statusWarning.opacity(0.35), lineWidth: DS.Border.hairline)
                )
            }
            Spacer()
        }
    }
}

// MARK: - Shared

struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: DS.Space.snug) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.Color.inkOnDeck.opacity(0.5))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkOnDeck)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.inkOnDeck.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.vertical, DS.Space.snug)
        .background(DS.Color.deck)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Color.seam).frame(height: DS.Border.seam)
        }
    }
}

struct EmptyPanel: View {
    let label: String
    let detail: String

    var body: some View {
        VStack(spacing: DS.Space.snug) {
            Silkscreen(text: label, large: true, color: DS.Color.inkOnDeck.opacity(0.55))
            Text(detail)
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkOnDeck.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
