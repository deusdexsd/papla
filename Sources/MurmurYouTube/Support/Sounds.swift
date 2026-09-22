import AppKit

/// Plays one of the user's chosen system sounds at the user's chosen volume — the one place
/// both dictation and grab-text reach for a "start" or "done" chime, so a volume/sound
/// change in Ustawienia affects both without either feature touching `NSSound` directly.
@MainActor
enum Sounds {
    static func playStart() { play(Settings.shared.soundStart) }
    static func playEnd() { play(Settings.shared.soundEnd) }

    /// A timer/alarm firing needs to actually be noticed, not blend into every other short
    /// "done" chime — the same system sound repeated a few times reads as "ring, ring, ring"
    /// rather than one quiet "pim". Ignores the mute-everything `soundEnabled` toggle on
    /// purpose: that setting is about dictation feedback, and a silent alarm defeats the point
    /// of setting one.
    static func playAlarm() {
        Task {
            for _ in 0..<3 {
                let instance = NSSound(named: Settings.shared.alarmSound.rawValue)
                instance?.volume = Float(Settings.shared.soundVolume)
                instance?.play()
                try? await Task.sleep(for: .milliseconds(750))
            }
        }
    }

    private static func play(_ sound: SystemSound) {
        guard Settings.shared.soundEnabled else { return }
        let instance = NSSound(named: sound.rawValue)
        instance?.volume = Float(Settings.shared.soundVolume)
        instance?.play()
    }
}
