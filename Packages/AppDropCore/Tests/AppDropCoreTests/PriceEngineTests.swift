import Foundation
import Testing
@testable import AppDropCore

@Suite struct PriceEngineTests {
    private func decimal(_ string: String) -> Decimal {
        Decimal(string: string) ?? 0
    }

    private func app(
        price: Decimal?,
        currency: String? = "USD",
        formatted: String? = "$4.99"
    ) -> AppStoreApp {
        AppStoreApp(
            trackId: "123456789",
            name: "Example",
            price: price,
            formattedPrice: formatted,
            currency: currency
        )
    }

    private func state(
        price: Decimal?,
        currency: String? = "USD",
        lowest: Decimal? = nil,
        isDiscounted: Bool = false,
        discountRate: Decimal = 0,
        atLow: Bool = false
    ) -> PriceSnapshot {
        PriceSnapshot(
            price: price,
            formattedPrice: price.map { "$\($0)" },
            currency: currency,
            lowestPrice: lowest ?? price,
            isDiscounted: isDiscounted,
            discountRate: discountRate,
            isAtHistoricalLow: atLow
        )
    }

    @Test func firstObservationCreatesBaselineWithoutNotification() {
        let evaluation = PriceEngine.evaluate(previous: nil, result: app(price: Decimal(string: "4.99")))
        guard case .baseline(let newState) = evaluation else {
            Issue.record("expected baseline, got \(evaluation)")
            return
        }
        #expect(newState.price == Decimal(string: "4.99"))
        #expect(newState.lowestPrice == Decimal(string: "4.99"))
        // A lone baseline observation is not an all-time low.
        #expect(!newState.isAtHistoricalLow)
        #expect(!newState.isDiscounted)
    }

    @Test func baselineIsAlsoUsedForEntriesWithoutPrice() {
        let previous = state(price: nil, currency: nil, lowest: nil)
        let evaluation = PriceEngine.evaluate(previous: previous, result: app(price: 0, formatted: "Free"))
        guard case .baseline(let newState) = evaluation else {
            Issue.record("expected baseline, got \(evaluation)")
            return
        }
        #expect(newState.price == 0)
    }

    @Test func missingPriceIsUnavailableAndNeverBecomesZero() {
        #expect(PriceEngine.evaluate(previous: nil, result: app(price: nil)) == .unavailable)
        #expect(PriceEngine.evaluate(previous: nil, result: nil) == .unavailable)
        #expect(PriceEngine.evaluate(previous: state(price: 4.99), result: app(price: nil)) == .unavailable)
        #expect(PriceEngine.evaluate(previous: state(price: 4.99), result: app(price: 1.99, currency: nil)) == .unavailable)
    }

    @Test func equalPriceIsUnchangedWithoutRecord() {
        let previous = state(price: Decimal(string: "4.99"))
        let evaluation = PriceEngine.evaluate(previous: previous, result: app(price: Decimal(string: "4.99")))
        guard case .unchanged(let newState) = evaluation else {
            Issue.record("expected unchanged, got \(evaluation)")
            return
        }
        #expect(newState.price == Decimal(string: "4.99"))
    }

    @Test func dropComputesPercentAndNewLow() {
        let previous = state(price: Decimal(string: "9.99"), lowest: Decimal(string: "9.99"))
        let evaluation = PriceEngine.evaluate(previous: previous, result: app(price: Decimal(string: "4.99")))
        guard case .decreased(let newState, let drop, let isNewLow) = evaluation else {
            Issue.record("expected decrease, got \(evaluation)")
            return
        }
        #expect(drop == Decimal(string: "50.1"))
        #expect(isNewLow)
        #expect(newState.isDiscounted)
        #expect(newState.discountRate == drop)
        #expect(newState.lowestPrice == Decimal(string: "4.99"))
        #expect(newState.isAtHistoricalLow)
    }

    @Test func dropAbovePreviousLowIsNotANewLow() {
        let previous = state(price: Decimal(string: "4.99"), lowest: Decimal(string: "1.99"))
        let evaluation = PriceEngine.evaluate(previous: previous, result: app(price: Decimal(string: "2.99")))
        guard case .decreased(let newState, _, let isNewLow) = evaluation else {
            Issue.record("expected decrease, got \(evaluation)")
            return
        }
        #expect(!isNewLow)
        #expect(newState.lowestPrice == Decimal(string: "1.99"))
        #expect(!newState.isAtHistoricalLow)
    }

    @Test func dropToThePreviousLowTiesWithoutNewLow() {
        let previous = state(price: Decimal(string: "4.99"), lowest: Decimal(string: "1.99"))
        let evaluation = PriceEngine.evaluate(previous: previous, result: app(price: Decimal(string: "1.99")))
        guard case .decreased(let newState, _, let isNewLow) = evaluation else {
            Issue.record("expected decrease, got \(evaluation)")
            return
        }
        #expect(!isNewLow)
        #expect(newState.isAtHistoricalLow)
    }

