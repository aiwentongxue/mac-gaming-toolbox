import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MacGameToolboxClickFlow
import MacGameToolboxCore
#endif

struct ToolboxStatusBarState: Equatable {
    private struct StatusIdentity: Equatable {
        let phase: TaskPhase
        let message: String

        init(_ status: TaskStatus) {
            phase = status.phase
            message = status.message
        }
    }

    private var dismissedStatus: StatusIdentity?

    mutating func dismiss(_ status: TaskStatus) {
        dismissedStatus = StatusIdentity(status)
    }

    mutating func statusDidChange(from oldStatus: TaskStatus, to newStatus: TaskStatus) {
        guard oldStatus.phase != newStatus.phase else { return }
        dismissedStatus = nil
    }

    func shouldShow(_ status: TaskStatus, in section: SidebarSection) -> Bool {
        guard status.phase != .idle,
              dismissedStatus != StatusIdentity(status) else {
            return false
        }
        if status.phase == .running || status.phase == .awaitingAuthorization {
            return true
        }
        return section == .gaming || section == .storage
    }
}

struct MainContentView: View {
    @ObservedObject var clickFlowController: ClickFlowFeatureController
    @ObservedObject var appDropController: AppDropFeatureController
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationController
    @Environment(\.colorScheme) private var systemColorScheme
    @StateObject private var navigation = NavigationModel()
    @State private var nativeGlassEnabled = NSApp.isActive
    @State private var statusBarState = ToolboxStatusBarState()

    var body: some View {
        ZStack {
            AppBackgroundView()
            NavigationSplitView {
                AppSidebarView(
                    navigation: navigation,
                    clickFlowController: clickFlowController
                )
                .scrollContentBackground(.hidden)
                .background(.ultraThinMaterial)
            } detail: {
                GeometryReader { viewport in
                    ZStack {
                        detailSurface
                        ToolboxDetailRouter(
                            selection: navigation.selection,
                            navigation: navigation,
                            clickFlowController: clickFlowController,
                            appDropController: appDropController
                        )
                        .id("\(navigation.selection.rawValue).\(localization.refreshToken)")
                    }
                    .frame(width: viewport.size.width, height: viewport.size.height)
                    .clipped()
                }
                .navigationTitle(navigation.selection.localizedTitle)
            }
            .navigationSplitViewStyle(.balanced)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowStatusBar {
                ToolboxStatusBar {
                    statusBarState.dismiss(model.status)
                }
            }
        }
        .background(
            WindowAppearanceConfigurator(
                colorScheme: systemColorScheme,
                nativeGlassEnabled: nativeGlassEnabled
            )
        )
        .alert(cacheAlertTitle, isPresented: $model.showingCacheConfirmation) {
            Button(tr("取消", "Cancel"), role: .cancel) {}
            Button(
                model.cacheConfirmationStage == 1
                    ? tr("继续", "Continue")
                    : tr("确认删除", "Delete"),
                role: .destructive
            ) {
                model.confirmCacheCleaning()
            }
        } message: {
            Text(cacheAlertMessage)
        }
        .onAppear {
            synchronizeClickFlowLanguage()
            MenuCommandCoordinator.shared.install(model: model)
            if navigation.selection.isClickFlowPage {
                clickFlowController.refreshPermissions()
            }
        }
        .onChange(of: localization.refreshToken) { _, _ in
            synchronizeClickFlowLanguage()
        }
        .onChange(of: navigation.selection) { _, item in
            if item.isClickFlowPage {
                clickFlowController.refreshPermissions()
            }
        }
        .onChange(of: model.status) { oldStatus, newStatus in
            statusBarState.statusDidChange(from: oldStatus, to: newStatus)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolboxNavigateToSettings)) { _ in
            navigation.select(.settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolboxNavigateToTutorials)) { _ in
            navigation.select(.tutorials)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolboxNavigateToAppDropWishlist)) { _ in
            navigation.select(.appDropWishlist)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            nativeGlassEnabled = true
            clickFlowController.refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            nativeGlassEnabled = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willMiniaturizeNotification)) { _ in
            nativeGlassEnabled = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                nativeGlassEnabled = NSApp.isActive
            }
        }
    }

    private var detailSurface: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay {
                Color(nsColor: .windowBackgroundColor)
                    .opacity(0.18)
            }
            .ignoresSafeArea()
    }

    private var shouldShowStatusBar: Bool {
        statusBarState.shouldShow(model.status, in: navigation.selection.section)
    }

    private func synchronizeClickFlowLanguage() {
        let language: ClickFlowLanguage
        switch AppLanguage.currentLanguage {
        case .simplifiedChinese: language = .simplifiedChinese
        case .traditionalChinese: language = .traditionalChinese
        case .english, .system: language = .english
        case .japanese: language = .japanese
        case .korean: language = .korean
        case .german: language = .german
        case .french: language = .french
        case .spanish: language = .spanish
        case .portuguese: language = .portuguese
        }
        clickFlowController.setLanguage(language)
    }

    private var cacheAlertTitle: String {
        if model.configuration.excludesSensitiveCacheFiles {
            return tr("准备清理", "Ready to Clean")
        }
        return model.cacheConfirmationStage == 1
            ? tr("高风险操作", "High Risk")
            : tr("最终确认", "Final Confirmation")
    }

    private var cacheAlertMessage: String {
        guard let scan = model.cacheScan else { return "" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(clamping: scan.estimatedBytes), countStyle: .file)
        if model.configuration.excludesSensitiveCacheFiles {
            return tr(
                "预计清理 \(size)。无法访问的项目将被跳过，删除无法撤销。",
                "About \(size) will be cleaned. Inaccessible items will be skipped. Deletion cannot be undone."
            )
        }
        if model.cacheConfirmationStage == 1 {
            return tr(
                "预计删除 \(size)，包含用户缓存和系统日志中的可清理项目。无法访问的项目将被跳过。登录状态及游戏缓存可能丢失。",
                "About \(size) of accessible user caches and system logs will be deleted. Inaccessible items will be skipped. Login state and game caches may be lost."
            )
        }
        return tr(
            "此操作不可撤销。首次使用时会启用系统辅助服务。确认永久删除这些缓存和日志吗？",
            "This cannot be undone. The system helper will be enabled on first use. Permanently delete these caches and logs?"
        )
    }
}

extension Notification.Name {
    static let toolboxNavigateToSettings = Notification.Name("toolbox.navigate.settings")
    static let toolboxNavigateToTutorials = Notification.Name("toolbox.navigate.tutorials")
}
