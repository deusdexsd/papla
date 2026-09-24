import Foundation

/// How much punctuation dictated text keeps.
enum PunctuationStyle: String, CaseIterable, Sendable {
    case normal
    /// No period at the very end — the chat "hate period".
    case noFinalPeriod
    /// Chat style: no period at the end and no commas either; `?` and `!` stay.
    case minimal

    @MainActor
    var displayName: String {
        switch self {
        case .normal: t("Normalna", "Normal")
        case .noFinalPeriod: t("Bez kropki na końcu", "No final period")
        case .minimal: t("Minimalna", "Minimal")
        }
    }
}

/// The last pass before translation and insertion. Two independent jobs:
///  - nothing punctuates an emoji or an "XD" — they *are* the end of the thought, so a comma or
///    period right after one is dropped whatever the style;
///  - the chosen `PunctuationStyle`.
enum PunctuationPolish {
    static func apply(to text: String, style: PunctuationStyle) -> String {
        var result = stripAfterEmojiAndXD(text)

        if style == .minimal {
            // Commas go, except inside numbers like 3,5.
            result = result.replacingOccurrences(of: "(?<!\\d),|,(?!\\d)", with: "", options: .regularExpression)
            result = result.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        }
        if style != .normal {
            result = stripFinalPeriod(result)
        }
        return result
    }

    private static func stripFinalPeriod(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex, text[text.index(before: end)].isWhitespace {
            end = text.index(before: end)
        }
        guard end > text.startIndex else { return text }
        let last = text.index(before: end)
        // A lone "." only — "..." is a deliberate ellipsis, not the hate period.
        guard text[last] == ".", last == text.startIndex || text[text.index(before: last)] != "." else { return text }
        return String(text[..<last]) + String(text[end...])
    }

    /// Drops `, . ; : …` sitting directly after an emoji or an XD run (spaces in between are
    /// tolerated). `?` and `!` are kept — they change what the sentence means.
    private static func stripAfterEmojiAndXD(_ text: String) -> String {
        let characters = Array(text)
        var output: [Character] = []
        var index = 0
        var previousWasToken = false

        while index < characters.count {
            let character = characters[index]

            if previousWasToken, ",.;:…".contains(character) {
                index += 1
                continue
            }
            if previousWasToken, character == " ", index + 1 < characters.count,
               ",.;:…".contains(characters[index + 1]) {
                index += 1
                continue
            }

            output.append(character)
            previousWasToken = isEmoji(character) || endsWithXD(output)
            index += 1
        }
        return String(output)
    }

    private static func isEmoji(_ character: Character) -> Bool {
        guard let first = character.unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && character.unicodeScalars.contains { $0.value == 0xFE0F })
    }

    /// "XD", "xd", "XDDD" or "XDXD" as a standalone word.
    private static func endsWithXD(_ output: [Character]) -> Bool {
        guard let last = output.last, last == "D" || last == "d" else { return false }
        var start = output.count
        while start > 0, "xXdD".contains(output[start - 1]) { start -= 1 }
        if start > 0, output[start - 1].isLetter || output[start - 1].isNumber { return false }
        let run = String(output[start...]).lowercased()
        return run.hasPrefix("x") && run.range(of: "^(?:xd+)+$", options: .regularExpression) != nil
    }
}
