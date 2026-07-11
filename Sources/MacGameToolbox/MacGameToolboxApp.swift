import SwiftUI

@main
struct MacGameToolboxApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(tr("Mac游戏工具箱", "Mac Game Toolbox")) {
            DashboardView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 650)
        }
        .defaultSize(width: 1040, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(tr("新Mac游戏工具箱窗口", "New Mac Game Toolbox Window")) {}
                    .keyboardShortcut("n")
                    .disabled(true)
            }
            CommandMenu(tr("问题解决", "Troubleshooting")) {
                Button(tr("导出诊断日志", "Export Diagnostics")) {
                    model.requestDiagnosticsExport()
                }
                Button(tr("修复核心功能", "Repair Core Features")) {
                    model.repairCoreFeatures()
                }
            }
        }
    }
}
