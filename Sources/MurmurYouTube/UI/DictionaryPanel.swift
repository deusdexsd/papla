import MurmurDictionary
import AppKit
import SwiftUI

/// The dictionary: add, edit, delete, search.
///
/// Both entry kinds live in one list rather than separate tabs — they're two shapes of the
/// same idea and you want to see everything you've taught it at once. The kind is carried by
/// a silkscreen tag on each row.
struct DictionaryPanel: View {
    @State private var store = DictionaryStore.shared
    @State private var query = ""
    @State private var editing: DictionaryEntry?
    @State private var isAdding = false

    private var entries: [DictionaryEntry] { store.filtered(by: query) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SearchField(text: $query, placeholder: "Szukaj w słowniku")
                addButton
                    .padding(.trailing, DS.Space.base)
                    .background(DS.Color.deck)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.Color.seam).frame(height: DS.Border.seam)
            }

            if entries.isEmpty {
                EmptyPanel(
                    label: store.entries.isEmpty ? "Słownik jest pusty" : "Brak wyników",
                    detail: store.entries.isEmpty
                        ? "Dodaj słowa, które silnik ciągle myli."
                        : "Spróbuj innego wyszukiwania."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.tight) {
                        ForEach(entries) { entry in
                            DictionaryRow(
                                entry: entry,
                                onEdit: { editing = entry },
                                onToggle: {
                                    var updated = entry
                                    updated.isEnabled.toggle()
                                    store.update(updated)
                                },
                                onDelete: { store.delete(entry) }
                            )
                        }
                    }
                    .padding(DS.Space.base)
                }
            }

            footer
        }
        .sheet(isPresented: $isAdding) {
            DictionaryEditor(entry: nil) { store.add($0) }
        }
        .sheet(item: $editing) { entry in
            DictionaryEditor(entry: entry) { store.update($0) }
        }
    }

    private var addButton: some View {
        Button { isAdding = true } label: {
            HStack(spacing: DS.Space.tight) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Silkscreen(text: "Dodaj", color: DS.Color.inkOnDeck)
            }
            .foregroundStyle(DS.Color.inkOnDeck)
            .padding(.horizontal, DS.Space.base)
            .padding(.vertical, DS.Space.snug)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.chip)
                    .strokeBorder(DS.Color.inkOnDeck.opacity(0.35), lineWidth: DS.Border.hairline)
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
    }

    /// The file path is shown because the spec asks for the dictionary to be editable outside
    /// the UI — which is only true if you can find it.
    private var footer: some View {
        HStack(spacing: DS.Space.snug) {
            Silkscreen(
                text: "\(store.entries.count) "
                    + polishPlural(store.entries.count, one: "wpis", few: "wpisy", many: "wpisów"),
                color: DS.Color.inkOnDeck.opacity(0.5)
            )
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
            } label: {
                Silkscreen(text: "Pokaż plik dictionary.txt", color: DS.Color.inkOnDeck.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help(DictionaryStore.fileURL.path)
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.vertical, DS.Space.snug)
        .background(DS.Color.deck)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Color.seam).frame(height: DS.Border.seam)
        }
    }
}

// MARK: - Row

