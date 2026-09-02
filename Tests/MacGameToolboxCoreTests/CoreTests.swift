import Foundation
import Testing
@testable import MacGameToolboxCore

@Test func pathValidationNormalizesAndRejectsRoot() throws {
    #expect(try InputValidation.normalizedAbsolutePath("~/Games", home: "/Users/test") == "/Users/test/Games")
    #expect(throws: ToolboxError.invalidPath("/")) { try InputValidation.normalizedAbsolutePath("/") }
    #expect(InputValidation.diskIdentifier("disk12s3"))
    #expect(!InputValidation.diskIdentifier("disk0"))
}

@Test func legacyConfigurationImportsValues() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let configURL = root.appendingPathComponent("new/configuration.json")
    let defaultDirectory = root.appendingPathComponent("Library/Disk Setup")
    let presetDirectory = root.appendingPathComponent("Library/Application Support/DiskUtilHelper")
    try FileManager.default.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: presetDirectory, withIntermediateDirectories: true)
    try "/tmp/a\n/tmp/b\n/tmp/a\n/tmp/c\n/tmp/d\n".write(to: defaultDirectory.appendingPathComponent("default_paths.txt"), atomically: true, encoding: .utf8)
    try "disk2s1\ndisk3s1\ninvalid\n".write(to: presetDirectory.appendingPathComponent("presetDiskIdentifiers.txt"), atomically: true, encoding: .utf8)
    try "disk2s1:/tmp/game:bottle\n".write(to: presetDirectory.appendingPathComponent("presetMappings.txt"), atomically: true, encoding: .utf8)

    let store = ConfigurationStore(configurationURL: configURL)
    let configuration = try await store.load(homeURL: root)
    #expect(configuration.didImportLegacyConfiguration)
    #expect(configuration.defaultPaths == ["/tmp/a", "/tmp/b", "/tmp/c", "/tmp/d"])
    #expect(configuration.diskPresets.count == 2)
    #expect(configuration.diskPresets.first?.mountPath == "/tmp/game:bottle")
}

@Test func diskParserExcludesBootDisk() throws {
    let plist: [String: Any] = [
        "AllDisksAndPartitions": [
            ["DeviceIdentifier": "disk0", "Partitions": [["DeviceIdentifier": "disk0s1", "VolumeName": "System", "Size": 10]]],
            ["DeviceIdentifier": "disk4", "Internal": false, "Partitions": [["DeviceIdentifier": "disk4s2", "Content": "Apple_APFS", "APFSVolumes": [["DeviceIdentifier": "disk5s1", "VolumeName": "Games", "Content": "APFS", "MountPoint": "/Volumes/Games", "Size": 1234]]]]]
        ]
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    let volumes = try DiskService.parseVolumes(data, excludingWholeDisk: "disk0")
    #expect(volumes.map(\.id) == ["disk5s1"])
    #expect(volumes.first?.mountPoint == "/Volumes/Games")
}

@Test func configurationRoundTripsHostnameBackupAndSpecialPaths() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
    var configuration = AppConfiguration()
    configuration.defaultPaths = ["/tmp/Game Bottle's Data"]
    configuration.hostnameBackup = HostnameBackup(computerName: "Iven Mac", hostName: "iven-mac", localHostName: "iven-mac")
    configuration.customWallpaperPath = "/tmp/wallpaper.png"
    try await store.save(configuration)
    let loaded = try await store.load(importLegacy: false)
    #expect(loaded == configuration)
    #expect(try InputValidation.normalizedAbsolutePath("/tmp/Game Bottle's Data") == "/tmp/Game Bottle's Data")
}

@Test func olderConfigurationDefaultsAutomaticMountRestorationToOff() throws {
    let data = Data(#"{"schemaVersion":1,"diskPresets":[{"diskIdentifier":"disk4s1","mountPath":"/tmp/Games"}]}"#.utf8)
    let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)
    #expect(!configuration.automaticallyRestoreMountsOnLaunch)
    #expect(configuration.restorableDiskMounts.isEmpty)
    #expect(configuration.customWallpaperPath == nil)
    #expect(configuration.favoriteProcessNames.isEmpty)
    #expect(configuration.recentMetalHUDApps.isEmpty)
    #expect(configuration.hoYoWaitSeconds == 15)
    #expect(!configuration.doesNotRaiseHoYoPriority)
    #expect(configuration.excludesSensitiveCacheFiles)
    #expect(configuration.diskPresets.first?.diskIdentifier == "disk4s1")
}

