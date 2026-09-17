import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif

@MainActor
final class AppModel: ObservableObject {
    @Published var status = TaskStatus()
    @Published var configuration = AppConfiguration()
    @Published var disks: [DiskVolume] = []
    @Published var selectedDiskIDs = Set<String>()
    @Published var diskPaths: [String: String] = [:]
    @Published var metalHUDEnabled = false
    @Published var cacheScan: CacheScan?
    @Published var showingDiskManager = false
    @Published var showingCacheConfirmation = false
    @Published var cacheConfirmationStage = 0
    @Published var showingChangelog = false
    @Published var showingTutorials = false
    @Published var isHoYoAssistantRunning = false
    @Published var showingProcessSelection = false
    @Published var runningProcesses: [SystemProcess] = []
    @Published var selectedProcessIDs = Set<Int32>()
    @Published var showingCrossOverBottleSelection = false
    @Published var crossOverBottles: [CrossOverBottle] = []
    @Published var showingDashboardFeatureEditor = false
    @Published var showingIOSMetalHUDLauncher = false
    @Published var iosDevices: [IOSDevice] = []
    @Published var iosApps: [IOSInstalledApp] = []
    @Published var selectedIOSDeviceID: String?
    @Published var selectedIOSBundleIdentifier: String?
    @Published var isRefreshingIOSDevices = false
    @Published var isRefreshingIOSApps = false
    @Published var showingIOSLaunchArgumentsEditor = false
    @Published var iosLaunchArgumentsApp: IOSInstalledApp?
    @Published var iosLaunchArgumentsText = ""

    private let privileged = PrivilegedHelperClient()
    private let configurationStore: ConfigurationStore
    private let diskService: DiskService
    private let gamingService: GamingService
    private let hostnameService: HostnameService
    private let cacheService: CacheService
    private let wallpaperService: WallpaperService
    private let metalHUDPresetStore: MetalHUDPresetStore
    private let crossOverBottleService: CrossOverBottleService
    private let diagnosticsService = DiagnosticsService()
    private var hoyoTask: Task<Void, Never>?
    private var automaticMountTask: Task<Void, Never>?
    private var didLaunch = false

    init() {
        configurationStore = ConfigurationStore()
        diskService = DiskService()
        gamingService = GamingService(privileged: privileged)
        hostnameService = HostnameService(privileged: privileged)
        cacheService = CacheService(privileged: privileged)
        wallpaperService = WallpaperService()
        metalHUDPresetStore = MetalHUDPresetStore()
        crossOverBottleService = CrossOverBottleService()
        launch()
    }

    func launch() {
        guard !didLaunch else { return }
        didLaunch = true
        DiagnosticFileLogger.write("App launched, version \(GitHubReleaseChecker.currentVersion)")
        Task {
            do { configuration = try await configurationStore.load() }
            catch { report(error) }
            metalHUDEnabled = await gamingService.metalHUDEnabled()
            if (try? String(contentsOfFile: "/etc/hosts", encoding: .utf8))?.contains("# BEGIN MAC GAME TOOLBOX HOYO") == true {
                await gamingService.cleanStaleHoYoEntries()
            }
            startAutomaticMountMonitoring()
        }
    }

    func setMetalHUD(_ enabled: Bool) {
        runTask(tr("正在更新 MetalHUD", "Updating MetalHUD")) {
            try await self.gamingService.setMetalHUD(enabled: enabled)
            self.metalHUDEnabled = enabled
            return enabled ? tr("MetalHUD 已开启", "MetalHUD enabled") : tr("MetalHUD 已关闭", "MetalHUD disabled")
        }
    }

    var visibleDashboardFeatures: [DashboardFeature] {
        configuration.dashboardFeatureOrder
    }

    func setDashboardFeature(_ feature: DashboardFeature, isVisible: Bool) {
        if isVisible {
            guard !configuration.dashboardFeatureOrder.contains(feature) else { return }
            configuration.dashboardFeatureOrder.append(feature)
        } else {
            configuration.dashboardFeatureOrder.removeAll { $0 == feature }
        }
        saveConfiguration()
    }

    func moveDashboardFeatures(from source: IndexSet, to destination: Int) {
        configuration.dashboardFeatureOrder.move(fromOffsets: source, toOffset: destination)
        saveConfiguration()
    }

    func launchAppWithMetalHUD() {
        let panel = NSOpenPanel()
        panel.title = tr("选择要启用 MetalHUD 的 App", "Choose an app for MetalHUD")
        panel.prompt = tr("启用并打开", "Enable and Open")
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK, let applicationURL = panel.url else { return }

        launchRecordedAppWithMetalHUD(applicationURL.path)
    }

