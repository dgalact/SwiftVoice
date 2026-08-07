@preconcurrency import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioRecorder: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private nonisolated(unsafe) var audioFile: AVAudioFile?
    private var startTime: Date?
    private let writeQueue = DispatchQueue(label: "org.swiftvoice.audiowrite", qos: .userInitiated)
    private(set) var recordingURL: URL?
    @Published var audioLevel: Float = 0.0

    var isRecording: Bool {
        audioEngine?.isRunning == true
    }

    func start() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw DictationError.microphonePermissionMissing
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            print("[SwiftVoice] Voice processing not supported on this device: \(error)")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftvoice-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let inputFormat = inputNode.outputFormat(forBus: 0)
        let file = try AVAudioFile(forWriting: url, settings: inputFormat.settings)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            if let channelData = buffer.floatChannelData?[0] {
                let channelDataPointer = channelData
                let frameLength = Int(buffer.frameLength)
                var sum: Float = 0.0
                for i in 0..<frameLength {
                    let sample = channelDataPointer[i]
                    sum += sample * sample
                }
                let rms = sqrt(sum / Float(max(1, frameLength)))
                let level = max(0.0, min(1.0, rms * 6.0))
                Task { @MainActor in
                    self.audioLevel = level
                }
            }

            guard let bufferCopy = buffer.copy() as? AVAudioPCMBuffer else { return }

            self.writeQueue.async {
                guard let file = self.audioFile else { return }
                try? file.write(from: bufferCopy)
            }
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.audioFile = file
        self.recordingURL = url
        self.startTime = Date()
    }

    func stop() -> Recording? {
        guard let engine = audioEngine, engine.isRunning else { return nil }

        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        engine.inputNode.removeTap(onBus: 0)
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        engine.stop()

        writeQueue.sync {}

        self.audioEngine = nil
        self.audioFile = nil
        self.audioLevel = 0.0

        guard let recordingURL else { return nil }
        return Recording(url: recordingURL, duration: duration)
    }
}

struct Recording {
    let url: URL
    let duration: TimeInterval
}

enum DictationError: LocalizedError {
    case recordingFailed
    case microphonePermissionMissing
    case recordingTooShort
    case missingConfiguration
    case transcriptionFailed(String)
    case emptyTranscription
    case accessibilityPermissionMissing

    var errorDescription: String? {
        let loc = LocalizationManager.shared
        switch self {
        case .recordingFailed:
            return loc.string("err_rec_failed")
        case .microphonePermissionMissing:
            return loc.string("err_mic_perm")
        case .recordingTooShort:
            return loc.string("err_rec_short")
        case .missingConfiguration:
            return loc.string("err_missing_config")
        case let .transcriptionFailed(details):
            return "\(loc.string("err_transcription_failed")) \(details)"
        case .emptyTranscription:
            return loc.string("err_empty_transcription")
        case .accessibilityPermissionMissing:
            return loc.string("err_acc_perm")
        }
    }
}
