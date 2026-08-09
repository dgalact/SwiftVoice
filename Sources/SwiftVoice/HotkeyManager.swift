import AppKit
import Combine
import Foundation

@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()
    private static let pushToTalkKey = "pushToTalkHotkey"
    private static let continuousKey = "continuousRecordingHotkey"

    @Published private(set) var hotkey: Hotkey {
        didSet {
            save(hotkey, key: Self.pushToTalkKey)
        }
    }

    @Published private(set) var continuousHotkey: Hotkey {
        didSet {
            save(continuousHotkey, key: Self.continuousKey)
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.pushToTalkKey),
           let decoded = try? JSONDecoder().decode(Hotkey.self, from: data) {
            self.hotkey = decoded
        } else {
            self.hotkey = Hotkey.defaultHotkey
        }
        if let data = UserDefaults.standard.data(forKey: Self.continuousKey),
           let decoded = try? JSONDecoder().decode(Hotkey.self, from: data) {
            self.continuousHotkey = decoded
        } else {
            self.continuousHotkey = Hotkey.defaultContinuousHotkey
        }
    }

    func setHotkey(_ newHotkey: Hotkey) {
        guard hotkey != newHotkey else { return }
        hotkey = newHotkey
    }

    func resetToDefault() {
        setHotkey(Hotkey.defaultHotkey)
    }

    func setContinuousHotkey(_ newHotkey: Hotkey) {
        guard continuousHotkey != newHotkey else { return }
        continuousHotkey = newHotkey
    }

    func resetContinuousToDefault() {
        setContinuousHotkey(Hotkey.defaultContinuousHotkey)
    }

    private func save(_ hotkey: Hotkey, key: String) {
        if let encoded = try? JSONEncoder().encode(hotkey) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}
