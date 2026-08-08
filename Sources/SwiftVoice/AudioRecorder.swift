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
    @Published var isRecording = false

    func start() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw DictationError.microphonePermissionMissing
        }

        stopEngine()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        if !AudioDevices.isCurrentInputBluetoothOrHeadset() {
            try? inputNode.setVoiceProcessingEnabled(true)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftvoice-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            throw DictationError.recordingFailed
        }

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
        self.isRecording = true
    }

    func stop() -> Recording? {
        guard isRecording, let engine = audioEngine, engine.isRunning else { return nil }

        isRecording = false
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0

        engine.inputNode.removeTap(onBus: 0)
        writeQueue.sync {}
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        engine.stop()

        self.audioEngine = nil
        self.audioFile = nil
        self.audioLevel = 0.0

        guard let recordingURL else { return nil }
        return Recording(url: recordingURL, duration: duration)
    }

    private func stopEngine() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            try? engine.inputNode.setVoiceProcessingEnabled(false)
            engine.stop()
        }
        audioEngine = nil
        audioFile = nil
        isRecording = false
        audioLevel = 0.0
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
