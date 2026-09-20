import AppKit
import Foundation

/// Turning "—" and "–" into "-" — for text being pasted, in whatever flavour the pasteboard
/// holds it (plain, RTF, HTML), without flattening the formatting of rich text.
enum DashTools {
    static func containsLongDash(_ text: String) -> Bool {
        text.contains("—") || text.contains("–")
    }

    static func straighten(_ text: String) -> String {
        text.replacingOccurrences(of: "—", with: "-").replacingOccurrences(of: "–", with: "-")
    }

    private static let plainTypes: Set<String> = [
        "public.utf8-plain-text", "NSStringPboardType", "public.plain-text",
    ]

    /// Rewrites one pasteboard flavour's bytes, or returns `nil` for a type it doesn't
    /// understand (which the caller leaves untouched).
    static func straighten(data: Data, type: NSPasteboard.PasteboardType) -> Data? {
        let raw = type.rawValue
        if plainTypes.contains(raw) {
            return String(data: data, encoding: .utf8).map { straighten($0).data(using: .utf8) } ?? nil
        }
        if raw == "public.utf16-external-plain-text" || raw == "public.utf16-plain-text" {
            return String(data: data, encoding: .utf16).map { straighten($0).data(using: .utf16) } ?? nil
        }
        if type == .rtf {
            guard let attributed = NSMutableAttributedString(rtf: data, documentAttributes: nil) else { return nil }
            let text = attributed.mutableString
            for dash in ["—", "–"] {
                text.replaceOccurrences(of: dash, with: "-", options: [], range: NSRange(location: 0, length: text.length))
            }
            return attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])
        }
        if type == .html {
            guard var html = String(data: data, encoding: .utf8) else { return nil }
            html = straighten(html)
            for entity in ["&mdash;", "&ndash;", "&#8212;", "&#8211;", "&#x2014;", "&#x2013;"] {
                html = html.replacingOccurrences(of: entity, with: "-")
            }
            return html.data(using: .utf8)
        }
        return nil
    }
}