@Test func configurationRoundTripsAutomaticMountRestorationState() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
    var configuration = AppConfiguration()
    configuration.automaticallyRestoreMountsOnLaunch = true
    configuration.restorableDiskMounts = [DiskPreset(diskIdentifier: "disk8s1", mountPath: "/tmp/Games")]
    try await store.save(configuration)
    let loaded = try await store.load(importLegacy: false)
    #expect(loaded.automaticallyRestoreMountsOnLaunch)
    #expect(loaded.restorableDiskMounts == configuration.restorableDiskMounts)
    #expect(loaded.schemaVersion == 7)
}

@Test func configurationPreservesAllRestorableMounts() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
    var configuration = AppConfiguration()
    configuration.restorableDiskMounts = (1...1_000).map {
        DiskPreset(diskIdentifier: "disk\($0)s1", mountPath: "/tmp/Games-\($0)")
    }

    try await store.save(configuration)
    let loaded = try await store.load(importLegacy: false)

    #expect(DiskService.maximumBatchMounts == Int.max)
    #expect(loaded.restorableDiskMounts.count == configuration.restorableDiskMounts.count)
    #expect(loaded.restorableDiskMounts.first?.diskIdentifier == "disk1s1")
    #expect(loaded.restorableDiskMounts.last?.diskIdentifier == "disk1000s1")
}

@Test func configurationPreservesAllDefaultPaths() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
    var configuration = AppConfiguration()
    configuration.defaultPaths = (1...1_000).map { "/tmp/Games-\($0)" }

    try await store.save(configuration)
    let loaded = try await store.load(importLegacy: false)

    #expect(ConfigurationStore.maxDefaultPaths == Int.max)
    #expect(loaded.defaultPaths.count == configuration.defaultPaths.count)
    #expect(loaded.defaultPaths.first == "/tmp/Games-1")
    #expect(loaded.defaultPaths.last == "/tmp/Games-1000")
}

@Test func wallpaperServiceImportsAndRemovesManagedWallpapersOnly() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let wallpaperDirectory = root.appendingPathComponent("Wallpapers", isDirectory: true)
    let source = root.appendingPathComponent("source.png")
    let external = root.appendingPathComponent("external.png")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data([0, 1, 2]).write(to: source)
    try Data([3, 4, 5]).write(to: external)

    let service = WallpaperService(wallpaperDirectory: wallpaperDirectory)
    let first = try service.importWallpaper(from: source)
    #expect(FileManager.default.fileExists(atPath: first.path))
    #expect(first.deletingLastPathComponent().standardizedFileURL == wallpaperDirectory.standardizedFileURL)

    let removedExternal = try service.removeManagedWallpaper(at: external.path)
    #expect(!removedExternal)
    #expect(FileManager.default.fileExists(atPath: external.path))

    let removedManaged = try service.removeManagedWallpaper(at: first.path)
    #expect(removedManaged)
    #expect(!FileManager.default.fileExists(atPath: first.path))
}

@Test func wallpaperServiceReimportRemovesPreviousManagedWallpaper() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let wallpaperDirectory = root.appendingPathComponent("Wallpapers", isDirectory: true)
    let source = root.appendingPathComponent("source.jpg")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data([6, 7, 8]).write(to: source)

    let service = WallpaperService(wallpaperDirectory: wallpaperDirectory)
    let first = try service.importWallpaper(from: source)
    let second = try service.importWallpaper(from: source, replacing: first.path)

    #expect(!FileManager.default.fileExists(atPath: first.path))
    #expect(FileManager.default.fileExists(atPath: second.path))
}

