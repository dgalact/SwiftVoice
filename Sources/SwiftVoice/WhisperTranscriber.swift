import Foundation

enum Settings {
    static let whisperExecutableKey = "whisperExecutablePath"
    static let modelPathKey = "whisperModelPath"
}

struct WhisperTranscriber {
    private func resolvePath(forKey key: String) -> String? {
        // 1. Check current domain
        if var path = UserDefaults.standard.string(forKey: key), !path.isEmpty {
            if !FileManager.default.fileExists(atPath: path) && path.contains("/Jarvis/") {
                let migratedPath = path.replacingOccurrences(of: "/Jarvis/", with: "/SwiftVoice/")
                if FileManager.default.fileExists(atPath: migratedPath) {
                    path = migratedPath
                    UserDefaults.standard.set(migratedPath, forKey: key)
                }
            }
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // 2. Check legacy bundle domains (local.dgalact.swiftvoice, local.dgalact.jarvis)
        let legacyDomains = ["local.dgalact.swiftvoice", "local.dgalact.jarvis"]
        for domain in legacyDomains {
            if let oldDict = UserDefaults.standard.persistentDomain(forName: domain),
               let oldPath = oldDict[key] as? String, !oldPath.isEmpty {
                var path = oldPath
                if !FileManager.default.fileExists(atPath: path) && path.contains("/Jarvis/") {
                    path = path.replacingOccurrences(of: "/Jarvis/", with: "/SwiftVoice/")
                }
                if FileManager.default.fileExists(atPath: path) {
                    UserDefaults.standard.set(path, forKey: key)
                    return path
                }
            }
        }

        // 3. Auto-discover default local build paths under ~/SwiftVoice/vendor/whisper.cpp
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let defaultPath: String
        if key == Settings.whisperExecutableKey {
            defaultPath = "\(home)/SwiftVoice/vendor/whisper.cpp/build/bin/whisper-cli"
        } else {
            defaultPath = "\(home)/SwiftVoice/vendor/whisper.cpp/models/ggml-large-v3-turbo.bin"
        }

        if FileManager.default.fileExists(atPath: defaultPath) {
            UserDefaults.standard.set(defaultPath, forKey: key)
            return defaultPath
        }

        return nil
    }

    private var executablePath: String? {
        resolvePath(forKey: Settings.whisperExecutableKey)
    }

    private var modelPath: String? {
        resolvePath(forKey: Settings.modelPathKey)
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
