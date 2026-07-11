import Foundation

func coreText(_ chinese: String, _ english: String) -> String {
    guard let preferred = Locale.preferredLanguages.first else { return english }
    return Locale(identifier: preferred).language.languageCode == .chinese ? chinese : english
}

public enum TaskPhase: String, Codable, Sendable {
    case idle, awaitingAuthorization, running, succeeded, failed, cancelled
}

public struct TaskStatus: Equatable, Sendable {
    public var phase: TaskPhase
    public var message: String
    public var progress: Double?
    public var log: [String]

    public init(phase: TaskPhase = .idle, message: String = "", progress: Double? = nil, log: [String] = []) {
        self.phase = phase
        self.message = message
        self.progress = progress
        self.log = log
    }
}

public struct DiskVolume: Identifiable, Hashable, Sendable {
    public let id: String
    public let volumeUUID: String?
    public let name: String
    public let fileSystem: String
    public let mountPoint: String?
    public let size: UInt64
    public let wholeDisk: String
    public let isInternal: Bool

    public init(id: String, volumeUUID: String? = nil, name: String, fileSystem: String, mountPoint: String?, size: UInt64, wholeDisk: String, isInternal: Bool) {
        self.id = id
        self.volumeUUID = volumeUUID
        self.name = name
        self.fileSystem = fileSystem
        self.mountPoint = mountPoint
        self.size = size
        self.wholeDisk = wholeDisk
        self.isInternal = isInternal
    }
}

public struct DiskPreset: Codable, Hashable, Sendable {
    public var diskIdentifier: String
    public var volumeUUID: String?
    public var mountPath: String?

    public init(diskIdentifier: String, volumeUUID: String? = nil, mountPath: String? = nil) {
        self.diskIdentifier = diskIdentifier
        self.volumeUUID = volumeUUID
        self.mountPath = mountPath
    }
}

public struct HostnameBackup: Codable, Equatable, Sendable {
    public var computerName: String
    public var hostName: String
    public var localHostName: String

    public init(computerName: String, hostName: String, localHostName: String) {
        self.computerName = computerName
        self.hostName = hostName
        self.localHostName = localHostName
    }
}

public struct SystemProcess: Identifiable, Hashable, Sendable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let parentPID: Int32
    public let command: String

    public init(pid: Int32, parentPID: Int32, command: String) {
        self.pid = pid
        self.parentPID = parentPID
        self.command = command
    }
}

public struct RecentMetalHUDApp: Codable, Hashable, Identifiable, Sendable {
    public var path: String
    public var displayName: String
    public var id: String { path }

    public init(path: String, displayName: String) {
        self.path = path
        self.displayName = displayName
    }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion = 3
    public var didImportLegacyConfiguration = false
    public var defaultPaths: [String] = []
    public var diskPresets: [DiskPreset] = []
    public var automaticallyRestoreMountsOnLaunch = false
    public var restorableDiskMounts: [DiskPreset] = []
    public var hostnameBackup: HostnameBackup?
    public var customWallpaperPath: String?
    public var recentMetalHUDApps: [RecentMetalHUDApp] = []
    public var hoYoWaitSeconds = 15
    public var excludesSensitiveCacheFiles = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, didImportLegacyConfiguration, defaultPaths, diskPresets
        case automaticallyRestoreMountsOnLaunch, restorableDiskMounts, hostnameBackup, customWallpaperPath
        case recentMetalHUDApps, hoYoWaitSeconds, excludesSensitiveCacheFiles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        didImportLegacyConfiguration = try container.decodeIfPresent(Bool.self, forKey: .didImportLegacyConfiguration) ?? false
        defaultPaths = try container.decodeIfPresent([String].self, forKey: .defaultPaths) ?? []
        diskPresets = try container.decodeIfPresent([DiskPreset].self, forKey: .diskPresets) ?? []
        automaticallyRestoreMountsOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .automaticallyRestoreMountsOnLaunch) ?? false
        restorableDiskMounts = try container.decodeIfPresent([DiskPreset].self, forKey: .restorableDiskMounts) ?? []
        hostnameBackup = try container.decodeIfPresent(HostnameBackup.self, forKey: .hostnameBackup)
        customWallpaperPath = try container.decodeIfPresent(String.self, forKey: .customWallpaperPath)
        recentMetalHUDApps = try container.decodeIfPresent([RecentMetalHUDApp].self, forKey: .recentMetalHUDApps) ?? []
        let decodedWait = try container.decodeIfPresent(Int.self, forKey: .hoYoWaitSeconds) ?? 15
        hoYoWaitSeconds = [10, 15, 20].contains(decodedWait) ? decodedWait : 15
        excludesSensitiveCacheFiles = try container.decodeIfPresent(Bool.self, forKey: .excludesSensitiveCacheFiles) ?? true
    }
}

public enum ToolboxError: LocalizedError, Equatable {
    case invalidPath(String)
    case invalidDisk(String)
    case commandFailed(String)
    case authorizationCancelled
    case helperApprovalRequired
    case helperUnavailable(String)
    case helperTimedOut
    case malformedOutput(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path): coreText("无效路径：\(path)", "Invalid path: \(path)")
        case .invalidDisk(let disk): coreText("无效磁盘：\(disk)", "Invalid disk: \(disk)")
        case .commandFailed(let message): message
        case .authorizationCancelled: coreText("已取消管理员授权", "Authorization cancelled")
        case .helperApprovalRequired: coreText("辅助服务需要在系统设置的“登录项与扩展”中批准", "Approve the helper in System Settings > Login Items & Extensions")
        case .helperUnavailable(let message): coreText("辅助服务不可用：\(message)", "Privileged helper unavailable: \(message)")
        case .helperTimedOut: coreText("辅助服务响应超时", "Privileged helper timed out")
        case .malformedOutput(let message): coreText("无法解析系统输出：\(message)", "Invalid system output: \(message)")
        }
    }
}
