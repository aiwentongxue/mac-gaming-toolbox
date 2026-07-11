import Foundation

public struct CacheScan: Equatable, Sendable {
    public let userTargets: [URL]
    public let systemTargets: [URL]
    public let estimatedBytes: UInt64

    public init(userTargets: [URL], systemTargets: [URL], estimatedBytes: UInt64) {
        self.userTargets = userTargets
        self.systemTargets = systemTargets
        self.estimatedBytes = estimatedBytes
    }
}

public actor CacheService {
    private let fileManager: FileManager
    private let privileged: any PrivilegedOperating

    public init(fileManager: FileManager = .default, privileged: any PrivilegedOperating) {
        self.fileManager = fileManager
        self.privileged = privileged
    }

    public func scan(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> CacheScan {
        let library = homeURL.appendingPathComponent("Library")
        var userTargets = [library.appendingPathComponent("Caches"), library.appendingPathComponent("Logs")]
        for rootName in ["Application Support", "Containers"] {
            let root = library.appendingPathComponent(rootName)
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where ["Cache", "Caches", "Logs"].contains(url.lastPathComponent) {
                userTargets.append(url)
                enumerator.skipDescendants()
            }
        }
        userTargets = uniqueExisting(userTargets)
        let systemTargets = [URL(fileURLWithPath: "/Library/Caches"), URL(fileURLWithPath: "/Library/Logs"), URL(fileURLWithPath: "/private/var/log")]
        let bytes = (userTargets + systemTargets).reduce(UInt64(0)) { $0 + directorySize($1) }
        return CacheScan(userTargets: userTargets, systemTargets: systemTargets, estimatedBytes: bytes)
    }

    public func clear(_ scan: CacheScan) async throws {
        // Complete first-use authorization before deleting anything locally.
        try await privileged.perform(.healthCheck)
        for directory in scan.userTargets { try removeVisibleContents(of: directory) }
        try await privileged.perform(.clearSystemCaches)
    }

    private func removeVisibleContents(of directory: URL) throws {
        guard let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for entry in entries where !entry.lastPathComponent.hasPrefix(".") { try fileManager.removeItem(at: entry) }
    }

    private func directorySize(_ directory: URL) -> UInt64 {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return 0 }
        var size: UInt64 = 0
        for case let url as URL in enumerator {
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true {
                size += UInt64(values.fileSize ?? 0)
            }
        }
        return size
    }

    private func uniqueExisting(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { fileManager.fileExists(atPath: $0.path) && seen.insert($0.standardizedFileURL.path).inserted }
    }
}
