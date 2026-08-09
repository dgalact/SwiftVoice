import AppKit
import SwiftUI

enum HotkeyRecorderKind {
    case pushToTalk
    case continuous
    case systemAudio
}

struct HotkeyRecorderView: View {
    let kind: HotkeyRecorderKind
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var isRecording = false
    @State private var previewText: String?
    @State private var pendingModifierHotkey: Hotkey?
    @State private var eventMonitor: Any?

    private var selectedHotkey: Hotkey {
        switch kind {
        case .pushToTalk: hotkeyManager.hotkey
        case .continuous: hotkeyManager.continuousHotkey
        case .systemAudio: hotkeyManager.systemAudioHotkey
        }
    }

    private var defaultHotkey: Hotkey {
        switch kind {
        case .pushToTalk: .defaultHotkey
        case .continuous: .defaultContinuousHotkey
        case .systemAudio: .defaultSystemAudioHotkey
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isRecording {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption2)
                            Text(previewText ?? loc.string("lbl_recording_hotkey"))
                                .fontWeight(.medium)
                        } else {
                            Image(systemName: "keyboard")
                                .foregroundStyle(.secondary)
                            Text(selectedHotkey.displayString)
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .accentColor : .gray)

                if isRecording {
                    Button(loc.string("btn_add") == "Add" ? "Cancel" : (loc.string("btn_add") == "Додати" ? "Скасувати" : "Отмена")) {
                        stopRecording()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if selectedHotkey != defaultHotkey {
                    Button(loc.string("btn_reset_default")) {
                        resetToDefault()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if selectedHotkey.isSystemConflict {
                Text(loc.string("warn_system_conflict"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }
            if hasDuplicateAssignment {
                Text(loc.string("warn_hotkeys_same"))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        previewText = nil
        pendingModifierHotkey = nil
        stopRecordingMonitor()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Escape cancels recording
            if event.type == .keyDown && event.keyCode == 53 {
                self.stopRecording()
                return nil
            }

            // Delete / Backspace resets to default
            if event.type == .keyDown && event.keyCode == 51 {
                self.resetToDefault()
                self.stopRecording()
                return nil
            }

            if event.type == .flagsChanged {
                let code = event.keyCode
                let modifierKeycodes: Set<UInt16> = [61, 58, 62, 59, 54, 55, 60, 56, 63]
                if modifierKeycodes.contains(code) {
                    let flags = event.modifierFlags
                    var isPressed = false
                    switch code {
                    case 61, 58: isPressed = flags.contains(.option)
                    case 62, 59: isPressed = flags.contains(.control)
                    case 54, 55: isPressed = flags.contains(.command)
                    case 60, 56: isPressed = flags.contains(.shift)
                    case 63: isPressed = flags.contains(.function)
                    default: isPressed = false
                    }

                    if isPressed {
                        let candidate = Hotkey(
                            keyCode: code,
                            modifierFlagsRaw: event.modifierFlags.rawValue,
                            isModifierOnly: true
                        )
                        self.pendingModifierHotkey = candidate
                        self.previewText = candidate.displayString + "…"
                    } else if let candidate = self.pendingModifierHotkey {
                        self.apply(candidate)
                        self.stopRecording()
                    }
                    return nil
                }
            } else if event.type == .keyDown {
                // Key combination (e.g. B while Ctrl is held down)
                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
                let recorded = Hotkey(
                    keyCode: event.keyCode,
                    modifierFlagsRaw: flags.rawValue,
                    isModifierOnly: false
                )
                self.apply(recorded)
                self.stopRecording()
                return nil
            }

            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        previewText = nil
        pendingModifierHotkey = nil
        stopRecordingMonitor()
    }

    private func stopRecordingMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }


    private func apply(_ hotkey: Hotkey) {
        switch kind {
        case .pushToTalk:
            hotkeyManager.setHotkey(hotkey)
        case .continuous:
            hotkeyManager.setContinuousHotkey(hotkey)
        case .systemAudio:
            hotkeyManager.setSystemAudioHotkey(hotkey)
        }
    }

    private func resetToDefault() {
        switch kind {
        case .pushToTalk:
            hotkeyManager.resetToDefault()
        case .continuous:
            hotkeyManager.resetContinuousToDefault()
        case .systemAudio:
            hotkeyManager.resetSystemAudioToDefault()
        }
    }

    private var hasDuplicateAssignment: Bool {
        let hotkeys = [
            hotkeyManager.hotkey,
            hotkeyManager.continuousHotkey,
            hotkeyManager.systemAudioHotkey
        ]
        return hotkeys.filter { $0 == selectedHotkey }.count > 1
    }
}
