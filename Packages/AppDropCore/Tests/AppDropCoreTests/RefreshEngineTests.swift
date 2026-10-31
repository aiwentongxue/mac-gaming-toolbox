import Foundation
import SwiftData
import Testing
@testable import AppDropCore

@Suite(.serialized) struct RefreshEngineTests {
    final class MockFetcher: AppStoreFetching, @unchecked Sendable {
        var outcome = LookupOutcome()
        var oneResult: AppStoreApp?
        var searchResults: [AppStoreApp] = []
        private(set) var lastLookupCountry: String?
        private(set) var lastLookupIds: [String] = []

        func lookup(appIds: [String], country: String) async -> LookupOutcome {
            lastLookupCountry = country
            lastLookupIds = appIds
            return outcome
        }

        func search(keyword: String, country: String, platform: AppStoreSearchPlatform) async throws -> [AppStoreApp] {
            searchResults
        }

        func lookupOne(appId: String, country: String) async throws -> AppStoreApp? {
            oneResult
        }
    }

    final class MockNotifier: UserNotifying, @unchecked Sendable {
        var sentBatches: [[PriceDropNotification]] = []
        var shouldSucceed = true

        func permission() async -> NotificationPermissionStatus { .authorized }
        func requestPermission() async -> NotificationPermissionStatus { .authorized }
        func sendPriceDrops(_ notifications: [PriceDropNotification]) async -> Bool {
            sentBatches.append(notifications)
            return shouldSucceed
        }
    }

    private struct Harness {
        var container: ModelContainer
        var store: AppDataStore
        var engine: RefreshEngine
        var fetcher: MockFetcher
        var notifier: MockNotifier
        var lockURL: URL
    }

