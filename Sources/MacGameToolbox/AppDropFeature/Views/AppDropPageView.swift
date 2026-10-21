import AppDropCore
import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum AppDropPage: String, CaseIterable, Identifiable, Hashable {
    case wishlist
    case todayDrops
    case historicalLows
    case settings

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .wishlist: "sidebar.wishlist"
        case .todayDrops: "sidebar.todayDrops"
        case .historicalLows: "sidebar.historicalLows"
        case .settings: "settings.title"
        }
    }

    var systemImage: String {
        switch self {
        case .wishlist: "heart"
        case .todayDrops: "arrow.down.right.circle"
        case .historicalLows: "chart.line.downtrend.xyaxis"
        case .settings: "gearshape"
        }
    }
}

enum AppDropSortMode: String, CaseIterable, Identifiable {
    case name
    case lastChecked
    case discount

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .name: "sort.name"
        case .lastChecked: "sort.lastChecked"
        case .discount: "sort.discount"
        }
    }
}

enum AppDropLayoutMode: String, CaseIterable {
    case grid
    case list
}

struct AppDropPageView: View {
    let page: AppDropPage
    @EnvironmentObject private var environment: AppEnvironment

    @State private var searchText = ""
    @State private var regionFilter = ""
    @State private var sortMode = AppDropSortMode.name
    @State private var layoutMode = AppDropLayoutMode.grid
    @State private var showingAddSheet = false
    @State private var showingImporter = false
    @State private var exportDocument: WishdropDocument?
    @State private var showingExporter = false
    @State private var alertMessage: String?
    @State private var importInProgress = false
    @State private var isSelectMode = false
    @State private var selectedAppIDs = Set<UUID>()
    @State private var confirmingBatchDelete = false
    @State private var deletingSingleApp: TrackedApp?
    @State private var confirmingSingleDelete = false

    @Query(sort: [SortDescriptor(\TrackedApp.createdAt)])
    private var trackedApps: [TrackedApp]

