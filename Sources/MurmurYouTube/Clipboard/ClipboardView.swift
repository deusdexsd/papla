import AppKit
import NaturalLanguage
import SwiftUI

/// The clipboard history: a search field, kind filters, and the list. The same view is the
/// floating panel (`isPanel`, keyboard-driven, closes after an action) and the "Schowek"
/// section of the main window (mouse-first, stays open).
///
/// Colours picked with the eyedropper live in their own history (`ColorStore`), and every
/// dictation in its own (`RunStore`) — both are shown here too, under their own filter chip
/// and "Wszystko", as virtual entries, so this one search bar reaches everything Papla's ever
/// produced instead of needing three separate windows.
struct ClipboardView: View {
    let controller: ClipboardController
    var isPanel = false
    /// A non-interactive live copy inside Ustawienia: never grabs keyboard focus.
    var isPreview = false

    @State private var store = ClipboardStore.shared
    @State private var colorStore = ColorStore.shared
    @State private var screenshots = ScreenshotIndex.shared
    @State private var runStore = RunStore.shared
    @State private var timerStore = TimerStore.shared
    @State private var query = ""
    @State private var filter: ClipboardKind?
    @State private var selection: UUID?
    @State private var flashedID: UUID?
    /// What a row is showing in place of "Skopiowano" while/after a translation — "Tłumaczę…",
    /// or the failure. Success is the ordinary copy flash, so this only ever holds the other two.
    @State private var translateStatus: (id: UUID, text: String)?
    @State private var isConfirmingClear = false
    @FocusState private var searchFocused: Bool

    private var style: PanelStyle { PanelStyle(native: isPanel) }
    private let cornerRadius: CGFloat = PanelStyle.cornerRadius

    private var allItems: [ClipboardItem] {
        let format = Settings.shared.colorFormat
        let picked = colorStore.entries.map { entry in
            ClipboardItem(
                id: entry.id, date: entry.date, kind: .color,
                text: entry.formatted(format), colorHex: entry.hex,
                appName: t("Próbnik kolorów", "Color picker"), fromColorPicker: true
            )
        }
        let captures = screenshots.entries.map { entry in
            ClipboardItem(
                id: entry.id, date: entry.date, kind: .screenshot,
                filePaths: [entry.path],
                appName: entry.isVideo ? t("Nagranie ekranu", "Screen recording") : t("Zrzut ekranu", "Screenshot"),
                fromScreenshot: true, isVideo: entry.isVideo
            )
        }
        let transcriptions = runStore.runs.map { run in
            ClipboardItem(
                id: run.id, date: run.date, kind: .transcription,
                text: run.text, appName: "Papla", fromTranscription: true
            )
        }
        return picked.isEmpty && captures.isEmpty && transcriptions.isEmpty
            ? store.items
            : (store.items + picked + captures + transcriptions).sorted { $0.date > $1.date }
    }

    private var visible: [ClipboardItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleKinds = Settings.shared.clipboardVisibleKinds
        return allItems.filter { item in
            visibleKinds.contains(item.kind)
                && (filter == nil || item.kind == filter)
                && (needle.isEmpty || item.searchableText.prefix(5_000).localizedStandardContains(needle))
        }
    }

    var body: some View {
        let items = visible
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                searchBar
                filterBar
            }
            // The window is only moved from here, so dragging a row can drag the entry out.
            .background { if isPanel { WindowDragArea() } }
            Rectangle().fill(style.hairline).frame(height: 1)