    private func makeHarness(now: @escaping @Sendable () -> Date = { Date() }) throws -> Harness {
        let container = try SharedStore.makeInMemoryContainer()
        let store = AppDataStore(modelContainer: container)
        let fetcher = MockFetcher()
        let notifier = MockNotifier()
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("appdrop-engine-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("refresh.lock")
        let engine = RefreshEngine(
            container: container,
            fetcher: fetcher,
            notifier: notifier,
            lockURL: lockURL,
            now: now
        )
        return Harness(container: container, store: store, engine: engine, fetcher: fetcher, notifier: notifier, lockURL: lockURL)
    }

    private func insert(
        _ store: AppDataStore,
        trackId: String = "123456789",
        country: String = "us",
        price: Decimal? = Decimal(string: "9.99")
    ) async throws -> TrackedAppSnapshot {
        try await store.insert(NewTrackedAppDraft(
            trackId: trackId,
            countryCode: country,
            name: "Example",
            price: price,
            formattedPrice: price.map { "$\($0)" },
            currency: price == nil ? nil : "USD"
        ), now: Date())
    }

    private func resultApp(trackId: String = "123456789", price: Decimal? = Decimal(string: "4.99")) -> AppStoreApp {
        AppStoreApp(trackId: trackId, name: "Example", price: price, formattedPrice: price.map { "$\($0)" }, currency: "USD")
    }

    @Test func priceDropNotifiesOnceAndIsIdempotentOnRetry() async throws {
        let harness = try makeHarness()
        _ = try await insert(harness.store) // previous price 9.99
        harness.fetcher.outcome = LookupOutcome(apps: [resultApp()])
        let first = await harness.engine.run(source: .manual, mode: .skipIfBusy)
        #expect(first.outcome == .success)
        #expect(first.checkedCount == 1)
        #expect(first.changedCount == 1)
        #expect(first.notifiedCount == 1)
        #expect(harness.notifier.sentBatches.count == 1)
        #expect(harness.notifier.sentBatches.first?.count == 1)
        #expect(harness.notifier.sentBatches.first?.first?.isNewLow == true)

        let second = await harness.engine.run(source: .manual, mode: .skipIfBusy)
        #expect(second.changedCount == 0)
        #expect(second.notifiedCount == 0)
        #expect(harness.notifier.sentBatches.count == 1)
        let records = try await harness.store.records(trackId: "123456789", countryCode: "us")
        #expect(records.count == 2)
        #expect(records.last?.notifiedAt != nil)
        let snapshot = try #require(try await harness.store.snapshot(trackId: "123456789", countryCode: "us"))
        #expect(snapshot.price.isAtHistoricalLow)
        #expect(snapshot.priceObservationCount == 2)
    }

    @Test func firstSuccessfulCheckCreatesBaselineWithoutNotification() async throws {
        let harness = try makeHarness()
        _ = try await insert(harness.store, price: nil)
        harness.fetcher.outcome = LookupOutcome(apps: [resultApp()])
        let summary = await harness.engine.run(source: .manual, mode: .skipIfBusy)
        #expect(summary.outcome == .success)
        #expect(summary.notifiedCount == 0)
        #expect(harness.notifier.sentBatches.isEmpty)
        let snapshot = try #require(try await harness.store.snapshot(trackId: "123456789", countryCode: "us"))
        #expect(snapshot.price.price == Decimal(string: "4.99"))
        // A baseline alone is not a low; nothing has dropped yet.
        #expect(!snapshot.price.isAtHistoricalLow)
        #expect(snapshot.priceObservationCount == 1)
    }

    @Test func multipleDropsInOneRunProduceOneNotificationBatch() async throws {
        let harness = try makeHarness()
        for index in 0..<4 {
            _ = try await insert(harness.store, trackId: "12345678\(index)")
        }
        harness.fetcher.outcome = LookupOutcome(apps: (0..<4).map { index in
            AppStoreApp(
                trackId: "12345678\(index)",
                name: "Game \(index + 1)",
                price: Decimal(string: "4.99"),
                formattedPrice: "$4.99",
                currency: "USD"
            )
        })

        let summary = await harness.engine.run(source: .background, mode: .skipIfBusy)

        #expect(summary.changedCount == 4)
        #expect(summary.notifiedCount == 4)
        #expect(harness.notifier.sentBatches.count == 1)
        #expect(harness.notifier.sentBatches.first?.count == 4)
        for index in 0..<4 {
            let records = try await harness.store.records(
                trackId: "12345678\(index)",
                countryCode: "us"
            )
            #expect(records.last?.notifiedAt != nil)
        }
    }

    @Test func failedBatchLeavesEveryRecordUnnotified() async throws {
        let harness = try makeHarness()
        _ = try await insert(harness.store, trackId: "123456781")
        _ = try await insert(harness.store, trackId: "123456782")
        harness.fetcher.outcome = LookupOutcome(apps: [
            AppStoreApp(
                trackId: "123456781",
                name: "Game 1",
                price: Decimal(string: "4.99"),
                formattedPrice: "$4.99",
                currency: "USD"
            ),
            AppStoreApp(
                trackId: "123456782",
                name: "Game 2",
                price: Decimal(string: "3.99"),
                formattedPrice: "$3.99",
                currency: "USD"
            )
        ])
        harness.notifier.shouldSucceed = false

        let summary = await harness.engine.run(source: .background, mode: .skipIfBusy)

        #expect(summary.notifiedCount == 0)
        #expect(harness.notifier.sentBatches.count == 1)
        for trackId in ["123456781", "123456782"] {
            let records = try await harness.store.records(trackId: trackId, countryCode: "us")
            #expect(records.last?.notifiedAt == nil)
        }
    }

    @Test func notFoundKeepsPriceAndMarksEntry() async throws {
        let harness = try makeHarness()
        _ = try await insert(harness.store)
        harness.fetcher.outcome = LookupOutcome(apps: [], missingIds: ["123456789"])
        let summary = await harness.engine.run(source: .manual, mode: .skipIfBusy)
        #expect(summary.outcome == .success)
        let snapshot = try #require(try await harness.store.snapshot(trackId: "123456789", countryCode: "us"))
        #expect(snapshot.price.price == Decimal(string: "9.99"))
        #expect(snapshot.lastCheckStatus == .notFound)
    }

    @Test func failedBatchKeepsPriceAndReportsFailure() async throws {
        let harness = try makeHarness()
        _ = try await insert(harness.store)
        harness.fetcher.outcome = LookupOutcome(
            apps: [],
            failedIds: ["123456789"],
            failures: [LookupBatchFailure(ids: ["123456789"], message: "HTTP 503")]
        )
        let summary = await harness.engine.run(source: .manual, mode: .skipIfBusy)
        #expect(summary.outcome == .failed)
        #expect(summary.failedCount == 1)
        let snapshot = try #require(try await harness.store.snapshot(trackId: "123456789", countryCode: "us"))
        #expect(snapshot.price.price == Decimal(string: "9.99"))
        #expect(snapshot.lastCheckStatus == .error)
    }

    @Test func overlappingRunsAreSerializedByTheLock() async throws {
        let harness = try makeHarness()
        _ = try await insert(harness.store)
        harness.fetcher.outcome = LookupOutcome(apps: [resultApp()])
        let lock = FileLock(url: harness.lockURL)
        let handle = try lock.acquire(.skipIfBusy)
        defer { handle.release() }
        let summary = await harness.engine.run(source: .background, mode: .skipIfBusy)
        #expect(summary.outcome == .skipped)
        #expect(summary.message?.contains("already running") == true)
    }

    @Test func backgroundRunsRespectTheMinimumInterval() async throws {
        let now = Date()
        let harness = try makeHarness(now: { now })
        _ = try await insert(harness.store)
        harness.fetcher.outcome = LookupOutcome(apps: [resultApp()])
        try await harness.store.recordRun(RefreshSummary(
            source: .background,
            outcome: .success,
            startedAt: now.addingTimeInterval(-3600),
            finishedAt: now.addingTimeInterval(-3599),
            checkedCount: 1,
            changedCount: 0,
            failedCount: 0,
            notifiedCount: 0
        ))
        let forced = await harness.engine.run(source: .background, mode: .skipIfBusy, force: false)
        #expect(forced.outcome == .skipped)
        #expect(forced.message?.contains("20 hours") == true)

        let runNow = await harness.engine.run(source: .background, mode: .skipIfBusy, force: true)
        #expect(runNow.outcome == .success)
    }

    @Test func overdueLogicMatchesTheDocumentedWindow() {
        let now = Date()
        #expect(RefreshEngine.isOverdue(lastAttempt: nil, now: now))
        #expect(!RefreshEngine.isOverdue(lastAttempt: now.addingTimeInterval(-3600), now: now))
        #expect(RefreshEngine.isOverdue(lastAttempt: now.addingTimeInterval(-21 * 3600), now: now))
    }

    @Test func replacingStorefrontFetchesFirstThenSwapsEntry() async throws {
        let harness = try makeHarness()
        let inserted = try await insert(harness.store)
        harness.fetcher.oneResult = AppStoreApp(
            trackId: "123456789",
            name: "Example JP",
            price: 700,
            formattedPrice: "¥700",
            currency: "JPY",
            platform: .iOS
        )
        let result = await harness.engine.replaceRegion(appID: inserted.id, newCountryCode: "jp")
        guard case .replaced(let snapshot) = result else {
            Issue.record("expected replaced, got \(result)")
            return
        }
        #expect(snapshot.countryCode == "jp")
        #expect(snapshot.price.price == 700)
        let oldEntry = try await harness.store.snapshot(trackId: "123456789", countryCode: "us")
        #expect(oldEntry == nil)
        let counts = try await harness.store.counts()
        #expect(counts.trackedApps == 1)
        #expect(counts.priceRecords == 1)
    }

    @Test func replacingStorefrontFailsWithoutTouchingTheEntryWhenLookupFails() async throws {
        let harness = try makeHarness()
        let inserted = try await insert(harness.store)
        harness.fetcher.oneResult = nil
        let result = await harness.engine.replaceRegion(appID: inserted.id, newCountryCode: "jp")
        guard case .failed = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
        let survivor = try await harness.store.snapshot(trackId: "123456789", countryCode: "us")
        #expect(survivor != nil)
    }
}

extension RefreshEngineTests {
    @Test func failedSubmissionRetriesOnUnchangedPriceThenStops() async throws {
        let h = try makeHarness()
        let app = try await insert(h.store)
        h.fetcher.outcome = LookupOutcome(apps: [resultApp()])
        h.notifier.shouldSucceed = false
        let failed = await h.engine.run(source: .manual, mode: .skipIfBusy)
        #expect(failed.changedCount == 1 && failed.notifiedCount == 0)
        #expect(try await h.store.hasUnsubmittedPriceDrops())
        h.notifier.shouldSucceed = true
        let retry = await h.engine.run(source: .manual, mode: .skipIfBusy)
        #expect(retry.changedCount == 0 && retry.notifiedCount == 1)
        #expect(try await !h.store.hasUnsubmittedPriceDrops())
        #expect(h.notifier.sentBatches.count == 2)
        let final = await h.engine.refreshSingle(appID: app.id)
        #expect(final.notifiedCount == 0)
        #expect(h.notifier.sentBatches.count == 2)
        #expect(try await h.store.records(trackId: app.trackId, countryCode: app.countryCode).count == 2)
    }

