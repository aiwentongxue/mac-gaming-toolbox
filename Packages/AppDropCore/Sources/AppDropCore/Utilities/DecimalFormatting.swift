import Foundation

/// Formatting helpers for prices, percentages and relative dates used by the UI
/// and by tests.
public enum PriceFormatting {
    /// Rounds a decimal to the given scale using plain rounding.
    public static func rounded(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, .plain)
        return output
    }

    /// "12.5" for 12.5 % — always without a trailing percent sign.
    public static func percentString(_ value: Decimal, maximumFractionDigits: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let roundedValue = rounded(value, scale: maximumFractionDigits)
        return formatter.string(from: roundedValue as NSDecimalNumber) ?? "\(roundedValue)"
    }

    /// Compact representation for diagnostics/tests: "12.50 USD".
    public static func priceString(_ price: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let number = formatter.string(from: price as NSDecimalNumber) ?? "\(price)"
        return currency.isEmpty ? number : "\(number) \(currency)"
    }
}
