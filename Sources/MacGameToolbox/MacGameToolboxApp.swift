import AppKit
import Carbon
import SwiftUI

@main
struct MacGameToolboxApp: App {
    @NSApplicationDelegateAdaptor(MacGameToolboxApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window(tr("Mac游戏工具箱", "Mac Game Toolbox"), id: "main") {
            DashboardView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 650)
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
            CommandMenu(tr("游戏工具", "Game Tools")) {
                Button(tr("切换 Mac 触控板", "Toggle Mac Trackpad")) {
                    MenuCommandCoordinator.shared.toggleTrackpad()
                }
                .keyboardShortcut("t", modifiers: [.control, .option])
            }
            CommandMenu(tr("帮助", "Help")) {
                Button(tr("导出诊断日志", "Export Diagnostics")) { MenuCommandCoordinator.shared.exportDiagnostics() }
                Button(tr("修复核心功能", "Repair Core Features")) { MenuCommandCoordinator.shared.repairCoreFeatures() }
                Button(tr("教程总导航", "Tutorials")) { MenuCommandCoordinator.shared.showTutorials() }
            }
        }
    }
}

final class MacGameToolboxApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
}

@MainActor
final class MenuCommandCoordinator: NSObject {
    static let shared = MenuCommandCoordinator()
    private weak var model: AppModel?
    private var keyMonitor: Any?
    private var trackpadHotKey: GlobalHotKey?
    private var explicitQuitRequested = false
    private var menuObserverInstalled = false
    private var isReorderingMenus = false

    func install(model: AppModel) {
        self.model = model
        installMenuOrderObserverIfNeeded()
        stabilizeTopLevelMenuOrder()
        if trackpadHotKey == nil {
            trackpadHotKey = GlobalHotKey.register(
                keyCode: UInt32(kVK_ANSI_T),
                modifiers: UInt32(controlKey | optionKey)
            ) {
                Task { @MainActor in MenuCommandCoordinator.shared.toggleTrackpad() }
            }
            if trackpadHotKey == nil {
                DiagnosticFileLogger.write("Unable to register global trackpad shortcut: Control-Option-T")
            }
        }
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
    func toggleTrackpad() { model?.toggleTrackpadDisabledWhenMouseConnected() }
}

private final class GlobalHotKey: @unchecked Sendable {
    private let action: @Sendable () -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?

    private init(action: @escaping @Sendable () -> Void) {
        self.action = action
    }

    static func register(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping @Sendable () -> Void
    ) -> GlobalHotKey? {
        let instance = GlobalHotKey(action: action)
        return instance.install(keyCode: keyCode, modifiers: modifiers) ? instance : nil
    }

    private func install(keyCode: UInt32, modifiers: UInt32) -> Bool {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().action()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else { return false }

        let identifier = EventHotKeyID(signature: OSType(0x4D47_5442), id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &hotKey
        )
        if hotKeyStatus != noErr {
            if let eventHandler { RemoveEventHandler(eventHandler) }
            eventHandler = nil
            return false
        }
        return true
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
