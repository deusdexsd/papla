import Foundation

/// The app's own UI language — independent of the Mac's system language on purpose. A user
/// running macOS in French but wanting Papla itself in English (or vice versa) sets it here,
/// not by changing their whole system.
enum AppLanguage: String, CaseIterable, Sendable {
    case polish
    case english

    var displayName: String {
        switch self {
        case .polish: "Polski"
        case .english: "English"
        }
    }
}

/// Every user-facing string in the app is written as `t("Polish", "English")` at its call
/// site — no separate catalog to keep in sync, no keys to look up, the two literals sit right
/// next to each other so a translation can never silently drift out of date with the string
/// it's translating. Reads `Settings.shared.appLanguage` live, same as any other setting.
@MainActor
func t(_ polish: String, _ english: String) -> String {
    Settings.shared.appLanguage == .english ? english : polish
}

/// The same choice as `t`, readable from any thread — for `LocalizedError.errorDescription` and
/// other nonisolated spots that can't hop to the main actor. Reads the persisted setting
/// directly (English when nothing's been saved yet, matching `Settings`' own default).
func tSync(_ polish: String, _ english: String) -> String {
    UserDefaults.standard.string(forKey: "appLanguage") == "polish" ? polish : english
}

/// English has one plural form where Polish has three (`polishPlural`) — same call shape,
/// used together as `t(polishPlural(n, ...), englishPlural(n, ...))`.
func englishPlural(_ count: Int, one: String, other: String) -> String {
    count == 1 ? one : other
}
