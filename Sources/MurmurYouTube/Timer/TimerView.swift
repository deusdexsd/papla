import SwiftUI

/// The Minutnik popup's content: pick "za" (a duration, counting down) or "o" (a specific
/// time, optionally a different day) and set it going; the list underneath shows whatever's
/// already running with a live countdown, cancel with one click. Styled to match the clipboard
/// search panel exactly — same `PanelStyle`/Liquid Glass — since it's the same kind of floating
/// popup and should read as one product with it, not as Papla's own separate "brand" look.
struct TimerView: View {
    let controller: TimerController
    @State private var store = TimerStore.shared
    @State private var mode: Mode = .duration
    @State private var hours = 0
    @State private var minutes = 10
    @State private var seconds = 0
    @State private var alarmTime = Date()
    @State private var label = ""

    private enum Mode { case duration, alarm }
    private let style = PanelStyle(native: true)
    private let cornerRadius: CGFloat = PanelStyle.cornerRadius

    private var durationSeconds: TimeInterval {
        TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Picker("", selection: $mode) {
                Text(t("Za", "In")).tag(Mode.duration)
                Text(t("O", "At")).tag(Mode.alarm)
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            if mode == .duration {
                DurationDigitField(hours: $hours, minutes: $minutes, seconds: $seconds, style: style)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else {
                DatePicker("", selection: $alarmTime, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.field)
            }

            TextField("", text: $label, prompt: Text(t("Opis", "Description")).italic())
                .textFieldStyle(.roundedBorder)

            Button {
                start()
            } label: {
                Text(mode == .duration ? t("Start", "Start") : t("Ustaw", "Set"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(mode == .duration && durationSeconds <= 0)

            if !store.entries.isEmpty {
                Rectangle().fill(style.hairline).frame(height: 1).padding(.vertical, 2)
                Text(t("Aktywne", "Active"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(style.secondary)
                activeList
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .modifier(GlassIfPanel(isPanel: true, radius: cornerRadius))
        .onAppear { hours = 0; minutes = 10; seconds = 0; label = "" }
    }

    private var header: some View {
        HStack {
            Text(t("Minutnik", "Timer"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(style.primary)
            Spacer()
            Button {
                controller.hidePanel()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(style.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private var activeList: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.entries) { entry in
                        HStack {
                            Image(systemName: entry.isAlarm ? "alarm" : "timer")
                                .foregroundStyle(style.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.label.isEmpty ? t("Minutnik", "Timer") : entry.label)
                                    .font(.system(size: 13))
                                    .foregroundStyle(style.primary)
                                Text(remaining(entry.fireDate))
                                    .font(.system(size: 11))
                                    .foregroundStyle(style.secondary)
                                    .monospacedDigit()
                            }
                            Spacer()
                            Button {
                                store.cancel(entry)
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(style.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: 130)
        }
    }

    private func remaining(_ fireDate: Date) -> String {
        let seconds = max(0, Int(fireDate.timeIntervalSinceNow))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func start() {
        let fireDate: Date
        let isAlarm: Bool
        switch mode {
        case .duration:
            guard durationSeconds > 0 else { return }
            fireDate = Date().addingTimeInterval(durationSeconds)
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
}

/// Three big, plainly typeable digit boxes (godz:min:sek) instead of either a "1h30m"-style
/// text format to remember, or clicking a stepper 45 times to reach 45 minutes — type the
/// number directly, same as any clock app's timer entry.
private struct DurationDigitField: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int
    let style: PanelStyle

    var body: some View {
        HStack(spacing: 6) {
            digitBox(value: $hours, range: 0...23)
            colon
            digitBox(value: $minutes, range: 0...59)
            colon
            digitBox(value: $seconds, range: 0...59)
        }
    }

    private var colon: some View {
        Text(":")
            .font(.system(size: 30, weight: .light, design: .rounded))
            .foregroundStyle(style.tertiary)
    }

    private func digitBox(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        TextField("", value: value, format: .number)
            .textFieldStyle(.plain)
            .font(.system(size: 30, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(style.primary)
            .multilineTextAlignment(.center)
            .frame(width: 56)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(style.chipOff))
            .onChange(of: value.wrappedValue) { _, newValue in
                let clamped = min(max(newValue, range.lowerBound), range.upperBound)
                if clamped != newValue { value.wrappedValue = clamped }
            }
    }
}
