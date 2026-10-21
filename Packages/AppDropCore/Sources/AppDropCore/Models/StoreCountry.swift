import Foundation

/// Metadata for one supported App Store storefront.
public struct StoreRegion: Sendable, Equatable, Hashable, Identifiable {
    /// Canonical lowercase ISO 3166-1 alpha-2 storefront code.
    public var code: String
    /// English display name (notifications, diagnostics, and the English UI).
    public var englishName: String
    /// ISO 4217 currency code used by the storefront.
    public var currency: String
    /// Currency symbol as shown by the storefront.
    public var symbol: String

    public var id: String { code }

    public init(code: String, englishName: String, currency: String, symbol: String) {
        self.code = code
        self.englishName = englishName
        self.currency = currency
        self.symbol = symbol
    }
}

/// Helpers for App Store storefront country codes.
public enum StoreCountry {
    /// Supported storefronts in display order. This is the single source of
    /// truth for every region picker, validator and price formatter.
    public static let regions: [StoreRegion] = [
        StoreRegion(code: "us", englishName: "United States", currency: "USD", symbol: "$"),
        StoreRegion(code: "cn", englishName: "China mainland", currency: "CNY", symbol: "¥"),
        StoreRegion(code: "hk", englishName: "Hong Kong", currency: "HKD", symbol: "HK$"),
        StoreRegion(code: "tw", englishName: "Taiwan", currency: "TWD", symbol: "NT$"),
        StoreRegion(code: "jp", englishName: "Japan", currency: "JPY", symbol: "¥"),
        StoreRegion(code: "gb", englishName: "United Kingdom", currency: "GBP", symbol: "£"),
        StoreRegion(code: "de", englishName: "Germany", currency: "EUR", symbol: "€"),
        StoreRegion(code: "ca", englishName: "Canada", currency: "CAD", symbol: "CA$"),
        StoreRegion(code: "au", englishName: "Australia", currency: "AUD", symbol: "A$"),
        StoreRegion(code: "fr", englishName: "France", currency: "EUR", symbol: "€"),
        StoreRegion(code: "kr", englishName: "South Korea", currency: "KRW", symbol: "₩"),
        StoreRegion(code: "sg", englishName: "Singapore", currency: "SGD", symbol: "S$"),
        StoreRegion(code: "tr", englishName: "Türkiye", currency: "TRY", symbol: "₺"),
        StoreRegion(code: "ng", englishName: "Nigeria", currency: "NGN", symbol: "₦"),
        StoreRegion(code: "ar", englishName: "Argentina", currency: "ARS", symbol: "$"),
        StoreRegion(code: "br", englishName: "Brazil", currency: "BRL", symbol: "R$"),
        StoreRegion(code: "in", englishName: "India", currency: "INR", symbol: "₹")
    ]

    /// Supported storefront codes in display order.
    public static var codes: [String] { regions.map(\.code) }

    /// Normalizes user input into the canonical lowercase two-letter code.
    public static func normalized(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Region metadata for a code, or `nil` when the storefront is not supported.
    public static func region(for code: String) -> StoreRegion? {
        let normalized = normalized(code)
        return regions.first { $0.code == normalized }
    }

    /// English display name (used in notifications and diagnostics).
    public static func displayName(for code: String) -> String {
        region(for: code)?.englishName ?? normalized(code).uppercased()
    }

    /// Uppercased code for display.
    public static func displayCode(for code: String) -> String {
        normalized(code).uppercased()
    }

    /// ISO 4217 currency of a supported storefront.
    public static func currency(for code: String) -> String? {
        region(for: code)?.currency
    }

    /// Currency symbol of a supported storefront.
    public static func symbol(for code: String) -> String? {
        region(for: code)?.symbol
    }

    /// Currency symbol for an ISO 4217 code, used when only the currency that
    /// the App Store reported is known (e.g. building a fallback price string).
    public static func symbol(forCurrency currency: String) -> String? {
        let normalized = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return nil }
        return regions.first { $0.currency == normalized }?.symbol
    }
}