            if items.isEmpty {
                emptyState
            } else {
                list(items)
            }
            footer(count: items.count)
        }
        .background { if !isPanel { DS.Color.deck } }
        .modifier(GlassIfPanel(isPanel: isPanel, radius: cornerRadius))
        .onAppear {
            resetForPresentation()
            screenshots.refresh()
        }
        .onChange(of: controller.presentation) { resetForPresentation() }
        .onChange(of: query) { selection = visible.first?.id }
        .onChange(of: filter) { selection = visible.first?.id }
        .confirmationDialog(
            t(
                "Usunąć całą historię schowka (\(store.items.count) "
                    + polishPlural(store.items.count, one: "element", few: "elementy", many: "elementów") + ")?",
                "Delete the entire clipboard history (\(store.items.count) "
                    + englishPlural(store.items.count, one: "item", other: "items") + ")?"
            ),
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button(t("Usuń wszystko", "Delete all"), role: .destructive) { store.clear() }
            Button(t("Anuluj", "Cancel"), role: .cancel) {}
        } message: {
            Text(t("Tej operacji nie można cofnąć.", "This can't be undone."))
        }
    }

    // MARK: - Pieces

    private var emptyState: some View {
        VStack(spacing: DS.Space.snug) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(style.tertiary)
            Text(allItems.isEmpty
                ? t("Schowek jest pusty", "Clipboard is empty")
                : t("Brak wyników", "No results"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(style.secondary)
            Text(allItems.isEmpty
                ? t("Skopiuj coś (⌘C) — pojawi się tutaj.", "Copy something (⌘C) — it'll show up here.")
                : t("Zmień filtr albo wyszukiwanie.", "Try a different filter or search."))
                .font(DS.Font.label)
                .foregroundStyle(style.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchBar: some View {
        HStack(spacing: DS.Space.base) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(style.secondary)
            TextField(t("Szukaj w schowku…", "Search clipboard…"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(style.primary)
                .focused($searchFocused)
                .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(style.tertiary)
                }
                .buttonStyle(.plain)
            }
            TimerBadge(nextTimer: timerStore.entries.first, style: style) { controller.openTimer() }
        }
        .padding(.horizontal, DS.Space.roomy + 6)
        .padding(.top, DS.Space.roomy + 2)
        .padding(.bottom, DS.Space.roomy)
    }

    private var filterBar: some View {
        GeometryReader { geo in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.snug) {
                FilterChip(title: t("Wszystko", "All"), isOn: filter == nil, style: style) { filter = nil }
                ForEach(ClipboardKind.allCases.filter { Settings.shared.clipboardVisibleKinds.contains($0) }, id: \.self) { kind in
                    FilterChip(title: kind.chipTitle, isOn: filter == kind, style: style) {
                        filter = filter == kind ? nil : kind
                    }
                }
            }
            .padding(.horizontal, DS.Space.roomy + 6)
            .padding(.vertical, 3)
            .frame(minWidth: geo.size.width)
        }
        .scrollClipDisabled()
        }
        .frame(height: 36)
        .padding(.bottom, DS.Space.base - 3)
    }

    private func list(_ items: [ClipboardItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let row = ClipboardRow(
                            item: item,
                            isSelected: selection == item.id,
                            quickIndex: isPanel && index < 9 ? index + 1 : nil,
                            didCopy: flashedID == item.id,
                            statusText: translateStatus?.id == item.id ? translateStatus?.text : nil,
                            style: style,
                            onDelete: { remove(item) }
                        )
                        Group {
                            if canDrag(item) {
                                row.onDrag { beginDrag(item) }
                            } else {
                                row
                            }
                        }
                        .id(item.id)
                        .onTapGesture { selection = item.id; activate(item) }
                        .contextMenu {
                            Button(t("Kopiuj", "Copy")) { copyOnly(item) }
                            if isPanel { Button(t("Wklej", "Paste")) { controller.paste(item) } }
                            if item.text != nil, [.text, .code, .link].contains(item.kind), item.fromTranscription != true {
                                Button(t("Usuń formatowanie", "Remove formatting")) { removeFormatting(item) }
                            }
                            if let direction = translateDirection(for: item) {
                                Button(direction.label) { translate(item, to: direction.target) }
                            }
                            if let path = item.filePaths?.first {
                                Button(t("Pokaż w Finderze", "Show in Finder")) {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                                }
                            }
                            Divider()
                            Button(item.fromScreenshot == true ? t("Ukryj na liście", "Hide from list") : t("Usuń", "Delete"), role: .destructive) { remove(item) }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.snug)
                .padding(.vertical, DS.Space.snug)
            }
            .onChange(of: selection) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) }
            }
        }
    }

    private func footer(count: Int) -> some View {
        HStack(spacing: DS.Space.roomy) {
            Text("\(count) " + t(polishPlural(count, one: "element", few: "elementy", many: "elementów"),
                                  englishPlural(count, one: "item", other: "items")))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(style.secondary)
            Spacer()
            if isPanel {
                hint("↩", t("Kopiuj", "Copy"))
                hint("⌘V", t("Wklej", "Paste"))
                hint("⌘T", t("Tłumacz", "Translate"))
                hint("⌘⌫", t("Usuń", "Delete"))
                Button { controller.openSettings() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(style.secondary)
                }
                .buttonStyle(.plain)
                .help(t("Otwórz Paplę i ustawienia", "Open Papla and settings"))
            } else {
                Button { isConfirmingClear = true } label: {
                    Text(t("Usuń wszystko", "Delete all"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(style.secondary)
                }
                .buttonStyle(.plain)
                .disabled(store.items.isEmpty)
            }
        }
        .padding(.horizontal, DS.Space.roomy + 6)
        .padding(.vertical, DS.Space.base)
        .overlay(alignment: .top) { Rectangle().fill(style.hairline).frame(height: 1) }
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: DS.Space.tight) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(style.primary.opacity(0.75))
            Text(label)
                .font(DS.Font.label)
                .foregroundStyle(style.secondary)
        }
    }

    // MARK: - Actions

    private func resetForPresentation() {
        query = ""
        filter = nil
        selection = allItems.first?.id
        if isPanel && !isPreview { searchFocused = true }
    }

    /// Colour entries live in `ColorStore`, transcriptions in `RunStore`, everything else in
    /// the clipboard's.
    private func remove(_ item: ClipboardItem) {
        if item.fromScreenshot == true {
            if let path = item.filePaths?.first { screenshots.hide(path: path) }
        } else if item.fromColorPicker == true {
            if let entry = colorStore.entries.first(where: { $0.id == item.id }) { colorStore.delete(entry) }
        } else if item.fromTranscription == true {
            if let run = runStore.runs.first(where: { $0.id == item.id }) { RunLog.delete(run) }
        } else {
            store.delete(item)
        }
    }

    /// Enter / click. In the panel: copy and get out of the way. In the window: copy and
    /// flash "Skopiowano" on the row, since nothing closes.
    private func activate(_ item: ClipboardItem) {
        copyOnly(item)
        if isPanel { controller.hidePanel() }
    }

    private func copyOnly(_ item: ClipboardItem) {
        controller.copy(item)
        flashedID = item.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if flashedID == item.id { flashedID = nil }
        }
    }

    /// What translate direction (if any) makes sense for this row: Polish text offers
    /// translating *out*, to `Settings.translateTargetLanguage`; anything else detected as
    /// non-Polish offers translating *in*, to Polish. Only plain text/links (not code — a
    /// language detector on a code snippet is meaningless and false-positives constantly).
    /// Short snippets are skipped — `NLLanguageRecognizer` is unreliable under a few words and
    /// would flicker the menu item between languages on near-identical short copies.
    private func translateDirection(for item: ClipboardItem) -> (label: String, target: Locale.Language)? {
        guard item.kind == .text || item.kind == .link || item.kind == .transcription,
              let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.count >= 12
        else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }

        if language == .polish {
            let target = Settings.shared.translateTargetLanguage
            return (t("Tłumacz na \(target.displayName.lowercased()) i kopiuj",
                       "Translate to \(target.displayName.lowercased()) and copy"),
                     Locale.Language(identifier: target.rawValue))
        }
        return (t("Tłumacz na polski i kopiuj", "Translate to Polish and copy"), Locale.Language(identifier: "pl"))
    }

    /// Translates a copied item and puts the *result* on the clipboard — the original entry is
    /// left untouched. Per `Settings.clipboardTranslateAddsToHistory`, the translation also
    /// gets filed as its own history entry above the original, so it's visible in the panel
    /// rather than only landing invisibly on the pasteboard. `controller.isTranslating` holds
    /// the panel open for the duration — selecting this from the context menu must not close
    /// it before the result is even back.
    private func translate(_ item: ClipboardItem, to target: Locale.Language) {
        guard let text = item.text else { return }
        translateStatus = (item.id, t("Tłumaczę…", "Translating…"))
        controller.isTranslating = true
        Task {
            defer { controller.isTranslating = false }
            do {
                let translated = try await Translator.translate(text, from: nil, to: target)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(translated, forType: .string)
                ClipboardMonitor.shared.adopt()
                if Settings.shared.clipboardTranslateAddsToHistory {
                    store.add(ClipboardItem(date: Date(), kind: .text, text: translated, appName: t("Tłumaczenie", "Translation")))
                }
                translateStatus = nil
                flashedID = item.id
                try? await Task.sleep(for: .seconds(1.2))
                if flashedID == item.id { flashedID = nil }
            } catch {
                Log.app.error("clipboard translate failed: \(String(describing: error), privacy: .public)")
                translateStatus = (item.id, t("Nie udało się przetłumaczyć", "Translation failed"))
                try? await Task.sleep(for: .seconds(3))
                if translateStatus?.id == item.id { translateStatus = nil }
            }
        }
    }

    /// Plain-text copy of an entry: only a bare string goes on the pasteboard (no RTF/HTML
    /// flavors), invisible layout characters are cleaned out, and the result becomes a new
    /// history entry on top — the same way a translation does.
    private func removeFormatting(_ item: ClipboardItem) {
        guard let text = item.text else { return }
        let plain = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "[\\u00A0\\u2007\\u202F]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[\\u200B\\u200C\\u200D\\u2060\\uFEFF]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]+\n", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(plain, forType: .string)
        ClipboardMonitor.shared.adopt()

        let copy = ClipboardItem(
            date: Date(), kind: item.kind, text: plain,
            appName: t("Bez formatowania", "Plain text"), fromPlainText: true
        )
        store.add(copy)
        selection = copy.id
        flashedID = copy.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if flashedID == copy.id { flashedID = nil }
        }
    }

    // MARK: - Dragging out

    /// Images, screenshots, recordings, files and colors can be dragged straight into other
    /// apps. Files go as the file itself (nothing is duplicated — the receiving app copies
    /// it), a color goes as a real color plus its text notation.
    private func canDrag(_ item: ClipboardItem) -> Bool {
        dragProvider(for: item) != nil
    }

    private func beginDrag(_ item: ClipboardItem) -> NSItemProvider {
        controller.isDragging = true
        Task { @MainActor in
            // Hold the panel open until the button is released, then close it like a paste does.
            while NSEvent.pressedMouseButtons & 1 != 0 { try? await Task.sleep(for: .milliseconds(80)) }
            try? await Task.sleep(for: .milliseconds(300))
            controller.isDragging = false
            if isPanel { controller.hidePanel() }
        }
        return dragProvider(for: item) ?? NSItemProvider()
    }

    private func dragProvider(for item: ClipboardItem) -> NSItemProvider? {
        switch item.kind {
        case .color:
            guard let hex = item.colorHex, let color = Self.nsColor(hex: hex) else { return nil }
            let provider = NSItemProvider()
            // The system's own color pasteboard type — what a color well or the color panel
            // drags — so it lands as a color, not text.
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
                provider.registerDataRepresentation(
                    forTypeIdentifier: NSPasteboard.PasteboardType.color.rawValue, visibility: .all
                ) { completion in completion(data, nil); return nil }
            }
            provider.registerObject((item.text ?? hex) as NSString, visibility: .all)
            provider.suggestedName = hex
            return provider
        case .image:
            guard let url = store.imageURL(for: item),
                  FileManager.default.fileExists(atPath: url.path),
                  let provider = NSItemProvider(contentsOf: url) else { return nil }
            provider.suggestedName = t("Obraz ", "Image ")
                + item.date.formatted(.dateTime.year().month().day().hour().minute())
                    .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
            return provider
        case .screenshot, .file:
            guard let path = item.filePaths?.first, FileManager.default.fileExists(atPath: path) else { return nil }
            return NSItemProvider(contentsOf: URL(fileURLWithPath: path))
        default:
            return nil
        }
    }

    private static func nsColor(hex: String) -> NSColor? {
        var value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
    }

    private func move(_ delta: Int) {
        let items = visible
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : items.count)
        selection = items[max(0, min(items.count - 1, current + delta))].id
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let items = visible
        let selected = items.first { $0.id == selection }
        let command = press.modifiers.contains(.command)

        switch press.key {
        case .upArrow: move(-1); return .handled
        case .downArrow: move(1); return .handled
        case .return:
            if let selected { activate(selected) }
            return .handled
        case .escape:
            guard isPanel else { return .ignored }
            controller.hidePanel()
            return .handled
        case .delete where command:
            if let selected {
                move(items.last?.id == selected.id ? -1 : 1)
                remove(selected)
            }
            return .handled
        default: break
        }

        guard isPanel, command else { return .ignored }
        if press.characters == "t", let selected, let direction = translateDirection(for: selected) {
            translate(selected, to: direction.target)
            return .handled
        }
        if press.characters == "v", let selected {
            controller.paste(selected)
            return .handled
        }
        if let digit = Int(press.characters), (1...9).contains(digit), digit <= items.count {
            controller.paste(items[digit - 1])
            return .handled
        }
        return .ignored
    }
}

