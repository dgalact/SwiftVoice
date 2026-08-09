import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
final class SystemAudioRecorder {
    private var stream: SCStream?
    private var output: SystemAudioCaptureOutput?
    private var startTime: Date?
    private(set) var isRecording = false

    func start(onChunk: @escaping @Sendable (URL) -> Void) async throws {
        guard !isRecording else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        guard let display = content.displays.first else {
            throw SystemAudioRecordingError.noDisplay
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftvoice-system-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let captureOutput = try SystemAudioCaptureOutput(url: url, onChunk: onChunk)
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: captureOutput)
        try stream.addStreamOutput(
            captureOutput,
            type: .audio,
            sampleHandlerQueue: captureOutput.queue
        )
        try await stream.startCapture()

        self.stream = stream
        self.output = captureOutput
        self.startTime = Date()
        self.isRecording = true
    }

    func stop() async throws -> Recording? {
        guard isRecording, let stream, let output else { return nil }
        isRecording = false
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0

        try await stream.stopCapture()
        let url = try await output.finish()
        self.stream = nil
        self.output = nil
        self.startTime = nil
        guard let url else { return nil }
        return Recording(url: url, duration: duration)
    }
}

private final class SystemAudioCaptureOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "org.swiftvoice.systemaudio", qos: .userInitiated)
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var started = false
    private var captureError: Error?
    private let onChunk: @Sendable (URL) -> Void
    private var chunkSamples: [Int16] = []
    private var overlapSamples: [Int16] = []
    private var freshSampleCount = 0
    private var silenceSampleCount = 0
    private var chunkHasAudio = false

    private let outputSampleRate = 16_000
    private let minimumChunkSamples = 5 * 16_000
    private let maximumChunkSamples = 10 * 16_000
    private let minimumSilenceSamples = 5_600
    private let overlapSampleCount = 8_000
    private let speechRMSThreshold: Float = 0.006

    init(url: URL, onChunk: @escaping @Sendable (URL) -> Void) throws {
        self.onChunk = onChunk
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ]
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw SystemAudioRecordingError.writerSetupFailed
        }
        writer.add(input)
        super.init()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio, sampleBuffer.isValid, captureError == nil else { return }

        if !started {
            guard writer.startWriting() else {
                captureError = writer.error ?? SystemAudioRecordingError.writerFailed
                return
            }
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            started = true
        }

        if input.isReadyForMoreMediaData, !input.append(sampleBuffer) {
            captureError = writer.error ?? SystemAudioRecordingError.writerFailed
        }

        do {
            try consumeForLiveText(sampleBuffer)
        } catch {
            captureError = error
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        captureError = error
    }

    func finish() async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                if let captureError {
                    writer.cancelWriting()
                    continuation.resume(throwing: captureError)
                    return
                }
                do {
                    try emitFinalChunkIfNeeded()
                } catch {
                    writer.cancelWriting()
                    continuation.resume(throwing: error)
                    return
                }
                guard started else {
                    writer.cancelWriting()
                    continuation.resume(returning: nil)
                    return
                }

                input.markAsFinished()
                writer.finishWriting { [self] in
                    if writer.status == .completed {
                        continuation.resume(returning: writer.outputURL)
                    } else {
                        continuation.resume(
                            throwing: writer.error ?? SystemAudioRecordingError.writerFailed
                        )
                    }
                }
            }
        }
    }

    private func consumeForLiveText(_ sampleBuffer: CMSampleBuffer) throws {
        guard let formatDescription = sampleBuffer.formatDescription,
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else { return }
        let asbd = asbdPointer.pointee
        let channelCount = max(1, Int(asbd.mChannelsPerFrame))
        let frameCount = sampleBuffer.numSamples
        guard frameCount > 0 else { return }

        var requiredSize = 0
        var blockBuffer: CMBlockBuffer?
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, requiredSize > 0 else { return }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: requiredSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        let audioBufferList = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: requiredSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let isNonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        var mono = [Float](repeating: 0, count: frameCount)

        if isFloat {
            for frame in 0..<frameCount {
                var sum: Float = 0
                if isNonInterleaved {
                    for channel in 0..<min(channelCount, buffers.count) {
                        guard let data = buffers[channel].mData else { continue }
                        sum += data.assumingMemoryBound(to: Float.self)[frame]
                    }
                } else if let data = buffers.first?.mData {
                    let samples = data.assumingMemoryBound(to: Float.self)
                    for channel in 0..<channelCount {
                        sum += samples[(frame * channelCount) + channel]
                    }
                }
                mono[frame] = sum / Float(channelCount)
            }
        } else {
            for frame in 0..<frameCount {
                var sum: Float = 0
                if isNonInterleaved {
                    for channel in 0..<min(channelCount, buffers.count) {
                        guard let data = buffers[channel].mData else { continue }
                        sum += Float(data.assumingMemoryBound(to: Int16.self)[frame]) / 32_768
                    }
                } else if let data = buffers.first?.mData {
                    let samples = data.assumingMemoryBound(to: Int16.self)
                    for channel in 0..<channelCount {
                        sum += Float(samples[(frame * channelCount) + channel]) / 32_768
                    }
                }
                mono[frame] = sum / Float(channelCount)
            }
        }

        let rms = sqrt(mono.reduce(Float.zero) { $0 + ($1 * $1) } / Float(frameCount))
        let factor = max(1, Int((asbd.mSampleRate / Double(outputSampleRate)).rounded()))
        var downsampled: [Int16] = []
        downsampled.reserveCapacity(frameCount / factor)
        for start in stride(from: 0, to: frameCount, by: factor) {
            let end = min(start + factor, frameCount)
            let average = mono[start..<end].reduce(Float.zero, +) / Float(end - start)
            let clamped = max(-1, min(1, average))
            downsampled.append(Int16(clamped * Float(Int16.max)))
        }

        chunkSamples.append(contentsOf: downsampled)
        freshSampleCount += downsampled.count
        if rms >= speechRMSThreshold {
            silenceSampleCount = 0
            chunkHasAudio = true
        } else {
            silenceSampleCount += downsampled.count
        }

        overlapSamples.append(contentsOf: downsampled)
        if overlapSamples.count > overlapSampleCount {
            overlapSamples.removeFirst(overlapSamples.count - overlapSampleCount)
        }

        let reachedPause = freshSampleCount >= minimumChunkSamples
            && silenceSampleCount >= minimumSilenceSamples
        let reachedMaximum = freshSampleCount >= maximumChunkSamples
        if reachedPause || reachedMaximum {
            try emitChunk(addOverlapToNext: reachedMaximum)
        }
    }

    private func emitFinalChunkIfNeeded() throws {
        guard freshSampleCount >= outputSampleRate / 2, chunkHasAudio else { return }
        try emitChunk(addOverlapToNext: false)
    }

    private func emitChunk(addOverlapToNext: Bool) throws {
        guard chunkHasAudio, !chunkSamples.isEmpty else {
            resetChunk(withOverlap: false)
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftvoice-live-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(outputSampleRate),
            channels: 1,
            interleaved: true
        ),
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(chunkSamples.count)
        ) else {
            throw SystemAudioRecordingError.writerSetupFailed
        }
        buffer.frameLength = AVAudioFrameCount(chunkSamples.count)
        guard let destination = buffer.mutableAudioBufferList.pointee.mBuffers.mData else {
            throw SystemAudioRecordingError.writerSetupFailed
        }
        chunkSamples.withUnsafeBytes { source in
            destination.copyMemory(from: source.baseAddress!, byteCount: source.count)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        try file.write(from: buffer)
        onChunk(url)
        resetChunk(withOverlap: addOverlapToNext)
    }

    private func resetChunk(withOverlap: Bool) {
        chunkSamples = withOverlap ? overlapSamples : []
        freshSampleCount = 0
        silenceSampleCount = 0
        chunkHasAudio = false
    }
}

enum SystemAudioRecordingError: LocalizedError {
    case noDisplay
    case writerSetupFailed
    case writerFailed

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return LocalizationManager.shared.string("err_system_no_display")
        case .writerSetupFailed, .writerFailed:
            return LocalizationManager.shared.string("err_system_recording")
        }
    }
}