    @Test func missedDropsAreRevalidatedAndCombinedAcrossMainAndHelperEngines() async throws {
        let h = try makeHarness()
        _ = try await insert(h.store, trackId: "123456781")
        _ = try await insert(h.store, trackId: "123456782")
        h.fetcher.outcome = LookupOutcome(apps: [resultApp(trackId: "123456781"), resultApp(trackId: "123456782")])
        h.notifier.shouldSucceed = false
        _ = await h.engine.run(source: .background, mode: .skipIfBusy)
        h.notifier.shouldSucceed = true
        let secondEngine = RefreshEngine(container: h.container, fetcher: h.fetcher, notifier: h.notifier, lockURL: h.lockURL)
        let recovered = await secondEngine.run(source: .manual, mode: .skipIfBusy)
        #expect(recovered.changedCount == 0)
        #expect(recovered.notifiedCount == 2)
        #expect(h.notifier.sentBatches.last?.count == 2)
        let repeated = await h.engine.run(source: .background, mode: .skipIfBusy)
        #expect(repeated.notifiedCount == 0)
        #expect(h.notifier.sentBatches.count == 2)
    }

    @Test func retryExcludesFailedAndUnavailableLookups() async throws {
        let h = try makeHarness()
        _ = try await insert(h.store, trackId: "123456781")
        _ = try await insert(h.store, trackId: "123456782")
        h.fetcher.outcome = LookupOutcome(apps: [resultApp(trackId: "123456781"), resultApp(trackId: "123456782")])
        h.notifier.shouldSucceed = false
        _ = await h.engine.run(source: .manual, mode: .skipIfBusy)
        h.notifier.shouldSucceed = true
        h.fetcher.outcome = LookupOutcome(apps: [], missingIds: ["123456781"], failedIds: ["123456782"], failures: [LookupBatchFailure(ids: ["123456782"], message: "offline")])
        let failed = await h.engine.run(source: .manual, mode: .skipIfBusy)
        #expect(failed.notifiedCount == 0)
        #expect(h.notifier.sentBatches.count == 1)
        h.fetcher.outcome = LookupOutcome(apps: [resultApp(trackId: "123456781")], failedIds: ["123456782"])
        let partial = await h.engine.run(source: .manual, mode: .skipIfBusy)
        #expect(partial.notifiedCount == 1)
        #expect(h.notifier.sentBatches.last?.first?.trackId == "123456781")
        #expect(try await h.store.records(trackId: "123456782", countryCode: "us").last?.notifiedAt == nil)
    }

