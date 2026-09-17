import Foundation

public enum ClickFlowLanguage: String, CaseIterable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case portuguese = "pt"
}

enum ClickFlowL10n {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var selectedLanguage = inferredSystemLanguage()

    static func setLanguage(_ language: ClickFlowLanguage) {
        lock.lock()
        selectedLanguage = language
        lock.unlock()
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        lock.lock()
        let language = selectedLanguage
        lock.unlock()

        let format = localizedFormat(for: key, language: language)
        guard !arguments.isEmpty else { return format }
        return String(
            format: format,
            locale: Locale(identifier: language.rawValue),
            arguments: arguments
        )
    }

    private static func localizedFormat(for key: String, language: ClickFlowLanguage) -> String {
        guard let path = resourceBundle.path(forResource: language.rawValue, ofType: "lproj"),
              let languageBundle = Bundle(path: path) else {
            return resourceBundle.localizedString(forKey: key, value: key, table: nil)
        }
        return languageBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func catalog(for language: ClickFlowLanguage) -> [String: String] {
        guard let path = resourceBundle.path(forResource: language.rawValue, ofType: "lproj"),
              let languageBundle = Bundle(path: path),
              let stringsURL = languageBundle.url(forResource: "Localizable", withExtension: "strings"),
              let data = try? Data(contentsOf: stringsURL),
              let catalog = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: String] else {
            return [:]
        }
        return catalog
    }

    private static var resourceBundle: Bundle {
#if SWIFT_PACKAGE
        Bundle.module
#else
        Bundle.main
#endif
    }

    private static func inferredSystemLanguage() -> ClickFlowLanguage {
        guard let identifier = Locale.preferredLanguages.first else { return .english }
        let locale = Locale(identifier: identifier)
        switch locale.language.languageCode?.identifier.lowercased() {
        case "zh":
            return locale.language.script?.identifier.caseInsensitiveCompare("Hant") == .orderedSame
                ? .traditionalChinese
                : .simplifiedChinese
        case "ja": return .japanese
        case "ko": return .korean
        case "de": return .german
        case "fr": return .french
        case "es": return .spanish
        case "pt": return .portuguese
        default: return .english
        }
    }
}

@inline(__always)
func cf(_ key: String, _ arguments: CVarArg...) -> String {
    ClickFlowL10n.string(key, arguments: arguments)
}

private extension ClickFlowL10n {
    static func string(_ key: String, arguments: [CVarArg]) -> String {
        lock.lock()
        let language = selectedLanguage
        lock.unlock()
        let format = localizedFormat(for: key, language: language)
        guard !arguments.isEmpty else { return format }
        return String(
            format: format,
            locale: Locale(identifier: language.rawValue),
            arguments: arguments
        )
    }
}
