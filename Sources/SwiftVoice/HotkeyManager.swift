import AppKit
import Combine
import Foundation

@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()
    private static let key = "pushToTalkHotkey"

    @Published private(set) var hotkey: Hotkey {
        didSet {
            save()
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Hotkey.self, from: data) {
            self.hotkey = decoded
        } else {
            self.hotkey = Hotkey.defaultHotkey
        }
    }

    func setHotkey(_ newHotkey: Hotkey) {
        guard hotkey != newHotkey else { return }
        hotkey = newHotkey
    }

    func resetToDefault() {
        setHotkey(Hotkey.defaultHotkey)
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(hotkey) {
            UserDefaults.standard.set(encoded, forKey: Self.key)
        }
    }
}
