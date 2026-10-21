import Foundation
import SwiftData
import Testing
@testable import AppDropCore

@Suite struct StoreTests {
    private func makeStore(allowsSave: Bool = true) throws -> (AppDataStore, ModelContainer) {
        let container = try SharedStore.makeInMemoryContainer(allowsSave: allowsSave)
        return (AppDataStore(modelContainer: container), container)
    }

    private func draft(
        trackId: String = "123456789",
        country: String = "us",
        price: Decimal? = Decimal(string: "4.99")
    ) -> NewTrackedAppDraft {
        NewTrackedAppDraft(
            trackId: trackId,
            countryCode: country,
            name: "Example",
            developerName: "Developer",
            artworkURL: nil,
            appStoreURL: "https://apps.apple.com/us/app/id\(trackId)",
            price: price,
            formattedPrice: price.map { "$\($0)" },
            currency: price == nil ? nil : "USD"
        )
    }

    @Test func insertWithPriceCreatesBaselineAndRecord() async throws {
        let (store, _) = try makeStore()
        let now = Date()
        let snapshot = try await store.insert(draft(), now: now)
        #expect(snapshot.price.price == Decimal(string: "4.99"))
        #expect(snapshot.lastCheckStatus == .ok)
        // First observation is a baseline, not an all-time low.
        #expect(!snapshot.price.isAtHistoricalLow)
        #expect(snapshot.priceObservationCount == 1)
        let counts = try await store.counts()
        #expect(counts.trackedApps == 1)
        #expect(counts.priceRecords == 1)
        let records = try await store.records(trackId: "123456789", countryCode: "us")
        #expect(records.first?.recordType == .initial)
    }

    @Test func insertWithoutPriceIsAllowedForImports() async throws {
        let (store, _) = try makeStore()
        let snapshot = try await store.insert(draft(price: nil), now: Date())
        #expect(snapshot.price.price == nil)
        #expect(snapshot.lastCheckStatus == .unknown)
        let counts = try await store.counts()
        #expect(counts.priceRecords == 0)
    }

    @Test func duplicateLogicalKeyIsRejected() async throws {
        let (store, _) = try makeStore()
        _ = try await store.insert(draft(), now: Date())
        do {
            _ = try await store.insert(draft(), now: Date())
            Issue.record("expected duplicate rejection")
        } catch let error as AppDataStoreError {
            #expect(error == .duplicateTrackedApp(trackId: "123456789", countryCode: "us"))
        }
    }

    @Test func sameAppInAnotherRegionIsIndependent() async throws {
        let (store, _) = try makeStore()
        _ = try await store.insert(draft(country: "us"), now: Date())
        _ = try await store.insert(draft(country: "jp"), now: Date())
        let counts = try await store.counts()
        #expect(counts.trackedApps == 2)
        let jp = try await store.snapshot(trackId: "123456789", countryCode: "jp")
        #expect(jp != nil)
    }

    @Test func deleteCascadesHistory() async throws {
        let (store, _) = try makeStore()
        let snapshot = try await store.insert(draft(), now: Date())
        try await store.delete(appID: snapshot.id)
        let counts = try await store.counts()
        #expect(counts.trackedApps == 0)
        #expect(counts.priceRecords == 0)
    }

