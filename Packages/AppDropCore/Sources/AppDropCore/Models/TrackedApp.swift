import Foundation
import SwiftData

/// A tracked app / storefront pair. `trackId + countryCode` is the logical unique key.
@Model
public final class TrackedApp {
    public var id: UUID
    /// "\(trackId)|\(countryCode)" — single-column unique constraint as a duplicate guard.
    @Attribute(.unique) public var logicalKey: String
    public var trackId: String
    public var countryCode: String
    public var name: String
    public var developerName: String?
    public var artworkURL: String?
    public var appStoreURL: String?
    /// `nil` when no price has been observed yet (e.g. an imported wishlist entry
    /// that has not been checked). Never replaced by an invented zero.
    public var currentPrice: Decimal?
    public var formattedPrice: String?
    public var currency: String?
    public var lowestPrice: Decimal?
    public var isDiscounted: Bool
    /// Drop versus the previous effective price, in percent.
    public var discountRate: Decimal
    public var isAtHistoricalLow: Bool
    /// Number of recorded price observations in the current currency (the
    /// baseline plus every observed change). A lone observation cannot prove
    /// an all-time low, so the low badge requires at least two.
    /// The default keeps the additive SwiftData migration lightweight.
    public var priceObservationCount: Int = 0
    public var lastCheckedAt: Date?
    public var lastCheckAttemptAt: Date?
    public var lastCheckStatusRaw: String
    public var lastCheckError: String?
    public var lastPriceChangeAt: Date?
    public var lastDecreaseAt: Date?
    public var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \PriceRecord.app)
    public var priceHistory: [PriceRecord]

    public init(
        id: UUID = UUID(),
        trackId: String,
        countryCode: String,
        name: String,
        developerName: String? = nil,
        artworkURL: String? = nil,
        appStoreURL: String? = nil,
        currentPrice: Decimal? = nil,
        formattedPrice: String? = nil,
        currency: String? = nil,
        lowestPrice: Decimal? = nil,
        isDiscounted: Bool = false,
        discountRate: Decimal = 0,
        isAtHistoricalLow: Bool = false,
        priceObservationCount: Int = 0,
        lastCheckedAt: Date? = nil,
        lastCheckAttemptAt: Date? = nil,
        lastCheckStatus: CheckStatus = .unknown,
        lastCheckError: String? = nil,
        lastPriceChangeAt: Date? = nil,
        lastDecreaseAt: Date? = nil,
        createdAt: Date = Date(),
        priceHistory: [PriceRecord] = []
    ) {
        self.id = id
        self.logicalKey = TrackedApp.makeLogicalKey(trackId: trackId, countryCode: countryCode)
        self.trackId = trackId
        self.countryCode = StoreCountry.normalized(countryCode)
        self.name = name
        self.developerName = developerName
        self.artworkURL = artworkURL
        self.appStoreURL = appStoreURL
        self.currentPrice = currentPrice
        self.formattedPrice = formattedPrice
        self.currency = currency
        self.lowestPrice = lowestPrice
        self.isDiscounted = isDiscounted
        self.discountRate = discountRate
        self.isAtHistoricalLow = isAtHistoricalLow
        self.priceObservationCount = priceObservationCount
        self.lastCheckedAt = lastCheckedAt
        self.lastCheckAttemptAt = lastCheckAttemptAt
        self.lastCheckStatusRaw = lastCheckStatus.rawValue
        self.lastCheckError = lastCheckError
        self.lastPriceChangeAt = lastPriceChangeAt
        self.lastDecreaseAt = lastDecreaseAt
        self.createdAt = createdAt
        self.priceHistory = priceHistory
    }

    public var lastCheckStatus: CheckStatus {
        get { CheckStatus(rawValue: lastCheckStatusRaw) ?? .unknown }
        set { lastCheckStatusRaw = newValue.rawValue }
    }

    public static func makeLogicalKey(trackId: String, countryCode: String) -> String {
        "\(trackId)|\(StoreCountry.normalized(countryCode))"
    }

    /// Immutable snapshot that is safe to pass across actor boundaries.
    public func makeSnapshot() -> TrackedAppSnapshot {
        TrackedAppSnapshot(
            id: id,
            trackId: trackId,
            countryCode: countryCode,
            name: name,
            developerName: developerName,
            artworkURL: artworkURL,
            appStoreURL: appStoreURL,
            price: PriceSnapshot(
                price: currentPrice,
                formattedPrice: formattedPrice,
                currency: currency,
                lowestPrice: lowestPrice,
                isDiscounted: isDiscounted,
                discountRate: discountRate,
                isAtHistoricalLow: isAtHistoricalLow
            ),
            priceObservationCount: priceObservationCount,
            lastCheckedAt: lastCheckedAt,
            lastCheckAttemptAt: lastCheckAttemptAt,
            lastCheckStatus: lastCheckStatus,
            lastCheckError: lastCheckError,
            lastPriceChangeAt: lastPriceChangeAt,
            lastDecreaseAt: lastDecreaseAt,
            createdAt: createdAt
        )
    }
}
