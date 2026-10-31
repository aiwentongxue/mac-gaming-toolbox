import Foundation
import AppDropCore

/// Drives manual refreshes and publishes their state for the UI.
@MainActor
final class RefreshCoordinator: ObservableObject {
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastSummary: RefreshSummary?
    @Published private(set) var lastErrorMessage: String?

    private let engine: RefreshEngine?
    private let didFinish: () -> Void

    init(engine: RefreshEngine?, didFinish: @escaping () -> Void) {
        self.engine = engine
        self.didFinish = didFinish
    }

    func refreshAll() async {
        guard let engine, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let summary = await engine.run(source: .manual, mode: .wait(timeout: 20), force: true)
        lastSummary = summary
        lastErrorMessage = summary.outcome == .failed ? summary.message : nil
        didFinish()
    }

    @discardableResult
    func refreshSingle(appID: UUID) async -> RefreshSummary? {
        guard let engine, !isRefreshing else { return nil }
        isRefreshing = true
        defer { isRefreshing = false }
        let summary = await engine.refreshSingle(appID: appID, source: .manual)
        lastSummary = summary
        didFinish()
        return summary
    }

    func replaceRegion(appID: UUID, country: String) async -> RegionReplaceResult {
        guard let engine else {
            return .failed(message: "Store unavailable")
        }
        let result = await engine.replaceRegion(appID: appID, newCountryCode: country)
        didFinish()
        return result
    }

    func replaceRegionForAll(to country: String) async -> BulkRegionChangeResult {
        guard let engine else {
            return BulkRegionChangeResult(
                targetCountry: country,
                failedCount: 1,
                failureMessages: ["Store unavailable"]
            )
        }
        let result = await engine.replaceRegionForAll(to: country)
        didFinish()
        return result
    }
}
