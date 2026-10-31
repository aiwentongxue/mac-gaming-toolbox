import Foundation
import UserNotifications

/// Notification permission state, decoupled from UserNotifications types.
public enum NotificationPermissionStatus: String, Codable, Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    public init(_ settingsAuthorization: UNAuthorizationStatus) {
        switch settingsAuthorization {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized: self = .authorized
        case .provisional: self = .provisional
        case .ephemeral: self = .ephemeral
        @unknown default: self = .unknown
        }
    }
}

/// A report belongs to the calling bundle, never to another app's identity.
public struct NotificationStatusReport: Codable, Sendable, Equatable {
    public var authorization: NotificationPermissionStatus
    public var alerts: String
    public var notificationCenter: String
    public var sound: String
    public var deliveredCount: Int
    public var canSubmit: Bool { authorization == .authorized || authorization == .provisional }

    public init(authorization: NotificationPermissionStatus, alerts: String, notificationCenter: String, sound: String, deliveredCount: Int = 0) {
        self.authorization = authorization
        self.alerts = alerts
        self.notificationCenter = notificationCenter
        self.sound = sound
        self.deliveredCount = deliveredCount
    }
}

public struct NotificationTestResult: Codable, Sendable {
    public var submitted: Bool
    public var error: String?
    public init(submitted: Bool, error: String? = nil) {
        self.submitted = submitted
        self.error = error
    }
}

/// Payload for one price-drop notification.
public struct PriceDropNotification: Sendable, Equatable {
    public var appName: String
    public var trackId: String
    public var countryCode: String
    public var formattedPrice: String
    public var currency: String
    public var dropPercent: Decimal
    public var isNewLow: Bool
    public var recordID: UUID

    public init(
        appName: String,
        trackId: String,
        countryCode: String,
        formattedPrice: String,
        currency: String,
        dropPercent: Decimal,
        isNewLow: Bool,
        recordID: UUID
    ) {
        self.appName = appName
        self.trackId = trackId
        self.countryCode = countryCode
        self.formattedPrice = formattedPrice
        self.currency = currency
        self.dropPercent = dropPercent
        self.isNewLow = isNewLow
        self.recordID = recordID
    }
}

/// Injectable notification interface (keeps the refresh engine testable).
public protocol UserNotifying: Sendable {
    func permission() async -> NotificationPermissionStatus
    func requestPermission() async -> NotificationPermissionStatus
    /// Returns true when one notification covering every payload was scheduled.
    func sendPriceDrops(_ notifications: [PriceDropNotification]) async -> Bool
}

/// Does nothing; used by tests and diagnostic modes.
public struct NoopNotifier: UserNotifying {
    public init() {}
    public func permission() async -> NotificationPermissionStatus { .notDetermined }
    public func requestPermission() async -> NotificationPermissionStatus { .notDetermined }
    public func sendPriceDrops(_ notifications: [PriceDropNotification]) async -> Bool { false }
}

enum NotificationLanguage: String, Sendable, Equatable, CaseIterable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case portuguese = "pt"
}

/// Localized strings that live inside the AppDropCore resource bundle.
public enum SharedText {
    /// Looks a string up in the AppDropCore bundle for an explicit locale.
    /// `String(localized:bundle:locale:)` only uses the locale for formatting,
    /// so the `.lproj` directory is resolved explicitly here.
    public static func string(_ key: String, locale: Locale? = nil) -> String {
        let language = locale.map(language(for:))
            ?? notificationLanguage(preferredLanguages: Locale.preferredLanguages)
        for candidate in [language, .english] {
            if let bundle = bundle(for: candidate) {
                let value = bundle.localizedString(forKey: key, value: "", table: nil)
                if !value.isEmpty, value != key { return value }
            }
        }
        return "AppDrop"
    }

