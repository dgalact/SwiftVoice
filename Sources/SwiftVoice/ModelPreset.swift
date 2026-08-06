import Foundation

enum ModelPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case largeV3Turbo = "large-v3-turbo"
    case largeV3 = "large-v3"
    case medium = "medium"
    case small = "small"
    case base = "base"
    case tiny = "tiny"
    case custom = "custom"

    var id: String { rawValue }

    var fileName: String {
        switch self {
        case .largeV3Turbo: return "ggml-large-v3-turbo.bin"
        case .largeV3: return "ggml-large-v3.bin"
        case .medium: return "ggml-medium.bin"
        case .small: return "ggml-small.bin"
        case .base: return "ggml-base.bin"
        case .tiny: return "ggml-tiny.bin"
        case .custom: return ""
        }
    }

    var downloadURL: URL? {
        guard !fileName.isEmpty else { return nil }
        return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")
    }

    var displayName: String {
        switch self {
        case .largeV3Turbo: return "Large v3 Turbo (~1.5 GB)"
        case .largeV3: return "Large v3 (~2.9 GB)"
        case .medium: return "Medium (~1.5 GB)"
        case .small: return "Small (~466 MB)"
        case .base: return "Base (~142 MB)"
        case .tiny: return "Tiny (~75 MB)"
        case .custom: return "Custom File…"
        }
    }

    var expectedURL: URL? {
        guard !fileName.isEmpty else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let vendorModels = home.appendingPathComponent("SwiftVoice/vendor/whisper.cpp/models/\(fileName)")
        if FileManager.default.fileExists(atPath: vendorModels.path) {
            return vendorModels
        }
        let appSupportModels = home.appendingPathComponent("Library/Application Support/SwiftVoice/models/\(fileName)")
        if FileManager.default.fileExists(atPath: appSupportModels.path) {
            return appSupportModels
        }
        // Preferred destination for new downloads
        let vendorDir = home.appendingPathComponent("SwiftVoice/vendor/whisper.cpp/models")
        if FileManager.default.fileExists(atPath: vendorDir.path) {
            return vendorModels
        }
        return appSupportModels
    }

    var exists: Bool {
        guard let expectedURL else { return false }
        return FileManager.default.fileExists(atPath: expectedURL.path)
    }

    static func detectPreset(forPath path: String) -> ModelPreset {
        let name = (path as NSString).lastPathComponent
        for preset in ModelPreset.allCases where preset != .custom {
            if preset.fileName == name {
                return preset
            }
        }
        return path.isEmpty ? .largeV3Turbo : .custom
    }
}

@MainActor
final class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = ModelDownloader()

    @Published var isDownloading = false
    @Published var progress: Double = 0.0
    @Published var statusText = ""
    @Published var errorMessage: String?

    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var completionHandler: ((URL?) -> Void)?
    private nonisolated(unsafe) var targetURL: URL?

    override private init() {
        super.init()
    }

    func download(_ preset: ModelPreset, completion: @escaping (URL?) -> Void) {
        guard let remoteURL = preset.downloadURL, let destinationURL = preset.expectedURL else {
            completion(nil)
            return
        }

        guard !isDownloading else { return }

        isDownloading = true
        progress = 0.0
        statusText = "0%"
        errorMessage = nil
        completionHandler = completion
        targetURL = destinationURL

        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
        downloadTask = session?.downloadTask(with: remoteURL)
        downloadTask?.resume()
    }

    func cancel() {
        downloadTask?.cancel()
        isDownloading = false
        progress = 0.0
        statusText = ""
        completionHandler?(nil)
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let targetURL = self.targetURL else {
            Task { @MainActor in
                self.isDownloading = false
                self.completionHandler?(nil)
            }
            return
        }

        do {
            let parentDir = targetURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.copyItem(at: location, to: targetURL)

            Task { @MainActor in
                self.isDownloading = false
                self.progress = 1.0
                self.statusText = "100%"
                self.completionHandler?(targetURL)
            }
        } catch {
            let errMessage = error.localizedDescription
            Task { @MainActor in
                self.isDownloading = false
                self.errorMessage = errMessage
                self.completionHandler?(nil)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            if totalBytesExpectedToWrite > 0 {
                let pct = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                self.progress = pct
                let mbWritten = Double(totalBytesWritten) / (1024 * 1024)
                let mbTotal = Double(totalBytesExpectedToWrite) / (1024 * 1024)
                self.statusText = String(format: "%.0f%% (%.1f / %.1f MB)", pct * 100, mbWritten, mbTotal)
            } else {
                let mbWritten = Double(totalBytesWritten) / (1024 * 1024)
                self.statusText = String(format: "%.1f MB", mbWritten)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            Task { @MainActor in
                if (error as NSError).code != NSURLErrorCancelled {
                    self.errorMessage = error.localizedDescription
                }
                self.isDownloading = false
                self.completionHandler?(nil)
            }
        }
    }
}
