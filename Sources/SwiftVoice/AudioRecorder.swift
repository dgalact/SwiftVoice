@preconcurrency import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioRecorder: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var tapState: AudioTapState?
    private var startTime: Date?
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
        let tapState = AudioTapState(file: file)
        let tapHandler = Self.makeTapHandler(state: tapState) { [weak self] level in
            Task { @MainActor [weak self] in
                self?.audioLevel = level
            }
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: inputFormat,
            block: tapHandler
        )

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.tapState = tapState
        self.recordingURL = url
        self.startTime = Date()
        self.isRecording = true
    }

    func stop() -> Recording? {
        guard isRecording, let engine = audioEngine, engine.isRunning else { return nil }

        isRecording = false
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0

        engine.inputNode.removeTap(onBus: 0)
        tapState?.finish()
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        engine.stop()

        self.audioEngine = nil
        self.tapState = nil
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
        tapState?.finish()
        tapState = nil
        isRecording = false
        audioLevel = 0.0
    }

    nonisolated private static func makeTapHandler(
        state: AudioTapState,
        updateLevel: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            state.process(buffer: buffer, updateLevel: updateLevel)
        }
    }
}

private final class AudioTapState: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.swiftvoice.audiowrite", qos: .userInitiated)
    private var file: AVAudioFile?

    init(file: AVAudioFile) {
        self.file = file
    }

    func process(buffer: AVAudioPCMBuffer, updateLevel: @Sendable (Float) -> Void) {
        if let channelData = buffer.floatChannelData?[0] {
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0.0
            for index in 0..<frameLength {
                let sample = channelData[index]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(max(1, frameLength)))
            updateLevel(max(0.0, min(1.0, rms * 6.0)))
        }

        guard let bufferCopy = buffer.copy() as? AVAudioPCMBuffer else { return }
        queue.async { [weak self] in
            guard let file = self?.file else { return }
            try? file.write(from: bufferCopy)
        }
    }

    func finish() {
        queue.sync {}
        file = nil
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
