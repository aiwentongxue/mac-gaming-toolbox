#if !SWIFT_PACKAGE
import XCTest
import SwiftUI
import AppDropCore
@testable import Mac_游戏工具箱

@MainActor final class AppDropChartUpdateTests: XCTestCase {
    func testTutorialLinksOrderCategoriesAndSearch() throws {
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: AppLanguage.preferenceKey)
        defer { if let old { defaults.set(old, forKey: AppLanguage.preferenceKey) } else { defaults.removeObject(forKey: AppLanguage.preferenceKey) } }
        let expected = ["https://b23.tv/JKMB60l", "https://b23.tv/8HWU3AQ", "https://b23.tv/T436Fv7", "https://b23.tv/h1XPWtM"]
        let original = ["https://b23.tv/pEOGX4P", "https://b23.tv/RiWoTPB", "https://b23.tv/V5xIKy4", "https://b23.tv/8l2dLbN", "https://b23.tv/l6ctHlr", "https://b23.tv/OZ5wkvd", "https://b23.tv/B8Fb50K", "https://b23.tv/HTFJ478", "https://b23.tv/1UfRohG", "https://b23.tv/dV7YBJQ", "https://youtube.com/channel/UC0TgypOLHt2fXboVw34SKVQ"]
        for language in [AppLanguage.Preference.simplifiedChinese, .english] {
            defaults.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            let all = TutorialItem.all
            XCTAssertEqual(all.count, 16)
            XCTAssertEqual(Set(all.map(\.id)).count, 16)
            XCTAssertEqual(all.first?.address, "https://b23.tv/qW8NuD7")
            XCTAssertEqual(all.first?.category, .gettingStarted)
            XCTAssertEqual(all.filter { original.contains($0.address) }.map(\.address), original)
            let anchor = try XCTUnwrap(all.firstIndex { $0.address == "https://b23.tv/HTFJ478" })
            XCTAssertEqual(Array(all[(anchor+1)...(anchor+4)]).map(\.address), expected)
            XCTAssertTrue(all[(anchor+1)...(anchor+4)].allSatisfy { $0.category == .games })
            XCTAssertEqual(TutorialItem.filtered(search: "  MetalFrame  ", category: .all).map(\.address), [expected[2]])
            XCTAssertTrue(TutorialItem.filtered(search: "MetalFrame", category: .support).isEmpty)
            XCTAssertEqual(TutorialItem.filtered(search: "", category: .games).suffix(4).map(\.address), expected)
            XCTAssertTrue(all.allSatisfy { $0.url.scheme == "https" })
        }
    }

    func testChartFitsAllLanguagesAndAppearances() throws {
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: AppLanguage.preferenceKey)
        defer { if let old { defaults.set(old, forKey: AppLanguage.preferenceKey) } else { defaults.removeObject(forKey: AppLanguage.preferenceKey) } }
        let now = Date()
        let records = [(200, "69.99"), (120, "27.99"), (80, "69.99"), (20, "27.99")].map { days, price in
            PriceRecordSnapshot(id: UUID(), trackId: "fixture", countryCode: "us", timestamp: now.addingTimeInterval(-Double(days)*86400), price: Decimal(string: price)!, formattedPrice: "$"+price, currency: "USD", recordType: .initial)
        }
        let output = URL(fileURLWithPath: "/tmp/mac-toolbox-404-chart-layout")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in AppLanguage.Preference.allCases where language != .system {
            defaults.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            for scheme in [ColorScheme.light, .dark] {
                for width in [CGFloat(632), CGFloat(900)] {
                    let host = NSHostingView(rootView: PriceHistoryChartView(records: records, currency: "USD")
                        .environment(\.locale, Locale(identifier: AppStrings.localeIdentifier))
                        .preferredColorScheme(scheme).padding(20).background(AppBackgroundView()))
                    let window = NSWindow(contentRect: NSRect(x:0,y:0,width:width,height:550), styleMask:[.borderless], backing:.buffered, defer:false)
                    window.isReleasedWhenClosed=false; window.contentView=host
                    host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                    XCTAssertLessThanOrEqual(host.fittingSize.width, width+1, "\(language) \(width)")
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
                    NSAppearance(named:scheme == .dark ? .darkAqua:.aqua)?.performAsCurrentDrawingAppearance { host.cacheDisplay(in:host.bounds,to:bitmap) }
                    try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:output.appendingPathComponent("chart-\(language.rawValue)-\(Int(width))-\(scheme == .dark ? "dark":"light").png"))
                    window.close()
                }
            }
        }
    }
}
#endif

