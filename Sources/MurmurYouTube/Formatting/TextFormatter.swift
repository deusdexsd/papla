import Foundation

/// The cleanup pass between raw transcription and injection.
///
/// This is where Wispr Flow actually earns its keep — raw STT output is full of filler
/// words, missing punctuation, and spoken corrections. Swapping in an LLM-backed
/// formatter (Apple Foundation Models on-device, or Claude for the high-quality tier)
/// is the point of keeping this behind a protocol.
protocol TextFormatter: Sendable {
    func format(_ raw: String) async -> String
}

/// Deterministic, zero-latency cleanup. Good enough to be useful on its own and always
/// the fallback when a model-backed formatter is unavailable or times out.
struct RuleBasedFormatter: TextFormatter {
    /// Standalone filler words, stripped only when surrounded by word boundaries.
    ///
    /// Celowo krótka lista — tylko prawdziwe, bezsensowne dźwięki wypełniające. Słowa typu
    /// "no" czy "znaczy" są w polskim za bardzo wieloznaczne (bywają też zwykłą treścią),
    /// więc usuwanie ich na sztywno regexem zjadłoby fragmenty zdań, które ktoś naprawdę
    /// powiedział.
    private static let fillers = ["yyy", "eee", "ee", "yy", "mhm", "hm", "ym"]

    /// Spoken punctuation people actually use mid-dictation. "małe iksde"/"małe eksde" are
    /// checked here, before `applyXDTokens` — a plain "iksde"/"eksde", with or without
    /// repeats, is that function's job (see its doc comment for why "XD" is a literal spoken
    /// token at all, rather than something inferred from tone).
    private static let spokenPunctuation: [(String, String)] = [
        ("nowy akapit", "\n\n"),
        ("nowa linia", "\n"),
        ("otwórz nawias", " ("),
        ("zamknij nawias", ") "),
        ("małe iksde", "xd"),
        ("małe eksde", "xd"),
    ]

    func format(_ raw: String) async -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        text = stripFillers(from: text)
        text = applySpokenPunctuation(to: text)
        text = applyXDTokens(to: text)
        text = collapseWhitespace(in: text)
        text = capitalizeSentences(in: text)
        text = ensureTerminalPunctuation(in: text)

        return text
    }

    /// A swear word alone can't tell a genuinely angry "kurwa" from a joking one, so instead
    /// of guessing tone, "XD" is a literal spoken token: say "iksde" (or "eksde") and it
    /// becomes exactly "XD". The two ways people actually escalate it while typing both work,
    /// because Polish reads "iksde" as the letters X-D one syllable each:
    ///   - Stretch the "de" *within one word* → more D's on one X: "iksdededede" → "XDDDD".
    ///   - Repeat "iksde" as *separate words* → each becomes its own "XD", glued together with
    ///     no space: "iksde iksde" → "XDXD".
    /// Mixing both forms in a row works too ("iksdede iksde" → "XDDXD") — each word is scored
    /// independently by its own length, then the scores are concatenated in order.
    ///
    /// Parakeet treats "iksde" as an ordinary word and sometimes guesses it deserves trailing
    /// punctuation — without consuming that comma here too, "XD" came out as "XD," even at the
    /// end of the utterance. The comma is matched (so it's replaced away) but never counted.
    private func applyXDTokens(to text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(?i)(?:\\b(?:iks|eks)(?:de)+\\b,?[ \\t]*)+")
        else { return text }

        let ns = text as NSString
        var result = text
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))

        for match in matches.reversed() {
            let whole = ns.substring(with: match.range)
            let replacement = whole
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map { token -> String in
                    // "iks"/"eks" are 3 letters, each "de" repeat adds 2 more — counted over
                    // letters only, so a trailing comma swept up by the regex above (or any
                    // other stray punctuation) can't throw the count off.
                    let letterCount = token.filter(\.isLetter).count
                    let dCount = max(1, (letterCount - 3) / 2)
                    return "X" + String(repeating: "D", count: dCount)
                }
                .joined()
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }

    private func stripFillers(from text: String) -> String {
        var result = text
        for filler in Self.fillers {
            // Match the filler as a whole word, plus a trailing comma if the ASR added one.
            let pattern = "(?i)(?<![\\w'])\(filler)\\b,?"
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        return result
    }

    private func applySpokenPunctuation(to text: String) -> String {
        var result = text
        for (phrase, replacement) in Self.spokenPunctuation {
            result = result.replacingOccurrences(
                of: "(?i)\\b\(phrase)\\b",
                with: replacement,
                options: .regularExpression
            )
        }
        return result
    }

    private func collapseWhitespace(in text: String) -> String {
        text
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +([,.!?;:])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func capitalizeSentences(in text: String) -> String {
        var result = ""
        var capitalizeNext = true

        for character in text {
            if capitalizeNext, character.isLetter {
                result.append(Character(character.uppercased()))
                capitalizeNext = false
            } else {
                result.append(character)
                if ".!?\n".contains(character) { capitalizeNext = true }
            }
        }
        return result
    }

    private func ensureTerminalPunctuation(in text: String) -> String {
        guard let last = text.last, last.isLetter || last.isNumber else { return text }
        return text + "."
    }
}

/// No-op formatter, for comparing raw engine output against the cleanup pass.
struct PassthroughFormatter: TextFormatter {
    func format(_ raw: String) async -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
