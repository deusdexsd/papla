import AppKit
import CryptoKit
import Foundation
import ImageIO
import Observation
import QuickLookThumbnailing

enum ClipboardKind: String, Codable, CaseIterable, Sendable {
    case text, link, image, screenshot, color, code, file, transcription

    /// Plural, for the filter chips.
    @MainActor
    var chipTitle: String {
        switch self {
        case .text: t("Tekst", "Text")
        case .link: t("Linki", "Links")
        case .image: t("Obrazy", "Images")
        case .screenshot: t("Zrzuty", "Screenshots")
        case .color: t("Kolory", "Colors")
        case .code: t("Kod", "Code")
        case .file: t("Pliki", "Files")
        case .transcription: t("Transkrypcje", "Transcriptions")
        }
    }

    /// Singular, for a row's subtitle.
    @MainActor
    var title: String {
        switch self {
        case .text: t("Tekst", "Text")
        case .link: t("Link", "Link")
        case .image: t("Obraz", "Image")
        case .screenshot: t("Zrzut", "Screenshot")
        case .color: t("Kolor", "Color")
        case .code: t("Kod", "Code")
        case .file: t("Plik", "File")
        case .transcription: t("Transkrypcja", "Transcription")
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .screenshot: "camera.viewfinder"
        case .color: "paintpalette"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .file: "doc"
        case .transcription: "waveform"
        }
    }
}

struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var date: Date
    var kind: ClipboardKind

    /// Text, link, code — and for a colour, the string as it was copied or picked.
    var text: String?
    /// A colour's normalized `#RRGGBB`, used for the swatch whatever notation `text` is in.
    var colorHex: String?
    var imageFile: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var filePaths: [String]?
    var appName: String?
    var bundleID: String?

    /// What "the same thing copied twice" means, per kind — a second copy of an identical
    /// item moves the old one to the top instead of stacking duplicates.
    var signature: String {
        switch kind {
        case .text, .link, .code: "t:" + (text ?? "")
        case .color: "c:" + (colorHex ?? text ?? "")
        case .image: "i:" + (imageDigest ?? id.uuidString)
        case .file: "f:" + (filePaths ?? []).joined(separator: "\n")
        case .screenshot: "s:" + (filePaths ?? []).joined(separator: "\n")
        // Never inserted through `ClipboardStore.add`, so this is never actually compared —
        // the id alone (unique per `DictationRun`) is enough to satisfy the switch.
        case .transcription: "r:" + id.uuidString
        }
    }

    var imageDigest: String?

    /// Set only on the virtual entries the search panel builds from `ColorStore`, so copying
    /// and deleting them are routed to the colour history instead of the clipboard's.
    var fromColorPicker: Bool?

    /// Likewise for entries built from `ScreenshotIndex` — the file is the source of truth.
    var fromScreenshot: Bool?
    var isVideo: Bool?

    /// Likewise for entries built from `RunStore` (dictation history) — copying and deleting
    /// route to `RunLog` instead of the clipboard's.
    var fromTranscription: Bool?

    /// "Nagranie" for a screen recording, otherwise the kind's own name.
    @MainActor
    var kindTitle: String { kind == .screenshot && isVideo == true ? t("Nagranie", "Recording") : kind.title }

    /// Everything the search field matches against.
    var searchableText: String {
        switch kind {
        case .text, .link, .code, .transcription: text ?? ""
        case .color: [text, colorHex].compactMap { $0 }.joined(separator: " ")
        case .file: (filePaths ?? []).map { ($0 as NSString).lastPathComponent }.joined(separator: " ")
        case .screenshot:
            (isVideo == true ? "nagranie wideo film ekranu " : "zrzut ekranu obraz ")
                + (filePaths ?? []).map { ($0 as NSString).lastPathComponent }.joined(separator: " ")
        case .image:
            "obraz zrzut " + (filePaths ?? []).map { ($0 as NSString).lastPathComponent }.joined(separator: " ")
        }
    }

    /// The row's main line.
    @MainActor
    var headline: String {
        switch kind {
        case .text, .link, .code, .transcription:
            (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case .color:
            text ?? colorHex ?? ""
        case .file, .screenshot:
            (filePaths ?? []).map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        case .image:
            if let paths = filePaths, !paths.isEmpty {
                paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            } else {
                t("Obraz", "Image") + " \(imageWidth ?? 0) × \(imageHeight ?? 0)"
            }
        }
    }
}