// MARK: - Row

private struct ClipboardRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let quickIndex: Int?
    let didCopy: Bool
    var statusText: String?
    let style: PanelStyle
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var fileThumbnail: NSImage?

    private static let relativePolish: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.unitsStyle = .short
        return formatter
    }()
    private static let relativeEnglish: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .short
        return formatter
    }()
    /// Follows `Settings.appLanguage` rather than a fixed locale — "5 min ago" shouldn't stay
    /// Polish once the rest of the row around it has switched to English.
    private var relative: RelativeDateTimeFormatter {
        Settings.shared.appLanguage == .english ? Self.relativeEnglish : Self.relativePolish
    }

    /// A natively-styled selected row is the system accent with white text, like any list.
    private var onAccent: Bool { style.native && isSelected }
    private var titleColor: Color { onAccent ? .white : style.primary }
    private var detailColor: Color { onAccent ? .white.opacity(0.75) : style.secondary }

    var body: some View {
        HStack(spacing: DS.Space.base) {
            tile
            VStack(alignment: .leading, spacing: 3) {
                Text(item.headline)
                    .font(item.kind == .code
                        ? .system(size: 13, design: .monospaced)
                        : DS.Font.body)
                    .foregroundStyle(titleColor)
                    .lineLimit(item.kind == .transcription ? 4 : 2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(subtitle)
                    .font(DS.Font.caption)
                    .foregroundStyle(detailColor)
                    .lineLimit(1)
            }
            trailing
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.vertical, DS.Space.snug)
        .background { rowBackground }
        .overlay {
            if isSelected, !style.native {
                RoundedRectangle(cornerRadius: DS.Radius.control)
                    .strokeBorder(style.accent.opacity(0.7), lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .task(id: item.id) {
            // Files, and image files with no stored copy, are previewed straight from disk.
            guard item.kind == .file || item.kind == .screenshot || (item.kind == .image && item.imageFile == nil),
                  let path = item.filePaths?.first else { return }
            fileThumbnail = await ClipboardStore.shared.fileThumbnail(path: path)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        if isSelected {
            shape.fill(style.native ? style.accent : style.accent.opacity(0.16))
        } else if isHovering {
            shape.fill(style.primary.opacity(0.06))
        }
    }

    private var subtitle: String {
        let app = item.appName ?? t("Nieznana aplikacja", "Unknown app")
        let when = relative.localizedString(for: item.date, relativeTo: Date())
        return "\(app) · \(when) · \(item.kindTitle)"
    }

    @ViewBuilder
    private var trailing: some View {
        if let statusText {
            Text(statusText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(onAccent ? .white : style.accent)
        } else if didCopy {
            Text(t("Skopiowano", "Copied"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(onAccent ? .white : style.accent)
        } else if isHovering {
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(detailColor)
            }
            .buttonStyle(.plain)
            .help(t("Usuń z historii", "Remove from history"))
        } else if let quickIndex {
            Text("⌘\(quickIndex)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(onAccent ? .white.opacity(0.6) : style.tertiary)
        }
    }

    // MARK: Thumbnail tile

    private let side: CGFloat = 46

    private var tile: some View {
        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            .fill(style.tile)
            .frame(width: side, height: side)
            .overlay { tileContent }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }

    @ViewBuilder
    private var tileContent: some View {
        switch item.kind {
        case .image:
            if let thumbnail = ClipboardStore.shared.thumbnail(for: item) {
                Image(nsImage: thumbnail).resizable().scaledToFill().frame(width: side, height: side)
            } else if let fileThumbnail {
                Image(nsImage: fileThumbnail).resizable().scaledToFill().frame(width: side, height: side)
            } else {
                symbol
            }
        case .file:
            if let fileThumbnail {
                Image(nsImage: fileThumbnail).resizable().scaledToFit().padding(3)
            } else {
                symbol
            }
        case .screenshot:
            if let fileThumbnail {
                Image(nsImage: fileThumbnail).resizable().scaledToFill().frame(width: side, height: side)
                    .overlay(alignment: .bottomTrailing) {
                        if item.isVideo == true {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white, .black.opacity(0.55))
                                .padding(2)
                        }
                    }
            } else {
                Image(systemName: item.isVideo == true ? "video" : "camera.viewfinder")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(onAccent ? .white : style.accent)
            }
        case .color:
            if let hex = item.colorHex, let color = ColorTools.parse(hex) {
                RoundedRectangle(cornerRadius: DS.Radius.control - 3, style: .continuous)
                    .fill(Color(nsColor: color))
                    .padding(6)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
            } else {
                symbol
            }
        default:
            symbol
        }
    }

    private var symbol: some View {
        Image(systemName: item.kind.symbol)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(onAccent ? .white : style.accent)
    }
}

// MARK: - Chip

private struct FilterChip: View {
    let title: String
    let isOn: Bool
    let style: PanelStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? (style.native ? Color.white : style.primary) : style.primary.opacity(0.75))
                .padding(.horizontal, DS.Space.roomy)
                .padding(.vertical, 7)
                .background(Capsule().fill(isOn ? (style.native ? style.accent : style.accent.opacity(0.2)) : style.chipOff))
                .overlay(Capsule().strokeBorder(isOn && !style.native ? style.accent.opacity(0.8) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}

// MARK: - Timer badge

/// Pinned in the search bar: a bare clock when nothing's running, the soonest countdown once
/// something is — so Minutnik is visible from the panel you actually have open most, instead
/// of only from its own separate shortcut.
private struct TimerBadge: View {
    let nextTimer: TimerEntry?
    let style: PanelStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let nextTimer {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack(spacing: 4) {
                        Image(systemName: nextTimer.isAlarm ? "alarm.fill" : "timer")
                        Text(remaining(nextTimer.fireDate))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                }
            } else {
                Image(systemName: "timer")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(nextTimer == nil ? style.tertiary : style.accent)
        .help(nextTimer == nil
            ? t("Ustaw minutnik", "Set a timer")
            : t("Minutnik działa — kliknij, żeby zobaczyć", "Timer running — click to view"))
    }

    private func remaining(_ fireDate: Date) -> String {
        let seconds = max(0, Int(fireDate.timeIntervalSinceNow))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}


/// Dragging anywhere on this area moves the whole window — the one place the search panel can
/// be moved from, so that dragging a list row means dragging its content instead.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
