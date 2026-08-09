import AppKit
import Combine
import CoreAudio
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private var cancellables = Set<AnyCancellable>()

    init(dictionary: DictionaryStore) {
        let root = SettingsView(dictionary: dictionary)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = LocalizationManager.shared.string("app_settings_title")
        window.setContentSize(NSSize(width: 720, height: 500))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)

        LocalizationManager.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak window] _ in
                window?.title = LocalizationManager.shared.string("app_settings_title")
            }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct SettingsView: View {
    @ObservedObject var dictionary: DictionaryStore
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(loc.string("tab_general"), systemImage: "gearshape") }
            DictionarySettingsView(dictionary: dictionary)
                .tabItem { Label(loc.string("tab_dictionary"), systemImage: "book") }
            RecognitionSettingsView()
                .tabItem { Label(loc.string("tab_recognition"), systemImage: "waveform") }
            FileTranscriptionView()
                .tabItem { Label(loc.string("tab_transcription"), systemImage: "doc.text.magnifyingglass") }
            AboutSettingsView()
                .tabItem { Label(loc.string("tab_about"), systemImage: "info.circle") }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 460)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var devices: [AudioInputDevice] = []
    @State private var selectedDeviceID: UInt32 = 0
    @State private var switchError: String?
    @AppStorage(DictationOverlayManager.enabledKey) private var showDictationOverlay = true
    @State private var launchAtLogin = false
    @State private var loginItemStatus = ""
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section(loc.string("sec_dictation")) {
                Picker(loc.string("lbl_language"), selection: Binding(
                    get: { loc.language },
                    set: { loc.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName(in: loc.language)).tag(lang)
                    }
                }

                LabeledContent(loc.string("lbl_push_to_talk")) {
                    HotkeyRecorderView(kind: .pushToTalk)
                }
                LabeledContent(loc.string("lbl_continuous_recording")) {
                    HotkeyRecorderView(kind: .continuous)
                }
                Toggle(loc.string("lbl_show_overlay"), isOn: $showDictationOverlay)
                LabeledContent(loc.string("lbl_processing")) {
                    Text(loc.string("val_processing"))
                }
                Toggle(loc.string("lbl_launch_at_login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LoginItemManager.setEnabled(enabled)
                            loginItemError = nil
                        } catch {
                            loginItemError = error.localizedDescription
                        }
                        refreshLoginItemStatus()
                    }
                LabeledContent(loc.string("lbl_autostart_status")) {
                    Text(loginItemStatus)
                        .foregroundStyle(
                            (loginItemStatus == loc.string("status_enabled")) ? Color.secondary : Color.orange
                        )
                }
                if let loginItemError {
                    Text(loginItemError)
                        .foregroundStyle(.red)
                }
            }

            Section(loc.string("sec_microphone")) {
                Picker(loc.string("lbl_input_device"), selection: $selectedDeviceID) {
                    ForEach(devices, id: \.id) { device in
                        Text(device.name).tag(UInt32(device.id))
                    }
                }
                .onChange(of: selectedDeviceID) { _, newValue in
                    guard newValue != 0 else { return }
                    do {
                        try AudioDevices.setDefaultInputDevice(AudioDeviceID(newValue))
                        switchError = nil
                    } catch {
                        switchError = error.localizedDescription
                    }
                }

                if let switchError {
                    Text(switchError)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            devices = AudioDevices.inputDevices()
            selectedDeviceID = UInt32(AudioDevices.defaultInputDevice()?.id ?? 0)
            launchAtLogin = UserDefaults.standard.bool(forKey: LoginItemSettings.enabledKey)
                || LoginItemManager.isEnabled
            refreshLoginItemStatus()
        }
        .onChange(of: loc.language) { _, _ in
            refreshLoginItemStatus()
        }
    }

    private func refreshLoginItemStatus() {
        loginItemStatus = LoginItemManager.statusDescription
    }
}

