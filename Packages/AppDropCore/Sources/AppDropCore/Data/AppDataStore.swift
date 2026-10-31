import Foundation
import SwiftData

/// Errors raised by the shared data access layer.
public enum AppDataStoreError: Error, LocalizedError, Equatable {
    case appNotFound
    case duplicateTrackedApp(trackId: String, countryCode: String)
    case recordNotFound

    public var errorDescription: String? {
        switch self {
        case .appNotFound:
            return "The tracked app no longer exists."
        case .duplicateTrackedApp(let trackId, let countryCode):
            return "App \(trackId) is already tracked for storefront \(countryCode.uppercased())."
        case .recordNotFound:
            return "The price record no longer exists."
        }
    }
}

/// Result of importing wishlist entries.
public struct WishdropImportOutcome: Sendable, Equatable {
    public var addedKeys: [String]
    public var alreadyTrackedKeys: [String]

    public init(addedKeys: [String] = [], alreadyTrackedKeys: [String] = []) {
        self.addedKeys = addedKeys
        self.alreadyTrackedKeys = alreadyTrackedKeys
    }
}

/// Serialized access layer for the shared SwiftData store. One actor instance
/// owns one ModelContext; every mutation goes through it so that reads and
/// writes inside a process never interleave.
@ModelActor
public actor AppDataStore {
    // MARK: - Queries

    public func counts() throws -> StoreCounts {
        StoreCounts(
            trackedApps: try modelContext.fetchCount(FetchDescriptor<TrackedApp>()),
            priceRecords: try modelContext.fetchCount(FetchDescriptor<PriceRecord>()),
            checkRuns: try modelContext.fetchCount(FetchDescriptor<CheckRunLog>())
        )
    }

    public func allSnapshots() throws -> [TrackedAppSnapshot] {
        let descriptor = FetchDescriptor<TrackedApp>(
            sortBy: [SortDescriptor(\TrackedApp.createdAt), SortDescriptor(\TrackedApp.name)]
        )
        return try modelContext.fetch(descriptor).map { $0.makeSnapshot() }
    }

    public func snapshot(trackId: String, countryCode: String) throws -> TrackedAppSnapshot? {
        try fetchApp(trackId: trackId, countryCode: countryCode)?.makeSnapshot()
    }

    public func snapshot(appID: UUID) throws -> TrackedAppSnapshot? {
        try fetchApp(appID: appID)?.makeSnapshot()
    }

    public func contains(trackId: String, countryCode: String) throws -> Bool {
        try fetchApp(trackId: trackId, countryCode: countryCode) != nil
    }

    public func records(trackId: String, countryCode: String) throws -> [PriceRecordSnapshot] {
        let country = StoreCountry.normalized(countryCode)
        let descriptor = FetchDescriptor<PriceRecord>(
            predicate: #Predicate { $0.trackId == trackId && $0.countryCode == country },
            sortBy: [SortDescriptor(\PriceRecord.timestamp)]
        )
        return try modelContext.fetch(descriptor).map { $0.makeSnapshot() }
    }

    /// A cheap recovery gate. These are candidates, not authorization to
    /// notify: the engine must still revalidate each price with the store.
    public func hasUnsubmittedPriceDrops() throws -> Bool {
        for app in try allSnapshots() {
            guard let latest = try records(trackId: app.trackId, countryCode: app.countryCode).last,
                  latest.recordType == .decrease, latest.notifiedAt == nil,
                  latest.price == app.price.price,
                  latest.currency.caseInsensitiveCompare(app.price.currency ?? "") == .orderedSame else { continue }
            return true
        }
        return false
    }

    /// Only the latest still-effective decrease for a successfully rechecked
    /// app can be retried. An unchanged lookup must not lose a failed alert.
    public func pendingPriceDrops(validatedAppIDs: Set<UUID>) throws -> [PriceDropNotification] {
        var pending: [PriceDropNotification] = []
        for id in validatedAppIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let app = try fetchApp(appID: id),
                  app.lastCheckStatus == .ok,
                  let currentPrice = app.currentPrice,
                  let currency = app.currency else { continue }
            let history = try records(trackId: app.trackId, countryCode: app.countryCode)
                .sorted { $0.timestamp == $1.timestamp ? $0.id.uuidString < $1.id.uuidString : $0.timestamp < $1.timestamp }
            guard let latest = history.last,
                  latest.recordType == .decrease, latest.notifiedAt == nil,
                  latest.price == currentPrice,
                  latest.currency.caseInsensitiveCompare(currency) == .orderedSame,
                  let previous = history.dropLast().last,
                  previous.currency.caseInsensitiveCompare(currency) == .orderedSame,
                  previous.price > latest.price else { continue }
            let earlierMinimum = history.dropLast()
                .filter { $0.currency.caseInsensitiveCompare(currency) == .orderedSame }
                .map(\.price).min() ?? previous.price
            pending.append(PriceDropNotification(
                appName: app.name, trackId: app.trackId, countryCode: app.countryCode,
                formattedPrice: latest.formattedPrice, currency: currency,
                dropPercent: PriceEngine.dropPercent(from: previous.price, to: latest.price),
                isNewLow: latest.price < earlierMinimum, recordID: latest.id
            ))
        }
        return pending
    }

    public func latestRunEntries(limit: Int = 10) throws -> [CheckRunEntry] {
        var descriptor = FetchDescriptor<CheckRunLog>(
            sortBy: [SortDescriptor(\CheckRunLog.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try modelContext.fetch(descriptor).map { $0.makeEntry() }
    }

    /// Start date of the most recent check attempt of any kind.
    public func latestAttemptDate() throws -> Date? {
        var descriptor = FetchDescriptor<CheckRunLog>(
            sortBy: [SortDescriptor(\CheckRunLog.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.startedAt
    }

    // MARK: - Mutations

    @discardableResult
    public func insert(_ draft: NewTrackedAppDraft, now: Date) throws -> TrackedAppSnapshot {
        if try fetchApp(trackId: draft.trackId, countryCode: draft.countryCode) != nil {
            throw AppDataStoreError.duplicateTrackedApp(trackId: draft.trackId, countryCode: draft.countryCode)
        }
        let app = TrackedApp(
            trackId: draft.trackId,
            countryCode: draft.countryCode,
            name: draft.name,
            developerName: draft.developerName,
            artworkURL: draft.artworkURL,
            appStoreURL: draft.appStoreURL,
            currentPrice: draft.price,
            formattedPrice: draft.formattedPrice,
            currency: draft.currency,
            lowestPrice: draft.price,
            // The first observation is a baseline only; it cannot be an
            // all-time low until a higher price has been observed at least once.
            isAtHistoricalLow: false,
            priceObservationCount: draft.price != nil ? 1 : 0,
            lastCheckedAt: draft.price != nil ? now : nil,
            lastCheckAttemptAt: draft.price != nil ? now : nil,
            lastCheckStatus: draft.price != nil ? .ok : .unknown,
            createdAt: now
        )
        modelContext.insert(app)
        if let price = draft.price, let formatted = draft.formattedPrice, let currency = draft.currency {
            let record = PriceRecord(
                trackId: draft.trackId,
                countryCode: draft.countryCode,
                timestamp: now,
                price: price,
                formattedPrice: formatted,
                currency: currency,
                recordType: .initial
            )
            record.app = app
            modelContext.insert(record)
        }
        try modelContext.save()
        return app.makeSnapshot()
    }

    public func delete(appID: UUID) throws {
        guard let app = try fetchApp(appID: appID) else { return }
        modelContext.delete(app)
        try modelContext.save()
    }

    public func delete(appIDs: Set<UUID>) throws {
        guard !appIDs.isEmpty else { return }
        for appID in appIDs {
            if let app = try fetchApp(appID: appID) {
                modelContext.delete(app)
            }
        }
        try modelContext.save()
    }

    /// Applies one price evaluation: updates the current state, appends a
    /// history record when required and returns what changed.
    @discardableResult
    public func apply(
        _ evaluation: PriceEvaluation,
        appID: UUID,
        metadata: AppStoreApp?,
        now: Date
    ) throws -> AppliedEvaluation {
        guard let app = try fetchApp(appID: appID) else {
            throw AppDataStoreError.appNotFound
        }
        if let metadata {
            app.name = metadata.name
            if let developer = metadata.developerName { app.developerName = developer }
            if let artwork = metadata.artworkURL { app.artworkURL = artwork }
            if let storeURL = metadata.appStoreURL { app.appStoreURL = storeURL }
        }

        var appended: PriceRecord?
        var wasDecrease = false
        var isNewLow = false

        switch evaluation {
        case .unavailable:
            app.lastCheckAttemptAt = now
            app.lastCheckStatus = .notFound
            app.lastCheckError = "App is not part of the storefront results."
        case .baseline(let state):
            applyState(state, to: app)
            app.lastCheckAttemptAt = now
            app.lastCheckedAt = now
            app.lastCheckStatus = .ok
            app.lastCheckError = nil
            appended = makeRecord(for: app, state: state, type: .initial, timestamp: now)
        case .unchanged(let state):
            applyState(state, to: app)
            app.lastCheckAttemptAt = now
            app.lastCheckedAt = now
            app.lastCheckStatus = .ok
            app.lastCheckError = nil
        case .decreased(let state, _, let newLow):
            applyState(state, to: app)
            app.lastCheckAttemptAt = now
            app.lastCheckedAt = now
            app.lastCheckStatus = .ok
            app.lastCheckError = nil
            app.lastPriceChangeAt = now
            app.lastDecreaseAt = now
            appended = makeRecord(for: app, state: state, type: .decrease, timestamp: now)
            wasDecrease = true
            isNewLow = newLow
        case .increased(let state):
            applyState(state, to: app)
            app.lastCheckAttemptAt = now
            app.lastCheckedAt = now
            app.lastCheckStatus = .ok
            app.lastCheckError = nil
            app.lastPriceChangeAt = now
            appended = makeRecord(for: app, state: state, type: .increase, timestamp: now)
        case .currencyChanged(let state):
            applyState(state, to: app)
            app.lastCheckAttemptAt = now
            app.lastCheckedAt = now
            app.lastCheckStatus = .ok
            app.lastCheckError = nil
            app.lastPriceChangeAt = now
            appended = makeRecord(for: app, state: state, type: .currencyChange, timestamp: now)
        }

        // Every appended record is one more observed price; a lone baseline
        // must never qualify as an all-time low (see PriceEngine docs).
        if appended != nil {
            app.priceObservationCount += 1
        }
        try modelContext.save()
        return AppliedEvaluation(
            app: app.makeSnapshot(),
            appendedRecordID: appended?.id,
            appendedRecordType: appended?.recordType,
            wasDecrease: wasDecrease,
            isNewLow: isNewLow
        )
    }

    /// Records a failed attempt without touching price data.
    public func markAttempt(
        appID: UUID,
        status: CheckStatus,
        error: String?,
        attemptedAt: Date
    ) throws {
        guard let app = try fetchApp(appID: appID) else { return }
        app.lastCheckAttemptAt = attemptedAt
        app.lastCheckStatus = status
        app.lastCheckError = error
        try modelContext.save()
    }

    public func markNotified(recordID: UUID, at date: Date) throws {
        let descriptor = FetchDescriptor<PriceRecord>(predicate: #Predicate { $0.id == recordID })
        guard let record = try modelContext.fetch(descriptor).first else {
            throw AppDataStoreError.recordNotFound
        }
        record.notifiedAt = date
        try modelContext.save()
    }

    public func recordRun(_ summary: RefreshSummary) throws {
        let log = CheckRunLog(
            startedAt: summary.startedAt,
            finishedAt: summary.finishedAt,
            source: summary.source,
            outcome: summary.outcome,
            checkedCount: summary.checkedCount,
            changedCount: summary.changedCount,
            failedCount: summary.failedCount,
            errorSummary: summary.message
        )
        modelContext.insert(log)
        try modelContext.save()
        try pruneRunLogs()
    }

    /// Development helper: clears the check-run history (used by the test tool
    /// to exercise the launchd-driven background path without waiting 20h).
    public func clearRunLogs() throws {
        let logs = try modelContext.fetch(FetchDescriptor<CheckRunLog>())
        for log in logs {
            modelContext.delete(log)
        }
        try modelContext.save()
    }

    /// Deletes a tracked app (used by "replace storefront") after the caller has
    /// made sure a replacement can be created.
    public func replaceRegionPrepareDeletion(appID: UUID) throws -> TrackedAppSnapshot {
        guard let app = try fetchApp(appID: appID) else {
            throw AppDataStoreError.appNotFound
        }
        return app.makeSnapshot()
    }

    /// Imports validated wishlist entries. Existing `trackId + country` pairs
    /// are reported instead of duplicated. Never deletes existing data.
    public func importWishdrop(entries: [WishdropApp], now: Date) throws -> WishdropImportOutcome {
        var outcome = WishdropImportOutcome()
        for entry in entries {
            let key = TrackedApp.makeLogicalKey(trackId: entry.trackId, countryCode: entry.countryCode)
            if try fetchApp(trackId: entry.trackId, countryCode: entry.countryCode) != nil {
                outcome.alreadyTrackedKeys.append(key)
                continue
            }
            let app = TrackedApp(
                trackId: entry.trackId,
                countryCode: entry.countryCode,
                name: entry.name,
                appStoreURL: entry.appStoreURL,
                createdAt: now
            )
            modelContext.insert(app)
            outcome.addedKeys.append(key)
        }
        try modelContext.save()
        return outcome
    }

    /// Development helper used by the integration test tool.
    public func setStoredPrice(
        trackId: String,
        countryCode: String,
        price: Decimal?,
        formattedPrice: String?,
        currency: String?,
        now: Date
    ) throws -> TrackedAppSnapshot {
        guard let app = try fetchApp(trackId: trackId, countryCode: countryCode) else {
            throw AppDataStoreError.appNotFound
        }
        app.currentPrice = price
        app.formattedPrice = formattedPrice
        app.currency = currency
        app.isDiscounted = false
        app.discountRate = 0
        let country = StoreCountry.normalized(countryCode)
        let descriptor = FetchDescriptor<PriceRecord>(
            predicate: #Predicate { $0.trackId == trackId && $0.countryCode == country }
        )
        if try modelContext.fetch(descriptor).isEmpty,
           let price, let formattedPrice, let currency {
            // Mirror a real first observation so history and derived state stay
            // consistent.
            let record = PriceRecord(
                trackId: trackId,
                countryCode: country,
                timestamp: now,
                price: price,
                formattedPrice: formattedPrice,
                currency: currency,
                recordType: .initial
            )
            record.app = app
            modelContext.insert(record)
            try modelContext.save()
        }
        let stored = try modelContext.fetch(descriptor)
        let prices = stored
            .filter { currency == nil || $0.currency == currency }
            .map(\.price)
        app.priceObservationCount = prices.count
        app.lowestPrice = prices.min() ?? price
        app.isAtHistoricalLow = price.map {
            PriceEngine.isAtHistoricalLow(current: $0, observedPrices: prices)
        } ?? false
        app.lastCheckedAt = now
        app.lastCheckAttemptAt = now
        app.lastCheckStatus = .ok
        app.lastCheckError = nil
        try modelContext.save()
        return app.makeSnapshot()
    }

    /// Recomputes the derived low-price state (lowest price, observation count
    /// and the all-time-low flag) from the stored records. Older builds flagged
    /// a lone baseline observation as an all-time low; this repair runs at
    /// launch and before every refresh cycle so stale rows are corrected.
    /// Returns the number of apps whose stored state changed.
    @discardableResult
    public func reconcilePriceState() throws -> Int {
        let apps = try modelContext.fetch(FetchDescriptor<TrackedApp>())
        guard !apps.isEmpty else { return 0 }
        let records = try modelContext.fetch(FetchDescriptor<PriceRecord>())
        let byKey = Dictionary(grouping: records) {
            TrackedApp.makeLogicalKey(trackId: $0.trackId, countryCode: $0.countryCode)
        }
        var changed = 0
        for app in apps {
            let prices = (byKey[app.logicalKey] ?? [])
                .filter { app.currency == nil || $0.currency == app.currency }
                .map(\.price)
            let lowest = prices.min()
            let atLow = app.currentPrice.map {
                PriceEngine.isAtHistoricalLow(current: $0, observedPrices: prices)
            } ?? false
            guard app.priceObservationCount != prices.count
                || app.lowestPrice != lowest
                || app.isAtHistoricalLow != atLow else { continue }
            app.priceObservationCount = prices.count
            app.lowestPrice = lowest
            app.isAtHistoricalLow = atLow
            changed += 1
        }
        if changed > 0 {
            try modelContext.save()
        }
        return changed
    }

    // MARK: - Private helpers

    private func fetchApp(trackId: String, countryCode: String) throws -> TrackedApp? {
        let country = StoreCountry.normalized(countryCode)
        let descriptor = FetchDescriptor<TrackedApp>(
            predicate: #Predicate { $0.trackId == trackId && $0.countryCode == country }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func fetchApp(appID: UUID) throws -> TrackedApp? {
        let descriptor = FetchDescriptor<TrackedApp>(predicate: #Predicate { $0.id == appID })
        return try modelContext.fetch(descriptor).first
    }

    private func applyState(_ state: PriceSnapshot, to app: TrackedApp) {
        app.currentPrice = state.price
        app.formattedPrice = state.formattedPrice
        app.currency = state.currency
        app.lowestPrice = state.lowestPrice
        app.isDiscounted = state.isDiscounted
        app.discountRate = state.discountRate
        app.isAtHistoricalLow = state.isAtHistoricalLow
    }

    private func makeRecord(
        for app: TrackedApp,
        state: PriceSnapshot,
        type: PriceRecordType,
        timestamp: Date
    ) -> PriceRecord? {
        guard let price = state.price,
              let formatted = state.formattedPrice,
              let currency = state.currency else { return nil }
        let record = PriceRecord(
            trackId: app.trackId,
            countryCode: app.countryCode,
            timestamp: timestamp,
            price: price,
            formattedPrice: formatted,
            currency: currency,
            recordType: type
        )
        record.app = app
        modelContext.insert(record)
        return record
    }

    private func pruneRunLogs() throws {
        let descriptor = FetchDescriptor<CheckRunLog>(
            sortBy: [SortDescriptor(\CheckRunLog.startedAt, order: .reverse)]
        )
        let logs = try modelContext.fetch(descriptor)
        guard logs.count > SharedConstants.checkRunLogLimit else { return }
        for log in logs.dropFirst(SharedConstants.checkRunLogLimit) {
            modelContext.delete(log)
        }
        try modelContext.save()
    }
}
