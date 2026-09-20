import AppKit

/// Plays one of the user's chosen system sounds at the user's chosen volume — the one place
/// both dictation and grab-text reach for a "start" or "done" chime, so a volume/sound
/// change in Ustawienia affects both without either feature touching `NSSound` directly.
@MainActor
enum Sounds {
    static func playStart() { play(Settings.shared.soundStart) }
    static func playEnd() { play(Settings.shared.soundEnd) }

    private static func play(_ sound: SystemSound) {
        guard Settings.shared.soundEnabled else { return }
        let instance = NSSound(named: sound.rawValue)
        instance?.volume = Float(Settings.shared.soundVolume)
        instance?.play()
    }
}
