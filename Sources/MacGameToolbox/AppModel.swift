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
    @Published var activeDiskID: String?
    @Published var selectedDiskIDs = Set<String>() // Explicit batch checkboxes only.
    @Published private(set) var isDiskBusy = false
    @Published private(set) var isRefreshingDisks = false
    @Published private(set) var diskOperationResult: DiskBatchResult?
    @Published private(set) var diskRefreshError: String?
    private var diskDraftsByUUID: [String: String] = [:]
    private var automaticRestoreNotBefore = Date.distantPast
    @Published var diskPaths: [String: String] = [:]
    @Published var metalHUDEnabled = false
    @Published var cacheScan: CacheScan?
    @Published private(set) var isCacheBusy = false
    @Published private(set) var cacheCleanupResult: CacheCleanupResult?
    @Published var showingCacheConfirmation = false
    @Published var cacheConfirmationStage = 0
    @Published var isHoYoAssistantRunning = false
    @Published var runningProcesses: [SystemProcess] = []
    @Published var selectedProcessIDs = Set<Int32>()
    @Published var crossOverBottles: [CrossOverBottle] = []
    @Published var iosDevices: [IOSDevice] = []
    @Published var iosApps: [IOSInstalledApp] = []
    @Published var selectedIOSDeviceID: String?
    @Published var selectedIOSBundleIdentifier: String?
    @Published var isRefreshingIOSDevices = false
    @Published var isRefreshingIOSApps = false
    @Published var iosLaunchArgumentsApp: IOSInstalledApp?
    @Published var iosLaunchArgumentsText = ""

    private let privileged = PrivilegedHelperClient()
    private let configurationStore: ConfigurationStore
    private let diskService: DiskService
    private let gamingService: GamingService
    private let hostnameService: HostnameService
    private let cacheService: CacheService
    private let metalHUDPresetStore: MetalHUDPresetStore
    private let crossOverBottleService: CrossOverBottleService
    private let diagnosticsService = DiagnosticsService()
    private var hoyoTask: Task<Void, Never>?
    private var automaticMountTask: Task<Void, Never>?
    private var didLaunch = false
    private let mountDirectoryCreator: (@MainActor (String) async throws -> Void)?

    init(configurationStore: ConfigurationStore = ConfigurationStore(), launchAutomatically: Bool = true, diskService: DiskService = DiskService(), mountDirectoryCreator: (@MainActor (String) async throws -> Void)? = nil, gamingService: GamingService? = nil) {
        self.configurationStore = configurationStore
        self.diskService = diskService
        self.mountDirectoryCreator = mountDirectoryCreator
        self.gamingService = gamingService ?? GamingService(privileged: privileged)
        hostnameService = HostnameService(privileged: privileged)
        cacheService = CacheService(privileged: privileged)
        metalHUDPresetStore = MetalHUDPresetStore()
        crossOverBottleService = CrossOverBottleService()
        if launchAutomatically { launch() }
    }

    func launch() {
        guard !didLaunch else { return }
        didLaunch = true
        DiagnosticFileLogger.write("App launched, version \(GitHubReleaseChecker.currentVersion)")
        Task {
            do {
                configuration = try await configurationStore.load()
            } catch { report(error) }
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

    func chooseMetalHUDApps() {
        let panel = NSOpenPanel()
        panel.title = tr("添加 App", "Add App")
        panel.prompt = tr("添加", "Add")
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK else { return }
        addMetalHUDApps(panel.urls)
    }

    /// Picker and Finder drops share the same add-only path. Launching is a separate explicit action.
    @discardableResult
    func addMetalHUDApps(_ urls: [URL]) -> Bool {
        var added = 0
        var failures: [String] = []
        for url in urls {
            do {
                let application = try Self.metalHUDShortcutURL(url)
                rememberMetalHUDApp(application, save: false)
                added += 1
            } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        guard added > 0 else {
            report(ToolboxError.invalidPath(tr("请添加有效的 .app 应用", "Add a valid .app application")))
            return false
        }
        saveConfiguration()
        status = TaskStatus(phase: .succeeded,
                            message: tr("已添加快捷方式，点击卡片右上角启动", "Shortcut added. Use the play button at the top right of the card to launch."),
                            log: failures)
        return true
    }

    static func metalHUDShortcutURL(_ input: URL) throws -> URL {
        guard input.isFileURL else { throw ToolboxError.invalidPath(input.absoluteString) }
        var url = input
        if (try? url.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == true {
            url = try URL(resolvingAliasFileAt: url, options: [.withoutUI])
        }
        url = url.standardizedFileURL.resolvingSymlinksInPath()
        guard url.pathExtension.lowercased() == "app",
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              let bundle = Bundle(url: url),
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ToolboxError.invalidPath(input.path)
        }
        return url
    }

    func refreshCrossOverBottles() {
        Task {
            do {
                crossOverBottles = try await crossOverBottleService.bottles()
                if crossOverBottles.isEmpty {
                    throw ToolboxError.commandFailed(
                        tr("未找到有效的 CrossOver 容器", "No valid CrossOver bottles found")
                    )
                }
            } catch {
                crossOverBottles = []
                report(error)
            }
        }
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
        iosLaunchArgumentsApp = nil
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

    func increaseCrossOverPriority(priority level: ProcessPriorityLevel) {
        runTask(tr("正在检测 CrossOver", "Detecting CrossOver")) {
            let processes = try await self.gamingService.wineProcesses(crossOverOnly: true)
            DiagnosticFileLogger.write("Detected CrossOver process count: \(processes.count)")
            guard !processes.isEmpty else {
                throw ToolboxError.commandFailed(tr("未检测到 CrossOver 或 Wine 进程", "No CrossOver or Wine process found"))
            }
            self.status.phase = .awaitingAuthorization
            try await self.privileged.perform(.renice(processes.map(\.pid), level.rawValue))
            return tr("优先级已更新：", "Priority updated:")
                + " \(processes.count) · \(level.localizedDisplayName)"
        }
    }

    func loadProcessesForManualSelection() {
        refreshRunningProcesses()
    }

    func refreshRunningProcesses() {
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

    func increaseSelectedProcessPriority(priority level: ProcessPriorityLevel) {
        let identifiers = Array(selectedProcessIDs)
        guard !identifiers.isEmpty else { return }
        runTask(tr("正在应用所选进程优先级", "Applying selected process priority")) {
            self.status.phase = .awaitingAuthorization
            try await self.privileged.perform(.renice(identifiers, level.rawValue))
            return tr("优先级已更新：", "Priority updated:")
                + " \(identifiers.count) · \(level.localizedDisplayName)"
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

    func increaseFavoriteProcessPriority(priority level: ProcessPriorityLevel) {
        let favoriteNames = configuration.favoriteProcessNames
        guard !favoriteNames.isEmpty else { return }
        runTask(tr("正在优化常用进程", "Optimizing favorite processes")) {
            let processes = try await self.gamingService.runningProcesses()
            let matches = GamingService.matchingFavoriteProcesses(processes, favoriteNames: favoriteNames)
            guard !matches.isEmpty else {
                throw ToolboxError.commandFailed(tr("未检测到收藏的常用进程", "No saved favorite process is running"))
            }
            guard matches.count <= ConfigurationStore.maxFavoriteProcesses else {
                throw ToolboxError.commandFailed(tr("匹配的常用进程超过 64 个，请编辑常用进程后重试", "More than 64 favorite processes matched; edit favorites and try again"))
            }
            self.status.phase = .awaitingAuthorization
            try await self.privileged.perform(.renice(matches.map(\.pid), level.rawValue))
            return tr("优先级已更新：", "Priority updated:")
                + " \(matches.count) · \(level.localizedDisplayName)"
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
        refreshDisks()
    }

    func refreshDisks() {
        guard !isDiskBusy, !isRefreshingDisks else { return }
        isRefreshingDisks = true
        Task {
            defer { isRefreshingDisks = false }
            do { applyDiskRefresh(try await diskService.listEligibleVolumes()) }
            catch { report(error) }
        }
    }

    func applyDiskRefresh(_ available: [DiskVolume]) {
        let previous = disks
        let focused = previous.first { $0.id == activeDiskID }
        let counts = Dictionary(available.compactMap { $0.volumeUUID?.lowercased() }.map { ($0, 1) }, uniquingKeysWith: +)
        let oldCounts = Dictionary(previous.compactMap { $0.volumeUUID?.lowercased() }.map { ($0, 1) }, uniquingKeysWith: +)
        for volume in previous {
            if let uuid = volume.volumeUUID?.lowercased(), oldCounts[uuid] == 1, let draft = diskPaths[volume.id] { diskDraftsByUUID[uuid] = draft }
        }
        func rematch(_ volume: DiskVolume) -> DiskVolume? {
            if let exact = available.first(where: { DiskService.sameIdentity($0, volume) }) { return exact }
            if let uuid = volume.volumeUUID, counts[uuid.lowercased()] == 1 {
                return available.first { $0.volumeUUID?.caseInsensitiveCompare(uuid) == .orderedSame }
            }
            return nil
        }
        selectedDiskIDs = Set(previous.filter { selectedDiskIDs.contains($0.id) }.compactMap { rematch($0)?.id })
        activeDiskID = focused.flatMap { rematch($0)?.id } ?? available.first?.id
        var drafts: [String: String] = [:]
        for volume in available {
            if let old = previous.first(where: { rematch($0)?.id == volume.id }), let path = diskPaths[old.id] {
                drafts[volume.id] = path
            } else if let uuid = volume.volumeUUID, counts[uuid.lowercased()] == 1, let path = diskDraftsByUUID[uuid.lowercased()] {
                drafts[volume.id] = path
            } else if let preset = configuration.diskPresets.first(where: { DiskService.matchingVolume(for: $0, in: available)?.id == volume.id }) {
                drafts[volume.id] = preset.mountPath
            }
        }
        diskPaths = drafts
        disks = available
    }

    func choosePath(for diskID: String) {
        guard !isDiskBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = tr("选择", "Choose")
        if panel.runModal() == .OK, let url = panel.url { diskPaths[diskID] = url.path }
    }

    func mountDisks(_ requests: [DiskMountRequest]) {
        guard !isDiskBusy, !isRefreshingDisks, !requests.isEmpty else { return }
        isDiskBusy = true
        diskOperationResult = nil
        diskRefreshError = nil
        status = TaskStatus(phase: .running, message: tr("正在挂载磁盘", "Mounting volumes"))
        Task {
            defer { isDiskBusy = false }
            do {
                let available = try await diskService.listEligibleVolumes()
                let prepared = try DiskService.validateMountRequests(requests, volumes: available)
                // All paths and identities are checked before requesting directory creation.
                // Cancellation of administrator authorization stops before any unmount.
                for request in prepared where !FileManager.default.fileExists(atPath: request.path) {
                    if let mountDirectoryCreator { try await mountDirectoryCreator(request.path) }
                    else {
                        do { try FileManager.default.createDirectory(atPath: request.path, withIntermediateDirectories: true) }
                        catch { try await privileged.perform(.createDirectory(request.path)) }
                    }
                }
                let result = await diskService.mountVolumes(prepared)
                rememberRestorableMounts(prepared.filter { request in result.items.contains { $0.volume.id == request.volume.id && $0.succeeded } })
                await finishDiskOperation(result)
            } catch {
                automaticRestoreNotBefore = Date().addingTimeInterval(30)
                diskOperationResult = .rejected(requests.map(\.volume), message: error.localizedDescription)
                report(error)
            }
        }
    }

    func restoreDisks(_ volumes: [DiskVolume]) {
        guard !isDiskBusy, !isRefreshingDisks, !volumes.isEmpty else { return }
        isDiskBusy = true
        diskOperationResult = nil
        diskRefreshError = nil
        status = TaskStatus(phase: .running, message: tr("正在恢复默认挂载", "Restoring default mounts"))
        Task {
            defer { isDiskBusy = false }
            let result = await diskService.restoreVolumes(volumes)
            let restored = result.items.filter(\.succeeded).map(\.volume)
            configuration.restorableDiskMounts.removeAll { record in
                restored.contains { volume in DiskService.matchingVolume(for: record, in: [volume]) != nil }
            }
            saveConfiguration()
            await finishDiskOperation(result)
        }
    }

    private func finishDiskOperation(_ result: DiskBatchResult) async {
        if !result.isSuccess { automaticRestoreNotBefore = Date().addingTimeInterval(30) }
        diskOperationResult = result
        do { applyDiskRefresh(try await diskService.listEligibleVolumes()) }
        catch {
            diskRefreshError = tr("操作已结束，但状态刷新失败，请手动刷新。", "The operation finished, but the status could not be refreshed. Refresh manually.") + " " + error.localizedDescription
            DiagnosticFileLogger.write("Post-operation disk refresh failed: \(error.localizedDescription)")
        }
        status = TaskStatus(phase: result.isSuccess && diskRefreshError == nil ? .succeeded : .failed,
                            message: diskRefreshError ?? (result.isSuccess ? tr("磁盘操作完成", "Volume operation completed") : tr("磁盘操作未全部完成，请查看逐项结果", "Volume operation incomplete; review the results")),
                            log: [result.description])
        DiagnosticFileLogger.write("Disk operation: \(result.description)")
    }

    func saveDiskPreset(_ identifier: String) {
        guard !isDiskBusy, let volume = disks.first(where: { $0.id == identifier }), let uuid = volume.volumeUUID else { return }
        do {
            let path = try InputValidation.normalizedAbsolutePath(diskPaths[identifier, default: ""])
            configuration.diskPresets.removeAll { $0.volumeUUID?.caseInsensitiveCompare(uuid) == .orderedSame }
            configuration.diskPresets.insert(DiskPreset(diskIdentifier: identifier, volumeUUID: uuid, mountPath: path), at: 0)
            configuration.diskPresets = Array(configuration.diskPresets.prefix(ConfigurationStore.maxPresets))
            saveConfiguration()
        } catch { report(error) }
    }

    func deleteDiskPreset(_ preset: DiskPreset, automatic: Bool = false) {
        guard !isDiskBusy else { return }
        if automatic { configuration.restorableDiskMounts.removeAll { $0 == preset } }
        else { configuration.diskPresets.removeAll { $0 == preset } }
        saveConfiguration()
    }

    func associateDiskRecord(_ preset: DiskPreset, with volume: DiskVolume, automatic: Bool) {
        guard !isDiskBusy, preset.volumeUUID == nil, let uuid = volume.volumeUUID,
              disks.contains(where: { DiskService.sameIdentity($0, volume) }) else { return }
        let updated = DiskPreset(diskIdentifier: volume.id, volumeUUID: uuid, mountPath: preset.mountPath)
        if automatic {
            configuration.restorableDiskMounts.removeAll { $0 == preset || $0.volumeUUID?.caseInsensitiveCompare(uuid) == .orderedSame }
            configuration.restorableDiskMounts.insert(updated, at: 0)
        } else {
            configuration.diskPresets.removeAll { $0 == preset || $0.volumeUUID?.caseInsensitiveCompare(uuid) == .orderedSame }
            configuration.diskPresets.insert(updated, at: 0)
            diskPaths[volume.id] = preset.mountPath
        }
        saveConfiguration()
    }

    func setAutomaticallyRestoreMountsOnLaunch(_ enabled: Bool) {
        configuration.automaticallyRestoreMountsOnLaunch = enabled
        saveConfiguration()
        startAutomaticMountMonitoring()
    }

    func restorePreviousMounts() {
        guard !isDiskBusy, !isRefreshingDisks else { return }
        isDiskBusy = true
        diskOperationResult = nil
        diskRefreshError = nil
        Task {
            defer { isDiskBusy = false }
            do {
                let available = try await diskService.listEligibleVolumes()
                applyDiskRefresh(available)
                await restoreMounts(from: available, manual: true)
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

    func prepareCacheScan() {
        guard !isCacheBusy else { return }
        isCacheBusy = true
        cacheScan = nil
        cacheCleanupResult = nil
        showingCacheConfirmation = false
        let excludesSensitiveFiles = configuration.excludesSensitiveCacheFiles
        status = TaskStatus(phase: .running, message: tr("正在扫描缓存", "Scanning caches"))
        Task {
            defer { isCacheBusy = false }
            cacheScan = await cacheService.scan(excludingSensitiveFiles: excludesSensitiveFiles)
            cacheConfirmationStage = 0
            status = TaskStatus()
        }
    }

    func requestCacheCleaning() {
        guard !isCacheBusy, cacheScan?.hasCleanableEntries == true else { return }
        cacheConfirmationStage = 1
        showingCacheConfirmation = true
    }

    func confirmCacheCleaning() {
        guard !isCacheBusy, let scan = cacheScan, scan.hasCleanableEntries else { return }
        if cacheConfirmationStage == 1, !configuration.excludesSensitiveCacheFiles {
            cacheConfirmationStage = 2
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard self.cacheScan == scan, !self.isCacheBusy else { return }
                self.showingCacheConfirmation = true
            }
            return
        }
        isCacheBusy = true
        runTask(tr("正在清理缓存", "Cleaning caches")) {
            defer {
                self.isCacheBusy = false
                self.cacheScan = nil
                self.showingCacheConfirmation = false
                self.cacheConfirmationStage = 0
            }
            if !scan.systemEntries.isEmpty { self.status.phase = .awaitingAuthorization }
            let result = try await self.cacheService.clear(scan)
            self.cacheCleanupResult = result
            for issue in result.failedItems + result.skippedItems {
                DiagnosticFileLogger.write("Cache cleanup skipped/failed: \(issue.path.path) - \(issue.reason)")
            }
            return tr(
                "缓存清理完成：已清理 \(result.removedCount) 项，跳过 \(result.skippedItems.count) 项，失败 \(result.failedItems.count) 项",
                "Cache cleanup completed: \(result.removedCount) removed, \(result.skippedItems.count) skipped, \(result.failedItems.count) failed"
            )
        }
    }

    func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    func setExcludesSensitiveCacheFiles(_ enabled: Bool) {
        guard !isCacheBusy, configuration.excludesSensitiveCacheFiles != enabled else { return }
        configuration.excludesSensitiveCacheFiles = enabled
        cacheScan = nil
        cacheCleanupResult = nil
        showingCacheConfirmation = false
        cacheConfirmationStage = 0
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
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/MacGameToolboxPrivilegedHelper")
        let quotedHelper = "'" + helper.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let quotedApp = "'" + Bundle.main.bundleURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        // Reinstall from the current bundle. The installer starts v10 before
        // retiring older services, including when v10 has never been installed.
        let shellScript = "set -e\n\(quotedHelper) --install \(quotedApp)"
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
            if isDiskBusy || isRefreshingDisks {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                continue
            }
            isRefreshingDisks = true
            do {
                let availableVolumes = try await diskService.listEligibleVolumes()
                guard !Task.isCancelled, configuration.automaticallyRestoreMountsOnLaunch else { isRefreshingDisks = false; return }
                applyDiskRefresh(availableVolumes)
                let elapsedSeconds = Int(startedAt.duration(to: clock.now).components.seconds)
                if elapsedSeconds >= nextLogSecond {
                    let identifiers = availableVolumes.map {
                        "\($0.id)[\($0.volumeUUID ?? "no-uuid")]=\($0.mountPoint ?? "unmounted")"
                    }.joined(separator: ", ")
                    DiagnosticFileLogger.write("Automatic disk scan \(elapsedSeconds)s: \(identifiers.isEmpty ? "no eligible volumes" : identifiers)")
                    nextLogSecond = max(10, ((elapsedSeconds / 10) + 1) * 10)
                }
                isRefreshingDisks = false
                if elapsedSeconds >= 10, Date() >= automaticRestoreNotBefore, !isDiskBusy {
                    isDiskBusy = true
                    await restoreMounts(from: availableVolumes)
                    isDiskBusy = false
                }
            } catch {
                isRefreshingDisks = false
                DiagnosticFileLogger.write("Automatic disk refresh failed: \(error.localizedDescription)")
            }
            do { try await Task.sleep(for: .seconds(1)) }
            catch { return }
        }
    }

    private func restoreMounts(from volumes: [DiskVolume], manual: Bool = false) async {
        let plan = DiskRestorationPlan(presets: configuration.restorableDiskMounts, volumes: volumes)
        if plan.requests.isEmpty {
            if manual {
                let message = plan.entries.isEmpty ? tr("没有可恢复的挂载记录", "No previous mounts to restore") : plan.entries.map { "\($0.preset.diskIdentifier): \(restorationStateText($0.state))" }.joined(separator: "\n")
                status = TaskStatus(phase: plan.entries.allSatisfy { $0.state == .alreadyMounted } ? .succeeded : .failed, message: message)
            }
            return
        }
        diskRefreshError = nil
        let result = await diskService.mountVolumes(plan.requests)
        rememberRestorableMounts(plan.requests.filter { request in result.items.contains { $0.volume.id == request.volume.id && $0.succeeded } })
        if !result.isSuccess { automaticRestoreNotBefore = Date().addingTimeInterval(30) }
        await finishDiskOperation(result)
        if manual, plan.entries.contains(where: { $0.state != .ready && $0.state != .alreadyMounted }) {
            status.log += plan.entries.filter { $0.state != .ready }.map { "\($0.preset.diskIdentifier): \(restorationStateText($0.state))" }
            status.message += tr("；部分记录需要处理", "; some records need attention")
        }
    }

    func restorationStateText(_ state: DiskRestorationState) -> String {
        switch state {
        case .ready: return tr("可以恢复", "Ready to restore")
        case .alreadyMounted: return tr("已在目标路径，无需恢复", "Already at the requested path")
        case .offline: return tr("磁盘未连接", "Volume offline")
        case .needsAssociation: return tr("旧记录需要重新关联", "Legacy record needs association")
        case .invalidPath: return tr("目标目录失效", "Destination unavailable")
        }
    }

    private func rememberRestorableMounts(_ requests: [DiskMountRequest]) {
        for request in requests {
            guard let uuid = request.volume.volumeUUID else { continue }
            configuration.restorableDiskMounts.removeAll { $0.volumeUUID?.caseInsensitiveCompare(uuid) == .orderedSame }
            configuration.restorableDiskMounts.insert(DiskPreset(diskIdentifier: request.volume.id, volumeUUID: uuid, mountPath: request.path), at: 0)
        }
        if !requests.isEmpty { saveConfiguration() }
    }

    private func saveConfiguration() {
        let value = configuration
        Task {
            do {
                try await configurationStore.save(value)
            } catch {
                report(ToolboxError.commandFailed(
                    tr("配置保存失败：\(error.localizedDescription)", "Failed to save configuration: \(error.localizedDescription)")
                ))
            }
        }
    }

    private func rememberMetalHUDApp(_ applicationURL: URL, save: Bool = true) {
        let normalizedURL = applicationURL.standardizedFileURL.resolvingSymlinksInPath()
        let displayName = FileManager.default.displayName(atPath: normalizedURL.path)
        let name = (displayName as NSString).deletingPathExtension
        let existingPreset = configuration.recentMetalHUDApps.first(where: { URL(fileURLWithPath: $0.path).standardizedFileURL.resolvingSymlinksInPath().path == normalizedURL.path })?.preset
        configuration.recentMetalHUDApps.removeAll { URL(fileURLWithPath: $0.path).standardizedFileURL.resolvingSymlinksInPath().path == normalizedURL.path }
        configuration.recentMetalHUDApps.insert(RecentMetalHUDApp(path: normalizedURL.path, displayName: name, preset: existingPreset), at: 0)
        configuration.recentMetalHUDApps = Array(configuration.recentMetalHUDApps.prefix(ConfigurationStore.maxRecentMetalHUDApps))
        if save { saveConfiguration() }
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
