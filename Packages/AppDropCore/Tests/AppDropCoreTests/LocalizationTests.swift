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
            ) == .traditionalChinese
        )
        #expect(
            SharedText.notificationLanguage(
                preferredLanguages: ["en-GB", "zh-Hans-HK"]
            ) == .english
        )
        #expect(
            SharedText.notificationLanguage(
                preferredLanguages: ["fr-FR", "de-DE"]
            ) == .french
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

@Suite struct MultilingualNotificationTests {
    @Test func everyLanguageResolvesAllNotificationTemplates() {
        let keys = ["notification.drop.title", "notification.drop.body", "notification.drop.body.newLow", "notification.batch.title", "notification.batch.body.all", "notification.batch.body.more"]
        for language in NotificationLanguage.allCases {
            for key in keys {
                let value = SharedText.string(key, locale: Locale(identifier: language.rawValue))
                #expect(value != key)
                #expect(value != "AppDrop")
                #expect(!value.isEmpty)
            }
        }
    }

    @Test func regionalIdentifiersChooseScriptAndFirstSupportedLanguage() {
        #expect(SharedText.notificationLanguage(preferredLanguages: ["zh-Hant-TW"]) == .traditionalChinese)
        #expect(SharedText.notificationLanguage(preferredLanguages: ["zh-Hans-HK"]) == .simplifiedChinese)
        #expect(SharedText.notificationLanguage(preferredLanguages: ["zh_TW"]) == .traditionalChinese)
        #expect(SharedText.notificationLanguage(preferredLanguages: ["yue-HK"]) == .traditionalChinese)
        #expect(SharedText.notificationLanguage(preferredLanguages: ["nl-NL", "pt-BR", "en"]) == .portuguese)
        #expect(SharedText.notificationLanguage(preferredLanguages: ["xx", "fr-CA", "de-DE"]) == .french)
        #expect(SharedText.notificationLanguage(preferredLanguages: ["xx"]) == .english)
    }

    @Test func translatedFormatsKeepAllArgumentsAndCorrectBatchCounts() throws {
        let notifications = (1...4).map { index in
            PriceDropNotification(appName: "Game \(index)", trackId: "\(index)", countryCode: "us", formattedPrice: "$4.99", currency: "USD", dropPercent: 50, isNewLow: true, recordID: UUID())
        }
        for language in NotificationLanguage.allCases {
            let locale = Locale(identifier: language.rawValue)
            let single = try #require(NotificationContentBuilder.prepare([notifications[0]], locale: locale))
            #expect(single.title.contains("Game 1"))
            #expect(single.body.contains("$4.99"))
            #expect(single.body.contains("US"))
            #expect(single.body.contains("50%"))
            for count in [2, 3, 4] {
                let batch = try #require(NotificationContentBuilder.prepare(Array(notifications.prefix(count)), locale: locale))
                #expect(batch.title.contains("\(count)"))
                #expect(batch.body.contains("Game 1"))
                #expect(batch.recordIDs.count == count)
                #expect(!batch.body.contains("%@"))
                #expect(!batch.body.contains("%lld"))
                if count == 4 {
                    let expectedCount = language == .simplifiedChinese || language == .traditionalChinese ? 4 : 1
                    let expected = String(format: SharedText.string("notification.batch.body.more", locale: locale), "LIST", Int64(expectedCount))
                    #expect(expected.contains("\(expectedCount)"))
                    #expect(batch.body.contains("\(expectedCount)"))
                }
            }
        }
    }
}

@Suite struct NotificationStatusReportTests {
    @Test func statusReportsRoundTripAndDistinguishPermissions() throws {
        for status in [NotificationPermissionStatus.notDetermined, .denied, .authorized, .provisional, .unknown] {
            let report = NotificationStatusReport(authorization: status, alerts: "disabled", notificationCenter: "enabled", sound: "disabled")
            let decoded = try JSONDecoder().decode(NotificationStatusReport.self, from: JSONEncoder().encode(report))
            #expect(report == decoded)
            #expect(report.canSubmit == (status == .authorized || status == .provisional))
        }
    }

    @Test func testNotificationCopyIsAvailableInAllNineLanguages() {
        for language in NotificationLanguage.allCases {
            let title = SharedText.string("notification.test.title", locale: Locale(identifier: language.rawValue))
            let body = SharedText.string("notification.test.body", locale: Locale(identifier: language.rawValue))
            #expect(title.contains("AppDrop"))
            #expect(!body.isEmpty && body != "AppDrop" && body != "notification.test.body")
        }
    }
}
