import Foundation

struct DictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var canonical: String
    var aliases: [String]
}

@MainActor
final class DictionaryStore: ObservableObject {
    @Published var entries: [DictionaryEntry] {
        didSet { save() }
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
            entries = decoded
        } else {
            entries = [
                DictionaryEntry(canonical: "FortiGate", aliases: ["фортигейт", "форти гейт", "fortigate"]),
                DictionaryEntry(canonical: "MikroTik", aliases: ["микротик", "микро тик", "mikrotik"]),
                DictionaryEntry(canonical: "Codex", aliases: ["кодекс", "codex"]),
                DictionaryEntry(canonical: "Hermes", aliases: ["гермес", "hermes"]),
                DictionaryEntry(canonical: "Raspberry Pi", aliases: ["распбери пай", "raspberry pi"]),
                DictionaryEntry(canonical: "VPN", aliases: ["впн", "vpn"])
            ]
            save()
        }
    }

    private static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Jarvis", isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent("dictionary.json")
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: Self.directoryURL,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.pretty.encode(entries)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("Jarvis dictionary save failed: \(error)")
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
