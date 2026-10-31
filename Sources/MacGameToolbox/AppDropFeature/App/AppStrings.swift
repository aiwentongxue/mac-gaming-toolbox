import Foundation
import AppDropCore

/// App-side localization helper. UI strings live in `AppDrop.xcstrings`;
/// notification strings live in the AppDropCore bundle (`SharedText`).
enum AppStrings {
    static func string(_ key: String) -> String {
        resolve(key, localeIdentifier: localeIdentifier)
    }

    /// Resolve each key independently: a language directory can exist for
    /// another module without containing the AppDrop table.
    static func resolve(
        _ key: String,
        localeIdentifier: String,
        bundles: [Bundle] = resourceBundles,
        fallbacks: [String: String] = englishFallbacks
    ) -> String {
        for language in [localeIdentifier, "en"] {
            for resource in bundles {
                if let path = resource.path(forResource: language, ofType: "lproj"),
                   let bundle = Bundle(path: path) {
                    let value = bundle.localizedString(forKey: key, value: "", table: "AppDrop")
                    if !value.isEmpty, value != key { return value }
                }
                // SwiftPM can copy an xcstrings catalog without compiling it.
                if let value = sourceCatalog(in: resource)[key]?[language], !value.isEmpty {
                    return value
                }
            }
        }
        if let value = fallbacks[key] { return value }
        return key.split(separator: ".").last.map { part in
            part.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
        } ?? "AppDrop"
    }

    static var resourceBundles: [Bundle] {
        #if SWIFT_PACKAGE
        [Bundle.module, Bundle.main]
        #else
        [Bundle.main]
        #endif
    }

    private static let catalogs: [URL: [String: [String: String]]] = {
        var result: [URL: [String: [String: String]]] = [:]
        for bundle in resourceBundles {
            guard let url = bundle.url(forResource: "AppDrop", withExtension: "xcstrings"),
                  let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let strings = root["strings"] as? [String: [String: Any]] else { continue }
            result[bundle.bundleURL] = strings.mapValues { entry in
                let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
                return localizations.compactMapValues { ($0["stringUnit"] as? [String: String])?["value"] }
            }
        }
        return result
    }()

