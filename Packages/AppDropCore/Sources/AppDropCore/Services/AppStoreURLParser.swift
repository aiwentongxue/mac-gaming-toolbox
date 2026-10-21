import Foundation

/// A parsed App Store link.
public struct ParsedAppStoreLink: Sendable, Equatable {
    public var trackId: String
    public var countryCode: String
    public var normalizedURL: String

    public init(trackId: String, countryCode: String, normalizedURL: String) {
        self.trackId = trackId
        self.countryCode = countryCode
        self.normalizedURL = normalizedURL
    }
}

/// Reasons an App Store link could not be used.
public enum AppStoreURLParserError: Error, LocalizedError, Equatable {
    case notAURL
    case unsupportedHost(String)
    case missingCountry
    case unsupportedCountry(String)
    case missingTrackId
    case invalidTrackId(String)

    public var errorDescription: String? {
        switch self {
        case .notAURL:
            return "This does not look like an App Store link."
        case .unsupportedHost(let host):
            return "Unsupported host \"\(host)\". Use an apps.apple.com link."
        case .missingCountry:
            return "The link does not include a storefront country."
        case .unsupportedCountry(let code):
            let supported = SharedConstants.supportedCountryCodes
                .map { $0.uppercased() }
                .joined(separator: ", ")
            return "The storefront \"\(code.uppercased())\" is not supported. Supported storefronts: \(supported)."
        case .missingTrackId:
            return "The link does not include an app id."
        case .invalidTrackId(let value):
            return "\"\(value)\" is not a valid App Store app id."
        }
    }
}

/// Structured parser for App Store links (no broad regular expressions).
public enum AppStoreURLParser {
    private static let supportedHosts: Set<String> = ["apps.apple.com", "itunes.apple.com"]

    public static func parse(_ input: String) -> Result<ParsedAppStoreLink, AppStoreURLParserError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.notAURL) }
        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased() else {
            return .failure(.notAURL)
        }
        guard supportedHosts.contains(host) else {
            return .failure(.unsupportedHost(host))
        }

        let segments = components.path
            .split(separator: "/")
            .map { String($0) }
            .filter { !$0.isEmpty }

        guard let first = segments.first,
              first.count == 2,
              first.allSatisfy({ $0.isLetter }) else {
            return .failure(.missingCountry)
        }
        let country = first.lowercased()
        guard SharedConstants.isSupportedCountry(country) else {
            return .failure(.unsupportedCountry(country))
        }

        guard let idSegment = segments.last(where: { isIdentifierSegment($0) }) else {
            // Distinguish "id present but malformed" from "no id at all".
            if let malformed = segments.last(where: { $0.lowercased().hasPrefix("id") }) {
                return .failure(.invalidTrackId(malformed))
            }
            return .failure(.missingTrackId)
        }

        let digits = String(idSegment.dropFirst(2))
        let normalized = "https://apps.apple.com/\(country)/app/id\(digits)"
        return .success(ParsedAppStoreLink(trackId: digits, countryCode: country, normalizedURL: normalized))
    }

    private static func isIdentifierSegment(_ segment: String) -> Bool {
        let lower = segment.lowercased()
        guard lower.hasPrefix("id") else { return false }
        let digits = lower.dropFirst(2)
        return digits.count >= 6 && digits.count <= 12 && digits.allSatisfy(\.isNumber)
    }
}
