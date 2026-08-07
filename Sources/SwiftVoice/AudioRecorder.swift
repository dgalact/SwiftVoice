@preconcurrency import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioRecorder: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private nonisolated(unsafe) var audioFile: AVAudioFile?
    private nonisolated(unsafe) var isCapturing = false
    private var startTime: Date?
    private let writeQueue = DispatchQueue(label: "org.swiftvoice.audiowrite", qos: .userInitiated)
    private(set) var recordingURL: URL?
    @Published var audioLevel: Float = 0.0
    @Published var isRecording = false

    init() {
        ensureWarmEngine()
    }

    func ensureWarmEngine() {
        guard audioEngine == nil else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        if !AudioDevices.isCurrentInputBluetoothOrHeadset() {
            try? inputNode.setVoiceProcessingEnabled(true)
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            if self.isCapturing {
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
            } else {
                Task { @MainActor in
                    if self.audioLevel != 0.0 {
                        self.audioLevel = 0.0
                    }
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
            self.audioEngine = engine
        } catch {
            print("[SwiftVoice] Failed to start warm audio engine: \(error)")
        }
    }

    func start() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw DictationError.microphonePermissionMissing
        }

        ensureWarmEngine()

        guard let engine = audioEngine, engine.isRunning else {
            throw DictationError.recordingFailed
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftvoice-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        let file = try AVAudioFile(forWriting: url, settings: inputFormat.settings)

        self.audioFile = file
        self.recordingURL = url
        self.startTime = Date()
        self.isCapturing = true
        self.isRecording = true
    }

    func stop() -> Recording? {
        guard isCapturing else { return nil }

        isCapturing = false
        isRecording = false

        writeQueue.sync {}

        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0

        self.audioFile = nil
        self.audioLevel = 0.0

        guard let recordingURL else { return nil }
        return Recording(url: recordingURL, duration: duration)
    }

    func resetEngine() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        isCapturing = false
        isRecording = false
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
