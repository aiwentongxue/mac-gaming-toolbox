import Foundation
import Testing
@testable import AppDropCore

@Suite struct StoreRegionTests {
    /// The storefront table is product data: it must match the agreed
    /// specification exactly (code, currency and symbol per region).
    @Test func regionTableMatchesSpecification() {
        let expected: [(String, String, String, String)] = [
            ("us", "United States", "USD", "$"),
            ("cn", "China mainland", "CNY", "¥"),
            ("hk", "Hong Kong", "HKD", "HK$"),
            ("tw", "Taiwan", "TWD", "NT$"),
            ("jp", "Japan", "JPY", "¥"),
            ("gb", "United Kingdom", "GBP", "£"),
            ("de", "Germany", "EUR", "€"),
            ("ca", "Canada", "CAD", "CA$"),
            ("au", "Australia", "AUD", "A$"),
            ("fr", "France", "EUR", "€"),
            ("kr", "South Korea", "KRW", "₩"),
            ("sg", "Singapore", "SGD", "S$"),
            ("tr", "Türkiye", "TRY", "₺"),
            ("ng", "Nigeria", "NGN", "₦"),
            ("ar", "Argentina", "ARS", "$"),
            ("br", "Brazil", "BRL", "R$"),
            ("in", "India", "INR", "₹")
        ]
        #expect(StoreCountry.regions.count == expected.count)
        for (index, item) in expected.enumerated() where index < StoreCountry.regions.count {
            let region = StoreCountry.regions[index]
            #expect(region.code == item.0)
            #expect(region.englishName == item.1)
            #expect(region.currency == item.2)
            #expect(region.symbol == item.3)
        }
    }

    @Test func lookupNormalizesInputAndFallsBackForUnknownCodes() {
        #expect(StoreCountry.region(for: "TW")?.currency == "TWD")
        #expect(StoreCountry.region(for: " gb ")?.symbol == "£")
        #expect(StoreCountry.region(for: "zz") == nil)
        #expect(StoreCountry.displayName(for: "KR") == "South Korea")
        #expect(StoreCountry.displayName(for: "zz") == "ZZ")
        #expect(StoreCountry.currency(for: "in") == "INR")
        #expect(StoreCountry.symbol(for: "ar") == "$")
        #expect(StoreCountry.symbol(forCurrency: " krw ") == "₩")
        #expect(StoreCountry.symbol(forCurrency: "XXX") == nil)
    }

    @Test func everySupportedCodeIsCanonicalAndUnique() {
        let codes = SharedConstants.supportedCountryCodes
        #expect(Set(codes).count == codes.count)
        #expect(codes == StoreCountry.regions.map(\.code))
        for code in codes {
            #expect(SharedConstants.isSupportedCountry(code))
            #expect(SharedConstants.isSupportedCountry(code.uppercased()))
            #expect(code == StoreCountry.normalized(code))
            #expect(code.count == 2)
            #expect(StoreCountry.region(for: code) != nil)
            #expect(StoreCountry.displayCode(for: code) == code.uppercased())
        }
    }
}