    @Test func onlyLatestDecreaseIsRetriedAndOldPriceIncreasesAreIgnored() async throws {
        let h = try makeHarness()
        _ = try await insert(h.store)
        h.notifier.shouldSucceed = false
        h.fetcher.outcome = LookupOutcome(apps: [resultApp()])
        _ = await h.engine.run(source: .manual, mode: .skipIfBusy)
        h.fetcher.outcome = LookupOutcome(apps: [resultApp(price: Decimal(string: "2.99"))])
        _ = await h.engine.run(source: .manual, mode: .skipIfBusy)
        h.notifier.shouldSucceed = true
        let retry = await h.engine.run(source: .manual, mode: .skipIfBusy)
        #expect(retry.notifiedCount == 1)
        #expect(h.notifier.sentBatches.last?.first?.formattedPrice == "$2.99")
        let records = try await h.store.records(trackId: "123456789", countryCode: "us")
        #expect(records.count == 3)
        #expect(records[1].notifiedAt == nil)
        #expect(records[2].notifiedAt != nil)
        h.fetcher.outcome = LookupOutcome(apps: [resultApp(price: Decimal(string: "7.99"))])
        let increased = await h.engine.run(source: .manual, mode: .skipIfBusy)
        #expect(increased.notifiedCount == 0)
    }

    @Test func deletedOrCurrencyChangedAppsDoNotRecoverOldAlerts() async throws {
        let h = try makeHarness()
        let app = try await insert(h.store)
        h.fetcher.outcome = LookupOutcome(apps: [resultApp()])
        h.notifier.shouldSucceed = false
        _ = await h.engine.run(source: .manual, mode: .skipIfBusy)
        h.fetcher.outcome = LookupOutcome(apps: [AppStoreApp(trackId: app.trackId, name: "Example", price: 500, formattedPrice: "¥500", currency: "JPY")])
        h.notifier.shouldSucceed = true
        let changed = await h.engine.run(source: .manual, mode: .skipIfBusy)
        #expect(changed.notifiedCount == 0)
        try await h.store.delete(appID: app.id)
        #expect(try await h.store.pendingPriceDrops(validatedAppIDs: [app.id]).isEmpty)
    }

    @Test func singleCheckOnlyRecoversTheSuccessfullyCheckedApp() async throws {
        let h = try makeHarness()
        let a = try await insert(h.store, trackId: "123456781")
        _ = try await insert(h.store, trackId: "123456782")
        h.fetcher.outcome = LookupOutcome(apps: [resultApp(trackId: "123456781"), resultApp(trackId: "123456782")])
        h.notifier.shouldSucceed = false
        _ = await h.engine.run(source: .manual, mode: .skipIfBusy)
        h.notifier.shouldSucceed = true
        let single = await h.engine.refreshSingle(appID: a.id)
        #expect(single.notifiedCount == 1)
        #expect(h.notifier.sentBatches.last?.count == 1)
        #expect(h.notifier.sentBatches.last?.first?.trackId == a.trackId)
    }
}