@Test func automaticMountMatchingPrefersStableVolumeUUIDAndFallsBackToIdentifier() {
    let oldIdentifier = DiskPreset(diskIdentifier: "disk4s1", volumeUUID: "VOLUME-UUID", mountPath: "/tmp/Games")
    let renumberedVolume = DiskVolume(id: "disk8s2", volumeUUID: "volume-uuid", name: "Games", fileSystem: "apfs", mountPoint: nil, size: 1, wholeDisk: "disk8", isInternal: false)
    #expect(DiskService.matchingVolume(for: oldIdentifier, in: [renumberedVolume])?.id == "disk8s2")

    let legacyPreset = DiskPreset(diskIdentifier: "disk4s1", mountPath: "/tmp/Games")
    let legacyVolume = DiskVolume(id: "disk4s1", name: "Games", fileSystem: "apfs", mountPoint: nil, size: 1, wholeDisk: "disk4", isInternal: false)
    #expect(DiskService.matchingVolume(for: legacyPreset, in: [legacyVolume])?.id == "disk4s1")
}

@Test func hostsEditorIsIdempotentAndRollsBack() {
    let original = "127.0.0.1 localhost\n0.0.0.0 example.com\n"
    let domains = ["a.example", "b.example"]
    let enabled = HostsFileEditor.replacingManagedBlock(in: original, domains: domains, enabled: true)
    #expect(HostsFileEditor.replacingManagedBlock(in: enabled, domains: domains, enabled: true) == enabled)
    #expect(HostsFileEditor.replacingManagedBlock(in: enabled, domains: domains, enabled: false) == original)
}

@Test func hoYoDomainsIncludeAllLaunchAssistanceEndpoints() {
    let expectedDomains = [
        "globaldp-prod-cn01.juequling.com",
        "globaldp-prod-cn02.juequling.com",
        "globaldp-prod-os01.zenlesszonezero.com",
        "globaldp-prod-os02.zenlesszonezero.com",
    ]
    #expect(expectedDomains.allSatisfy(GamingService.hoyoDomains.contains))
}

@Test func processParserFiltersCrossOver() {
    let text = "  100 1 /Applications/CrossOver 25.app/Contents/MacOS/CrossOver\n  110 100 /Applications/CrossOver 25.app/Contents/SharedSupport/CrossOver/bin/cxoffice\n  120 110 /Applications/CrossOver 25.app/Contents/SharedSupport/CrossOver/bin/wine64-preloader\n  200 1 /usr/local/bin/wine game.exe\n  300 1 unrelated"
    let processes = GamingService.parseProcessTable(text)
    #expect(GamingService.matchingProcesses(processes, crossOverOnly: false).map(\.pid) == [120, 200])
    #expect(GamingService.matchingProcesses(processes, crossOverOnly: true).map(\.pid) == [100, 110, 120])
}

@Test func processParserFindsDetachedCrossOverWineServices() {
    let text = "  3949 1 C:\\windows\\system32\\winedevice.exe\n  3950 1 C:\\windows\\system32\\wineserver.exe"
    let processes = GamingService.parseProcessTable(text)
    #expect(GamingService.matchingProcesses(processes, crossOverOnly: true).map(\.pid) == [3949, 3950])
}

@Test func processParserReadsCPUUsageAndSortsDescending() {
    let text = "  100 1 18.7 /Applications/Game.app/Contents/MacOS/Game\n  101 1 75.2 /Applications/Launcher.app/Contents/MacOS/Launcher\n  102 1 18.7 /Applications/Another.app/Contents/MacOS/Another"
    let processes = GamingService.parseProcessTable(text)

    #expect(processes.map(\.cpuUsage) == [18.7, 75.2, 18.7])
    #expect(GamingService.sortedRunningProcesses(processes).map(\.pid) == [101, 102, 100])
}

@Test func processParserFallsBackToZeroForMissingOrInvalidCPUUsage() {
    let text = "  100 1 invalid /Applications/Game.app/Contents/MacOS/Game\n  101 1 /Applications/Legacy.app/Contents/MacOS/Legacy"
    let processes = GamingService.parseProcessTable(text)

    #expect(processes.map(\.cpuUsage) == [0, 0])
    #expect(processes.map(\.command) == [
        "/Applications/Game.app/Contents/MacOS/Game",
        "/Applications/Legacy.app/Contents/MacOS/Legacy"
    ])
}

