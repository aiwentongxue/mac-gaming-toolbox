import Darwin
import Foundation

public struct CacheScanIssue: Codable, Equatable, Sendable {
    public let path: URL
    public let reason: String

    public init(path: URL, reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct CacheCleanupResult: Codable, Equatable, Sendable {
    public let removedCount: Int
    public let failedItems: [CacheScanIssue]
    public let skippedItems: [CacheScanIssue]

    public init(removedCount: Int, failedItems: [CacheScanIssue], skippedItems: [CacheScanIssue] = []) {
        self.removedCount = removedCount
        self.failedItems = failedItems
        self.skippedItems = skippedItems
    }
}

public struct CacheScan: Equatable, Sendable {
    public let userTargets: [URL]
    public let systemTargets: [URL]
    public let userEntries: [URL]
    public let systemEntries: [URL]
    /// Only fully readable entries are included in this estimate.
    public let estimatedBytes: UInt64
    public let inaccessibleTargets: [CacheScanIssue]
    public var hasCleanableEntries: Bool { !userEntries.isEmpty || !systemEntries.isEmpty }

    public init(userTargets: [URL], systemTargets: [URL], userEntries: [URL] = [], systemEntries: [URL] = [], estimatedBytes: UInt64, inaccessibleTargets: [CacheScanIssue] = []) {
        self.userTargets = userTargets
        self.systemTargets = systemTargets
        self.userEntries = userEntries
        self.systemEntries = systemEntries
        self.estimatedBytes = estimatedBytes
        self.inaccessibleTargets = inaccessibleTargets
    }
}

/// Shared by the scanner and helper so links and unreadable descendants are
/// treated consistently. Never follows symbolic links, including in parents.
struct CacheFileAccess {
    let fileManager: FileManager
    static let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]

    static func resolvedPath(_ url: URL) -> String? {
        guard let path = realpath(url.path, nil) else { return nil }
        defer { free(path) }
        return String(cString: path)
    }

    static func canonicalURL(_ url: URL) -> URL {
        URL(fileURLWithPath: resolvedPath(url) ?? url.path)
    }

    static func isLexicallyValid(_ url: URL) -> Bool {
        url.isFileURL && !url.pathComponents.contains("..") && !url.pathComponents.contains(".")
    }

    func values(_ url: URL) throws -> URLResourceValues {
        // Use fresh URLs: resource values cached during a scan may be stale by cleanup.
        try URL(fileURLWithPath: url.path).resourceValues(forKeys: Self.keys)
    }

    func children(_ directory: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(Self.keys), options: [])
            .sorted { $0.path < $1.path }
    }

    func validate(_ entry: URL, roots: [URL]) throws {
        guard Self.isLexicallyValid(entry),
              roots.contains(where: { $0.path == entry.deletingLastPathComponent().path }) else {
            throw ToolboxError.invalidPath(entry.path)
        }
        let resource = try values(entry)
        guard resource.isSymbolicLink != true, Self.resolvedPath(entry) == entry.path else {
            throw ToolboxError.invalidPath(entry.path)
        }
    }

    func measure(_ entry: URL) throws -> UInt64 {
        let resource = try values(entry)
        guard resource.isSymbolicLink != true,
              Self.resolvedPath(entry) == entry.path else {
            throw ToolboxError.commandFailed(coreText("已跳过符号链接", "Symbolic link skipped"))
        }
        if resource.isRegularFile == true { return UInt64(max(0, resource.fileSize ?? 0)) }
        guard resource.isDirectory == true else {
            throw ToolboxError.commandFailed(coreText("已跳过特殊文件", "Special file skipped"))
        }
        return try children(entry).reduce(UInt64(0)) { try $0 + measure($1) }
    }

    static func isMissing(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code))
            || (error.domain == NSPOSIXErrorDomain && error.code == 2)
    }

    func clear(_ entries: [URL], roots: [URL], removeItem: (URL) throws -> Void) -> CacheCleanupResult {
        var removedCount = 0
        var failed: [CacheScanIssue] = []
        var skipped: [CacheScanIssue] = []
        var seen = Set<String>()
        for entry in entries where seen.insert(entry.path).inserted {
            do {
                try validate(entry, roots: roots)
                // Recheck before recursive removal: a new link or an unreadable
                // descendant must not turn a safe scan into a broader deletion.
                _ = try measure(entry)
            } catch {
                skipped.append(CacheScanIssue(path: entry, reason: Self.isMissing(error)
                    ? coreText("项目已不存在", "Item no longer exists") : error.localizedDescription))
                continue
            }
            do {
                try removeItem(entry)
                removedCount += 1
            } catch {
                let issue = CacheScanIssue(path: entry, reason: error.localizedDescription)
                if Self.isMissing(error) { skipped.append(issue) } else { failed.append(issue) }
            }
        }
        return CacheCleanupResult(removedCount: removedCount, failedItems: failed, skippedItems: skipped)
    }
}

public enum SystemCacheCleanup {
    public static let roots = ["/Library/Caches", "/Library/Logs", "/private/var/log"].map { URL(fileURLWithPath: $0) }

    public static func clear(_ entries: [URL]) throws -> CacheCleanupResult {
        try clear(entries, allowedRoots: roots, fileManager: .default)
    }

