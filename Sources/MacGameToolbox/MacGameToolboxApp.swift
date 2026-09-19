import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MacGameToolboxClickFlow
#endif

@main
struct MacGameToolboxApp: App {
    @NSApplicationDelegateAdaptor(MacGameToolboxApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model = AppModel()
    @StateObject private var localization = LocalizationController()
    @StateObject private var clickFlowController = ClickFlowFeatureController()

    var body: some Scene {
        Window(tr("Mac游戏工具箱", "Mac Game Toolbox"), id: "main") {
            MainContentView(clickFlowController: clickFlowController)
                .environmentObject(model)
                .environmentObject(localization)
                .id(localization.refreshToken)
                .frame(minWidth: 900, minHeight: 650)
                .onAppear {
                    applicationDelegate.shutdownHandler = { clickFlowController.shutdown() }
                }
        }
        .defaultSize(width: 1040, height: 760)
        .commandsReplaced {
            CommandGroup(replacing: .appInfo) {
                Button(tr("关于 Mac游戏工具箱", "About Mac Game Toolbox")) {
                    MenuCommandCoordinator.shared.showAboutPanel()
                }
            }
            CommandGroup(replacing: .appTermination) {
                Button(tr("退出Mac游戏工具箱", "Quit Mac Game Toolbox")) {
                    MenuCommandCoordinator.shared.quitApplication()
                }
                .keyboardShortcut("q")
            }
            CommandGroup(replacing: .windowSize) { }
        }
        .commands {
            CommandMenu(tr("帮助", "Help")) {
                Button(tr("导出诊断日志", "Export Diagnostics")) { MenuCommandCoordinator.shared.exportDiagnostics() }
                Button(tr("修复核心功能", "Repair Core Features")) { MenuCommandCoordinator.shared.repairCoreFeatures() }
                Button(tr("教程总导航", "Tutorials")) { MenuCommandCoordinator.shared.showTutorials() }
            }
        }
        Settings {
            SettingsView()
                .environmentObject(localization)
        }
    }
}

final class MacGameToolboxApplicationDelegate: NSObject, NSApplicationDelegate {
    var shutdownHandler: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard UpdateCheckPreference.isEnabled else { return }

        Task {
            guard let release = await GitHubReleaseChecker.latestStableRelease(),
                  GitHubReleaseChecker.isNewer(release.version, than: GitHubReleaseChecker.currentVersion) else {
                return
            }

            await MainActor.run { [weak self] in
                self?.showUpdateAlert(for: release)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutdownHandler?()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if MenuCommandCoordinator.shared.consumeExplicitQuitRequest() {
            return .terminateNow
        }
        if NSAppleEventManager.shared().currentAppleEvent?.eventID == 0x7175_6974 {
            return .terminateNow
        }
        return .terminateCancel
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            MenuCommandCoordinator.shared.reopenMainWindow()
        }
        return true
    }

    @MainActor
    private func showUpdateAlert(for release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = tr("发现新版本", "New Version Available")
        alert.informativeText = tr(
            "Mac游戏工具箱 \(release.version) 已发布，当前版本为 \(GitHubReleaseChecker.currentVersion)。是否前往 Releases 页面下载更新？",
            "Mac Game Toolbox \(release.version) is available. Your current version is \(GitHubReleaseChecker.currentVersion). Open the Releases page to download it?"
        )
        alert.addButton(withTitle: tr("前往更新", "Update"))
        alert.addButton(withTitle: tr("暂不更新", "Not Now"))

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(GitHubReleaseChecker.releasesPageURL)
        }
    }
}

enum UpdateCheckPreference {
    static let key = "automaticallyCheckForUpdates"

    static var isEnabled: Bool {
        // A missing value represents the default-on preference for existing users too.
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}

struct GitHubRelease: Sendable {
    let version: String
}

enum GitHubReleaseChecker {
    static let releasesPageURL = URL(string: "https://github.com/aiwentongxue/mac-gaming-toolbox/releases/latest")!
    private static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/aiwentongxue/mac-gaming-toolbox/releases/latest")!

