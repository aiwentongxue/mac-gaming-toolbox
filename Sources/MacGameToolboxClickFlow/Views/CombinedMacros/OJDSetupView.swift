import AppKit
import SwiftUI

@MainActor
final class OJDSetupModel: ObservableObject {
    @Published var busy = false
    @Published var message = ""
    @Published var connected = false
    @Published var permissions = OJDPermissionStatus.unknown
    @Published var sources: [ControllerSourceChoice] = []
    @Published var selectedSourceID = ""
    @Published var externalServicePaths: [String] = []
    @Published var legacyAvailable = false
    @Published var inputConfirmed = false
    var canSwitchLegacy: Bool {
        legacyAvailable && !externalServicePaths.isEmpty && externalServicePaths.allSatisfy {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath() == OJDPaths.current.executable(in: OJDPaths.current.legacyAppURL).resolvingSymlinksInPath()
        }
    }
    private let output: ControllerOutputRouter

    init(output: ControllerOutputRouter) { self.output = output }

    func refreshSources() {
        connected = output.isOJDConnected
        if !connected, output.hasOJDFeed, !busy {
            busy = true
            let output = output
            Task {
                await Task.detached { output.disconnectOJD() }.value
                message = cf("ojd.error.disconnected")
                busy = false
                refreshSources()
            }
            return
        }
        let registry = ControllerDeviceRegistry.shared
        sources = registry.physicalControllers().enumerated().map {
            ControllerSourceChoice(id: registry.identifier($0.element), name: "\($0.element.vendorName ?? "Controller") #\($0.offset + 1)")
        }
        let selected = registry.selectedController(preferredName: nil)
        selectedSourceID = selected.map(registry.identifier) ?? ""
    }
    func selectSource(_ id: String) {
        ControllerDeviceRegistry.shared.select(id: id.isEmpty ? nil : id)
        selectedSourceID = id
    }
    func install() async {
        guard !busy else { return }
        busy = true; message = cf("ojd.installing")
        do {
            let result = try await Task.detached { try await OJDService().install() }.value
            message = cf(result == .migrated ? "ojd.migrated" : "ojd.installed")
        } catch { message = error.localizedDescription }
        busy = false; refreshSources(); await refreshComponentState(); await refreshPermissions()
    }
    func inspect() async {
        guard !busy else { return }
        busy = true
        do {
            let permissions = try await Task.detached {
                let service = OJDService()
                try service.verify()
                return try OJDPermissionStatus.decodeStatus(service.status())
            }.value
            self.permissions = permissions
            message = cf("ojd.verified")
        } catch { message = error.localizedDescription }
        busy = false; refreshSources(); await refreshComponentState(); await refreshPermissions()
    }
    func connect() async {
        guard !busy else { return }
        busy = true; message = cf("ojd.connecting")
        do {
            let output = output
            try await Task.detached { try output.connectOJD() }.value
            message = cf("ojd.connected")
        } catch { message = error.localizedDescription }
        busy = false; refreshSources(); await refreshComponentState(); await refreshPermissions()
    }
    func openComponent() async {
        do {
            try await Task.detached {
                let service = OJDService()
                try service.verify(); try service.requireNoExternalService()
            }.value
            NSWorkspace.shared.open(OJDService.appURL)
        } catch { message = error.localizedDescription }
    }

    func refreshComponentState() async {
        guard !busy else { return }
        legacyAvailable = FileManager.default.fileExists(atPath: OJDPaths.current.legacyAppURL.path)
        do {
            externalServicePaths = try await Task.detached { try OJDService().externalInstances().map { $0.executableURL.path } }.value
        } catch { message = error.localizedDescription }
    }

    func switchService() async {
        guard !busy else { return }
        busy = true; message = cf("ojd.switching")
        let output = output
        do {
            try await Task.detached {
                output.disconnectOJD()
                try OJDService().switchService(confirmed: true)
            }.value
            message = cf("ojd.switched")
        } catch { message = error.localizedDescription }
        busy = false; refreshSources(); await refreshComponentState(); await refreshPermissions()
    }

    func trashLegacy() async {
        guard !busy, connected, inputConfirmed else { return }
        busy = true
        do {
            try await Task.detached { try OJDService().trashLegacy(inputConfirmed: true) }.value
            message = cf("ojd.legacyTrashed")
            inputConfirmed = false
        } catch { message = cf("ojd.legacyTrashFailed") + "\n" + error.localizedDescription }
        busy = false; await refreshComponentState()
    }

    func refreshPermissions() async {
        guard !busy else { return }
        do {
            permissions = try await Task.detached {
                try OJDPermissionStatus.decodeStatus(OJDService().status())
            }.value
        } catch { permissions = .unknown }
    }

    func disconnect() async {
        guard !busy else { return }
        busy = true
        let output = output
        await Task.detached { output.disconnectOJD() }.value
        message = cf("ojd.disconnected")
        busy = false; refreshSources(); await refreshComponentState(); await refreshPermissions()
    }
}

struct ControllerSourceChoice: Identifiable { var id: String; var name: String }