    private static func sourceCatalog(in bundle: Bundle) -> [String: [String: String]] {
        catalogs[bundle.bundleURL] ?? [:]
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale(identifier: localeIdentifier), arguments: arguments)
    }

    /// Localized storefront name, falling back to the English name (and then
    /// to the uppercased code) when the catalog has no entry for the region.
    static func regionName(_ code: String) -> String {
        let key = "region.\(StoreCountry.normalized(code)).name"
        if englishFallbacks[key] != nil { return string(key) }
        return StoreCountry.displayName(for: code)
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

    static func errorDescription(_ error: Error) -> String {
        if let error = error as? AppStoreURLParserError {
            switch error {
            case .notAURL: return string("error.link.invalid")
            case .unsupportedHost(let host): return format("error.link.host", host)
            case .missingCountry: return string("error.link.country")
            case .unsupportedCountry(let code):
                return format("error.link.unsupportedCountry", code.uppercased(), SharedConstants.supportedCountryCodes.map { $0.uppercased() }.joined(separator: ", "))
            case .missingTrackId: return string("error.link.missingID")
            case .invalidTrackId(let id): return format("error.link.invalidID", id)
            }
        }
        if let error = error as? WishdropError {
            switch error {
            case .invalidJSON(let message): return format("error.import.json", message)
            case .wrongFormatIdentifier(let identifier): return format("error.import.format", identifier)
            case .unsupportedVersion(let version): return format("error.import.version", version, SharedConstants.wishdropFormatVersion)
            }
        }
        if let error = error as? AppStoreServiceError {
            switch error {
            case .invalidURL: return string("error.request.invalid")
            case .httpStatus(let code): return format("error.request.http", code)
            case .decodingFailed(let message): return format("error.request.decoding", message)
            case .network(let message): return format("error.request.network", message)
            case .cancelled: return string("error.request.cancelled")
            }
        }
        if let error = error as? AppDataStoreError {
            switch error {
            case .appNotFound: return string("error.store.appMissing")
            case .duplicateTrackedApp(let id, let country): return format("error.store.duplicate", id, country.uppercased())
            case .recordNotFound: return string("error.store.recordMissing")
            }
        }
        if let error = error as? SharedStoreError {
            switch error {
            case .applicationSupportDirectoryUnavailable: return string("error.storage.support")
            case .storageDirectoryUnavailable(let path, let underlying): return format("error.storage.create", path, underlying)
            case .storageDirectoryNotWritable(let path): return format("error.storage.write", path)
            case .containerInitializationFailed(let message): return format("error.storage.open", message)
            }
        }
        return error.localizedDescription
    }

    static func issueDescription(_ issue: WishdropEntryIssue) -> String {
        format("import.issue.entry", issue.index + 1, string("import.issue.\(issue.code.rawValue)"))
    }

    static let englishFallbacks: [String: String] = [
        "%@ · id%@": "%1$@ · id%2$@",
        "%@ %@": "%1$@ %2$@",
        "• %@": "• %@",
        "add.action": "Track This App",
        "add.duplicateNamed": "%@ is already tracked for this storefront.",
        "add.failed": "Could not add the app: %@",
        "add.link.invalid": "Enter a valid App Store link.",
        "add.link.parse": "Parse",
        "add.link.placeholder": "Paste an App Store link (apps.apple.com/…)",
        "add.noPrice": "The App Store did not return a price for this app.",
        "add.notFound": "The app could not be found in this storefront.",
        "add.platform": "Platform",
        "add.platform.ios": "iPhone·iPad",
        "add.platform.mac": "Mac",
        "add.region": "Region",
        "add.search.button": "Search",
        "add.search.indexGapHint": "Apple's search index does not include every app (some recently released Mac apps are missing). You can add such apps by pasting their App Store link.",
        "add.search.noExactMatch": "None of these results matches “%@”.",
        "add.search.noResults": "No results.",
        "add.search.placeholder": "Search the App Store",
        "add.search.switchToLink": "Add by link instead",
        "add.success": "Added %@.",
        "add.tab.link": "App Store Link",
        "add.tab.search": "Search",
        "add.title": "Add App",
        "settings.storageIdentity": "Local data: %1$@ · Helper: %2$@",
        "card.discountSinceLast": "%@ lower than the previous price",
        "card.firstRecordFormat": "First seen %@",
        "card.lastCheckedFormat": "Checked %@",
        "card.lowestFormat": "Lowest %@",
        "card.neverChecked": "Never checked",
        "card.newLowBadge": "All-time low",
        "card.pendingPrice": "Price pending",
        "common.add": "Add",
        "common.back": "Back",
        "common.cancel": "Cancel",
        "common.close": "Close",
        "common.continue": "Continue",
        "common.done": "Done",
        "common.ok": "OK",
        "common.working": "Working…",
        "Copyright (C) 2026 我是艾文喵": "Copyright (C) 2026 我是艾文喵",
        "detail.changeRegion": "Change Storefront…",
        "detail.changeRegion.duplicate": "This app is already tracked in the selected storefront.",
        "detail.changeRegionMessage": "The price history of the current storefront will be cleared and a new baseline will be created for the new storefront.",
        "detail.changeRegionTitle": "Change storefront?",
        "detail.chart.dateAxis": "Date",
        "detail.chart.empty": "No price history yet. Run a check to record the first price.",
        "detail.chart.priceAxis": "Price",
        "detail.chart.singlePoint": "Only one price recorded so far.",
        "detail.chart.title": "Price History",
        "detail.checkNow": "Check Now",
        "detail.currentPrice": "Current price",
        "detail.delete": "Stop Tracking…",
        "detail.deleteConfirmMessage": "The price history of this app and storefront will be removed.",
        "detail.deleteConfirmTitle": "Stop tracking this app?",
        "detail.lastChange": "Last price change",
        "detail.lastCheck": "Last successful check",
        "detail.lowestNoComparisonFormat": "First recorded %@, no comparison yet",
        "detail.lowestPrice": "All-time low",
        "detail.openInStore": "Open in App Store",
        "empty.lows.message": "Apps that are at their lowest recorded price appear here.",
        "empty.lows.title": "No all-time lows",
        "empty.todayDrops.message": "Price drops recorded today will show up here.",
        "empty.todayDrops.title": "No drops today",
        "empty.wishlist.message": "Track apps by App Store link or search, and AppDrop will watch their prices.",
        "empty.wishlist.title": "No tracked apps yet",
        "export.errorFormat": "Export failed: %@",
        "export.fileName": "AppDrop-Wishlist.wishdrop",
        "filter.allRegions": "All Regions",
        "import.errorFormat": "Import failed: %@",
        "import.inProgress": "Importing…",
        "import.summaryFormat": "Added %d · Already tracked %d · Invalid %d",
        "import.title": "Import Wishlist",
        "menu.title": "AppDrop",
        "onboarding.background.body": "AppDrop registers a lightweight background helper that checks prices even when the main app is closed. macOS may show a second notification permission prompt for the helper.",
        "onboarding.background.title": "Background checks",
        "onboarding.disabled": "Disabled",
        "onboarding.enabled": "Enabled",
        "onboarding.finish": "Finish",
        "onboarding.notifications.body": "AppDrop uses local notifications for price drops. You can skip this step and enable it later in Settings.",
        "onboarding.notifications.title": "Price drop notifications",
        "onboarding.region.body": "New apps use this storefront by default; you can pick a different one whenever you add an app.",
        "onboarding.region.title": "Choose a default storefront",
        "onboarding.summary.background": "Background checks: %@",
        "onboarding.summary.body": "AppDrop is ready. You can change any of these choices later in Settings.",
        "onboarding.summary.notifications": "Notifications: %@",
        "onboarding.summary.region": "Default storefront: %@",
        "onboarding.summary.title": "You're all set",
        "onboarding.useBackground": "Enable background checks",
        "onboarding.welcome.body": "Track App Store prices across 17 storefronts (US, UK, Japan, South Korea, Germany and more), review price history and get notified when prices drop.",
        "onboarding.welcome.title": "Welcome to AppDrop",
        "permission.authorized": "Authorized",
        "permission.denied": "Denied",
        "permission.ephemeral": "Ephemeral",
        "permission.notDetermined": "Not requested",
        "permission.provisional": "Provisional",
        "permission.unknown": "Unknown",
        "platform.ios": "iPhone·iPad",
        "platform.mac": "Mac",
        "refresh.summaryFormat": "Checked %d · Changed %d · Failed %d",
        "region.ar.name": "Argentina",
        "region.au.name": "Australia",
        "region.br.name": "Brazil",
        "region.ca.name": "Canada",
        "region.cn.name": "China mainland",
        "region.de.name": "Germany",
        "region.fr.name": "France",
        "region.gb.name": "United Kingdom",
        "region.hk.name": "Hong Kong",
        "region.in.name": "India",
        "region.jp.name": "Japan",
        "region.kr.name": "South Korea",
        "region.ng.name": "Nigeria",
        "region.sg.name": "Singapore",
        "region.tr.name": "Türkiye",
        "region.tw.name": "Taiwan",
        "region.us.name": "United States",
        "settings.about": "About",
        "settings.backend.enabled": "Enabled",
        "settings.backend.notFound": "Helper not found",
        "settings.backend.notRegistered": "Not registered",
        "settings.backend.requiresApproval": "Waiting for approval in System Settings",
        "settings.backend.requiresApprovalHint": "Allow AppDrop's background helper under System Settings → General → Login Items & Extensions, otherwise scheduled checks cannot run.",
        "settings.backend.unknown": "Unknown",
        "settings.background": "Background Checks",
        "settings.backgroundNote": "launchd runs the helper at most once every 24 hours and only while the Mac is awake; runs can be delayed or missed while the Mac sleeps or is off.",
        "settings.backgroundStateFormat": "Status: %@",
        "settings.backgroundToggle": "Enable background checks",
        "settings.defaultRegion": "Default region",
        "settings.defaultRegionCaption": "Default region only affects newly added apps. To change globally, use the option on the right.",
        "settings.helperPermissionHint": "The background helper requests its own notification permission the first time it runs. Notifications it sends use that permission.",
        "settings.lastAttempt": "Last attempt",
        "settings.lastError": "Last error",
        "settings.lastSuccess": "Last success",
        "settings.notifications": "Notifications",
        "settings.notificationStatus": "Permission",
        "settings.openLoginItems": "Open Login Items Settings",
        "settings.openNotificationSettings": "Open System Settings",
        "settings.requestNotification": "Request Permission",
        "settings.reRegister": "Re-register Helper",
        "settings.revealInFinder": "Reveal in Finder",
        "settings.runCheck": "Run Check Now",
        "settings.storage": "Shared Storage",
        "settings.storePath": "Store path",
        "settings.title": "Settings",
        "settings.versionFormat": "Version %@ (%@)",
        "sidebar.historicalLows": "All-time Lows",
        "sidebar.settings": "Settings",
        "sidebar.todayDrops": "Today's Drops",
        "sidebar.wishlist": "Wishlist",
        "sort.discount": "Discount",
        "sort.lastChecked": "Last Checked",
        "sort.name": "Name",
        "startup.body": "The shared local storage directory is not available. AppDrop refuses to create a different fallback database so that the app and the background helper always use one store.",
        "startup.storageHint": "AppDrop stores its database in your user Library. Confirm that the Application Support folder is writable, then reopen the app. No Full Disk Access grant is required.",
        "startup.quit": "Quit",
        "startup.title": "AppDrop could not open its shared database",
        "status.error": "Check failed",
        "status.notFound": "Not found in store results",
        "status.ok": "Up to date",
        "status.unknown": "Not checked yet",
        "toolbar.add": "Add App",
        "toolbar.export": "Export Wishlist",
        "toolbar.import": "Import Wishlist",
        "toolbar.layout": "Layout",
        "toolbar.refresh": "Refresh Prices",
        "toolbar.region": "Region",
        "toolbar.search": "Search apps",
        "toolbar.sort": "Sort",
        "settings.changeAllToDefaultRegion": "Change All Apps to Default Region",
        "settings.changeAllConfirmTitle": "Change All Apps to Default Region?",
        "settings.changeAllConfirmMessage": "This will switch all apps not already in %@ to this storefront and refresh their prices. Apps not available in that storefront will keep their current region.",
        "settings.changeAllConfirmAction": "Change All",
        "settings.changingRegions": "Updating regions…",
        "settings.changeAllResultTitle": "Region Update Results",
        "settings.changeAllResultMessage": "Updated %d apps to %@; %d unchanged; %d kept in original region (unavailable or already tracked).",
        "toolbar.select": "Select",
        "toolbar.selectAll": "Select All",
        "toolbar.deselectAll": "Deselect All",
        "toolbar.deleteSelected": "Delete",
        "toolbar.selectedCount": "%d Selected",
        "batchDelete.confirmTitle": "Delete Selected Apps",
        "batchDelete.confirmMessage": "Are you sure you want to remove the %d selected apps from tracking? This cannot be undone.",
        "batchDelete.confirmAction": "Delete %d Apps",
        "contextMenu.delete": "Delete App",
        "contextMenu.openInStore": "Open in App Store",
        "contextMenu.copyLink": "Copy Link",
        "error.link.invalid": "This does not look like an App Store link.",
        "error.link.host": "Unsupported host “%@”. Use apps.apple.com.",
        "error.link.country": "The link does not include a storefront country.",
        "error.link.unsupportedCountry": "Storefront “%@” is not supported. Supported: %@.",
        "error.link.missingID": "The link does not include an app ID.",
        "error.link.invalidID": "“%@” is not a valid App Store app ID.",
        "error.import.json": "This file is not valid JSON: %@",
        "error.import.format": "This is not an AppDrop wishdrop preset (format: %@).",
        "error.import.version": "Preset version %d exceeds supported version %d. Update AppDrop and try again.",
        "import.issue.entry": "Entry %d: %@",
        "import.issue.invalidTrackId": "Invalid app ID.",
        "import.issue.unsupportedCountry": "Unsupported storefront.",
        "import.issue.emptyName": "Missing app name.",
        "import.issue.invalidURL": "Invalid App Store URL.",
        "error.request.invalid": "Could not build a valid App Store request.",
        "error.request.http": "The App Store returned HTTP %d.",
        "error.request.decoding": "Could not read the App Store response: %@",
        "error.request.network": "Network error: %@",
        "error.request.cancelled": "The request was cancelled.",
        "error.store.appMissing": "The tracked app no longer exists.",
        "error.store.duplicate": "App %@ is already tracked in %@.",
        "error.store.recordMissing": "The price record no longer exists.",
        "error.storage.support": "Could not locate your Application Support folder.",
        "error.storage.create": "Could not create storage at %@: %@",
        "error.storage.write": "The storage folder is not writable: %@",
        "error.storage.open": "Could not open the database: %@",
        "notifications.app": "Toolbox Notifications",
        "notifications.helper": "Background Helper Notifications",
        "notifications.options": "Alerts: %@ · Notification Center: %@ · Sound: %@",
        "notifications.test": "Send Test Notification",
        "notifications.explanation": "The toolbox and its background helper require separate notification permissions. If denied, allow notifications in System Settings. Focus and alert settings may affect display. Newly allowed notifications trigger a fresh check and one summary of still-valid missed price drops.",
        "notifications.recovering": "Verifying missed price drops…",
        "notifications.submitted": "Submitted to the system. Check Notification Center; banner display depends on your system settings.",
        "notifications.failed": "Not submitted to the system: %@",
        "notifications.helperUnavailable": "Could not read helper notification status. Check the embedded helper and try again.",
        "notifications.setting.enabled": "Enabled",
        "notifications.setting.disabled": "Disabled",
        "notifications.setting.notSupported": "Not supported",
        "notifications.setting.unknown": "Unknown",
        "detail.reloadHistory": "Reload Price History",
        "notifications.deliveredCount": "Notification Center reports %d delivered notifications."
    ]
}
