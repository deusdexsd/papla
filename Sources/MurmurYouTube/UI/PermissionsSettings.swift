import AppKit
import SwiftUI

/// Ustawienia ▸ Uprawnienia: every macOS grant Papla depends on in one place, with live status
/// and a shortcut into the right System Settings page.
struct PermissionsSettingsPanel: View {
    @State private var accessibility = Permissions.hasAccessibility
    @State private var microphone = Permissions.hasMicrophone
    @State private var screenRecording = Permissions.hasScreenRecording

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            reinstallNotice

            section(t("Wymagane uprawnienia", "Required permissions")) {
                permissionRow(
                    title: t("Dostępność", "Accessibility"),
                    detail: t("Skróty klawiszowe, wpisywanie tekstu do pól, wklejanie z wyszukiwarki.",
                              "Keyboard shortcuts, typing text into fields, pasting from the search."),
                    granted: accessibility,
                    open: { Permissions.promptForAccessibility(); Permissions.openAccessibilitySettings() }
                )
                permissionRow(
                    title: t("Mikrofon", "Microphone"),
                    detail: t("Dyktowanie.", "Dictation."),
                    granted: microphone,
                    open: {
                        Task {
                            _ = await Permissions.requestMicrophone()
                            microphone = Permissions.hasMicrophone
                            if !microphone { Permissions.openMicrophoneSettings() }
                        }
                    }
                )
                permissionRow(
                    title: t("Nagrywanie ekranu", "Screen Recording"),
                    detail: t("Chwytanie tekstu z ekranu (OCR) i kodów QR.", "Grabbing text (OCR) and QR codes from the screen."),
                    granted: screenRecording,
                    open: { Permissions.promptForScreenRecording(); Permissions.openScreenRecordingSettings() }
                )
            }

            section(t("Jak nadać uprawnienie", "How to grant a permission")) {
                Text(t("1. Kliknij „Otwórz ustawienia” przy uprawnieniu.\n"
                    + "2. Na liście znajdź Paplę. Jeśli jest, ale nie działa — zaznacz ją i kliknij − (usuń), "
                    + "potem + i dodaj Paplę z Programów jeszcze raz.\n"
                    + "3. Włącz przełącznik przy Papli.\n"
                    + "4. Kliknij „Uruchom Paplę od nowa” poniżej — uprawnienia działają dopiero po restarcie.",
                    "1. Click “Open settings” next to a permission.\n"
                    + "2. Find Papla in the list. If it's there but doesn't work — select it, click − (remove), "
                    + "then + and add Papla from Applications again.\n"
                    + "3. Switch Papla on.\n"
                    + "4. Click “Restart Papla” below — permissions only take effect after a restart."))
                    .font(DS.Font.body)
                    .fixedSize(horizontal: false, vertical: true)

                TransportKey(title: t("Uruchom Paplę od nowa", "Restart Papla"), systemImage: "arrow.clockwise") {
                    Self.relaunch()
                }
                .padding(.top, DS.Space.snug)
            }
        }
        .onReceive(ticker) { _ in
            accessibility = Permissions.hasAccessibility
            microphone = Permissions.hasMicrophone
            screenRecording = Permissions.hasScreenRecording
        }
    }

    private var reinstallNotice: some View {
        HStack(alignment: .top, spacing: DS.Space.base) {
            Image(systemName: "info.circle.fill").foregroundStyle(Brand.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(t("Po każdej reinstalacji lub aktualizacji Papli", "After every reinstall or update of Papla"))
                    .font(DS.Font.bodyEmphasis)
                Text(t("macOS wiąże uprawnienia z podpisem aplikacji, a każda nowa wersja ma nowy podpis — więc "
                    + "zapomina wszystkie trzy uprawnienia. Trzeba je nadać ponownie (zwykle wystarczy usunąć "
                    + "Paplę z listy i dodać jeszcze raz). Jeśli skróty nagle przestały działać po aktualizacji, "
                    + "to jest właśnie ten powód.",
                    "macOS ties permissions to the app's signature, and every new build has a new one — so it "
                    + "forgets all three permissions. You have to grant them again (usually removing Papla from "
                    + "the list and adding it back is enough). If shortcuts suddenly stop working after an "
                    + "update, this is why."))
                    .font(DS.Font.body).foregroundStyle(DS.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Space.base)
        .background(Brand.accent.opacity(0.12), in: .rect(cornerRadius: DS.Radius.control))
    }

    private func permissionRow(
        title: String, detail: String, granted: Bool, open: @escaping () -> Void
    ) -> some View {
        PermissionRowView(title: title, detail: detail, granted: granted, open: open)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            Silkscreen(text: title, large: true)
            content()
            Rectangle().fill(DS.Color.seam).frame(height: 1).padding(.top, DS.Space.snug)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? process.run()
        NSApp.terminate(nil)
    }
}


/// One permission: live status dot, what it's for, and a single button into the right page.
struct PermissionRowView: View {
    let title: String
    let detail: String
    let granted: Bool
    let open: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.base) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(granted ? DS.Color.statusGood : DS.Color.statusBad)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.Font.bodyEmphasis)
                Text(detail).font(DS.Font.label).foregroundStyle(DS.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Space.base)
            Text(granted ? t("Nadane", "Granted") : t("Brak", "Missing"))
                .font(DS.Font.silkscreen)
                .foregroundStyle(granted ? DS.Color.statusGood : DS.Color.statusBad)
            TransportKey(title: t("Otwórz ustawienia", "Open settings"), action: open)
        }
        .padding(.vertical, DS.Space.tight)
    }
}

/// The three permission actions, shared by Ustawienia ▸ Uprawnienia and the first-run guide.
@MainActor
enum PermissionActions {
    static func accessibility() { Permissions.promptForAccessibility(); Permissions.openAccessibilitySettings() }
    static func screenRecording() { Permissions.promptForScreenRecording(); Permissions.openScreenRecordingSettings() }
    static func microphone(done: @escaping @MainActor () -> Void) {
        Task {
            _ = await Permissions.requestMicrophone()
            done()
            if !Permissions.hasMicrophone { Permissions.openMicrophoneSettings() }
        }
    }
}
