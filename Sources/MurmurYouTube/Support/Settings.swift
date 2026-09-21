import Foundation
import Observation
import SwiftUI

/// Which edge of the screen the floating orb hugs — shared by dictation's HUD and the
/// grab-text HUD, since there's no reason the two would want to live in different spots.
enum HUDPosition: String, CaseIterable, Sendable {
    case top, bottom, left, right

    var displayName: String {
        switch self {
        case .top: "Góra"
        case .bottom: "Dół"
        case .left: "Lewo"
        case .right: "Prawo"
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

    var displayName: String {
        switch self {
        case .hold: "Przytrzymaj"
        case .toggle: "Przełącznik"
        }
    }

    var note: String {
        switch self {
        case .hold: "Trzymasz klawisz i mówisz — puszczasz, żeby skończyć."
        case .toggle: "Naciskasz raz, żeby zacząć, drugi raz, żeby skończyć. "
            + "Klawisz możesz puścić w trakcie mówienia."
        }
    }
}

/// Light / dark / follow-the-system for the floating search panel.
enum PanelAppearance: String, CaseIterable, Sendable {
    case system, light, dark

    var displayName: String {
        switch self {
        case .system: "Systemowy"
        case .light: "Jasny"
        case .dark: "Ciemny"
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
        static let soundEnabled = "soundEnabled"
        static let soundVolume = "soundVolume"
        static let soundStart = "soundStart"
        static let soundEnd = "soundEnd"
        static let hudPosition = "hudPosition"
        static let hudMargin = "hudMargin"
        static let orbSpread = "orbSpread"
        static let accentPrimary = "accentPrimary"
        static let accentSecondary = "accentSecondary"
        static let accentTertiary = "accentTertiary"
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
        static let clipboardKeepImages = "clipboardKeepImages"
        static let pasteStraightenDashes = "pasteStraightenDashes"
        static let clipboardAppearance = "clipboardAppearance"
        static let screenshotsEnabled = "screenshotsEnabled"
        static let colorMaxItems = "colorMaxItems"
        static let colorFormat = "colorFormat"
    }

    private init() {
        let savedKeys = (defaults.stringArray(forKey: Keys.triggerKeys) ?? [])
            .compactMap(PushToTalkKey.init(rawValue:))
        triggerKeys = savedKeys.isEmpty ? [.rightOption] : Set(savedKeys)
        customShortcut = Settings.decode(CustomShortcut.self, defaults, Keys.customShortcut)
        triggerMode = DictationTriggerMode(rawValue: defaults.string(forKey: Keys.triggerMode) ?? "") ?? .hold
        cleanupEnabled = defaults.object(forKey: Keys.cleanupEnabled) as? Bool ?? true

        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        soundVolume = defaults.object(forKey: Keys.soundVolume) as? Double ?? 1.0
        soundStart = SystemSound(rawValue: defaults.string(forKey: Keys.soundStart) ?? "") ?? .tink
        soundEnd = SystemSound(rawValue: defaults.string(forKey: Keys.soundEnd) ?? "") ?? .pop

        hudPosition = HUDPosition(rawValue: defaults.string(forKey: Keys.hudPosition) ?? "") ?? .bottom
        hudMargin = defaults.object(forKey: Keys.hudMargin) as? Double ?? 48
        orbSpread = defaults.object(forKey: Keys.orbSpread) as? Double ?? 0.7

        accentPrimary = Settings.decode(RGBColor.self, defaults, Keys.accentPrimary) ?? Brand.defaultPrimary
        accentSecondary = Settings.decode(RGBColor.self, defaults, Keys.accentSecondary) ?? Brand.defaultSecondary
        accentTertiary = Settings.decode(RGBColor.self, defaults, Keys.accentTertiary) ?? Brand.defaultTertiary

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
        clipboardKeepImages = defaults.object(forKey: Keys.clipboardKeepImages) as? Bool ?? true
        screenshotsEnabled = defaults.object(forKey: Keys.screenshotsEnabled) as? Bool ?? true
        clipboardAppearance = PanelAppearance(rawValue: defaults.string(forKey: Keys.clipboardAppearance) ?? "") ?? .system
        pasteStraightenDashes = defaults.object(forKey: Keys.pasteStraightenDashes) as? Bool ?? false
        colorMaxItems = defaults.object(forKey: Keys.colorMaxItems) as? Int ?? 200
        colorFormat = ColorFormat(rawValue: defaults.string(forKey: Keys.colorFormat) ?? "") ?? .hex
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
