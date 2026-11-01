import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif

struct MetalHUDDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var mode = MetalHUDMode.desktop
    @State private var appSearchText = ""
    @State private var showsPresetGuide = false
    @State private var isDropTargeted = false

    var body: some View {
        GeometryReader { viewport in
        ToolboxPage(
            icon: SidebarItem.metalHUD.iconName,
            title: tr("MetalHUD 性能监控", "MetalHUD Performance Monitor"),
            subtitle: tr(
                "查看全局注入状态，或只为指定 App、CrossOver 容器及 iOS 游戏开启 MetalHUD。",
                "Manage global injection or enable MetalHUD for a specific app, CrossOver bottle, or iOS game."
            )
        ) {
            Picker(tr("MetalHUD 模式", "MetalHUD Mode"), selection: $mode) {
                ForEach(MetalHUDMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)

            switch mode {
            case .desktop:
                desktopContent
            case .ios:
                iosContent
            }
        }
        .frame(width: viewport.size.width, height: viewport.size.height)
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = model.addMetalHUDApps(urls)
            if accepted { mode = .desktop }
            return accepted
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    .padding(8).allowsHitTesting(false)
            }
        }
        .accessibilityIdentifier("metalHUD.page")
        .onChange(of: mode) { _, newMode in
            if newMode == .ios, model.iosDevices.isEmpty, !model.isRefreshingIOSDevices {
                model.refreshIOSDevices()
            }
        }
        }
    }

    private var desktopContent: some View {
        VStack(spacing: 18) {
            ToolboxCard(
                tr("全局 MetalHUD", "Global MetalHUD"),
                subtitle: tr(
                    "全局开关会影响之后启动的原生与 Wine 游戏；单 App 启动不会修改这个全局值。",
                    "The global switch affects subsequently launched native and Wine games. Per-app launches do not change this value."
                )
            ) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(model.metalHUDEnabled ? Color.green : Color.secondary.opacity(0.45))
                        .frame(width: 9, height: 9)
                        .accessibilityHidden(true)
                    Text(model.metalHUDEnabled ? tr("已启用", "Enabled") : tr("已关闭", "Disabled"))
                        .font(.headline)
                    Spacer()
                    Toggle(
                        tr("全局启用", "Enable globally"),
                        isOn: Binding(
                            get: { model.metalHUDEnabled },
                            set: { model.setMetalHUD($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel(tr("全局启用 MetalHUD", "Enable MetalHUD globally"))
                }
            }

            ToolboxCard(
                tr("为单个 App 启动", "Launch a Single App"),
                subtitle: tr(
                    "将访达中的 .app 拖入此页面，或点“添加 App”。添加后不会自动启动，请点击卡片右上角的启动按钮。",
                    "Drag .app files from Finder onto this page, or choose Add App. Adding does not launch an app; use the play button at the top right of its card."
                )
            ) {
                if model.configuration.recentMetalHUDApps.isEmpty {
                    ContentUnavailableText(
                        icon: "app.dashed",
                        title: tr("暂无最近 App", "No Recent Apps"),
                        message: tr("拖入 .app 或点击添加，无需重新查找目录。", "Drop an .app here or add it directly, without finding the folder again.")
                    )
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(model.configuration.recentMetalHUDApps) { app in
                            MetalHUDRecentAppCard(app: app)
                        }
                    }
                }
                HStack {
                    Button {
                        model.chooseMetalHUDApps()
                    } label: {
                        Label(tr("添加 App", "Add App"), systemImage: "plus.app")
                    }
                    Spacer()
                    Button {
                        withAnimation { showsPresetGuide.toggle() }
                    } label: {
                        Label(tr("如何保存预设", "How to Save a Preset"), systemImage: "questionmark.circle")
                    }
                }
                if showsPresetGuide {
                    MetalHUDPresetGuide()
                }
            }

            ToolboxCard(
                "CrossOver",
                subtitle: tr(
                    "扫描有效容器，并将导出的 MetalHUD 预设应用到指定 Bottle。",
                    "Scan valid bottles and apply an exported MetalHUD preset to one of them."
                )
            ) {
                if model.crossOverBottles.isEmpty {
                    ContentUnavailableText(
                        icon: "wineglass",
                        title: tr("尚未扫描容器", "Bottles Not Scanned"),
                        message: tr("只有同时包含 cxbottle.conf 与 drive_c 的容器会被列出。", "Only bottles containing both cxbottle.conf and drive_c are listed.")
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(model.crossOverBottles) { bottle in
                            HStack(spacing: 12) {
                                Image(systemName: "wineglass")
                                    .foregroundStyle(.purple)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(bottle.displayName)
                                        .font(.subheadline.weight(.medium))
                                    Text(bottle.path)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Button(tr("应用预设", "Apply Preset")) {
                                    model.chooseMetalHUDPreset(forCrossOverBottle: bottle)
                                }
                            }
                            .padding(10)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
                HStack {
                    Button(tr("扫描 CrossOver 容器", "Scan CrossOver Bottles")) {
                        model.refreshCrossOverBottles()
                    }
                    Spacer()
                }
            }
        }
    }

    private var iosContent: some View {
        VStack(spacing: 18) {
            ToolboxCard(
                tr("iOS / iPadOS 设备", "iOS / iPadOS Device"),
                subtitle: tr(
                    "选择已连接、已信任并在 Xcode 中完成配对的设备。MetalHUD 只注入本次启动的进程。",
                    "Choose a connected, trusted, Xcode-paired device. MetalHUD is injected only into the app launched by this action."
                )
            ) {
                HStack(spacing: 10) {
                    TextField(tr("搜索应用名称或包名", "Search app name or bundle ID"), text: $appSearchText)
                        .textFieldStyle(.roundedBorder)
                    Button { model.refreshIOSDevices() } label: {
                        Label(tr("刷新设备", "Refresh Devices"), systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshingIOSDevices)
                }

                HStack(alignment: .top, spacing: 14) {
                    deviceList
                    Divider()
                    appList
                }
                .frame(minHeight: 320)

                if let app = model.iosLaunchArgumentsApp {
                    IOSLaunchArgumentsInlineEditor(app: app)
                }

                HStack {
                    Text(model.selectedIOSBundleIdentifier ?? tr("请选择要启动的应用", "Select an app to launch"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button(tr("带 MetalHUD 启动", "Launch with MetalHUD")) {
                        model.launchSelectedIOSAppWithMetalHUD()
                    }
                    .toolboxProminentButton()
                    .disabled(model.selectedIOSDeviceID == nil || model.selectedIOSBundleIdentifier == nil)
                }
            }
        }
        .task {
            if model.iosDevices.isEmpty { model.refreshIOSDevices() }
        }
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("设备", "Devices"))
                .font(.subheadline.weight(.semibold))
            if model.isRefreshingIOSDevices, model.iosDevices.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.iosDevices.isEmpty {
                ContentUnavailableText(
                    icon: "iphone.slash",
                    title: tr("未发现设备", "No Devices Found"),
                    message: tr("连接并信任设备，完成 Xcode 配对后刷新。", "Connect and trust the device, pair it with Xcode, then refresh.")
                )
            } else {
                List(selection: Binding(
                    get: { model.selectedIOSDeviceID },
                    set: { model.selectIOSDevice($0) }
                )) {
                    ForEach(model.iosDevices) { device in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.displayName)
                            Text([device.model, device.state].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(Optional(device.id))
                    }
                }
                .listStyle(.inset)
                .frame(width: 250)
            }
        }
        .frame(width: 260, alignment: .topLeading)
    }

    private var appList: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("设备上的应用", "Apps on Device"))
                .font(.subheadline.weight(.semibold))
            if model.selectedIOSDeviceID == nil {
                ContentUnavailableText(
                    icon: "iphone",
                    title: tr("先选择设备", "Select a Device First"),
                    message: ""
                )
            } else if model.isRefreshingIOSApps, model.iosApps.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredIOSApps.isEmpty {
                ContentUnavailableText(
                    icon: "magnifyingglass",
                    title: tr("未找到应用", "No Apps Found"),
                    message: tr("可尝试刷新应用列表或更改搜索条件。", "Refresh the app list or change the search terms.")
                )
            } else {
                List(selection: $model.selectedIOSBundleIdentifier) {
                    ForEach(filteredIOSApps) { app in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                if model.isPinnedIOSApp(app) {
                                    Image(systemName: "pin.fill")
                                        .foregroundStyle(.tint)
                                }
                                Text(app.displayName)
                            }
                            Text(app.version.isEmpty ? app.bundleIdentifier : "\(app.bundleIdentifier) · \(app.version)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(Optional(app.bundleIdentifier))
                        .contextMenu {
                            Button(model.isPinnedIOSApp(app) ? tr("取消置顶", "Unpin") : tr("置顶应用", "Pin App")) {
                                model.togglePinnedIOSApp(app)
                            }
                            Button(tr("设置启动参数", "Set Launch Arguments")) {
                                model.editIOSLaunchArguments(for: app)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var filteredIOSApps: [IOSInstalledApp] {
        let query = appSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.iosApps }
        return model.iosApps.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
                $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }
}

private enum MetalHUDMode: String, CaseIterable, Identifiable {
    case desktop
    case ios

    var id: Self { self }

    var title: String {
        switch self {
        case .desktop: tr("原生与 Wine 游戏", "Native & Wine Games")
        case .ios: tr("iOS / iPadOS 游戏", "iOS / iPadOS Games")
        }
    }
}

private struct MetalHUDRecentAppCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    let app: RecentMetalHUDApp

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    Spacer(minLength: 2)
                    Button { launch() } label: {
                        ZStack {
                            Circle().fill(Color.blue)
                            Image(systemName: "play.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white).offset(x: 1)
                        }.frame(width: 31, height: 31)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("使用 MetalHUD 启动", "Launch with MetalHUD") + ", \(app.displayName)")
                    .accessibilityIdentifier("metalHUD.launch.\(app.path)")
                    .help(tr("使用 MetalHUD 启动", "Launch with MetalHUD") + " " + app.displayName)
                }
                Text(app.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
            }

            presetControls
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
        .background {
            shape
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    shape.fill(
                        Color.accentColor.opacity(isHovering ? 0.055 : 0.018)
                    )
                }
        }
        .overlay {
            shape.stroke(
                isHovering
                    ? Color.accentColor.opacity(0.58)
                    : Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08),
                lineWidth: isHovering ? 1.25 : 0.8
            )
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.24 : 0.08),
            radius: isHovering ? 9 : 5,
            y: isHovering ? 4 : 2
        )
        .contentShape(shape)
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .contextMenu {
            Button(app.preset == nil
                ? tr("添加 HUD 预设", "Add HUD Preset")
                : tr("更换 HUD 预设", "Change HUD Preset")) {
                choosePreset()
            }
            Button(tr("移除 HUD 预设", "Remove HUD Preset")) {
                model.removeMetalHUDPreset(for: app)
            }
            .disabled(app.preset == nil)
            Divider()
            Button(tr("从列表中移除", "Remove from List"), role: .destructive) {
                model.removeRecentMetalHUDApp(app)
            }
        }
    }

    @ViewBuilder
    private var presetControls: some View {
        if let preset = app.preset {
            Menu {
                Button(tr("更换 HUD 预设", "Change HUD Preset")) {
                    choosePreset()
                }
                Button(tr("移除 HUD 预设", "Remove HUD Preset")) {
                    model.removeMetalHUDPreset(for: app)
                }
                Divider()
                Button(tr("从列表中移除", "Remove from List"), role: .destructive) {
                    model.removeRecentMetalHUDApp(app)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                        .fixedSize()
                    Text(preset.displayName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 2)
                    Image(systemName: "ellipsis")
                        .fixedSize()
                        .layoutPriority(1)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(.quaternary.opacity(0.55), in: Capsule())
                .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel(tr("预设与管理", "Preset & Actions"))
            .accessibilityValue(preset.displayName)
        } else {
            HStack(spacing: 6) {
                Button {
                    choosePreset()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text(tr("添加 HUD 预设", "Add HUD Preset"))
                            .lineLimit(1)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(.quaternary.opacity(0.4), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(
                                .secondary.opacity(0.25),
                                style: StrokeStyle(lineWidth: 0.8, dash: [3, 3])
                            )
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("添加 HUD 预设", "Add HUD Preset"))

                Menu {
                    Button(tr("从列表中移除", "Remove from List"), role: .destructive) {
                        model.removeRecentMetalHUDApp(app)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.quaternary.opacity(0.55), in: Circle())
                        .contentShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(tr("预设与管理", "Preset & Actions"))
            }
        }
    }

    private func launch() {
        model.launchRecordedAppWithMetalHUD(app.path)
    }

    private func choosePreset() {
        model.chooseMetalHUDPreset(for: app)
    }
}

private struct MetalHUDPresetGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text(tr(
                "在游戏中连续点击 MetalHUD 三下，或从左上角菜单编辑 HUD，然后选择“Export HUD Configuration”导出配置文件。回到工具箱后，在最近 App 上右键并保存预设。",
                "In the game, click MetalHUD three times or edit it from the upper-left menu, then choose “Export HUD Configuration.” Return here and save the preset from the recent app’s context menu."
            ))
            .font(.subheadline)
            Image("MetalHUDPresetTutorial")
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxHeight: 360)
        }
    }
}

private struct IOSLaunchArgumentsInlineEditor: View {
    @EnvironmentObject private var model: AppModel
    let app: IOSInstalledApp

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(tr("启动参数 · \(app.displayName)", "Launch Arguments · \(app.displayName)"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(tr("收起", "Hide")) {
                    model.iosLaunchArgumentsApp = nil
                }
            }
            Text(tr("每行一个参数，不经过 Shell 解析。", "One argument per line; arguments are never shell-parsed."))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $model.iosLaunchArgumentsText)
                .font(.body.monospaced())
                .frame(minHeight: 110)
                .border(.secondary.opacity(0.25))
            HStack {
                Spacer()
                Button(tr("保存参数", "Save Arguments")) {
                    model.saveIOSLaunchArguments()
                }
                .toolboxProminentButton()
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct HoYoGamesDetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ToolboxPage(
            icon: SidebarItem.hoYoAssistant.iconName,
            title: tr("HoYoGames 启动帮助", "HoYoGames Launch Assistant"),
            subtitle: tr(
                "在限定时间内启动游戏，帮助工具箱识别 Wine 进程并完成后续优化。",
                "Launch the game within a limited window so the toolbox can identify Wine processes and continue optimization."
            )
        ) {
            ToolboxCard(
                tr("启动流程", "Launch Flow"),
                subtitle: tr(
                    "开始后会临时调整启动辅助配置，并在倒计时结束后检测 Wine 进程。无论成功或取消，都会尝试恢复原状态。",
                    "Temporary launch assistance is applied first. Wine processes are checked after the countdown. The original state is restored on success or cancellation."
                )
            ) {
                HStack(alignment: .center, spacing: 14) {
                    Button(tr("开始运行", "Start")) {
                        model.startHoYoAssistant()
                    }
                    .toolboxProminentButton()
                    .controlSize(.large)
                    .disabled(model.isHoYoAssistantRunning)

                    Picker(
                        tr("等待时间", "Wait Time"),
                        selection: Binding(
                            get: { model.configuration.hoYoWaitSeconds },
                            set: { model.setHoYoWaitSeconds($0) }
                        )
                    ) {
                        ForEach([10, 15, 20], id: \.self) { seconds in
                            Text("\(seconds) \(tr("秒", "sec"))").tag(seconds)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180)

                    Toggle(
                        tr("倒计时后不提升优先级", "Do Not Raise Priority"),
                        isOn: Binding(
                            get: { model.configuration.doesNotRaiseHoYoPriority },
                            set: { model.setDoesNotRaiseHoYoPriority($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    Spacer()
                }
            }

            ToolboxCard(tr("当前状态", "Current Status")) {
                HStack(spacing: 12) {
                    Image(systemName: statusIcon)
                        .font(.title2)
                        .foregroundStyle(statusColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.status.phase == .idle ? tr("等待启动", "Ready to Launch") : model.status.message)
                            .font(.headline)
                        Text(AppLanguage.phase(model.status.phase))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isHoYoAssistantRunning {
                        Button(tr("取消并恢复", "Cancel and Restore")) {
                            model.cancelHoYoAssistant()
                        }
                    }
                }
            }

            SteamDeckModeSection()

            if !model.status.log.isEmpty {
                ToolboxCard(tr("执行记录", "Activity Log")) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(model.status.log.enumerated()), id: \.offset) { _, line in
                            Label(line, systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
        case .running, .awaitingAuthorization: "hourglass.circle.fill"
        case .idle: "gamecontroller"
        }
    }

    private var statusColor: Color {
        switch model.status.phase {
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .secondary
        case .running, .awaitingAuthorization: .orange
        case .idle: .purple
        }
    }
}

struct ProcessPriorityDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var mode = ProcessPriorityMode.crossOver
    @State private var searchText = ""
    @State private var sortOrder = ProcessSortOrder.cpu
    @State private var favoriteName = ""
    @AppStorage(ProcessPriorityStorageKey.crossOver.rawValue)
    private var crossOverPriorityRaw = Int(ProcessPriorityLevel.highest.rawValue)
    @AppStorage(ProcessPriorityStorageKey.manual.rawValue)
    private var manualPriorityRaw = Int(ProcessPriorityLevel.highest.rawValue)
    @AppStorage(ProcessPriorityStorageKey.favorites.rawValue)
    private var favoritesPriorityRaw = Int(ProcessPriorityLevel.highest.rawValue)

    var body: some View {
        ToolboxPage(
            icon: SidebarItem.processPriority.iconName,
            title: tr("游戏进程优化", "Game Process Optimization"),
            subtitle: tr(
                "通过系统特权 Helper 调整 CrossOver、手动选择的进程或收藏进程的调度优先级。",
                "Adjust scheduling priority for CrossOver, selected, or favorite processes through the privileged helper."
            ),
            maxContentWidth: 1180
        ) {
            Picker(tr("优化模式", "Optimization Mode"), selection: $mode) {
                ForEach(ProcessPriorityMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 620)

            switch mode {
            case .crossOver:
                crossOverContent
            case .manual:
                manualContent
            case .favorites:
                favoritesContent
            }
        }
    }

    private var crossOverContent: some View {
        ToolboxCard(
            tr("CrossOver / Wine 全量优化", "CrossOver / Wine Optimization"),
            subtitle: tr(
                "检测所有 CrossOver 或 Wine 游戏进程，并统一应用此模式选定的调度优先级。它不会按 Bottle 单独选择，也不会修改图形后端。",
                "Detect all CrossOver or Wine game processes and apply this mode's scheduling priority together. It does not target one bottle or change the graphics backend."
            )
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    priorityPicker(crossOverPriorityBinding)
                    Spacer()
                    Button(tr("检测并应用优先级", "Detect and Apply Priority")) {
                        model.increaseCrossOverPriority(priority: crossOverPriority)
                    }
                    .toolboxProminentButton()
                }
                priorityHelp
            }
        }
    }

    private var manualContent: some View {
        ToolboxCard(
            tr("运行中的进程", "Running Processes"),
            subtitle: tr(
                "最多可选择 64 个进程。搜索会匹配完整路径、名称和 PID。",
                "Select up to 64 processes. Search matches complete paths, names, and PIDs."
            )
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField(tr("搜索名称、路径或 PID", "Search name, path, or PID"), text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .layoutPriority(1)
                        .frame(minWidth: 220, maxWidth: .infinity)
                    Picker(tr("排序", "Sort"), selection: $sortOrder) {
                        ForEach(ProcessSortOrder.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .frame(width: 120)
                    priorityPicker(manualPriorityBinding)
                    Button { model.refreshRunningProcesses() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(tr("刷新进程", "Refresh Processes"))
                }
                priorityHelp

                if model.runningProcesses.isEmpty {
                    ContentUnavailableText(
                        icon: "list.bullet.rectangle",
                        title: tr("尚未读取进程", "Processes Not Loaded"),
                        message: tr("点击刷新读取当前可运行的进程。", "Refresh to read the currently running processes.")
                    )
                    HStack {
                        Spacer()
                        Button(tr("读取进程", "Load Processes")) {
                            model.refreshRunningProcesses()
                        }
                        Spacer()
                    }
                } else {
                    List(sortedProcesses) { process in
                        HStack(spacing: 10) {
                            Toggle("", isOn: processBinding(process))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .fixedSize()
                                .accessibilityLabel(
                                    tr("选择进程", "Select Process") + ", \(process.displayName)"
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(process.displayName)
                                    .font(.subheadline.weight(.medium))
                                Text("CPU \(process.cpuUsage.formatted(.number.precision(.fractionLength(1))))% · PID \(process.pid) · \(process.locationPath ?? process.command)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                model.toggleFavoriteProcess(process)
                            } label: {
                                Image(systemName: model.isFavoriteProcess(process) ? "star.fill" : "star")
                                    .foregroundStyle(model.isFavoriteProcess(process) ? .yellow : .secondary)
                                    .frame(width: 24)
                            }
                            .buttonStyle(.borderless)
                            .fixedSize()
                            .help(tr("收藏进程", "Favorite Process"))
                        }
                        .padding(.vertical, 3)
                    }
                    .frame(minHeight: 380, idealHeight: 450, maxHeight: 520)
                }

                HStack {
                    Text(tr("已选择 \(model.selectedProcessIDs.count) 个进程", "\(model.selectedProcessIDs.count) process(es) selected"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(tr("应用到所选进程", "Apply to Selected")) {
                        model.increaseSelectedProcessPriority(priority: manualPriority)
                    }
                    .toolboxProminentButton()
                    .disabled(model.selectedProcessIDs.isEmpty)
                }
            }
        }
    }

    private var favoritesContent: some View {
        VStack(spacing: 18) {
            ToolboxCard(
                tr("收藏的常用进程", "Favorite Processes"),
                subtitle: tr(
                    "优化时按完整且区分大小写的进程名匹配。",
                    "Optimization matches complete, case-sensitive process names."
                )
            ) {
                HStack {
                    TextField(tr("输入精确进程名", "Enter exact process name"), text: $favoriteName)
                        .textFieldStyle(.roundedBorder)
                    Button(tr("添加", "Add")) {
                        model.addFavoriteProcess(favoriteName)
                        favoriteName = ""
                    }
                    .disabled(normalizedFavoriteName.isEmpty)
                }
                if model.configuration.favoriteProcessNames.isEmpty {
                    ContentUnavailableText(
                        icon: "star",
                        title: tr("暂无常用进程", "No Favorite Processes"),
                        message: tr("添加常用进程后，可一键优化所有正在运行的同名进程。", "Add favorites to optimize every running process with that exact name.")
                    )
                } else {
                    VStack(spacing: 7) {
                        ForEach(model.configuration.favoriteProcessNames, id: \.self) { name in
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                Text(name)
                                    .font(.body.monospaced())
                                Spacer()
                                Button(tr("移除", "Remove"), role: .destructive) {
                                    model.removeFavoriteProcess(name)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(9)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                HStack {
                    priorityPicker(favoritesPriorityBinding)
                    Spacer()
                    Button(tr("优化常用进程", "Optimize Favorites")) {
                        model.increaseFavoriteProcessPriority(priority: favoritesPriority)
                    }
                    .toolboxProminentButton()
                    .disabled(model.configuration.favoriteProcessNames.isEmpty)
                }
                priorityHelp
            }
        }
    }

    private var crossOverPriorityBinding: Binding<ProcessPriorityLevel> {
        Binding(
            get: { ProcessPriorityLevel.fromStoredRawValue(crossOverPriorityRaw) },
            set: { crossOverPriorityRaw = Int($0.rawValue) }
        )
    }

    private var manualPriorityBinding: Binding<ProcessPriorityLevel> {
        Binding(
            get: { ProcessPriorityLevel.fromStoredRawValue(manualPriorityRaw) },
            set: { manualPriorityRaw = Int($0.rawValue) }
        )
    }

    private var favoritesPriorityBinding: Binding<ProcessPriorityLevel> {
        Binding(
            get: { ProcessPriorityLevel.fromStoredRawValue(favoritesPriorityRaw) },
            set: { favoritesPriorityRaw = Int($0.rawValue) }
        )
    }

    private var crossOverPriority: ProcessPriorityLevel {
        ProcessPriorityLevel.fromStoredRawValue(crossOverPriorityRaw)
    }

    private var manualPriority: ProcessPriorityLevel {
        ProcessPriorityLevel.fromStoredRawValue(manualPriorityRaw)
    }

    private var favoritesPriority: ProcessPriorityLevel {
        ProcessPriorityLevel.fromStoredRawValue(favoritesPriorityRaw)
    }

    private var priorityHelp: some View {
        Label(
            tr(
                "默认档位为系统 nice 0，不会恢复进程之前的历史值。",
                "Default means system nice 0; it does not restore a process's previous value."
            ),
            systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func priorityPicker(_ selection: Binding<ProcessPriorityLevel>) -> some View {
        Picker(tr("优先级", "Priority"), selection: selection) {
            ForEach(ProcessPriorityLevel.allCases) { level in
                Text(level.localizedMenuTitle).tag(level)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 190)
    }

    private var normalizedFavoriteName: String {
        favoriteName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sortedProcesses: [SystemProcess] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty
            ? model.runningProcesses
            : model.runningProcesses.filter { $0.matches(searchText: query) }
        switch sortOrder {
        case .cpu:
            return filtered.sorted {
                if $0.cpuUsage == $1.cpuUsage {
                    return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
                return $0.cpuUsage > $1.cpuUsage
            }
        case .name:
            return filtered.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        case .pid:
            return filtered.sorted { $0.pid < $1.pid }
        }
    }

    private func processBinding(_ process: SystemProcess) -> Binding<Bool> {
        Binding(
            get: { model.selectedProcessIDs.contains(process.pid) },
            set: { selected in
                if selected {
                    guard model.selectedProcessIDs.count < 64 else { return }
                    model.selectedProcessIDs.insert(process.pid)
                } else {
                    model.selectedProcessIDs.remove(process.pid)
                }
            }
        )
    }
}

enum ProcessPriorityStorageKey: String, CaseIterable {
    case crossOver = "app.processPriority.crossOver"
    case manual = "app.processPriority.manual"
    case favorites = "app.processPriority.favorites"

    var defaultLevel: ProcessPriorityLevel { .highest }

    func level(in defaults: UserDefaults) -> ProcessPriorityLevel {
        guard defaults.object(forKey: rawValue) != nil else { return defaultLevel }
        return ProcessPriorityLevel.fromStoredRawValue(defaults.integer(forKey: rawValue))
    }

    func setLevel(_ level: ProcessPriorityLevel, in defaults: UserDefaults) {
        defaults.set(Int(level.rawValue), forKey: rawValue)
    }
}

private enum ProcessPriorityMode: String, CaseIterable, Identifiable {
    case crossOver
    case manual
    case favorites

    var id: Self { self }

    var title: String {
        switch self {
        case .crossOver: "CrossOver"
        case .manual: tr("手动选择", "Manual")
        case .favorites: tr("常用进程", "Favorites")
        }
    }
}

private enum ProcessSortOrder: String, CaseIterable, Identifiable {
    case cpu
    case name
    case pid

    var id: Self { self }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .name: tr("名称", "Name")
        case .pid: "PID"
        }
    }
}

struct SteamDeckModeSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmsToggle = false

    var body: some View {
        VStack(spacing: 18) {
            ToolboxCard(
                isActive ? tr("SteamDeck 模式已启用", "SteamDeck Mode Enabled") : tr("当前使用原始设备名称", "Original Names Active"),
                subtitle: tr(
                    "此功能只修改主机名，不是完整的硬件或 AppID 欺骗。",
                    "This changes hostnames only; it is not a complete hardware or AppID spoof."
                )
            ) {
                HStack(spacing: 12) {
                    Image(systemName: isActive ? "checkmark.shield.fill" : "desktopcomputer")
                        .font(.title2)
                        .foregroundStyle(isActive ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isActive ? "steamdeck" : "macOS")
                            .font(.headline.monospaced())
                        Text(tr("设备名称配置", "Hostname profile"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(isActive ? tr("恢复原始名称", "Restore Original Names") : tr("切换到 SteamDeck", "Switch to SteamDeck")) {
                        confirmsToggle = true
                    }
                    .toolboxProminentButton()
                }

                if let backup = model.configuration.hostnameBackup {
                    Divider()
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                        GridRow {
                            Text(tr("电脑名称", "Computer Name")).foregroundStyle(.secondary)
                            Text(backup.computerName).textSelection(.enabled)
                        }
                        GridRow {
                            Text(tr("主机名", "Host Name")).foregroundStyle(.secondary)
                            Text(backup.hostName).textSelection(.enabled)
                        }
                        GridRow {
                            Text(tr("本地主机名", "Local Hostname")).foregroundStyle(.secondary)
                            Text(backup.localHostName).textSelection(.enabled)
                        }
                    }
                    .font(.caption.monospaced())
                }
            }

            ToolboxCard(tr("重要说明", "Important")) {
                Label(
                    tr(
                        "切换需要管理员授权；游戏或网络服务可能暂时断开。请勿在重要会议、远程连接或未保存工作时操作。",
                        "Changing hostnames requires administrator authorization and may briefly interrupt games or network services. Do not use this during meetings, remote sessions, or unsaved work."
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
        }
        .confirmationDialog(
            isActive ? tr("恢复原始设备名称？", "Restore Original Device Names?") : tr("切换到 SteamDeck 模式？", "Switch to SteamDeck Mode?"),
            isPresented: $confirmsToggle,
            titleVisibility: .visible
        ) {
            Button(isActive ? tr("恢复", "Restore") : tr("切换", "Switch"), role: isActive ? nil : .destructive) {
                model.toggleSteamDeck()
            }
            Button(tr("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(tr(
                "工具箱会记录原始名称，退出模式时用于恢复。",
                "The toolbox records the original names and uses them when leaving the mode."
            ))
        }
    }

    private var isActive: Bool {
        model.configuration.hostnameBackup != nil
    }
}

struct ContentUnavailableText: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .padding(12)
    }
}
