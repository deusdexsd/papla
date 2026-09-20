import Foundation

/// One correction that actually fired, kept so history can show whether the dictionary is
/// earning its place.
public struct AppliedCorrection: Codable, Hashable, Sendable {
    /// The text as the engine produced it.
    public let from: String
    /// What it was rewritten to.
    public let to: String
    /// How many times it fired in this transcript.
    public let count: Int
}

/// Rewrites transcribed text using the dictionary's correction pairs.
///
/// This is the guaranteed half of the dictionary. Engine biasing is a nudge — it raises the
/// odds of the right word and promises nothing — so anything that must be correct has to be
/// fixed here, after the fact, deterministically.
///
/// Three rules, all load-bearing:
///
/// **Longest match first.** "Claude Code" is applied before "Claude", so the longer rule
/// isn't pre-empted by a shorter one that overlaps it.
///
/// **Whole matches only.** Every pattern is fenced by word boundaries, so a rule for
/// "cloud code" can never touch "Cloudflare" or the ordinary word "cloud".
///
/// **Glued words still match.** Engines run words together — "CloudCode", "cloud-code" — so
/// the gap between the parts of a phrase is matched as *optional* whitespace or hyphens
/// rather than a literal space.
public struct DictionaryCorrector: Sendable {
    private let rules: [Rule]

    private struct Rule: Sendable {
        let regex: NSRegularExpression
        let replacement: String
        let trigger: String
    }

    public init(entries: [DictionaryEntry]) {
        // Longest trigger first. Sorting by the trigger's length is what makes "Claude Code"
        // win over "Claude" — once the longer rule has rewritten the span, the shorter one
        // no longer sees the text it would have matched.
        let corrections = entries
            .filter { $0.isEnabled && $0.kind == .correction }
            .filter { !$0.hear.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.hear.count > $1.hear.count }

        rules = corrections.compactMap { entry in
            guard let regex = Self.makeRegex(for: entry.hear) else { return nil }
            return Rule(
                regex: regex,
                replacement: NSRegularExpression.escapedTemplate(for: entry.write),
                trigger: entry.hear
            )
        }
    }

    public var isEmpty: Bool { rules.isEmpty }

    /// Applies every rule in order.
    ///
    /// - Returns: the rewritten text, plus one `AppliedCorrection` per rule that fired.
    public func apply(to text: String) -> (text: String, applied: [AppliedCorrection]) {
        guard !rules.isEmpty, !text.isEmpty else { return (text, []) }

        // Normalize to NFC before matching. macOS hands back decomposed (NFC vs NFD) strings
        // in several places — a filesystem read of the dictionary being the obvious one — and
        // "café" decomposed is five scalars where composed is four. The pattern and the text
        // must be in the same form or an accented trigger silently never matches. The Windows
        // implementation normalizes identically; this is part of the shared contract.
        var result = text.precomposedStringWithCanonicalMapping
        var applied: [AppliedCorrection] = []

        for rule in rules {
            let range = NSRange(result.startIndex..., in: result)
            let matches = rule.regex.numberOfMatches(in: result, range: range)
            guard matches > 0 else { continue }

            // Record what the engine actually produced, not the rule's trigger — seeing the
            // real mishearing is the point, and it can differ from the trigger in case or
            // spacing ("CloudCode" matched by "cloud code").
            let firstMatch = rule.regex.firstMatch(in: result, range: range)
            let heard = firstMatch
                .flatMap { Range($0.range, in: result) }
                .map { String(result[$0]) } ?? rule.trigger

            result = rule.regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: rule.replacement
            )

            applied.append(AppliedCorrection(
                from: heard,
                to: rule.replacement.replacingOccurrences(of: "\\", with: ""),
                count: matches
            ))
        }

        return (result, applied)
    }

    /// Builds the pattern for one trigger phrase.
    ///
    /// The parts are joined with `[\s\-]*` — zero or more spaces or hyphens — which is what
    /// catches "CloudCode" and "Cloud-Code" alongside the spaced form.
    ///
    /// The fences are lookarounds on letters and digits rather than `\b`. `\b` would treat a
    /// trailing hyphen or apostrophe as a boundary and let a rule bite into a longer word;
    /// requiring that no letter or digit sits on either side is the stricter guarantee, and
    /// it's what keeps "cloud code" off "Cloudflare".
    private static func makeRegex(for trigger: String) -> NSRegularExpression? {
        // NFC here too, matching `apply(to:)` — a trigger typed into the UI and a trigger read
        // back from the dictionary file can arrive in different normal forms.
        let parts = trigger
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "\t" })
            .map { NSRegularExpression.escapedPattern(for: String($0)) }

        guard !parts.isEmpty else { return nil }

        let body = parts.joined(separator: "[\\s\\-]*")
        let pattern = "(?<![\\p{L}\\p{N}])\(body)(?![\\p{L}\\p{N}])"

        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}

// MARK: - Engine biasing

public extension DictionaryCorrector {
    /// The phrases to hand the speech engine as context before it transcribes.
    ///
    /// Kept deliberately short. These models drift when given a long context list — on quiet
    /// or ambiguous audio they start inventing text from the vocabulary they were primed
    /// with, which is a far worse failure than the misspelling it was meant to fix.
    public static let biasLimit = 40

    /// - Returns: the correct spellings — `.term` words and the *write* side of corrections —
    ///   most recently useful first, capped at `biasLimit`.
    public static func biasPhrases(from entries: [DictionaryEntry]) -> [String] {
        var seen = Set<String>()
        var phrases: [String] = []

        for entry in entries where entry.isEnabled {
            let phrase = entry.write.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty, seen.insert(phrase.lowercased()).inserted else { continue }
            phrases.append(phrase)
            if phrases.count == biasLimit { break }
        }

        return phrases
    }
}
