import AppKit
import Foundation

struct Hotkey: Codable, Equatable, Sendable {
    var keyCode: UInt16
    var modifierFlagsRaw: UInt
    var isModifierOnly: Bool

    static let defaultHotkey = Hotkey(
        keyCode: 61,
        modifierFlagsRaw: NSEvent.ModifierFlags.option.rawValue,
        isModifierOnly: true
    )

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRaw)
    }

    var displayString: String {
        if isModifierOnly {
            switch keyCode {
            case 61: return "Right ⌥"
            case 58: return "Left ⌥"
            case 62: return "Right ⌃"
            case 59: return "Left ⌃"
            case 54: return "Right ⌘"
            case 55: return "Left ⌘"
            case 60: return "Right ⇧"
            case 56: return "Left ⇧"
            case 63: return "Fn"
            default: return "Modifier (\(keyCode))"
            }
        }

        var parts: [String] = []
        let flags = modifierFlags

        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }

        let keyName = Hotkey.name(forKeyCode: keyCode)
        parts.append(keyName)
        return parts.joined()
    }

    var isSystemConflict: Bool {
        if isModifierOnly {
            return false
        }
        let flags = modifierFlags
        let hasCmd = flags.contains(.command)
        let hasCtrl = flags.contains(.control)

        if hasCmd {
            // ⌘C, ⌘V, ⌘X, ⌘Z, ⌘A, ⌘Q, ⌘W, ⌘M, ⌘H, ⌘Tab, ⌘Space
            let systemCmdKeys: Set<UInt16> = [8, 9, 7, 6, 0, 12, 13, 46, 4, 48, 49]
            if systemCmdKeys.contains(keyCode) {
                return true
            }
        }

        if hasCtrl && keyCode == 49 { // Ctrl+Space
            return true
        }

        if hasCtrl && (keyCode == 126 || keyCode == 125) { // Ctrl+Up, Ctrl+Down
            return true
        }

        return false
    }

    static func name(forKeyCode code: UInt16) -> String {
        switch code {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key \(code)"
        }
    }
}
