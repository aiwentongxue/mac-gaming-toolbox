import Foundation
import Testing
@testable import AppDropCore

@Suite struct LocalizationTests {
    @Test func notificationStringsResolveInBothLanguages() {
        let english = SharedText.string("notification.drop.title", locale: Locale(identifier: "en"))
        let chinese = SharedText.string("notification.drop.title", locale: Locale(identifier: "zh-Hans"))
        #expect(english.contains("Price drop"))
        #expect(chinese.contains("降价"))

        let bodyEN = SharedText.string("notification.drop.body", locale: Locale(identifier: "en"))
        let bodyZH = SharedText.string("notification.drop.body", locale: Locale(identifier: "zh-Hans"))
        #expect(bodyEN.contains("%@"))
        #expect(bodyZH.contains("%@"))
    }

    @Test func preferredLanguageUsesFirstSupportedLanguage() {
        #expect(
            SharedText.notificationLanguage(
                preferredLanguages: ["zh-Hans-HK", "yue-Hant-HK", "en-GB"]
            ) == .simplifiedChinese
        )
        #expect(
            SharedText.notificationLanguage(
                preferredLanguages: ["zh_CN", "en-GB"]
            ) == .simplifiedChinese
        )
        #expect(
            SharedText.notificationLanguage(
                preferredLanguages: ["yue-Hant-HK", "en-GB"]
            ) == .simplifiedChinese
        )
        #expect(
            SharedText.notificationLanguage(
                preferredLanguages: ["en-GB", "zh-Hans-HK"]
            ) == .english
        )
        #expect(
            SharedText.notificationLanguage(
                preferredLanguages: ["fr-FR", "de-DE"]
            ) == .english
        )
    }

    @Test func singleDropKeepsDetailedFormat() throws {
        let notification = PriceDropNotification(
            appName: "Example",
            trackId: "123456789",
            countryCode: "us",
            formattedPrice: "$4.99",
            currency: "USD",
            dropPercent: 50,
            isNewLow: true,
            recordID: UUID()
        )

        let chinese = try #require(
            NotificationContentBuilder.prepare(
                [notification],
                locale: Locale(identifier: "zh-Hans")
            )
        )
        #expect(chinese.title == "降价提醒：Example")
        #expect(chinese.body.contains("$4.99"))
        #expect(chinese.body.contains("刷新历史最低价"))
    }

    @Test func multipleDropsUseNamesAndCounts() throws {
        let notifications = (1...4).map { index in
            PriceDropNotification(
                appName: "Game \(index)",
                trackId: "12345678\(index)",
                countryCode: "us",
                formattedPrice: "$4.99",
                currency: "USD",
                dropPercent: 50,
                isNewLow: false,
                recordID: UUID()
            )
        }

        let chinese = try #require(
            NotificationContentBuilder.prepare(
                notifications,
                locale: Locale(identifier: "zh-Hans")
            )
        )
        #expect(chinese.title == "4 款游戏降价")
        #expect(chinese.body == "Game 1、Game 2、Game 3 等 4 款游戏降价了。")
        #expect(chinese.recordIDs.count == 4)
        #expect(chinese.identifier.hasPrefix("price-drop-batch-4-"))

        let english = try #require(
            NotificationContentBuilder.prepare(
                notifications,
                locale: Locale(identifier: "en")
            )
        )
        #expect(english.title == "4 Games Dropped in Price")
        #expect(english.body == "Game 1, Game 2, Game 3, plus 1 more, have dropped in price.")
    }

    @Test func twoAndThreeDropsListEveryGame() throws {
        let notifications = (1...3).map { index in
            PriceDropNotification(
                appName: "Game \(index)",
                trackId: "12345678\(index)",
                countryCode: "us",
                formattedPrice: "$4.99",
                currency: "USD",
                dropPercent: 50,
                isNewLow: false,
                recordID: UUID()
            )
        }

        let two = try #require(
            NotificationContentBuilder.prepare(
                Array(notifications.prefix(2)),
                locale: Locale(identifier: "zh-Hans")
            )
        )
        #expect(two.title == "2 款游戏降价")
        #expect(two.body == "Game 1、Game 2 降价了。")

        let three = try #require(
            NotificationContentBuilder.prepare(
                notifications,
                locale: Locale(identifier: "en")
            )
        )
        #expect(three.title == "3 Games Dropped in Price")
        #expect(three.body == "Game 1, Game 2 and Game 3 have dropped in price.")
    }

    @Test func emptyBatchHasNoNotificationContent() {
        #expect(NotificationContentBuilder.prepare([]) == nil)
    }
}