    @Test func applyingDecreaseUpdatesStateAndAppendsRecord() async throws {
        let (store, _) = try makeStore()
        let now = Date()
        let inserted = try await store.insert(draft(price: Decimal(string: "9.99")), now: now)
        let evaluation = PriceEngine.evaluate(
            previous: inserted.price,
            result: AppStoreApp(trackId: "123456789", name: "Example", price: Decimal(string: "4.99"), formattedPrice: "$4.99", currency: "USD")
        )
        let applied = try await store.apply(evaluation, appID: inserted.id, metadata: nil, now: now.addingTimeInterval(60))
        #expect(applied.wasDecrease)
        #expect(applied.isNewLow)
        #expect(applied.appendedRecordType == .decrease)
        #expect(applied.app.price.discountRate == Decimal(string: "50.1"))
        #expect(applied.app.price.isAtHistoricalLow)
        #expect(applied.app.priceObservationCount == 2)
        let records = try await store.records(trackId: "123456789", countryCode: "us")
        #expect(records.count == 2)
        #expect(records.last?.recordType == .decrease)

        let recordID = try #require(applied.appendedRecordID)
        try await store.markNotified(recordID: recordID, at: now.addingTimeInterval(61))
        let refreshed = try await store.records(trackId: "123456789", countryCode: "us")
        #expect(refreshed.last?.notifiedAt != nil)
    }

    @Test func unchangedPriceDoesNotAppendRecord() async throws {
        let (store, _) = try makeStore()
        let inserted = try await store.insert(draft(), now: Date())
        let evaluation = PriceEngine.evaluate(
            previous: inserted.price,
            result: AppStoreApp(trackId: "123456789", name: "Example", price: Decimal(string: "4.99"), formattedPrice: "$4.99", currency: "USD")
        )
        let applied = try await store.apply(evaluation, appID: inserted.id, metadata: nil, now: Date())
        #expect(applied.appendedRecordID == nil)
        let counts = try await store.counts()
        #expect(counts.priceRecords == 1)
    }

    @Test func unavailableResultKeepsPriceAndMarksNotFound() async throws {
        let (store, _) = try makeStore()
        let inserted = try await store.insert(draft(), now: Date())
        let evaluation = PriceEngine.evaluate(previous: inserted.price, result: nil)
        let applied = try await store.apply(evaluation, appID: inserted.id, metadata: nil, now: Date())
        #expect(applied.app.price.price == Decimal(string: "4.99"))
        #expect(applied.app.lastCheckStatus == .notFound)
        let counts = try await store.counts()
        #expect(counts.priceRecords == 1)
    }

    @Test func failedAttemptKeepsPriceAndRecordsError() async throws {
        let (store, _) = try makeStore()
        let inserted = try await store.insert(draft(), now: Date())
        try await store.markAttempt(appID: inserted.id, status: .error, error: "network down", attemptedAt: Date())
        let snapshot = try #require(try await store.snapshot(appID: inserted.id))
        #expect(snapshot.price.price == Decimal(string: "4.99"))
        #expect(snapshot.lastCheckStatus == .error)
        #expect(snapshot.lastCheckError == "network down")
    }

    @Test func checkRunLogIsPruned() async throws {
        let (store, _) = try makeStore()
        let now = Date()
        for index in 0..<(SharedConstants.checkRunLogLimit + 5) {
            let summary = RefreshSummary(
                source: .manual,
                outcome: .success,
                startedAt: now.addingTimeInterval(Double(index)),
                finishedAt: now.addingTimeInterval(Double(index) + 1),
                checkedCount: 0,
                changedCount: 0,
                failedCount: 0,
                notifiedCount: 0
            )
            try await store.recordRun(summary)
        }
        let counts = try await store.counts()
        #expect(counts.checkRuns == SharedConstants.checkRunLogLimit)
    }

    @Test func clearRunLogsRemovesHistory() async throws {
        let (store, _) = try makeStore()
        try await store.recordRun(RefreshSummary(
            source: .background,
            outcome: .success,
            startedAt: Date(),
            finishedAt: Date(),
            checkedCount: 1,
            changedCount: 0,
            failedCount: 0,
            notifiedCount: 0
        ))
        try await store.clearRunLogs()
        let counts = try await store.counts()
        #expect(counts.checkRuns == 0)
    }

    @Test func restrictedContainersSurfaceErrorsInsteadOfSilentlySucceeding() async {
        var surfaced = false
        do {
            let container = try SharedStore.makeInMemoryContainer(allowsSave: false)
            let store = AppDataStore(modelContainer: container)
            do {
                _ = try await store.insert(draft(), now: Date())
            } catch {
                surfaced = true
            }
        } catch {
            surfaced = true
        }
        #expect(surfaced)
    }

