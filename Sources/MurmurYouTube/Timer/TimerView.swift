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
    private let cornerRadius: CGFloat = 26

    private var durationSeconds: TimeInterval {
        TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Picker("", selection: $mode) {
                Text("Za").tag(Mode.duration)
                Text("O").tag(Mode.alarm)
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            if mode == .duration {
                DurationStepperField(hours: $hours, minutes: $minutes, seconds: $seconds, style: style)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else {
                DatePicker("", selection: $alarmTime, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.field)
            }

            TextField("na co (opcjonalnie)", text: $label)
                .textFieldStyle(.roundedBorder)

            Button {
                start()
            } label: {
                Text(mode == .duration ? "Start" : "Ustaw")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(mode == .duration && durationSeconds <= 0)

            if !store.entries.isEmpty {
                Rectangle().fill(style.hairline).frame(height: 1).padding(.vertical, 2)
                Text("Aktywne")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(style.secondary)
                activeList
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: TimerPanel.size.width, height: TimerPanel.size.height, alignment: .top)
        .modifier(GlassIfPanel(isPanel: true, radius: cornerRadius))
        .onAppear { hours = 0; minutes = 10; seconds = 0; label = "" }
    }

    private var header: some View {
        HStack {
            Text("Minutnik")
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
                                Text(entry.label.isEmpty ? "Minutnik" : entry.label)
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

/// Three native `Stepper`s (godz./min./sek.) instead of typing something like "1h30m" into a
/// text field — no format to remember, no parsing to get wrong.
private struct DurationStepperField: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int
    let style: PanelStyle

    var body: some View {
        HStack(spacing: 14) {
            component("godz.", value: $hours, range: 0...23)
            separator
            component("min.", value: $minutes, range: 0...59)
            separator
            component("sek.", value: $seconds, range: 0...59)
        }
    }

    private var separator: some View {
        Text(":")
            .font(.system(size: 22, weight: .light, design: .rounded))
            .foregroundStyle(style.tertiary)
            .padding(.top, -12)
    }

    private func component(_ caption: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(spacing: 3) {
            Stepper(value: value, in: range) {
                Text(String(format: "%02d", value.wrappedValue))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(style.primary)
            }
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(style.tertiary)
        }
    }
}