@Test func processSearchMatchesApplicationDirectoryAndShowsExecutableName() {
    let process = SystemProcess(
        pid: 9527,
        parentPID: 1,
        command: "X6Game",
        applicationPath: "/Applications/无限暖暖.app"
    )

    #expect(process.matches(searchText: "无限暖暖"))
    #expect(process.matches(searchText: "X6Game"))
    #expect(process.locationPath == "/Applications/无限暖暖.app")
    #expect(process.displayName == "X6Game")
}

@Test func processSearchUsesAppBundlePathEmbeddedInCommand() {
    let process = SystemProcess(
        pid: 9528,
        parentPID: 1,
        command: "/Applications/无限暖暖.app/Contents/MacOS/X6Game -fullscreen"
    )

    #expect(process.matches(searchText: "无限暖暖"))
    #expect(process.locationPath == "/Applications/无限暖暖.app")
    #expect(process.displayName == "X6Game")
}

@Test func favoriteProcessMatchingRequiresExactCaseSensitiveDisplayName() {
    let processes = [
        SystemProcess(pid: 10, parentPID: 1, command: "X6Game"),
        SystemProcess(pid: 11, parentPID: 1, command: "x6game"),
        SystemProcess(pid: 12, parentPID: 1, command: "/Applications/无限暖暖.app/Contents/MacOS/X6Game -fullscreen"),
        SystemProcess(pid: 13, parentPID: 1, command: "X6GameHelper")
    ]

    #expect(GamingService.matchingFavoriteProcesses(processes, favoriteNames: ["X6Game"]).map(\.pid) == [10, 12])
}

@Test func volumeInfoFilteringUsesPhysicalBootStoresAndKeepsUnmountedExternalVolumes() {
    let boot: [String: Any] = [
        "ParentWholeDisk": "disk3",
        "DeviceIdentifier": "disk3s3s1",
        "BooterDeviceIdentifier": "disk3s4",
        "RecoveryDeviceIdentifier": "disk3s5",
        "APFSVolumeGroupID": "SYSTEM-GROUP",
        "APFSPhysicalStores": [["APFSPhysicalStore": "disk0s2"]]
    ]
    let excluded = DiskService.systemWholeDisks(from: boot)
    #expect(excluded == ["disk0", "disk3"])

    let external: [String: Any] = [
        "DeviceIdentifier": "disk8s1", "ParentWholeDisk": "disk8", "WholeDisk": false,
        "VolumeName": "Games", "FilesystemType": "exfat", "MountPoint": "", "TotalSize": 2_000,
        "Internal": false
    ]
    #expect(DiskService.parseVolumeInfo(external, bootInfo: boot)?.id == "disk8s1")

    var system = external
    system["DeviceIdentifier"] = "disk3s7"
    system["ParentWholeDisk"] = "disk3"
    system["APFSVolumeGroupID"] = "USER-CREATED-GROUP"
    #expect(DiskService.parseVolumeInfo(system, bootInfo: boot)?.id == "disk3s7")

    var systemGroupVolume = system
    systemGroupVolume["APFSVolumeGroupID"] = "SYSTEM-GROUP"
    #expect(DiskService.parseVolumeInfo(systemGroupVolume, bootInfo: boot) == nil)

    var cryptex = external
    cryptex["MountPoint"] = "/private/var/run/com.apple.security.cryptexd/mnt/toolchain"
    #expect(DiskService.parseVolumeInfo(cryptex, bootInfo: boot) == nil)
}

actor RecordingPrivilegedOperator: PrivilegedOperating {
    private(set) var operations: [PrivilegedOperation] = []
    func perform(_ operation: PrivilegedOperation) async throws { operations.append(operation) }
}

actor RecordingCommandRunner: CommandRunning {
    private(set) var calls: [(String, [String])] = []

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        calls.append((executable, arguments))
        return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data())
    }
}

