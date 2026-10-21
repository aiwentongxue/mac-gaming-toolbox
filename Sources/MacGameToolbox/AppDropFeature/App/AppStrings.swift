import Foundation
import AppDropCore

/// App-side localization helper. UI strings live in `Localizable.xcstrings`;
/// notification strings live in the AppDropCore bundle (`SharedText`).
enum AppStrings {
    static func string(_ key: String) -> String {
        localizedBundle.localizedString(
            forKey: key,
            value: key,
            table: "AppDrop"
        )
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }

    /// Localized storefront name, falling back to the English name (and then
    /// to the uppercased code) when the catalog has no entry for the region.
    static func regionName(_ code: String) -> String {
        let key = "region.\(StoreCountry.normalized(code)).name"
        let localized = localizedBundle.localizedString(
            forKey: key,
            value: key,
            table: "AppDrop"
        )
        return localized == key ? StoreCountry.displayName(for: code) : localized
    }

    /// "中国香港 (HK)" / "Hong Kong (HK)" — used by every region picker.
    static func regionLabel(_ code: String) -> String {
        let name = regionName(code)
        let displayCode = StoreCountry.displayCode(for: code)
        guard !name.isEmpty, name.caseInsensitiveCompare(displayCode) != .orderedSame else {
            return displayCode
        }
        return "\(name) (\(displayCode))"
    }

    private static var localizedBundle: Bundle {
        let identifier = localeIdentifier
        if let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }

    static var localeIdentifier: String {
        switch AppLanguage.currentLanguage {
        case .simplifiedChinese: "zh-Hans"
        case .traditionalChinese: "zh-Hant"
        case .english, .system: "en"
        case .japanese: "ja"
        case .korean: "ko"
        case .german: "de"
        case .french: "fr"
        case .spanish: "es"
        case .portuguese: "pt"
        }
    }
}
