import AudioToolbox
import Foundation

enum AudioFileConversionError: LocalizedError {
    case unsupportedFile
    case conversionFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return LocalizationManager.shared.string("err_file_unsupported")
        case let .conversionFailed(status):
            return "\(LocalizationManager.shared.string("err_file_conversion")) (OSStatus \(status))"
        }
    }
}

enum AudioFileConverter {
    static let supportedExtensions = ["wav", "m4a", "mp3", "aac"]

    static func convertToWhisperWAV(_ sourceURL: URL) async throws -> URL {
        guard supportedExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            throw AudioFileConversionError.unsupportedFile
        }

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftvoice-import-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        do {
            try await Task.detached(priority: .userInitiated) {
                try convert(sourceURL, to: destinationURL)
            }.value
            return destinationURL
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    private static func convert(_ sourceURL: URL, to destinationURL: URL) throws {
        var inputFile: ExtAudioFileRef?
        var outputFile: ExtAudioFileRef?

        var status = ExtAudioFileOpenURL(sourceURL as CFURL, &inputFile)
        guard status == noErr, let inputFile else {
            throw AudioFileConversionError.conversionFailed(status)
        }
        defer { ExtAudioFileDispose(inputFile) }

        var pcmFormat = AudioStreamBasicDescription(
            mSampleRate: 16_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        status = ExtAudioFileSetProperty(
            inputFile,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &pcmFormat
        )
        guard status == noErr else {
            throw AudioFileConversionError.conversionFailed(status)
        }

        status = ExtAudioFileCreateWithURL(
            destinationURL as CFURL,
            kAudioFileWAVEType,
            &pcmFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &outputFile
        )
        guard status == noErr, let outputFile else {
            throw AudioFileConversionError.conversionFailed(status)
        }
        defer { ExtAudioFileDispose(outputFile) }

        let frameCapacity: UInt32 = 4096
        let byteCapacity = Int(frameCapacity * pcmFormat.mBytesPerFrame)
        let data = UnsafeMutableRawPointer.allocate(
            byteCount: byteCapacity,
            alignment: MemoryLayout<Int16>.alignment
        )
        defer { data.deallocate() }

        let buffer = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(byteCapacity), mData: data)
        var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: buffer)

        while true {
            var frames = frameCapacity
            bufferList.mBuffers.mDataByteSize = UInt32(byteCapacity)
            status = ExtAudioFileRead(inputFile, &frames, &bufferList)
            guard status == noErr else {
                throw AudioFileConversionError.conversionFailed(status)
            }
            guard frames > 0 else { break }

            status = ExtAudioFileWrite(outputFile, frames, &bufferList)
            guard status == noErr else {
                throw AudioFileConversionError.conversionFailed(status)
            }
        }
    }
}
