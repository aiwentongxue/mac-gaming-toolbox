import AppKit
import Foundation
import AppDropCore
import SwiftData
import SwiftUI

/// Summary shown after importing a `.wishdrop` file.
struct WishdropImportSummary: Identifiable {
    let id = UUID()
    var fileName: String
    var addedCount: Int
    var existingCount: Int
    var invalidCount: Int
    var issues: [WishdropEntryIssue]
    var errorMessage: String?
}

enum AddTrackedAppOutcome: Equatable {
    case added(name: String)
    case duplicate(name: String)
    case failed(message: String)
}

/// Error wrapper for export failures (String is not an Error type).
struct AppExportError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Central UI-facing state: container, services and cross-cutting actions.
@MainActor
final class AppEnvironment: ObservableObject {
    private enum DefaultsKey {
        static let defaultCountryCode = "appdrop.defaultCountryCode"
    }

    let container: ModelContainer?
    let startupError: String?
    let store: AppDataStore?
    let fetcher: AppStoreService
    let notificationScheduler: UserNotificationScheduler
    let backend = BackendManager()
    private(set) var refresh: RefreshCoordinator?

    /// Bumped whenever data may have changed (manual refresh, import, helper
    /// run) so that query-backed views reload.
    @Published private(set) var dataVersion = 0
    @Published var pendingImportSummary: WishdropImportSummary?
    @Published var defaultCountryCode: String
    private var lastObservedCheckAttempt: Date?

    init() {
        let defaults = UserDefaults.standard
        self.defaultCountryCode = defaults.string(forKey: DefaultsKey.defaultCountryCode) ?? SharedConstants.defaultCountryCode
        self.fetcher = AppStoreService()
        self.notificationScheduler = UserNotificationScheduler()

        do {
            let container = try SharedStore.makeContainer()
            self.container = container
            self.startupError = nil
            let store = AppDataStore(modelContainer: container)
            self.store = store
            let engine = RefreshEngine(
                container: container,
                fetcher: fetcher,
                notifier: notificationScheduler,
                lockURL: RefreshEngine.defaultLockURL(),
                logURL: RefreshEngine.defaultLogURL()
            )
            self.refresh = RefreshCoordinator(engine: engine) { [weak self] in
                self?.bumpDataVersion()
            }
        } catch {
            self.container = nil
            self.store = nil
            self.refresh = nil
            var message = error.localizedDescription
            if let storeError = error as? SharedStoreError {
                message = storeError.errorDescription ?? message
            }
            if let url = try? SharedStore.storeURL(createDirectory: false) {
                message += "\n\nStore: \(url.path)"
            }
            self.startupError = message
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.handleDidBecomeActive() }
        }

