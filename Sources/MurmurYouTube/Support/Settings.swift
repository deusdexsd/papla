import Foundation
import Observation
import SwiftUI

/// Which edge of the screen the floating orb hugs — shared by dictation's HUD and the
/// grab-text HUD, since there's no reason the two would want to live in different spots.
enum HUDPosition: String, CaseIterable, Sendable {
    case top, bottom, left, right

    @MainActor
    var displayName: String {
        switch self {
        case .top: t("Góra", "Top")
        case .bottom: t("Dół", "Bottom")
        case .left: t("Lewo", "Left")
        case .right: t("Prawo", "Right")
        }
    }
}

/// How the trigger key starts and stops a recording.
enum DictationTriggerMode: String, CaseIterable, Sendable {
    /// Classic push-to-talk: down starts, up stops. You must keep the key held the whole
    /// time you're speaking.
    case hold
    /// One tap starts, a second tap stops — the key can be released in between. Better for
    /// longer dictations where holding a modifier the whole time is uncomfortable.
    case toggle

    @MainActor
    var displayName: String {
        switch self {
        case .hold: t("Przytrzymaj", "Hold")
        case .toggle: t("Przełącznik", "Toggle")
        }
    }

    @MainActor
    var note: String {
        switch self {
        case .hold: t("Trzymasz klawisz i mówisz — puszczasz, żeby skończyć.",
                       "Hold the key and speak — release it to finish.")
        case .toggle: t("Naciskasz raz, żeby zacząć, drugi raz, żeby skończyć. "
                + "Klawisz możesz puścić w trakcie mówienia.",
                "Press once to start, again to finish. You can let go of "
                + "the key in between — no need to hold it while you speak.")
        }
    }
}

/// A language Papla can translate dictated or copied text into. Polish is always the
/// source — these are the fixed set of targets exposed in Ustawienia, a curated subset of
/// what Apple's on-device Translation framework actually supports (its full catalogue is
/// much longer, but a bounded picker beats a giant unlabeled list).
enum TranslateLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case italian = "it"
    case ukrainian = "uk"
    case portuguese = "pt"

    @MainActor
    var displayName: String {
        switch self {
        case .english: t("Angielski", "English")
        case .german: t("Niemiecki", "German")
        case .spanish: t("Hiszpański", "Spanish")
        case .french: t("Francuski", "French")
        case .italian: t("Włoski", "Italian")
        case .ukrainian: t("Ukraiński", "Ukrainian")
        case .portuguese: t("Portugalski", "Portuguese")
        }
    }
}

/// The dictation indicator's shape — shown in the HUD, the main window's level meter, and
/// the grab HUD, wherever `VisualizerView` is used.
enum HUDVisualizerStyle: String, CaseIterable, Sendable {
    case orb
    /// A scrolling row of mirrored bars reacting to mic level — a modern equalizer look,
    /// closer to Tesla's own voice-command visualizer than a soft glowing sphere.
    case waveform

    @MainActor
    var displayName: String {
        switch self {
        case .orb: t("Kula", "Orb")
        case .waveform: t("Fala", "Waveform")
        }
    }
}

/// The glyph in the menu bar — five to pick from, each with a "lit" variant shown while
/// dictating.
enum MenuBarIconStyle: String, CaseIterable, Sendable {
    case orb, wave, mic, bubble, spark

    var symbol: String { symbol(active: false) }

    func symbol(active: Bool) -> String {
        switch self {
        case .orb: active ? "circle.hexagongrid.fill" : "circle.hexagongrid"
        case .wave: active ? "waveform.circle.fill" : "waveform"
        case .mic: active ? "mic.fill" : "mic"
        case .bubble: active ? "text.bubble.fill" : "text.bubble"
        case .spark: active ? "sparkles" : "sparkle"
        }
    }

    @MainActor
    var displayName: String {
        switch self {
        case .orb: t("Kula", "Orb")
        case .wave: t("Fala", "Wave")
        case .mic: t("Mikrofon", "Microphone")
        case .bubble: t("Dymek", "Bubble")
        case .spark: t("Iskra", "Spark")
        }
    }
}

/// Light / dark / follow-the-system for the floating search panel.
enum PanelAppearance: String, CaseIterable, Sendable {
    case system, light, dark

    @MainActor
    var displayName: String {
        switch self {
        case .system: t("Systemowy", "System")
        case .light: t("Jasny", "Light")
        case .dark: t("Ciemny", "Dark")
        }
    }