    var body: some View {
        NavigationStack {
            Group {
                if page == .settings {
                    AppDropSettingsView()
                } else {
                    libraryContent
                }
            }
            .navigationTitle(AppStrings.string(page.titleKey))
            .navigationDestination(for: UUID.self) { appID in
                if let app = trackedApps.first(where: { $0.id == appID }) {
                    AppDetailView(app: app)
                } else {
                    ContentUnavailableView(
                        AppStrings.string("empty.wishlist.title"),
                        systemImage: "app.dashed"
                    )
                }
            }
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingAddSheet) {
            AddAppView()
        }
        .sheet(item: $environment.pendingImportSummary) { summary in
            ImportSummaryView(summary: summary) {
                environment.pendingImportSummary = nil
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.wishdrop]
        ) { result in
            handleImportResult(result)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .wishdrop,
            defaultFilename: AppStrings.string("export.fileName")
        ) { result in
            if case .failure(let error) = result {
                alertMessage = AppStrings.format("export.errorFormat", error.localizedDescription)
            }
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
        .overlay(alignment: .bottom) {
            if importInProgress {
                Text(AppStrings.string("import.inProgress"))
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
        .confirmationDialog(
            AppStrings.string("batchDelete.confirmTitle"),
            isPresented: $confirmingBatchDelete,
            titleVisibility: .visible
        ) {
            Button(
                AppStrings.format("batchDelete.confirmAction", selectedAppIDs.count),
                role: .destructive
            ) {
                deleteSelectedApps()
            }
            Button(AppStrings.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(AppStrings.format("batchDelete.confirmMessage", selectedAppIDs.count))
        }
        .confirmationDialog(
            AppStrings.string("detail.deleteConfirmTitle"),
            isPresented: $confirmingSingleDelete,
            titleVisibility: .visible
        ) {
            Button(AppStrings.string("detail.delete"), role: .destructive) {
                if let deletingSingleApp {
                    deleteApp(deletingSingleApp.id)
                }
            }
            Button(AppStrings.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(AppStrings.string("detail.deleteConfirmMessage"))
        }
        .onChange(of: page) { _, _ in
            isSelectMode = false
            selectedAppIDs.removeAll()
        }
    }

    private var libraryContent: some View {
        VStack(spacing: 0) {
            filterBar
            if isSelectMode {
                selectionBanner
            }
            if filteredApps.isEmpty {
                emptyState
            } else {
                switch layoutMode {
                case .grid:
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 250), spacing: 14)],
                            spacing: 14
                        ) {
                            ForEach(filteredApps) { app in
                                if isSelectMode {
                                    Button {
                                        toggleSelection(app.id)
                                    } label: {
                                        TrackedAppCardView(
                                            app: app,
                                            isSelectMode: true,
                                            isSelected: selectedAppIDs.contains(app.id)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    NavigationLink(value: app.id) {
                                        TrackedAppCardView(app: app)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        appContextMenu(for: app)
                                    }
                                }
                            }
                        }
                        .padding(18)
                    }
                case .list:
                    List {
                        ForEach(filteredApps) { app in
                            if isSelectMode {
                                Button {
                                    toggleSelection(app.id)
                                } label: {
                                    TrackedAppRowView(
                                        app: app,
                                        isSelectMode: true,
                                        isSelected: selectedAppIDs.contains(app.id)
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink(value: app.id) {
                                    TrackedAppRowView(app: app)
                                }
                                .contextMenu {
                                    appContextMenu(for: app)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            TextField(AppStrings.string("toolbar.search"), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160, maxWidth: 320)
            Spacer(minLength: 4)
            Picker(AppStrings.string("toolbar.sort"), selection: $sortMode) {
                ForEach(AppDropSortMode.allCases) { mode in
                    Text(AppStrings.string(mode.titleKey)).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 145)
            Picker(AppStrings.string("toolbar.region"), selection: $regionFilter) {
                Text(AppStrings.string("filter.allRegions")).tag("")
                ForEach(SharedConstants.supportedCountryCodes, id: \.self) { code in
                    Text(AppStrings.regionLabel(code)).tag(code)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 165)
            Picker(AppStrings.string("toolbar.layout"), selection: $layoutMode) {
                Image(systemName: "square.grid.2x2").tag(AppDropLayoutMode.grid)
                Image(systemName: "list.bullet").tag(AppDropLayoutMode.list)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 78)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: emptyStateIcon)
                    .font(.system(size: 42))
                    .foregroundStyle(.tertiary)
                Text(AppStrings.string(emptyTitleKey))
                    .font(.title2.weight(.semibold))
                Text(AppStrings.string(emptyMessageKey))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                if page == .wishlist {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label(AppStrings.string("toolbar.add"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    AppDropQuickSetupCard()
                        .frame(maxWidth: 520)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 440)
            .padding(28)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if page != .settings {
            ToolbarItemGroup {
                if !filteredApps.isEmpty {
                    Button {
                        isSelectMode.toggle()
                        if !isSelectMode {
                            selectedAppIDs.removeAll()
                        }
                    } label: {
                        Label(
                            AppStrings.string(isSelectMode ? "common.done" : "toolbar.select"),
                            systemImage: isSelectMode ? "checkmark" : "checklist"
                        )
                    }
                }
                Button {
                    showingAddSheet = true
                } label: {
                    Label(AppStrings.string("toolbar.add"), systemImage: "plus")
                }
                Button {
                    showingImporter = true
                } label: {
                    Label(AppStrings.string("toolbar.import"), systemImage: "square.and.arrow.down")
                }
                Button {
                    exportWishlist()
                } label: {
                    Label(AppStrings.string("toolbar.export"), systemImage: "square.and.arrow.up")
                }
                Button {
                    Task { await environment.refreshAll() }
                } label: {
                    Label(AppStrings.string("toolbar.refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(environment.refresh?.isRefreshing == true)
                if environment.refresh?.isRefreshing == true {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private var emptyStateIcon: String {
        switch page {
        case .wishlist: "heart"
        case .todayDrops: "arrow.down.right.circle"
        case .historicalLows: "chart.line.downtrend.xyaxis"
        case .settings: "gearshape"
        }
    }

    private var emptyTitleKey: String {
        switch page {
        case .wishlist: "empty.wishlist.title"
        case .todayDrops: "empty.todayDrops.title"
        case .historicalLows: "empty.lows.title"
        case .settings: "settings.title"
        }
    }

    private var emptyMessageKey: String {
        switch page {
        case .wishlist: "empty.wishlist.message"
        case .todayDrops: "empty.todayDrops.message"
        case .historicalLows: "empty.lows.message"
        case .settings: "settings.defaultRegionCaption"
        }
    }

    private var selectionBanner: some View {
        HStack(spacing: 12) {
            Button {
                if selectedAppIDs.count == filteredApps.count {
                    selectedAppIDs.removeAll()
                } else {
                    selectedAppIDs = Set(filteredApps.map(\.id))
                }
            } label: {
                Label(
                    AppStrings.string(
                        selectedAppIDs.count == filteredApps.count
                            ? "toolbar.deselectAll"
                            : "toolbar.selectAll"
                    ),
                    systemImage: selectedAppIDs.count == filteredApps.count
                        ? "xmark.circle"
                        : "checkmark.circle"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Text(AppStrings.format("toolbar.selectedCount", selectedAppIDs.count))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
                confirmingBatchDelete = true
            } label: {
                Label(AppStrings.string("toolbar.deleteSelected"), systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
            .disabled(selectedAppIDs.isEmpty)
            Button(AppStrings.string("common.done")) {
                isSelectMode = false
                selectedAppIDs.removeAll()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var filteredApps: [TrackedApp] {
        var apps = trackedApps
        switch page {
        case .todayDrops:
            apps = apps.filter { app in
                guard let lastDecrease = app.lastDecreaseAt else { return false }
                return Calendar.current.isDateInToday(lastDecrease)
            }
        case .historicalLows:
            apps = apps.filter(\.isAtHistoricalLow)
        case .wishlist, .settings:
            break
        }
        if !regionFilter.isEmpty {
            apps = apps.filter { $0.countryCode == regionFilter }
        }
        if !searchText.isEmpty {
            apps = apps.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.trackId.contains(searchText)
                    || StoreCountry.displayCode(for: $0.countryCode)
                        .localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortMode {
        case .name:
            apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .lastChecked:
            apps.sort { ($0.lastCheckedAt ?? .distantPast) > ($1.lastCheckedAt ?? .distantPast) }
        case .discount:
            apps.sort { $0.discountRate > $1.discountRate }
        }
        return apps
    }

    private func exportWishlist() {
        Task {
            switch await environment.exportWishdropData() {
            case .success(let data):
                exportDocument = WishdropDocument(data: data)
                showingExporter = true
            case .failure(let error):
                alertMessage = AppStrings.format("export.errorFormat", error.localizedDescription)
            }
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                importInProgress = true
                Task {
                    environment.pendingImportSummary = await environment.importWishdrop(
                        data: data,
                        fileName: url.lastPathComponent
                    )
                    importInProgress = false
                }
            } catch {
                environment.pendingImportSummary = WishdropImportSummary(
                    fileName: url.lastPathComponent,
                    addedCount: 0,
                    existingCount: 0,
                    invalidCount: 0,
                    issues: [],
                    errorMessage: error.localizedDescription
                )
            }
        case .failure(let error):
            environment.pendingImportSummary = WishdropImportSummary(
                fileName: "",
                addedCount: 0,
                existingCount: 0,
                invalidCount: 0,
                issues: [],
                errorMessage: error.localizedDescription
            )
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedAppIDs.contains(id) {
            selectedAppIDs.remove(id)
        } else {
            selectedAppIDs.insert(id)
        }
    }

    @ViewBuilder
    private func appContextMenu(for app: TrackedApp) -> some View {
        if let urlString = app.appStoreURL ?? canonicalURLString(for: app),
           let url = URL(string: urlString) {
            Link(AppStrings.string("contextMenu.openInStore"), destination: url)
            Button(AppStrings.string("contextMenu.copyLink")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }
        Divider()
        Button(role: .destructive) {
            deletingSingleApp = app
            confirmingSingleDelete = true
        } label: {
            Label(AppStrings.string("contextMenu.delete"), systemImage: "trash")
        }
    }

    private func canonicalURLString(for app: TrackedApp) -> String? {
        "https://apps.apple.com/\(app.countryCode)/app/id\(app.trackId)"
    }

    private func deleteSelectedApps() {
        let toDelete = selectedAppIDs
        Task {
            if let error = await environment.delete(appIDs: toDelete) {
                alertMessage = error
            } else {
                selectedAppIDs.removeAll()
                isSelectMode = false
            }
        }
    }

    private func deleteApp(_ appID: UUID) {
        Task {
            if let error = await environment.delete(appID: appID) {
                alertMessage = error
            }
        }
    }
}

private struct AppDropQuickSetupCard: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(AppStrings.string("settings.defaultRegion"), systemImage: "globe")
                .font(.headline)
            Picker("", selection: Binding(
                get: { environment.defaultCountryCode },
                set: { environment.setDefaultCountryCode($0) }
            )) {
                ForEach(SharedConstants.supportedCountryCodes, id: \.self) { code in
                    Text(AppStrings.regionLabel(code)).tag(code)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Text(AppStrings.string("settings.helperPermissionHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.secondary.opacity(0.15))
        )
    }
}
