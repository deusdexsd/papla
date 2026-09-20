import CoreGraphics
import Foundation

/// Turns Vision's per-line observations into text that reads the way the original did —
/// paragraph breaks preserved, justified hyphenation undone — rather than one line per
/// `\n` regardless of whether the source was a single wrapped sentence or a genuinely new
/// paragraph.
enum TextAssembler {
    static func assemble(_ lines: [OCRLine], joinHyphenated: Bool, straightenDashes: Bool = false) -> String {
        guard !lines.isEmpty else { return "" }

        // Vision's boundingBox origin is bottom-left; reading order is top-to-bottom, so
        // sort by descending y. Ties (rare — genuinely side-by-side text, e.g. columns)
        // fall back to x so a row still reads left-to-right instead of interleaving.
        let sorted = lines.sorted { lhs, rhs in
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.002 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.midX < rhs.boundingBox.midX
        }

        var result = ""
        var previous: OCRLine?

        for line in sorted {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            guard let prev = previous else {
                result = text
                previous = line
                continue
            }

            let gap = prev.boundingBox.minY - line.boundingBox.maxY
            let lineHeight = max(prev.boundingBox.height, line.boundingBox.height, 0.001)
            // A gap comfortably bigger than one line height reads as a blank line in the
            // source (a new paragraph, a UI section break) rather than ordinary line
            // spacing within one paragraph.
            let isParagraphBreak = gap > lineHeight * 0.6

            if isParagraphBreak {
                result += "\n\n" + text
            } else if joinHyphenated, let dehyphenated = joinAcrossHyphen(result, text) {
                result = dehyphenated
            } else {
                result += "\n" + text
            }

            previous = line
        }

        // Collapse anything beyond one blank line — a source with genuinely large gaps
        // (a table, a form) would otherwise produce a ladder of blank lines instead of one.
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        if straightenDashes {
            result = straighten(result)
        }

        return result.precomposedStringWithCanonicalMapping
    }

    /// Em dash ("—", U+2014) and en dash ("–", U+2013) to a plain hyphen. Screenshotted
    /// text — captions, generated copy, chat exports — carries typographic dashes a lot of
    /// plain-text destinations (code, forms, anything monospaced) don't want, and it's the
    /// one visual tell that reads as "this was generated," which is exactly what someone
    /// pasting captured text somewhere else is usually trying to avoid.
    private static func straighten(_ text: String) -> String {
        text.replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
    }

    /// If `current` ends in a hyphen immediately after a letter, and `next` starts with a
    /// lowercase letter, treats it as a word broken across the line wrap and joins them
    /// with no space and no hyphen. Deliberately narrow: a hyphen preceded by whitespace
    /// (a bullet, a minus sign) or followed by an uppercase letter (a new sentence, a
    /// proper noun, an em-dash aside) is left alone rather than mangled.
    private static func joinAcrossHyphen(_ current: String, _ next: String) -> String? {
        guard let last = current.last, last == "-" || last == "\u{00AD}" else { return nil }
        guard current.count >= 2 else { return nil }
        let beforeHyphen = current[current.index(current.endIndex, offsetBy: -2)]
        guard beforeHyphen.isLetter else { return nil }
        guard let first = next.first, first.isLowercase else { return nil }
        return String(current.dropLast()) + next
    }
}
