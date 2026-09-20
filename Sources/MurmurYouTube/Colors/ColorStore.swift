import AppKit
import Foundation
import Observation

struct ColorEntry: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var date: Date
    /// Always normalized `#RRGGBB`; the other notations are derived from it on demand.
    var hex: String

    var color: NSColor { ColorTools.parse(hex) ?? .gray }

    func formatted(_ format: ColorFormat) -> String { ColorTools.format(color, as: format) }
}

/// The colour picker's own history — deliberately separate from the clipboard history.
@MainActor
@Observable
final class ColorStore {
    static let shared = ColorStore()

    private(set) var entries: [ColorEntry] = []

    private let fileURL = RunLog.directory.appendingPathComponent("colors.json")
    private var saveTask: Task<Void, Never>?

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([ColorEntry].self, from: data) {
            entries = decoded
        }
    }

    /// Picking a colour you already have moves it to the top instead of duplicating it.
    func add(hex: String) {
        entries.removeAll { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
        entries.insert(ColorEntry(date: Date(), hex: hex.uppercased()), at: 0)
        trim()
        scheduleSave()
    }

    func delete(_ entry: ColorEntry) {
        entries.removeAll { $0.id == entry.id }
        scheduleSave()
    }

    func clear() {
        entries = []
        scheduleSave()
    }

    func trim() {
        let limit = max(10, Settings.shared.colorMaxItems)
        if entries.count > limit { entries = Array(entries.prefix(limit)) }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            if let data = try? JSONEncoder().encode(self.entries) {
                try? data.write(to: self.fileURL, options: .atomic)
            }
        }
    }
}
