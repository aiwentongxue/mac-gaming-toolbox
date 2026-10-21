import Foundation

/// A `.wishdrop` preset file.
public struct WishdropPreset: Codable, Sendable, Equatable {
    public var formatIdentifier: String
    public var version: Int
    public var title: String
    public var author: String?
    public var exportedAt: Date
    public var apps: [WishdropApp]

    public init(
        formatIdentifier: String = SharedConstants.wishdropFormatIdentifier,
        version: Int = SharedConstants.wishdropFormatVersion,
        title: String,
        author: String? = nil,
        exportedAt: Date,
        apps: [WishdropApp]
    ) {
        self.formatIdentifier = formatIdentifier
        self.version = version
        self.title = title
        self.author = author
        self.exportedAt = exportedAt
        self.apps = apps
    }
}

/// One app entry of a `.wishdrop` file.
public struct WishdropApp: Codable, Sendable, Equatable {
    public var trackId: String
    public var name: String
    public var countryCode: String
    public var appStoreURL: String?

    public init(trackId: String, name: String, countryCode: String, appStoreURL: String? = nil) {
        self.trackId = trackId
        self.name = name
        self.countryCode = countryCode
        self.appStoreURL = appStoreURL
    }
}

/// Reasons an entry inside an otherwise valid file cannot be imported.
public struct WishdropEntryIssue: Sendable, Equatable {
    public enum Code: String, Sendable {
        case invalidTrackId
        case unsupportedCountry
        case emptyName
        case invalidURL
    }

    public var index: Int
    public var code: Code
    public var reason: String

    public init(index: Int, code: Code, reason: String) {
        self.index = index
        self.code = code
        self.reason = reason
    }
}

/// Errors that make the whole file unusable.
public enum WishdropError: Error, LocalizedError, Equatable {
    case invalidJSON(message: String)
    case wrongFormatIdentifier(String)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let message):
            return "This file is not valid JSON: \(message)"
        case .wrongFormatIdentifier(let identifier):
            return "This file is not an AppDrop wishdrop preset (format: \(identifier))."
        case .unsupportedVersion(let version):
            return "This wishdrop version (\(version)) is newer than this AppDrop build supports (\(SharedConstants.wishdropFormatVersion)). Update AppDrop and try again."
        }
    }
}

/// Encodes/decodes `.wishdrop` JSON with validation.
public enum WishdropCodec {
    public static func encode(_ preset: WishdropPreset) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(preset)
    }

    public static func decode(_ data: Data) throws -> WishdropPreset {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let preset: WishdropPreset
        do {
            preset = try decoder.decode(WishdropPreset.self, from: data)
        } catch {
            throw WishdropError.invalidJSON(message: error.localizedDescription)
        }
        guard preset.formatIdentifier == SharedConstants.wishdropFormatIdentifier else {
            throw WishdropError.wrongFormatIdentifier(preset.formatIdentifier)
        }
        guard preset.version <= SharedConstants.wishdropFormatVersion else {
            throw WishdropError.unsupportedVersion(preset.version)
        }
        return preset
    }

    /// Splits entries into valid ones and per-index issues; never throws.
    public static func validateEntries(_ preset: WishdropPreset) -> (valid: [WishdropApp], issues: [WishdropEntryIssue]) {
        var valid: [WishdropApp] = []
        var issues: [WishdropEntryIssue] = []

        for (index, entry) in preset.apps.enumerated() {
            let trackId = entry.trackId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trackId.count >= 6, trackId.count <= 12, trackId.allSatisfy(\.isNumber) else {
                issues.append(WishdropEntryIssue(
                    index: index,
                    code: .invalidTrackId,
                    reason: "Invalid app id \"\(entry.trackId)\"."
                ))
                continue
            }
            let country = StoreCountry.normalized(entry.countryCode)
            guard SharedConstants.isSupportedCountry(country) else {
                issues.append(WishdropEntryIssue(
                    index: index,
                    code: .unsupportedCountry,
                    reason: "Unsupported storefront \"\(entry.countryCode)\"."
                ))
                continue
            }
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                issues.append(WishdropEntryIssue(index: index, code: .emptyName, reason: "Missing app name."))
                continue
            }
            if let urlString = entry.appStoreURL,
               !urlString.isEmpty,
               !isValidStoreURL(urlString) {
                issues.append(WishdropEntryIssue(
                    index: index,
                    code: .invalidURL,
                    reason: "Invalid App Store URL \"\(urlString)\"."
                ))
                continue
            }
            valid.append(WishdropApp(trackId: trackId, name: name, countryCode: country, appStoreURL: entry.appStoreURL))
        }
        return (valid, issues)
    }

    private static func isValidStoreURL(_ string: String) -> Bool {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return false
        }
        return true
    }

    /// Builds an exportable preset from tracked-app snapshots.
    public static func makePreset(
        title: String,
        author: String? = nil,
        snapshots: [TrackedAppSnapshot],
        exportedAt: Date
    ) -> WishdropPreset {
        let apps = snapshots.map { snapshot in
            WishdropApp(
                trackId: snapshot.trackId,
                name: snapshot.name,
                countryCode: snapshot.countryCode,
                appStoreURL: snapshot.appStoreURL
                    ?? "https://apps.apple.com/\(snapshot.countryCode)/app/id\(snapshot.trackId)"
            )
        }
        return WishdropPreset(
            title: title,
            author: author,
            exportedAt: exportedAt,
            apps: apps
        )
    }
}
