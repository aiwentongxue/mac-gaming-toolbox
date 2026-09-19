import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class CrossOverGameSetupViewModel: ObservableObject {
    @Published var applications: [CrossOverApplication] = []
    @Published var bottles: [ClickFlowCrossOverBottle] = []
    @Published var selectedApplicationID: String?
    @Published var selectedBottleID: String?
    @Published var gameURL: URL?
    @Published var preset: CrossOverGamePreset = .automatic
    @Published var report: CrossOverDiagnosticReport?
    @Published var isBusy = false
    @Published var statusMessage: String?

    private let service: CrossOverGameIntegrationService

    init(service: CrossOverGameIntegrationService = CrossOverGameIntegrationService()) {
        self.service = service
    }

    var selectedApplication: CrossOverApplication? {
        applications.first { $0.id == selectedApplicationID }
    }

    var selectedBottle: ClickFlowCrossOverBottle? {
        bottles.first { $0.id == selectedBottleID }
    }

    var installedManifest: CrossOverIntegrationManifest? {
        report?.installedManifest.flatMap { $0.state == .installed ? $0 : nil }
    }

    var antiCheatFiles: [String] { report?.plan?.antiCheatFiles ?? [] }

    func load() async {
        isBusy = true
        let environment = await service.discoverEnvironment()
        applications = environment.applications
        bottles = environment.bottles
        if selectedApplicationID == nil { selectedApplicationID = applications.first?.id }
        if selectedBottleID == nil { selectedBottleID = bottles.first?.id }
        isBusy = false
    }

    func selectGame(_ url: URL) async {
        gameURL = url.standardizedFileURL
        preset = CrossOverGamePreset.knownPreset(for: url.lastPathComponent) ?? .automatic
        autoSelectBottleAndApplication()
        await diagnose()
    }

    func diagnose() async {
        isBusy = true
        report = await service.diagnose(
            gameURL: gameURL,
            bottle: selectedBottle,
            application: selectedApplication,
            preset: preset
        )
        isBusy = false
    }

    func install() async {
        guard let gameURL, let bottle = selectedBottle, let application = selectedApplication else {
            statusMessage = cf("windowsGames.error.incompleteSelection")
            return
        }
        isBusy = true
        do {
            _ = try await service.install(
                gameURL: gameURL,
                bottle: bottle,
                application: application,
                preset: preset
            )
            statusMessage = cf("windowsGames.install.success")
        } catch {
            statusMessage = error.localizedDescription
        }
        report = await service.diagnose(
            gameURL: gameURL,
            bottle: bottle,
            application: application,
            preset: preset
        )
        isBusy = false
    }

    func restore() async {
        guard let manifest = installedManifest else { return }
        isBusy = true
        do {
            try await service.restore(manifest: manifest)
            statusMessage = cf("windowsGames.restore.success")
        } catch {
            statusMessage = error.localizedDescription
        }
        report = await service.diagnose(
            gameURL: gameURL,
            bottle: selectedBottle,
            application: selectedApplication,
            preset: preset
        )
        isBusy = false
    }

    func refreshEnvironment() async {
        let existingApplication = selectedApplicationID
        let existingBottle = selectedBottleID
        await load()
        if applications.contains(where: { $0.id == existingApplication }) {
            selectedApplicationID = existingApplication
        }
        if bottles.contains(where: { $0.id == existingBottle }) {
            selectedBottleID = existingBottle
        }
        autoSelectBottleAndApplication()
        await diagnose()
    }

    func copyReport() {
        guard let report else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.plainText, forType: .string)
        statusMessage = cf("windowsGames.diagnostics.copied")
    }

    private func autoSelectBottleAndApplication() {
        guard let gameURL else { return }
        let preset = CrossOverGamePreset.knownPreset(for: gameURL.lastPathComponent)
        let preferredBottleName: String?
        switch preset {
        case .aniimo: preferredBottleName = "aniimo"
        case .genshinImpact: preferredBottleName = "yuanshen"
        case .zenlessZoneZero: preferredBottleName = "zzz"
        case .automatic, .genericXInput, .none: preferredBottleName = nil
        }
        if let preferredBottleName,
           let bottle = bottles.first(where: { $0.name.caseInsensitiveCompare(preferredBottleName) == .orderedSame }) {
            selectedBottleID = bottle.id
        }
        if let preferredApplicationName = preset?.preferredCrossOverDisplayName,
           let application = applications.first(where: {
               $0.displayName.caseInsensitiveCompare(preferredApplicationName) == .orderedSame
           }) {
            selectedApplicationID = application.id
            return
        }
        guard let bottle = selectedBottle else { return }
        let bottleMajorMinor = bottle.version.split(separator: ".").prefix(2).joined(separator: ".")
        if let exact = applications.first(where: { $0.version.hasPrefix(bottleMajorMinor) }) {
            selectedApplicationID = exact.id
        }
    }
}

