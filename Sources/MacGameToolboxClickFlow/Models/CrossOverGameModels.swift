import Foundation

enum CrossOverGamePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case genericXInput
    case aniimo
    case genshinImpact
    case zenlessZoneZero

    var id: Self { self }

    var knownExecutableNames: Set<String> {
        switch self {
        case .automatic, .genericXInput: []
        case .aniimo: ["aniimo.exe"]
        case .genshinImpact: ["yuanshen.exe", "genshinimpact.exe"]
        case .zenlessZoneZero: ["zenlesszonezero.exe"]
        }
    }

    var fixedDLLNames: [String]? {
        switch self {
        case .automatic: nil
        case .genericXInput:
            ["xinput1_1.dll", "xinput1_2.dll", "xinput1_3.dll", "xinput1_4.dll", "xinput9_1_0.dll"]
        case .aniimo:
            ["xinput1_3.dll"]
        case .genshinImpact:
            ["xinput1_3.dll", "xinput1_4.dll", "xinput9_1_0.dll"]
        case .zenlessZoneZero:
            ["xinput1_3.dll", "xinput1_4.dll"]
        }
    }

    var disablesWindowsGamingInput: Bool {
        switch self {
        case .aniimo, .zenlessZoneZero: true
        case .automatic, .genericXInput, .genshinImpact: false
        }
    }

    var preferredCrossOverDisplayName: String? {
        switch self {
        case .aniimo: "CrossOver Preview"
        case .genshinImpact: "CrossOver 25.1.1"
        case .zenlessZoneZero: "CrossOver"
        case .automatic, .genericXInput: nil
        }
    }

    static func knownPreset(for executableName: String) -> Self? {
        let name = executableName.lowercased()
        return allCases.first { $0.knownExecutableNames.contains(name) }
    }
}

enum WindowsPEArchitecture: String, Codable, Sendable {
    case x64
    case x86
    case unsupported

    var resourceDirectoryName: String? {
        switch self {
        case .x64: "x64"
        case .x86: "x86"
        case .unsupported: nil
        }
    }
}

struct CrossOverApplication: Identifiable, Hashable, Sendable {
    let url: URL
    let displayName: String
    let version: String

    var id: String { url.standardizedFileURL.path }
    var wineURL: URL {
        url.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine")
    }
}

struct ClickFlowCrossOverBottle: Identifiable, Hashable, Sendable {
    let name: String
    let url: URL
    let version: String
    let is64Bit: Bool

    var id: String { url.standardizedFileURL.path }
    var registryURL: URL { url.appendingPathComponent("user.reg") }
}

struct CrossOverAdapterPlan: Hashable, Sendable {
    let preset: CrossOverGamePreset
    let architecture: WindowsPEArchitecture
    let dllNames: [String]
    let disableWindowsGamingInput: Bool
    let detectedDLLNames: [String]
    let antiCheatFiles: [String]
}

enum CrossOverDiagnosticSeverity: String, Codable, Sendable {
    case passed
    case information
    case warning
    case failed
}

struct CrossOverDiagnosticItem: Identifiable, Hashable, Sendable {
    let id: String
    let severity: CrossOverDiagnosticSeverity
    let title: String
    let detail: String
}

struct CrossOverDiagnosticReport: Sendable {
    let generatedAt: Date
    let plan: CrossOverAdapterPlan?
    let items: [CrossOverDiagnosticItem]
    let installedManifest: CrossOverIntegrationManifest?

    var hasFailure: Bool { items.contains { $0.severity == .failed } }

    var plainText: String {
        let formatter = ISO8601DateFormatter()
        var lines = ["ClickFlow CrossOver controller diagnostics", "Generated: \(formatter.string(from: generatedAt))"]
        for item in items {
            lines.append("[\(item.severity.rawValue.uppercased())] \(item.title): \(item.detail)")
        }
        return lines.joined(separator: "\n")
    }
}

struct CrossOverRegistryValueBackup: Codable, Hashable, Sendable {
    let name: String
    let previousValue: String?
    let installedValue: String
}

struct CrossOverInstalledFile: Codable, Hashable, Sendable {
    let name: String
    let installedSHA256: String
    let originalExisted: Bool
    let originalBackupName: String?
}

enum CrossOverIntegrationManifestState: String, Codable, Sendable {
    case pending
    case installed
    case restored
}

struct CrossOverIntegrationManifest: Codable, Identifiable, Hashable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var state: CrossOverIntegrationManifestState
    let gameExecutablePath: String
    let bottleName: String
    let bottlePath: String
    let crossOverApplicationPath: String
    let preset: CrossOverGamePreset
    let architecture: WindowsPEArchitecture
    let files: [CrossOverInstalledFile]
    let registryValues: [CrossOverRegistryValueBackup]

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        state: CrossOverIntegrationManifestState,
        gameExecutablePath: String,
        bottleName: String,
        bottlePath: String,
        crossOverApplicationPath: String,
        preset: CrossOverGamePreset,
        architecture: WindowsPEArchitecture,
        files: [CrossOverInstalledFile],
        registryValues: [CrossOverRegistryValueBackup]
    ) {
        schemaVersion = Self.schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.state = state
        self.gameExecutablePath = gameExecutablePath
        self.bottleName = bottleName
        self.bottlePath = bottlePath
        self.crossOverApplicationPath = crossOverApplicationPath
        self.preset = preset
        self.architecture = architecture
        self.files = files
        self.registryValues = registryValues
    }
}

enum CrossOverIntegrationError: LocalizedError, Sendable {
    case invalidSelection(String)
    case unsupportedExecutable
    case gameIsRunning
    case missingProxy(String)
    case commandFailed(String)
    case unsafeRestore(String)

    var errorDescription: String? {
        switch self {
        case .invalidSelection(let detail): detail
        case .unsupportedExecutable: cf("windowsGames.error.unsupportedExecutable")
        case .gameIsRunning: cf("windowsGames.error.gameRunning")
        case .missingProxy(let name): cf("windowsGames.error.missingProxy %@", name)
        case .commandFailed(let detail): cf("windowsGames.error.commandFailed %@", detail)
        case .unsafeRestore(let name): cf("windowsGames.error.changedFile %@", name)
        }
    }
}
