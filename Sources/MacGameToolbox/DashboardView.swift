#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif
import AppKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var nativeGlassEnabled = NSApp.isActive
    @State private var showingMetalHUDApps = false

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 18)]
    private var hasCustomWallpaper: Bool { model.configuration.customWallpaperPath != nil }
    private var effectiveColorScheme: ColorScheme { hasCustomWallpaper ? .dark : colorScheme }
    private var useLiquidGlassUI: Bool { hasCustomWallpaper }

    var body: some View {
        ZStack(alignment: .bottom) {
            background
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LazyVGrid(columns: columns, spacing: 18) {
                        featureCards
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, model.status.phase == .idle ? 28 : 86)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            bottomControls
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
        }
        .background(WindowAppearanceConfigurator(nativeGlassEnabled: $nativeGlassEnabled, colorScheme: effectiveColorScheme, isEnabled: useLiquidGlassUI))
        .sheet(isPresented: $model.showingDiskManager) { DiskManagerView().environmentObject(model) }
        .sheet(isPresented: $model.showingChangelog) { ChangelogView() }
        .sheet(isPresented: $model.showingTutorials) { TutorialsView() }
        .sheet(isPresented: $model.showingProcessSelection) { ProcessSelectionView().environmentObject(model) }
        .sheet(isPresented: $model.showingCrossOverBottleSelection) { CrossOverBottleSelectionView().environmentObject(model) }
        .sheet(isPresented: $model.showingDashboardFeatureEditor) { DashboardFeatureEditorView().environmentObject(model) }
        .sheet(isPresented: $model.showingIOSMetalHUDLauncher) { IOSMetalHUDLauncherView().environmentObject(model) }
        .alert(cacheAlertTitle, isPresented: $model.showingCacheConfirmation) {
            Button(tr("取消", "Cancel"), role: .cancel) {}
            Button(model.cacheConfirmationStage == 1 ? tr("继续", "Continue") : tr("确认删除", "Delete"), role: model.configuration.excludesSensitiveCacheFiles ? nil : .destructive) { model.confirmCacheCleaning() }
        } message: { Text(cacheAlertMessage) }
        .environment(\.colorScheme, effectiveColorScheme)
        .environment(\.dashboardColorScheme, effectiveColorScheme)
        .environment(\.nativeGlassEnabled, useLiquidGlassUI && nativeGlassEnabled)
        .environment(\.usesLiquidGlassUI, useLiquidGlassUI)
        .preferredColorScheme(useLiquidGlassUI ? .dark : nil)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            guard useLiquidGlassUI else { return }
            nativeGlassEnabled = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard useLiquidGlassUI else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                nativeGlassEnabled = NSApp.isActive
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willMiniaturizeNotification)) { _ in
            guard useLiquidGlassUI else { return }
            nativeGlassEnabled = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { _ in
            guard useLiquidGlassUI else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                nativeGlassEnabled = NSApp.isActive
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .onAppear { MenuCommandCoordinator.shared.install(model: model) }
    }

    @ViewBuilder private var statusPanel: some View {
        if model.status.phase != .idle {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                    Text(model.status.message).font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .layoutPriority(1)
                if let progress = model.status.progress {
                    ProgressView(value: progress)
                        .tint(.purple)
                        .frame(minWidth: 160)
                }
                Spacer(minLength: 8)
                if model.isHoYoAssistantRunning {
                    Button(tr("取消并恢复 hosts", "Cancel and restore hosts")) { model.cancelHoYoAssistant() }
                }
                Text(AppLanguage.phase(model.status.phase))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .liquidGlassButtonStyle()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .liquidGlassPanel(cornerRadius: 12, colorScheme: effectiveColorScheme, usesLiquidGlassUI: useLiquidGlassUI, nativeGlassEnabled: nativeGlassEnabled)
        }
    }

    private var bottomControls: some View {
        HStack(alignment: .center, spacing: 14) {
            statusPanel
                .frame(maxWidth: .infinity, alignment: .leading)
            dashboardFeatureEditorButton
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var dashboardFeatureEditorButton: some View {
        Button {
            model.showingDashboardFeatureEditor = true
        } label: {
            Label(tr("选项框编辑", "Edit Cards"), systemImage: "rectangle.3.group")
        }
        .liquidGlassButtonStyle()
        .help(tr("添加、删除或调整首页选项框的顺序", "Add, remove, or reorder dashboard cards"))
    }

    @ViewBuilder private var featureCards: some View {
        ForEach(model.visibleDashboardFeatures) { feature in
            featureCard(for: feature)
        }
    }

    @ViewBuilder private func featureCard(for feature: DashboardFeature) -> some View {
        switch feature {
        case .metalHUD:
        FeatureCard(icon: "gauge.with.dots.needle.67percent", title: tr("MetalHUD性能监视器", "MetalHUD Performance Monitor"), subtitle: tr("开发者工具，可以查看游戏帧率等信息，也可以帮助你找到游戏异常的原因", "A developer tool for viewing game frame rates and diagnosing game issues")) {
            HStack {
                Toggle(tr("全局启用", "Enable globally"), isOn: Binding(get: { model.metalHUDEnabled }, set: { value in model.setMetalHUD(value) })).toggleStyle(.switch)
                Spacer()
                Button(tr("对单个 App 启用", "Enable for one app")) {
                    if model.configuration.recentMetalHUDApps.isEmpty {
                        model.launchAppWithMetalHUD()
                    } else {
                        showingMetalHUDApps.toggle()
                    }
                }
                .popover(isPresented: $showingMetalHUDApps, arrowEdge: .bottom) {
                    MetalHUDAppMenu(isPresented: $showingMetalHUDApps).environmentObject(model)
                }
            }
        }
        case .hoYoGames:
        FeatureCard(icon: "gamecontroller.fill", title: tr("HoYoGames 启动帮助", "HoYoGames Launch Assistant"), subtitle: tr("此选项可以帮助你启动HoYoGames，点击“开始运行”后需要在指定时间内打开游戏", "Helps launch HoYoGames; open the game within the selected time after clicking Start")) {
            HStack(alignment: .bottom) {
                Button(tr("开始运行", "Start")) { model.startHoYoAssistant() }
                    .liquidGlassButton(prominent: true)
                Menu {
                    Toggle(tr("倒计时结束后不提升优先级", "Do not raise priority after countdown"), isOn: Binding(
                        get: { model.configuration.doesNotRaiseHoYoPriority },
                        set: { model.setDoesNotRaiseHoYoPriority($0) }
                    ))
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .help(tr("启动帮助选项", "Launch assistant options"))
                Spacer()
                Picker(tr("等待时间", "Wait time"), selection: Binding(get: { model.configuration.hoYoWaitSeconds }, set: { model.setHoYoWaitSeconds($0) })) {
                    ForEach([10, 15, 20], id: \.self) { Text("\($0) \(tr("秒", "sec"))").tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 92)
            }
        }
        case .crossOverPriority:
        FeatureCard(icon: "bolt.fill", title: tr("提高进程优先级", "Increase Process Priority"), subtitle: tr("检测并提高游戏进程优先级", "Detect and increase game process priority")) {
            HStack(alignment: .bottom) {
                Button(tr("CrossOver进程", "CrossOver Processes")) { model.increaseCrossOverPriority() }
                Spacer()
                Button(tr("手动选择进程", "Select processes")) { model.loadProcessesForManualSelection() }
            }
        }
        case .diskMount:
        FeatureCard(icon: "externaldrive.fill", title: tr("将磁盘挂载指定路径", "Mount a Disk at a Specified Path"), subtitle: tr("此方法可自定义外接磁盘的挂载路径，可将部分原本不可放在外接磁盘的游戏资源转移到外接磁盘以节省内置磁盘储存空间", "Customize an external disk's mount path and move supported game resources there to save internal storage space")) {
            HStack(alignment: .bottom) {
                Button(tr("管理磁盘", "Manage volumes")) { model.loadDisks() }
                Spacer()
                Button(tr("恢复上次挂载", "Restore last mount")) { model.restorePreviousMounts() }
            }
        }
        case .cacheCleanup:
        FeatureCard(icon: "trash.fill", title: tr("缓存日志一键清理", "One-click Cache and Log Cleanup"), subtitle: tr("默认仅清理用户缓存和日志；关闭敏感文件排除后将执行高风险完整清理", "Cleans user caches and logs by default; disabling sensitive-file exclusion performs the high-risk full cleanup")) {
            HStack(alignment: .bottom) {
                Button(tr("一键清理", "Clean now"), role: .destructive) { model.prepareCacheScan() }
                Spacer()
                Toggle(tr("排除敏感文件", "Exclude sensitive files"), isOn: Binding(get: { model.configuration.excludesSensitiveCacheFiles }, set: { model.setExcludesSensitiveCacheFiles($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        case .steamDeckMode:
        FeatureCard(icon: "rectangle.2.swap", title: tr("切换到SteamDeck模式", "Switch to SteamDeck Mode"), subtitle: tr("部分游戏反作弊只给SteamDeck后门，伪装成SteamDeck让Mac也能玩", "Some anti-cheat systems allow SteamDeck; impersonating one may let the game run on Mac")) {
            Button(tr("切换模式", "Toggle mode")) { model.toggleSteamDeck() }
        }
        case .wallpaper:
        FeatureCard(icon: "photo.fill.on.rectangle.fill", title: tr("导入壁纸", "Import Wallpaper"), subtitle: tr("自定义工具箱背景，图片会按比例填充整个界面", "Customize the toolbox background; images fill the window without stretching")) {
            HStack {
                Button(model.configuration.customWallpaperPath == nil ? tr("导入壁纸", "Import wallpaper") : tr("重新导入", "Import again")) {
                    model.importWallpaper()
                }
                if model.configuration.customWallpaperPath != nil {
                    Button(tr("恢复默认", "Reset")) {
                        model.resetWallpaper()
                    }
                }
            }
        }
        case .tutorials:
        FeatureCard(icon: "book.pages.fill", title: tr("教程总导航", "Tutorial Hub"), subtitle: tr("Mac 游戏与 CrossOver 教程", "Mac gaming and CrossOver tutorials")) {
            Button(tr("打开导航", "Open hub")) { model.showingTutorials = true }
        }
        case .changelog:
        FeatureCard(icon: "clock.arrow.circlepath", title: tr("更新日志", "Changelog"), subtitle: tr("查看版本变化", "Review version changes")) {
            Button(tr("查看", "View")) { model.showingChangelog = true }
        }
        }
    }

    private var statusIcon: String {
        switch model.status.phase {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "minus.circle.fill"
        case .awaitingAuthorization: "lock.shield.fill"
        default: "gearshape.2.fill"
        }
    }

    private var backgroundColors: [Color] {
        effectiveColorScheme == .dark
            ? [Color(red: 0.035, green: 0.045, blue: 0.07), Color(red: 0.08, green: 0.055, blue: 0.13)]
            : [Color(red: 0.94, green: 0.96, blue: 1.0), Color(red: 0.98, green: 0.94, blue: 1.0)]
    }

    @ViewBuilder private var background: some View {
        GeometryReader { proxy in
            if let image = customWallpaperImage {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                    LinearGradient(colors: wallpaperOverlayColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            } else {
                LinearGradient(colors: backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .ignoresSafeArea()
    }

    private var customWallpaperImage: NSImage? {
        guard let path = model.configuration.customWallpaperPath else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private var wallpaperOverlayColors: [Color] {
        effectiveColorScheme == .dark
            ? [Color.black.opacity(0.06), Color.black.opacity(0.16)]
            : [Color.white.opacity(0.04), Color.white.opacity(0.12)]
    }

    private var cacheAlertTitle: String {
        if model.configuration.excludesSensitiveCacheFiles { return tr("准备清理", "Ready to Clean") }
        return model.cacheConfirmationStage == 1 ? tr("高风险操作", "High Risk") : tr("最终确认", "Final Confirmation")
    }
    private var cacheAlertMessage: String {
        guard let scan = model.cacheScan else { return "" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(scan.estimatedBytes), countStyle: .file)
        if model.configuration.excludesSensitiveCacheFiles {
            return tr("预计清理 \(size)，点击继续进行清理", "About \(size) will be cleaned. Click Continue to proceed.")
        }
        if model.cacheConfirmationStage == 1 {
            return tr("预计删除 \(size)，涉及 \(scan.userTargets.count) 个用户目录和系统日志。登录状态及游戏缓存可能丢失。", "About \(size) will be deleted across \(scan.userTargets.count) user folders and system logs. Login state and game caches may be lost.")
        }
        return tr("此操作不可撤销。首次使用时会启用系统辅助服务。确认永久删除这些缓存和日志吗？", "This cannot be undone. The system helper will be enabled on first use. Permanently delete these caches and logs?")
    }
}

private struct DashboardFeatureEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var hiddenFeatures: [DashboardFeature] {
        DashboardFeature.allCases.filter { !model.visibleDashboardFeatures.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("选项框编辑", "Edit Cards"))
                        .font(.title2.bold())
                    Text(tr("使用上下箭头调整首页选项框的顺序。", "Use the arrows to change the dashboard card order."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(tr("完成", "Done")) { dismiss() }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            List {
                Section(tr("已显示", "Displayed")) {
                    ForEach(Array(model.visibleDashboardFeatures.enumerated()), id: \.element) { index, feature in
                        HStack(spacing: 12) {
                            Image(systemName: feature.icon)
                                .frame(width: 20)
                                .foregroundStyle(.tint)
                            Text(feature.title)
                            Spacer()
                            Button {
                                move(featureAt: index, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .help(tr("上移", "Move up"))
                            Button {
                                move(featureAt: index, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == model.visibleDashboardFeatures.count - 1)
                            .help(tr("下移", "Move down"))
                            Button(tr("删除", "Remove"), role: .destructive) {
                                model.setDashboardFeature(feature, isVisible: false)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                if !hiddenFeatures.isEmpty {
                    Section(tr("可添加", "Available")) {
                        ForEach(hiddenFeatures) { feature in
                            HStack(spacing: 12) {
                                Image(systemName: feature.icon)
                                    .frame(width: 20)
                                    .foregroundStyle(.secondary)
                                Text(feature.title)
                                Spacer()
                                Button(tr("添加", "Add")) {
                                    model.setDashboardFeature(feature, isVisible: true)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 510, height: 500)
    }

    private func move(featureAt index: Int, by offset: Int) {
        model.moveDashboardFeatures(from: IndexSet(integer: index), to: index + offset + (offset > 0 ? 1 : 0))
    }
}

private extension DashboardFeature {
    var title: String {
        switch self {
        case .metalHUD: tr("MetalHUD性能监视器", "MetalHUD Performance Monitor")
        case .hoYoGames: tr("HoYoGames 启动帮助", "HoYoGames Launch Assistant")
        case .crossOverPriority: tr("提高进程优先级", "Increase Process Priority")
        case .diskMount: tr("将磁盘挂载指定路径", "Mount a Disk at a Specified Path")
        case .cacheCleanup: tr("缓存日志一键清理", "One-click Cache and Log Cleanup")
        case .steamDeckMode: tr("切换到SteamDeck模式", "Switch to SteamDeck Mode")
        case .wallpaper: tr("导入壁纸", "Import Wallpaper")
        case .tutorials: tr("教程总导航", "Tutorial Hub")
        case .changelog: tr("更新日志", "Changelog")
        }
    }

    var icon: String {
        switch self {
        case .metalHUD: "gauge.with.dots.needle.67percent"
        case .hoYoGames: "gamecontroller.fill"
        case .crossOverPriority: "bolt.fill"
        case .diskMount: "externaldrive.fill"
        case .cacheCleanup: "trash.fill"
        case .steamDeckMode: "rectangle.2.swap"
        case .wallpaper: "photo.fill.on.rectangle.fill"
        case .tutorials: "book.pages.fill"
        case .changelog: "clock.arrow.circlepath"
        }
    }
}

private struct MetalHUDAppMenu: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var launchingPath: String?
    @State private var showingPresetTutorial = false

    private let columns = Array(repeating: GridItem(.fixed(88), spacing: 14), count: 4)

    var body: some View {
        VStack(spacing: 16) {
            Text(tr("最近使用 MetalHUD 打开的 App", "Recently opened with MetalHUD"))
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(model.configuration.recentMetalHUDApps) { app in
                    Button {
                        launch(app)
                    } label: {
                        VStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 58, height: 58)
                                .scaleEffect(launchingPath == app.path ? 1.35 : 1)
                                .opacity(launchingPath == app.path ? 0 : 1)
                            Text(app.displayName)
                                .font(.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 84)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(tr("选择 HUD 预设", "Choose HUD Preset")) {
                            isPresented = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                model.chooseMetalHUDPreset(for: app)
                            }
                        }
                        Button(tr("移除 HUD 预设", "Remove HUD Preset")) {
                            model.removeMetalHUDPreset(for: app)
                        }
                        .disabled(app.preset == nil)
                        Divider()
                        Button(tr("移除", "Remove"), role: .destructive) { model.removeRecentMetalHUDApp(app) }
                    }
                    .transaction { $0.animation = .easeInOut(duration: 0.22) }
                }
            }
            Divider()
            HStack {
                Button {
                    isPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { model.launchAppWithMetalHUD() }
                } label: {
                    Label(tr("其他 App", "Other App"), systemImage: "plus.app")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    showingPresetTutorial = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .help(tr("MetalHUD 预设教程", "MetalHUD preset tutorial"))
            }
            Button {
                isPresented = false
                model.chooseCrossOverBottleMetalHUDPreset()
            } label: {
                Label(tr("为 CrossOver 容器选择 MetalHUD 预设", "Choose MetalHUD Preset for CrossOver Bottle"), systemImage: "wineglass")
                    .frame(maxWidth: .infinity)
            }
            Button {
                isPresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { model.openIOSMetalHUDLauncher() }
            } label: {
                Label(tr("为 iOS 游戏开启 MetalHUD", "Enable MetalHUD for an iOS Game"), systemImage: "iphone.and.arrow.forward")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(width: 430)
        .sheet(isPresented: $showingPresetTutorial) {
            MetalHUDPresetTutorialView()
        }
    }

    private func launch(_ app: RecentMetalHUDApp) {
        withAnimation(.easeInOut(duration: 0.22)) { launchingPath = app.path }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            isPresented = false
            launchingPath = nil
            model.launchRecordedAppWithMetalHUD(app.path)
        }
    }
}

private struct IOSMetalHUDLauncherView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var appSearchText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("为 iOS 游戏开启 MetalHUD", "Enable MetalHUD for an iOS Game"))
                        .font(.title2.bold())
                    Text(tr("选择已通过 Xcode 配对的设备和已安装 App；启动时只向该进程注入 MetalHUD。", "Choose an Xcode-paired device and installed app. MetalHUD is injected only into that launch."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(tr("关闭", "Close")) { dismiss() }
            }
            .padding(20)

            HStack(spacing: 0) {
                deviceColumn
                Divider()
                appColumn
            }
            .frame(maxHeight: .infinity)

            Divider()
            HStack {
                Text(selectedAppDescription).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button(tr("带 MetalHUD 启动", "Launch with MetalHUD")) {
                    model.launchSelectedIOSAppWithMetalHUD()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedIOSDeviceID == nil || model.selectedIOSBundleIdentifier == nil)
            }
            .padding(20)
        }
        .frame(width: 780, height: 520)
        .sheet(isPresented: $model.showingIOSLaunchArgumentsEditor) {
            IOSLaunchArgumentsEditorView().environmentObject(model)
        }
    }

    private var deviceColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("iOS 设备", "iOS Devices")).font(.headline)
                Spacer()
                Button { model.refreshIOSDevices() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.isRefreshingIOSDevices)
                    .help(tr("刷新设备", "Refresh devices"))
            }
            if model.isRefreshingIOSDevices && model.iosDevices.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.iosDevices.isEmpty {
                ContentUnavailableView(tr("未发现设备", "No devices found"), systemImage: "iphone.slash", description: Text(tr("请连接、信任并在 Xcode 中完成配对后刷新。", "Connect, trust, and pair the device in Xcode, then refresh.")))
            } else {
                List(selection: Binding(get: { model.selectedIOSDeviceID }, set: { model.selectIOSDevice($0) })) {
                    ForEach(model.iosDevices) { device in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.displayName)
                            Text([device.model, device.state].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(Optional(device.id))
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 290)
    }

    private var appColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("设备上的应用程序", "Apps on Device")).font(.headline)
                Spacer()
                Button { model.refreshIOSApps() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.selectedIOSDeviceID == nil || model.isRefreshingIOSApps)
                    .help(tr("刷新应用", "Refresh apps"))
            }
            TextField(tr("搜索应用名称或包名", "Search app name or bundle ID"), text: $appSearchText)
                .textFieldStyle(.roundedBorder)
            if model.selectedIOSDeviceID == nil {
                ContentUnavailableView(tr("先选择设备", "Select a device first"), systemImage: "iphone")
            } else if model.isRefreshingIOSApps && model.iosApps.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.iosApps.isEmpty {
                ContentUnavailableView(tr("未读取到应用", "No apps found"), systemImage: "app.dashed", description: Text(tr("刷新后仍为空时，请确认设备已连接且 Xcode 可访问。", "If refresh stays empty, confirm the device is connected and available to Xcode.")))
            } else if filteredIOSApps.isEmpty {
                ContentUnavailableView(tr("未找到匹配的应用", "No matching apps"), systemImage: "magnifyingglass", description: Text(tr("可按应用名称或包名的一部分进行搜索。", "Search by any part of the app name or bundle ID.")))
            } else {
                List(selection: $model.selectedIOSBundleIdentifier) {
                    ForEach(filteredIOSApps) { app in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                if model.isPinnedIOSApp(app) { Image(systemName: "pin.fill").foregroundStyle(.tint) }
                                Text(app.displayName)
                            }
                            Text(app.version.isEmpty ? app.bundleIdentifier : "\(app.bundleIdentifier) · \(app.version)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(Optional(app.bundleIdentifier))
                        .contextMenu {
                            Button(model.isPinnedIOSApp(app) ? tr("取消置顶", "Unpin") : tr("将此 iOS 应用程序置顶", "Pin this iOS app")) {
                                model.togglePinnedIOSApp(app)
                            }
                            Button(tr("为 iOS 应用程序传入启动参数", "Set iOS app launch arguments")) {
                                model.editIOSLaunchArguments(for: app)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    private var selectedAppDescription: String {
        guard let bundleIdentifier = model.selectedIOSBundleIdentifier else {
            return tr("请选择要启动的应用程序", "Select an app to launch")
        }
        return bundleIdentifier
    }

    private var filteredIOSApps: [IOSInstalledApp] {
        let query = appSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.iosApps }
        return model.iosApps.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct IOSLaunchArgumentsEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("iOS 应用程序启动参数", "iOS App Launch Arguments"))
                .font(.title2.bold())
            if let app = model.iosLaunchArgumentsApp {
                Text(app.displayName).font(.headline)
                Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
            }
            Text(tr("每行一个参数。它们会在 App Bundle ID 之后传给 devicectl，不经过 Shell 解析，且只用于下一次“带 MetalHUD 启动”。留空即可清除。", "One argument per line. They are passed after the app bundle ID to devicectl without shell parsing and apply only to the next Launch with MetalHUD. Leave empty to clear."))
                .foregroundStyle(.secondary)
            TextEditor(text: $model.iosLaunchArgumentsText)
                .font(.body.monospaced())
                .border(Color.secondary.opacity(0.3))
                .frame(minHeight: 160)
            HStack {
                Spacer()
                Button(tr("取消", "Cancel")) { dismiss() }
                Button(tr("保存", "Save")) { model.saveIOSLaunchArguments() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 580, height: 360)
    }
}

private struct CrossOverBottleSelectionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("选择 CrossOver 容器", "Choose a CrossOver Bottle"))
                .font(.title2.bold())
            Text(tr("仅显示同时包含 cxbottle.conf 与 drive_c 的容器。选择后再选取 MetalHUD 预设文件。", "Only bottles containing both cxbottle.conf and drive_c are shown. You will choose the MetalHUD preset next."))
                .foregroundStyle(.secondary)
            List(model.crossOverBottles) { bottle in
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        model.chooseMetalHUDPreset(forCrossOverBottle: bottle)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bottle.displayName)
                        Text(bottle.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
            HStack {
                Spacer()
                Button(tr("取消", "Cancel")) { dismiss() }
            }
        }
        .padding(24)
        .frame(width: 560, height: 380)
    }
}

private struct MetalHUDPresetTutorialView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(tr("保存 MetalHUD 预设", "Save a MetalHUD preset"))
                    .font(.title2.bold())
                Spacer()
                Button(tr("完成", "Done")) { dismiss() }
            }
            Text(tr("在游戏中连续点击 MetalHUD 三下，或在游戏左上角菜单栏中编辑 MetalHUD。点击“Export HUD Configuration”，再选择一个目录保存配置文件。", "In the game, click MetalHUD three times in succession, or edit MetalHUD from the menu bar at the upper-left. Click “Export HUD Configuration”, then choose a folder to save the configuration file."))
            Image("MetalHUDPresetTutorial")
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(tr("回到工具箱，在对应最近 App 的图标上点按右键并选择“选择 HUD 预设”。工具箱会复制一份到自己的应用程序支持目录；之后直接从这里启动该 App 时，预设只会传给这个 App。", "Return to Toolbox, right-click the matching recent-app icon, and choose “Choose HUD Preset”. Toolbox keeps its own copy in Application Support; future launches pass the preset only to that app."))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 720, height: 690)
    }
}

private struct ProcessSelectionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showingFavoriteProcessEditor = false
    @State private var lowersPriority = false

    private var filteredProcesses: [SystemProcess] {
        guard !searchText.isEmpty else { return model.runningProcesses }
        return model.runningProcesses.filter { $0.matches(searchText: searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("手动选择进程", "Select Processes")).font(.title2.bold())
                    Text(tr("选择需要提高优先级的进程", "Choose processes whose priority should be increased"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(tr("降低优先级", "Lower priority"), isOn: $lowersPriority)
                    .toggleStyle(.switch)
                Button(tr("取消", "Cancel")) { dismiss() }
            }
            TextField(tr("搜索进程名称、目录或 PID", "Search process name, location, or PID"), text: $searchText)
                .textFieldStyle(.roundedBorder)
            if model.runningProcesses.isEmpty {
                ProgressView(tr("正在读取进程", "Loading processes"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredProcesses) { process in
                    Toggle(isOn: Binding(
                        get: { model.selectedProcessIDs.contains(process.pid) },
                        set: { selected in
                            if selected, model.selectedProcessIDs.count < 64 { model.selectedProcessIDs.insert(process.pid) }
                            else { model.selectedProcessIDs.remove(process.pid) }
                        }
                    )) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(process.displayName)
                                    .font(.headline)
                                Text("CPU \(process.cpuUsage.formatted(.number.precision(.fractionLength(1))))% · PID \(process.pid) · \(tr("目录", "Location")) · \(process.locationPath ?? process.command)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                            Button {
                                model.toggleFavoriteProcess(process)
                            } label: {
                                Image(systemName: model.isFavoriteProcess(process) ? "star.fill" : "star")
                                    .foregroundStyle(model.isFavoriteProcess(process) ? .yellow : .secondary)
                            }
                            .buttonStyle(.borderless)
                            .help(model.isFavoriteProcess(process) ? tr("取消收藏", "Remove favorite") : tr("收藏进程", "Favorite process"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            HStack {
                HStack(spacing: 4) {
                    Button(tr("常用进程优化", "Optimize Favorite Processes")) { model.increaseFavoriteProcessPriority(lowerPriority: lowersPriority) }
                        .disabled(model.configuration.favoriteProcessNames.isEmpty)
                    Menu {
                        Button(tr("编辑常用进程", "Edit Favorite Processes")) { showingFavoriteProcessEditor = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                }
                Text(tr("已选择 \(model.selectedProcessIDs.count)/64 个进程", "\(model.selectedProcessIDs.count)/64 process(es) selected"))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(lowersPriority ? tr("降低优先级", "Lower Priority") : tr("提高优先级", "Increase Priority")) {
                    model.increaseSelectedProcessPriority(lowerPriority: lowersPriority)
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedProcessIDs.isEmpty)
            }
        }
        .padding(22)
        .frame(minWidth: 680, minHeight: 520)
        .sheet(isPresented: $showingFavoriteProcessEditor) {
            FavoriteProcessEditorView().environmentObject(model)
        }
    }
}

private struct FavoriteProcessEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var processName = ""

    private var normalizedName: String {
        processName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("编辑常用进程", "Edit Favorite Processes"))
                        .font(.title2.bold())
                    Text(tr("常用进程优化只会按完整且区分大小写的进程名进行搜索", "Favorite optimization only searches complete, case-sensitive process names"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(tr("完成", "Done")) { dismiss() }
            }

            HStack {
                TextField(tr("输入精确进程名", "Enter exact process name"), text: $processName)
                    .textFieldStyle(.roundedBorder)
                Button(tr("添加常用进程", "Add Favorite Process")) {
                    model.addFavoriteProcess(processName)
                    processName = ""
                }
                .disabled(normalizedName.isEmpty || model.configuration.favoriteProcessNames.contains(normalizedName) || model.configuration.favoriteProcessNames.count >= ConfigurationStore.maxFavoriteProcesses)
            }

            if model.configuration.favoriteProcessNames.isEmpty {
                Text(tr("尚未收藏常用进程", "No favorite processes saved"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.configuration.favoriteProcessNames, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button(tr("删除", "Delete"), role: .destructive) {
                            model.removeFavoriteProcess(name)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 560, height: 420)
    }
}

private struct FeatureCard<Content: View>: View {
    @Environment(\.dashboardColorScheme) private var colorScheme
    @Environment(\.nativeGlassEnabled) private var nativeGlassEnabled
    @Environment(\.usesLiquidGlassUI) private var usesLiquidGlassUI
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(icon: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.icon = icon; self.title = title; self.subtitle = subtitle; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).font(.title).foregroundStyle(.purple)
            Text(title).font(.title3.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
            content
                .liquidGlassButtonStyle()
        }
        .padding(18).frame(minHeight: 180)
        .liquidGlassCard(cornerRadius: 18, colorScheme: colorScheme, usesLiquidGlassUI: usesLiquidGlassUI, nativeGlassEnabled: nativeGlassEnabled)
    }
}

private struct NativeGlassEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct DashboardColorSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme = .light
}

private struct UsesLiquidGlassUIKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var nativeGlassEnabled: Bool {
        get { self[NativeGlassEnabledKey.self] }
        set { self[NativeGlassEnabledKey.self] = newValue }
    }

    var dashboardColorScheme: ColorScheme {
        get { self[DashboardColorSchemeKey.self] }
        set { self[DashboardColorSchemeKey.self] = newValue }
    }

    var usesLiquidGlassUI: Bool {
        get { self[UsesLiquidGlassUIKey.self] }
        set { self[UsesLiquidGlassUIKey.self] = newValue }
    }
}

private struct WindowAppearanceConfigurator: NSViewRepresentable {
    @Binding var nativeGlassEnabled: Bool
    let colorScheme: ColorScheme
    let isEnabled: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window, context: context) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window, context: context) }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func configure(_ window: NSWindow?, context: Context) {
        guard let window else { return }
        guard isEnabled else {
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.titlebarAppearsTransparent = false
            window.animationBehavior = .default
            window.contentView?.layer?.backgroundColor = nil
            return
        }
        window.isOpaque = true
        window.backgroundColor = fallbackBackgroundColor
        window.titlebarAppearsTransparent = true
        window.animationBehavior = .none
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = fallbackBackgroundColor.cgColor
        context.coordinator.configure(for: window) {
            nativeGlassEnabled = false
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.displayIfNeeded()
        } didRestore: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                nativeGlassEnabled = NSApp.isActive
            }
        }
    }

    private var fallbackBackgroundColor: NSColor {
        colorScheme == .dark
            ? NSColor(calibratedRed: 0.035, green: 0.045, blue: 0.07, alpha: 1.0)
            : NSColor(calibratedRed: 0.965, green: 0.97, blue: 0.995, alpha: 1.0)
    }

    @MainActor final class Coordinator: NSObject {
        private weak var observedWindow: NSWindow?
        private var willMiniaturize: (() -> Void)?
        private var didRestore: (() -> Void)?

        func configure(for window: NSWindow, willMiniaturize: @escaping () -> Void, didRestore: @escaping () -> Void) {
            self.willMiniaturize = willMiniaturize
            self.didRestore = didRestore
            guard observedWindow !== window else { return }
            if let observedWindow {
                NotificationCenter.default.removeObserver(self, name: NSWindow.willMiniaturizeNotification, object: observedWindow)
                NotificationCenter.default.removeObserver(self, name: NSWindow.didDeminiaturizeNotification, object: observedWindow)
            }
            observedWindow = window
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillMiniaturize),
                name: NSWindow.willMiniaturizeNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidDeminiaturize),
                name: NSWindow.didDeminiaturizeNotification,
                object: window
            )
        }

        @objc private func windowWillMiniaturize() {
            willMiniaturize?()
        }

        @objc private func windowDidDeminiaturize() {
            didRestore?()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

private extension View {
    @ViewBuilder
    func liquidGlassCard(cornerRadius: CGFloat, colorScheme: ColorScheme, usesLiquidGlassUI: Bool, nativeGlassEnabled: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if !usesLiquidGlassUI {
            self
                .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.72), in: shape)
                .overlay(shape.stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)))
        } else if #available(macOS 26.0, *), nativeGlassEnabled {
            self
                .background(liquidGlassFallbackFill(colorScheme), in: shape)
                .glassEffect(.clear.interactive(), in: shape)
                .overlay(shape.stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.24), lineWidth: 0.7))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 14, y: 6)
        } else {
            self
                .background(stableGlassFill(colorScheme), in: shape)
                .overlay(shape.stroke(stableGlassStroke(colorScheme), lineWidth: 0.7))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 14, y: 6)
        }
    }

    @ViewBuilder
    func liquidGlassPanel(cornerRadius: CGFloat, colorScheme: ColorScheme, usesLiquidGlassUI: Bool, nativeGlassEnabled: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if !usesLiquidGlassUI {
            self
                .background(.ultraThinMaterial, in: shape)
        } else if #available(macOS 26.0, *), nativeGlassEnabled {
            self
                .background(liquidGlassFallbackFill(colorScheme), in: shape)
                .glassEffect(.clear.interactive(), in: shape)
                .overlay(shape.stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.26), lineWidth: 0.7))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 12, y: 5)
        } else {
            self
                .background(stableGlassFill(colorScheme), in: shape)
                .overlay(shape.stroke(stableGlassStroke(colorScheme), lineWidth: 0.7))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 12, y: 5)
        }
    }

    @ViewBuilder
    func liquidGlassButton(prominent: Bool = false) -> some View {
        self.modifier(LiquidGlassButtonModifier(prominent: prominent))
    }

    @ViewBuilder
    func liquidGlassButtonStyle() -> some View {
        self.modifier(LiquidGlassButtonModifier(prominent: false))
    }

    func liquidGlassFallbackFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.14)
    }

    func stableGlassFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black.opacity(0.46) : Color.white.opacity(0.64)
    }

    func stableGlassStroke(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }
}

private struct LiquidGlassButtonModifier: ViewModifier {
    @Environment(\.nativeGlassEnabled) private var nativeGlassEnabled
    @Environment(\.usesLiquidGlassUI) private var usesLiquidGlassUI
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), usesLiquidGlassUI && nativeGlassEnabled {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content
        }
    }
}
