import Foundation
import ServiceManagement

enum LoginItemSettings {
    static let enabledKey = "launchAtLogin"
}

@MainActor
enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "Включён"
        case .requiresApproval:
            return "Требуется разрешение в Login Items"
        case .notFound:
            return "Jarvis должен находиться в папке Applications"
        case .notRegistered:
            return "Выключен"
        @unknown default:
            return "Неизвестное состояние"
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
        UserDefaults.standard.set(enabled, forKey: LoginItemSettings.enabledKey)
    }

    static func applySavedPreference() {
        guard UserDefaults.standard.bool(forKey: LoginItemSettings.enabledKey),
              SMAppService.mainApp.status == .notRegistered
        else {
            return
        }
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("Jarvis launch-at-login registration failed: \(error)")
        }
    }
}
