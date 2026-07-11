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
            statusPanel
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
        }
        .background(WindowAppearanceConfigurator(nativeGlassEnabled: $nativeGlassEnabled, colorScheme: effectiveColorScheme, isEnabled: useLiquidGlassUI))
        .sheet(isPresented: $model.showingDiskManager) { DiskManagerView().environmentObject(model) }
        .sheet(isPresented: $model.showingChangelog) { ChangelogView() }
        .sheet(isPresented: $model.showingTutorials) { TutorialsView() }
        .sheet(isPresented: $model.showingProcessSelection) { ProcessSelectionView().environmentObject(model) }
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

    @ViewBuilder private var featureCards: some View {
        FeatureCard(icon: "gauge.with.dots.needle.67percent", title: tr("MetalHUD性能监视器", "MetalHUD Performance Monitor"), subtitle: tr("开发者工具，可以查看游戏帧率等信息，也可以帮助你找到游戏异常的原因", "A developer tool for viewing game frame rates and diagnosing game issues")) {
            HStack {
                Toggle(tr("全局启用", "Enable globally"), isOn: Binding(get: { model.metalHUDEnabled }, set: { value in model.setMetalHUD(value) })).toggleStyle(.switch)
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
        FeatureCard(icon: "gamecontroller.fill", title: tr("HoYoGames 启动帮助", "HoYoGames Launch Assistant"), subtitle: tr("此选项可以帮助你启动HoYoGames，点击“开始运行”后需要在指定时间内打开游戏", "Helps launch HoYoGames; open the game within the selected time after clicking Start")) {
            HStack(alignment: .bottom) {
                Button(tr("开始运行", "Start")) { model.startHoYoAssistant() }
                    .liquidGlassButton(prominent: true)
                Spacer()
                Picker(tr("等待时间", "Wait time"), selection: Binding(get: { model.configuration.hoYoWaitSeconds }, set: { model.setHoYoWaitSeconds($0) })) {
                    ForEach([10, 15, 20], id: \.self) { Text("\($0) \(tr("秒", "sec"))").tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 92)
            }
        }
        FeatureCard(icon: "bolt.fill", title: tr("提高CrossOver优先级", "Increase CrossOver Priority"), subtitle: tr("检测并提高Windows游戏优先级", "Detect and increase Windows game priority")) {
            HStack(alignment: .bottom) {
                Button(tr("检测并优化", "Detect and optimize")) { model.increaseCrossOverPriority() }
                Spacer()
                Button(tr("手动选择进程", "Select processes")) { model.loadProcessesForManualSelection() }
            }
        }
        FeatureCard(icon: "externaldrive.fill", title: tr("将磁盘挂载指定路径", "Mount a Disk at a Specified Path"), subtitle: tr("此方法可自定义外接磁盘的挂载路径，可将部分原本不可放在外接磁盘的游戏资源转移到外接磁盘以节省内置磁盘储存空间", "Customize an external disk's mount path and move supported game resources there to save internal storage space")) {
            HStack(alignment: .bottom) {
                Button(tr("管理磁盘", "Manage volumes")) { model.loadDisks() }
                Spacer()
                Button(tr("恢复上次挂载", "Restore last mount")) { model.restorePreviousMounts() }
            }
        }
        FeatureCard(icon: "trash.fill", title: tr("缓存日志一键清理", "One-click Cache and Log Cleanup"), subtitle: tr("默认仅清理用户缓存和日志；关闭敏感文件排除后将执行高风险完整清理", "Cleans user caches and logs by default; disabling sensitive-file exclusion performs the high-risk full cleanup")) {
            HStack(alignment: .bottom) {
                Button(tr("一键清理", "Clean now"), role: .destructive) { model.prepareCacheScan() }
                Spacer()
                Toggle(tr("排除敏感文件", "Exclude sensitive files"), isOn: Binding(get: { model.configuration.excludesSensitiveCacheFiles }, set: { model.setExcludesSensitiveCacheFiles($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        FeatureCard(icon: "rectangle.2.swap", title: tr("切换到SteamDeck模式", "Switch to SteamDeck Mode"), subtitle: tr("部分游戏反作弊只给SteamDeck后门，伪装成SteamDeck让Mac也能玩", "Some anti-cheat systems allow SteamDeck; impersonating one may let the game run on Mac")) {
            Button(tr("切换模式", "Toggle mode")) { model.toggleSteamDeck() }
        }
        FeatureCard(icon: "clock.arrow.circlepath", title: tr("更新日志", "Changelog"), subtitle: tr("查看版本变化", "Review version changes")) {
            Button(tr("查看", "View")) { model.showingChangelog = true }
        }
        FeatureCard(icon: "book.pages.fill", title: tr("教程总导航", "Tutorial Hub"), subtitle: tr("Mac 游戏与 CrossOver 教程", "Mac gaming and CrossOver tutorials")) {
            Button(tr("打开导航", "Open hub")) { model.showingTutorials = true }
        }
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

private struct MetalHUDAppMenu: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var launchingPath: String?

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
                        Button(tr("移除", "Remove"), role: .destructive) { model.removeRecentMetalHUDApp(app) }
                    }
                    .transaction { $0.animation = .easeInOut(duration: 0.22) }
                }
            }
            Divider()
            Button {
                isPresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { model.launchAppWithMetalHUD() }
            } label: {
                Label(tr("其他 App", "Other App"), systemImage: "plus.app")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(width: 430)
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

private struct ProcessSelectionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredProcesses: [SystemProcess] {
        guard !searchText.isEmpty else { return model.runningProcesses }
        return model.runningProcesses.filter {
            $0.command.localizedCaseInsensitiveContains(searchText) || String($0.pid).contains(searchText)
        }
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
                Button(tr("取消", "Cancel")) { dismiss() }
            }
            TextField(tr("搜索进程名称或 PID", "Search process name or PID"), text: $searchText)
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
                        VStack(alignment: .leading, spacing: 3) {
                            Text(process.command.split(separator: "/").last.map(String.init) ?? process.command)
                                .font(.headline)
                            Text("PID \(process.pid) · \(process.command)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            HStack {
                Text(tr("已选择 \(model.selectedProcessIDs.count)/64 个进程", "\(model.selectedProcessIDs.count)/64 process(es) selected"))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(tr("提高优先级", "Increase Priority")) { model.increaseSelectedProcessPriority() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedProcessIDs.isEmpty)
            }
        }
        .padding(22)
        .frame(minWidth: 680, minHeight: 520)
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

    final class Coordinator: NSObject {
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