    @Test func wishdropImportSkipsDuplicatesAndKeepsExistingData() async throws {
        let (store, _) = try makeStore()
        _ = try await store.insert(draft(trackId: "111111111"), now: Date())
        let outcome = try await store.importWishdrop(entries: [
            WishdropApp(trackId: "111111111", name: "Existing", countryCode: "us"),
            WishdropApp(trackId: "222222222", name: "New", countryCode: "jp")
        ], now: Date())
        #expect(outcome.alreadyTrackedKeys == ["111111111|us"])
        #expect(outcome.addedKeys == ["222222222|jp"])
        let counts = try await store.counts()
        #expect(counts.trackedApps == 2)
    }

    @Test func setStoredPriceSupportsTestTooling() async throws {
        let (store, _) = try makeStore()
        _ = try await store.insert(draft(price: nil), now: Date())
        let updated = try await store.setStoredPrice(
            trackId: "123456789",
            countryCode: "us",
            price: Decimal(string: "9.99"),
            formattedPrice: "$9.99",
            currency: "USD",
            now: Date()
        )
        #expect(updated.price.price == Decimal(string: "9.99"))
        #expect(updated.price.lowestPrice == Decimal(string: "9.99"))
        #expect(!updated.price.isAtHistoricalLow)
        #expect(updated.priceObservationCount == 1)
    }

    @Test func reconcileClearsLegacyBaselineLowFlag() async throws {
        let (store, container) = try makeStore()
        _ = try await store.insert(draft(), now: Date())

        // Simulate a row written by an older build: one record, flagged as low.
        let context = ModelContext(container)
        let apps = try context.fetch(FetchDescriptor<TrackedApp>())
        let legacy = try #require(apps.first)
        legacy.isAtHistoricalLow = true
        legacy.priceObservationCount = 0
        try context.save()

        let changed = try await store.reconcilePriceState()
        #expect(changed == 1)
        let snapshot = try #require(try await store.snapshot(trackId: "123456789", countryCode: "us"))
        #expect(!snapshot.price.isAtHistoricalLow)
        #expect(snapshot.priceObservationCount == 1)
        #expect(snapshot.price.lowestPrice == Decimal(string: "4.99"))
    }

    @Test func reconcileKeepsGenuineLowAndRecomputesCount() async throws {
        let (store, container) = try makeStore()
        let inserted = try await store.insert(draft(price: Decimal(string: "9.99")), now: Date())
        let evaluation = PriceEngine.evaluate(
            previous: inserted.price,
            result: AppStoreApp(trackId: "123456789", name: "Example", price: Decimal(string: "4.99"), formattedPrice: "$4.99", currency: "USD")
        )
        _ = try await store.apply(evaluation, appID: inserted.id, metadata: nil, now: Date())

        // Simulate a stale row: the flag and the count were never maintained.
        let context = ModelContext(container)
        let apps = try context.fetch(FetchDescriptor<TrackedApp>())
        let stale = try #require(apps.first)
        stale.isAtHistoricalLow = false
        stale.priceObservationCount = 0
        try context.save()

        let changed = try await store.reconcilePriceState()
        #expect(changed == 1)
        let snapshot = try #require(try await store.snapshot(trackId: "123456789", countryCode: "us"))
        #expect(snapshot.price.isAtHistoricalLow)
        #expect(snapshot.priceObservationCount == 2)
        #expect(snapshot.price.lowestPrice == Decimal(string: "4.99"))
    }

    @Test func reconcileIsANoOpForConsistentRows() async throws {
        let (store, _) = try makeStore()
        _ = try await store.insert(draft(), now: Date())
        let changed = try await store.reconcilePriceState()
        #expect(changed == 0)
    }
}
