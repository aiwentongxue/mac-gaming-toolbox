import Foundation
import UserNotifications

/// Notification permission state, decoupled from UserNotifications types.
public enum NotificationPermissionStatus: String, Sendable, Equatable {
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

enum NotificationLanguage: String, Sendable, Equatable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
}

/// Localized strings that live inside the AppDropCore resource bundle.
public enum SharedText {
    /// Looks a string up in the AppDropCore bundle for an explicit locale.
    /// `String(localized:bundle:locale:)` only uses the locale for formatting,
    /// so the `.lproj` directory is resolved explicitly here.
    public static func string(_ key: String, locale: Locale? = nil) -> String {
        let language = locale.map(language(for:))
            ?? notificationLanguage(preferredLanguages: Locale.preferredLanguages)
        if let bundle = bundle(for: language) {
            return bundle.localizedString(forKey: key, value: nil, table: nil)
        }
        return Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    static func notificationLanguage(preferredLanguages: [String]) -> NotificationLanguage {
        let candidates = preferredLanguages.isEmpty
            ? [Locale.current.identifier]
            : preferredLanguages
        for identifier in candidates {
            let normalized = identifier
                .replacingOccurrences(of: "_", with: "-")
                .lowercased()
            if normalized == "zh"
                || normalized.hasPrefix("zh-")
                || normalized == "yue"
                || normalized.hasPrefix("yue-") {
                return .simplifiedChinese
            }
            if normalized == "en" || normalized.hasPrefix("en-") {
                return .english
            }
        }
        return .english
    }

    private static func language(for locale: Locale) -> NotificationLanguage {
        let identifier = locale.identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        if identifier == "zh"
            || identifier.hasPrefix("zh-")
            || identifier == "yue"
            || identifier.hasPrefix("yue-") {
            return .simplifiedChinese
        }
        return .english
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
        case .simplifiedChinese:
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

    public func permission() async -> NotificationPermissionStatus {
        let settings = await center.notificationSettings()
        return NotificationPermissionStatus(settings.authorizationStatus)
    }

    public func requestPermission() async -> NotificationPermissionStatus {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await permission()
    }

    public func sendPriceDrops(_ notifications: [PriceDropNotification]) async -> Bool {
        guard !notifications.isEmpty else { return true }
        let status = await permission()
        guard status == .authorized || status == .provisional else {
            AppLog.info("notification skipped: permission is \(status.rawValue)")
            return false
        }

        guard let prepared = NotificationContentBuilder.prepare(notifications) else {
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
