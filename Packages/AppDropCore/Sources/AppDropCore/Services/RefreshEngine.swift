import Foundation
import SwiftData

/// Result of one refresh cycle. Codable so the helper can print it for scripts.
public struct RefreshSummary: Sendable, Equatable, Codable {
    public var source: CheckSource
    public var outcome: CheckRunOutcome
    public var startedAt: Date
    public var finishedAt: Date
    public var checkedCount: Int
    public var changedCount: Int
    public var failedCount: Int
    public var notifiedCount: Int
    public var message: String?

    public init(
        source: CheckSource,
        outcome: CheckRunOutcome,
        startedAt: Date,
        finishedAt: Date,
        checkedCount: Int,
        changedCount: Int,
        failedCount: Int,
        notifiedCount: Int,
        message: String? = nil
    ) {
        self.source = source
        self.outcome = outcome
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.checkedCount = checkedCount
        self.changedCount = changedCount
        self.failedCount = failedCount
        self.notifiedCount = notifiedCount
        self.message = message
    }
}

/// Result of replacing the storefront of a tracked app.
public enum RegionReplaceResult: Sendable, Equatable {
    case replaced(TrackedAppSnapshot)
    case unchanged
    case duplicate
    case failed(message: String)
}

/// Result of batch-replacing the storefront of all tracked apps.
public struct BulkRegionChangeResult: Sendable, Equatable {
    public var targetCountry: String
    public var updatedCount: Int
    public var unchangedCount: Int
    public var unavailableCount: Int
    public var duplicateCount: Int
    public var failedCount: Int
    public var failureMessages: [String]

    public init(
        targetCountry: String,
        updatedCount: Int = 0,
        unchangedCount: Int = 0,
        unavailableCount: Int = 0,
        duplicateCount: Int = 0,
        failedCount: Int = 0,
        failureMessages: [String] = []
    ) {
        self.targetCountry = targetCountry
        self.updatedCount = updatedCount
        self.unchangedCount = unchangedCount
        self.unavailableCount = unavailableCount
        self.duplicateCount = duplicateCount
        self.failedCount = failedCount
        self.failureMessages = failureMessages
    }
}

/// The shared price-check pipeline used by the main app (manual refresh) and by
/// the background helper (scheduled runs). Serialized across processes with an
/// advisory file lock and idempotent notifications.
public final class RefreshEngine: @unchecked Sendable {
    private let store: AppDataStore
    private let fetcher: any AppStoreFetching
    private let notifier: any UserNotifying
    private let lock: FileLock?
    private let logURL: URL?
    private let now: @Sendable () -> Date

    public init(
        container: ModelContainer,
        fetcher: any AppStoreFetching,
        notifier: any UserNotifying,
        lockURL: URL? = nil,
        logURL: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = AppDataStore(modelContainer: container)
        self.fetcher = fetcher
        self.notifier = notifier
        self.lock = lockURL.map { FileLock(url: $0) }
        self.logURL = logURL
        self.now = now
    }

    /// Convenience factory that wires up the shared-store lock file.
    public static func defaultLockURL() -> URL? {
        guard let support = try? SharedStore.supportDirectoryURL() else { return nil }
        return support.appendingPathComponent(SharedConstants.refreshLockFileName)
    }

    /// Convenience factory that wires up the helper log file.
    public static func defaultLogURL() -> URL? {
        guard let support = try? SharedStore.supportDirectoryURL() else { return nil }
        return support.appendingPathComponent(SharedConstants.helperLogFileName)
    }

