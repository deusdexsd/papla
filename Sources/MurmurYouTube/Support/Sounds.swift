import AppKit

/// Plays one of the user's chosen system sounds at the user's chosen volume — the one place
/// both dictation and grab-text reach for a "start" or "done" chime, so a volume/sound
/// change in Ustawienia affects both without either feature touching `NSSound` directly.
@MainActor
enum Sounds {
    static func playStart() { play(Settings.shared.soundStart) }
    static func playEnd() { play(Settings.shared.soundEnd) }

    private static var alarmLoop: Task<Void, Never>?

    /// A timer/alarm firing needs to actually be noticed, not blend into every other short
    /// "done" chime — three fixed reps of a short system sound just reads as a quiet "pim,
    /// pim, pim" and is easy to miss entirely. This keeps ringing, with a real gap of
    /// silence between each ring, until `stopAlarmLoop()` is called (`TimerController` calls
    /// it when the "Wyłącz" button on the fire popup is pressed). Ignores the mute-everything
    /// `soundEnabled` toggle on purpose: that setting is about dictation feedback, and a
    /// silent alarm defeats the point of setting one.
    static func startAlarmLoop() {
        guard alarmLoop == nil else { return }
        alarmLoop = Task {
            while !Task.isCancelled {
                let instance = NSSound(named: Settings.shared.alarmSound.rawValue)
                instance?.volume = Float(Settings.shared.soundVolume)
                instance?.play()
                try? await Task.sleep(for: .milliseconds(1_100))
            }
        }
    }

    static func stopAlarmLoop() {
        alarmLoop?.cancel()
        alarmLoop = nil
    }

    private static func play(_ sound: SystemSound) {
        guard Settings.shared.soundEnabled else { return }
        let instance = NSSound(named: sound.rawValue)
        instance?.volume = Float(Settings.shared.soundVolume)
        instance?.play()
    }
}