/// The clipboard history. Newest first.
///
/// One JSON file for the metadata plus one PNG per image, both under the same Application
/// Support folder as the dictation and grab histories (never `~/Desktop`, which iCloud syncs).
@MainActor
@Observable
final class ClipboardStore {
    static let shared = ClipboardStore()

    private(set) var items: [ClipboardItem] = []

    private let fileURL = RunLog.directory.appendingPathComponent("clipboard.json")
    private let imagesDirectory = RunLog.directory.appendingPathComponent("ClipboardImages", isDirectory: true)
    private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let thumbnails = NSCache<NSString, NSImage>()

    private init() {
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            items = decoded
        }
    }

    // MARK: - Mutation

    func add(_ item: ClipboardItem) {
        // Same content copied again → drop the old entry (and its image file, unless the new
        // item reuses it) so the fresh one lands on top with the current time and app.
        let duplicates = items.filter { $0.signature == item.signature }
        items.removeAll { $0.signature == item.signature }
        for old in duplicates where old.imageFile != item.imageFile { deleteImageFile(of: old) }

        items.insert(item, at: 0)
        trim()
        scheduleSave()
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        deleteImageFile(of: item)
        scheduleSave()
    }

    func clear() {
        items.forEach(deleteImageFile(of:))
        items = []
        scheduleSave()
    }

    func trim() {
        let limit = max(20, Settings.shared.clipboardMaxItems)
        guard items.count > limit else { return }
        items.suffix(from: limit).forEach(deleteImageFile(of:))
        items = Array(items.prefix(limit))
    }

    // MARK: - Images

    /// Writes PNG data for a new image item and returns the file name to store on it.
    func saveImage(_ png: Data) -> String? {
        let name = UUID().uuidString + ".png"
        do {
            try png.write(to: imagesDirectory.appendingPathComponent(name))
            return name
        } catch {
            Log.app.error("clipboard: couldn't save image — \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        item.imageFile.map { imagesDirectory.appendingPathComponent($0) }
    }

    /// A small decoded thumbnail — decoding a full-resolution screenshot for every row on
    /// every redraw would make the list crawl.
    func thumbnail(for item: ClipboardItem) -> NSImage? {
        guard let url = imageURL(for: item) else { return nil }
        let key = url.lastPathComponent as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 160,
              ] as CFDictionary)
        else { return nil }

        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnails.setObject(image, forKey: key)
        return image
    }

    @ObservationIgnored private let fileThumbnails = NSCache<NSString, NSImage>()

    /// A real preview of a file — QuickLook renders PDFs, videos, documents, images and so on
    /// the same way Finder does; the plain file icon is the fallback.
    func fileThumbnail(path: String) async -> NSImage? {
        let key = path as NSString
        if let cached = fileThumbnails.object(forKey: key) { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: CGSize(width: 96, height: 96),
            scale: 2,
            representationTypes: .all
        )
        let image: NSImage
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            image = representation.nsImage
        } else {
            image = NSWorkspace.shared.icon(forFile: path)
        }
        fileThumbnails.setObject(image, forKey: key)
        return image
    }

    private func deleteImageFile(of item: ClipboardItem) {
        guard let url = imageURL(for: item) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Persistence

    /// Debounced: a burst of copies (or a big delete) writes once, not once per change.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            if let data = try? JSONEncoder().encode(self.items) {
                try? data.write(to: self.fileURL, options: .atomic)
            }
        }
    }
}