    static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "3.2.1"
    }

    static func latestStableRelease() async -> GitHubRelease? {
        var request = URLRequest(url: latestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacGameToolbox", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            let payload = try JSONDecoder().decode(LatestReleasePayload.self, from: data)
            let version = payload.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
            return version.isEmpty ? nil : GitHubRelease(version: version)
        } catch {
            // Update checks are intentionally silent when offline or GitHub is unavailable.
            return nil
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        normalizedVersion(candidate).compare(normalizedVersion(current), options: .numeric) == .orderedDescending
    }

    private static func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first?.lowercased() == "v" ? String(trimmed.dropFirst()) : trimmed
    }

    private struct LatestReleasePayload: Decodable {
        let tagName: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }
    }
}

@MainActor
final class MenuCommandCoordinator: NSObject {
    static let shared = MenuCommandCoordinator()
    private weak var model: AppModel?
    private var keyMonitor: Any?
    private var explicitQuitRequested = false
    private var menuObserverInstalled = false
    private var isReorderingMenus = false

    func install(model: AppModel) {
        self.model = model
        installMenuOrderObserverIfNeeded()
        stabilizeTopLevelMenuOrder()
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let relevantModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard relevantModifiers == .command else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "w":
                self?.closeWindow()
                return nil
            case "q":
                self?.quitApplication()
                return nil
            default:
                return event
            }
        }
    }

    private func installMenuOrderObserverIfNeeded() {
        guard !menuObserverInstalled else { return }
        menuObserverInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainMenuDidAddItem(_:)),
            name: NSMenu.didAddItemNotification,
            object: nil
        )
    }

    @objc private func mainMenuDidAddItem(_ notification: Notification) {
        guard let changedMenu = notification.object as? NSMenu,
              changedMenu === NSApp.mainMenu else { return }
        stabilizeTopLevelMenuOrder()
    }

    private func stabilizeTopLevelMenuOrder() {
        guard !isReorderingMenus, let menu = NSApp.mainMenu else { return }
        isReorderingMenus = true
        if let viewItem = menu.items.first(where: { $0.title == tr("显示", "View") }) {
            menu.removeItem(viewItem)
        }
        if let windowItem = menu.items.first(where: { $0.title == tr("窗口", "Window") }),
           let helpItem = menu.items.first(where: { $0.title == tr("帮助", "Help") }),
           menu.index(of: helpItem) < menu.index(of: windowItem) {
            menu.removeItem(helpItem)
            menu.insertItem(helpItem, at: menu.index(of: windowItem) + 1)
        }
        isReorderingMenus = false
    }

    func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(options: [:])
    }

    func quitApplication() {
        explicitQuitRequested = true
        NSApp.terminate(nil)
    }

    func consumeExplicitQuitRequest() -> Bool {
        guard explicitQuitRequested else { return false }
        explicitQuitRequested = false
        return true
    }

    static func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    func minimize() { (NSApp.keyWindow ?? NSApp.mainWindow)?.miniaturize(nil) }
    func closeWindow() {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.orderOut(nil)
    }
    func reopenMainWindow() {
        let window = NSApp.windows.first { window in
            !(window is NSPanel) && window.canBecomeMain
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func zoom() { (NSApp.keyWindow ?? NSApp.mainWindow)?.performZoom(nil) }
    func toggleFullScreen() { (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil) }
    func center() { (NSApp.keyWindow ?? NSApp.mainWindow)?.center() }

    func fill() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let screen = window.screen ?? NSScreen.main else { return }
        window.setFrame(screen.visibleFrame, display: true, animate: true)
    }

    func exportDiagnostics() { model?.requestDiagnosticsExport() }
    func repairCoreFeatures() { model?.repairCoreFeatures() }
    func showTutorials() { model?.showingTutorials = true }
}