    func openIOSMetalHUDLauncher() {
        showingIOSMetalHUDLauncher = true
        refreshIOSDevices()
    }

    func refreshIOSDevices() {
        isRefreshingIOSDevices = true
        Task {
            defer { isRefreshingIOSDevices = false }
            do {
                iosDevices = try await gamingService.iosDevices()
                if let selectedIOSDeviceID, iosDevices.contains(where: { $0.id == selectedIOSDeviceID }) {
                    refreshIOSApps()
                } else {
                    selectedIOSDeviceID = iosDevices.first?.id
                    iosApps = []
                    selectedIOSBundleIdentifier = nil
                    if selectedIOSDeviceID != nil { refreshIOSApps() }
                }
            } catch { report(error) }
        }
    }

    func selectIOSDevice(_ deviceID: String?) {
        guard selectedIOSDeviceID != deviceID else { return }
        selectedIOSDeviceID = deviceID
        iosApps = []
        selectedIOSBundleIdentifier = nil
        refreshIOSApps()
    }

    func refreshIOSApps() {
        guard let deviceID = selectedIOSDeviceID else { return }
        isRefreshingIOSApps = true
        Task {
            defer { isRefreshingIOSApps = false }
            do {
                iosApps = sortedIOSApps(try await gamingService.iosApps(on: deviceID))
                if let selectedIOSBundleIdentifier, !iosApps.contains(where: { $0.bundleIdentifier == selectedIOSBundleIdentifier }) {
                    self.selectedIOSBundleIdentifier = nil
                }
            } catch { report(error) }
        }
    }

    func launchSelectedIOSAppWithMetalHUD() {
        guard let deviceID = selectedIOSDeviceID,
              let bundleIdentifier = selectedIOSBundleIdentifier,
              let app = iosApps.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
        runTask(tr("正在带 MetalHUD 启动 iOS App", "Launching iOS app with MetalHUD")) {
            try await self.gamingService.launchIOSAppWithMetalHUD(
                deviceID: deviceID,
                bundleIdentifier: bundleIdentifier,
                launchArguments: self.configuration.iOSLaunchArguments[bundleIdentifier] ?? []
            )
            return tr("已带 MetalHUD 启动 \(app.displayName)", "Launched \(app.displayName) with MetalHUD")
        }
    }

    func togglePinnedIOSApp(_ app: IOSInstalledApp) {
        if let index = configuration.pinnedIOSAppBundleIdentifiers.firstIndex(of: app.bundleIdentifier) {
            configuration.pinnedIOSAppBundleIdentifiers.remove(at: index)
        } else {
            configuration.pinnedIOSAppBundleIdentifiers.append(app.bundleIdentifier)
        }
        iosApps = sortedIOSApps(iosApps)
        saveConfiguration()
    }

    func isPinnedIOSApp(_ app: IOSInstalledApp) -> Bool {
        configuration.pinnedIOSAppBundleIdentifiers.contains(app.bundleIdentifier)
    }

    func editIOSLaunchArguments(for app: IOSInstalledApp) {
        iosLaunchArgumentsApp = app
        iosLaunchArgumentsText = (configuration.iOSLaunchArguments[app.bundleIdentifier] ?? []).joined(separator: "\n")
        showingIOSLaunchArgumentsEditor = true
    }

    func saveIOSLaunchArguments() {
        guard let app = iosLaunchArgumentsApp else { return }
        let arguments = iosLaunchArgumentsText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if arguments.isEmpty {
            configuration.iOSLaunchArguments.removeValue(forKey: app.bundleIdentifier)
        } else {
            configuration.iOSLaunchArguments[app.bundleIdentifier] = arguments
        }
        saveConfiguration()
        showingIOSLaunchArgumentsEditor = false
    }

    func iOSLaunchArguments(for app: IOSInstalledApp) -> [String] {
        configuration.iOSLaunchArguments[app.bundleIdentifier] ?? []
    }

