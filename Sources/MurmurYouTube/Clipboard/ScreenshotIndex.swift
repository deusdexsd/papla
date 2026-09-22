import AppKit
import CryptoKit
import Foundation
import Observation
import UniformTypeIdentifiers

struct ScreenshotEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let path: String
    let date: Date
    let isVideo: Bool
}

/// Screenshots and screen recordings taken with macOS's own capture (⌘⇧3 / ⌘⇧4 / ⌘⇧5),
/// found on disk — Papla doesn't take them, it only lists them so they're searchable next to
/// everything else.
///
/// Recognized by the `kMDItemIsScreenCapture` attribute macOS stamps on every capture, not by
/// file name (which is localized) and not through Spotlight (which may be off or partial).
/// Both the configured capture folder (`defaults read com.apple.screencapture location`) and
/// the Desktop are scanned, because older captures stay wherever they were saved.
///
/// Rescanned when the search opens, not watched in the background: a directory listing is
/// cheap, and there's nothing to keep running between uses.
@MainActor
@Observable
final class ScreenshotIndex {
    static let shared = ScreenshotIndex()

    private(set) var entries: [ScreenshotEntry] = []

    private var hidden: Set<String>
    private var isRefreshing = false
    private let hiddenURL = RunLog.directory.appendingPathComponent("screenshots-hidden.json")

    nonisolated private static let limit = 400

    private init() {
        if let data = try? Data(contentsOf: hiddenURL),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            hidden = Set(paths)
        } else {
            hidden = []
        }
    }

    func refresh() {
        guard Settings.shared.screenshotsEnabled else {
            entries = []
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        let directories = Self.captureDirectories()
        let hiddenPaths = hidden

        Task {
            let found = await Task.detached(priority: .utility) {
                Self.scan(directories: directories).filter { !hiddenPaths.contains($0.path) }
            }.value
            entries = found
            isRefreshing = false
        }
    }

    /// Removes an entry from Papla's list. The file itself is never touched.
    func hide(path: String) {
        hidden.insert(path)
        entries.removeAll { $0.path == path }
        if let data = try? JSONEncoder().encode(Array(hidden)) {
            try? data.write(to: hiddenURL, options: .atomic)
        }
    }

    // MARK: - Scanning

    nonisolated static func captureDirectories() -> [URL] {
        var directories: [URL] = []
        let configured = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        if let configured, !configured.isEmpty {
            directories.append(URL(fileURLWithPath: (configured as NSString).expandingTildeInPath, isDirectory: true))
        }
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        if !directories.contains(desktop) { directories.append(desktop) }
        return directories
    }

    nonisolated private static func scan(directories: [URL]) -> [ScreenshotEntry] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .contentTypeKey, .isRegularFileKey]
        var seen = Set<String>()
        var result: [ScreenshotEntry] = []

        for directory in directories {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let type = values.contentType,
                      type.conforms(to: .image) || type.conforms(to: .movie),
                      isScreenCapture(url),
                      seen.insert(url.path).inserted
                else { continue }

                result.append(ScreenshotEntry(
                    id: stableID(for: url.path),
                    path: url.path,
                    date: values.creationDate ?? values.contentModificationDate ?? .distantPast,
                    isVideo: type.conforms(to: .movie)
                ))
            }
        }
        return Array(result.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// macOS marks every capture with this extended attribute; the name prefixes are only a
    /// fallback for captures that lost it (copied through a service that strips attributes).
    nonisolated private static func isScreenCapture(_ url: URL) -> Bool {
        if getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0 { return true }
        let name = url.lastPathComponent.lowercased()
        // macOS's actual Polish naming is "Nagranie z ekranu …" for recordings — note the
        // "z" — not "Nagranie ekranu". The xattr is the primary signal; these prefixes are
        // only the fallback for files that lost it (e.g. an iCloud-synced Desktop round-trip
        // stripping extended attributes), so they need to match what Finder really writes.
        return ["zrzut ekranu", "nagranie z ekranu", "nagranie ekranu", "screenshot", "screen shot", "screen recording"]
            .contains { name.hasPrefix($0) }
    }

    /// The same file gets the same id on every scan, so a selected row stays selected.
    nonisolated private static func stableID(for path: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data(path.utf8)).prefix(16))
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
        ))
    }
}
