import Foundation
import SwiftData

/// Machine readable diagnostics for the shared store, used by
/// `--dump-store-info` in both processes and by integration scripts.
public struct StoreInfoReport: Codable, Sendable {
    public var processName: String
    public var storePath: String
    public var storageRootPath: String
    public var trackedApps: Int
    public var priceRecords: Int
    public var checkRuns: Int
    public var lastRun: LastRunReport?

    public init(
        processName: String,
        storePath: String,
        storageRootPath: String,
        trackedApps: Int,
        priceRecords: Int,
        checkRuns: Int,
        lastRun: LastRunReport?
    ) {
        self.processName = processName
        self.storePath = storePath
        self.storageRootPath = storageRootPath
        self.trackedApps = trackedApps
        self.priceRecords = priceRecords
        self.checkRuns = checkRuns
        self.lastRun = lastRun
    }
}

public struct LastRunReport: Codable, Sendable {
    public var source: String
    public var outcome: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var checkedCount: Int
    public var changedCount: Int
    public var failedCount: Int
    public var errorSummary: String?

    public init(entry: CheckRunEntry) {
        self.source = entry.source.rawValue
        self.outcome = entry.outcome.rawValue
        self.startedAt = entry.startedAt
        self.finishedAt = entry.finishedAt
        self.checkedCount = entry.checkedCount
        self.changedCount = entry.changedCount
        self.failedCount = entry.failedCount
        self.errorSummary = entry.errorSummary
    }
}

public enum Diagnostics {
    /// Collects the shared-store report. Works from any process that can open
    /// the local store (main app, helper, appdropctl).
    public static func storeInfo(container: ModelContainer) async throws -> StoreInfoReport {
        let store = AppDataStore(modelContainer: container)
        let counts = try await store.counts()
        let lastRun = try await store.latestRunEntries(limit: 1).first
        let storeURL = try? SharedStore.storeURL(createDirectory: false)
        let storageRootURL = SharedStore.resolvedStorageRoot?.url
            ?? (try? SharedStore.supportDirectoryURL(create: false))
        return StoreInfoReport(
            processName: ProcessInfo.processInfo.processName,
            storePath: storeURL?.path ?? "<unresolved>",
            storageRootPath: storageRootURL?.path ?? "<unresolved>",
            trackedApps: counts.trackedApps,
            priceRecords: counts.priceRecords,
            checkRuns: counts.checkRuns,
            lastRun: lastRun.map(LastRunReport.init(entry:))
        )
    }

    /// Pretty, stable JSON used by the CLI entry points.
    public static func jsonString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            return "<encoding failed>"
        }
        return string
    }
}
