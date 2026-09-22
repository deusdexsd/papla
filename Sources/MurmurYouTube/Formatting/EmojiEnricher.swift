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
    struct Entry: Identifiable, Codable, Equatable, Sendable {
        enum Placement: String, Codable, Sendable {
            /// Right after the trigger word — "kocham ❤️ cię".
            case inline
            /// Always at the end of the sentence the trigger appeared in, regardless of the
            /// `atSentenceEnd` setting — for a *softener*, the emoji is commenting on the whole
            /// clause, not the one word that happened to trip it.
            case sentenceEnd
        }

        var id: String { phrase }
        let phrase: String
        let emoji: String
        var placement: Placement = .inline

        enum CodingKeys: String, CodingKey { case phrase, emoji, placement }

        init(phrase: String, emoji: String, placement: Placement = .inline) {
            self.phrase = phrase
            self.emoji = emoji
            self.placement = placement
        }

        /// Manual conformance so entries saved before `placement` existed still decode —
        /// a missing key just falls back to `.inline`, the old (only) behavior.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            phrase = try container.decode(String.self, forKey: .phrase)
            emoji = try container.decode(String.self, forKey: .emoji)
            placement = try container.decodeIfPresent(Placement.self, forKey: .placement) ?? .inline
        }
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

    /// A tone-softening layer, opt-in via `Settings.emojiSofteningEnabled` — modeled on how
    /// David actually writes to people: a correction, a limitation, or a personal admission
    /// gets one small emoji at the very end of that sentence to take the edge off ("Log
    /// logowi nie równy 😃", "to po Twojej stronie leży przygotowanie pytań 😃", "real
    /// logistical puzzle 😅", "fajniej jest jak... 🙈"). Detecting *tone* rather than *topic*
    /// is inherently fuzzier than the content dictionary above, so treat this as a starting
    /// heuristic — disable individual triggers, or add sharper ones, in Ustawienia.
    static let softeningEntries: [Entry] = [
        // A correction or a stated limitation — "that's not how it works, don't worry".
        Entry(phrase: "nie jest", emoji: "😃", placement: .sentenceEnd),
        Entry(phrase: "nie są", emoji: "😃", placement: .sentenceEnd),
        Entry(phrase: "nie ma", emoji: "😃", placement: .sentenceEnd),
        Entry(phrase: "to nie", emoji: "😃", placement: .sentenceEnd),
        Entry(phrase: "nie musi", emoji: "😃", placement: .sentenceEnd),
        // An expectation placed on the other person.
        Entry(phrase: "po twojej stronie", emoji: "😃", placement: .sentenceEnd),
        Entry(phrase: "musisz", emoji: "😃", placement: .sentenceEnd),
        // Admitting something is genuinely hard — a self-deprecating laugh, not a real "😱".
        Entry(phrase: "wyzwanie", emoji: "😅", placement: .sentenceEnd),
        Entry(phrase: "ciężko", emoji: "😅", placement: .sentenceEnd),
        Entry(phrase: "trudne", emoji: "😅", placement: .sentenceEnd),
        // Thinking out loud / genuinely unsure.
        Entry(phrase: "zastanawiam się", emoji: "🤔", placement: .sentenceEnd),
        Entry(phrase: "nie wiem czy", emoji: "🤔", placement: .sentenceEnd),
        Entry(phrase: "testuję", emoji: "🤔", placement: .sentenceEnd),
        // A personal preference or bias, offered a little shyly.
        Entry(phrase: "fajniej", emoji: "🙈", placement: .sentenceEnd),
        Entry(phrase: "wolałbym", emoji: "🙈", placement: .sentenceEnd),
        Entry(phrase: "wolę", emoji: "🙈", placement: .sentenceEnd),
        // Frustration defused with a laugh rather than left to sting.
        Entry(phrase: "kurwa", emoji: "XD", placement: .sentenceEnd),
        Entry(phrase: "cholera", emoji: "XD", placement: .sentenceEnd),
    ]

    /// - Parameters:
    ///   - text: already-cleaned, already-corrected text — this runs last in the pipeline.
    ///   - intensity: 0…5, from `Settings.emojiIntensity`. 0 short-circuits to a no-op.
    ///   - disabledKeywords: matches on these phrases (built-in or custom) are skipped.
    ///   - customEntries: `Settings.customEmojiEntries` — tried before the built-in table, so
    ///     a custom phrase can shadow a stock one.
    ///   - atSentenceEnd: place the emoji at the end of the sentence the trigger word was in,
    ///     rather than right after the word itself. `softeningEntries` always place at the
    ///     sentence end regardless of this flag — that's the whole point of a softener.
    ///   - suppressPeriod: drop a "." that would otherwise sit immediately next to the emoji.
    ///   - softeningEnabled: also match `softeningEntries` — content keywords still win when
    ///     both a topic word and a softener match the same sentence.
    /// - Returns: `text` with at most `intensity` emoji added, one per sentence, in reading
    ///   order, each trigger phrase matched at most once.
    static func apply(
        to text: String,
        intensity: Int,
        disabledKeywords: Set<String>,
        customEntries: [Entry] = [],
        atSentenceEnd: Bool = false,
        suppressPeriod: Bool = false,
        softeningEnabled: Bool = false
    ) -> String {
        guard intensity > 0, !text.isEmpty else { return text }

        // Custom entries first (so they can shadow a built-in phrase), then content keywords,
        // softeners last (a topic word beats a tone word when both match the same sentence).
        // Longest phrase first within each group so multi-word phrases are tried before a
        // shorter word inside them.
        let candidates = (customEntries.sorted { $0.phrase.count > $1.phrase.count })
            + (entries.sorted { $0.phrase.count > $1.phrase.count })
            + (softeningEnabled ? softeningEntries.sorted { $0.phrase.count > $1.phrase.count } : [])

        var consumed = Set<String>()
        var used = 0
        var output: [String] = []

        for sentence in splitIntoSentences(text) {
            guard used < intensity else { output.append(sentence); continue }

            var chosen: (entry: Entry, matchRange: NSRange)?
            let ns = sentence as NSString
            for entry in candidates {
                guard !disabledKeywords.contains(entry.id), !consumed.contains(entry.phrase) else { continue }
                let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: entry.phrase))\\b"
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: sentence, range: NSRange(location: 0, length: ns.length))
                else { continue }
                chosen = (entry, match.range)
                break
            }

            guard let (entry, matchRange) = chosen else {
                output.append(sentence)
                continue
            }
            consumed.insert(entry.phrase)
            used += 1
            output.append(insert(
                entry.emoji, into: sentence, matchRange: matchRange,
                atSentenceEnd: atSentenceEnd || entry.placement == .sentenceEnd,
                suppressPeriod: suppressPeriod
            ))
        }

        return output.joined()
    }

    // MARK: - Sentence splitting

    /// A rough, regex-based split that keeps each sentence's own terminator and trailing
    /// whitespace attached, so rejoining the pieces reproduces the original text exactly.
    /// Not real NLP sentence detection — good enough for "where does this clause end".
    private static func splitIntoSentences(_ text: String) -> [String] {
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern: "[^.!?\\n]+[.!?]*\\s*|\\n+") else { return [text] }
        var result: [String] = []
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            result.append(ns.substring(with: match.range))
        }
        return result.isEmpty ? [text] : result
    }

    // MARK: - Insertion

    private static func insert(
        _ emoji: String, into sentence: String, matchRange: NSRange,
        atSentenceEnd: Bool, suppressPeriod: Bool
    ) -> String {
        let ns = sentence as NSString

        if atSentenceEnd {
            var end = ns.length
            var trailingWhitespace = ""
            while end > 0, let scalar = Unicode.Scalar(ns.character(at: end - 1)),
                  CharacterSet.whitespacesAndNewlines.contains(scalar) {
                trailingWhitespace = ns.substring(with: NSRange(location: end - 1, length: 1)) + trailingWhitespace
                end -= 1
            }
            if suppressPeriod, end > 0, ns.character(at: end - 1) == 46 /* "." */ {
                end -= 1
            }
            return ns.substring(to: end) + " " + emoji + trailingWhitespace
        }

        let insertAt = matchRange.location + matchRange.length
        var tailStart = insertAt
        if suppressPeriod, insertAt < ns.length, ns.character(at: insertAt) == 46 {
            tailStart = insertAt + 1
        }
        return ns.substring(to: insertAt) + " " + emoji + ns.substring(from: tailStart)
    }
}