@Test func perAppMetalHUDLaunchUsesScopedEnvironment() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let application = root.appendingPathComponent("Example Game.app", isDirectory: true)
    try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let runner = RecordingCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())
    try await service.launchWithMetalHUD(applicationPath: application.path)

    let calls = await runner.calls
    #expect(calls.count == 1)
    #expect(calls.first?.0 == "/usr/bin/env")
    #expect(calls.first?.1 == ["MTL_HUD_ENABLED=1", "/usr/bin/open", "-a", application.path])
}

@Test func perAppMetalHUDLaunchPassesPresetOnlyToThatLaunch() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let application = root.appendingPathComponent("Example Game.app", isDirectory: true)
    let preset = root.appendingPathComponent("my-hud.json")
    try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
    let properties: [String: Any] = [
        "MTL_HUD_ALIGNMENT": 18,
        "MTL_HUD_ELEMENTS": "fps,gputime",
        "MTL_HUD_ENABLED": true
    ]
    try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0).write(to: preset)
    defer { try? FileManager.default.removeItem(at: root) }

    let runner = RecordingCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())
    try await service.launchWithMetalHUD(applicationPath: application.path, presetPath: preset.path)

    let calls = await runner.calls
    #expect(calls.first?.1 == ["MTL_HUD_ALIGNMENT=bottomleft", "MTL_HUD_ELEMENTS=fps,gputime", "MTL_HUD_ENABLED=1", "/usr/bin/open", "-a", application.path])
}

@Test func metalHUDEnvironmentConvertsLegacyNumericAlignments() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let preset = root.appendingPathComponent("hud.plist")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let properties: [String: Any] = ["MTL_HUD_ALIGNMENT": 18, "MTL_HUD_ENABLED": true]
    try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0).write(to: preset)

    #expect(try GamingService.metalHUDEnvironment(from: preset) == ["MTL_HUD_ALIGNMENT=bottomleft", "MTL_HUD_ENABLED=1"])
}

@Test func iOSDeviceAndAppParsersReadDevicectlJSON() throws {
    let devices = """
    {"result":{"devices":[{"identifier":"00008110-001234567890801E","name":"Iven's iPhone","deviceProperties":{"modelName":"iPhone 17 Pro","connectionState":"connected"}}]}}
    """
    let apps = """
    {"result":{"apps":[{"bundleIdentifier":"com.example.game","displayName":"Example Game","version":"1.2.3"}]}}
    """

    #expect(try GamingService.parseIOSDevices(devices) == [IOSDevice(id: "00008110-001234567890801E", name: "Iven's iPhone", model: "iPhone 17 Pro", state: "connected")])
    #expect(try GamingService.parseIOSApps(apps) == [IOSInstalledApp(bundleIdentifier: "com.example.game", displayName: "Example Game", version: "1.2.3")])
}

@Test func iOSMetalHUDLaunchUsesDeviceScopedEnvironment() async throws {
    let runner = RecordingCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())

    try await service.launchIOSAppWithMetalHUD(deviceID: "00008110-001234567890801E", bundleIdentifier: "com.example.game")

    let calls = await runner.calls
    #expect(calls.count == 1)
    #expect(calls.first?.0 == "/usr/bin/xcrun")
    #expect(calls.first?.1 == ["devicectl", "device", "process", "launch", "--device", "00008110-001234567890801E", "--environment-variables", "{\"MTL_HUD_ENABLED\":\"1\"}", "--terminate-existing", "com.example.game"])
}

@Test func iOSMetalHUDLaunchPassesArgumentsAfterBundleIdentifier() async throws {
    let runner = RecordingCommandRunner()
    let service = GamingService(runner: runner, privileged: RecordingPrivilegedOperator())
    try await service.launchIOSAppWithMetalHUD(
        deviceID: "00008110-001234567890801E",
        bundleIdentifier: "com.example.game",
        launchArguments: ["-SkipSplash", "-OpenFileLog"]
    )

    let calls = await runner.calls
    #expect(calls.first.map { Array($0.1.suffix(4)) } == ["com.example.game", "--", "-SkipSplash", "-OpenFileLog"])
}

