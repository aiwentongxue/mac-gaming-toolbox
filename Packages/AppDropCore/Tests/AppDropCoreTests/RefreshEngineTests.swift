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