    @Test func increaseClearsDiscountAndKeepsLow() {
        let previous = state(price: Decimal(string: "1.99"), lowest: Decimal(string: "1.99"), isDiscounted: true, discountRate: 60, atLow: true)
        let evaluation = PriceEngine.evaluate(previous: previous, result: app(price: Decimal(string: "4.99")))
        guard case .increased(let newState) = evaluation else {
            Issue.record("expected increase, got \(evaluation)")
            return
        }
        #expect(!newState.isDiscounted)
        #expect(newState.discountRate == 0)
        #expect(newState.lowestPrice == Decimal(string: "1.99"))
        #expect(!newState.isAtHistoricalLow)
    }

    @Test func currencyChangeIsTreatedAsFreshBaseline() {
        let previous = state(price: Decimal(string: "4.99"), currency: "USD", lowest: Decimal(string: "4.99"))
        let evaluation = PriceEngine.evaluate(previous: previous, result: app(price: 700, currency: "JPY", formatted: "¥700"))
        guard case .currencyChanged(let newState) = evaluation else {
            Issue.record("expected currency change, got \(evaluation)")
            return
        }
        #expect(newState.currency == "JPY")
        #expect(newState.lowestPrice == 700)
        #expect(!newState.isDiscounted)
        #expect(!newState.isAtHistoricalLow)
    }

    @Test func historicalLowRequiresEvidenceOfAHigherObservation() {
        #expect(!PriceEngine.isAtHistoricalLow(current: 4.99, observedPrices: []))
        #expect(!PriceEngine.isAtHistoricalLow(current: decimal("4.99"), observedPrices: [decimal("4.99")]))
        #expect(!PriceEngine.isAtHistoricalLow(current: decimal("4.99"), observedPrices: [decimal("4.99"), decimal("4.99")]))
        #expect(PriceEngine.isAtHistoricalLow(current: decimal("4.99"), observedPrices: [decimal("9.99"), decimal("4.99")]))
        // Back at the low after a rise: equal to the minimum, with a higher
        // observation on record.
        #expect(PriceEngine.isAtHistoricalLow(current: decimal("4.99"), observedPrices: [decimal("9.99"), decimal("4.99"), decimal("9.99"), decimal("4.99")]))
        #expect(!PriceEngine.isAtHistoricalLow(current: decimal("4.99"), observedPrices: [decimal("9.99"), decimal("2.99"), decimal("9.99"), decimal("4.99")]))
        #expect(!PriceEngine.isAtHistoricalLow(current: decimal("9.99"), observedPrices: [decimal("9.99"), decimal("2.99")]))
        #expect(!PriceEngine.isAtHistoricalLow(current: 0, observedPrices: [0]))
    }

    @Test func firstObservedDropQualifiesAsLowWithRealEvidence() {
        let baseline = PriceEngine.evaluate(previous: nil, result: app(price: Decimal(string: "9.99")))
        guard case .baseline(let baselineState) = baseline else {
            Issue.record("expected baseline, got \(baseline)")
            return
        }
        #expect(!baselineState.isAtHistoricalLow)

        let drop = PriceEngine.evaluate(previous: baselineState, result: app(price: Decimal(string: "4.99")))
        guard case .decreased(let droppedState, _, let isNewLow) = drop else {
            Issue.record("expected decrease, got \(drop)")
            return
        }
        #expect(isNewLow)
        #expect(droppedState.isAtHistoricalLow)
    }

    @Test func freePricesNeverDivideByZero() {
        #expect(PriceEngine.dropPercent(from: 0, to: 0) == 0)
        #expect(PriceEngine.dropPercent(from: 0, to: 4.99) == 0)
        let fourNinetyNine = Decimal(string: "4.99") ?? 0
        #expect(PriceEngine.dropPercent(from: fourNinetyNine, to: 0) == 100)

        let previous = state(price: 0, lowest: 0)
        let evaluation = PriceEngine.evaluate(previous: previous, result: app(price: 0, formatted: "Free"))
        #expect(evaluation == .unchanged(state: PriceSnapshot(
            price: 0,
            formattedPrice: "Free",
            currency: "USD",
            lowestPrice: 0,
            isDiscounted: false,
            discountRate: 0,
            isAtHistoricalLow: false
        )))
    }

    @Test func regionIsolationIsTheResponsibilityOfTheKeyButStatesDoNotLeak() {
        let usState = state(price: Decimal(string: "4.99"), currency: "USD")
        let jpResult = AppStoreApp(trackId: "123456789", name: "Example", price: 700, formattedPrice: "¥700", currency: "JPY")
        let evaluation = PriceEngine.evaluate(previous: usState, result: jpResult)
        guard case .currencyChanged = evaluation else {
            Issue.record("expected currencyChanged, got \(evaluation)")
            return
        }
    }
}
