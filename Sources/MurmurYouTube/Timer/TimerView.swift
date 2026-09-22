import SwiftUI

/// The Minutnik popup's content: pick "za" (a duration, counting down) or "o" (a specific
/// time, optionally a different day) and set it going; the list underneath shows whatever's
/// already running with a live countdown, cancel with one click.
struct TimerView: View {
    let controller: TimerController
    @State private var store = TimerStore.shared
    @State private var mode: Mode = .duration
    @State private var durationText = "10m"
    @State private var alarmTime = Date()
    @State private var label = ""
    @State private var errorMessage: String?

    private enum Mode { case duration, alarm }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.base) {
            HStack {
                Silkscreen(text: "Minutnik", large: true, color: DS.Color.ink)
                Spacer()
                Button {
                    controller.hidePanel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.inkSecondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: DS.Space.snug) {
                TransportKey(title: "Za", isEngaged: mode == .duration, engagedColor: Brand.accent) {
                    mode = .duration
                }
                TransportKey(title: "O", isEngaged: mode == .alarm, engagedColor: Brand.accent) {
                    mode = .alarm
                }
            }

            if mode == .duration {
                DeckWindow {
                    TextField("np. 10m, 1h30m, 90s", text: $durationText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(DS.Color.inkOnDeck)
                        .padding(.horizontal, DS.Space.base)
                        .padding(.vertical, DS.Space.snug)
                }
            } else {
                DatePicker("", selection: $alarmTime, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.field)
            }

            DeckWindow {
                TextField("na co (opcjonalnie)", text: $label)
                    .textFieldStyle(.plain)
                    .foregroundStyle(DS.Color.inkOnDeck)
                    .padding(.horizontal, DS.Space.base)
                    .padding(.vertical, DS.Space.snug)
            }

            if let errorMessage {
                Text(errorMessage).font(DS.Font.label).foregroundStyle(DS.Color.statusBad)
            }

            TransportKey(title: mode == .duration ? "Start" : "Ustaw", engagedColor: Brand.accent) {
                start()
            }

            if !store.entries.isEmpty {
                Rectangle().fill(DS.Color.seam).frame(height: 1).padding(.vertical, DS.Space.tight)
                Silkscreen(text: "Aktywne")
                activeList
            }
        }
        .padding(DS.Space.panel)
        .frame(width: TimerPanel.size.width, height: TimerPanel.size.height, alignment: .top)
        .background { BrushedPanel() }
        .onAppear { durationText = "10m"; label = ""; errorMessage = nil }
    }

    private var activeList: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    ForEach(store.entries) { entry in
                        HStack {
                            Image(systemName: entry.isAlarm ? "alarm" : "timer")
                                .foregroundStyle(Brand.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.label.isEmpty ? "Minutnik" : entry.label)
                                    .font(DS.Font.body)
                                Text(remaining(entry.fireDate))
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.inkSecondary)
                            }
                            Spacer()
                            Button {
                                store.cancel(entry)
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(DS.Color.inkSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: 140)
        }
    }

    private func remaining(_ fireDate: Date) -> String {
        let seconds = max(0, Int(fireDate.timeIntervalSinceNow))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func start() {
        errorMessage = nil
        let fireDate: Date
        let isAlarm: Bool
        switch mode {
        case .duration:
            guard let seconds = Self.parseDuration(durationText), seconds > 0 else {
                errorMessage = "Nie rozumiem tego czasu — spróbuj np. „10m” albo „1h30m”."
                return
            }
            fireDate = Date().addingTimeInterval(seconds)
            isAlarm = false
        case .alarm:
            // "domyślnie dzisiaj" — but a time already in the past today obviously means
            // tomorrow, the same way every alarm clock app assumes it.
            fireDate = alarmTime > Date() ? alarmTime : alarmTime.addingTimeInterval(24 * 3600)
            isAlarm = true
        }
        TimerStore.shared.add(label: label.trimmingCharacters(in: .whitespaces), fireDate: fireDate, isAlarm: isAlarm)
        controller.hidePanel()
    }

    /// Lenient: "10m", "1h30m", "90s", "10 min", "2 godziny", "1:30" (mm:ss), a bare number
    /// (assumed minutes — "10" means "za 10 minut", the overwhelmingly common case).
    private static func parseDuration(_ input: String) -> TimeInterval? {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").compactMap { Double($0) }
            guard !parts.isEmpty else { return nil }
            let seconds: Double
            switch parts.count {
            case 3: seconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
            case 2: seconds = parts[0] * 60 + parts[1]
            default: seconds = parts[0] * 60
            }
            return seconds > 0 ? seconds : nil
        }

        guard let regex = try? NSRegularExpression(pattern: "([0-9]+(?:[.,][0-9]+)?)\\s*([a-ząćęłńóśźż]*)") else { return nil }
        let ns = trimmed as NSString
        var total: Double = 0
        var matched = false
        for match in regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length)) {
            guard let numRange = Range(match.range(at: 1), in: trimmed) else { continue }
            let numStr = trimmed[numRange].replacingOccurrences(of: ",", with: ".")
            guard let value = Double(numStr) else { continue }
            let unit = Range(match.range(at: 2), in: trimmed).map { String(trimmed[$0]) } ?? ""
            matched = true
            if unit.hasPrefix("h") || unit.hasPrefix("godz") {
                total += value * 3600
            } else if unit.hasPrefix("s") || unit.hasPrefix("sek") {
                total += value
            } else {
                total += value * 60 // "m"/"min"/bare number
            }
        }
        return matched && total > 0 ? total : nil
    }
}
