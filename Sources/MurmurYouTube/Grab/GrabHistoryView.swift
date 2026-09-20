import AppKit
import SwiftUI

/// The grab history list — same shape as dictation's `TranscriptionList`, its own file
/// since it reads `GrabStore`, not `RunStore`.
struct GrabHistoryList: View {
    @State private var store = GrabStore.shared
    @State private var query = ""
    @State private var isConfirmingClear = false

    private var grabs: [Grab] {
        let all = store.grabs.reversed().map { $0 }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.text.localizedStandardContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $query, placeholder: "Szukaj w chwytach")

            if grabs.isEmpty {
                EmptyPanel(
                    label: store.grabs.isEmpty ? "Brak zrzutów" : "Brak wyników",
                    detail: store.grabs.isEmpty
                        ? "Użyj skrótu albo menu paska górnego, żeby zacząć."
                        : "Spróbuj innego wyszukiwania."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.snug) {
                        ForEach(grabs) { grab in
                            GrabRow(grab: grab) {
                                withAnimation(DS.Motion.panel) { GrabLog.delete(grab) }
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
                text: "\(store.grabs.count) "
                    + polishPlural(store.grabs.count, one: "zrzut", few: "zrzuty", many: "zrzutów"),
                color: DS.Color.inkOnDeck.opacity(0.5)
            )
            Spacer()
            Button { isConfirmingClear = true } label: {
                Silkscreen(text: "Usuń wszystko", color: DS.Color.inkOnDeck.opacity(0.5))
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
            "Usunąć całą historię chwytów (\(store.grabs.count) "
                + polishPlural(store.grabs.count, one: "zrzut", few: "zrzuty", many: "zrzutów") + ")?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Usuń wszystko", role: .destructive) { GrabLog.clear() }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Tej operacji nie można cofnąć.")
        }
    }
}

private struct GrabRow: View {
    let grab: Grab
    let onDelete: () -> Void

    @State private var didCopy = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            HStack(spacing: DS.Space.snug) {
                Silkscreen(
                    text: grab.languages.map(OCRLanguage.name(for:)).joined(separator: " + "),
                    color: DS.Color.inkOnDeck.opacity(0.7)
                )
                Readout(text: "\(grab.characters) znaków")
                    .foregroundStyle(DS.Color.inkOnDeck.opacity(0.6))
                Spacer()
                Text(grab.date, style: .time)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.inkOnDeck.opacity(0.5))
                copyButton
                deleteButton
                    .opacity(isHovering ? 1 : 0)
            }

            Text(grab.text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkOnDeck)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(8)
        }
        .padding(DS.Space.base)
        .background {
            DeckWindow { Color.clear }
                .opacity(isHovering ? 0.85 : 1)
        }
        .onHover { isHovering = $0 }
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(grab.text, forType: .string)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                didCopy = false
            }
        } label: {
            Silkscreen(
                text: didCopy ? "Skopiowano" : "Kopiuj",
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
        .help("Usuń ten zrzut")
    }
}