@Test func crossOverBottleServiceFindsValidBottlesAndPreservesExistingSettings() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let valid = root.appendingPathComponent("Valid", isDirectory: true)
    let invalid = root.appendingPathComponent("Invalid", isDirectory: true)
    let config = valid.appendingPathComponent("cxbottle.conf")
    let preset = root.appendingPathComponent("hud.plist")
    try FileManager.default.createDirectory(at: valid.appendingPathComponent("drive_c"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
    try "[EnvironmentVariables]\n\"CX_GRAPHICS_BACKEND\" = \"d3dmetal\"\n\"MTL_HUD_CONFIG_FILE\" = \"/old.plist\"\n".write(to: config, atomically: true, encoding: .utf8)
    let properties: [String: Any] = ["MTL_HUD_ALIGNMENT": 18, "MTL_HUD_ENABLED": true]
    try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0).write(to: preset)
    defer { try? FileManager.default.removeItem(at: root) }

    let service = CrossOverBottleService(bottlesDirectory: root)
    let bottles = try await service.bottles()
    #expect(bottles.count == 1)
    #expect(bottles.first?.displayName == "Valid")
    try await service.applyMetalHUDPreset(preset, to: bottles[0])

    let updated = try String(contentsOf: config, encoding: .utf8)
    #expect(updated.contains("\"CX_GRAPHICS_BACKEND\" = \"d3dmetal\""))
    #expect(updated.contains("\"MTL_HUD_ALIGNMENT\" = \"bottomleft\""))
    #expect(updated.contains("\"MTL_HUD_CONFIG_FILE\" = \"\(preset.path)\""))
    #expect(!updated.contains("\"MTL_HUD_ENABLED\""))
}

@Test func metalHUDPresetStoreCopiesAnExportIntoItsManagedDirectory() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let source = root.appendingPathComponent("exported-hud.json")
    let managed = root.appendingPathComponent("managed", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("preset".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = MetalHUDPresetStore(directoryURL: managed)
    let preset = try await store.importPreset(from: source, forApplicationPath: "/Applications/Test Game.app")
    try FileManager.default.removeItem(at: source)

    #expect(preset.path.hasPrefix(managed.path))
    #expect(FileManager.default.contents(atPath: preset.path) == Data("preset".utf8))
}

actor HostnameRunner: CommandRunning {
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        switch arguments.last {
        case "ComputerName": return CommandResult(exitCode: 0, standardOutput: Data("MacBook Pro\n".utf8), standardError: Data())
        case "LocalHostName": return CommandResult(exitCode: 0, standardOutput: Data("MacBook-Pro\n".utf8), standardError: Data())
        case "HostName": throw ToolboxError.commandFailed("HostName: not set")
        default: throw ToolboxError.commandFailed("unexpected fixture")
        }
    }
}

@Test func missingHostNameFallsBackToLocalHostName() async throws {
    let service = HostnameService(runner: HostnameRunner(), privileged: RecordingPrivilegedOperator())
    let names = try await service.current()
    #expect(names == HostnameBackup(computerName: "MacBook Pro", hostName: "MacBook-Pro", localHostName: "MacBook-Pro"))
    #expect(InputValidation.computerName(names.computerName))
}

@Test func privilegedHealthCheckRoundTripsThroughCodableRequest() throws {
    let data = try JSONEncoder().encode(PrivilegedRequest.healthCheck)
    let decoded = try JSONDecoder().decode(PrivilegedRequest.self, from: data)
    guard case .healthCheck = decoded else {
        Issue.record("Unexpected request case")
        return
    }
}

@Test func allPrivilegedRequestsRoundTripThroughCodable() throws {
    let requests: [PrivilegedRequest] = [
        .healthCheck,
        .addHoYoHosts,
        .removeHoYoHosts,
        .renice([42, 84], -20),
        .renice([42, 84], 20),
        .clearSystemCaches,
        .setHostnames(HostnameBackup(computerName: "steamdeck", hostName: "steamdeck", localHostName: "steamdeck")),
        .createDirectory("/Users/test/Games")
    ]
    for request in requests {
        let data = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(PrivilegedRequest.self, from: data) == request)
    }
}

@Test func helperRegistrationStatesChooseExpectedActions() {
    #expect(helperRegistrationDecision(for: .enabled) == .connect)
    #expect(helperRegistrationDecision(for: .notRegistered) == .register)
    #expect(helperRegistrationDecision(for: .requiresApproval) == .requestApproval)
    #expect(helperRegistrationDecision(for: .notFound) == .unavailable)
}