    /// `nil` means "inherit" — the panel then tracks the system's light/dark setting live.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// A plain, Codable RGB triple — `SwiftUI.Color` itself isn't reliably `Codable` across
/// macOS versions, and this is the one thing about a color `UserDefaults` actually needs to
/// hold onto. `sRGB`, not device RGB: it has to round-trip the exact same value regardless
/// of which display extracted it.
struct RGBColor: Codable, Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Extracts sRGB components from any `Color` the system hands back (a `ColorPicker`
    /// binding, for instance) via `NSColor`, which — unlike `Color` itself — has a
    /// straightforward, always-available component accessor.
    init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        r = Double(resolved.redComponent)
        g = Double(resolved.greenComponent)
        b = Double(resolved.blueComponent)
    }
}

/// A curated slice of the system sound library (`/System/Library/Sounds`) — every macOS
/// install ships all of these, so there's nothing to bundle or download.
enum SystemSound: String, CaseIterable, Sendable {
    case tink = "Tink"
    case pop = "Pop"
    case glass = "Glass"
    case ping = "Ping"
    case purr = "Purr"
    case submarine = "Submarine"
    case bottle = "Bottle"
    case blow = "Blow"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case sosumi = "Sosumi"
    case basso = "Basso"

    var displayName: String { rawValue }
}