    static func notificationLanguage(preferredLanguages: [String]) -> NotificationLanguage {
        let candidates = preferredLanguages.isEmpty ? [Locale.current.identifier] : preferredLanguages
        for identifier in candidates {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            let parts = normalized.split(separator: "-")
            guard let base = parts.first else { continue }
            if base == "zh" || base == "yue" {
                if parts.contains("hans") { return .simplifiedChinese }
                if parts.contains("hant") || parts.contains("tw") || parts.contains("hk") || parts.contains("mo") || base == "yue" {
                    return .traditionalChinese
                }
                return .simplifiedChinese
            }
            if let language = NotificationLanguage(rawValue: String(base)) { return language }
        }
        return .english
    }

    private static func language(for locale: Locale) -> NotificationLanguage {
        notificationLanguage(preferredLanguages: [locale.identifier])
    }

    private static func bundle(for language: NotificationLanguage) -> Bundle? {
        guard let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}

struct PreparedNotification: Sendable, Equatable {
    var identifier: String
    var title: String
    var body: String
    var recordIDs: [UUID]

    var userInfo: [String: Any] {
        if recordIDs.count == 1, let recordID = recordIDs.first {
            return ["recordID": recordID.uuidString]
        }
        return [
            "recordIDs": recordIDs.map(\.uuidString),
            "recordCount": recordIDs.count
        ]
    }
}

enum NotificationContentBuilder {
    static func prepare(
        _ notifications: [PriceDropNotification],
        locale: Locale? = nil
    ) -> PreparedNotification? {
        guard !notifications.isEmpty else { return nil }
        let language = locale.map { locale in
            SharedText.notificationLanguage(preferredLanguages: [locale.identifier])
        } ?? SharedText.notificationLanguage(preferredLanguages: Locale.preferredLanguages)

        if notifications.count == 1 {
            let notification = notifications[0]
            let country = StoreCountry.displayCode(for: notification.countryCode)
            let percent = PriceFormatting.percentString(notification.dropPercent) + "%"
            let bodyKey = notification.isNewLow
                ? "notification.drop.body.newLow"
                : "notification.drop.body"
            return PreparedNotification(
                identifier: "price-drop-\(notification.recordID.uuidString)",
                title: String(
                    format: SharedText.string("notification.drop.title", locale: locale),
                    notification.appName
                ),
                body: String(
                    format: SharedText.string(bodyKey, locale: locale),
                    notification.formattedPrice,
                    country,
                    percent
                ),
                recordIDs: [notification.recordID]
            )
        }

        let sortedRecordIDs = notifications.map(\.recordID.uuidString).sorted()
        let names = notifications.map(\.appName)
        let listedNames = names.prefix(3)
        let joinedNames: String
        let body: String
        switch language {
        case .simplifiedChinese, .traditionalChinese:
            joinedNames = listedNames.joined(separator: "、")
            if notifications.count > 3 {
                body = String(
                    format: SharedText.string("notification.batch.body.more", locale: locale),
                    joinedNames,
                    Int64(notifications.count)
                )
            } else {
                body = String(
                    format: SharedText.string("notification.batch.body.all", locale: locale),
                    joinedNames
                )
            }
        case .english:
            if notifications.count == 2 {
                joinedNames = "\(listedNames[0]) and \(listedNames[1])"
            } else if notifications.count == 3 {
                joinedNames = "\(listedNames[0]), \(listedNames[1]) and \(listedNames[2])"
            } else {
                joinedNames = listedNames.joined(separator: ", ")
            }
            if notifications.count > 3 {
                body = String(
                    format: SharedText.string("notification.batch.body.more", locale: locale),
                    joinedNames,
                    Int64(notifications.count - 3)
                )
            } else {
                body = String(
                    format: SharedText.string("notification.batch.body.all", locale: locale),
                    joinedNames
                )
            }
        case .japanese, .korean, .german, .french, .spanish, .portuguese:
            let formatter = ListFormatter()
            formatter.locale = Locale(identifier: language.rawValue)
            joinedNames = formatter.string(from: Array(listedNames)) ?? listedNames.joined(separator: ", ")
            if notifications.count > 3 {
                body = String(
                    format: SharedText.string("notification.batch.body.more", locale: locale),
                    joinedNames,
                    Int64(notifications.count - 3)
                )
            } else {
                body = String(format: SharedText.string("notification.batch.body.all", locale: locale), joinedNames)
            }
        }

        return PreparedNotification(
            identifier: "price-drop-batch-\(notifications.count)-\(sortedRecordIDs.first!)-\(sortedRecordIDs.last!)",
            title: String(
                format: SharedText.string("notification.batch.title", locale: locale),
                Int64(notifications.count)
            ),
            body: body,
            recordIDs: sortedRecordIDs.compactMap(UUID.init(uuidString:))
        )
    }
}

/// UserNotifications backed scheduler used by both the app and the helper.
/// The permission identity is the bundle of the calling process, which is why
/// the embedded helper requests its own authorization once.
public final class UserNotificationScheduler: UserNotifying, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func statusReport() async -> NotificationStatusReport {
        let settings = await center.notificationSettings()
        func value(_ setting: UNNotificationSetting) -> String {
            switch setting {
            case .enabled: return "enabled"
            case .disabled: return "disabled"
            case .notSupported: return "notSupported"
            @unknown default: return "unknown"
            }
        }
        let deliveredCount = await center.deliveredNotifications().count
        return NotificationStatusReport(
            authorization: NotificationPermissionStatus(settings.authorizationStatus),
            alerts: value(settings.alertSetting), notificationCenter: value(settings.notificationCenterSetting),
            sound: value(settings.soundSetting), deliveredCount: deliveredCount
        )
    }