actor RejectingPrivilegedOperator: PrivilegedOperating {
    private(set) var operations: [PrivilegedOperation] = []
    func perform(_ operation: PrivilegedOperation) async throws {
        operations.append(operation)
        throw ToolboxError.authorizationCancelled
    }
}

@Test func cacheClearAuthorizesBeforeDeletingUserFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("keep-me.cache")
    try Data("important".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: root) }

    let privileged = RejectingPrivilegedOperator()
    let service = CacheService(privileged: privileged)
    do {
        try await service.clear(CacheScan(userTargets: [root], systemTargets: [URL(fileURLWithPath: "/Library/Caches")], estimatedBytes: 9))
        Issue.record("Expected authorization failure")
    } catch {
        #expect(error as? ToolboxError == .authorizationCancelled)
    }
    #expect(FileManager.default.fileExists(atPath: file.path))
    #expect(await privileged.operations == [.healthCheck])
}

@Test func sensitiveCacheExclusionScansAndClearsOnlyUserCachesAndLogs() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
    let logs = root.appendingPathComponent("Library/Logs", isDirectory: true)
    let sensitive = root.appendingPathComponent("Library/Application Support/Game/Caches", isDirectory: true)
    try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: sensitive, withIntermediateDirectories: true)
    try Data("cache".utf8).write(to: caches.appendingPathComponent("user.cache"))
    try Data("log".utf8).write(to: logs.appendingPathComponent("user.log"))
    try Data("keep".utf8).write(to: sensitive.appendingPathComponent("sensitive.cache"))
    defer { try? FileManager.default.removeItem(at: root) }

    let privileged = RecordingPrivilegedOperator()
    let service = CacheService(privileged: privileged)
    let scan = await service.scan(excludingSensitiveFiles: true, homeURL: root)
    #expect(scan.userTargets.map(\.standardizedFileURL.path) == [caches, logs].map(\.standardizedFileURL.path))
    #expect(scan.systemTargets.isEmpty)
    try await service.clear(scan)

    #expect(!FileManager.default.fileExists(atPath: caches.appendingPathComponent("user.cache").path))
    #expect(!FileManager.default.fileExists(atPath: logs.appendingPathComponent("user.log").path))
    #expect(FileManager.default.fileExists(atPath: sensitive.appendingPathComponent("sensitive.cache").path))
    #expect(await privileged.operations.isEmpty)
}

@Test func cacheCleanupContinuesAfterAnInaccessibleEntry() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let blocked = root.appendingPathComponent("com.apple.HomeKit")
    let removable = root.appendingPathComponent("removable.cache")
    try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
    try Data("remove".utf8).write(to: removable)
    defer { try? FileManager.default.removeItem(at: root) }

    let service = CacheService(privileged: RecordingPrivilegedOperator()) { url in
        if url.lastPathComponent == blocked.lastPathComponent {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.removeItem(at: url)
    }
    try await service.clear(CacheScan(userTargets: [root], systemTargets: [], estimatedBytes: 6))

    #expect(FileManager.default.fileExists(atPath: blocked.path))
    #expect(!FileManager.default.fileExists(atPath: removable.path))
}

@Test func configurationNormalizesNewVersionThreePreferences() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
    var configuration = AppConfiguration()
    configuration.hoYoWaitSeconds = 99
    configuration.doesNotRaiseHoYoPriority = true
    configuration.excludesSensitiveCacheFiles = false
    configuration.recentMetalHUDApps = [
        RecentMetalHUDApp(path: "/Applications/A.app", displayName: "A", preset: MetalHUDPreset(path: "/managed/a.json", displayName: "A HUD")),
        RecentMetalHUDApp(path: "/Applications/A.app", displayName: "Duplicate")
    ]
    configuration.favoriteProcessNames = [" X6Game ", "", "X6Game", "x6game"]
    try await store.save(configuration)
    let loaded = try await store.load(importLegacy: false)
    #expect(loaded.schemaVersion == 7)
    #expect(loaded.hoYoWaitSeconds == 15)
    #expect(loaded.doesNotRaiseHoYoPriority)
    #expect(!loaded.excludesSensitiveCacheFiles)
    #expect(loaded.recentMetalHUDApps == [RecentMetalHUDApp(path: "/Applications/A.app", displayName: "A", preset: MetalHUDPreset(path: "/managed/a.json", displayName: "A HUD"))])
    #expect(loaded.favoriteProcessNames == ["X6Game", "x6game"])
}