struct CrossOverGameSetupView: View {
    @StateObject private var model = CrossOverGameSetupViewModel()
    @State private var isChoosingGame = false
    @State private var showInstallConfirmation = false
    @State private var showRestoreConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                introduction
                configuration
                actions
                diagnostics
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .task { await model.load() }
        .fileImporter(
            isPresented: $isChoosingGame,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            guard url.pathExtension.lowercased() == "exe" else {
                model.statusMessage = cf("windowsGames.error.chooseExecutable")
                return
            }
            Task { await model.selectGame(url) }
        }
        .alert(cf("app.message.title"), isPresented: statusBinding) {
            Button(cf("common.ok")) { model.statusMessage = nil }
        } message: {
            Text(model.statusMessage ?? "")
        }
        .confirmationDialog(
            cf("windowsGames.install.confirm.title"),
            isPresented: $showInstallConfirmation,
            titleVisibility: .visible
        ) {
            Button(cf("windowsGames.install.action")) { Task { await model.install() } }
            Button(cf("common.cancel"), role: .cancel) {}
        } message: {
            Text(installConfirmationMessage)
        }
        .confirmationDialog(
            cf("windowsGames.restore.confirm.title"),
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button(cf("windowsGames.restore.action"), role: .destructive) { Task { await model.restore() } }
            Button(cf("common.cancel"), role: .cancel) {}
        } message: {
            Text(cf("windowsGames.restore.confirm.message"))
        }
    }

    private var introduction: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(cf("windowsGames.title"), systemImage: "gamecontroller.fill")
                    .font(.title2.bold())
                Text(cf("windowsGames.explanation"))
                    .foregroundStyle(.secondary)
                Label(cf("windowsGames.notVirtualHID"), systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Label(cf("windowsGames.antiCheatWarning"), systemImage: "exclamationmark.shield")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var configuration: some View {
        GroupBox(cf("windowsGames.configuration")) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text(cf("windowsGames.game"))
                    HStack {
                        Text(model.gameURL?.path ?? cf("windowsGames.game.none"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(model.gameURL == nil ? .secondary : .primary)
                        Spacer()
                        Button(cf("windowsGames.game.choose")) { isChoosingGame = true }
                    }
                }
                Divider().gridCellColumns(2)
                GridRow {
                    Text(cf("windowsGames.bottle"))
                    Picker(cf("windowsGames.bottle"), selection: $model.selectedBottleID) {
                        Text(cf("windowsGames.selection.none")).tag(String?.none)
                        ForEach(model.bottles) { bottle in
                            Text("\(bottle.name) · \(bottle.version)").tag(Optional(bottle.id))
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text(cf("windowsGames.crossOver"))
                    Picker(cf("windowsGames.crossOver"), selection: $model.selectedApplicationID) {
                        Text(cf("windowsGames.selection.none")).tag(String?.none)
                        ForEach(model.applications) { application in
                            Text("\(application.displayName) · \(application.version)")
                                .tag(Optional(application.id))
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text(cf("windowsGames.profile"))
                    Picker(cf("windowsGames.profile"), selection: $model.preset) {
                        ForEach(CrossOverGamePreset.allCases) { preset in
                            Text(cf(preset.localizedKey)).tag(preset)
                        }
                    }
                    .labelsHidden()
                }
            }
            .padding(.top, 6)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.refreshEnvironment() }
            } label: {
                Label(cf("windowsGames.refresh"), systemImage: "arrow.clockwise")
            }
            Button {
                Task { await model.diagnose() }
            } label: {
                Label(cf("windowsGames.diagnose"), systemImage: "stethoscope")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.gameURL == nil || model.isBusy)

            Spacer()

            if model.installedManifest != nil {
                Button(role: .destructive) { showRestoreConfirmation = true } label: {
                    Label(cf("windowsGames.restore.action"), systemImage: "arrow.uturn.backward.circle")
                }
                .disabled(model.isBusy)
            } else {
                Button { showInstallConfirmation = true } label: {
                    Label(cf("windowsGames.install.action"), systemImage: "shippingbox.and.arrow.backward")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.gameURL == nil || model.selectedBottle == nil || model.selectedApplication == nil || model.isBusy)
            }
            if model.isBusy { ProgressView().controlSize(.small) }
        }
    }

    @ViewBuilder
    private var diagnostics: some View {
        if let report = model.report {
            GroupBox(cf("windowsGames.diagnostics")) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(report.items) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.severity.systemImage)
                                .foregroundStyle(item.severity.color)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).fontWeight(.medium)
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        if item.id != report.items.last?.id { Divider() }
                    }
                    HStack {
                        Spacer()
                        Button(cf("windowsGames.diagnostics.copy")) { model.copyReport() }
                    }
                    .padding(.top, 10)
                }
            }
        } else {
            ContentUnavailableView(
                cf("windowsGames.diagnostics.empty.title"),
                systemImage: "stethoscope",
                description: Text(cf("windowsGames.diagnostics.empty.message"))
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        }
    }

    private var statusBinding: Binding<Bool> {
        Binding(
            get: { model.statusMessage != nil },
            set: { if !$0 { model.statusMessage = nil } }
        )
    }

    private var installConfirmationMessage: String {
        if model.antiCheatFiles.isEmpty {
            return cf("windowsGames.install.confirm.message")
        }
        return cf(
            "windowsGames.install.confirm.antiCheat %@",
            model.antiCheatFiles.joined(separator: ", ")
        )
    }
}

private extension CrossOverGamePreset {
    var localizedKey: String {
        switch self {
        case .automatic: "windowsGames.profile.automatic"
        case .genericXInput: "windowsGames.profile.generic"
        case .aniimo: "windowsGames.profile.aniimo"
        case .genshinImpact: "windowsGames.profile.genshin"
        case .zenlessZoneZero: "windowsGames.profile.zzz"
        }
    }
}

private extension CrossOverDiagnosticSeverity {
    var systemImage: String {
        switch self {
        case .passed: "checkmark.circle.fill"
        case .information: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .passed: .green
        case .information: .blue
        case .warning: .orange
        case .failed: .red
        }
    }
}
