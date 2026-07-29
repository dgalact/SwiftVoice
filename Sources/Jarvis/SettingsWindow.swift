import AppKit
import CoreAudio
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(dictionary: DictionaryStore) {
        let root = SettingsView(dictionary: dictionary)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Настройки Jarvis"
        window.setContentSize(NSSize(width: 720, height: 480))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
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

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("Основные", systemImage: "gearshape") }
            DictionarySettingsView(dictionary: dictionary)
                .tabItem { Label("Словарь", systemImage: "book") }
            RecognitionSettingsView()
                .tabItem { Label("Распознавание", systemImage: "waveform") }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 440)
    }
}

private struct GeneralSettingsView: View {
    @State private var devices: [AudioInputDevice] = []
    @State private var selectedDeviceID: UInt32 = 0
    @State private var switchError: String?
    @State private var launchAtLogin = false
    @State private var loginItemStatus = ""
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section("Диктовка") {
                LabeledContent("Push-to-talk") {
                    Text("Удерживай правый ⌥")
                }
                LabeledContent("Обработка") {
                    Text("Локально на этом Mac")
                }
                Toggle("Запускать Jarvis при входе в macOS", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LoginItemManager.setEnabled(enabled)
                            loginItemError = nil
                        } catch {
                            loginItemError = error.localizedDescription
                        }
                        refreshLoginItemStatus()
                    }
                LabeledContent("Автозагрузка") {
                    Text(loginItemStatus)
                        .foregroundStyle(
                            loginItemStatus == "Включён" ? Color.secondary : Color.orange
                        )
                }
                if let loginItemError {
                    Text(loginItemError)
                        .foregroundStyle(.red)
                }
            }

            Section("Микрофон") {
                Picker("Устройство ввода", selection: $selectedDeviceID) {
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
    }

    private func refreshLoginItemStatus() {
        loginItemStatus = LoginItemManager.statusDescription
    }
}

private struct DictionarySettingsView: View {
    @ObservedObject var dictionary: DictionaryStore
    @State private var selection: DictionaryEntry.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Термины подсказываются Whisper и нормализуются перед вставкой.")
                .foregroundStyle(.secondary)

            Table($dictionary.entries, selection: $selection) {
                TableColumn("Правильное написание") { $entry in
                    TextField("FortiGate", text: $entry.canonical)
                }
                .width(min: 160, ideal: 200)

                TableColumn("Варианты произношения через запятую") { $entry in
                    TextField(
                        "фортигейт, форти гейт",
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
                        DictionaryEntry(canonical: "Новое слово", aliases: [])
                    )
                } label: {
                    Label("Добавить", systemImage: "plus")
                }

                Button {
                    guard let selection else { return }
                    dictionary.entries.removeAll { $0.id == selection }
                    self.selection = nil
                } label: {
                    Label("Удалить", systemImage: "minus")
                }
                .disabled(selection == nil)

                Spacer()
                Text("\(dictionary.entries.count) терминов")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }
}

private struct RecognitionSettingsView: View {
    @AppStorage(Settings.whisperExecutableKey) private var executablePath = ""
    @AppStorage(Settings.modelPathKey) private var modelPath = ""

    var body: some View {
        Form {
            Section("Движок") {
                pathRow(
                    title: "whisper-cli",
                    path: executablePath,
                    action: { chooseFile(title: "Выбери whisper-cli", binding: $executablePath) }
                )
            }

            Section("Модель") {
                pathRow(
                    title: "GGML",
                    path: modelPath,
                    action: { chooseFile(title: "Выбери модель Whisper", binding: $modelPath) }
                )
                LabeledContent("Язык") {
                    Text("Определяется автоматически")
                }
            }

            Section("Конфиденциальность") {
                Text("Запись и распознавание выполняются локально. Сетевые API не используются.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func pathRow(title: String, path: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Button("Выбрать…", action: action)
            }
            Text(path.isEmpty ? "Не выбрано" : path)
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
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
        }
    }
}
