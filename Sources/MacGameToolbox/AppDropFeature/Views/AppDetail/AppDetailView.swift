import SwiftData
import SwiftUI
import AppDropCore

struct AppDetailView: View {
    @ObservedObject var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let app: TrackedApp

    @State private var records: [PriceRecordSnapshot] = []
    @State private var recordsError: String?
    @State private var loadingRecords = true

    @State private var checkingNow = false
    @State private var alertMessage: String?
    @State private var confirmingDelete = false
    @State private var confirmingRegionChange = false


    init(app: TrackedApp, environment: AppEnvironment) {
        self.app = app
        self.environment = environment
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                statsGrid
                chartSection
                actionSection
            }
            .padding(20)
        }
        .navigationTitle(app.name)
        .task(id: "\(app.id).\(app.countryCode).\(environment.dataVersion)") {
            await loadRecords()
        }
        .alert(
            "AppDrop",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button(AppStrings.string("common.ok")) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog(
            AppStrings.string("detail.deleteConfirmTitle"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(AppStrings.string("detail.delete"), role: .destructive) {
                deleteApp()
            }
            Button(AppStrings.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(AppStrings.string("detail.deleteConfirmMessage"))
        }
        .sheet(isPresented: $confirmingRegionChange) {
            ChangeRegionView(currentCountryCode: app.countryCode) { code in
                changeRegion(to: code)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            TrackedAppIconView(artworkURL: app.artworkURL, size: 76)
            VStack(alignment: .leading, spacing: 6) {
                Text(app.name)
                    .font(.title2.weight(.semibold))
                if let developer = app.developerName, !developer.isEmpty {
                    Text(developer)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    RegionBadge(countryCode: app.countryCode)
                    if app.isAtHistoricalLow {
                        NewLowBadge()
                    }
                    Text(AppStrings.string(statusKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let urlString = app.appStoreURL ?? canonicalURLString,
                   let url = URL(string: urlString) {
                    Link(AppStrings.string("detail.openInStore"), destination: url)
                        .font(.caption)
                }
            }
            Spacer()
        }
    }

    private var canonicalURLString: String? {
        "https://apps.apple.com/\(app.countryCode)/app/id\(app.trackId)"
    }

    private var statusKey: String {
        switch app.lastCheckStatus {
        case .unknown: return "status.unknown"
        case .ok: return "status.ok"
        case .notFound: return "status.notFound"
        case .error: return "status.error"
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
            statCard(
                titleKey: "detail.currentPrice",
                value: app.formattedPrice ?? AppStrings.string("card.pendingPrice"),
                detail: app.currency
            )
            statCard(
                titleKey: "detail.lowestPrice",
                value: hasPriceComparison
                    ? app.lowestPrice.map { PriceFormatting.priceString($0, currency: app.currency ?? "") } ?? "—"
                    : "—",
                detail: hasPriceComparison
                    ? nil
                    : app.formattedPrice.map { AppStrings.format("detail.lowestNoComparisonFormat", $0) }
            )
            statCard(
                titleKey: "detail.lastChange",
                value: app.lastPriceChangeAt.map { RelativeTime.string(for: $0) } ?? "—",
                detail: app.isDiscounted && app.discountRate > 0
                    ? AppStrings.format("card.discountSinceLast", PriceFormatting.percentString(app.discountRate) + "%")
                    : nil
            )
            statCard(
                titleKey: "detail.lastCheck",
                value: app.lastCheckedAt.map { RelativeTime.string(for: $0) } ?? "—",
                detail: app.lastCheckError
            )
        }
    }

    private func statCard(titleKey: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(AppStrings.string(titleKey))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
                .lineLimit(1)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.string("detail.chart.title"))
                .font(.headline)
            if let recordsError {
                Label(recordsError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Button(AppStrings.string("detail.reloadHistory")) {
                    Task { await loadRecords() }
                }
            } else if loadingRecords {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                PriceHistoryChartView(
                    points: chartPoints,
                    lowest: hasPriceComparison ? lowestPoint : nil
                )
                .accessibilityIdentifier("appdrop.priceHistory")
                .accessibilityValue(String(chartPoints.count))
            }
        }
    }

    /// True once at least one higher price has been observed, i.e. the recorded
    /// minimum can be meaningfully called a low.
    private var hasPriceComparison: Bool {
        app.priceObservationCount >= 2
    }

    private var actionSection: some View {
        HStack(spacing: 10) {
            Button {
                checkNow()
            } label: {
                Label(AppStrings.string("detail.checkNow"), systemImage: "arrow.clockwise")
            }
            .disabled(checkingNow || environment.refresh?.isRefreshing == true)
            .accessibilityIdentifier("appdrop.checkNow")
            if checkingNow {
                ProgressView().controlSize(.small)
            }
            Button {
                confirmingRegionChange = true
            } label: {
                Label(AppStrings.string("detail.changeRegion"), systemImage: "globe")
            }
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label(AppStrings.string("detail.delete"), systemImage: "trash")
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    /// Only records in the app's current currency are plotted; earlier records
    /// in a different currency are excluded instead of mixed into one series.
    private var chartPoints: [PriceHistoryChartView.ChartPoint] {
        let currentCurrency = app.currency
        return records
            .filter { record in currentCurrency.map { record.currency.caseInsensitiveCompare($0) == .orderedSame } ?? true }
            .map { record in
                PriceHistoryChartView.ChartPoint(
                    id: record.id,
                    date: record.timestamp,
                    price: NSDecimalNumber(decimal: record.price).doubleValue,
                    formatted: record.formattedPrice
                )
            }
    }

    private var lowestPoint: PriceHistoryChartView.ChartPoint? {
        chartPoints.min { $0.price < $1.price }
    }

    @MainActor
    private func loadRecords() async {
        let trackId = app.trackId
        let country = app.countryCode
        guard let store = environment.store else {
            loadingRecords = false
            recordsError = AppStrings.string("startup.storageHint")
            return
        }
        do {
            let fetched = try await store.records(trackId: trackId, countryCode: country)
            guard !Task.isCancelled else { return }
            records = fetched
            recordsError = nil
        } catch {
            guard !Task.isCancelled else { return }
            recordsError = AppStrings.errorDescription(error)
        }
        loadingRecords = false
    }

    private func checkNow() {
        guard !checkingNow, let refresh = environment.refresh, !refresh.isRefreshing else { return }
        let appID = app.id
        let environment = environment
        checkingNow = true
        Task { @MainActor in
            let summary = await refresh.refreshSingle(appID: appID)
            checkingNow = false
            if let summary, summary.outcome == .failed || summary.outcome == .skipped {
                alertMessage = summary.message
            }
            environment.bumpDataVersion()
        }
    }

    private func changeRegion(to code: String) {
        let environment = environment
        let appID = app.id
        Task {
            if let error = await environment.changeRegion(appID: appID, to: code) {
                alertMessage = error
                environment.bumpDataVersion()
            } else {
                // The storefront swap deletes this record and creates a fresh
                // one with a new id, so this detail view no longer resolves.
                // Pop back to the list, which now shows the new entry.
                environment.bumpDataVersion()
                dismiss()
            }
        }
    }

    private func deleteApp() {
        let environment = environment
        let appID = app.id
        Task {
            if let error = await environment.delete(appID: appID) {
                alertMessage = error
            } else {
                environment.bumpDataVersion()
                dismiss()
            }
        }
    }
}
