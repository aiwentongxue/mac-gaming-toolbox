import Foundation
import Testing
@testable import AppDropCore

@Suite struct AppStoreURLParserTests {
    @Test func parsesAllSupportedStorefronts() throws {
        let cases: [(String, String, String)] = [
            ("https://apps.apple.com/us/app/example/id123456789", "us", "123456789"),
            ("https://apps.apple.com/hk/app/example/id123456789", "hk", "123456789"),
            ("https://apps.apple.com/jp/app/example/id123456789", "jp", "123456789"),
            ("https://apps.apple.com/cn/app/example/id123456789", "cn", "123456789"),
            ("https://apps.apple.com/tw/app/example/id123456789", "tw", "123456789"),
            ("https://apps.apple.com/gb/app/example/id123456789", "gb", "123456789"),
            ("https://apps.apple.com/de/app/example/id123456789", "de", "123456789"),
            ("https://apps.apple.com/ca/app/example/id123456789", "ca", "123456789"),
            ("https://apps.apple.com/au/app/example/id123456789", "au", "123456789"),
            ("https://apps.apple.com/fr/app/example/id123456789", "fr", "123456789"),
            ("https://apps.apple.com/kr/app/example/id123456789", "kr", "123456789"),
            ("https://apps.apple.com/sg/app/example/id123456789", "sg", "123456789"),
            ("https://apps.apple.com/tr/app/example/id123456789", "tr", "123456789"),
            ("https://apps.apple.com/ng/app/example/id123456789", "ng", "123456789"),
            ("https://apps.apple.com/ar/app/example/id123456789", "ar", "123456789"),
            ("https://apps.apple.com/br/app/example/id123456789", "br", "123456789"),
            ("https://apps.apple.com/in/app/example/id123456789", "in", "123456789")
        ]
        for (input, country, trackId) in cases {
            let parsed = try #require(try? AppStoreURLParser.parse(input).get())
            #expect(parsed.countryCode == country)
            #expect(parsed.trackId == trackId)
            #expect(parsed.normalizedURL == "https://apps.apple.com/\(country)/app/id\(trackId)")
        }
    }

    @Test func handlesQueryParametersTrailingSlashAndCase() throws {
        let withQuery = try #require(try? AppStoreURLParser.parse("https://apps.apple.com/us/app/Example-App/id123456789?mt=12&uo=4").get())
        #expect(withQuery.trackId == "123456789")
        #expect(withQuery.countryCode == "us")

        let trailing = try #require(try? AppStoreURLParser.parse("https://apps.apple.com/JP/app/example/id123456789/").get())
        #expect(trailing.countryCode == "jp")

        let uppercase = try #require(try? AppStoreURLParser.parse("https://Apps.Apple.Com/Hk/app/example/ID123456789").get())
        #expect(uppercase.countryCode == "hk")
        #expect(uppercase.trackId == "123456789")
    }

    @Test func acceptsSluglessAndItunesLinks() throws {
        let slugless = try #require(try? AppStoreURLParser.parse("https://apps.apple.com/us/app/id123456789").get())
        #expect(slugless.trackId == "123456789")

        let itunes = try #require(try? AppStoreURLParser.parse("https://itunes.apple.com/cn/app/weekly/id123456789").get())
        #expect(itunes.countryCode == "cn")
    }

    @Test func rejectsMissingTrackId() {
        #expect(AppStoreURLParser.parse("https://apps.apple.com/us/app/example").failure == .missingTrackId)
    }

    @Test func rejectsMalformedTrackId() {
        #expect(AppStoreURLParser.parse("https://apps.apple.com/us/app/example/id12").failure == .invalidTrackId("id12"))
        #expect(AppStoreURLParser.parse("https://apps.apple.com/us/app/example/idabc").failure == .invalidTrackId("idabc"))
    }

    @Test func rejectsUnsupportedHost() {
        #expect(AppStoreURLParser.parse("https://appstore.example.com/us/app/example/id123456789").failure == .unsupportedHost("appstore.example.com"))
        #expect(AppStoreURLParser.parse("https://example.com/id123456789").failure == .unsupportedHost("example.com"))
    }

    @Test func rejectsUnsupportedAndMissingCountry() {
        #expect(AppStoreURLParser.parse("https://apps.apple.com/zz/app/example/id123456789").failure == .unsupportedCountry("zz"))
        #expect(AppStoreURLParser.parse("https://apps.apple.com/app/id123456789").failure == .missingCountry)
    }

    @Test func rejectsGarbage() {
        #expect(AppStoreURLParser.parse("").failure == .notAURL)
        #expect(AppStoreURLParser.parse("not a url at all").failure == .notAURL)
    }
}

private extension Result where Failure == AppStoreURLParserError {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
