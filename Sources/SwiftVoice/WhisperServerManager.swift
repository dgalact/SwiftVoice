import Foundation

@MainActor
final class WhisperServerManager {
    static let shared = WhisperServerManager()

    private var process: Process?
    private var loadedModelPath: String?
    private var ready = false
    private let port = 18_000 + Int(ProcessInfo.processInfo.processIdentifier % 10_000)

    private init() {}

    func start(modelPath: String) async throws {
        try await ensureRunning(modelPath: modelPath)
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil
        loadedModelPath = nil
        ready = false
    }

    func transcribe(audioURL: URL, modelPath: String, prompt: String) async throws -> String {
        try await ensureRunning(modelPath: modelPath)

        let boundary = "SwiftVoice-\(UUID().uuidString)"
        var body = Data()
        appendField("language", value: "auto", boundary: boundary, to: &body)
        appendField("response_format", value: "text", boundary: boundary, to: &body)
        if !prompt.isEmpty {
            appendField("prompt", value: prompt, boundary: boundary, to: &body)
        }
        try appendFile(audioURL, boundary: boundary, to: &body)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: endpoint(path: "/inference"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 30 * 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let details = String(data: data, encoding: .utf8) ?? "HTTP error"
            throw DictationError.transcriptionFailed(details)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func ensureRunning(modelPath: String) async throws {
        if let process, process.isRunning, loadedModelPath == modelPath {
            try await waitUntilReady(process)
            return
        }
        stop()

        let serverURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/whisper-server")
        guard FileManager.default.isExecutableFile(atPath: serverURL.path) else {
            throw DictationError.missingConfiguration
        }

        let process = Process()
        process.executableURL = serverURL
        process.arguments = [
            "-m", modelPath,
            "-l", "auto",
            "--host", "127.0.0.1",
            "--port", String(port),
            "--no-timestamps"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
        self.loadedModelPath = modelPath
        self.ready = false

        try await waitUntilReady(process)
    }

    private func waitUntilReady(_ process: Process) async throws {
        for _ in 0..<600 {
            if ready { return }
            if !process.isRunning {
                stop()
                throw DictationError.transcriptionFailed("whisper-server stopped while loading the model")
            }
            var request = URLRequest(url: endpoint(path: "/"))
            request.timeoutInterval = 0.5
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               (200..<500).contains(http.statusCode) {
                ready = true
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        stop()
        throw DictationError.transcriptionFailed("Timed out while loading the Whisper model")
    }

    private func endpoint(path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    private func appendField(_ name: String, value: String, boundary: String, to body: inout Data) {
        let part = "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
            + "\(value)\r\n"
        body.append(part.data(using: .utf8)!)
    }

    private func appendFile(_ url: URL, boundary: String, to body: inout Data) throws {
        let header = "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n"
            + "Content-Type: audio/wav\r\n\r\n"
        body.append(header.data(using: .utf8)!)
        body.append(try Data(contentsOf: url))
        body.append("\r\n".data(using: .utf8)!)
    }
}