@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    /// Every key here must be held down together to trigger dictation. Never empty —
    /// setting it to `[]` is refused, falling back to whatever it was before. Ignored
    /// entirely while `customShortcut` is set — that takes over as the trigger.
    var triggerKeys: Set<PushToTalkKey> {
        didSet {
            guard !triggerKeys.isEmpty else {
                triggerKeys = oldValue
                return
            }
            defaults.set(triggerKeys.map(\.rawValue), forKey: Keys.triggerKeys)
        }
    }

    /// A recorded "modifiers + one key" combo (⌘⌥[, F13, …), for when the fixed set of
    /// modifier-only keys isn't the key you actually want. Takes priority over
    /// `triggerKeys` whenever it's set; `nil` falls back to the modifier-only picker.
    var customShortcut: CustomShortcut? {
        didSet { encode(customShortcut, forKey: Keys.customShortcut) }
    }

    var triggerMode: DictationTriggerMode {
        didSet { defaults.set(triggerMode.rawValue, forKey: Keys.triggerMode) }
    }

    /// Run the cleanup pass before injecting. Off = raw engine output.
    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Keys.cleanupEnabled) }
    }

    // MARK: Tłumaczenie

    /// A second, independent trigger next to normal dictation: hold/toggle it instead, and
    /// the finished utterance is translated before it's injected — everything else about the
    /// recording (cleanup, dictionary, emoji) runs exactly the same first.
    var translateShortcut: CustomShortcut {
        didSet { encode(translateShortcut, forKey: Keys.translateShortcut) }
    }

    var translateTargetLanguage: TranslateLanguage {
        didSet { defaults.set(translateTargetLanguage.rawValue, forKey: Keys.translateTargetLanguage) }
    }

    // MARK: Emoji

    /// 0 = never add emoji (default). 1…5 = how freely `EmojiEnricher` inserts them — higher
    /// allows more matches through per utterance, it does not change *which* emoji a word
    /// maps to (that's the fixed dictionary).
    var emojiIntensity: Int {
        didSet {
            let clamped = emojiIntensity.clamped(0, 5)
            if clamped != emojiIntensity { emojiIntensity = clamped; return }
            defaults.set(emojiIntensity, forKey: Keys.emojiIntensity)
        }
    }

    /// Dictionary keywords (see `EmojiEnricher.entries`) the user turned off — their emoji is
    /// never inserted even at max intensity, but the trigger word is left untouched otherwise.
    var emojiDisabledKeywords: Set<String> {
        didSet { defaults.set(Array(emojiDisabledKeywords), forKey: Keys.emojiDisabledKeywords) }
    }

    /// Off (default): the emoji lands right after the word that triggered it. On: it moves to
    /// the end of the sentence that word appeared in — closer to how people actually text.
    var emojiAtSentenceEnd: Bool {
        didSet { defaults.set(emojiAtSentenceEnd, forKey: Keys.emojiAtSentenceEnd) }
    }

    /// When an emoji lands right where a "." would otherwise be — the end of a sentence, or a
    /// trigger word that was itself the last word — this drops that period instead of leaving
    /// both. "Emoji to tak naprawdę jest zamiast kropki."
    var emojiSuppressPeriod: Bool {
        didSet { defaults.set(emojiSuppressPeriod, forKey: Keys.emojiSuppressPeriod) }
    }

    /// User-added phrase→emoji pairs, tried before the built-in dictionary (so a custom entry
    /// can override a stock one by reusing its phrase).
    var customEmojiEntries: [EmojiEnricher.Entry] {
        didSet { encode(customEmojiEntries, forKey: Keys.customEmojiEntries) }
    }

    /// Off (default): only the content dictionary above. On: also matches
    /// `EmojiEnricher.softeningEntries` — a corrective, a limitation, or a personal admission
    /// gets a soft emoji at the end of that sentence, the way David actually writes to people.
    var emojiSofteningEnabled: Bool {
        didSet { defaults.set(emojiSofteningEnabled, forKey: Keys.emojiSofteningEnabled) }
    }

    // MARK: Sound

    /// Master on/off for both the dictation tick and the grab chime.
    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    /// 0…1. `NSSound.volume` is per-instance, not global, so this is applied to every sound
    /// right before it plays rather than being a system setting anywhere.
    var soundVolume: Double {
        didSet { defaults.set(soundVolume, forKey: Keys.soundVolume) }
    }

    /// Played when a recording/grab starts.
    var soundStart: SystemSound {
        didSet { defaults.set(soundStart.rawValue, forKey: Keys.soundStart) }
    }

    /// Played when it finishes successfully.
    var soundEnd: SystemSound {
        didSet { defaults.set(soundEnd.rawValue, forKey: Keys.soundEnd) }
    }

    // MARK: HUD

    /// Which edge of the screen the floating orb parks against.
    var hudPosition: HUDPosition {
        didSet { defaults.set(hudPosition.rawValue, forKey: Keys.hudPosition) }
    }

    /// Distance from that edge, in points.
    var hudMargin: Double {
        didSet { defaults.set(hudMargin, forKey: Keys.hudMargin) }
    }

    /// How far the orb's three blobs fork outward as energy (mic level, or a working state)
    /// rises — "rozpiętość" in Ustawienia. Low keeps it a tight, calm ball even shouting;
    /// high forks it wide open on a whisper. Multiplies the same term that used to be a
    /// fixed `0.7` in `SiriOrb`.
    var orbSpread: Double {
        didSet { defaults.set(orbSpread, forKey: Keys.orbSpread) }
    }

    /// Which shape the dictation indicator draws as — the orb everywhere it's shown (HUD,
    /// the main window's level meter, the grab HUD).
    var hudVisualizerStyle: HUDVisualizerStyle {
        didSet { defaults.set(hudVisualizerStyle.rawValue, forKey: Keys.hudVisualizerStyle) }
    }

    /// The app's own UI language (see `AppLanguage`) — independent of the Mac's system
    /// language, and of what language you dictate or translate into.
    var appLanguage: AppLanguage {
        didSet { defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage) }
    }

    /// First-run guide and the "co jest co" tour each show once; both can be replayed.
    var onboardingDone: Bool {
        didSet { defaults.set(onboardingDone, forKey: Keys.onboardingDone) }
    }

    var tourDone: Bool {
        didSet { defaults.set(tourDone, forKey: Keys.tourDone) }
    }

    var speechModel: SpeechModel {
        didSet { defaults.set(speechModel.rawValue, forKey: SpeechModel.defaultsKey) }
    }

    var punctuationStyle: PunctuationStyle {
        didSet { defaults.set(punctuationStyle.rawValue, forKey: Keys.punctuationStyle) }
    }

    var menuBarIconStyle: MenuBarIconStyle {
        didSet { defaults.set(menuBarIconStyle.rawValue, forKey: Keys.menuBarIconStyle) }
    }

    // MARK: Colors

    var accentPrimary: RGBColor {
        didSet { encode(accentPrimary, forKey: Keys.accentPrimary) }
    }
    var accentSecondary: RGBColor {
        didSet { encode(accentSecondary, forKey: Keys.accentSecondary) }
    }
    var accentTertiary: RGBColor {
        didSet { encode(accentTertiary, forKey: Keys.accentTertiary) }
    }

    func resetAccentColors() {
        accentPrimary = Brand.defaultPrimary
        accentSecondary = Brand.defaultSecondary
        accentTertiary = Brand.defaultTertiary
    }

    /// The orb's three colors while a "dyktuj i przetłumacz" recording is in flight — a
    /// visibly different palette than plain dictation, so you can tell at a glance which one
    /// is running without reading anything.
    var translateAccentPrimary: RGBColor {
        didSet { encode(translateAccentPrimary, forKey: Keys.translateAccentPrimary) }
    }
    var translateAccentSecondary: RGBColor {
        didSet { encode(translateAccentSecondary, forKey: Keys.translateAccentSecondary) }
    }
    var translateAccentTertiary: RGBColor {
        didSet { encode(translateAccentTertiary, forKey: Keys.translateAccentTertiary) }
    }

    func resetTranslateAccentColors() {
        translateAccentPrimary = Brand.defaultTranslatePrimary
        translateAccentSecondary = Brand.defaultTranslateSecondary
        translateAccentTertiary = Brand.defaultTranslateTertiary
    }

    /// The waveform visualizer's own three colors — independent of the orb's, so picking a
    /// different palette for one never drags the other along with it.
    var waveformAccentPrimary: RGBColor {
        didSet { encode(waveformAccentPrimary, forKey: Keys.waveformAccentPrimary) }
    }
    var waveformAccentSecondary: RGBColor {
        didSet { encode(waveformAccentSecondary, forKey: Keys.waveformAccentSecondary) }
    }
    var waveformAccentTertiary: RGBColor {
        didSet { encode(waveformAccentTertiary, forKey: Keys.waveformAccentTertiary) }
    }

    func resetWaveformAccentColors() {
        waveformAccentPrimary = Brand.defaultWaveformPrimary
        waveformAccentSecondary = Brand.defaultWaveformSecondary
        waveformAccentTertiary = Brand.defaultWaveformTertiary
    }

    var waveformTranslateAccentPrimary: RGBColor {
        didSet { encode(waveformTranslateAccentPrimary, forKey: Keys.waveformTranslateAccentPrimary) }
    }
    var waveformTranslateAccentSecondary: RGBColor {
        didSet { encode(waveformTranslateAccentSecondary, forKey: Keys.waveformTranslateAccentSecondary) }
    }
    var waveformTranslateAccentTertiary: RGBColor {
        didSet { encode(waveformTranslateAccentTertiary, forKey: Keys.waveformTranslateAccentTertiary) }
    }

    func resetWaveformTranslateAccentColors() {
        waveformTranslateAccentPrimary = Brand.defaultWaveformTranslatePrimary
        waveformTranslateAccentSecondary = Brand.defaultWaveformTranslateSecondary
        waveformTranslateAccentTertiary = Brand.defaultWaveformTranslateTertiary
    }

    // MARK: Chwytanie tekstu (grab-text OCR)

    /// The global shortcut that opens the region-selection overlay. Deliberately its own
    /// field, never `customShortcut` — dictation and grabbing are two independent triggers
    /// that must both be armed at once, not one shared slot.
    var grabShortcut: CustomShortcut {
        didSet { encode(grabShortcut, forKey: Keys.grabShortcut) }
    }

    /// Primary OCR recognition language, BCP-47. Forcing this (rather than trusting Vision's
    /// automatic detection) is what keeps Polish diacritics from getting silently dropped.
    var grabPrimaryLanguage: String {
        didSet { defaults.set(grabPrimaryLanguage, forKey: Keys.grabPrimaryLanguage) }
    }

    /// A second language Vision may fall back to per-word. `nil` = primary-only.
    var grabSecondaryLanguage: String? {
        didSet { defaults.set(grabSecondaryLanguage, forKey: Keys.grabSecondaryLanguage) }
    }

    var grabAccurateRecognition: Bool {
        didSet { defaults.set(grabAccurateRecognition, forKey: Keys.grabAccurateRecognition) }
    }

    var grabJoinHyphenatedLines: Bool {
        didSet { defaults.set(grabJoinHyphenatedLines, forKey: Keys.grabJoinHyphenatedLines) }
    }

    /// Replaces em dashes ("—") with a plain hyphen ("-") in grabbed text. Screenshotted
    /// text — captions, generated copy, chat exports — carries typographic dashes a lot of
    /// plain-text destinations (code, forms, anything monospaced) don't want.
    var grabStraightenDashes: Bool {
        didSet { defaults.set(grabStraightenDashes, forKey: Keys.grabStraightenDashes) }
    }

    var grabAutoPaste: Bool {
        didSet { defaults.set(grabAutoPaste, forKey: Keys.grabAutoPaste) }
    }

    /// The selection rectangle's border cycles through the three accent colors with a soft
    /// blurred glow instead of a plain static stroke. Off falls back to one flat color and
    /// no per-frame redraw timer while dragging — the "ram zjada" escape hatch.
    var grabAnimatedSelectionGlow: Bool {
        didSet { defaults.set(grabAnimatedSelectionGlow, forKey: Keys.grabAnimatedSelectionGlow) }
    }

    // MARK: Schowek (clipboard history + colour picker)

    /// Record what gets copied. Off stops the background watcher entirely; the panel still
    /// opens and shows what's already stored.
    var clipboardEnabled: Bool {
        didSet { defaults.set(clipboardEnabled, forKey: Keys.clipboardEnabled) }
    }

    /// Opens the floating Papla search (clipboard history). Its own field, like `grabShortcut` — every Papla
    /// trigger is independent and all are armed at once.
    var clipboardShortcut: CustomShortcut {
        didSet { encode(clipboardShortcut, forKey: Keys.clipboardShortcut) }
    }

    /// Starts the eyedropper — the colour picker feature's own shortcut.
    var colorPickerShortcut: CustomShortcut {
        didSet { encode(colorPickerShortcut, forKey: Keys.colorPickerShortcut) }
    }

    /// How many entries the history keeps before the oldest fall off.
    var clipboardPanelWidth: Double {
        didSet { defaults.set(clipboardPanelWidth, forKey: Keys.clipboardPanelWidth) }
    }

    var clipboardMaxItems: Int {
        didSet { defaults.set(clipboardMaxItems, forKey: Keys.clipboardMaxItems) }
    }

    /// Images are by far the heaviest thing in the history; this lets you skip them.
    var clipboardKeepImages: Bool {
        didSet { defaults.set(clipboardKeepImages, forKey: Keys.clipboardKeepImages) }
    }

    /// List macOS screenshots and screen recordings in the search under "Zrzuty".
    var screenshotsEnabled: Bool {
        didSet { defaults.set(screenshotsEnabled, forKey: Keys.screenshotsEnabled) }
    }

    /// Light, dark or system for the floating search panel.
    var clipboardAppearance: PanelAppearance {
        didSet { defaults.set(clipboardAppearance.rawValue, forKey: Keys.clipboardAppearance) }
    }

    /// What "Tłumacz i kopiuj" in the search panel does with the result, beyond always
    /// putting it on the pasteboard. On (default): the translation is also filed as a new
    /// history entry, right above the original, so you can see it without the panel closing.
    /// Off: copy only, panel behaves like any other copy action.
    var clipboardTranslateAddsToHistory: Bool {
        didSet { defaults.set(clipboardTranslateAddsToHistory, forKey: Keys.clipboardTranslateAddsToHistory) }
    }

    /// Which `ClipboardKind`s actually show up in the search panel — everything, by default.
    /// Turning one off (say, Kod) just hides it there; the underlying history it comes from
    /// (clipboard, colour picker, dictation…) is untouched and still fully intact.
    var clipboardVisibleKinds: Set<ClipboardKind> {
        didSet { defaults.set(clipboardVisibleKinds.map(\.rawValue), forKey: Keys.clipboardVisibleKinds) }
    }

    /// Rewrites "—" and "–" as "-" at the moment of *pasting* (⌘V anywhere, and pasting from
    /// the history panel). Copying itself is never touched. Needs Accessibility, like every
    /// other global shortcut here.
    var pasteStraightenDashes: Bool {
        didSet { defaults.set(pasteStraightenDashes, forKey: Keys.pasteStraightenDashes) }
    }

    /// How many picked colours the colour history keeps.
    var colorMaxItems: Int {
        didSet { defaults.set(colorMaxItems, forKey: Keys.colorMaxItems) }
    }

    /// Notation the eyedropper copies a colour in.
    var colorFormat: ColorFormat {
        didSet { defaults.set(colorFormat.rawValue, forKey: Keys.colorFormat) }
    }

    // MARK: Minutnik (timer / budzik)

    /// Opens the quick-entry popup — its own shortcut, like every other Papla trigger.
    var timerShortcut: CustomShortcut {
        didSet { encode(timerShortcut, forKey: Keys.timerShortcut) }
    }

    /// Played on a loop (see `Sounds.startAlarmLoop`) when a timer or alarm fires — a distinct
    /// pick from the short dictation start/end chimes, since this one needs to actually be
    /// noticed from another room.
    var alarmSound: SystemSound {
        didSet { defaults.set(alarmSound.rawValue, forKey: Keys.alarmSound) }
    }

    /// Shows the soonest running Minutnik's countdown in the menu bar, next to the orb —
    /// off by default since most people only care while the search panel is already open.
    var showTimerInMenuBar: Bool {
        didSet { defaults.set(showTimerInMenuBar, forKey: Keys.showTimerInMenuBar) }
    }

    /// What's actually armed right now for dictation — the recorded custom shortcut if
    /// there is one, otherwise the modifier checklist.
    var triggerDisplayName: String {
        customShortcut?.displayName ?? triggerKeys.sortedDisplay
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let triggerKeys = "triggerKeys"
        static let customShortcut = "customShortcut"
        static let triggerMode = "triggerMode"
        static let cleanupEnabled = "cleanupEnabled"
        static let translateShortcut = "translateShortcut"
        static let translateTargetLanguage = "translateTargetLanguage"
        static let emojiIntensity = "emojiIntensity"
        static let emojiDisabledKeywords = "emojiDisabledKeywords"
        static let emojiAtSentenceEnd = "emojiAtSentenceEnd"
        static let emojiSuppressPeriod = "emojiSuppressPeriod"
        static let customEmojiEntries = "customEmojiEntries"
        static let emojiSofteningEnabled = "emojiSofteningEnabled"
        static let translateAccentPrimary = "translateAccentPrimary"
        static let translateAccentSecondary = "translateAccentSecondary"
        static let translateAccentTertiary = "translateAccentTertiary"
        static let clipboardTranslateAddsToHistory = "clipboardTranslateAddsToHistory"
        static let clipboardVisibleKinds = "clipboardVisibleKinds"
        static let soundEnabled = "soundEnabled"
        static let soundVolume = "soundVolume"
        static let soundStart = "soundStart"
        static let soundEnd = "soundEnd"
        static let hudPosition = "hudPosition"
        static let hudMargin = "hudMargin"
        static let orbSpread = "orbSpread"
        static let hudVisualizerStyle = "hudVisualizerStyle"
        static let appLanguage = "appLanguage"
        static let menuBarIconStyle = "menuBarIconStyle"
        static let onboardingDone = "onboardingDone"
        static let tourDone = "tourDone"
        static let punctuationStyle = "punctuationStyle"
        static let accentPrimary = "accentPrimary"
        static let accentSecondary = "accentSecondary"
        static let accentTertiary = "accentTertiary"
        static let waveformAccentPrimary = "waveformAccentPrimary"
        static let waveformAccentSecondary = "waveformAccentSecondary"
        static let waveformAccentTertiary = "waveformAccentTertiary"
        static let waveformTranslateAccentPrimary = "waveformTranslateAccentPrimary"
        static let waveformTranslateAccentSecondary = "waveformTranslateAccentSecondary"
        static let waveformTranslateAccentTertiary = "waveformTranslateAccentTertiary"
        static let grabShortcut = "grabShortcut"
        static let grabPrimaryLanguage = "grabPrimaryLanguage"
        static let grabSecondaryLanguage = "grabSecondaryLanguage"
        static let grabAccurateRecognition = "grabAccurateRecognition"
        static let grabJoinHyphenatedLines = "grabJoinHyphenatedLines"
        static let grabStraightenDashes = "grabStraightenDashes"
        static let grabAutoPaste = "grabAutoPaste"
        static let grabAnimatedSelectionGlow = "grabAnimatedSelectionGlow"
        static let clipboardEnabled = "clipboardEnabled"
        static let clipboardShortcut = "clipboardShortcut"
        static let colorPickerShortcut = "colorPickerShortcut"
        static let clipboardMaxItems = "clipboardMaxItems"
        static let clipboardPanelWidth = "clipboardPanelWidth"
        static let clipboardKeepImages = "clipboardKeepImages"
        static let pasteStraightenDashes = "pasteStraightenDashes"
        static let clipboardAppearance = "clipboardAppearance"
        static let screenshotsEnabled = "screenshotsEnabled"
        static let colorMaxItems = "colorMaxItems"
        static let colorFormat = "colorFormat"
        static let timerShortcut = "timerShortcut"
        static let alarmSound = "alarmSound"
        static let showTimerInMenuBar = "showTimerInMenuBar"
    }

    private init() {
        let savedKeys = (defaults.stringArray(forKey: Keys.triggerKeys) ?? [])
            .compactMap(PushToTalkKey.init(rawValue:))
        triggerKeys = savedKeys.isEmpty ? [.rightOption] : Set(savedKeys)
        customShortcut = Settings.decode(CustomShortcut.self, defaults, Keys.customShortcut)
        translateShortcut = Settings.decode(CustomShortcut.self, defaults, Keys.translateShortcut) ?? .defaultTranslateShortcut
        translateTargetLanguage = TranslateLanguage(rawValue: defaults.string(forKey: Keys.translateTargetLanguage) ?? "") ?? .english
        emojiIntensity = (defaults.object(forKey: Keys.emojiIntensity) as? Int ?? 0).clamped(0, 5)
        emojiDisabledKeywords = Set(defaults.stringArray(forKey: Keys.emojiDisabledKeywords) ?? [])
        emojiAtSentenceEnd = defaults.object(forKey: Keys.emojiAtSentenceEnd) as? Bool ?? false
        emojiSuppressPeriod = defaults.object(forKey: Keys.emojiSuppressPeriod) as? Bool ?? false
        customEmojiEntries = Settings.decode([EmojiEnricher.Entry].self, defaults, Keys.customEmojiEntries) ?? []
        emojiSofteningEnabled = defaults.object(forKey: Keys.emojiSofteningEnabled) as? Bool ?? false
        triggerMode = DictationTriggerMode(rawValue: defaults.string(forKey: Keys.triggerMode) ?? "") ?? .hold
        cleanupEnabled = defaults.object(forKey: Keys.cleanupEnabled) as? Bool ?? true

        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        soundVolume = defaults.object(forKey: Keys.soundVolume) as? Double ?? 1.0
        soundStart = SystemSound(rawValue: defaults.string(forKey: Keys.soundStart) ?? "") ?? .tink
        soundEnd = SystemSound(rawValue: defaults.string(forKey: Keys.soundEnd) ?? "") ?? .pop

        hudPosition = HUDPosition(rawValue: defaults.string(forKey: Keys.hudPosition) ?? "") ?? .bottom
        hudMargin = defaults.object(forKey: Keys.hudMargin) as? Double ?? 48
        orbSpread = defaults.object(forKey: Keys.orbSpread) as? Double ?? 0.7
        hudVisualizerStyle = HUDVisualizerStyle(rawValue: defaults.string(forKey: Keys.hudVisualizerStyle) ?? "") ?? .orb
        appLanguage = AppLanguage(rawValue: defaults.string(forKey: Keys.appLanguage) ?? "") ?? .english
        onboardingDone = defaults.bool(forKey: Keys.onboardingDone)
        tourDone = defaults.bool(forKey: Keys.tourDone)
        speechModel = SpeechModel.current
        punctuationStyle = PunctuationStyle(rawValue: defaults.string(forKey: Keys.punctuationStyle) ?? "") ?? .normal
        menuBarIconStyle = MenuBarIconStyle(rawValue: defaults.string(forKey: Keys.menuBarIconStyle) ?? "") ?? .orb

        accentPrimary = Settings.decode(RGBColor.self, defaults, Keys.accentPrimary) ?? Brand.defaultPrimary
        accentSecondary = Settings.decode(RGBColor.self, defaults, Keys.accentSecondary) ?? Brand.defaultSecondary
        accentTertiary = Settings.decode(RGBColor.self, defaults, Keys.accentTertiary) ?? Brand.defaultTertiary
        translateAccentPrimary = Settings.decode(RGBColor.self, defaults, Keys.translateAccentPrimary) ?? Brand.defaultTranslatePrimary
        translateAccentSecondary = Settings.decode(RGBColor.self, defaults, Keys.translateAccentSecondary) ?? Brand.defaultTranslateSecondary
        translateAccentTertiary = Settings.decode(RGBColor.self, defaults, Keys.translateAccentTertiary) ?? Brand.defaultTranslateTertiary
        waveformAccentPrimary = Settings.decode(RGBColor.self, defaults, Keys.waveformAccentPrimary) ?? Brand.defaultWaveformPrimary
        waveformAccentSecondary = Settings.decode(RGBColor.self, defaults, Keys.waveformAccentSecondary) ?? Brand.defaultWaveformSecondary
        waveformAccentTertiary = Settings.decode(RGBColor.self, defaults, Keys.waveformAccentTertiary) ?? Brand.defaultWaveformTertiary
        waveformTranslateAccentPrimary = Settings.decode(RGBColor.self, defaults, Keys.waveformTranslateAccentPrimary) ?? Brand.defaultWaveformTranslatePrimary
        waveformTranslateAccentSecondary = Settings.decode(RGBColor.self, defaults, Keys.waveformTranslateAccentSecondary) ?? Brand.defaultWaveformTranslateSecondary
        waveformTranslateAccentTertiary = Settings.decode(RGBColor.self, defaults, Keys.waveformTranslateAccentTertiary) ?? Brand.defaultWaveformTranslateTertiary

        grabShortcut = Settings.decode(CustomShortcut.self, defaults, Keys.grabShortcut) ?? .defaultGrabShortcut
        grabPrimaryLanguage = defaults.string(forKey: Keys.grabPrimaryLanguage) ?? "pl-PL"
        grabSecondaryLanguage = defaults.object(forKey: Keys.grabSecondaryLanguage) == nil
            ? "en-US"
            : defaults.string(forKey: Keys.grabSecondaryLanguage)
        grabAccurateRecognition = defaults.object(forKey: Keys.grabAccurateRecognition) as? Bool ?? true
        grabJoinHyphenatedLines = defaults.object(forKey: Keys.grabJoinHyphenatedLines) as? Bool ?? true
        grabStraightenDashes = defaults.object(forKey: Keys.grabStraightenDashes) as? Bool ?? true
        grabAutoPaste = defaults.object(forKey: Keys.grabAutoPaste) as? Bool ?? false
        grabAnimatedSelectionGlow = defaults.object(forKey: Keys.grabAnimatedSelectionGlow) as? Bool ?? true

        clipboardEnabled = defaults.object(forKey: Keys.clipboardEnabled) as? Bool ?? true
        clipboardShortcut = Settings.decode(CustomShortcut.self, defaults, Keys.clipboardShortcut) ?? .defaultClipboardShortcut
        colorPickerShortcut = Settings.decode(CustomShortcut.self, defaults, Keys.colorPickerShortcut) ?? .defaultColorPickerShortcut
        clipboardMaxItems = defaults.object(forKey: Keys.clipboardMaxItems) as? Int ?? 500
        clipboardPanelWidth = min(max(defaults.object(forKey: Keys.clipboardPanelWidth) as? Double ?? 760, 600), 1200)
        clipboardKeepImages = defaults.object(forKey: Keys.clipboardKeepImages) as? Bool ?? true
        screenshotsEnabled = defaults.object(forKey: Keys.screenshotsEnabled) as? Bool ?? true
        clipboardAppearance = PanelAppearance(rawValue: defaults.string(forKey: Keys.clipboardAppearance) ?? "") ?? .system
        clipboardTranslateAddsToHistory = defaults.object(forKey: Keys.clipboardTranslateAddsToHistory) as? Bool ?? true
        if let saved = defaults.stringArray(forKey: Keys.clipboardVisibleKinds) {
            clipboardVisibleKinds = Set(saved.compactMap(ClipboardKind.init(rawValue:)))
        } else {
            clipboardVisibleKinds = Set(ClipboardKind.allCases)
        }
        pasteStraightenDashes = defaults.object(forKey: Keys.pasteStraightenDashes) as? Bool ?? false
        colorMaxItems = defaults.object(forKey: Keys.colorMaxItems) as? Int ?? 200
        colorFormat = ColorFormat(rawValue: defaults.string(forKey: Keys.colorFormat) ?? "") ?? .hex
        timerShortcut = Settings.decode(CustomShortcut.self, defaults, Keys.timerShortcut) ?? .defaultTimerShortcut
        alarmSound = SystemSound(rawValue: defaults.string(forKey: Keys.alarmSound) ?? "") ?? .sosumi
        showTimerInMenuBar = defaults.object(forKey: Keys.showTimerInMenuBar) as? Bool ?? false
    }

    private func encode<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ defaults: UserDefaults, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

private extension Int {
    func clamped(_ lower: Int, _ upper: Int) -> Int { Swift.min(Swift.max(self, lower), upper) }
}
