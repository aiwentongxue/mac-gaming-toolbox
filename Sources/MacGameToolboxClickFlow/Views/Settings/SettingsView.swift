import SwiftUI

struct ClickFlowSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section(cf("settings.permissions")) {
                LabeledContent(cf("settings.accessibility")) {
                    permissionRow(
                        granted: appState.permissionManager.canPostEvents,
                        request: appState.permissionManager.requestEventPostingAccess,
                        openSettings: appState.permissionManager.openAccessibilitySettings
                    )
                }
                LabeledContent(cf("settings.inputMonitoring")) {
                    permissionRow(
                        granted: appState.permissionManager.canListenToEvents,
                        request: appState.permissionManager.requestEventListeningAccess,
                        openSettings: appState.permissionManager.openInputMonitoringSettings
                    )
                }
                Text(cf("permission.inputMonitoring.restartHint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(cf("permission.refresh")) {
                    appState.permissionManager.refresh()
                }
            }
            Section(cf("settings.hotkeys")) {
                HotkeySettingsView()
            }
        }
        .formStyle(.grouped)
        .onAppear { appState.permissionManager.refresh() }
    }

    @ViewBuilder
    private func permissionRow(
        granted: Bool,
        request: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(cf(granted ? "permission.granted" : "permission.notGranted"))
                .foregroundStyle(granted ? .green : .secondary)
            if !granted {
                Button(cf("permission.request"), action: request)
                Button(cf("permission.openSettings"), action: openSettings)
            }
        }
    }
}