    /// Should a scheduled background run happen?
    public static func isOverdue(
        lastAttempt: Date?,
        now: Date,
        minimumInterval: TimeInterval = SharedConstants.backgroundMinimumInterval
    ) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= minimumInterval
    }

    // MARK: - Public entry points

    /// Refreshes all tracked apps.
    /// - Parameters:
    ///   - source: who triggered the cycle (recorded in the run log).
    ///   - mode: lock behaviour; the helper skips, the app may wait briefly.
    ///   - force: when false and the source is `.background`, the cycle is
    ///     skipped if the previous attempt is less than 20 hours old.
    public func run(
        source: CheckSource,
        mode: FileLockMode,
        force: Bool = true
    ) async -> RefreshSummary {
        let startedAt = now()
        var handle: FileLock.Handle?
        if let lock {
            do {
                handle = try lock.acquire(mode)
            } catch {
                let summary = RefreshSummary(
                    source: source,
                    outcome: .skipped,
                    startedAt: startedAt,
                    finishedAt: now(),
                    checkedCount: 0,
                    changedCount: 0,
                    failedCount: 0,
                    notifiedCount: 0,
                    message: "Skipped: another refresh is already running."
                )
                log("run skipped because the refresh lock is busy")
                return summary
            }
        }
        defer { handle?.release() }

        do {
            if source == .background, !force {
                let lastAttempt = try await store.latestAttemptDate()
                guard Self.isOverdue(lastAttempt: lastAttempt, now: startedAt) else {
                    let summary = RefreshSummary(
                        source: source,
                        outcome: .skipped,
                        startedAt: startedAt,
                        finishedAt: now(),
                        checkedCount: 0,
                        changedCount: 0,
                        failedCount: 0,
                        notifiedCount: 0,
                        message: "Skipped: the previous check is less than 20 hours old."
                    )
                    log("run skipped because of the minimum interval")
                    return summary
                }
            }

            // Repair derived low-price flags written by older builds before
            // comparing any prices (a lone baseline used to count as a low).
            _ = try? await store.reconcilePriceState()
            let snapshots = try await store.allSnapshots()
            return await performCycle(snapshots: snapshots, source: source, startedAt: startedAt)
        } catch {
            let summary = RefreshSummary(
                source: source,
                outcome: .failed,
                startedAt: startedAt,
                finishedAt: now(),
                checkedCount: 0,
                changedCount: 0,
                failedCount: 0,
                notifiedCount: 0,
                message: error.localizedDescription
            )
            log("run failed: \(error.localizedDescription)")
            try? await store.recordRun(summary)
            return summary
        }
    }

    /// Refreshes a single tracked app (detail view "check now").
    public func refreshSingle(appID: UUID, source: CheckSource = .manual) async -> RefreshSummary {
        let startedAt = now()
        var handle: FileLock.Handle?
        if let lock {
            do {
                handle = try lock.acquire(.wait(timeout: 15))
            } catch {
                return RefreshSummary(
                    source: source,
                    outcome: .skipped,
                    startedAt: startedAt,
                    finishedAt: now(),
                    checkedCount: 0,
                    changedCount: 0,
                    failedCount: 0,
                    notifiedCount: 0,
                    message: "Skipped: another refresh is already running."
                )
            }
        }
        defer { handle?.release() }

        do {
            _ = try? await store.reconcilePriceState()
            guard let snapshot = try await store.snapshot(appID: appID) else {
                return RefreshSummary(
                    source: source,
                    outcome: .failed,
                    startedAt: startedAt,
                    finishedAt: now(),
                    checkedCount: 0,
                    changedCount: 0,
                    failedCount: 0,
                    notifiedCount: 0,
                    message: "The tracked app no longer exists."
                )
            }
            return await performCycle(snapshots: [snapshot], source: source, startedAt: startedAt)
        } catch {
            return RefreshSummary(
                source: source,
                outcome: .failed,
                startedAt: startedAt,
                finishedAt: now(),
                checkedCount: 0,
                changedCount: 0,
                failedCount: 0,
                notifiedCount: 0,
                message: error.localizedDescription
            )
        }
    }

    /// Replaces the storefront of a tracked app: fetch first, then delete the
    /// old entry and create a fresh baseline in the new storefront.
    public func replaceRegion(appID: UUID, newCountryCode: String, source: CheckSource = .manual) async -> RegionReplaceResult {
        let country = StoreCountry.normalized(newCountryCode)
        guard SharedConstants.isSupportedCountry(country) else {
            return .failed(message: "Unsupported storefront \"\(newCountryCode)\".")
        }
        do {
            guard let current = try await store.snapshot(appID: appID) else {
                return .failed(message: "The tracked app no longer exists.")
            }
            if current.countryCode == country { return .unchanged }
            if try await store.contains(trackId: current.trackId, countryCode: country) {
                return .duplicate
            }

            let result: AppStoreApp?
            do {
                result = try await fetcher.lookupOne(appId: current.trackId, country: country)
            } catch {
                return .failed(message: error.localizedDescription)
            }
            guard let result, let price = result.price, let currency = result.currency,
                  let formatted = result.formattedPrice else {
                return .failed(message: "The app could not be found in the \(country.uppercased()) storefront.")
            }

            try await store.delete(appID: appID)
            let draft = NewTrackedAppDraft(
                trackId: current.trackId,
                countryCode: country,
                name: result.name,
                developerName: result.developerName,
                artworkURL: result.artworkURL,
                appStoreURL: result.appStoreURL,
                price: price,
                formattedPrice: formatted,
                currency: currency
            )
            let snapshot = try await store.insert(draft, now: now())
            log("storefront replaced for \(current.trackId): \(current.countryCode) -> \(country)")
            return .replaced(snapshot)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    /// Replaces the storefront for all tracked apps to the given country code.
    /// Apps already in that storefront are kept unchanged. Apps not available in
    /// the target storefront are left in their existing region.
    public func replaceRegionForAll(to newCountryCode: String) async -> BulkRegionChangeResult {
        let country = StoreCountry.normalized(newCountryCode)
        guard SharedConstants.isSupportedCountry(country) else {
            return BulkRegionChangeResult(
                targetCountry: newCountryCode,
                failedCount: 1,
                failureMessages: ["Unsupported storefront \"\(newCountryCode)\"."]
            )
        }

        do {
            let all = try await store.allSnapshots()
            guard !all.isEmpty else {
                return BulkRegionChangeResult(targetCountry: country)
            }

            var updatedCount = 0
            var unchangedCount = 0
            var unavailableCount = 0
            var duplicateCount = 0
            var failedCount = 0
            var failures: [String] = []

            var toLookup: [TrackedAppSnapshot] = []

            for app in all {
                if app.countryCode == country {
                    unchangedCount += 1
                    continue
                }
                if try await store.contains(trackId: app.trackId, countryCode: country) {
                    duplicateCount += 1
                    failures.append("\(app.name): Already tracked in \(country.uppercased())")
                    continue
                }
                toLookup.append(app)
            }

            guard !toLookup.isEmpty else {
                return BulkRegionChangeResult(
                    targetCountry: country,
                    updatedCount: 0,
                    unchangedCount: unchangedCount,
                    unavailableCount: 0,
                    duplicateCount: duplicateCount,
                    failedCount: 0,
                    failureMessages: failures
                )
            }

            let outcome = await fetcher.lookup(appIds: toLookup.map(\.trackId), country: country)
            let byId = Dictionary(outcome.apps.map { ($0.trackId, $0) }, uniquingKeysWith: { first, _ in first })

            for app in toLookup {
                guard let result = byId[app.trackId] else {
                    unavailableCount += 1
                    failures.append("\(app.name): Not available in \(country.uppercased()) storefront")
                    continue
                }
                guard let price = result.price, let currency = result.currency,
                      let formatted = result.formattedPrice else {
                    unavailableCount += 1
                    failures.append("\(app.name): Missing price in \(country.uppercased()) storefront")
                    continue
                }

                do {
                    try await store.delete(appID: app.id)
                    let draft = NewTrackedAppDraft(
                        trackId: app.trackId,
                        countryCode: country,
                        name: result.name,
                        developerName: result.developerName ?? app.developerName,
                        artworkURL: result.artworkURL ?? app.artworkURL,
                        appStoreURL: result.appStoreURL ?? app.appStoreURL,
                        price: price,
                        formattedPrice: formatted,
                        currency: currency
                    )
                    _ = try await store.insert(draft, now: now())
                    updatedCount += 1
                } catch {
                    failedCount += 1
                    failures.append("\(app.name): \(error.localizedDescription)")
                }
            }

            log("bulk storefront replaced to \(country): updated=\(updatedCount) unchanged=\(unchangedCount) unavailable=\(unavailableCount)")

            return BulkRegionChangeResult(
                targetCountry: country,
                updatedCount: updatedCount,
                unchangedCount: unchangedCount,
                unavailableCount: unavailableCount,
                duplicateCount: duplicateCount,
                failedCount: failedCount,
                failureMessages: failures
            )
        } catch {
            return BulkRegionChangeResult(
                targetCountry: country,
                failedCount: 1,
                failureMessages: [error.localizedDescription]
            )
        }
    }

    // MARK: - Cycle implementation

    private func performCycle(
        snapshots: [TrackedAppSnapshot],
        source: CheckSource,
        startedAt: Date
    ) async -> RefreshSummary {
        guard !snapshots.isEmpty else {
            let summary = RefreshSummary(
                source: source,
                outcome: .success,
                startedAt: startedAt,
                finishedAt: now(),
                checkedCount: 0,
                changedCount: 0,
                failedCount: 0,
                notifiedCount: 0,
                message: "No tracked apps."
            )
            try? await store.recordRun(summary)
            return summary
        }

        var checkedCount = 0
        var changedCount = 0
        var failedCount = 0
        var failures: [String] = []
        var pendingNotifications: [PriceDropNotification] = []

        let byCountry = Dictionary(grouping: snapshots, by: \.countryCode)
        for (country, apps) in byCountry.sorted(by: { $0.key < $1.key }) {
            let outcome = await fetcher.lookup(appIds: apps.map(\.trackId), country: country)
            let byId = Dictionary(outcome.apps.map { ($0.trackId, $0) }, uniquingKeysWith: { first, _ in first })
            let failedIds = Set(outcome.failedIds)
            let failureMessage = outcome.failures.first?.message

            for app in apps {
                do {
                    if failedIds.contains(app.trackId) {
                        failedCount += 1
                        failures.append("\(app.name): \(failureMessage ?? "lookup failed")")
                        try await store.markAttempt(
                            appID: app.id,
                            status: .error,
                            error: failureMessage ?? "App Store lookup failed",
                            attemptedAt: now()
                        )
                        continue
                    }
                    let result = byId[app.trackId]
                    let evaluation = PriceEngine.evaluate(previous: app.price, result: result)
                    let applied = try await store.apply(evaluation, appID: app.id, metadata: result, now: now())
                    checkedCount += 1
                    switch evaluation {
                    case .decreased(_, let dropPercent, let isNewLow):
                        changedCount += 1
                        if let recordID = applied.appendedRecordID,
                           let formatted = applied.app.price.formattedPrice {
                            pendingNotifications.append(PriceDropNotification(
                                appName: applied.app.name,
                                trackId: applied.app.trackId,
                                countryCode: applied.app.countryCode,
                                formattedPrice: formatted,
                                currency: applied.app.price.currency ?? "",
                                dropPercent: dropPercent,
                                isNewLow: isNewLow,
                                recordID: recordID
                            ))
                        }
                    case .increased, .currencyChanged:
                        changedCount += 1
                    case .baseline, .unchanged, .unavailable:
                        break
                    }
                } catch {
                    failedCount += 1
                    failures.append("\(app.name): \(error.localizedDescription)")
                }
            }
        }

        var notifiedCount = 0
        if !pendingNotifications.isEmpty,
           await notifier.sendPriceDrops(pendingNotifications) {
            for notification in pendingNotifications {
                try? await store.markNotified(recordID: notification.recordID, at: now())
            }
            notifiedCount = pendingNotifications.count
        }

        let outcome: CheckRunOutcome
        if failedCount == 0 {
            outcome = .success
        } else if checkedCount > 0 {
            outcome = .partial
        } else {
            outcome = .failed
        }
        let message: String? = failures.isEmpty ? nil : failures.prefix(5).joined(separator: "; ")
        let summary = RefreshSummary(
            source: source,
            outcome: outcome,
            startedAt: startedAt,
            finishedAt: now(),
            checkedCount: checkedCount,
            changedCount: changedCount,
            failedCount: failedCount,
            notifiedCount: notifiedCount,
            message: message
        )
        try? await store.recordRun(summary)
        log("run finished: outcome=\(outcome.rawValue) checked=\(checkedCount) changed=\(changedCount) failed=\(failedCount) notified=\(notifiedCount)")
        return summary
    }

    private func log(_ message: String) {
        AppLog.info("[refresh] \(message)", fileURL: logURL)
    }
}