struct OJDSetupView: View {
    @ObservedObject var model: OJDSetupModel
    @ObservedObject var appState: AppState
    @State private var confirmingSwitch = false
    private var activityRunning: Bool { appState.isPlayingCombinedMacro || appState.isRecordingCombinedMacro }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(cf("ojd.title"), systemImage: "gamecontroller.fill").font(.title2.bold())
                        Text(cf("controller.backend.ojd.description"))
                        Text(cf("ojd.instructions")).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox(cf("ojd.location")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(OJDService.appURL.path).font(.callout).textSelection(.enabled)
                        HStack {
                            Button(cf("ojd.permissions.copyPath")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(OJDService.appURL.path, forType: .string)
                            }
                            Button(cf("ojd.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([OJDService.appURL]) }
                        }
                        if !model.externalServicePaths.isEmpty {
                            Text(cf("ojd.switchNeeded")).foregroundStyle(.orange)
                            ForEach(model.externalServicePaths, id: \.self) { Text($0).font(.footnote).textSelection(.enabled) }
                            if model.canSwitchLegacy {
                                Button(cf("ojd.switch")) { confirmingSwitch = true }
                            } else {
                                Text(cf("ojd.error.otherService")).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        if model.legacyAvailable {
                            Text(cf("ojd.legacyHelp")).font(.footnote).foregroundStyle(.secondary)
                            Toggle(cf("ojd.confirmInput"), isOn: $model.inputConfirmed)
                            Button(cf("ojd.trashLegacy")) { Task { await model.trashLegacy() } }
                                .disabled(!model.connected || !model.inputConfirmed || !model.externalServicePaths.isEmpty)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }.disabled(model.busy || activityRunning)
                GroupBox(cf("ojd.source")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(cf("ojd.source"), selection: Binding(get: { model.selectedSourceID }, set: model.selectSource)) {
                            Text(cf("ojd.source.none")).tag("")
                            ForEach(model.sources) { Text($0.name).tag($0.id) }
                        }
                        Text(cf("ojd.source.help")).font(.footnote).foregroundStyle(.secondary)
                        Button(cf("ojd.refreshSources")) { model.refreshSources() }
                    }.padding(6)
                }.disabled(model.busy || activityRunning || model.connected)
                HStack {
                    Button(cf("ojd.install")) { Task { await model.install() } }
                    Button(cf("ojd.check")) { Task { await model.inspect() } }
                    Spacer()
                    if model.connected {
                        Button(cf("ojd.disconnect")) { Task { await model.disconnect() } }
                    } else {
                        Button(cf("ojd.connect")) { Task { await model.connect() } }.buttonStyle(.borderedProminent)
                    }
                    if model.busy { ProgressView().controlSize(.small) }
                }.disabled(model.busy || activityRunning)
                GroupBox(cf("ojd.permissions.title")) {
                    VStack(alignment: .leading, spacing: 10) {
                        permissionRow(cf("ojd.permissions.input"), state: model.permissions.inputRead) {
                            appState.permissionManager.openInputMonitoringSettings()
                        }
                        permissionRow(cf("ojd.permissions.inject"), state: model.permissions.inputInject) {
                            appState.permissionManager.openAccessibilitySettings()
                        }
                        Text(String(format: cf("ojd.permissions.help"), OJDService.appURL.path)).font(.footnote).foregroundStyle(.secondary)
                        HStack {
                            Button(cf("ojd.permissions.copyPath")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(OJDService.appURL.path, forType: .string)
                            }
                            Button(cf("ojd.permissions.open")) { Task { await model.openComponent() } }
                            Button(cf("ojd.permissions.recheck")) { Task { await model.refreshPermissions() } }
                        }
                    }.padding(6)
                }.disabled(model.busy || activityRunning)
                Label(cf(model.connected ? "ojd.feed.active" : "ojd.feed.inactive"), systemImage: model.connected ? "checkmark.circle" : "circle")
                if !model.message.isEmpty {
                    Text(model.message).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                Text(cf("ojd.dependency")).font(.footnote).foregroundStyle(.secondary)
                Link(cf("ojd.website"), destination: URL(string: "https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.6.0-alpha.1")!)
            }.padding(24).frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle(cf("ojd.title"))
        .alert(cf("ojd.switch"), isPresented: $confirmingSwitch) {
            Button(cf("common.cancel"), role: .cancel) {}
            Button(cf("ojd.switch")) { Task { await model.switchService() } }
        } message: { Text(cf("ojd.switchConfirm")) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refreshComponentState(); await model.refreshPermissions() }
        }
        .task {
            model.refreshSources()
            await model.refreshComponentState()
            await model.refreshPermissions()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { model.refreshSources() }
            }
        }
    }
    private func permissionRow(_ key: String, state: String, open: @escaping () -> Void) -> some View {
        HStack {
            Label(key, systemImage: state == "Granted" ? "checkmark.circle.fill" : "circle")
            Spacer()
            Text(cf(state == "Granted" ? "ojd.permissions.granted" : "ojd.permissions.unknown"))
                .foregroundStyle(.secondary)
            Button(cf("ojd.permissions.settings"), action: open)
        }
    }

}
