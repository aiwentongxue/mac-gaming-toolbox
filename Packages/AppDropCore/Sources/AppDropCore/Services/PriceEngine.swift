import Foundation

/// Outcome of comparing one fresh App Store result with the stored state.
public enum PriceEvaluation: Sendable, Equatable {
    /// The lookup succeeded but the app is missing/incomplete in the results.
    case unavailable
    /// First successfully observed price for this app/storefront pair.
    case baseline(state: PriceSnapshot)
    /// Price identical to the previous effective price; no record is written.
    case unchanged(state: PriceSnapshot)
    /// Price dropped compared with the previous effective price.
    case decreased(state: PriceSnapshot, dropPercent: Decimal, isNewLow: Bool)
    /// Price rose; discount state is cleared, the historical low is kept.
    case increased(state: PriceSnapshot)
    /// The storefront reported a different currency; treated as a new baseline.
    case currencyChanged(state: PriceSnapshot)
}

/// Pure business rules that decide what a fresh App Store price means for a
/// tracked app. Everything here is deterministic and unit tested.
public enum PriceEngine {
    /// Evaluates a fresh lookup result against the previously stored state.
    public static func evaluate(previous: PriceSnapshot?, result: AppStoreApp?) -> PriceEvaluation {
        guard let result,
              let price = result.price,
              let currency = result.currency, !currency.isEmpty else {
            return .unavailable
        }
        let formatted = result.formattedPrice ?? PriceFormatting.priceString(price, currency: currency)

        guard let previous, let previousPrice = previous.price else {
            // First successfully observed price (or currency-less import entry).
            // A lone baseline observation is not an all-time low: without any
            // higher recorded price there is no evidence of a drop.
            return .baseline(state: PriceSnapshot(
                price: price,
                formattedPrice: formatted,
                currency: currency,
                lowestPrice: price,
                isDiscounted: false,
                discountRate: 0,
                isAtHistoricalLow: false
            ))
        }

        let previousCurrency = previous.currency ?? ""
        if previousCurrency.caseInsensitiveCompare(currency) != .orderedSame {
            // A fresh baseline in the new currency; same evidence rule as above.
            return .currencyChanged(state: PriceSnapshot(
                price: price,
                formattedPrice: formatted,
                currency: currency,
                lowestPrice: price,
                isDiscounted: false,
                discountRate: 0,
                isAtHistoricalLow: false
            ))
        }

        if price == previousPrice {
            var state = previous
            state.formattedPrice = formatted
            state.currency = currency
            return .unchanged(state: state)
        }

        if price < previousPrice {
            let drop = dropPercent(from: previousPrice, to: price)
            let previousLowest = previous.lowestPrice ?? previousPrice
            let lowest = min(previousLowest, price)
            // The drop itself is the evidence needed for "all-time low": the
            // previous observation was strictly higher than the new price.
            let isNewLow = price < previousLowest
            return .decreased(
                state: PriceSnapshot(
                    price: price,
                    formattedPrice: formatted,
                    currency: currency,
                    lowestPrice: lowest,
                    isDiscounted: true,
                    discountRate: drop,
                    isAtHistoricalLow: price <= lowest
                ),
                dropPercent: drop,
                isNewLow: isNewLow
            )
        }

        let previousLowest = previous.lowestPrice ?? previousPrice
        return .increased(state: PriceSnapshot(
            price: price,
            formattedPrice: formatted,
            currency: currency,
            lowestPrice: previousLowest,
            isDiscounted: false,
            discountRate: 0,
            isAtHistoricalLow: price <= previousLowest
        ))
    }

    /// Percentage drop from `old` to `new`. Returns 0 when `old` is not
    /// positive, so free apps never cause a division by zero.
    public static func dropPercent(from old: Decimal, to new: Decimal) -> Decimal {
        guard old > 0 else { return 0 }
        let ratio = (old - new) / old * 100
        return PriceFormatting.rounded(ratio, scale: 1)
    }

    /// Whether `current` qualifies as the all-time low of the recorded series.
    /// Requires the current price to equal the recorded minimum **and** at
    /// least one observation to have been strictly higher: a lone first
    /// observation (or a series of identical prices) never qualifies.
    public static func isAtHistoricalLow(current: Decimal, observedPrices: [Decimal]) -> Bool {
        guard let minimum = observedPrices.min(), let maximum = observedPrices.max() else {
            return false
        }
        return current == minimum && maximum > minimum
    }
}
