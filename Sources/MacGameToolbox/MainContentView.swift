import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MacGameToolboxClickFlow
#endif

struct MainContentView: View {
    @ObservedObject var clickFlowController: ClickFlowFeatureController
    @ObservedObject var appDropController: AppDropFeatureController
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationController
    @Environment(\.colorScheme) private var systemColorScheme
    @StateObject private var navigation = NavigationModel()
    @State private var nativeGlassEnabled = NSApp.isActive
    @State private var dismissedStatusMessage: String?

    private var usesWallpaper: Bool {
        model.wallpaperImage != nil
    }

    private var effectiveColorScheme: ColorScheme {
        usesWallpaper ? .dark : systemColorScheme
    }

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
                ZStack {
                    detailSurface
                    ToolboxDetailRouter(
                        selection: navigation.selection,
                        navigation: navigation,
                        clickFlowController: clickFlowController,
                        appDropController: appDropController
                    )
                    .id(navigation.selection)
                }
                .navigationTitle(navigation.selection.localizedTitle)
            }
            .navigationSplitViewStyle(.balanced)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowStatusBar {
                ToolboxStatusBar {
                    dismissedStatusMessage = model.status.message
                }
            }
        }
        .background(
            WindowAppearanceConfigurator(
                colorScheme: effectiveColorScheme,
                usesWallpaper: usesWallpaper,
                nativeGlassEnabled: nativeGlassEnabled
            )
        )
        .environment(\.colorScheme, effectiveColorScheme)
        .environment(\.toolboxUsesGlass, usesWallpaper && nativeGlassEnabled)
        .environment(\.nativeGlassEnabled, nativeGlassEnabled)
        .preferredColorScheme(usesWallpaper ? .dark : nil)
        .alert(cacheAlertTitle, isPresented: $model.showingCacheConfirmation) {
            Button(tr("取消", "Cancel"), role: .cancel) {}
            if let scan = model.cacheScan, !scan.inaccessibleTargets.isEmpty {
                Button(tr("打开系统设置", "Open System Settings")) {
                    model.openFullDiskAccessSettings()
                }
                Button(tr("重新扫描", "Scan Again")) {
                    model.prepareCacheScan()
                }
            } else {
                Button(
                    model.cacheConfirmationStage == 1
                        ? tr("继续", "Continue")
                        : tr("确认删除", "Delete"),
                    role: model.configuration.excludesSensitiveCacheFiles ? nil : .destructive
                ) {
                    model.confirmCacheCleaning()
                }
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
            if model.status.phase != .running && model.status.phase != .awaitingAuthorization {
                dismissedStatusMessage = nil
            }
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
                    .opacity(usesWallpaper ? 0.44 : 0.18)
            }
            .ignoresSafeArea()
    }

    private var shouldShowStatusBar: Bool {
        guard model.status.phase != .idle,
              dismissedStatusMessage != model.status.message else {
            return false
        }
        if model.status.phase == .running || model.status.phase == .awaitingAuthorization {
            return true
        }
        return navigation.selection.section == .gaming || navigation.selection.section == .storage
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
        if let scan = model.cacheScan, !scan.inaccessibleTargets.isEmpty {
            return tr("需要完全磁盘访问权限", "Full Disk Access Required")
        }
        if model.configuration.excludesSensitiveCacheFiles {
            return tr("准备清理", "Ready to Clean")
        }
        return model.cacheConfirmationStage == 1
            ? tr("高风险操作", "High Risk")
            : tr("最终确认", "Final Confirmation")
    }

    private var cacheAlertMessage: String {
        guard let scan = model.cacheScan else { return "" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(scan.estimatedBytes), countStyle: .file)
        if !scan.inaccessibleTargets.isEmpty {
            let paths = scan.inaccessibleTargets.prefix(3)
                .map { "\($0.path.path)：\($0.reason)" }
                .joined(separator: "\n")
            let suffix = scan.inaccessibleTargets.count > 3
                ? tr("\n……以及其他项目", "\n…and other items")
                : ""
            return tr(
                "发现 \(scan.inaccessibleTargets.count) 个无法读取的缓存目录，已统计大小 \(size)。请在系统设置中授予完全磁盘访问权限后重新扫描：\n\(paths)\(suffix)",
                "Found \(scan.inaccessibleTargets.count) unreadable cache item(s); readable size is \(size). Grant Full Disk Access in System Settings, then scan again:\n\(paths)\(suffix)"
            )
        }
        if model.configuration.excludesSensitiveCacheFiles {
            return tr(
                "预计清理 \(size)，点击继续执行安全清理。",
                "About \(size) will be cleaned. Click Continue for the safe cleanup."
            )
        }
        if model.cacheConfirmationStage == 1 {
            return tr(
                "预计删除 \(size)，涉及 \(scan.userTargets.count) 个用户目录和系统日志。登录状态及游戏缓存可能丢失。",
                "About \(size) will be deleted across \(scan.userTargets.count) user folders and system logs. Login state and game caches may be lost."
            )
        }
        return tr(
            "此操作不可撤销。首次使用时会启用系统辅助服务。确认永久删除这些缓存和日志吗？",
            "This cannot be undone. The system helper will be enabled on first use. Permanently delete these caches and logs?"
        )
    }
}

extension Notification.Name {
    static let toolboxNavigateToTutorials = Notification.Name("toolbox.navigate.tutorials")
}
