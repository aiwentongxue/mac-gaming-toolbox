import Combine
import Foundation
import SwiftUI

@MainActor
public final class ClickFlowFeatureController: ObservableObject {
    public static let integratedVersion = "1.0.1"
    public static let preferencesSuiteName = "com.iven.macgametoolbox.clickflow"

    @Published private(set) var appState: AppState?
    @Published public private(set) var language: ClickFlowLanguage = .english
    @Published public private(set) var isAutomationActive = false

    private let defaults: UserDefaults
    private let disclaimerStore: DisclaimerAcceptanceStore
    private let applicationSupportRoot: URL
    private var stateObservation: AnyCancellable?

    public var isEnabled: Bool { appState != nil }

    public init(
        defaults: UserDefaults? = UserDefaults(suiteName: ClickFlowFeatureController.preferencesSuiteName),
        applicationSupportRoot: URL? = nil
    ) {
        let resolvedDefaults = defaults ?? .standard
        self.defaults = resolvedDefaults
        disclaimerStore = DisclaimerAcceptanceStore(defaults: resolvedDefaults)
        self.applicationSupportRoot = applicationSupportRoot ?? Self.defaultApplicationSupportRoot()
        if disclaimerStore.hasAcceptedCurrentDisclaimer {
            appState = Self.makeAppState(defaults: resolvedDefaults, root: self.applicationSupportRoot)
            observeState()
        }
    }

    public func acceptDisclaimer() {
        guard appState == nil else { return }
        disclaimerStore.acceptCurrentDisclaimer()
        appState = Self.makeAppState(defaults: defaults, root: applicationSupportRoot)
        observeState()
    }

    public func shutdown() {
        appState?.shutdown()
    }

    public func refreshPermissions() {
        appState?.permissionManager.refresh()
    }

    public func setLanguage(_ language: ClickFlowLanguage) {
        ClickFlowL10n.setLanguage(language)
        if self.language == language {
            objectWillChange.send()
        } else {
            self.language = language
        }
    }

    private func observeState() {
        stateObservation = appState?.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAutomationActivity()
            }
        }
        refreshAutomationActivity()
    }

    private func refreshAutomationActivity() {
        guard let appState else {
            isAutomationActive = false
            return
        }
        isAutomationActive =
            appState.isClickerRunning ||
            appState.isRecording ||
            appState.isPlayingMacro ||
            appState.isRecordingCombinedMacro ||
            appState.isPlayingCombinedMacro
    }

    private static func makeAppState(defaults: UserDefaults, root: URL) -> AppState {
        AppState(
            settings: SettingsStore(defaults: defaults),
            macroStorage: MacroStorage(directoryURL: root.appendingPathComponent("Macros", isDirectory: true)),
            combinedMacroStorage: CombinedMacroStorage(
                directoryURL: root.appendingPathComponent("CombinedMacros", isDirectory: true)
            )
        )
    }

    nonisolated static func defaultApplicationSupportRoot() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("MacGameToolbox", isDirectory: true)
            .appendingPathComponent("ClickFlow", isDirectory: true)
    }
}

public enum ClickFlowIntegratedPage: String, CaseIterable, Hashable, Sendable {
    case clicker
    case macros
    case combinedMacros
    case settings

    var sidebarPage: SidebarPage {
        switch self {
        case .clicker: .clicker
        case .macros: .macros
        case .combinedMacros: .combinedMacros
        case .settings: .settings
        }
    }

    init(sidebarPage: SidebarPage) {
        switch sidebarPage {
        case .clicker: self = .clicker
        case .macros: self = .macros
        case .combinedMacros: self = .combinedMacros
        case .settings: self = .settings
        }
    }
}

public struct ClickFlowIntegratedPageView: View {
    @ObservedObject private var controller: ClickFlowFeatureController
    private let page: ClickFlowIntegratedPage
    private let onDecline: () -> Void
    private let onNavigate: (ClickFlowIntegratedPage) -> Void

    public init(
        controller: ClickFlowFeatureController,
        page: ClickFlowIntegratedPage,
        onDecline: @escaping () -> Void,
        onNavigate: @escaping (ClickFlowIntegratedPage) -> Void
    ) {
        self.controller = controller
        self.page = page
        self.onDecline = onDecline
        self.onNavigate = onNavigate
    }

    public var body: some View {
        Group {
            if let appState = controller.appState {
                pageContent(appState: appState)
                    .environmentObject(appState)
                    .alert(cf("app.message.title"), isPresented: messageBinding(appState)) {
                        Button(cf("common.ok")) { appState.userMessage = nil }
                    } message: {
                        Text(appState.userMessage ?? "")
                    }
                    .onAppear {
                        appState.selectedPage = page.sidebarPage
                        appState.permissionManager.refresh()
                    }
                    .onChange(of: appState.selectedPage) { _, newPage in
                        onNavigate(ClickFlowIntegratedPage(sidebarPage: newPage))
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                        appState.permissionManager.refresh()
                    }
            } else {
                DisclaimerView(onAccept: controller.acceptDisclaimer, onDecline: onDecline)
            }
        }
    }

    @ViewBuilder
    private func pageContent(appState: AppState) -> some View {
        switch page {
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

    private func messageBinding(_ appState: AppState) -> Binding<Bool> {
        Binding(
            get: { appState.userMessage != nil },
            set: { if !$0 { appState.userMessage = nil } }
        )
    }
}

public struct ClickFlowFeatureView: View {
    @ObservedObject private var controller: ClickFlowFeatureController
    private let onDecline: () -> Void

    public init(controller: ClickFlowFeatureController, onDecline: @escaping () -> Void) {
        self.controller = controller
        self.onDecline = onDecline
    }

    public var body: some View {
        Group {
            if let appState = controller.appState {
                RootView()
                    .environmentObject(appState)
            } else {
                DisclaimerView(
                    onAccept: controller.acceptDisclaimer,
                    onDecline: onDecline
                )
            }
        }
    }
}
