import AppKit
import SwiftUI

/// Ustawienia ▸ Model: which speech model is in use, where it lives, re-downloading it when
/// something's wrong with it, and whether a newer one has been published.
struct ModelSettingsPanel: View {
    let controller: DictationController

    @State private var installed = ParakeetModels.isDownloaded
    @State private var size = ParakeetModels.installedSize
    @State private var date = ParakeetModels.installedDate
    @State private var isBusy = false
    @State private var isConfirming = false
    @State private var status: String?
    @State private var others: [String] = []

    private static let byteFormat: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            section(t("Model mowy", "Speech model")) {
                row(t("Model", "Model"), "NVIDIA Parakeet TDT 0.6B v3 (CoreML, int8)")
                row(t("Języki", "Languages"), t("25 europejskich, w tym polski", "25 European, Polish included"))
                row(t("Stan", "Status"), installed
                    ? t("Zainstalowany ✓", "Installed ✓")
                    : t("Nie pobrany — pobierze się przy pierwszym dyktowaniu", "Not downloaded — will download on first dictation"))
                if let size { row(t("Rozmiar", "Size"), Self.byteFormat.string(fromByteCount: size)) }
                if let date { row(t("Pobrany", "Downloaded"), date.formatted(date: .abbreviated, time: .shortened)) }
                row(t("Lokalizacja", "Location"), ParakeetModels.folderURL.path.replacingOccurrences(
                    of: NSHomeDirectory(), with: "~"))

                HStack(spacing: DS.Space.snug) {
                    TransportKey(title: installed ? t("Pobierz ponownie", "Download again") : t("Pobierz model", "Download model"),
                                 systemImage: "arrow.down.circle", isEnabled: !isBusy && !controller.state.isActive) {
                        installed ? (isConfirming = true) : download()
                    }
                    TransportKey(title: t("Sprawdź aktualizacje", "Check for updates"),
                                 systemImage: "arrow.triangle.2.circlepath", isEnabled: !isBusy) { checkUpdates() }
                    TransportKey(title: t("Pokaż w Finderze", "Show in Finder"), systemImage: "folder",
                                 isEnabled: installed) {
                        NSWorkspace.shared.activateFileViewerSelecting([ParakeetModels.folderURL])
                    }
                    if isBusy { ProgressView().controlSize(.small) }
                }
                .padding(.top, DS.Space.snug)

                if let status {
                    Text(status).font(DS.Font.body).foregroundStyle(DS.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(t("„Pobierz ponownie” kasuje lokalną kopię i ściąga ją od nowa (ok. 470 MB) — to "
                    + "sposób na uszkodzony model, gdy dyktowanie przestaje działać albo rozpoznaje bzdury.",
                    "“Download again” deletes the local copy and fetches it fresh (about 470 MB) — the fix "
                    + "for a corrupted model, when dictation stops working or recognizes nonsense."))
                    .font(DS.Font.label).foregroundStyle(DS.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !others.isEmpty {
                section(t("Inne modele tego samego autora", "Other models from the same author")) {
                    Text(others.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DS.Color.inkSecondary)
                        .textSelection(.enabled)
                    Text(t("Tylko v3 obsługuje polski. Pozostałe są angielskie, japońskie, chińskie albo "
                        + "strumieniowe — Papla ich nie używa, to tylko informacja, co jest dostępne.",
                        "Only v3 covers Polish. The rest are English, Japanese, Chinese or streaming "
                        + "variants — Papla doesn't use them; this is just what's out there."))
                        .font(DS.Font.label).foregroundStyle(DS.Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .confirmationDialog(
            t("Skasować model i pobrać go ponownie?", "Delete the model and download it again?"),
            isPresented: $isConfirming, titleVisibility: .visible
        ) {
            Button(t("Pobierz ponownie", "Download again"), role: .destructive) { download() }
            Button(t("Anuluj", "Cancel"), role: .cancel) {}
        } message: {
            Text(t("Dyktowanie nie zadziała, dopóki pobieranie się nie skończy.",
                   "Dictation won't work until the download finishes."))
        }
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

    private func refresh() {
        installed = ParakeetModels.isDownloaded
        size = ParakeetModels.installedSize
        date = ParakeetModels.installedDate
    }

    private func download() {
        isBusy = true
        status = t("Pobieram model… to może potrwać kilka minut.", "Downloading the model… this can take a few minutes.")
        Task {
            do {
                try await ParakeetModels.shared.redownload()
                status = t("Gotowe — model pobrany i wczytany ✓", "Done — model downloaded and loaded ✓")
            } catch {
                status = t("Nie udało się pobrać: ", "Download failed: ") + error.localizedDescription
            }
            refresh()
            isBusy = false
        }
    }

    private func checkUpdates() {
        isBusy = true
        status = t("Sprawdzam…", "Checking…")
        Task {
            do {
                let result = try await ParakeetModels.checkRemote()
                others = result.others
                if let remote = result.lastModified, let local = date {
                    status = remote > local
                        ? t("Jest nowsza wersja modelu (opublikowana \(remote.formatted(date: .abbreviated, time: .omitted))). "
                            + "Użyj „Pobierz ponownie”, żeby ją dostać.",
                            "A newer version of the model is available (published \(remote.formatted(date: .abbreviated, time: .omitted))). "
                            + "Use “Download again” to get it.")
                        : t("Masz aktualną wersję ✓ (ostatnia zmiana modelu: \(remote.formatted(date: .abbreviated, time: .omitted)))",
                            "You're up to date ✓ (model last changed \(remote.formatted(date: .abbreviated, time: .omitted)))")
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