#if !SWIFT_PACKAGE
private actor Process405Runner: CommandRunning {
    private(set) var requestCount = 0
    private var pending: CheckedContinuation<CommandResult, Error>?
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        requestCount += 1
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func finish(_ output: String) {
        pending?.resume(returning: CommandResult(exitCode: 0, standardOutput: Data(output.utf8), standardError: Data()))
        pending = nil
    }
    func fail() {
        pending?.resume(throwing: ToolboxError.commandFailed("Process fixture failed"))
        pending = nil
    }
}
private actor Process405Privilege: PrivilegedOperating {
    func perform(_ operation: PrivilegedOperation) async throws {}
    func clearSystemCacheEntries(_ entries: [URL]) async throws -> CacheCleanupResult {
        CacheCleanupResult(removedCount: 0, failedItems: [])
    }
}

@MainActor final class Toolbox405Tests: XCTestCase {
    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<400 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for a process fixture")
    }
    private func model(_ runner: Process405Runner) -> AppModel {
        AppModel(launchAutomatically: false, gamingService: GamingService(runner: runner, privileged: Process405Privilege()))
    }
    func testProcessRefreshDeduplicatesPreservesSelectionsAndRecoversFromFailure() async throws {
        let runner = Process405Runner(), model = model(runner)
        XCTAssertEqual(model.runningProcessLoadState, .idle)
        model.loadProcessesForManualSelection()
        model.refreshRunningProcesses()
        XCTAssertTrue(model.isRefreshingRunningProcesses)
        try await waitUntil { await runner.requestCount == 1 }
        await runner.finish("201 1 8.0 /tmp/GameA\n202 1 3.0 /tmp/GameB\n203 1 1.0 /tmp/GameC\n")
        try await waitUntil { !model.isRefreshingRunningProcesses }
        XCTAssertEqual(model.runningProcessLoadState, .loaded)
        XCTAssertEqual(model.runningProcesses.count, 3)
        model.selectedProcessIDs = [201, 202, 203]
        model.refreshRunningProcesses()
        XCTAssertEqual(model.runningProcesses.count, 3)
        XCTAssertEqual(model.selectedProcessIDs, [201, 202, 203])
        try await waitUntil { await runner.requestCount == 2 }
        await runner.finish("201 1 9.0 /tmp/GameA\n202 1 3.0 /tmp/Replacement\n204 1 1.0 /tmp/GameD\n")
        try await waitUntil { !model.isRefreshingRunningProcesses }
        XCTAssertEqual(model.selectedProcessIDs, [201])
        XCTAssertEqual(Set(model.runningProcesses.map(\.pid)), [201, 202, 204])
        model.refreshRunningProcesses()
        try await waitUntil { await runner.requestCount == 3 }
        await runner.fail()
        try await waitUntil { !model.isRefreshingRunningProcesses }
        guard case .failed = model.runningProcessLoadState else { return XCTFail("Expected a readable failure state") }
        XCTAssertEqual(model.runningProcesses.count, 3)
        XCTAssertEqual(model.selectedProcessIDs, [201])
        model.refreshRunningProcesses()
        try await waitUntil { await runner.requestCount == 4 }
        await runner.finish("")
        try await waitUntil { !model.isRefreshingRunningProcesses }
        XCTAssertEqual(model.runningProcessLoadState, .loaded)
        XCTAssertTrue(model.runningProcesses.isEmpty)
        XCTAssertTrue(model.selectedProcessIDs.isEmpty)
    }

    private final class LayoutCapture {
        var frames: [String: CGRect] = [:]
    }

    @discardableResult private func render<V: View>(_ view: V, name: String, size: NSSize, scheme: ColorScheme = .light, button: String? = nil) throws -> NSRect? {
        let capture = LayoutCapture()
        let host = NSHostingView(rootView: ZStack { AppBackgroundView(); view }
            .onPreferenceChange(ToolboxLayoutFrameKey.self) { frames in
                MainActor.assumeIsolated { capture.frames = frames }
            })
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        defer { window.close() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appendingPathComponent("build/405-qa")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        window.appearance?.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: bitmap) }
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
        if let button {
            let frame = try XCTUnwrap(capture.frames[button], "Missing action: \(name)")
            let contentFrame = host.bounds
            XCTAssertGreaterThan(frame.width, 0, name)
            XCTAssertGreaterThanOrEqual(frame.minY, contentFrame.minY - 1, name)
            XCTAssertLessThanOrEqual(frame.maxY, contentFrame.maxY + 1, name)
            XCTAssertGreaterThanOrEqual(frame.minX, contentFrame.minX - 1, name)
            XCTAssertLessThanOrEqual(frame.maxX, contentFrame.maxX + 1, name)
            return frame
        }
        return nil
    }

    func testManualEntryAutomaticallyLoads() async throws {
        let runner = Process405Runner(), model = model(runner), localization = LocalizationController()
        let host = NSHostingView(rootView: ProcessPriorityDetailView(initialMode: .manual).environmentObject(model).environmentObject(localization))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 610), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await waitUntil { await runner.requestCount == 1 }
        await runner.finish("201 1 5.0 /tmp/GameA\n")
        try await waitUntil { !model.isRefreshingRunningProcesses }
        XCTAssertEqual(model.runningProcesses.map(\.pid), [201])
        window.close()
    }

    func testAdaptivePagesFitNineLanguagesAndBothAppearances() throws {
        let defaults = UserDefaults.standard, old = defaults.object(forKey: AppLanguage.preferenceKey)
        defer { if let old { defaults.set(old, forKey: AppLanguage.preferenceKey) } else { defaults.removeObject(forKey: AppLanguage.preferenceKey) } }
        let model = AppModel(launchAutomatically: false), localization = LocalizationController()
        model.runningProcesses = (201...220).map { SystemProcess(pid: Int32($0), parentPID: 1, command: "/Applications/Long Game Name.app/Contents/MacOS/ExampleGame-\($0)", cpuUsage: 8) }
        model.iosDevices = [IOSDevice(id: "fixture", name: "Test iPhone", model: "iPhone", state: "connected")]
        model.selectedIOSDeviceID = "fixture"
        model.iosApps = (1...20).map { IOSInstalledApp(bundleIdentifier: "local.fixture.\($0)", displayName: "Example Game \($0)", version: "1.0") }
        model.selectedIOSBundleIdentifier = "local.fixture.1"
        for language in AppLanguage.Preference.allCases where language != .system {
            localization.setPreference(language)
            for scheme in [ColorScheme.light, .dark] {
                for size in [NSSize(width: 612, height: 540), NSSize(width: 840, height: 660)] {
                    let label = "\(language.rawValue)-\(scheme == .dark ? "dark" : "light")-\(Int(size.width))"
                    try render(ProcessPriorityDetailView(initialMode: .manual, automaticallyLoadsProcesses: false)
                        .environmentObject(model).environmentObject(localization).preferredColorScheme(scheme),
                        name: "process-" + label, size: size, scheme: scheme, button: "process.apply")
                    try render(MetalHUDDetailView(initialMode: .ios, automaticallyLoadsDevices: false)
                        .environmentObject(model).environmentObject(localization).preferredColorScheme(scheme),
                        name: "ios-" + label, size: size, scheme: scheme, button: "metalHUD.ios.launch")
                }
            }
        }
    }

    func testProcessStatesKeepActionsAtTheSameHeight() async throws {
        let runner = Process405Runner(), model = model(runner), localization = LocalizationController()
        let size = NSSize(width: 612, height: 540)
        func snapshot(_ state: String) throws -> NSRect? {
            try render(ProcessPriorityDetailView(initialMode: .manual, automaticallyLoadsProcesses: false)
                .environmentObject(model).environmentObject(localization), name: "state-" + state, size: size, button: "process.apply")
        }
        let idle = try snapshot("idle")
        model.refreshRunningProcesses()
        let loading = try snapshot("loading")
        try await waitUntil { await runner.requestCount == 1 }
        await runner.fail()
        try await waitUntil { !model.isRefreshingRunningProcesses }
        let failed = try snapshot("failed")
        model.refreshRunningProcesses()
        try await waitUntil { await runner.requestCount == 2 }
        await runner.finish("201 1 8.0 /tmp/GameA\n")
        try await waitUntil { !model.isRefreshingRunningProcesses }
        let loaded = try snapshot("loaded")
        XCTAssertEqual(idle, loading)
        XCTAssertEqual(idle, failed)
        XCTAssertEqual(idle, loaded)
    }

    func testArgumentsMoveToSheetWithoutLosingDraft() async throws {
        let model = AppModel(launchAutomatically: false), localization = LocalizationController(), capture = LayoutCapture()
        let app = IOSInstalledApp(bundleIdentifier: "local.fixture.game", displayName: "Fixture Game", version: "1.0")
        model.iosDevices = [IOSDevice(id: "fixture", name: "Test iPhone", state: "connected")]
        model.selectedIOSDeviceID = "fixture"; model.iosApps = [app]
        let host = NSHostingView(rootView: MetalHUDDetailView(initialMode: .ios, automaticallyLoadsDevices: false)
            .environmentObject(model).environmentObject(localization)
            .onPreferenceChange(ToolboxLayoutFrameKey.self) { frames in
                MainActor.assumeIsolated { capture.frames = frames }
            })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 920), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.title = "Launch Arguments Layout Test"
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        model.editIOSLaunchArguments(for: app)
        model.iosLaunchArgumentsText = "--fixture\nunsaved draft"
        try await waitUntil { capture.frames["metalHUD.ios.arguments"] != nil }
        XCTAssertTrue(window.sheets.isEmpty)
        window.setContentSize(NSSize(width: 612, height: 540))
        host.layoutSubtreeIfNeeded()
        try await waitUntil { !window.sheets.isEmpty }
        XCTAssertEqual(model.iosLaunchArgumentsText, "--fixture\nunsaved draft")
        window.setContentSize(NSSize(width: 900, height: 920))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.sheets.count, 1)
        XCTAssertEqual(model.iosLaunchArgumentsText, "--fixture\nunsaved draft")
        model.iosLaunchArgumentsApp = nil
        try await waitUntil { window.sheets.isEmpty }
        window.close()
    }

    func testHoYoHostnameStatesRenderWithoutChangingHostnames() throws {
        let model = AppModel(launchAutomatically: false), localization = LocalizationController()
        try render(SteamDeckModeSection().environmentObject(model).environmentObject(localization),
            name: "hostname-original", size: NSSize(width: 840, height: 500))
        model.configuration.hostnameBackup = HostnameBackup(computerName: "Fixture Mac", hostName: "fixture", localHostName: "fixture")
        try render(SteamDeckModeSection().environmentObject(model).environmentObject(localization),
            name: "hostname-steamdeck", size: NSSize(width: 840, height: 500))
    }

}
#endif
