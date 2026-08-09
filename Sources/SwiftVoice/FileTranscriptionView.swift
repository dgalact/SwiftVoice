import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class FileTranscriptionViewModel: ObservableObject {
    @Published var selectedURL: URL?
    @Published var durationText = ""
    @Published var result = ""
    @Published var statusText = ""
    @Published var errorText: String?
    @Published var isTranscribing = false

    private let transcriber = WhisperTranscriber()

    var isReady: Bool {
        selectedURL != nil && !isTranscribing
    }

    func select(_ url: URL) {
        guard AudioFileConverter.supportedExtensions.contains(url.pathExtension.lowercased()) else {
            errorText = LocalizationManager.shared.string("err_file_unsupported")
            return
        }

        selectedURL = url
        result = ""
        statusText = ""
        errorText = nil
        durationText = Self.durationDescription(for: url)
    }

    func transcribe() {
        guard let selectedURL, !isTranscribing else { return }
        guard transcriber.isConfigured else {
            errorText = LocalizationManager.shared.string("err_missing_config")
            return
        }

        isTranscribing = true
        errorText = nil
        result = ""
        statusText = LocalizationManager.shared.string("file_status_preparing")

        Task {
            var temporaryURL: URL?
            defer {
                if let temporaryURL {
                    try? FileManager.default.removeItem(at: temporaryURL)
                }
                isTranscribing = false
            }

            do {
                let wavURL = try await AudioFileConverter.convertToWhisperWAV(selectedURL)
                temporaryURL = wavURL
                statusText = LocalizationManager.shared.string("file_status_transcribing")
                result = try await transcriber.transcribe(wavURL, dictionary: [])
                statusText = LocalizationManager.shared.string("file_status_ready")
            } catch {
                statusText = ""
                errorText = error.localizedDescription
            }
        }
    }

    func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }

    func saveResult() {
        let panel = NSSavePanel()
        panel.title = LocalizationManager.shared.string("file_save_title")
        panel.nameFieldStringValue = selectedURL?
            .deletingPathExtension()
            .lastPathComponent
            .appending(".txt") ?? "transcription.txt"
        panel.allowedContentTypes = [.plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try result.write(to: url, atomically: true, encoding: .utf8)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    func clear() {
        selectedURL = nil
        durationText = ""
        result = ""
        statusText = ""
        errorText = nil
    }

    private static func durationDescription(for url: URL) -> String {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else {
            return ""
        }
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? ""
    }
}

struct FileTranscriptionView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @StateObject private var model = FileTranscriptionViewModel()
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc.string("file_description"))
                .foregroundStyle(.secondary)

            filePicker

            HStack {
                Button(loc.string("file_transcribe")) {
                    model.transcribe()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.isReady)

                if model.isTranscribing {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(model.statusText)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            if let errorText = model.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            TextEditor(text: $model.result)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25))
                }
                .disabled(model.isTranscribing)

            HStack {
                Button(loc.string("file_copy")) {
                    model.copyResult()
                }
                .disabled(model.result.isEmpty)

                Button(loc.string("file_save")) {
                    model.saveResult()
                }
                .disabled(model.result.isEmpty)

                Spacer()

                Button(loc.string("file_clear")) {
                    model.clear()
                }
                .disabled(model.selectedURL == nil && model.result.isEmpty)
            }
        }
        .padding(.top, 8)
    }

    private var filePicker: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.badge.plus")
                .font(.title2)
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.selectedURL?.lastPathComponent ?? loc.string("file_drop_prompt"))
                    .lineLimit(1)
                if let url = model.selectedURL {
                    Text([url.pathExtension.uppercased(), model.durationText]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("WAV, M4A, MP3, AAC")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(loc.string("file_choose")) {
                chooseFile()
            }
            .disabled(model.isTranscribing)
        }
        .padding(14)
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1, dash: [5])
                )
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard !model.isTranscribing, let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data,
                      let string = String(data: data, encoding: .utf8),
                      let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                Task { @MainActor in model.select(url) }
            }
            return true
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = loc.string("file_choose_title")
        panel.allowedContentTypes = AudioFileConverter.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            model.select(url)
        }
    }
}