private struct DictionaryRow: View {
    let entry: DictionaryEntry
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DS.Space.base) {
            Lamp(color: DS.Color.statusGood, isLit: entry.isEnabled, size: 6)

            Silkscreen(
                text: entry.kind == .correction ? "Popr." : "Słowo",
                color: DS.Color.inkOnDeck.opacity(0.5)
            )
            .frame(width: 42, alignment: .leading)

            if entry.kind == .correction {
                Text(entry.hear)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkOnDeck.opacity(0.6))
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.Color.inkOnDeck.opacity(0.4))
            }

            Text(entry.write)
                .font(DS.Font.bodyEmphasis)
                .foregroundStyle(DS.Color.inkOnDeck)

            Spacer()

            if isHovering {
                rowButton("Edytuj", action: onEdit)
                rowButton(entry.isEnabled ? "Wyłącz" : "Włącz", action: onToggle)
                rowButton("Usuń", action: onDelete)
            }
        }
        .opacity(entry.isEnabled ? 1 : 0.45)
        .padding(.horizontal, DS.Space.base)
        .padding(.vertical, DS.Space.snug)
        .background(isHovering ? DS.Color.hover : DS.Color.deck, in: .rect(cornerRadius: DS.Radius.chip))
        .onHover { isHovering = $0 }
    }

    private func rowButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Silkscreen(text: title, color: DS.Color.inkOnDeck.opacity(0.6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Editor

/// Add or edit one entry, with the false-positive warning shown live as you type.
///
/// Not `private` — `MainWindow` reuses it for the "add to dictionary" flow launched from a
/// transcription row (pre-filling `hear` with the mis-transcribed text).
struct DictionaryEditor: View {
    let entry: DictionaryEntry?
    let onSave: (DictionaryEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: DictionaryEntry.Kind
    @State private var hear: String
    @State private var write: String

    init(entry: DictionaryEntry?, onSave: @escaping (DictionaryEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _kind = State(initialValue: entry?.kind ?? .term)
        _hear = State(initialValue: entry?.hear ?? "")
        _write = State(initialValue: entry?.write ?? "")
    }

    private var draft: DictionaryEntry {
        DictionaryEntry(
            id: entry?.id ?? UUID(),
            kind: kind,
            write: write.trimmingCharacters(in: .whitespacesAndNewlines),
            hear: kind == .correction ? hear.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            isEnabled: entry?.isEnabled ?? true
        )
    }

    private var warnings: [DictionaryWarning] { DictionaryWarning.check(draft) }

    private var isValid: Bool {
        !draft.write.isEmpty && (kind == .term || !draft.hear.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            Silkscreen(text: entry == nil ? "Nowy wpis" : "Edytuj wpis", large: true)

            kindPicker

            VStack(alignment: .leading, spacing: DS.Space.base) {
                if kind == .correction {
                    field("Kiedy usłyszysz", text: $hear, prompt: "fajnal kat pro")
                }
                field(
                    kind == .correction ? "Napisz" : "Słowo lub fraza",
                    text: $write,
                    prompt: kind == .correction ? "Final Cut Pro" : "Godox"
                )
            }

            ForEach(warnings) { warning in
                HStack(alignment: .top, spacing: DS.Space.snug) {
                    Lamp(color: DS.Color.statusWarning, isLit: true, size: 6)
                        .padding(.top, 3)
                    Text(warning.message)
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DS.Space.snug)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip)
                        .strokeBorder(DS.Color.statusWarning.opacity(0.4), lineWidth: DS.Border.hairline)
                )
            }

            HStack(spacing: DS.Space.snug) {
                Spacer()
                TransportKey(title: "Anuluj") { dismiss() }
                TransportKey(title: "Zapisz", isEngaged: isValid, engagedColor: DS.Color.ink) {
                    guard isValid else { return }
                    onSave(draft)
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
        .padding(DS.Space.panel)
        .frame(width: 460)
        .background(BrushedPanel(radius: DS.Radius.window))
    }

    private var kindPicker: some View {
        HStack(spacing: DS.Space.snug) {
            ForEach([DictionaryEntry.Kind.term, .correction], id: \.self) { candidate in
                TransportKey(
                    title: candidate == .term ? "Słowo" : "Poprawka",
                    isEngaged: kind == candidate,
                    engagedColor: DS.Color.ink
                ) {
                    withAnimation(DS.Motion.panel) { kind = candidate }
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            Silkscreen(text: label)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkOnDeck)
                .padding(.horizontal, DS.Space.snug)
                .padding(.vertical, DS.Space.snug)
                .background(DS.Color.deck, in: .rect(cornerRadius: DS.Radius.chip))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip)
                        .strokeBorder(DS.Color.seam, lineWidth: DS.Border.hairline)
                )
        }
    }
}
