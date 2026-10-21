import Foundation

struct MacroLoadResult: Sendable {
    var macros: [MouseMacro]
    var damagedFileNames: [String]
}

actor MacroStorage {
    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var latestSavedDates: [UUID: Date] = [:]

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.directoryURL = applicationSupport
                .appendingPathComponent("ClickFlow", isDirectory: true)
                .appendingPathComponent("Macros", isDirectory: true)
        }

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadAll() -> MacroLoadResult {
        do {
            try ensureDirectory()
            let urls = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension.lowercased() == "json" }

            var macros: [MouseMacro] = []
            var damaged: [String] = []
            for url in urls {
                do {
                    let macro = try decoder.decode(MouseMacro.self, from: Data(contentsOf: url))
                    guard macro.schemaVersion <= MouseMacro.schemaVersion else {
                        damaged.append(url.lastPathComponent)
                        continue
                    }
                    macros.append(macro)
                } catch {
                    damaged.append(url.lastPathComponent)
                    AppLogger.storage.error("Could not load \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            macros.sort { $0.updatedAt > $1.updatedAt }
            return MacroLoadResult(macros: macros, damagedFileNames: damaged)
        } catch {
            AppLogger.storage.error("Could not enumerate macros: \(error.localizedDescription, privacy: .public)")
            return MacroLoadResult(macros: [], damagedFileNames: [directoryURL.lastPathComponent])
        }
    }

    func save(_ macro: MouseMacro) throws {
        if let latestDate = latestSavedDates[macro.id], latestDate > macro.updatedAt {
            return
        }
        try ensureDirectory()
        let data = try encoder.encode(macro)
        try data.write(to: fileURL(for: macro.id), options: .atomic)
        latestSavedDates[macro.id] = macro.updatedAt
        AppLogger.storage.info("Saved macro \(macro.id.uuidString, privacy: .public)")
    }

    func delete(id: UUID) throws {
        latestSavedDates[id] = nil
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func storagePath() -> String {
        directoryURL.path
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func fileURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }
}