    private func sortedIOSApps(_ apps: [IOSInstalledApp]) -> [IOSInstalledApp] {
        let pinned = configuration.pinnedIOSAppBundleIdentifiers
        return apps.sorted { lhs, rhs in
            let lhsIndex = pinned.firstIndex(of: lhs.bundleIdentifier)
            let rhsIndex = pinned.firstIndex(of: rhs.bundleIdentifier)
            switch (lhsIndex, rhsIndex) {
            case let (.some(left), .some(right)): return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
        }
    }

    func launchRecordedAppWithMetalHUD(_ path: String) {
        let applicationURL = URL(fileURLWithPath: path)
        runTask(tr("正在使用 MetalHUD 启动 App", "Launching app with MetalHUD")) {
            let presetPath = self.configuration.recentMetalHUDApps.first(where: { $0.path == applicationURL.path })?.preset?.path
            try await self.gamingService.launchWithMetalHUD(applicationPath: applicationURL.path, presetPath: presetPath)
            self.rememberMetalHUDApp(applicationURL)
            return tr("已使用 MetalHUD 打开 \(applicationURL.deletingPathExtension().lastPathComponent)", "Opened \(applicationURL.deletingPathExtension().lastPathComponent) with MetalHUD")
        }
    }

    func chooseMetalHUDPreset(for app: RecentMetalHUDApp) {
        let panel = NSOpenPanel()
        panel.title = tr("选择已导出的 MetalHUD 预设", "Choose an exported MetalHUD preset")
        panel.prompt = tr("保存预设", "Save Preset")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let presetURL = panel.url else { return }

        runTask(tr("正在保存 MetalHUD 预设", "Saving MetalHUD preset")) {
            let preset = try await self.metalHUDPresetStore.importPreset(from: presetURL, forApplicationPath: app.path)
            guard let index = self.configuration.recentMetalHUDApps.firstIndex(where: { $0.path == app.path }) else {
                throw ToolboxError.invalidPath(app.path)
            }
            self.configuration.recentMetalHUDApps[index].preset = preset
            self.saveConfiguration()
            return tr("已为 \(app.displayName) 保存 MetalHUD 预设", "Saved a MetalHUD preset for \(app.displayName)")
        }
    }

    func removeMetalHUDPreset(for app: RecentMetalHUDApp) {
        guard let index = configuration.recentMetalHUDApps.firstIndex(where: { $0.path == app.path }) else { return }
        configuration.recentMetalHUDApps[index].preset = nil
        saveConfiguration()
    }

    func removeRecentMetalHUDApp(_ app: RecentMetalHUDApp) {
        configuration.recentMetalHUDApps.removeAll { $0.path == app.path }
        saveConfiguration()
    }

    func chooseCrossOverBottleMetalHUDPreset() {
        Task {
            do {
                crossOverBottles = try await crossOverBottleService.bottles()
                guard !crossOverBottles.isEmpty else {
                    throw ToolboxError.commandFailed(tr("未找到有效的 CrossOver 容器", "No valid CrossOver bottles found"))
                }
                showingCrossOverBottleSelection = true
            } catch { report(error) }
        }
    }

    func chooseMetalHUDPreset(forCrossOverBottle bottle: CrossOverBottle) {
        let panel = NSOpenPanel()
        panel.title = tr("选择已导出的 MetalHUD 预设", "Choose an exported MetalHUD preset")
        panel.prompt = tr("应用到容器", "Apply to Bottle")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let presetURL = panel.url else { return }

        runTask(tr("正在保存 MetalHUD 预设并更新 CrossOver 容器", "Saving MetalHUD preset and updating CrossOver bottle")) {
            let preset = try await self.metalHUDPresetStore.importPreset(from: presetURL, forApplicationPath: bottle.path)
            try await self.crossOverBottleService.applyMetalHUDPreset(URL(fileURLWithPath: preset.path), to: bottle)
            return tr("已为 CrossOver 容器 \(bottle.displayName) 应用 MetalHUD 预设", "Applied the MetalHUD preset to CrossOver bottle \(bottle.displayName)")
        }
    }

    func increaseCrossOverPriority() {
        runTask(tr("正在检测 CrossOver", "Detecting CrossOver")) {
            let processes = try await self.gamingService.wineProcesses(crossOverOnly: true)
            DiagnosticFileLogger.write("Detected CrossOver process count: \(processes.count)")
            guard !processes.isEmpty else {
                throw ToolboxError.commandFailed(tr("未检测到 CrossOver 或 Wine 进程", "No CrossOver or Wine process found"))
            }
            self.status.phase = .awaitingAuthorization
            try await self.privileged.perform(.renice(processes.map(\.pid), -20))
            return tr("已提高 \(processes.count) 个进程的优先级", "Updated \(processes.count) processes")
        }
    }

    func loadProcessesForManualSelection() {
        showingProcessSelection = true
        runningProcesses = []
        selectedProcessIDs.removeAll()
        Task {
            do {
                let processes = try await gamingService.runningProcesses()
                runningProcesses = processes.map { process in
                    SystemProcess(
                        pid: process.pid,
                        parentPID: process.parentPID,
                        command: process.command,
                        cpuUsage: process.cpuUsage,
                        applicationPath: NSRunningApplication(processIdentifier: process.pid)?.bundleURL?.path
                    )
                }
            }
            catch { report(error) }
        }
    }

    func increaseSelectedProcessPriority(lowerPriority: Bool = false) {
        let identifiers = Array(selectedProcessIDs)
        guard !identifiers.isEmpty else { return }
        showingProcessSelection = false
        let priority = lowerPriority ? Int32(20) : Int32(-20)
        runTask(lowerPriority ? tr("正在降低所选进程优先级", "Lowering selected process priority") : tr("正在提高所选进程优先级", "Increasing selected process priority")) {
            self.status.phase = .awaitingAuthorization
            try await self.privileged.perform(.renice(identifiers, priority))
            return lowerPriority
                ? tr("已将 \(identifiers.count) 个进程的优先级降至最低", "Lowered \(identifiers.count) selected process(es) to the lowest priority")
                : tr("已提高 \(identifiers.count) 个进程的优先级", "Updated \(identifiers.count) selected process(es)")
        }
    }

    func isFavoriteProcess(_ process: SystemProcess) -> Bool {
        configuration.favoriteProcessNames.contains(process.displayName)
    }

    func toggleFavoriteProcess(_ process: SystemProcess) {
        if isFavoriteProcess(process) {
            removeFavoriteProcess(process.displayName)
        } else {
            addFavoriteProcess(process.displayName)
        }
    }

    func addFavoriteProcess(_ name: String) {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !configuration.favoriteProcessNames.contains(normalized),
              configuration.favoriteProcessNames.count < ConfigurationStore.maxFavoriteProcesses else { return }
        configuration.favoriteProcessNames.append(normalized)
        saveConfiguration()
    }

    func removeFavoriteProcess(_ name: String) {
        configuration.favoriteProcessNames.removeAll { $0 == name }
        saveConfiguration()
    }

    func increaseFavoriteProcessPriority(lowerPriority: Bool = false) {
        let favoriteNames = configuration.favoriteProcessNames
        guard !favoriteNames.isEmpty else { return }
        showingProcessSelection = false
        let priority = lowerPriority ? Int32(20) : Int32(-20)
        runTask(lowerPriority ? tr("正在降低常用进程优先级", "Lowering favorite process priority") : tr("正在优化常用进程", "Optimizing favorite processes")) {
            let processes = try await self.gamingService.runningProcesses()
            let matches = GamingService.matchingFavoriteProcesses(processes, favoriteNames: favoriteNames)
            guard !matches.isEmpty else {
                throw ToolboxError.commandFailed(tr("未检测到收藏的常用进程", "No saved favorite process is running"))
            }
            guard matches.count <= ConfigurationStore.maxFavoriteProcesses else {
                throw ToolboxError.commandFailed(tr("匹配的常用进程超过 64 个，请编辑常用进程后重试", "More than 64 favorite processes matched; edit favorites and try again"))
            }
            self.status.phase = .awaitingAuthorization
            try await self.privileged.perform(.renice(matches.map(\.pid), priority))
            return lowerPriority
                ? tr("已将 \(matches.count) 个常用进程的优先级降至最低", "Lowered \(matches.count) favorite process(es) to the lowest priority")
                : tr("已提高 \(matches.count) 个常用进程的优先级", "Updated \(matches.count) favorite process(es)")
        }
    }

    func setHoYoWaitSeconds(_ seconds: Int) {
        guard [10, 15, 20].contains(seconds) else { return }
        configuration.hoYoWaitSeconds = seconds
        saveConfiguration()
    }

    func setDoesNotRaiseHoYoPriority(_ enabled: Bool) {
        configuration.doesNotRaiseHoYoPriority = enabled
        saveConfiguration()
    }

    func startHoYoAssistant() {
        guard hoyoTask == nil else { return }
        let waitSeconds = configuration.hoYoWaitSeconds
        let doesNotRaisePriority = configuration.doesNotRaiseHoYoPriority
        isHoYoAssistantRunning = true
        status = TaskStatus(phase: .awaitingAuthorization, message: tr("正在启用系统辅助服务", "Enabling system helper"), progress: 0, log: [])
        hoyoTask = Task {
            do {
                try await gamingService.beginHoYoLaunch()
                status.phase = .running
                status.log.append(tr("已写入临时 hosts，等待 \(waitSeconds) 秒", "Temporary hosts applied; waiting \(waitSeconds) seconds"))
                for remaining in stride(from: waitSeconds, through: 1, by: -1) {
                    try Task.checkCancellation()
                    status.message = tr("请启动游戏，剩余 \(remaining) 秒", "Launch the game; \(remaining) seconds remaining")
                    status.progress = Double(waitSeconds - remaining) / Double(waitSeconds)
                    try await Task.sleep(for: .seconds(1))
                }

                try Task.checkCancellation()
                guard !doesNotRaisePriority else {
                    try await gamingService.finishHoYoLaunch()
                    status = TaskStatus(
                        phase: .succeeded,
                        message: tr("倒计时结束，未提升 Wine 进程优先级并已恢复 hosts", "Countdown complete; Wine process priority was unchanged and hosts were restored"),
                        progress: 1,
                        log: status.log
                    )
                    return
                }

                status.message = tr("正在检测 Wine 进程", "Detecting Wine processes")
                status.log.append(tr("等待完成，开始检测 Wine 进程", "Wait complete; detecting Wine processes"))
                let processes = try await gamingService.wineProcesses()
                DiagnosticFileLogger.write("HoYo Wine check after \(waitSeconds) seconds: \(processes.count) process(es)")
                guard !processes.isEmpty else {
                    throw ToolboxError.commandFailed(tr("\(waitSeconds) 秒后未检测到 Wine 进程", "No Wine process detected after \(waitSeconds) seconds"))
                }

                status.phase = .awaitingAuthorization
                try await privileged.perform(.renice(processes.map(\.pid), -20))
                try await gamingService.finishHoYoLaunch()
                status = TaskStatus(
                    phase: .succeeded,
                    message: tr("已优化 \(processes.count) 个进程并恢复 hosts", "Updated \(processes.count) processes and restored hosts"),
                    progress: 1,
                    log: status.log
                )
            } catch is CancellationError {
                try? await gamingService.finishHoYoLaunch()
                status = TaskStatus(phase: .cancelled, message: tr("已取消并恢复 hosts", "Cancelled and restored hosts"))
            } catch {
                try? await gamingService.finishHoYoLaunch()
                report(error)
            }
            hoyoTask = nil
            isHoYoAssistantRunning = false
        }
    }

    func cancelHoYoAssistant() { hoyoTask?.cancel() }

    func loadDisks() {
        showingDiskManager = true
        Task {
            do {
                disks = try await diskService.listEligibleVolumes()
                for preset in configuration.diskPresets { if let path = preset.mountPath { diskPaths[preset.diskIdentifier] = path } }
            } catch { report(error) }
        }
    }

    func choosePath(for diskID: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = tr("选择", "Choose")
        if panel.runModal() == .OK, let url = panel.url { diskPaths[diskID] = url.path }
    }

    func mountSelectedDisks() {
        let assignments = selectedDiskIDs.compactMap { id -> (String, String)? in
            guard let path = diskPaths[id], !path.isEmpty else { return nil }
            return (id, path)
        }
        guard assignments.count == selectedDiskIDs.count, !assignments.isEmpty else {
            report(ToolboxError.invalidPath(tr("请为每个磁盘选择路径", "Choose a path for every volume")))
            return
        }
        runTask(tr("正在挂载磁盘", "Mounting volumes")) {
            for (_, path) in assignments {
                if !FileManager.default.fileExists(atPath: path) { try await self.privileged.perform(.createDirectory(path)) }
            }
            let results = await self.diskService.mountBatch(assignments)
            let failures = results.compactMap { key, result -> String? in if case .failure = result { return key }; return nil }
            guard failures.isEmpty else { throw ToolboxError.commandFailed(tr("挂载失败并已回滚：\(failures.joined(separator: ", "))", "Mount failed and rolled back: \(failures.joined(separator: ", "))")) }
            self.rememberRestorableMounts(assignments)
            return tr("已成功挂载 \(assignments.count) 个卷", "Mounted \(assignments.count) volume(s)")
        }
    }

    func restoreSelectedDisks() {
        runTask(tr("正在恢复默认挂载", "Restoring default mounts")) {
            for identifier in self.selectedDiskIDs { try await self.diskService.restoreDefaultMount(identifier) }
            let selectedUUIDs = Set(self.disks.filter { self.selectedDiskIDs.contains($0.id) }.compactMap(\.volumeUUID))
            self.configuration.restorableDiskMounts.removeAll {
                self.selectedDiskIDs.contains($0.diskIdentifier) || ($0.volumeUUID.map(selectedUUIDs.contains) ?? false)
            }
            self.saveConfiguration()
            return tr("已恢复系统默认挂载路径", "Default mounts restored")
        }
    }

    func saveDiskPreset(_ identifier: String) {
        configuration.diskPresets.removeAll { $0.diskIdentifier == identifier }
        configuration.diskPresets.insert(DiskPreset(diskIdentifier: identifier, mountPath: diskPaths[identifier]), at: 0)
        configuration.diskPresets = Array(configuration.diskPresets.prefix(ConfigurationStore.maxPresets))
        saveConfiguration()
    }

    func deleteDiskPreset(_ identifier: String) {
        configuration.diskPresets.removeAll { $0.diskIdentifier == identifier }
        saveConfiguration()
    }

    func setAutomaticallyRestoreMountsOnLaunch(_ enabled: Bool) {
        configuration.automaticallyRestoreMountsOnLaunch = enabled
        saveConfiguration()
        startAutomaticMountMonitoring()
    }

    func restorePreviousMounts() {
        status = TaskStatus(phase: .running, message: tr("正在恢复上次挂载", "Restoring previous mounts"))
        Task {
            do {
                let availableVolumes = try await diskService.listEligibleVolumes()
                disks = availableVolumes
                enrichRestorableMountUUIDs(from: availableVolumes)
                guard !configuration.restorableDiskMounts.isEmpty else {
                    throw ToolboxError.commandFailed(tr("没有可恢复的挂载记录", "No previous mounts to restore"))
                }
                await restoreMounts(from: availableVolumes, manual: true)
            } catch { report(error) }
        }
    }

    func addDefaultPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = tr("添加", "Add")
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        configuration.defaultPaths.removeAll { $0 == path }
        configuration.defaultPaths.insert(path, at: 0)
        configuration.defaultPaths = Array(configuration.defaultPaths.prefix(ConfigurationStore.maxDefaultPaths))
        saveConfiguration()
    }

