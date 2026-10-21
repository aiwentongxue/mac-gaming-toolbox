import Foundation

/// Sendable copy of the price-related state of a tracked app.
public struct PriceSnapshot: Sendable, Equatable {
    public var price: Decimal?
    public var formattedPrice: String?
    public var currency: String?
    public var lowestPrice: Decimal?
    public var isDiscounted: Bool
    public var discountRate: Decimal
    public var isAtHistoricalLow: Bool

    public init(
        price: Decimal? = nil,
        formattedPrice: String? = nil,
        currency: String? = nil,
        lowestPrice: Decimal? = nil,
        isDiscounted: Bool = false,
        discountRate: Decimal = 0,
        isAtHistoricalLow: Bool = false
    ) {
        self.price = price
        self.formattedPrice = formattedPrice
        self.currency = currency
        self.lowestPrice = lowestPrice
        self.isDiscounted = isDiscounted
        self.discountRate = discountRate
        self.isAtHistoricalLow = isAtHistoricalLow
    }

    public var hasPrice: Bool { price != nil }
}

/// Sendable copy of a tracked app, safe to pass across actor boundaries.
public struct TrackedAppSnapshot: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var trackId: String
    public var countryCode: String
    public var name: String
    public var developerName: String?
    public var artworkURL: String?
    public var appStoreURL: String?
    public var price: PriceSnapshot
    /// Number of recorded price observations in the current currency.
    public var priceObservationCount: Int
    public var lastCheckedAt: Date?
    public var lastCheckAttemptAt: Date?
    public var lastCheckStatus: CheckStatus
    public var lastCheckError: String?
    public var lastPriceChangeAt: Date?
    public var lastDecreaseAt: Date?
    public var createdAt: Date

    public init(
        id: UUID,
        trackId: String,
        countryCode: String,
        name: String,
        developerName: String? = nil,
        artworkURL: String? = nil,
        appStoreURL: String? = nil,
        price: PriceSnapshot = PriceSnapshot(),
        priceObservationCount: Int = 0,
        lastCheckedAt: Date? = nil,
        lastCheckAttemptAt: Date? = nil,
        lastCheckStatus: CheckStatus = .unknown,
        lastCheckError: String? = nil,
        lastPriceChangeAt: Date? = nil,
        lastDecreaseAt: Date? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.trackId = trackId
        self.countryCode = countryCode
        self.name = name
        self.developerName = developerName
        self.artworkURL = artworkURL
        self.appStoreURL = appStoreURL
        self.price = price
        self.priceObservationCount = priceObservationCount
        self.lastCheckedAt = lastCheckedAt
        self.lastCheckAttemptAt = lastCheckAttemptAt
        self.lastCheckStatus = lastCheckStatus
        self.lastCheckError = lastCheckError
        self.lastPriceChangeAt = lastPriceChangeAt
        self.lastDecreaseAt = lastDecreaseAt
        self.createdAt = createdAt
    }

    public var logicalKey: String {
        TrackedApp.makeLogicalKey(trackId: trackId, countryCode: countryCode)
    }
}

/// Sendable copy of a price history record.
public struct PriceRecordSnapshot: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var trackId: String
    public var countryCode: String
    public var timestamp: Date
    public var price: Decimal
    public var formattedPrice: String
    public var currency: String
    public var recordType: PriceRecordType
    public var notifiedAt: Date?

    public init(
        id: UUID,
        trackId: String,
        countryCode: String,
        timestamp: Date,
        price: Decimal,
        formattedPrice: String,
        currency: String,
        recordType: PriceRecordType,
        notifiedAt: Date? = nil
    ) {
        self.id = id
        self.trackId = trackId
        self.countryCode = countryCode
        self.timestamp = timestamp
        self.price = price
        self.formattedPrice = formattedPrice
        self.currency = currency
        self.recordType = recordType
        self.notifiedAt = notifiedAt
    }
}

/// Sendable copy of a check run log entry.
public struct CheckRunEntry: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var finishedAt: Date?
    public var source: CheckSource
    public var outcome: CheckRunOutcome
    public var checkedCount: Int
    public var changedCount: Int
    public var failedCount: Int
    public var errorSummary: String?

    public init(
        id: UUID,
        startedAt: Date,
        finishedAt: Date?,
        source: CheckSource,
        outcome: CheckRunOutcome,
        checkedCount: Int,
        changedCount: Int,
        failedCount: Int,
        errorSummary: String?
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.source = source
        self.outcome = outcome
        self.checkedCount = checkedCount
        self.changedCount = changedCount
        self.failedCount = failedCount
        self.errorSummary = errorSummary
    }
}

/// Draft used when adding a new tracked app that already comes with a price.
public struct NewTrackedAppDraft: Sendable {
    public var trackId: String
    public var countryCode: String
    public var name: String
    public var developerName: String?
    public var artworkURL: String?
    public var appStoreURL: String?
    public var price: Decimal?
    public var formattedPrice: String?
    public var currency: String?

    public init(
        trackId: String,
        countryCode: String,
        name: String,
        developerName: String? = nil,
        artworkURL: String? = nil,
        appStoreURL: String? = nil,
        price: Decimal? = nil,
        formattedPrice: String? = nil,
        currency: String? = nil
    ) {
        self.trackId = trackId
        self.countryCode = countryCode
        self.name = name
        self.developerName = developerName
        self.artworkURL = artworkURL
        self.appStoreURL = appStoreURL
        self.price = price
        self.formattedPrice = formattedPrice
        self.currency = currency
    }
}

/// Store counters used by diagnostics.
public struct StoreCounts: Sendable, Equatable {
    public var trackedApps: Int
    public var priceRecords: Int
    public var checkRuns: Int

    public init(trackedApps: Int, priceRecords: Int, checkRuns: Int) {
        self.trackedApps = trackedApps
        self.priceRecords = priceRecords
        self.checkRuns = checkRuns
    }
}

/// Result of applying one evaluation to the store.
public struct AppliedEvaluation: Sendable {
    public var app: TrackedAppSnapshot
    public var appendedRecordID: UUID?
    public var appendedRecordType: PriceRecordType?
    public var wasDecrease: Bool
    public var isNewLow: Bool

    public init(
        app: TrackedAppSnapshot,
        appendedRecordID: UUID? = nil,
        appendedRecordType: PriceRecordType? = nil,
        wasDecrease: Bool = false,
        isNewLow: Bool = false
    ) {
        self.app = app
        self.appendedRecordID = appendedRecordID
        self.appendedRecordType = appendedRecordType
        self.wasDecrease = wasDecrease
        self.isNewLow = isNewLow
    }
}
