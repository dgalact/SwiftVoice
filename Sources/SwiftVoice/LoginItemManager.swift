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
        let loc = LocalizationManager.shared
        switch SMAppService.mainApp.status {
        case .enabled:
            return loc.string("status_enabled")
        case .requiresApproval:
            return loc.string("status_requires_approval")
        case .notFound:
            return loc.string("status_not_found")
        case .notRegistered:
            return loc.string("status_disabled")
        @unknown default:
            return loc.string("status_disabled")
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
            NSLog("SwiftVoice launch-at-login registration failed: \(error)")
        }
    }
}
