import AppKit
import SwiftUI

/// Ustawienia ▸ Model: pick the speech model, see where it lives, re-download it when
/// something's wrong, and check whether a newer one has been published.
///
/// Only the Parakeet v3 model understands Polish. The others are selectable — they can be
/// useful for other languages — but every place that touches the choice says plainly that
/// Polish will not work with them.
struct ModelSettingsPanel: View {
    let controller: DictationController

    @State private var settings = Settings.shared
    @State private var refreshToken = 0
    @State private var isBusy = false
    @State private var pendingChoice: SpeechModel?
    @State private var isConfirmingDownload = false
    @State private var status: String?
    @State private var others: [String] = []

    private static let byteFormat: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private var model: SpeechModel { settings.speechModel }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            if !model.supportsPolish { polishWarningBanner }

            section(t("Wybierz model mowy", "Choose the speech model")) {
                ForEach(SpeechModel.allCases, id: \.self) { candidate in
                    modelRow(candidate)
                }
                Text(t("Podświetlone na zielono modele rozumieją polski. Wszystkie pozostałe NIE obsługują "
                    + "polskiego — po ich wybraniu polskie dyktowanie będzie zwracać bzdury albo puste "
                    + "teksty.",
                    "Models highlighted in green understand Polish. All the others do NOT support Polish — "
                    + "with them selected, Polish dictation will come out as nonsense or empty text."))
                    .font(DS.Font.label).foregroundStyle(DS.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section(t("Wybrany model", "Selected model")) {
                let _ = refreshToken
                row(t("Model", "Model"), model.title)
                row(t("Języki", "Languages"), model.languages)
                row(t("Stan", "Status"), model.isDownloaded
                    ? t("Zainstalowany ✓", "Installed ✓")
                    : t("Nie pobrany — pobierze się przy pierwszym dyktowaniu", "Not downloaded — will download on first dictation"))
                if let size = ParakeetModels.installedSize(of: model) {
                    row(t("Rozmiar", "Size"), Self.byteFormat.string(fromByteCount: size))
                }
                if let date = ParakeetModels.installedDate(of: model) {
                    row(t("Pobrany", "Downloaded"), date.formatted(date: .abbreviated, time: .shortened))
                }
                row(t("Lokalizacja", "Location"),
                    model.folderURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))

                HStack(spacing: DS.Space.snug) {
                    TransportKey(title: model.isDownloaded ? t("Pobierz ponownie", "Download again") : t("Pobierz model", "Download model"),
                                 systemImage: "arrow.down.circle", isEnabled: !isBusy && !controller.state.isActive) {
                        model.isDownloaded ? (isConfirmingDownload = true) : download()
                    }
                    TransportKey(title: t("Sprawdź aktualizacje", "Check for updates"),
                                 systemImage: "arrow.triangle.2.circlepath", isEnabled: !isBusy) { checkUpdates() }
                    TransportKey(title: t("Pokaż w Finderze", "Show in Finder"), systemImage: "folder",
                                 isEnabled: model.isDownloaded) {
                        NSWorkspace.shared.activateFileViewerSelecting([model.folderURL])
                    }
                    if isBusy { ProgressView().controlSize(.small) }
                }
                .padding(.top, DS.Space.snug)

                if let status {
                    Text(status).font(DS.Font.body).foregroundStyle(DS.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(t("„Pobierz ponownie” kasuje lokalną kopię i ściąga ją od nowa — to sposób na uszkodzony "
                    + "model, gdy dyktowanie przestaje działać albo rozpoznaje bzdury.",
                    "“Download again” deletes the local copy and fetches it fresh — the fix for a corrupted "
                    + "model, when dictation stops working or recognizes nonsense."))
                    .font(DS.Font.label).foregroundStyle(DS.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !others.isEmpty {
                section(t("Wszystkie modele Parakeet tego autora", "All Parakeet models from the author")) {
                    Text(others.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DS.Color.inkSecondary)
                        .textSelection(.enabled)
                    Text(t("Lista z Hugging Face — informacyjnie. Papla potrafi uruchomić tylko cztery modele "
                        + "z góry tej zakładki.",
                        "From Hugging Face — for information. Papla can only run the four models at the top of "
                        + "this tab."))
                        .font(DS.Font.label).foregroundStyle(DS.Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .confirmationDialog(
            t("Skasować model i pobrać go ponownie?", "Delete the model and download it again?"),
            isPresented: $isConfirmingDownload, titleVisibility: .visible
        ) {
            Button(t("Pobierz ponownie", "Download again"), role: .destructive) { download() }
            Button(t("Anuluj", "Cancel"), role: .cancel) {}
        } message: {
            Text(t("Dyktowanie nie zadziała, dopóki pobieranie się nie skończy.",
                   "Dictation won't work until the download finishes."))
        }
        .confirmationDialog(
            t("Ten model nie obsługuje polskiego", "This model does not support Polish"),
            isPresented: Binding(get: { pendingChoice != nil }, set: { if !$0 { pendingChoice = nil } }),
            titleVisibility: .visible
        ) {
            Button(t("Wybierz mimo to", "Choose anyway"), role: .destructive) {
                if let choice = pendingChoice { select(choice) }
                pendingChoice = nil
            }
            Button(t("Zostań przy obecnym", "Keep the current one"), role: .cancel) { pendingChoice = nil }
        } message: {
            Text(t("„\(pendingChoice?.title ?? "")” rozumie: \(pendingChoice?.languages ?? "") — nie polski. "
                + "Dyktowanie po polsku przestanie działać poprawnie. Możesz wrócić do Parakeet v3 w każdej chwili.",
                "“\(pendingChoice?.title ?? "")” understands: \(pendingChoice?.languages ?? "") — not Polish. "
                + "Dictating in Polish will stop working properly. You can go back to Parakeet v3 any time."))
        }
    }

    private var polishWarningBanner: some View {
        HStack(alignment: .top, spacing: DS.Space.base) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DS.Color.statusWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text(t("Aktywny model NIE obsługuje polskiego", "The active model does NOT support Polish"))
                    .font(DS.Font.bodyEmphasis)
                Text(t("Dyktowanie po polsku nie będzie działać. Wróć do „Parakeet TDT 0.6B v3”, żeby "
                    + "znów dyktować po polsku.",
                    "Dictating in Polish won't work. Switch back to “Parakeet TDT 0.6B v3” to dictate in "
                    + "Polish again."))
                    .font(DS.Font.body).foregroundStyle(DS.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            TransportKey(title: t("Wróć do v3", "Back to v3")) { select(.v3) }
        }
        .padding(DS.Space.base)
        .background(DS.Color.statusWarning.opacity(0.15), in: .rect(cornerRadius: DS.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Color.statusWarning.opacity(0.7), lineWidth: 1))
    }

    private func modelRow(_ candidate: SpeechModel) -> some View {
        let isSelected = model == candidate
        let tint = candidate.supportsPolish ? DS.Color.statusGood : DS.Color.statusWarning
        return Button {
            guard !isSelected else { return }
            candidate.supportsPolish ? select(candidate) : (pendingChoice = candidate)
        } label: {
            HStack(spacing: DS.Space.base) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Brand.accent : DS.Color.inkSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DS.Space.snug) {
                        Text(candidate.title).font(DS.Font.bodyEmphasis)
                        if let size = candidate.approxSize {
                            Text(size).font(DS.Font.label).foregroundStyle(DS.Color.inkSecondary)
                        }
                        if candidate.isDownloaded {
                            Text(t("pobrany", "downloaded")).font(DS.Font.label).foregroundStyle(DS.Color.inkSecondary)
                        }
                    }
                    Text(candidate.languages).font(DS.Font.label).foregroundStyle(DS.Color.inkSecondary)
                }
                Spacer(minLength: 0)
                Text(candidate.supportsPolish
                    ? t("✓ Polski", "✓ Polish")
                    : t("⚠︎ Bez polskiego", "⚠︎ No Polish"))
                    .font(DS.Font.silkscreen)
                    .foregroundStyle(tint)
            }
            .foregroundStyle(DS.Color.ink)
            .padding(.horizontal, DS.Space.base)
            .padding(.vertical, DS.Space.snug + 2)
            .background(tint.opacity(candidate.supportsPolish ? 0.16 : 0.07), in: .rect(cornerRadius: DS.Radius.control))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control)
                    .strokeBorder(isSelected ? Brand.accent : tint.opacity(candidate.supportsPolish ? 0.5 : 0.25),
                                  lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            Silkscreen(text: title, large: true)
            content()
            Rectangle().fill(DS.Color.seam).frame(height: 1).padding(.top, DS.Space.snug)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.base) {
            Text(label).font(DS.Font.body).foregroundStyle(DS.Color.inkSecondary)
                .frame(width: 90, alignment: .leading)
            Text(value).font(DS.Font.body).foregroundStyle(DS.Color.ink)
                .textSelection(.enabled)
        }
    }

    private func select(_ candidate: SpeechModel) {
        settings.speechModel = candidate
        refreshToken += 1
        status = candidate.supportsPolish
            ? t("Wybrano \(candidate.title) — obsługuje polski ✓", "Selected \(candidate.title) — supports Polish ✓")
            : t("Wybrano \(candidate.title) — uwaga: NIE obsługuje polskiego.",
                "Selected \(candidate.title) — note: it does NOT support Polish.")
        if !candidate.isDownloaded {
            status = (status ?? "") + " " + t("Model pobierze się przy pierwszym dyktowaniu albo od razu przyciskiem „Pobierz model”.",
                                            "It will download on first dictation, or right away with “Download model”.")
        }
    }

    private func download() {
        let target = model
        isBusy = true
        status = t("Pobieram model… to może potrwać kilka minut.", "Downloading the model… this can take a few minutes.")
        Task {
            do {
                try await ParakeetModels.shared.redownload(target)
                status = t("Gotowe — model pobrany i wczytany ✓", "Done — model downloaded and loaded ✓")
                    + (target.supportsPolish ? "" : t(" Pamiętaj: ten model NIE obsługuje polskiego.", " Remember: this model does NOT support Polish."))
            } catch {
                status = t("Nie udało się pobrać: ", "Download failed: ") + error.localizedDescription
            }
            refreshToken += 1
            isBusy = false
        }
    }

    private func checkUpdates() {
        let target = model
        isBusy = true
        status = t("Sprawdzam…", "Checking…")
        Task {
            do {
                let result = try await ParakeetModels.checkRemote(target)
                others = result.others
                if let remote = result.lastModified, let local = ParakeetModels.installedDate(of: target) {
                    let day = remote.formatted(date: .abbreviated, time: .omitted)
                    status = remote > local
                        ? t("Jest nowsza wersja modelu (opublikowana \(day)). Użyj „Pobierz ponownie”, żeby ją dostać.",
                            "A newer version of the model is available (published \(day)). Use “Download again” to get it.")
                        : t("Masz aktualną wersję ✓ (ostatnia zmiana modelu: \(day))",
                            "You're up to date ✓ (model last changed \(day))")
                } else {
                    status = t("Sprawdzone, ale nie da się porównać wersji — model nie jest jeszcze pobrany.",
                               "Checked, but there's nothing local to compare with — the model isn't downloaded yet.")
                }
            } catch {
                status = t("Brak połączenia z serwerem modeli: ", "Couldn't reach the model server: ") + error.localizedDescription
            }
            isBusy = false
        }
    }
}
