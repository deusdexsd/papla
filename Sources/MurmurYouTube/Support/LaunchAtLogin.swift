import Foundation
import ServiceManagement

/// "Uruchamiaj przy logowaniu" — registers Papla itself as a login item, so it appears in
/// Ustawienia systemowe ▸ Ogólne ▸ Rzeczy otwierane podczas logowania and can be switched off
/// there too. The system is the source of truth; nothing is stored in Papla's own settings.
@MainActor
enum LaunchAtLogin {
    private static var service: SMAppService { .mainApp }

    static var isEnabled: Bool { service.status == .enabled }

    /// macOS sometimes wants the user to confirm a new login item in System Settings first.
    static var needsApproval: Bool { service.status == .requiresApproval }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            Log.app.error("login item: \(error.localizedDescription, privacy: .public)")
        }
        if enabled, needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }
}
