import Foundation

/// Adds emoji to dictated text, deliberately by a **fixed lookup table**, not a model. David
/// tried an LLM for dictation cleanup once (Bielik, via MLX) and pulled it out the same day —
/// "totalnie źle działa, bardziej przeszkadza niż pomaga". Emoji placement has exactly the
/// same failure mode (surprising, unpredictable, un-debuggable), so this stays a keyword
/// dictionary on purpose: every insertion traces back to one matched word, is instant, and
/// never varies between two identical utterances.
enum EmojiEnricher {
    /// One matchable phrase and the emoji it adds. Phrases are Polish, lower-case, matched as
    /// whole words (so "kotek" doesn't fire on "kotelnia"). `id` is what `Settings.
    /// emojiDisabledKeywords` stores — stable even if the emoji itself is ever swapped.
    struct Entry: Identifiable, Sendable {
        var id: String { phrase }
        let phrase: String
        let emoji: String
    }

    /// Ordered roughly by how often each would actually come up in speech — not that it
    /// matters for matching, only for `entries` being pleasant to scroll in Ustawienia.
    static let entries: [Entry] = [
        Entry(phrase: "kocham", emoji: "❤️"),
        Entry(phrase: "uwielbiam", emoji: "😍"),
        Entry(phrase: "super", emoji: "🎉"),
        Entry(phrase: "świetnie", emoji: "🎉"),
        Entry(phrase: "extra", emoji: "🔥"),
        Entry(phrase: "genialne", emoji: "🔥"),
        Entry(phrase: "haha", emoji: "😂"),
        Entry(phrase: "śmieszne", emoji: "😂"),
        Entry(phrase: "zabawne", emoji: "😂"),
        Entry(phrase: "dziękuję", emoji: "🙏"),
        Entry(phrase: "dzięki", emoji: "🙏"),
        Entry(phrase: "proszę", emoji: "🙏"),
        Entry(phrase: "gratulacje", emoji: "🎉"),
        Entry(phrase: "urodziny", emoji: "🎂"),
        Entry(phrase: "smutne", emoji: "😢"),
        Entry(phrase: "przykro mi", emoji: "😢"),
        Entry(phrase: "płaczę", emoji: "😢"),
        Entry(phrase: "zmęczony", emoji: "😴"),
        Entry(phrase: "zmęczona", emoji: "😴"),
        Entry(phrase: "śpię", emoji: "😴"),
        Entry(phrase: "wkurzony", emoji: "😠"),
        Entry(phrase: "wkurzona", emoji: "😠"),
        Entry(phrase: "zły", emoji: "😠"),
        Entry(phrase: "przestraszony", emoji: "😱"),
        Entry(phrase: "szok", emoji: "😱"),
        Entry(phrase: "kawa", emoji: "☕️"),
        Entry(phrase: "herbata", emoji: "🍵"),
        Entry(phrase: "piwo", emoji: "🍺"),
        Entry(phrase: "wino", emoji: "🍷"),
        Entry(phrase: "jedzenie", emoji: "🍽️"),
        Entry(phrase: "pizza", emoji: "🍕"),
        Entry(phrase: "obiad", emoji: "🍽️"),
        Entry(phrase: "słońce", emoji: "☀️"),
        Entry(phrase: "deszcz", emoji: "🌧️"),
        Entry(phrase: "śnieg", emoji: "❄️"),
        Entry(phrase: "impreza", emoji: "🎉"),
        Entry(phrase: "urlop", emoji: "🏖️"),
        Entry(phrase: "wakacje", emoji: "🏖️"),
        Entry(phrase: "podróż", emoji: "✈️"),
        Entry(phrase: "samochód", emoji: "🚗"),
        Entry(phrase: "praca", emoji: "💼"),
        Entry(phrase: "pieniądze", emoji: "💰"),
        Entry(phrase: "muzyka", emoji: "🎵"),
        Entry(phrase: "film", emoji: "🎬"),
        Entry(phrase: "książka", emoji: "📚"),
        Entry(phrase: "pomysł", emoji: "💡"),
        Entry(phrase: "uwaga", emoji: "⚠️"),
        Entry(phrase: "ważne", emoji: "❗️"),
        Entry(phrase: "pilne", emoji: "🚨"),
        Entry(phrase: "spotkanie", emoji: "📅"),
        Entry(phrase: "termin", emoji: "⏰"),
        Entry(phrase: "gotowe", emoji: "✅"),
        Entry(phrase: "zrobione", emoji: "✅"),
        Entry(phrase: "błąd", emoji: "❌"),
        Entry(phrase: "problem", emoji: "❌"),
        Entry(phrase: "pies", emoji: "🐶"),
        Entry(phrase: "kot", emoji: "🐱"),
        Entry(phrase: "dziecko", emoji: "👶"),
        Entry(phrase: "serce", emoji: "❤️"),
        Entry(phrase: "gwiazda", emoji: "⭐️"),
    ]

    /// Longest phrase first, so "przykro mi" is tried before a stray "mi" could ever matter
    /// (it can't, "mi" isn't in the table — but any future two-word entry gets this for free).
    private static let sortedEntries = entries.sorted { $0.phrase.count > $1.phrase.count }

    /// - Parameters:
    ///   - text: already-cleaned, already-corrected text — this runs last in the pipeline.
    ///   - intensity: 0…5, from `Settings.emojiIntensity`. 0 short-circuits to a no-op so the
    ///     default (off) costs nothing.
    ///   - disabledKeywords: `Settings.emojiDisabledKeywords` — matches on these phrases are
    ///     skipped, the word itself is left exactly as dictated.
    /// - Returns: `text` with at most `intensity` emoji appended after their matched words, in
    ///   reading order, each word matched at most once.
    static func apply(to text: String, intensity: Int, disabledKeywords: Set<String>) -> String {
        guard intensity > 0, !text.isEmpty else { return text }

        var result = text
        var insertions = 0
        var consumed = Set<String>() // lower-cased phrases already matched once

        for entry in sortedEntries {
            guard insertions < intensity else { break }
            guard !disabledKeywords.contains(entry.id), !consumed.contains(entry.phrase) else { continue }

            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: entry.phrase))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsResult = result as NSString
            guard let match = regex.firstMatch(in: result, range: NSRange(location: 0, length: nsResult.length))
            else { continue }

            let insertAt = match.range.location + match.range.length
            let emojiText = " " + entry.emoji
            result = nsResult.replacingCharacters(in: NSRange(location: insertAt, length: 0), with: emojiText)
            insertions += 1
            consumed.insert(entry.phrase)
        }

        return result
    }
}
