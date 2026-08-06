import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioRecorder: ObservableObject {
    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private(set) var recordingURL: URL?
    @Published var audioLevel: Float = 0.0

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    func start() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw DictationError.microphonePermissionMissing
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftvoice-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw DictationError.recordingFailed
        }

        self.recorder = recorder
        recordingURL = url

        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder, recorder.isRecording else { return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                let normalized = max(0, min(1, (power + 60) / 60))
                self.audioLevel = normalized
            }
        }
    }

    func stop() -> Recording? {
        levelTimer?.invalidate()
        levelTimer = nil
        audioLevel = 0.0
        let duration = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
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