@Test func processRunnerDrainsOutputLargerThanPipeBuffer() async throws {
    let result = try await ProcessCommandRunner().run("/usr/bin/seq", arguments: ["1", "30000"])
    #expect(result.outputString.hasPrefix("1\n2\n3"))
    #expect(result.outputString.hasSuffix("30000"))
    #expect(result.standardOutput.count > 65_536)
}

actor MockRunner: CommandRunning {
    var calls: [[String]] = []
    var failingMount: String?
    var staleInfoReads: [String: Int]
    var reportedMountPaths: [String: String]

    init(failingMount: String? = nil, staleInfoReads: [String: Int] = [:], reportedMountPaths: [String: String] = [:]) {
        self.failingMount = failingMount
        self.staleInfoReads = staleInfoReads
        self.reportedMountPaths = reportedMountPaths
    }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        calls.append(arguments)
        if arguments.contains("mount"), let failingMount, arguments.contains(where: { $0.contains(failingMount) }) {
            throw ToolboxError.commandFailed("fixture failure")
        }
        if arguments.first == "info" {
            let identifier = arguments.last ?? ""
            if let remaining = staleInfoReads[identifier], remaining > 0 {
                staleInfoReads[identifier] = remaining - 1
                let data = try PropertyListSerialization.data(fromPropertyList: ["MountPoint": "/Volumes/Stale"], format: .xml, options: 0)
                return CommandResult(exitCode: 0, standardOutput: data, standardError: Data())
            }
            let path = reportedMountPaths[identifier]
                ?? calls.last(where: { $0.contains("-mountPoint") && $0.last?.contains(identifier) == true })?.dropFirst(2).first
                ?? "/Volumes/Test"
            let data = try PropertyListSerialization.data(fromPropertyList: ["MountPoint": path], format: .xml, options: 0)
            return CommandResult(exitCode: 0, standardOutput: data, standardError: Data())
        }
        return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data())
    }
}

@Test func batchMountRollsBackEarlierVolumeOnFailure() async {
    let runner = MockRunner(failingMount: "disk5s1")
    let service = DiskService(runner: runner)
    _ = await service.mountBatch([("disk4s1", "/tmp/one"), ("disk5s1", "/tmp/two")])
    let calls = await runner.calls
    #expect(calls.contains(["mount", "disk4s1"]))
    #expect(calls.filter { $0 == ["unmount", "disk5s1"] }.count == 2)
}

@Test func mountWaitsForDiskutilInfoToReflectTheRequestedPath() async throws {
    let runner = MockRunner(staleInfoReads: ["disk4s1": 2])
    let service = DiskService(runner: runner)

    try await service.mount("disk4s1", at: "/tmp/delayed")

    let calls = await runner.calls
    #expect(calls.filter { $0 == ["info", "-plist", "disk4s1"] }.count == 3)
}

@Test func mountAcceptsEquivalentCanonicalMountPaths() async throws {
    let mountPath = "/tmp/mac-game-toolbox-canonical-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: mountPath, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: mountPath) }
    let runner = MockRunner(reportedMountPaths: ["disk4s1": "/private\(mountPath)"])
    let service = DiskService(runner: runner)

    try await service.mount("disk4s1", at: mountPath)
}

@Test func batchMountProcessesAllVolumesWithoutANumericalCap() async {
    let runner = MockRunner()
    let service = DiskService(runner: runner)
    let assignments = (1...1_000).map { ("disk\($0)s1", "/tmp/volume-\($0)") }

    let results = await service.mountBatch(assignments)

    #expect(results.count == assignments.count)
    #expect(results["disk4s1"] != nil)
    #expect(results["disk1000s1"] != nil)
}
