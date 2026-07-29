import AppKit
import ApplicationServices
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let recorder = AudioRecorder()
    private let transcriber = WhisperTranscriber()
    private let dictionaryStore = DictionaryStore()
    private var settingsWindowController: SettingsWindowController?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var permissionRetryTimer: Timer?
    private var isRightOptionDown = false
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var microphoneMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var isBusy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "JarvisIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        buildMenu()
        LoginItemManager.applySavedPreference()
        requestPermissions()
        installPushToTalkWhenAuthorized()
        refreshConfigurationStatus()
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

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = MenuBarIcon.make()
        statusItem.button?.image?.accessibilityDescription = "Jarvis"

        let menu = NSMenu()
        menu.delegate = self
        statusMenuItem = NSMenuItem(title: "Проверяю конфигурацию…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        microphoneMenuItem = NSMenuItem(title: "Микрофон: определяю…", action: nil, keyEquivalent: "")
        microphoneMenuItem.submenu = NSMenu()
        menu.addItem(microphoneMenuItem)
        menu.addItem(.separator())

        toggleMenuItem = NSMenuItem(
            title: "Начать диктовку",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        menu.addItem(.separator())
        let settings = NSMenuItem(
            title: "Настройки…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Завершить", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        refreshMicrophoneMenu()
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

            guard type == .flagsChanged,
                  event.getIntegerValueField(.keyboardEventKeycode) == 61
            else {
                return Unmanaged.passUnretained(event)
            }

            let isPressed = event.flags.contains(.maskAlternate)
            Task { @MainActor in
                delegate.handleRightOption(isPressed: isPressed)
            }
            return nil
        }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
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

    private func handleRightOption(isPressed: Bool) {
        guard isPressed != isRightOptionDown else { return }
        isRightOptionDown = isPressed

        if isPressed {
            guard !recorder.isRecording, !isBusy else { return }
            startRecording()
        } else if recorder.isRecording {
            stopAndTranscribe()
        }
    }

    @objc private func toggleRecording() {
        guard !isBusy else { return }

        if recorder.isRecording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard transcriber.isConfigured else {
            presentConfigurationError()
            return
        }

        do {
            try recorder.start()
            setState(title: "Запись… отпусти правый ⌥", symbol: "waveform.circle.fill")
            toggleMenuItem.title = "Остановить и распознать"
        } catch {
            showError("Не удалось начать запись", details: error.localizedDescription)
        }
    }

    private func stopAndTranscribe() {
        guard let recording = recorder.stop() else { return }
        isBusy = true
        toggleMenuItem.isEnabled = false
        setState(
            title: String(format: "Распознаю запись %.1f с…", recording.duration),
            symbol: "ellipsis.circle"
        )

        Task {
            do {
                guard recording.duration >= 0.5 else {
                    throw DictationError.recordingTooShort
                }
                try preserveDiagnosticRecording(recording.url)
                let text = try await transcriber.transcribe(
                    recording.url,
                    dictionary: dictionaryStore.entries
                )
                try TextInjector.type(text)
                setState(title: "Готово", symbol: "checkmark.circle")
            } catch {
                showError("Ошибка диктовки", details: error.localizedDescription)
            }

            try? FileManager.default.removeItem(at: recording.url)
            isBusy = false
            toggleMenuItem.isEnabled = true
            toggleMenuItem.title = "Начать диктовку"
            refreshConfigurationStatus()
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
            .appendingPathComponent("Library/Application Support/Jarvis", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let destination = support.appendingPathComponent("latest.wav")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
    }

    @objc private func selectWhisperExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Выбери исполняемый файл whisper-cli"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: Settings.whisperExecutableKey)
            refreshConfigurationStatus()
        }
    }

    @objc private func selectModel() {
        let panel = NSOpenPanel()
        panel.title = "Выбери модель Whisper в формате GGML"
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
            showError("Не удалось выбрать микрофон", details: error.localizedDescription)
        }
    }

    private func refreshMicrophoneMenu() {
        let devices = AudioDevices.inputDevices()
        let active = AudioDevices.defaultInputDevice()
        microphoneMenuItem?.title = "Микрофон: \(active?.name ?? "не выбран")"

        let submenu = NSMenu()
        if devices.isEmpty {
            let empty = NSMenuItem(title: "Входные устройства не найдены", action: nil, keyEquivalent: "")
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
        if transcriber.isConfigured {
            setState(title: "Готово · удерживай правый ⌥", symbol: "waveform.circle")
        } else {
            setState(title: "Нужны whisper-cli и модель", symbol: "exclamationmark.circle")
        }
    }

    private func setState(title: String, symbol: String) {
        statusMenuItem?.title = title
        statusItem?.button?.image = MenuBarIcon.make(isRecording: symbol == "waveform.circle.fill")
        statusItem?.button?.image?.accessibilityDescription = title
    }

    private func presentConfigurationError() {
        showError(
            "Диктовка не настроена",
            details: "Через меню выбери собранный whisper-cli и файл модели GGML."
        )
    }

    private func showError(_ message: String, details: String) {
        setState(title: "Ошибка", symbol: "xmark.circle")
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = details
        alert.alertStyle = .warning
        alert.runModal()
    }
}