    func deleteDefaultPath(_ path: String) {
        configuration.defaultPaths.removeAll { $0 == path }
        saveConfiguration()
    }

    func importWallpaper() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.title = tr("导入壁纸", "Import Wallpaper")
        panel.prompt = tr("导入", "Import")
        guard panel.runModal() == .OK, let source = panel.url else { return }

        do {
            let oldPath = configuration.customWallpaperPath
            let destination = try wallpaperService.importWallpaper(from: source, replacing: oldPath)
            configuration.customWallpaperPath = destination.path
            saveConfiguration()
            status = TaskStatus(phase: .succeeded, message: tr("已导入自定义背景", "Custom wallpaper imported"), progress: 1)
            DiagnosticFileLogger.write("Custom wallpaper imported: \(destination.path)")
        } catch {
            report(error)
        }
    }

    func resetWallpaper() {
        let oldPath = configuration.customWallpaperPath
        configuration.customWallpaperPath = nil
        saveConfiguration()
        do {
            let removed = try wallpaperService.removeManagedWallpaper(at: oldPath)
            DiagnosticFileLogger.write("Custom wallpaper cleared; removed file: \(removed)")
        } catch {
            DiagnosticFileLogger.write("Custom wallpaper cleared; failed to remove file: \(error.localizedDescription)")
        }
        status = TaskStatus(phase: .succeeded, message: tr("已恢复默认背景", "Default background restored"), progress: 1)
    }

    func prepareCacheScan() {
        status = TaskStatus(phase: .running, message: tr("正在扫描缓存", "Scanning caches"))
        Task {
            cacheScan = await cacheService.scan(excludingSensitiveFiles: configuration.excludesSensitiveCacheFiles)
            cacheConfirmationStage = 1
            showingCacheConfirmation = true
            status = TaskStatus()
        }
    }

    func confirmCacheCleaning() {
        guard let scan = cacheScan, scan.inaccessibleTargets.isEmpty else { return }
        if cacheConfirmationStage == 1, !configuration.excludesSensitiveCacheFiles {
            cacheConfirmationStage = 2
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.showingCacheConfirmation = true }
            return
        }
        runTask(tr("正在清理缓存", "Cleaning caches")) {
            if !scan.systemTargets.isEmpty { self.status.phase = .awaitingAuthorization }
            let result = try await self.cacheService.clear(scan)
            for failure in result.failedItems {
                DiagnosticFileLogger.write("Cache cleanup failed: \(failure.path.path) - \(failure.reason)")
            }
            if result.failedItems.isEmpty {
                return tr("缓存清理完成，已清理 \(result.removedCount) 项", "Cache cleaning completed; removed \(result.removedCount) item(s)")
            }
            return tr(
                "缓存清理完成，已清理 \(result.removedCount) 项，\(result.failedItems.count) 项无法清理",
                "Cache cleaning completed; removed \(result.removedCount) item(s), \(result.failedItems.count) item(s) could not be removed"
            )
        }
    }

    func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    func setExcludesSensitiveCacheFiles(_ enabled: Bool) {
        configuration.excludesSensitiveCacheFiles = enabled
        saveConfiguration()
    }

    func toggleSteamDeck() {
        runTask(tr("正在读取设备名称", "Reading hostnames")) {
            let current = try await self.hostnameService.current()
            self.status.phase = .awaitingAuthorization
            if current.computerName == "steamdeck" {
                guard let backup = self.configuration.hostnameBackup else { throw ToolboxError.commandFailed(tr("找不到原始设备名称备份", "Hostname backup is missing")) }
                try await self.hostnameService.restore(backup)
                self.configuration.hostnameBackup = nil
                self.saveConfiguration()
                return tr("已恢复原始设备名称", "Original hostnames restored")
            }
            self.configuration.hostnameBackup = current
            self.saveConfiguration()
            try await self.hostnameService.setSteamDeck()
            return tr("已切换至 SteamDeck 模式", "SteamDeck mode enabled")
        }
    }

    func requestDiagnosticsExport() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = tr("Mac游戏工具箱-诊断-\(Self.diagnosticTimestamp()).txt", "MacGameToolbox-Diagnostics-\(Self.diagnosticTimestamp()).txt")
        panel.title = tr("导出诊断日志", "Export Diagnostics")
        panel.prompt = tr("导出", "Export")
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        exportDiagnostics(to: destination)
    }

    func repairCoreFeatures() {
        runTask(tr("正在修复核心功能", "Repairing core features")) {
            self.status.phase = .awaitingAuthorization
            try await Self.runCoreFeatureRepairScript()
            return tr("核心功能已修复", "Core features repaired")
        }
    }

    func exportDiagnostics(to destination: URL) {
        let currentStatus = status
        let currentConfiguration = configuration
        let helperStatus = privileged.diagnosticStatus()
        status = TaskStatus(phase: .running, message: tr("正在收集诊断日志", "Collecting diagnostics"))
        DiagnosticFileLogger.write("Diagnostics export started: \(destination.path)")
        do {
            try (tr("诊断日志正在收集，请稍候…", "Diagnostics collection in progress…") + "\n").write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            report(error)
            return
        }
        Task {
            let diagnosticsText = await diagnosticsService.collect(taskStatus: currentStatus, helperStatus: helperStatus, configuration: currentConfiguration)
            do {
                try diagnosticsText.write(to: destination, atomically: true, encoding: .utf8)
                status = TaskStatus(phase: .succeeded, message: tr("诊断日志已导出：\(destination.path)", "Diagnostics exported: \(destination.path)"))
                DiagnosticFileLogger.write("Diagnostics exported: \(destination.path)")
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch { report(error) }
        }
    }

    private static func diagnosticTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func runCoreFeatureRepairScript() async throws {
        let shellScript = """
        /bin/launchctl bootout system /Library/LaunchDaemons/com.iven.macgametoolbox.helper.v8.plist 2>/dev/null || true
        /bin/launchctl enable system/com.iven.macgametoolbox.helper.v8
        /bin/launchctl bootstrap system /Library/LaunchDaemons/com.iven.macgametoolbox.helper.v8.plist
        """
        let appleScript = """
        on run argv
            do shell script item 1 of argv with administrator privileges
        end run
        """

        let result: (Int32, String, String) = try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", appleScript, "--", shellScript]
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()
            let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let error = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (process.terminationStatus, output, error)
        }.value

        guard result.0 == 0 else {
            if result.2.contains("(-128)") { throw ToolboxError.authorizationCancelled }
            let message = result.2.isEmpty ? result.1 : result.2
            throw ToolboxError.commandFailed(message.isEmpty ? tr("核心功能修复失败", "Core feature repair failed") : message)
        }
    }

    private func startAutomaticMountMonitoring() {
        automaticMountTask?.cancel()
        automaticMountTask = nil
        guard configuration.automaticallyRestoreMountsOnLaunch else { return }
        automaticMountTask = Task { [weak self] in
            await self?.monitorDisksAndRestoreMounts()
        }
    }

    private func monitorDisksAndRestoreMounts() async {
        let clock = ContinuousClock()
        let startedAt = clock.now
        var nextLogSecond = 0
        while !Task.isCancelled, configuration.automaticallyRestoreMountsOnLaunch {
            do {
                let availableVolumes = try await diskService.listEligibleVolumes()
                disks = availableVolumes
                enrichRestorableMountUUIDs(from: availableVolumes)
                let elapsedSeconds = Int(startedAt.duration(to: clock.now).components.seconds)
                if elapsedSeconds >= nextLogSecond {
                    let identifiers = availableVolumes.map {
                        "\($0.id)[\($0.volumeUUID ?? "no-uuid")]=\($0.mountPoint ?? "unmounted")"
                    }.joined(separator: ", ")
                    DiagnosticFileLogger.write("Automatic disk scan \(elapsedSeconds)s: \(identifiers.isEmpty ? "no eligible volumes" : identifiers)")
                    nextLogSecond = max(10, ((elapsedSeconds / 10) + 1) * 10)
                }
                if elapsedSeconds >= 10 { await restoreMounts(from: availableVolumes) }
            } catch {
                DiagnosticFileLogger.write("Automatic disk refresh failed: \(error.localizedDescription)")
            }
            do { try await Task.sleep(for: .seconds(1)) }
            catch { return }
        }
    }

    private func restoreMounts(from volumes: [DiskVolume], manual: Bool = false) async {
        let assignments = configuration.restorableDiskMounts.compactMap { preset -> (String, String)? in
            guard let path = preset.mountPath,
                  let volume = DiskService.matchingVolume(for: preset, in: volumes),
                  volume.mountPoint != path,
                  FileManager.default.fileExists(atPath: path) else { return nil }
            return (volume.id, path)
        }
        guard !assignments.isEmpty else {
            if manual {
                report(ToolboxError.commandFailed(tr("没有找到可恢复的磁盘和路径", "No matching volume and path found to restore")))
                return
            }
            if !configuration.restorableDiskMounts.isEmpty {
                DiagnosticFileLogger.write("Automatic mount restore waiting: no matching unmounted target with an existing path")
            }
            return
        }

        status = TaskStatus(phase: .running, message: tr("正在自动恢复上次挂载", "Restoring previous mounts"))
        let results = await diskService.mountBatch(assignments)
        let succeeded = assignments.filter {
            guard case .success? = results[$0.0] else { return false }
            return true
        }
        if succeeded.count == assignments.count {
            rememberRestorableMounts(succeeded)
            status = TaskStatus(phase: .succeeded, message: tr("已自动恢复 \(succeeded.count) 个卷的挂载", "Restored \(succeeded.count) previous mount(s)"), progress: 1)
            DiagnosticFileLogger.write("Automatically restored \(succeeded.count) mount(s)")
        } else {
            report(ToolboxError.commandFailed(tr("自动恢复上次挂载失败", "Failed to restore previous mounts")))
        }
    }

    private func rememberRestorableMounts(_ assignments: [(String, String)]) {
        let identifiers = Set(assignments.map(\.0))
        let presets = assignments.map { identifier, path in
            let volume = disks.first { $0.id == identifier }
            return DiskPreset(diskIdentifier: identifier, volumeUUID: volume?.volumeUUID, mountPath: path)
        }
        let volumeUUIDs = Set(presets.compactMap(\.volumeUUID))
        configuration.restorableDiskMounts.removeAll {
            identifiers.contains($0.diskIdentifier) || ($0.volumeUUID.map(volumeUUIDs.contains) ?? false)
        }
        configuration.restorableDiskMounts.insert(contentsOf: presets, at: 0)
        saveConfiguration()
    }

    private func enrichRestorableMountUUIDs(from volumes: [DiskVolume]) {
        var changed = false
        for index in configuration.restorableDiskMounts.indices where configuration.restorableDiskMounts[index].volumeUUID == nil {
            let identifier = configuration.restorableDiskMounts[index].diskIdentifier
            guard let volumeUUID = volumes.first(where: { $0.id == identifier })?.volumeUUID else { continue }
            configuration.restorableDiskMounts[index].volumeUUID = volumeUUID
            changed = true
            DiagnosticFileLogger.write("Added volume UUID to automatic restore record: \(identifier) -> \(volumeUUID)")
        }
        if changed { saveConfiguration() }
    }

    private func saveConfiguration() {
        let value = configuration
        Task { try? await configurationStore.save(value) }
    }

    private func rememberMetalHUDApp(_ applicationURL: URL) {
        let normalizedURL = applicationURL.standardizedFileURL
        let displayName = FileManager.default.displayName(atPath: normalizedURL.path)
        let name = (displayName as NSString).deletingPathExtension
        let existingPreset = configuration.recentMetalHUDApps.first(where: { $0.path == normalizedURL.path })?.preset
        configuration.recentMetalHUDApps.removeAll { $0.path == normalizedURL.path }
        configuration.recentMetalHUDApps.insert(RecentMetalHUDApp(path: normalizedURL.path, displayName: name, preset: existingPreset), at: 0)
        configuration.recentMetalHUDApps = Array(configuration.recentMetalHUDApps.prefix(ConfigurationStore.maxRecentMetalHUDApps))
        saveConfiguration()
    }

    private func runTask(_ message: String, operation: @escaping @MainActor () async throws -> String) {
        status = TaskStatus(phase: .running, message: message)
        DiagnosticFileLogger.write("Task started: \(message)")
        Task {
            do {
                let result = try await operation()
                status = TaskStatus(phase: .succeeded, message: result, progress: 1)
                DiagnosticFileLogger.write("Task succeeded: \(result)")
            } catch is CancellationError {
                status = TaskStatus(phase: .cancelled, message: tr("已取消", "Cancelled"))
            } catch { report(error) }
        }
    }

    private func report(_ error: Error) {
        status = TaskStatus(phase: error is CancellationError ? .cancelled : .failed, message: error.localizedDescription)
        DiagnosticFileLogger.write("Task failed: \(error.localizedDescription)")
    }
}
