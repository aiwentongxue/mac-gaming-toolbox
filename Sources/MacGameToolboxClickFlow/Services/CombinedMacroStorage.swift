import Foundation

struct CombinedMacroLoadResult: Sendable {
    var macros: [CombinedMacro]
    var damagedFileNames: [String]
}

actor CombinedMacroStorage {
    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directoryURL = support
                .appendingPathComponent("ClickFlow", isDirectory: true)
                .appendingPathComponent("CombinedMacros", isDirectory: true)
        }
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadAll() -> CombinedMacroLoadResult {
        do {
            try ensureDirectory()
            let urls = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension.lowercased() == "json" }
            var macros: [CombinedMacro] = []
            var damaged: [String] = []
            for url in urls {
                do {
                    let macro = try decoder.decode(CombinedMacro.self, from: Data(contentsOf: url))
                    guard macro.schemaVersion <= CombinedMacro.schemaVersion else {
                        damaged.append(url.lastPathComponent)
                        continue
                    }
                    macros.append(macro)
                } catch {
                    damaged.append(url.lastPathComponent)
                    AppLogger.storage.error("Could not load combined macro \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            return CombinedMacroLoadResult(
                macros: macros.sorted { $0.updatedAt > $1.updatedAt },
                damagedFileNames: damaged
            )
        } catch {
            return CombinedMacroLoadResult(macros: [], damagedFileNames: [directoryURL.lastPathComponent])
        }
    }

    func save(_ macro: CombinedMacro) throws {
        try ensureDirectory()
        try encoder.encode(macro).write(to: fileURL(macro.id), options: .atomic)
    }

    func delete(id: UUID) throws {
        let url = fileURL(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func fileURL(_ id: UUID) -> URL {
        directoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }
}