        Task { [weak self] in
            guard let self else { return }
            if let store = self.store {
                self.lastObservedCheckAttempt = try? await store.latestAttemptDate()
            }
            await self.reconcileStoredState()
        }
    }

    func bumpDataVersion() {
        dataVersion += 1
        if let store {
            Task { @MainActor [weak self] in
                self?.lastObservedCheckAttempt = try? await store.latestAttemptDate()
            }
        }
    }

    private func handleDidBecomeActive() async {
        backend.refreshStatus()
        guard let store else { return }
        if let latest = try? await store.latestAttemptDate(), latest != lastObservedCheckAttempt {
            lastObservedCheckAttempt = latest
            dataVersion += 1
            await reconcileStoredState()
        }
    }

    /// Repairs derived low-price flags written by older builds (a lone baseline
    /// observation used to be flagged as an all-time low). Skips while the
    /// background helper holds the refresh lock — that run reconciles itself.
    private func reconcileStoredState() async {
        guard let store else { return }
        var handle: FileLock.Handle?
        if let lockURL = RefreshEngine.defaultLockURL() {
            handle = try? FileLock(url: lockURL).acquire(.skipIfBusy)
            guard handle != nil else { return }
        }
        defer { handle?.release() }
        if let changed = try? await store.reconcilePriceState(), changed > 0 {
            bumpDataVersion()
        }
    }

    func setDefaultCountryCode(_ code: String) {
        defaultCountryCode = StoreCountry.normalized(code)
        UserDefaults.standard.set(defaultCountryCode, forKey: DefaultsKey.defaultCountryCode)
    }

    // MARK: - Refresh

    func refreshAll() async {
        await refresh?.refreshAll()
    }

    // MARK: - Tracked apps

    func addTrackedApp(searchResult: AppStoreApp, country: String) async -> AddTrackedAppOutcome {
        guard let store else {
            return .failed(message: startupError ?? "Store unavailable")
        }
        var result = searchResult
        if result.price == nil || result.currency == nil {
            // Some catalog entries (mostly Mac) omit the price in search
            // responses; ask the lookup endpoint before giving up.
            let lookup = try? await fetcher.lookupOne(appId: result.trackId, country: country)
            result = result.fillingMissingPrice(from: lookup)
        }
        let draft = NewTrackedAppDraft(
            trackId: result.trackId,
            countryCode: country,
            name: result.name,
            developerName: result.developerName,
            artworkURL: result.artworkURL,
            appStoreURL: result.appStoreURL,
            price: result.price,
            formattedPrice: result.formattedPrice
                ?? result.price.flatMap { price in result.currency.map { PriceFormatting.priceString(price, currency: $0) } },
            currency: result.currency
        )
        do {
            let snapshot = try await store.insert(draft, now: Date())
            bumpDataVersion()
            return .added(name: snapshot.name)
        } catch let error as AppDataStoreError {
            if case .duplicateTrackedApp = error {
                return .duplicate(name: result.name)
            }
            return .failed(message: error.localizedDescription)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    func addTrackedApp(parsedLink: ParsedAppStoreLink) async -> AddTrackedAppOutcome {
        do {
            guard let result = try await fetcher.lookupOne(appId: parsedLink.trackId, country: parsedLink.countryCode) else {
                return .failed(message: AppStrings.string("add.notFound"))
            }
            return await addTrackedApp(searchResult: result, country: parsedLink.countryCode)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    func delete(appID: UUID) async -> String? {
        guard let store else { return startupError }
        do {
            try await store.delete(appID: appID)
            bumpDataVersion()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func delete(appIDs: Set<UUID>) async -> String? {
        guard let store else { return startupError }
        do {
            try await store.delete(appIDs: appIDs)
            bumpDataVersion()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func changeRegion(appID: UUID, to country: String) async -> String? {
        guard let refresh else { return startupError }
        let result = await refresh.replaceRegion(appID: appID, country: country)
        switch result {
        case .replaced, .unchanged:
            return nil
        case .duplicate:
            return AppStrings.string("detail.changeRegion.duplicate")
        case .failed(let message):
            return message
        }
    }

    func changeAllAppsRegion(to country: String) async -> BulkRegionChangeResult {
        guard let refresh else {
            return BulkRegionChangeResult(
                targetCountry: country,
                failedCount: 1,
                failureMessages: [startupError ?? "Store unavailable"]
            )
        }
        let outcome = await refresh.replaceRegionForAll(to: country)
        if outcome.updatedCount > 0 {
            bumpDataVersion()
        }
        return outcome
    }

    // MARK: - Wishdrop

    func exportWishdropData() async -> Result<Data, AppExportError> {
        guard let store else { return .failure(AppExportError(message: startupError ?? "Store unavailable")) }
        do {
            let snapshots = try await store.allSnapshots()
            let preset = WishdropCodec.makePreset(title: "AppDrop Wishlist", snapshots: snapshots, exportedAt: Date())
            return .success(try WishdropCodec.encode(preset))
        } catch {
            return .failure(AppExportError(message: error.localizedDescription))
        }
    }

    func importWishdrop(data: Data, fileName: String) async -> WishdropImportSummary {
        do {
            let preset = try WishdropCodec.decode(data)
            let validation = WishdropCodec.validateEntries(preset)
            guard let store else {
                return WishdropImportSummary(
                    fileName: fileName,
                    addedCount: 0,
                    existingCount: 0,
                    invalidCount: 0,
                    issues: [],
                    errorMessage: startupError
                )
            }
            let outcome = try await store.importWishdrop(entries: validation.valid, now: Date())
            bumpDataVersion()
            return WishdropImportSummary(
                fileName: fileName,
                addedCount: outcome.addedKeys.count,
                existingCount: outcome.alreadyTrackedKeys.count,
                invalidCount: validation.issues.count,
                issues: validation.issues,
                errorMessage: nil
            )
        } catch {
            return WishdropImportSummary(
                fileName: fileName,
                addedCount: 0,
                existingCount: 0,
                invalidCount: 0,
                issues: [],
                errorMessage: error.localizedDescription
            )
        }
    }

    func handleIncomingFiles(_ urls: [URL]) {
        for url in urls.sorted(by: { $0.path < $1.path }) {
            guard url.pathExtension.lowercased() == SharedConstants.wishdropFileExtension else { continue }
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                AppLog.info("incoming wishdrop file: \(url.path) (\(data.count) bytes)")
                Task { @MainActor in
                    let summary = await importWishdrop(data: data, fileName: url.lastPathComponent)
                    pendingImportSummary = summary
                }
            } catch {
                AppLog.error("incoming file read failed: \(error.localizedDescription)")
                pendingImportSummary = WishdropImportSummary(
                    fileName: url.lastPathComponent,
                    addedCount: 0,
                    existingCount: 0,
                    invalidCount: 0,
                    issues: [],
                    errorMessage: error.localizedDescription
                )
            }
        }
    }
}