private struct DictionarySettingsView: View {
    @ObservedObject var dictionary: DictionaryStore
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var selection: DictionaryEntry.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc.string("desc_dictionary"))
                .foregroundStyle(.secondary)

            Table($dictionary.entries, selection: $selection) {
                TableColumn(loc.string("col_canonical")) { $entry in
                    TextField(loc.string("ph_canonical"), text: $entry.canonical)
                }
                .width(min: 160, ideal: 200)

                TableColumn(loc.string("col_aliases")) { $entry in
                    TextField(
                        loc.string("ph_aliases"),
                        text: Binding(
                            get: { entry.aliases.joined(separator: ", ") },
                            set: { value in
                                entry.aliases = value
                                    .split(separator: ",")
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .filter { !$0.isEmpty }
                            }
                        )
                    )
                }
            }

            HStack {
                Button {
                    dictionary.entries.append(
                        DictionaryEntry(canonical: loc.string("txt_new_word"), aliases: [])
                    )
                } label: {
                    Label(loc.string("btn_add"), systemImage: "plus")
                }

                Button {
                    guard let selection else { return }
                    dictionary.entries.removeAll { $0.id == selection }
                    self.selection = nil
                } label: {
                    Label(loc.string("btn_remove"), systemImage: "minus")
                }
                .disabled(selection == nil)

                Button {
                    importDictionary()
                } label: {
                    Label(loc.string("btn_import"), systemImage: "square.and.arrow.down")
                }

                Button {
                    exportDictionary()
                } label: {
                    Label(loc.string("btn_export"), systemImage: "square.and.arrow.up")
                }
                .disabled(dictionary.entries.isEmpty)

                Spacer()
                Text("\(dictionary.entries.count) \(loc.string("txt_terms_count"))")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private func importDictionary() {
        let panel = NSOpenPanel()
        panel.title = loc.string("dlg_import_title")
        panel.allowedContentTypes = [.json, .commaSeparatedText, .plainText]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                if url.pathExtension.lowercased() == "json" {
                    try dictionary.importJSON(data)
                } else {
                    let text = String(decoding: data, as: UTF8.self)
                    dictionary.importCSV(text)
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Import Error"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    private func exportDictionary() {
        let panel = NSSavePanel()
        panel.title = loc.string("dlg_export_title")
        panel.nameFieldStringValue = "swiftvoice-dictionary.json"
        panel.allowedContentTypes = [.json, .commaSeparatedText]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                if url.pathExtension.lowercased() == "csv" {
                    let csv = dictionary.exportCSV()
                    try csv.write(to: url, atomically: true, encoding: .utf8)
                } else {
                    let data = try dictionary.exportJSON()
                    try data.write(to: url, options: .atomic)
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Error"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}

private struct RecognitionSettingsView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var downloader = ModelDownloader.shared
    @AppStorage(Settings.modelPathKey) private var modelPath = ""
    @State private var selectedPreset: ModelPreset = .largeV3Turbo

    var body: some View {
        Form {
            Section(loc.string("sec_engine")) {
                LabeledContent("whisper.cpp") {
                    Text("v1.9.2 · \(loc.string("engine_bundled"))")
                        .foregroundStyle(.secondary)
                }
            }

            Section(loc.string("sec_model")) {
                Picker(loc.string("sec_model"), selection: $selectedPreset) {
                    ForEach(ModelPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .onChange(of: selectedPreset) { _, newPreset in
                    if newPreset != .custom, let expectedURL = newPreset.expectedURL {
                        modelPath = expectedURL.path
                    }
                }

                if selectedPreset != .custom {
                    HStack {
                        if selectedPreset.exists {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(loc.string("lbl_status_ready"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                            Text(loc.string("lbl_status_not_downloaded"))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            if downloader.isDownloading {
                                Button(loc.string("btn_cancel_download")) {
                                    downloader.cancel()
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            } else {
                                Button(loc.string("btn_download_model")) {
                                    downloader.download(selectedPreset) { downloadedURL in
                                        if let downloadedURL {
                                            modelPath = downloadedURL.path
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .font(.caption)
                            }
                        }
                    }

                    if !modelPath.isEmpty {
                        Text(modelPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }

                    if downloader.isDownloading {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: downloader.progress)
                            Text(downloader.statusText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = downloader.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                } else {
                    pathRow(
                        title: "GGML File",
                        path: modelPath,
                        action: { chooseFile(title: loc.string("dlg_choose_model"), binding: $modelPath) }
                    )
                }

                LabeledContent(loc.string("lbl_language_detect")) {
                    Text(loc.string("val_auto_detect"))
                }
            }

            Section(loc.string("sec_privacy")) {
                Text(loc.string("desc_privacy"))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            selectedPreset = ModelPreset.detectPreset(forPath: modelPath)
            if selectedPreset != .custom, let expectedURL = selectedPreset.expectedURL {
                modelPath = expectedURL.path
            }
        }
    }

    @ViewBuilder
    private func pathRow(title: String, path: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Button(loc.string("btn_choose"), action: action)
            }
            Text(path.isEmpty ? loc.string("val_not_selected") : path)
                .font(.caption)
                .foregroundStyle(path.isEmpty ? .red : .secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private func chooseFile(title: String, binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        let currentPath = binding.wrappedValue
        let defaultFolder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SwiftVoice/models", isDirectory: true)
        if !currentPath.isEmpty {
            let url = URL(fileURLWithPath: currentPath)
            if FileManager.default.fileExists(atPath: url.path) {
                panel.directoryURL = url.deletingLastPathComponent()
            } else {
                panel.directoryURL = defaultFolder
            }
        } else {
            panel.directoryURL = defaultFolder
        }

        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
        }
    }
}

private struct AboutSettingsView: View {
    @ObservedObject private var loc = LocalizationManager.shared

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if let iconURL = Bundle.main.url(forResource: "SwiftVoiceIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: iconURL) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
            } else {
                Image(systemName: "waveform.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 4) {
                Text("SwiftVoice")
                    .font(.title2)
                    .bold()
                Text("\(loc.string("lbl_version")) \(appVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(loc.string("desc_about"))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                Text(loc.string("lbl_license"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Link(destination: URL(string: "https://github.com/dgalact/SwiftVoice")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("GitHub Repository")
                    }
                    .font(.caption)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
