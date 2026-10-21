import SwiftUI
#if SWIFT_PACKAGE
import MacGameToolboxClickFlow
#endif

struct ToolboxDetailRouter: View {
    let selection: SidebarItem
    @ObservedObject var navigation: NavigationModel
    @ObservedObject var clickFlowController: ClickFlowFeatureController

    var body: some View {
        Group {
            switch selection {
            case .metalHUD:
                MetalHUDDetailView()
            case .hoYoAssistant:
                HoYoGamesDetailView()
            case .processPriority:
                ProcessPriorityDetailView()
            case .steamDeckSpoof:
                SteamDeckDetailView()
            case .diskManager:
                DiskManagerDetailView()
            case .systemCleaner:
                SystemCleanerDetailView()
            case .cfClicker, .cfMacros, .cfCombinedMacros, .cfSettings:
                if let page = selection.clickFlowPage {
                    ClickFlowIntegratedPageView(
                        controller: clickFlowController,
                        page: page,
                        onDecline: { navigation.select(.metalHUD) },
                        onNavigate: navigateToClickFlowPage
                    )
                }
            case .appDrop:
                AppDropPlaceholderView()
            case .appearanceWallpaper:
                AppearanceSettingsDetailView()
            case .tutorials:
                TutorialsDetailView()
            case .changelogAbout:
                ChangelogAboutDetailView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func navigateToClickFlowPage(_ page: ClickFlowIntegratedPage) {
        switch page {
        case .clicker:
            navigation.select(.cfClicker)
        case .macros:
            navigation.select(.cfMacros)
        case .combinedMacros:
            navigation.select(.cfCombinedMacros)
        case .settings:
            navigation.select(.cfSettings)
        }
    }
}
