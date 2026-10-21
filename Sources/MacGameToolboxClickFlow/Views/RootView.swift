import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: selectedPageBinding)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            Group {
                switch appState.selectedPage {
                case .clicker:
                    AutoClickerView()
                case .macros:
                    MacroListView()
                case .combinedMacros:
                    CombinedMacroListView()
                case .settings:
                    ClickFlowSettingsView()
                }
            }
            .frame(minWidth: 620, minHeight: 480)
        }
        .alert(cf("app.message.title"), isPresented: messageBinding) {
            Button(cf("common.ok")) { appState.userMessage = nil }
        } message: {
            Text(appState.userMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.permissionManager.refresh()
        }
    }

    private var messageBinding: Binding<Bool> {
        Binding(
            get: { appState.userMessage != nil },
            set: { if !$0 { appState.userMessage = nil } }
        )
    }

    private var selectedPageBinding: Binding<SidebarPage> {
        Binding(
            get: { appState.selectedPage },
            set: { page in
                Task { @MainActor in
                    await Task.yield()
                    appState.selectedPage = page
                    appState.saveNavigationState()
                }
            }
        )
    }
}