    static func clear(_ entries: [URL], allowedRoots: [URL], fileManager: FileManager, removeItem: ((URL) throws -> Void)? = nil) throws -> CacheCleanupResult {
        let access = CacheFileAccess(fileManager: fileManager)
        // Validate the entire request before making any change. Missing entries
        // are valid stale scan results, but every path must still be bounded.
        for entry in entries {
            guard CacheFileAccess.isLexicallyValid(entry),
                  allowedRoots.contains(where: { $0.path == entry.deletingLastPathComponent().path }),
                  CacheFileAccess.resolvedPath(entry.deletingLastPathComponent()) == entry.deletingLastPathComponent().path else {
                throw ToolboxError.invalidPath(entry.path)
            }
            if let values = try? access.values(entry), values.isSymbolicLink == true {
                throw ToolboxError.invalidPath(entry.path)
            }
        }
        return access.clear(entries, roots: allowedRoots, removeItem: removeItem ?? { try fileManager.removeItem(at: $0) })
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

    public func scan(excludingSensitiveFiles: Bool = false, homeURL: URL = FileManager.default.homeDirectoryForCurrentUser, systemRoots: [URL] = SystemCacheCleanup.roots) -> CacheScan {
        let access = CacheFileAccess(fileManager: fileManager)
        let library = CacheFileAccess.canonicalURL(homeURL).appendingPathComponent("Library")
        var userTargets = [library.appendingPathComponent("Caches"), library.appendingPathComponent("Logs")]
        var issues: [CacheScanIssue] = []
        if !excludingSensitiveFiles {
            for rootName in ["Application Support", "Containers"] {
                discover(in: library.appendingPathComponent(rootName), access: access, targets: &userTargets, issues: &issues)
            }
        }
        userTargets = uniqueRoots(userTargets)
        let systemTargets = excludingSensitiveFiles ? [] : uniqueRoots(systemRoots)
        var bytes: UInt64 = 0
        let userEntries = scanEntries(userTargets, access: access, bytes: &bytes, issues: &issues)
        let systemEntries = scanEntries(systemTargets, access: access, bytes: &bytes, issues: &issues)
        var seen = Set<String>()
        return CacheScan(userTargets: userTargets, systemTargets: systemTargets, userEntries: userEntries, systemEntries: systemEntries, estimatedBytes: bytes,
                         inaccessibleTargets: issues.filter { seen.insert($0.path.path).inserted })
    }

    public func clear(_ scan: CacheScan) async throws -> CacheCleanupResult {
        if !scan.systemEntries.isEmpty { try await privileged.perform(.healthCheck) }
        let user = CacheFileAccess(fileManager: fileManager).clear(scan.userEntries, roots: scan.userTargets, removeItem: removeItem)
        var removed = user.removedCount
        var failed = user.failedItems
        var skipped = scan.inaccessibleTargets + user.skippedItems
        if !scan.systemEntries.isEmpty {
            do {
                let system = try await privileged.clearSystemCacheEntries(scan.systemEntries)
                removed += system.removedCount
                failed += system.failedItems
                skipped += system.skippedItems
            } catch {
                // Preserve the results of user deletions even if XPC fails later.
                failed += scan.systemEntries.map { CacheScanIssue(path: $0, reason: error.localizedDescription) }
            }
        }
        return CacheCleanupResult(removedCount: removed, failedItems: failed, skippedItems: skipped)
    }

    private func discover(in directory: URL, access: CacheFileAccess, targets: inout [URL], issues: inout [CacheScanIssue]) {
        do {
            let values = try directory.resourceValues(forKeys: CacheFileAccess.keys)
            guard values.isSymbolicLink != true else {
                // Discovery is not a filesystem inventory. Only cache/log links
                // are skipped candidates; unrelated app locks and Wine drive
                // mappings are outside the cleanup scope and need no warning.
                if ["Cache", "Caches", "Logs"].contains(directory.lastPathComponent) {
                    issues.append(CacheScanIssue(path: directory, reason: coreText("已跳过符号链接", "Symbolic link skipped")))
                }
                return
            }
            guard values.isDirectory == true else { return }
            guard CacheFileAccess.resolvedPath(directory) == directory.path else {
                issues.append(CacheScanIssue(path: directory, reason: coreText("已跳过符号链接", "Symbolic link skipped")))
                return
            }
            if ["Cache", "Caches", "Logs"].contains(directory.lastPathComponent) {
                targets.append(directory)
                return
            }
            guard values.isPackage != true else { return }
            for entry in try access.children(directory) {
                discover(in: entry, access: access, targets: &targets, issues: &issues)
            }
        } catch {
            if !CacheFileAccess.isMissing(error) { issues.append(CacheScanIssue(path: directory, reason: error.localizedDescription)) }
        }
    }

    private func scanEntries(_ roots: [URL], access: CacheFileAccess, bytes: inout UInt64, issues: inout [CacheScanIssue]) -> [URL] {
        var entries: [URL] = []
        for root in roots {
            do {
                let values = try access.values(root)
                guard values.isDirectory == true, values.isSymbolicLink != true, CacheFileAccess.resolvedPath(root) == root.path else {
                    throw ToolboxError.invalidPath(root.path)
                }
                for entry in try access.children(root) {
                    do {
                        let size = try access.measure(entry)
                        entries.append(entry)
                        bytes += size
                    } catch {
                        if !CacheFileAccess.isMissing(error) { issues.append(CacheScanIssue(path: entry, reason: error.localizedDescription)) }
                    }
                }
            } catch {
                if !CacheFileAccess.isMissing(error) { issues.append(CacheScanIssue(path: root, reason: error.localizedDescription)) }
            }
        }
        return entries
    }

    private func uniqueRoots(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        for url in urls.map({ URL(fileURLWithPath: $0.path) }).sorted(by: { $0.path.count < $1.path.count }) {
            if !result.contains(where: { url.path == $0.path || url.path.hasPrefix($0.path + "/") }) { result.append(url) }
        }
        return result
    }
}
