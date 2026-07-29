import AVFoundation
import Foundation

@MainActor
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private(set) var recordingURL: URL?

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    func start() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw DictationError.microphonePermissionMissing
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-\(UUID().uuidString)")
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
        guard recorder.prepareToRecord(), recorder.record() else {
            throw DictationError.recordingFailed
        }

        self.recorder = recorder
        recordingURL = url
    }

    func stop() -> Recording? {
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
        switch self {
        case .recordingFailed:
            return "Аудиоустройство не начало запись."
        case .microphonePermissionMissing:
            return "Разреши Jarvis доступ к микрофону в Privacy & Security → Microphone."
        case .recordingTooShort:
            return "Запись короче 0,5 секунды. Удерживай паузу между включением и выключением диктовки."
        case .missingConfiguration:
            return "Не выбраны whisper-cli или модель."
        case let .transcriptionFailed(details):
            return "whisper-cli завершился с ошибкой: \(details)"
        case .emptyTranscription:
            return "Модель не вернула текст."
        case .accessibilityPermissionMissing:
            return "Разреши Jarvis управлять компьютером в Privacy & Security → Accessibility."
        }
    }
}
