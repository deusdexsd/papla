import AppKit
import SwiftUI

/// The "Kolory" section: a button to start the eyedropper, and the history of picked colours
/// with a copy button per notation.
struct ColorHistoryList: View {
    let controller: ColorController

    @State private var store = ColorStore.shared
    @State private var query = ""
    @State private var isConfirmingClear = false

    private var entries: [ColorEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return store.entries }
        return store.entries.filter { entry in
            ColorFormat.allCases.contains { entry.formatted($0).localizedStandardContains(needle) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.base) {
                TransportKey(title: t("Wybierz kolor z ekranu", "Pick color from screen"), systemImage: "eyedropper", engagedColor: Brand.accent) {
                    controller.pick()
                }
                Text(Settings.shared.colorPickerShortcut.displayName)
                    .font(DS.Font.counter)
                    .foregroundStyle(DS.Color.inkOnDeck.opacity(0.5))
                Spacer()
            }
            .padding(DS.Space.base)

            SearchField(text: $query, placeholder: t("Szukaj koloru", "Search colors"))

            if entries.isEmpty {
                EmptyPanel(
                    label: store.entries.isEmpty ? t("Brak kolorów", "No colors") : t("Brak wyników", "No results"),
                    detail: store.entries.isEmpty
                        ? t("Użyj przycisku albo skrótu i kliknij dowolny piksel na ekranie.", "Use the button or the shortcut and click any pixel on the screen.")
                        : t("Spróbuj innego wyszukiwania.", "Try a different search.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.snug) {
                        ForEach(entries) { entry in
                            ColorRow(entry: entry, controller: controller) {
                                withAnimation(DS.Motion.panel) { store.delete(entry) }
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
                text: "\(store.entries.count) "
                    + t(polishPlural(store.entries.count, one: "kolor", few: "kolory", many: "kolorów"),
                        englishPlural(store.entries.count, one: "color", other: "colors")),
                color: DS.Color.inkOnDeck.opacity(0.5)
            )
            Spacer()
            Button { isConfirmingClear = true } label: {
                Silkscreen(text: t("Usuń wszystko", "Delete all"), color: DS.Color.inkOnDeck.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.vertical, DS.Space.snug)
        .background(DS.Color.deck)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Color.seam).frame(height: DS.Border.seam)
        }
        .confirmationDialog(
            t("Usunąć całą historię kolorów?", "Delete the entire color history?"),
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button(t("Usuń wszystko", "Delete all"), role: .destructive) { store.clear() }
            Button(t("Anuluj", "Cancel"), role: .cancel) {}
        } message: {
            Text(t("Tej operacji nie można cofnąć.", "This action cannot be undone."))
        }
    }
}

private struct ColorRow: View {
    let entry: ColorEntry
    let controller: ColorController
    let onDelete: () -> Void

    @State private var copiedFormat: ColorFormat?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DS.Space.base) {
            RoundedRectangle(cornerRadius: DS.Radius.control)
                .fill(Color(nsColor: entry.color))
                .frame(width: 46, height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .strokeBorder(DS.Color.inkOnDeck.opacity(0.18), lineWidth: DS.Border.hairline)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.hex)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.Color.inkOnDeck)
                Text(entry.date, style: .relative)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.inkOnDeck.opacity(0.45))
            }

            Spacer()

            ForEach(ColorFormat.allCases, id: \.self) { format in
                Button {
                    controller.copy(entry.color, as: format)
                    copiedFormat = format
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        if copiedFormat == format { copiedFormat = nil }
                    }
                } label: {
                    Silkscreen(
                        text: copiedFormat == format ? t("Skopiowano", "Copied") : format.displayName,
                        color: copiedFormat == format ? Brand.accent : DS.Color.inkOnDeck.opacity(0.7)
                    )
                    .padding(.horizontal, DS.Space.snug)
                    .padding(.vertical, DS.Space.tight)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.chip)
                            .strokeBorder(DS.Color.inkOnDeck.opacity(0.3), lineWidth: DS.Border.hairline)
                    )
                }
                .buttonStyle(.plain)
                .help(entry.formatted(format))
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Color.inkOnDeck.opacity(0.55))
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
        }
        .padding(DS.Space.base)
        .background { DeckWindow { Color.clear }.opacity(isHovering ? 0.85 : 1) }
        .onHover { isHovering = $0 }
    }
}
