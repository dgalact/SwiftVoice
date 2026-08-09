import Foundation

enum Settings {
    static let modelPathKey = "whisperModelPath"
}

struct WhisperTranscriber {
    private var executablePath: String? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/whisper-cli")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url.path : nil
    }

    private var modelPath: String? {
        guard let path = UserDefaults.standard.string(forKey: Settings.modelPathKey),
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    var isConfigured: Bool {
        guard let executablePath, let modelPath else { return false }
        return FileManager.default.isExecutableFile(atPath: executablePath)
            && FileManager.default.fileExists(atPath: modelPath)
    }

    func transcribe(_ audioURL: URL, dictionary: [DictionaryEntry]) async throws -> String {
        guard let executablePath, let modelPath, isConfigured else {
            throw DictationError.missingConfiguration
        }

        let outputPrefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftvoice-output-\(UUID().uuidString)")
        let outputURL = outputPrefix.appendingPathExtension("txt")
        let errorURL = outputPrefix.appendingPathExtension("log")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        var arguments = [
            "-m", modelPath,
            "-f", audioURL.path,
            "-l", "auto",
            "-otxt",
            "-of", outputPrefix.path,
            "-nt",
            "-np"
        ]
        let prompt = dictionary
            .map(\.canonical)
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        if !prompt.isEmpty {
            arguments += ["--prompt", prompt]
        }
        process.arguments = arguments

        process.standardOutput = Pipe()
        process.standardError = errorHandle

        try process.run()
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
        }
        try? errorHandle.close()

        guard process.terminationStatus == 0 else {
            let details = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? "неизвестная ошибка"
            try? FileManager.default.removeItem(at: errorURL)
            throw DictationError.transcriptionFailed(details.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }
        let rawText = try String(contentsOf: outputURL, encoding: .utf8)
        let cleaned = rawText
            .replacingOccurrences(of: #"\[[^\]]+\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let text = normalize(cleaned, with: dictionary)

        guard !text.isEmpty else {
            throw DictationError.emptyTranscription
        }
        return text
    }

    private func normalize(_ text: String, with dictionary: [DictionaryEntry]) -> String {
        var result = text
        for entry in dictionary where !entry.canonical.isEmpty {
            let variants = ([entry.canonical.lowercased()] + entry.aliases)
                .filter { !$0.isEmpty }
                .sorted { $0.count > $1.count }
            for variant in variants {
                let escaped = NSRegularExpression.escapedPattern(for: variant)
                let pattern = #"(?iu)(?<![\p{L}\p{N}])\#(escaped)(?![\p{L}\p{N}])"#
                result = result.replacingOccurrences(
                    of: pattern,
                    with: entry.canonical,
                    options: .regularExpression
                )
            }
        }
        return result
    }
}
