import Foundation

public enum PriceHistoryRange: String, CaseIterable, Identifiable, Sendable {
    case threeMonths, sixMonths, twelveMonths, all

    public var id: Self { self }

    public var months: Int? {
        switch self {
        case .threeMonths: 3
        case .sixMonths: 6
        case .twelveMonths: 12
        case .all: nil
        }
    }

    public func start(endingAt date: Date, calendar: Calendar = .current) -> Date? {
        months.flatMap { calendar.date(byAdding: .month, value: -$0, to: date) }
    }
}

/// A price remains effective until the next observation. Display-only boundary
/// points never become observations or add historical-low occurrences.
public struct PriceHistoryTimeline: Sendable {
    public struct Point: Identifiable, Equatable, Sendable {
        public var id: Date { date }
        public let date: Date
        public let price: Decimal
    }

    public struct Selection: Equatable, Sendable {
        public let date: Date
        public let recordedAt: Date
        public let effectiveUntil: Date
        public let price: Decimal
        public let formattedPrice: String
        public let currency: String
    }

    public let observations: [PriceRecordSnapshot]
    public let end: Date
    public let visibleStart: Date?
    public let requestedStart: Date?
    public let lowestPrice: Decimal?
    public let points: [Point]
    public let lowMarkers: [Point]
    public var lowCount: Int { lowMarkers.count }
    public var firstRecordedAt: Date? { observations.first?.timestamp }

    /// The caller scopes records to one app/storefront. Other currencies and
    /// future timestamps are excluded before any comparison or clipping.
    public init(
        records: [PriceRecordSnapshot],
        currency: String?,
        range: PriceHistoryRange,
        now: Date,
        calendar: Calendar = .current
    ) {
        end = now
        requestedStart = range.start(endingAt: now, calendar: calendar)
        let effectiveCurrency = currency ?? records
            .filter { $0.timestamp <= now }
            .max { $0.timestamp < $1.timestamp }?.currency
        let ordered = records.filter {
            $0.timestamp <= now && $0.currency.caseInsensitiveCompare(effectiveCurrency ?? "") == .orderedSame
        }.sorted {
            if $0.timestamp == $1.timestamp { return $0.id.uuidString < $1.id.uuidString }
            return $0.timestamp < $1.timestamp
        }
        // Coalesce equal timestamps deterministically, so a vertical price
        // transition has one well-defined effective price and stable point id.
        var canonical: [PriceRecordSnapshot] = []
        for record in ordered {
            if canonical.last?.timestamp == record.timestamp { canonical.removeLast() }
            canonical.append(record)
        }
        observations = canonical
        guard let first = canonical.first else {
            visibleStart = nil
            lowestPrice = nil
            points = []
            lowMarkers = []
            return
        }
        let start = max(first.timestamp, requestedStart ?? first.timestamp)
        visibleStart = start
        let minimum = canonical.map(\.price).min()!
        let maximum = canonical.map(\.price).max()!
        // A single baseline, or an unchanged price, is not evidence of a low.
        lowestPrice = maximum > minimum ? minimum : nil

        let carry = canonical.last { $0.timestamp <= start }!
        var plotted = [Point(date: start, price: carry.price)]
        plotted.append(contentsOf: canonical.filter { $0.timestamp > start }.map {
            Point(date: $0.timestamp, price: $0.price)
        })
        if let last = plotted.last, last.date < now {
            plotted.append(Point(date: now, price: last.price))
        }
        points = plotted

        var markers: [Point] = []
        if maximum > minimum {
            var index = 0
            while index < canonical.count {
                guard canonical[index].price == minimum else { index += 1; continue }
                let began = canonical[index].timestamp
                repeat { index += 1 } while index < canonical.count && canonical[index].price == minimum
                let ended = index < canonical.count ? canonical[index].timestamp : now
                // Intervals are [begin, next change), with the final price
                // also valid at `now`. A low ending at the left edge is out.
                if began <= now && (ended > start || (index == canonical.count && ended == start)) {
                    markers.append(Point(date: max(began, start), price: minimum))
                }
            }
        }
        lowMarkers = markers
    }

    /// Exact piecewise-constant lookup; never choose the nearest observation
    /// (which could incorrectly show a future sale before it started).
    public func selection(at date: Date) -> Selection? {
        guard let start = visibleStart, date >= start, date <= end else { return nil }
        var lower = 0
        var upper = observations.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if observations[middle].timestamp <= date { lower = middle + 1 }
            else { upper = middle }
        }
        guard lower > 0 else { return nil }
        let record = observations[lower - 1]
        return Selection(
            date: date,
            recordedAt: record.timestamp,
            effectiveUntil: lower < observations.count ? observations[lower].timestamp : end,
            price: record.price,
            formattedPrice: record.formattedPrice,
            currency: record.currency
        )
    }
}
