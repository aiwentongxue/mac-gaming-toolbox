import AppKit
import AppDropCore
import ServiceManagement
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
    @StateObject private var appDropController = AppDropFeatureController()

    var body: some Scene {
        Window(tr("Mac游戏工具箱", "Mac Game Toolbox"), id: "main") {
            MainContentView(
                clickFlowController: clickFlowController,
                appDropController: appDropController
            )
                .environmentObject(model)
                .environmentObject(localization)
                .id(localization.refreshToken)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    applicationDelegate.shutdownHandler = { clickFlowController.shutdown() }
                    applicationDelegate.openFilesHandler = { urls in
                        appDropController.open(urls: urls)
                    }
                    let queued = AppEventBus.shared.queuedFileURLs
                    if !queued.isEmpty {
                        appDropController.open(urls: queued)
                        AppEventBus.shared.queuedFileURLs.removeAll()
                    }
                }
        }
        .defaultSize(width: 1120, height: 760)
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
            CommandGroup(replacing: .help) {
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
    var openFilesHandler: (([URL]) -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--unregister-appdrop-helper") {
            let service = SMAppService.agent(
                plistName: SharedConstants.helperAgentPlistName
            )
            try? service.unregister()
            DispatchQueue.main.async {
                MenuCommandCoordinator.shared.quitApplication()
            }
            return
        }
        guard UpdateCheckPreference.isEnabled else { return }

        Task {
            guard case let .available(release) = await GitHubReleaseChecker.check() else {
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

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if let openFilesHandler {
            openFilesHandler(urls)
        } else {
            AppEventBus.shared.queuedFileURLs.append(contentsOf: urls)
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let openFilesHandler {
            openFilesHandler(urls)
        } else {
            AppEventBus.shared.queuedFileURLs.append(contentsOf: urls)
        }
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

enum GitHubUpdateCheckResult: Sendable, Equatable {
    case available(GitHubRelease)
    case upToDate(currentVersion: String)
    case rateLimited
    case failed(message: String)
}

extension GitHubRelease: Equatable {}

enum GitHubReleaseChecker {
    static let releasesPageURL = URL(string: "https://github.com/aiwentongxue/mac-gaming-toolbox/releases/latest")!
    private static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/aiwentongxue/mac-gaming-toolbox/releases/latest")!
    private static let releasesAtomURL = URL(string: "https://github.com/aiwentongxue/mac-gaming-toolbox/releases.atom")!

    static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "3.2.1"
    }

    static func check(
        currentVersion: String = currentVersion,
        session: URLSession = .shared
    ) async -> GitHubUpdateCheckResult {
        var apiWasRateLimited = false

        do {
            let version = try await fetchAPIVersion(session: session)
            return result(for: version, currentVersion: currentVersion)
        } catch let error as UpdateFetchError {
            apiWasRateLimited = error == .rateLimited
        } catch {
            // Fall through to public GitHub endpoints below.
        }

        do {
            let version = try await fetchAtomVersion(session: session)
            return result(for: version, currentVersion: currentVersion)
        } catch {
            // The redirect endpoint is a final fallback when the Atom feed is
            // unavailable but the public Releases page is still reachable.
        }

        do {
            let version = try await fetchRedirectVersion(session: session)
            return result(for: version, currentVersion: currentVersion)
        } catch {
            if apiWasRateLimited {
                return .rateLimited
            }
            return .failed(
                message: tr(
                    "无法连接 GitHub 检查更新，请稍后重试。",
                    "GitHub could not be reached to check for updates. Please try again later."
                )
            )
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        normalizedVersion(candidate).compare(normalizedVersion(current), options: .numeric) == .orderedDescending
    }

    static func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first?.lowercased() == "v" ? String(trimmed.dropFirst()) : trimmed
    }

    static func versionFromReleasePath(_ path: String) -> String? {
        guard let range = path.range(of: "/releases/tag/") else { return nil }
        let value = path[range.upperBound...]
            .split(separator: "/")
            .first
            .map(String.init)?
            .removingPercentEncoding
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func result(
        for version: String,
        currentVersion: String
    ) -> GitHubUpdateCheckResult {
        isNewer(version, than: currentVersion)
            ? .available(GitHubRelease(version: version))
            : .upToDate(currentVersion: currentVersion)
    }

    private static func request(for url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("MacGameToolbox", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        return request
    }

    private static func fetchAPIVersion(session: URLSession) async throws -> String {
        let request = request(for: latestReleaseAPIURL, accept: "application/vnd.github+json")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateFetchError.invalidResponse
        }
        if httpResponse.statusCode == 403,
           httpResponse.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
            throw UpdateFetchError.rateLimited
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw UpdateFetchError.httpStatus(httpResponse.statusCode)
        }
        let payload = try JSONDecoder().decode(LatestReleasePayload.self, from: data)
        let version = payload.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { throw UpdateFetchError.invalidResponse }
        return version
    }

    private static func fetchAtomVersion(session: URLSession) async throws -> String {
        let request = request(
            for: releasesAtomURL,
            accept: "application/atom+xml, application/xml;q=0.9, text/xml;q=0.8"
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw UpdateFetchError.invalidResponse
        }
        let parser = AtomReleaseParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse(), let version = parser.latestVersion, !version.isEmpty else {
            throw UpdateFetchError.invalidResponse
        }
        return version
    }

    private static func fetchRedirectVersion(session: URLSession) async throws -> String {
        let request = request(for: releasesPageURL, accept: "text/html")
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let finalURL = response.url,
              let version = versionFromReleasePath(finalURL.path),
              !version.isEmpty else {
            throw UpdateFetchError.invalidResponse
        }
        return version
    }

    private enum UpdateFetchError: Error, Equatable {
        case rateLimited
        case invalidResponse
        case httpStatus(Int)
    }

    private struct LatestReleasePayload: Decodable {
        let tagName: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }
    }
}

private final class AtomReleaseParser: NSObject, XMLParserDelegate {
    private var isInsideEntry = false
    private var didCaptureFirstEntryLink = false
    private var firstEntryLink: String?
    private var firstEntryId: String?
    private var isInsideId = false
    private var currentText = ""

    var latestVersion: String? {
        if let firstEntryLink,
           let version = GitHubReleaseChecker.versionFromReleasePath(firstEntryLink) {
            return version
        }
        guard let firstEntryId else { return nil }
        let suffix = firstEntryId.split(separator: "/").last.map(String.init)
        return suffix
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "entry", firstEntryLink == nil, firstEntryId == nil {
            isInsideEntry = true
            didCaptureFirstEntryLink = false
        }
        guard isInsideEntry else { return }
        if elementName == "link",
           !didCaptureFirstEntryLink,
           attributeDict["rel"] == "alternate",
           let href = attributeDict["href"] {
            firstEntryLink = href
            didCaptureFirstEntryLink = true
        } else if elementName == "id", firstEntryId == nil {
            isInsideId = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideId else { return }
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "id", isInsideId, firstEntryId == nil {
            firstEntryId = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            isInsideId = false
            currentText = ""
        } else if elementName == "entry" {
            isInsideEntry = false
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
    func showTutorials() {
        NotificationCenter.default.post(name: .toolboxNavigateToTutorials, object: nil)
    }
}
