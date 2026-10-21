import Foundation
import SwiftData

/// One entry of the price history of a tracked app / storefront pair.
@Model
public final class PriceRecord {
    public var id: UUID
    public var trackId: String
    public var countryCode: String
    public var timestamp: Date
    public var price: Decimal
    public var formattedPrice: String
    public var currency: String
    public var recordTypeRaw: String
    /// Set once a notification for this record has been scheduled, so retries
    /// and repeated cycles never notify twice for the same price change.
    public var notifiedAt: Date?
    public var app: TrackedApp?

    public init(
        id: UUID = UUID(),
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
        self.countryCode = StoreCountry.normalized(countryCode)
        self.timestamp = timestamp
        self.price = price
        self.formattedPrice = formattedPrice
        self.currency = currency
        self.recordTypeRaw = recordType.rawValue
        self.notifiedAt = notifiedAt
    }

    public var recordType: PriceRecordType {
        get { PriceRecordType(rawValue: recordTypeRaw) ?? .initial }
        set { recordTypeRaw = newValue.rawValue }
    }

    public func makeSnapshot() -> PriceRecordSnapshot {
        PriceRecordSnapshot(
            id: id,
            trackId: trackId,
            countryCode: countryCode,
            timestamp: timestamp,
            price: price,
            formattedPrice: formattedPrice,
            currency: currency,
            recordType: recordType,
            notifiedAt: notifiedAt
        )
    }
}
