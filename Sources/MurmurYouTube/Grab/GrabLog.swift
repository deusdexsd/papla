import Foundation
import Observation

/// One completed grab.
struct Grab: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    let date: Date
    let text: String
    let languages: [String]
    /// How long recognition itself took, from captured image to assembled text. Doesn't
    /// include the time spent dragging the selection — that's user-paced, not a cost of
    /// the app.
    let recognizeSeconds: Double

    var characters: Int { text.count }

    init(
        id: UUID = UUID(),
        date: Date,
        text: String,
        languages: [String],
        recognizeSeconds: Double
    ) {
        self.id = id
        self.date = date
        self.text = text
        self.languages = languages
        self.recognizeSeconds = recognizeSeconds
    }
}

/// Live-updating view of the grab history, backing the main window's own section — kept
/// entirely separate from `RunStore` (dictation's history), per its own file.
@MainActor
@Observable
final class GrabStore {
    static let shared = GrabStore()

    private(set) var grabs: [Grab] = []

    private init() { reload() }

    func reload() {
        grabs = GrabLog.load()
    }
}

/// Appends every grab to a JSONL file, alongside (but separate from) dictation's own
/// `runs.jsonl` — same Application Support folder, since both are Papla's data, different
/// file since they're unrelated histories. Text only, never the captured image: a screen
/// region can easily contain something the user didn't mean to keep around (a password
/// manager, a banking tab); the recognized text is the whole point, the pixels have no
/// reason to outlive the grab that produced them.
@MainActor
enum GrabLog {
    private static var fileURL: URL { RunLog.directory.appendingPathComponent("grabs.jsonl") }

    static func record(_ grab: Grab) {
        append(grab)
        GrabStore.shared.reload()
    }

    private static func append(_ grab: Grab) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(grab) else { return }
        line.append(0x0A)

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: fileURL)
        }
    }

    static func load() -> [Grab] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(Grab.self, from: Data(line))
        }
    }

    static func delete(_ grab: Grab) {
        delete(ids: [grab.id])
    }

    static func delete(ids: Set<UUID>) {
        rewrite(load().filter { !ids.contains($0.id) })
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        GrabStore.shared.reload()
    }

    private static func rewrite(_ grabs: [Grab]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let body = grabs.compactMap { grab -> String? in
            guard let data = try? encoder.encode(grab) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")

        try? (body.isEmpty ? "" : body + "\n")
            .write(to: fileURL, atomically: true, encoding: .utf8)

        GrabStore.shared.reload()
    }
}