    public func permission() async -> NotificationPermissionStatus {
        await statusReport().authorization
    }

    public func submitTestNotification() async -> NotificationTestResult {
        let report = await statusReport()
        guard report.canSubmit else { return NotificationTestResult(submitted: false, error: report.authorization.rawValue) }
        let content = UNMutableNotificationContent()
        content.title = SharedText.string("notification.test.title")
        content.body = SharedText.string("notification.test.body")
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: "appdrop-test-\(UUID().uuidString)", content: content, trigger: nil))
            return NotificationTestResult(submitted: true)
        } catch {
            return NotificationTestResult(submitted: false, error: error.localizedDescription)
        }
    }

    public func requestPermission() async -> NotificationPermissionStatus {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await permission()
    }

    public func sendPriceDrops(_ notifications: [PriceDropNotification]) async -> Bool {
        guard !notifications.isEmpty else { return true }
        let report = await statusReport()
        guard report.canSubmit else {
            AppLog.info("notification skipped: permission is \(report.authorization.rawValue)")
            return false
        }

        // Repair an interrupted marker save without displaying the same alert
        // again in this identity's Notification Center.
        let delivered = await center.deliveredNotifications()
        let requests = await center.pendingNotificationRequests()
        let infos = delivered.map { $0.request.content.userInfo } + requests.map { $0.content.userInfo }
        let knownIDs = Set(infos.flatMap { info -> [String] in
            if let id = info["recordID"] as? String { return [id] }
            return info["recordIDs"] as? [String] ?? []
        })
        let unscheduled = notifications.filter { !knownIDs.contains($0.recordID.uuidString) }
        if unscheduled.isEmpty { return true }
        guard let prepared = NotificationContentBuilder.prepare(unscheduled) else {
            return false
        }
        let content = UNMutableNotificationContent()
        content.title = prepared.title
        content.body = prepared.body
        content.sound = .default
        content.userInfo = prepared.userInfo

        let request = UNNotificationRequest(
            identifier: prepared.identifier,
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            return true
        } catch {
            AppLog.error("notification could not be scheduled: \(error.localizedDescription)")
            return false
        }
    }
}
