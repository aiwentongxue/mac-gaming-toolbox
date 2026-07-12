import AppKit
import SwiftUI

@main
struct MacGameToolboxApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window(tr("Mac游戏工具箱", "Mac Game Toolbox"), id: "main") {
            DashboardView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 650)
        }
        .defaultSize(width: 1040, height: 760)
        .commandsReplaced {
            CommandMenu(tr("编辑", "Edit")) {
                Button(tr("撤销", "Undo")) { MenuCommandCoordinator.send(#selector(UndoManager.undo)) }
                    .keyboardShortcut("z")
                Button(tr("重做", "Redo")) { MenuCommandCoordinator.send(#selector(UndoManager.redo)) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                Divider()
                Button(tr("剪切", "Cut")) { MenuCommandCoordinator.send(#selector(NSText.cut(_:))) }
                    .keyboardShortcut("x")
                Button(tr("拷贝", "Copy")) { MenuCommandCoordinator.send(#selector(NSText.copy(_:))) }
                    .keyboardShortcut("c")
                Button(tr("粘贴", "Paste")) { MenuCommandCoordinator.send(#selector(NSText.paste(_:))) }
                    .keyboardShortcut("v")
                Button(tr("全选", "Select All")) { MenuCommandCoordinator.send(#selector(NSText.selectAll(_:))) }
                    .keyboardShortcut("a")
            }
            CommandMenu(tr("显示", "View")) {
                Button(tr("进入全屏幕", "Enter Full Screen")) { MenuCommandCoordinator.shared.toggleFullScreen() }
                    .keyboardShortcut("f", modifiers: [.function])
            }
            CommandMenu(tr("问题解决", "Troubleshooting")) {
                Button(tr("导出诊断日志", "Export Diagnostics")) { MenuCommandCoordinator.shared.exportDiagnostics() }
                Button(tr("修复核心功能", "Repair Core Features")) { MenuCommandCoordinator.shared.repairCoreFeatures() }
            }
            CommandMenu(tr("窗口", "Window")) {
                Button(tr("最小化", "Minimize")) { MenuCommandCoordinator.shared.minimize() }
                    .keyboardShortcut("m")
                Button(tr("缩放", "Zoom")) { MenuCommandCoordinator.shared.zoom() }
                Button(tr("填充", "Fill")) { MenuCommandCoordinator.shared.fill() }
                    .keyboardShortcut("f", modifiers: [.control, .function])
                Button(tr("居中", "Center")) { MenuCommandCoordinator.shared.center() }
                    .keyboardShortcut("c", modifiers: [.control, .function])
            }
            CommandMenu(tr("帮助", "Help")) {
                Button(tr("教程总导航", "Tutorials")) { MenuCommandCoordinator.shared.showTutorials() }
            }
        }
    }
}

@MainActor
final class MenuCommandCoordinator {
    static let shared = MenuCommandCoordinator()
    private weak var model: AppModel?

    func install(model: AppModel) {
        self.model = model
    }

    static func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    func minimize() { (NSApp.keyWindow ?? NSApp.mainWindow)?.miniaturize(nil) }
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
