import AppKit
import Foundation
import UserNotifications

extension Notification.Name {
    /// Posted when a `TimerEntry` fires — `object` is the fired `TimerEntry`. `TimerController`
    /// owns what happens on screen and in sound from here; `TimerStore` stays a plain data
    /// layer that doesn't know about panels or `NSSound`.
    static let timerDidFire = Notification.Name("ai.pivotstudio.papla.timerDidFire")
}

/// One running countdown or scheduled alarm.
struct TimerEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    /// What it's for — shown in the notification and the list. Can be empty.
    var label: String
    var fireDate: Date
    var createdAt = Date()

    /// Whether this was created as "za X" (a duration) or "o X" (a clock time) — cosmetic
    /// only, decides the icon/wording in the list.
    var isAlarm: Bool
}

/// Every running timer/alarm, newest-created first, persisted so a relaunch doesn't lose one
/// mid-countdown. Firing is belt-and-suspenders: an in-process `Task` plays the actual
/// (repeated, alarm-like) sound while the app is running, and a `UNUserNotificationCenter`
/// request is scheduled alongside it so a banner (with the system's own sound) still appears
/// even if Papla wasn't frontmost, or the Mac was asleep and woke up again after the fire time.
@MainActor
@Observable
final class TimerStore {
    static let shared = TimerStore()

    private(set) var entries: [TimerEntry] = []
    private let fileURL = RunLog.directory.appendingPathComponent("timers.json")
    private var fireTasks: [UUID: Task<Void, Never>] = [:]

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([TimerEntry].self, from: data) {
            // Anything that should have fired while Papla wasn't running is just dropped —
            // firing it late, silently, on next launch would be more confusing than useful.
            entries = decoded.filter { $0.fireDate > Date() }
        }
        for entry in entries { scheduleFire(for: entry) }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    @discardableResult
    func add(label: String, fireDate: Date, isAlarm: Bool) -> TimerEntry {
        let entry = TimerEntry(label: label, fireDate: fireDate, isAlarm: isAlarm)
        entries.append(entry)
        entries.sort { $0.fireDate < $1.fireDate }
        save()
        scheduleFire(for: entry)
        scheduleNotification(for: entry)
        return entry
    }

    func cancel(_ entry: TimerEntry) {
        entries.removeAll { $0.id == entry.id }
        fireTasks[entry.id]?.cancel()
        fireTasks[entry.id] = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [entry.id.uuidString])
        save()
    }

    // MARK: - Firing

    private func scheduleFire(for entry: TimerEntry) {
        fireTasks[entry.id]?.cancel()
        fireTasks[entry.id] = Task { [weak self] in
            let interval = entry.fireDate.timeIntervalSinceNow
            if interval > 0 {
                try? await Task.sleep(for: .seconds(interval))
            }
            guard !Task.isCancelled else { return }
            self?.fire(entry)
        }
    }

    private func fire(_ entry: TimerEntry) {
        entries.removeAll { $0.id == entry.id }
        fireTasks[entry.id] = nil
        save()
        NotificationCenter.default.post(name: .timerDidFire, object: entry)
    }

    private func scheduleNotification(for entry: TimerEntry) {
        let content = UNMutableNotificationContent()
        content.title = entry.isAlarm ? t("Papla — budzik", "Papla — alarm") : t("Papla — minutnik", "Papla — timer")
        content.body = entry.label.isEmpty ? t("Czas minął.", "Time's up.") : entry.label
        content.sound = .defaultCritical
        let interval = max(1, entry.fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: entry.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
