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
            entries = []
            save()
        }
    }

    private static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SwiftVoice", isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent("dictionary.json")
    }

    func exportJSON() throws -> Data {
        try JSONEncoder.pretty.encode(entries)
    }

    func exportCSV() -> String {
        var lines = ["Canonical,Aliases"]
        for entry in entries {
            let canonicalEscaped = "\"" + entry.canonical.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let aliasesJoined = entry.aliases.joined(separator: ", ")
            let aliasesEscaped = "\"" + aliasesJoined.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            lines.append("\(canonicalEscaped),\(aliasesEscaped)")
        }
        return lines.joined(separator: "\n")
    }

    @discardableResult
    func importJSON(_ data: Data) throws -> Int {
        let imported = try JSONDecoder().decode([DictionaryEntry].self, from: data)
        return merge(imported)
    }

    @discardableResult
    func importCSV(_ text: String) -> Int {
        var imported: [DictionaryEntry] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.lowercased().hasPrefix("canonical") {
                continue
            }
            let parts: [String]
            if trimmed.contains(";") {
                parts = trimmed.components(separatedBy: ";")
            } else if trimmed.contains("\t") {
                parts = trimmed.components(separatedBy: "\t")
            } else {
                parts = parseCSVLine(trimmed)
            }

            guard let first = parts.first?.trimmingCharacters(in: CharacterSet(charactersIn: "\" '")), !first.isEmpty else {
                continue
            }

            let canonical = first
            var aliases: [String] = []
            if parts.count > 1 {
                let rest = parts[1...].joined(separator: ",")
                aliases = rest.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" '")) }
                    .filter { !$0.isEmpty }
            }

            imported.append(DictionaryEntry(canonical: canonical, aliases: aliases))
        }

        return merge(imported)
    }

    @discardableResult
    private func merge(_ newEntries: [DictionaryEntry]) -> Int {
        var count = 0
        for newEntry in newEntries {
            let canonical = newEntry.canonical.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !canonical.isEmpty else { continue }

            if let index = entries.firstIndex(where: { $0.canonical.caseInsensitiveCompare(canonical) == .orderedSame }) {
                var existingAliases = Set(entries[index].aliases.map { $0.lowercased() })
                for alias in newEntry.aliases {
                    let cleaned = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty && !existingAliases.contains(cleaned.lowercased()) {
                        entries[index].aliases.append(cleaned)
                        existingAliases.insert(cleaned.lowercased())
                    }
                }
            } else {
                let cleanedAliases = newEntry.aliases
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                entries.append(DictionaryEntry(canonical: canonical, aliases: cleanedAliases))
                count += 1
            }
        }
        return count
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
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
            NSLog("SwiftVoice dictionary save failed: \(error)")
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
