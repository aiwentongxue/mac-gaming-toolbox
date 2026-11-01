#if !SWIFT_PACKAGE
import XCTest
import SwiftUI
@testable import Mac_游戏工具箱

private actor ShortcutCommandRecorder: CommandRunning {
    var calls: [(String,[String])] = []
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        calls.append((executable,arguments))
        return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data())
    }
}
private actor ShortcutNoopPrivilege: PrivilegedOperating {
    func perform(_ operation: PrivilegedOperation) async throws {}
    func clearSystemCacheEntries(_ entries: [URL]) async throws -> CacheCleanupResult { CacheCleanupResult(removedCount: 0, failedItems: []) }
}
@MainActor final class MetalHUDShortcutTests: XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("metalhud-shortcut-" + UUID().uuidString) }
    private func fixture(_ root: URL, name: String = "Steam Library/steamapps/common/Fixture Game.app") throws -> URL {
        let app = root.appendingPathComponent(name), contents = app.appendingPathComponent("Contents")
        let executable = contents.appendingPathComponent("MacOS/FixtureGame")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let info: [String:Any] = ["CFBundleIdentifier":"local.test." + UUID().uuidString, "CFBundleName":"Fixture Game", "CFBundlePackageType":"APPL", "CFBundleExecutable":"FixtureGame"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions:0o755], ofItemAtPath: executable.path)
        return app.resolvingSymlinksInPath()
    }
    private func waitForSave(_ store: ConfigurationStore, path: URL, count: Int) async throws -> AppConfiguration {
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: path.path), let config = try? await store.load(importLegacy: false), config.recentMetalHUDApps.count == count { return config }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ToolboxError.commandFailed("shortcut save did not complete")
    }
    func testAddingCustomFolderAppsPersistsWithoutLaunchingOrChangingGlobalHUD() async throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try fixture(root), second = try fixture(root, name:"Another Library/Game Two.app")
        let recorder = ShortcutCommandRecorder(), configURL = root.appendingPathComponent("config.json")
        let store = ConfigurationStore(configurationURL: configURL)
        let service = GamingService(runner: recorder, privileged: ShortcutNoopPrivilege())
        let model = AppModel(configurationStore: store, launchAutomatically: false, gamingService: service)
        model.metalHUDEnabled = true
        XCTAssertTrue(model.addMetalHUDApps([app,second]))
        XCTAssertEqual(model.configuration.recentMetalHUDApps.map(\.path), [second.path,app.path])
        let calls = await recorder.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(model.metalHUDEnabled)
        let saved = try await waitForSave(store,path:configURL,count:2)
        XCTAssertEqual(saved.recentMetalHUDApps.map(\.path),[second.path,app.path])
        let reloaded = AppModel(configurationStore:store,launchAutomatically:false,gamingService:service)
        reloaded.configuration = try await store.load(importLegacy:false)
        XCTAssertEqual(reloaded.configuration.recentMetalHUDApps,model.configuration.recentMetalHUDApps)
        model.launchRecordedAppWithMetalHUD(app.path)
        for _ in 0..<100 {
            if model.status.phase != .running { break }
            try await Task.sleep(for:.milliseconds(10))
        }
        let launched = await recorder.calls
        XCTAssertEqual(launched.count,1)
        XCTAssertEqual(launched.first?.0,"/usr/bin/env")
        XCTAssertEqual(launched.first?.1,["MTL_HUD_ENABLED=1","/usr/bin/open","-a",app.path])
        XCTAssertTrue(model.metalHUDEnabled)
        _ = try await waitForSave(store,path:configURL,count:2)
    }
    func testAddingAliasOrDuplicatePreservesPresetAndDoesNotDuplicateCard() async throws {
        let root=root();defer {try? FileManager.default.removeItem(at:root)}
        let app=try fixture(root),alias=root.appendingPathComponent("Shortcut.app")
        try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:app)
        let configURL=root.appendingPathComponent("config.json"),store=ConfigurationStore(configurationURL:configURL)
        let model=AppModel(configurationStore:store,launchAutomatically:false)
        let preset=MetalHUDPreset(path:"/managed/preset.json",displayName:"User Preset")
        model.configuration.recentMetalHUDApps=[RecentMetalHUDApp(path:app.path,displayName:"Game",preset:preset)]
        XCTAssertTrue(model.addMetalHUDApps([alias,app]))
        XCTAssertEqual(model.configuration.recentMetalHUDApps.count,1)
        XCTAssertEqual(model.configuration.recentMetalHUDApps[0].path,app.path)
        XCTAssertEqual(model.configuration.recentMetalHUDApps[0].preset,preset)
        _=try await waitForSave(store,path:configURL,count:1)
    }
    func testInvalidAndMixedDropsNeverLaunchFiles() async throws {
        let root=root();defer {try? FileManager.default.removeItem(at:root)}
        let app=try fixture(root),invalid=root.appendingPathComponent("Not An Application.app")
        try FileManager.default.createDirectory(at:invalid,withIntermediateDirectories:true)
        let recorder=ShortcutCommandRecorder(),configURL=root.appendingPathComponent("config.json"),store=ConfigurationStore(configurationURL:configURL)
        let model=AppModel(configurationStore:store,launchAutomatically:false,gamingService:GamingService(runner:recorder,privileged:ShortcutNoopPrivilege()))
        XCTAssertFalse(model.addMetalHUDApps([invalid,URL(string:"https://example.com/remote.app")!]))
        XCTAssertTrue(model.configuration.recentMetalHUDApps.isEmpty)
        XCTAssertTrue(model.addMetalHUDApps([invalid,app]))
        XCTAssertEqual(model.configuration.recentMetalHUDApps.map(\.path),[app.path])
        XCTAssertEqual(model.status.log.count,1)
        let calls=await recorder.calls;XCTAssertTrue(calls.isEmpty)
        _=try await waitForSave(store,path:configURL,count:1)
    }
    func testMetalHUDShortcutPageFitsNineLanguagesWithoutLaunching() throws {
        let root=root();defer {try? FileManager.default.removeItem(at:root)}
        let app=try fixture(root),model=AppModel(launchAutomatically:false),localization=LocalizationController()
        model.configuration.recentMetalHUDApps=[RecentMetalHUDApp(path:app.path,displayName:"Steam Game with a Long Display Name")]
        let defaults=UserDefaults.standard,old=defaults.object(forKey:AppLanguage.preferenceKey)
        defer {if let old {defaults.set(old,forKey:AppLanguage.preferenceKey)} else {defaults.removeObject(forKey:AppLanguage.preferenceKey)}}
        let output=URL(fileURLWithPath:"/tmp/mac-toolbox-403-metalhud-qa")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        for language in AppLanguage.Preference.allCases where language != .system {
            localization.setPreference(language)
            for scheme in [ColorScheme.light,.dark] {
                let content=ZStack {AppBackgroundView();MetalHUDDetailView()}.environmentObject(model).environmentObject(localization).environment(\.colorScheme,scheme).preferredColorScheme(scheme)
                let host=NSHostingView(rootView:content)
                let window=NSWindow(contentRect:NSRect(x:0,y:0,width:672,height:612),styleMask:[.borderless],backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false;window.contentView=host
                host.layoutSubtreeIfNeeded();window.displayIfNeeded()
                XCTAssertLessThanOrEqual(host.fittingSize.width,673)
                let bitmap=try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
                NSAppearance(named:scheme == .dark ? .darkAqua:.aqua)?.performAsCurrentDrawingAppearance {host.cacheDisplay(in:host.bounds,to:bitmap)}
                try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:output.appendingPathComponent("metalhud-\(language.rawValue)-\(scheme == .dark ? "dark":"light").png"))
                window.close()
            }
        }
    }
}
#endif
