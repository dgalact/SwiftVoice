import AppKit
import ApplicationServices
import AVFoundation
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum RecordingMode {
        case pushToTalk
        case continuous
    }

    private let recorder = AudioRecorder()
    private let transcriber = WhisperTranscriber()
    private let dictionaryStore = DictionaryStore()
    private var settingsWindowController: SettingsWindowController?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var permissionRetryTimer: Timer?
    private var isHotkeyKeyDown = false
    private var recordingMode: RecordingMode?
    private var lastTranscription: String?
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var microphoneMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var copyLastTextMenuItem: NSMenuItem!
    private var settingsMenuItem: NSMenuItem!
    private var quitMenuItem: NSMenuItem!
    private var isBusy = false
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "SwiftVoiceIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        buildMenu()
        LoginItemManager.applySavedPreference()
        requestPermissions()
        installPushToTalkWhenAuthorized()
        refreshConfigurationStatus()

        LocalizationManager.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateLocalizedMenuTitles()
            }
            .store(in: &cancellables)

        HotkeyManager.shared.$hotkey
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateLocalizedMenuTitles()
            }
            .store(in: &cancellables)

        HotkeyManager.shared.$continuousHotkey
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateLocalizedMenuTitles()
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionRetryTimer?.invalidate()
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        eventTap = nil
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showSettings()
        return true
    }

    private var aboutMenuItem: NSMenuItem!

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = MenuBarIcon.make()
        statusItem.button?.image?.accessibilityDescription = "SwiftVoice"

        let loc = LocalizationManager.shared
        let menu = NSMenu()
        menu.delegate = self
        statusMenuItem = NSMenuItem(title: loc.string("menu_checking"), action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        microphoneMenuItem = NSMenuItem(title: loc.string("menu_mic_detecting"), action: nil, keyEquivalent: "")
        microphoneMenuItem.submenu = NSMenu()
        menu.addItem(microphoneMenuItem)
        menu.addItem(.separator())

        toggleMenuItem = NSMenuItem(
            title: "\(loc.string("menu_continuous_start")): \(HotkeyManager.shared.continuousHotkey.displayString)",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        copyLastTextMenuItem = NSMenuItem(
            title: loc.string("menu_copy_last"),
            action: #selector(copyLastText),
            keyEquivalent: ""
        )
        copyLastTextMenuItem.target = self
        copyLastTextMenuItem.isEnabled = false
        menu.addItem(copyLastTextMenuItem)

        menu.addItem(.separator())
        settingsMenuItem = NSMenuItem(
            title: loc.string("menu_settings"),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)

        quitMenuItem = NSMenuItem(title: loc.string("menu_quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitMenuItem)
        statusItem.menu = menu
        refreshMicrophoneMenu()
    }

    private func updateLocalizedMenuTitles() {
        let loc = LocalizationManager.shared
        settingsMenuItem?.title = loc.string("menu_settings")
        quitMenuItem?.title = loc.string("menu_quit")
        copyLastTextMenuItem?.title = loc.string("menu_copy_last")
        if !recorder.isRecording && !isBusy {
            toggleMenuItem?.title = "\(loc.string("menu_continuous_start")): \(HotkeyManager.shared.continuousHotkey.displayString)"
        }
        refreshMicrophoneMenu()
        refreshConfigurationStatus()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMicrophoneMenu()
    }

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func installPushToTalkWhenAuthorized() {
        if installPushToTalk() {
            permissionRetryTimer?.invalidate()
            permissionRetryTimer = nil
            return
        }

        permissionRetryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.installPushToTalk() else { return }
                self.permissionRetryTimer?.invalidate()
                self.permissionRetryTimer = nil
            }
        }
    }

    @discardableResult
    private func installPushToTalk() -> Bool {
        guard eventTap == nil, AXIsProcessTrusted() else {
            return eventTap != nil
        }

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let eventTap = delegate.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            let hotkeyManager = HotkeyManager.shared
            let hotkey = hotkeyManager.hotkey
            let continuousHotkey = hotkeyManager.continuousHotkey
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

            if type == .keyDown,
               code == 53,
               delegate.recordingMode == .continuous {
                Task { @MainActor in delegate.stopContinuousRecording() }
                return nil
            }

            if !continuousHotkey.isModifierOnly,
               type == .keyDown,
               code == continuousHotkey.keyCode,
               delegate.modifiersMatch(event.flags, hotkey: continuousHotkey),
               event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                Task { @MainActor in delegate.toggleContinuousRecording() }
                return nil
            }


            if continuousHotkey.isModifierOnly,
               type == .flagsChanged,
               code == continuousHotkey.keyCode,
               delegate.modifierIsPressed(code: code, flags: event.flags) {
                Task { @MainActor in delegate.toggleContinuousRecording() }
                return nil
            }

            if hotkey.isModifierOnly {
                if type == .flagsChanged, code == hotkey.keyCode {
                    let flags = event.flags
                    var isPressed = false
                    switch code {
                    case 61, 58: isPressed = flags.contains(.maskAlternate)
                    case 62, 59: isPressed = flags.contains(.maskControl)
                    case 54, 55: isPressed = flags.contains(.maskCommand)
                    case 60, 56: isPressed = flags.contains(.maskShift)
                    case 63: isPressed = flags.contains(.maskSecondaryFn)
                    default: isPressed = false
                    }
                    Task { @MainActor in
                        delegate.handlePushToTalk(isPressed: isPressed)
                    }
                    return nil
                }
            } else {
                if type == .keyDown, code == hotkey.keyCode {
                    if delegate.modifiersMatch(event.flags, hotkey: hotkey) {
                        Task { @MainActor in
                            delegate.handlePushToTalk(isPressed: true)
                        }
                        return nil
                    }
                } else if type == .keyUp, code == hotkey.keyCode {
                    Task { @MainActor in
                        delegate.handlePushToTalk(isPressed: false)
                    }
                    return nil
                }
            }

            return Unmanaged.passUnretained(event)
        }

        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        )

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventTapSource = source
        return true
    }

    private func handlePushToTalk(isPressed: Bool) {
        guard isPressed != isHotkeyKeyDown else { return }
        isHotkeyKeyDown = isPressed

        if isPressed {
            guard !recorder.isRecording, !isBusy else { return }
            startRecording(mode: .pushToTalk)
        } else if recorder.isRecording, recordingMode == .pushToTalk {
            stopAndTranscribe()
        }
    }

    @objc private func toggleRecording() {
        toggleContinuousRecording()
    }

    private func toggleContinuousRecording() {
        guard !isBusy else { return }

        if recorder.isRecording, recordingMode == .continuous {
            stopAndTranscribe()
        } else if !recorder.isRecording {
            startRecording(mode: .continuous)
        }
    }

    private func stopContinuousRecording() {
        guard recorder.isRecording, recordingMode == .continuous else { return }
        stopAndTranscribe()
    }

    private func startRecording(mode: RecordingMode) {
        guard transcriber.isConfigured else {
            presentConfigurationError()
            return
        }

        do {
            try recorder.start()
            recordingMode = mode
            DictationOverlayManager.shared.showRecording(recorder: recorder)
            let loc = LocalizationManager.shared
            if mode == .continuous {
                toggleMenuItem.title = loc.string("menu_continuous_stop")
            }
            setState(title: loc.string("menu_recording"), symbol: "waveform.circle.fill")
        } catch {
            showError(LocalizationManager.shared.string("err_rec_failed"), details: error.localizedDescription)
        }
    }

    private func stopAndTranscribe() {
        guard let recording = recorder.stop() else {
            DictationOverlayManager.shared.hide()
            return
        }
        recordingMode = nil
        isBusy = true
        toggleMenuItem.isEnabled = false
        DictationOverlayManager.shared.showTranscribing(recorder: recorder)
        let loc = LocalizationManager.shared
        setState(
            title: loc.string("menu_transcribing"),
            symbol: "ellipsis.circle"
        )

        Task {
            defer {
                DictationOverlayManager.shared.hide()
            }
            do {
                guard recording.duration >= 0.5 else {
                    throw DictationError.recordingTooShort
                }
                try preserveDiagnosticRecording(recording.url)
                let text = try await transcriber.transcribe(
                    recording.url,
                    dictionary: dictionaryStore.entries
                )
                lastTranscription = text
                copyLastTextMenuItem.isEnabled = true
                try TextInjector.type(text)
                setState(title: loc.string("menu_ready"), symbol: "checkmark.circle")
            } catch {
                showError("SwiftVoice", details: error.localizedDescription)
            }

            try? FileManager.default.removeItem(at: recording.url)
            isBusy = false
            toggleMenuItem.isEnabled = true
            toggleMenuItem.title = "\(loc.string("menu_continuous_start")): \(HotkeyManager.shared.continuousHotkey.displayString)"
            refreshConfigurationStatus()
        }
    }

    @objc private func copyLastText() {
        guard let lastTranscription else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscription, forType: .string)
    }

    private func modifiersMatch(_ flags: CGEventFlags, hotkey: Hotkey) -> Bool {
        let required = hotkey.modifierFlags
        return (!required.contains(.command) || flags.contains(.maskCommand))
            && (!required.contains(.option) || flags.contains(.maskAlternate))
            && (!required.contains(.control) || flags.contains(.maskControl))
            && (!required.contains(.shift) || flags.contains(.maskShift))
    }

    private func modifierIsPressed(code: UInt16, flags: CGEventFlags) -> Bool {
        switch code {
        case 61, 58: return flags.contains(.maskAlternate)
        case 62, 59: return flags.contains(.maskControl)
        case 54, 55: return flags.contains(.maskCommand)
        case 60, 56: return flags.contains(.maskShift)
        case 63: return flags.contains(.maskSecondaryFn)
        default: return false
        }
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(dictionary: dictionaryStore)
        }
        settingsWindowController?.present()
    }

    private func preserveDiagnosticRecording(_ sourceURL: URL) throws {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SwiftVoice", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let destination = support.appendingPathComponent("latest.wav")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
    }

    @objc private func selectModel() {
        let loc = LocalizationManager.shared
        let panel = NSOpenPanel()
        panel.title = loc.string("dlg_choose_model")
        panel.allowedContentTypes = []
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: Settings.modelPathKey)
            refreshConfigurationStatus()
        }
    }

    @objc private func selectInputDevice(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        do {
            try AudioDevices.setDefaultInputDevice(AudioDeviceID(number.uint32Value))
            refreshMicrophoneMenu()
        } catch {
            showError("SwiftVoice", details: error.localizedDescription)
        }
    }

    private func refreshMicrophoneMenu() {
        let loc = LocalizationManager.shared
        let devices = AudioDevices.inputDevices()
        let active = AudioDevices.defaultInputDevice()
        microphoneMenuItem?.title = "\(loc.string("menu_mic_prefix")) \(active?.name ?? loc.string("menu_mic_unknown"))"

        let submenu = NSMenu()
        if devices.isEmpty {
            let empty = NSMenuItem(title: loc.string("menu_mic_unknown"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for device in devices {
                let item = NSMenuItem(
                    title: device.name,
                    action: #selector(selectInputDevice(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = NSNumber(value: device.id)
                item.state = device.id == active?.id ? .on : .off
                submenu.addItem(item)
            }
        }
        microphoneMenuItem?.submenu = submenu
    }

    private func refreshConfigurationStatus() {
        let loc = LocalizationManager.shared
        if transcriber.isConfigured {
            setState(title: loc.string("menu_ready"), symbol: "waveform.circle")
        } else {
            setState(title: loc.string("err_missing_config"), symbol: "exclamationmark.circle")
        }
    }

    private func setState(title: String, symbol: String) {
        statusMenuItem?.title = title
        statusItem?.button?.image = MenuBarIcon.make(isRecording: symbol == "waveform.circle.fill")
        statusItem?.button?.image?.accessibilityDescription = title
    }

    private func presentConfigurationError() {
        let loc = LocalizationManager.shared
        showError(
            "SwiftVoice",
            details: loc.string("err_missing_config")
        )
    }

    private func showError(_ message: String, details: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = details
        alert.alertStyle = .warning
        alert.runModal()
    }
}
