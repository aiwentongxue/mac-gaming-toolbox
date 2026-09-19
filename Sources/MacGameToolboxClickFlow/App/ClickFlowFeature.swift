import Foundation
import SwiftUI

@MainActor
public final class ClickFlowFeatureController: ObservableObject {
    public static let integratedVersion = "1.0.1"
    public static let preferencesSuiteName = "com.iven.macgametoolbox.clickflow"

    @Published private(set) var appState: AppState?
    @Published public private(set) var language: ClickFlowLanguage = .english

    private let defaults: UserDefaults
    private let disclaimerStore: DisclaimerAcceptanceStore
    private let applicationSupportRoot: URL

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
        }
    }

    public func acceptDisclaimer() {
        guard appState == nil else { return }
        disclaimerStore.acceptCurrentDisclaimer()
        appState = Self.makeAppState(defaults: defaults, root: applicationSupportRoot)
    }

    public func shutdown() {
        appState?.shutdown()
    }

    public func setLanguage(_ language: ClickFlowLanguage) {
        ClickFlowL10n.setLanguage(language)
        if self.language == language {
            objectWillChange.send()
        } else {
            self.language = language
        }
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
