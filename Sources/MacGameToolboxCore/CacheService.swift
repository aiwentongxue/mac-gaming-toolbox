import Foundation

public struct CacheScanIssue: Equatable, Sendable {
    public let path: URL
    public let reason: String

    public init(path: URL, reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct CacheCleanupResult: Equatable, Sendable {
    public let removedCount: Int
    public let failedItems: [CacheScanIssue]

    public init(removedCount: Int, failedItems: [CacheScanIssue]) {
        self.removedCount = removedCount
        self.failedItems = failedItems
    }
}

public struct CacheScan: Equatable, Sendable {
    public let userTargets: [URL]
    public let systemTargets: [URL]
    public let estimatedBytes: UInt64
    public let inaccessibleTargets: [CacheScanIssue]

    public init(userTargets: [URL], systemTargets: [URL], estimatedBytes: UInt64, inaccessibleTargets: [CacheScanIssue] = []) {
        self.userTargets = userTargets
        self.systemTargets = systemTargets
        self.estimatedBytes = estimatedBytes
        self.inaccessibleTargets = inaccessibleTargets
    }
}

public actor CacheService {
    private let fileManager: FileManager
    private let privileged: any PrivilegedOperating
    private let removeItem: (URL) throws -> Void

    public init(fileManager: FileManager = .default, privileged: any PrivilegedOperating, removeItem: ((URL) throws -> Void)? = nil) {
        self.fileManager = fileManager
        self.privileged = privileged
        self.removeItem = removeItem ?? { try fileManager.removeItem(at: $0) }
    }

    public func scan(excludingSensitiveFiles: Bool = false, homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> CacheScan {
        let library = homeURL.appendingPathComponent("Library")
        var userTargets = [library.appendingPathComponent("Caches"), library.appendingPathComponent("Logs")]
        if !excludingSensitiveFiles {
            for rootName in ["Application Support", "Containers"] {
                let root = library.appendingPathComponent(rootName)
                guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants]) else { continue }
                for case let url as URL in enumerator where ["Cache", "Caches", "Logs"].contains(url.lastPathComponent) {
                    userTargets.append(url)
                    enumerator.skipDescendants()
                }
            }
        }
        userTargets = uniqueExisting(userTargets)
        let systemTargets = excludingSensitiveFiles ? [] : [URL(fileURLWithPath: "/Library/Caches"), URL(fileURLWithPath: "/Library/Logs"), URL(fileURLWithPath: "/private/var/log")]
        var inaccessibleTargets: [CacheScanIssue] = []
        let bytes = (userTargets + systemTargets).reduce(UInt64(0)) { total, directory in
            let measurement = directorySize(directory)
            inaccessibleTargets.append(contentsOf: measurement.issues)
            return total + measurement.bytes
        }
        return CacheScan(userTargets: userTargets, systemTargets: systemTargets, estimatedBytes: bytes, inaccessibleTargets: uniqueIssues(inaccessibleTargets))
    }

    public func clear(_ scan: CacheScan) async throws -> CacheCleanupResult {
        // Complete authorization before deleting locally when the full cleanup
        // will also mutate protected system directories.
        if !scan.systemTargets.isEmpty { try await privileged.perform(.healthCheck) }
        var removedCount = 0
        var failedItems: [CacheScanIssue] = []
        for directory in scan.userTargets {
            let result = removeVisibleContents(of: directory)
            removedCount += result.removedCount
            failedItems.append(contentsOf: result.failedItems)
        }
        if !scan.systemTargets.isEmpty { try await privileged.perform(.clearSystemCaches) }
        return CacheCleanupResult(removedCount: removedCount, failedItems: failedItems)
    }

    private func removeVisibleContents(of directory: URL) -> CacheCleanupResult {
        do {
            let entries = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])
            var removedCount = 0
            var failedItems: [CacheScanIssue] = []
            for entry in entries {
                do {
                    try removeItem(entry)
                    removedCount += 1
                } catch {
                    failedItems.append(CacheScanIssue(path: entry, reason: error.localizedDescription))
                }
            }
            return CacheCleanupResult(removedCount: removedCount, failedItems: failedItems)
        } catch {
            return CacheCleanupResult(removedCount: 0, failedItems: [CacheScanIssue(path: directory, reason: error.localizedDescription)])
        }
    }

    private struct DirectoryMeasurement {
        let bytes: UInt64
        let issues: [CacheScanIssue]
    }

    private func directorySize(_ directory: URL) -> DirectoryMeasurement {
        var issues: [CacheScanIssue] = []
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [],
            errorHandler: { url, error in
                issues.append(CacheScanIssue(path: url, reason: error.localizedDescription))
                return true
            }
        ) else {
            return DirectoryMeasurement(bytes: 0, issues: [CacheScanIssue(path: directory, reason: "Directory contents could not be read")])
        }
        var size: UInt64 = 0
        for case let url as URL in enumerator {
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values.isRegularFile == true {
                    size += UInt64(values.fileSize ?? 0)
                }
            } catch {
                issues.append(CacheScanIssue(path: url, reason: error.localizedDescription))
            }
        }
        return DirectoryMeasurement(bytes: size, issues: issues)
    }

    private func uniqueExisting(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { fileManager.fileExists(atPath: $0.path) && seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func uniqueIssues(_ issues: [CacheScanIssue]) -> [CacheScanIssue] {
        var seen = Set<String>()
        return issues.filter { seen.insert($0.path.standardizedFileURL.path).inserted }
    }
}
