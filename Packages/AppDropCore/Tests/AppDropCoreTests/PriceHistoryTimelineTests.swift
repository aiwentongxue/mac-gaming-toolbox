import Foundation
import Testing
@testable import AppDropCore

@Suite struct PriceHistoryTimelineTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private func date(_ month: Int, _ day: Int = 2, hour: Int = 12, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func record(_ month: Int, _ price: String, day: Int = 2, hour: Int = 12, currency: String = "CNY") -> PriceRecordSnapshot {
        PriceRecordSnapshot(id: UUID(), trackId: "123", countryCode: "CN", timestamp: date(month, day, hour: hour),
                            price: Decimal(string: price)!, formattedPrice: "¥\(price)", currency: currency, recordType: .initial)
    }

    private func timeline(_ records: [PriceRecordSnapshot], range: PriceHistoryRange = .all) -> PriceHistoryTimeline {
        PriceHistoryTimeline(records: records, currency: "CNY", range: range, now: date(11), calendar: calendar)
    }

    @Test func emptyHistoryHasNoInventedPrice() {
        let result = timeline([])
        #expect(result.points.isEmpty)
        #expect(result.visibleStart == nil)
        #expect(result.lowestPrice == nil)
        #expect(result.lowCount == 0)
        #expect(result.selection(at: date(10)) == nil)
    }

    @Test func finalKnownPriceExtendsHorizontallyToNow() {
        let result = timeline([record(5, "298"), record(10, "89.40")])
        #expect(result.points.map(\.date) == [date(5), date(10), date(11)])
        #expect(result.points.map(\.price) == [298, Decimal(string: "89.40")!, Decimal(string: "89.40")!])
        #expect(result.observations.count == 2)
        #expect(result.lowCount == 1)
    }

    @Test func singleBaselineDrawsFlatLineWithoutClaimingHistoricalLow() {
        let result = timeline([record(10, "19.99")], range: .sixMonths)
        #expect(result.points.count == 2)
        #expect(result.points.first?.price == result.points.last?.price)
        #expect(result.visibleStart == date(10))
        #expect(result.lowestPrice == nil)
        #expect(result.lowCount == 0)
        #expect(result.selection(at: date(10, 15))?.price == Decimal(string: "19.99"))
    }

    @Test func exactNowBaselineIsNotDropped() {
        let result = timeline([record(11, "298")])
        #expect(result.points.count == 1)
        #expect(result.selection(at: date(11))?.price == 298)
        #expect(result.lowCount == 0)
    }

    @Test func unchangedObservationsNeverBecomeLowOccurrences() {
        let result = timeline([record(5, "298"), record(8, "298"), record(10, "298")])
        #expect(result.lowestPrice == nil)
        #expect(result.lowCount == 0)
    }

    @Test func windowCarriesPriceFromBeforeItsLeftBoundary() {
        let result = timeline([record(1, "298"), record(7, "89.4"), record(10, "298")], range: .threeMonths)
        #expect(result.visibleStart == date(8))
        #expect(result.points.first?.price == Decimal(string: "89.4"))
        #expect(result.points.first?.date == date(8))
        #expect(result.selection(at: date(9))?.price == Decimal(string: "89.4"))
        #expect(result.lowCount == 1)
        #expect(result.lowMarkers.first?.date == date(8))
    }

    @Test func noChangesInsideWindowStillDrawsKnownPrice() {
        let result = timeline([record(1, "298"), record(4, "89.4")], range: .threeMonths)
        #expect(result.points.map(\.date) == [date(8), date(11)])
        #expect(result.points.first?.price == result.points.last?.price)
        #expect(result.lowCount == 1)
    }

    @Test func hoverUsesEffectivePriceRatherThanNearestRecord() {
        let result = timeline([record(5, "298"), record(10, "89.40")])
        let beforeSale = result.selection(at: date(10).addingTimeInterval(-1))
        #expect(beforeSale?.price == 298)
        #expect(beforeSale?.recordedAt == date(5))
        #expect(beforeSale?.effectiveUntil == date(10))
        #expect(result.selection(at: date(10))?.price == Decimal(string: "89.40"))
        #expect(result.selection(at: date(11))?.formattedPrice == "¥89.40")
        #expect(result.selection(at: date(11))?.currency == "CNY")
    }

    @Test func intradayPricesAndExactDecimalArePreserved() {
        let result = timeline([record(10, "0.29", hour: 9), record(10, "0.10", hour: 15)])
        #expect(result.selection(at: date(10, hour: 14))?.price == Decimal(string: "0.29"))
        #expect(result.selection(at: date(10, hour: 15))?.price == Decimal(string: "0.10"))
        #expect(result.lowestPrice == Decimal(string: "0.10"))
    }

    @Test func unknownTimesAreNeverBackfilledAndOutsideWindowIsUnselectable() {
        let result = timeline([record(10, "298")], range: .sixMonths)
        #expect(result.visibleStart == date(10))
        #expect(result.firstRecordedAt == date(10))
        #expect(result.selection(at: date(9)) == nil)
        #expect(result.selection(at: date(11).addingTimeInterval(1)) == nil)
    }

    @Test func countsContinuousLowEpisodesRatherThanDaysOrRecords() {
        let result = timeline([
            record(1, "298"), record(5, "89.4"), record(6, "89.40"), record(7, "298"),
            record(8, "89.4"), record(9, "298"), record(10, "89.4")
        ])
        #expect(result.lowCount == 3)
        #expect(result.lowMarkers.map(\.date) == [date(5), date(8), date(10)])
    }

    @Test func allFourRangesCountOnlyOverlappingGlobalLowEpisodes() {
        let records = [record(1, "298"), record(2, "89.4"), record(3, "298"), record(6, "89.4"),
                       record(7, "298"), record(10, "89.4")]
        #expect(timeline(records, range: .threeMonths).lowCount == 1)
        #expect(timeline(records, range: .sixMonths).lowCount == 2)
        #expect(timeline(records, range: .twelveMonths).lowCount == 3)
        #expect(timeline(records, range: .all).lowCount == 3)
    }

    @Test func lowEndingExactlyAtWindowStartIsExcluded() {
        let result = timeline([record(1, "298"), record(7, "89.4"), record(8, "298")], range: .threeMonths)
        #expect(result.lowCount == 0)
        #expect(result.points.first?.price == 298)
    }

    @Test func newerSaleAboveGlobalMinimumDoesNotCountAsHistoricalLow() {
        let result = timeline([record(1, "298"), record(2, "49"), record(3, "298"), record(10, "89.4")], range: .threeMonths)
        #expect(result.lowestPrice == 49)
        #expect(result.lowCount == 0)
    }

    @Test func currentLowStartingExactlyNowCountsOnce() {
        let result = timeline([record(5, "298"), record(11, "0")], range: .threeMonths)
        #expect(result.lowestPrice == 0)
        #expect(result.lowCount == 1)
        #expect(result.selection(at: date(11))?.price == 0)
    }

    @Test func differentCurrenciesAndFutureObservationsAreExcluded() {
        let result = timeline([record(5, "298"), record(6, "1", currency: "USD"), record(10, "89.4"), record(12, "0")])
        #expect(result.observations.count == 2)
        #expect(result.lowestPrice == Decimal(string: "89.4"))
        #expect(result.points.last?.price == Decimal(string: "89.4"))
    }

    @Test func unorderedRecordsAndDuplicateTimestampsProduceStablePoints() {
        var duplicate = record(10, "89.4")
        duplicate.id = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        var earlier = record(10, "298")
        earlier.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let result = timeline([duplicate, earlier, record(5, "298")])
        #expect(result.observations.count == 2)
        #expect(result.selection(at: date(10))?.price == Decimal(string: "89.4"))
        #expect(Set(result.points.map(\.id)).count == result.points.count)
    }

    @Test func calendarMonthsHandleLeapDayAndMonthEnd() {
        let leapEnd = calendar.date(from: DateComponents(year: 2024, month: 5, day: 31, hour: 12))!
        let start = PriceHistoryRange.threeMonths.start(endingAt: leapEnd, calendar: calendar)!
        #expect(calendar.component(.month, from: start) == 2)
        #expect(calendar.component(.day, from: start) == 29)
        #expect(PriceHistoryRange.all.start(endingAt: leapEnd, calendar: calendar) == nil)
    }
}
