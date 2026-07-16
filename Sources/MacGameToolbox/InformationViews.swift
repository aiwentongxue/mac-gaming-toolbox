import SwiftUI

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("3.0.5") {
                    Text(tr("更新应用图标，采用铺满画布的蓝紫色背景", "Updated the app icon with a blue-purple background that fills the canvas"))
                    Text(tr("移除磁盘挂载数量限制，支持选择、批量挂载和自动恢复任意数量的磁盘", "Removed the disk mount limit and added support for selecting, batch-mounting, and automatically restoring any number of volumes"))
                    Text(tr("优化磁盘选择计数，仅显示当前已选择数量", "Simplified the disk selection counter to show only the current selection count"))
                    Text(tr("修复自动恢复将扫描次数误当成秒数的问题，改为按真实经过时间触发", "Fixed automatic restoration treating scan cycles as seconds; it now triggers using real elapsed time"))
                    Text(tr("挂载后会等待系统更新状态并核对规范路径，避免实际成功却显示失败", "Mount verification now waits for system state updates and compares canonical paths to avoid false failure reports"))
                    Text(tr("挂载确认失败时会完整回滚当前卷和已处理卷，避免残留错误挂载", "A failed mount verification now rolls back both the current volume and previously processed volumes to prevent incorrect residual mounts"))
                }
                Section("3.0.4") {
                    Text(tr("更新应用图标，移除工具箱正面的苹果标志", "Updated the app icon and removed the Apple logo from the front of the toolbox"))
                    Text(tr("将同时选择、批量挂载和自动恢复的磁盘上限由 3 提高到 999", "Raised the limit for selected, batch-mounted, and automatically restored volumes from 3 to 999"))
                }
                Section("3.0.3") {
                    Text(tr("恢复 ⌘W 隐藏窗口但保持应用运行，以及 ⌘Q、应用菜单和 Dock 正常退出", "Restored Command-W to hide the window while keeping the app running, while Command-Q, the app menu, and Dock quit normally"))
                    Text(tr("稳定菜单栏结构：保留“关于”和系统窗口管理，并将诊断、修复和教程集中到帮助菜单", "Stabilized the menu bar with About, system window controls, and diagnostics, repair, and tutorials in Help"))
                    Text(tr("调整首页顺序：导入壁纸、教程总导航、更新日志依次排列", "Reordered the dashboard cards to Import Wallpaper, Tutorial Hub, then Changelog"))
                }
                Section("3.0.2") {
                    Text(tr("修复窗口菜单在启动后闪变的问题，稳定保留最小化、缩放、填充和居中", "Fixed the Window menu changing shortly after launch and kept Minimize, Zoom, Fill, and Center stable"))
                    Text(tr("移除“显示”菜单中的标签页栏和所有标签页命令", "Removed the tab bar and tab overview commands from the View menu"))
                }
                Section("3.0.1") {
                    Text(tr("将 MetalHUD 的单 App 启用按钮移动到选项框右下角", "Moved the per-app MetalHUD button to the lower-right corner of its card"))
                    Text(tr("修复安全缓存清理遇到无权限文件时提前终止的问题", "Fixed safe cache cleanup stopping when it encounters inaccessible files"))
                    Text(tr("修复窗口菜单在应用启动后自动缩减的问题", "Fixed the Window menu collapsing shortly after app launch"))
                }
                Section("3.0.0") {
                    Text(tr("MetalHUD 新增最近 App 启动台，可快速重开、移除记录或选择其他 App", "Added a MetalHUD recent-app launcher with quick reopen, removal, and Other App selection"))
                    Text(tr("HoYoGames 启动帮助新增 10、15、20 秒等待时间", "Added 10, 15, and 20 second wait options to the HoYoGames Launch Assistant"))
                    Text(tr("CrossOver 优先级优化新增手动选择进程", "Added manual process selection for CrossOver priority optimization"))
                    Text(tr("磁盘挂载新增手动恢复上次挂载", "Added manual restoration of previous disk mounts"))
                    Text(tr("缓存清理新增默认开启的敏感文件排除模式", "Added a sensitive-file exclusion mode enabled by default for cache cleanup"))
                }
                Section("2.4.0") {
                    Text(tr("MetalHUD 开关更名为“全局启用”，明确其作用范围", "Renamed the MetalHUD switch to “Enable globally” to clarify its scope"))
                    Text(tr("新增对单个 App 启用 MetalHUD，可从应用程序目录选择并立即启动", "Added per-app MetalHUD launch from the Applications folder"))
                }
                Section("2.3.0") {
                    Text(tr("更新应用图标，优化品牌识别；同步版本到 2.3.0", "Updated the app icon, refined brand recognition, and synchronized the version to 2.3.0"))
                }
                Section("2.2.1") {
                    Text(tr("恢复默认壁纸时会自动删除已导入的旧壁纸，减少储存空间占用", "Resetting the wallpaper now removes previously imported wallpaper files to save storage space"))
                }
                Section("2.2.0") {
                    Text(tr("新增 macOS 26 液态玻璃主界面效果", "Added macOS 26 Liquid Glass effects to the dashboard"))
                    Text(tr("自定义壁纸在玻璃界面下更通透", "Custom wallpapers now show through the glass interface more clearly"))
                    Text(tr("导入壁纸后固定使用深色玻璃界面", "After importing a wallpaper, the dashboard now uses the dark glass interface"))
                    Text(tr("macOS 14 与 macOS 15 继续使用原有兼容界面", "macOS 14 and macOS 15 continue using the existing compatible interface"))
                }
                Section("2.1.0") {
                    Text(tr("主界面标题移到窗口最上方栏位", "Moved the dashboard title into the top window bar"))
                    Text(tr("导出诊断日志入口移到 macOS 顶部菜单栏", "Moved Export Diagnostics to the macOS menu bar"))
                    Text(tr("新增导入自定义壁纸，背景会按比例填充界面且不拉伸", "Added custom wallpaper import with proportional fill and no stretching"))
                }
                Section("2.0.2") {
                    Text(tr("修复作为登录项后台启动时自动挂载任务未运行的问题", "Fixed automatic mounting not starting when the app launches as a background login item"))
                    Text(tr("自动检测与挂载现在随应用进程启动，不再依赖主窗口打开", "Automatic detection and mounting now start with the app process and no longer depend on opening the main window"))
                }
                Section("2.0.1") {
                    Text(tr("修复开机后未及时识别外接磁盘时无法自动挂载的问题", "Fixed automatic mounting when external volumes are not detected immediately after startup"))
                    Text(tr("开启自动恢复后每秒自动刷新可用磁盘", "Available volumes now refresh every second while automatic restoration is enabled"))
                    Text(tr("自动恢复等待时间由 5 秒调整为 10 秒", "Changed the automatic restoration delay from 5 seconds to 10 seconds"))
                    Text(tr("推出或卸载磁盘不再清除恢复记录，仅恢复默认挂载会清除", "Ejecting or unmounting no longer clears restoration records; only restoring the default mount clears them"))
                    Text(tr("使用卷 UUID 识别磁盘，避免重启后设备编号变化导致恢复失败", "Volumes are matched by UUID to handle device identifier changes after restart"))
                }
                Section("2.0.0") {
                    Text(tr("新增开启应用 5 秒后自动恢复上次自定义挂载", "Added automatic restoration of previous custom mounts 5 seconds after launch"))
                    Text(tr("可配合系统“登录时打开”实现开机自动挂载", "Works with macOS Open at Login for automatic mounting after startup"))
                    Text(tr("磁盘推出或恢复默认挂载后不再自动恢复", "Ejected volumes and volumes restored to default mounting are no longer restored automatically"))
                }
                Section("1.2.0") {
                    Text(tr("更新主界面功能名称与说明", "Updated dashboard feature names and descriptions"))
                    Text(tr("新增艾文哔哩哔哩主页快捷链接", "Added a shortcut to Iven's Bilibili profile"))
                }
                Section("1.1.0") {
                    Text(tr("新增首次启动授权引导与系统设置快捷入口", "Added first-launch authorization guidance and System Settings shortcuts"))
                    Text(tr("新增专属应用图标", "Added a dedicated application icon"))
                    Text(tr("中文与英文界面现在会根据系统语言自动切换", "Chinese and English interfaces now switch automatically based on system language"))
                    Text(tr("HoYoGames 启动帮助现在会显示倒计时", "HoYoGames Launch Assistant now displays the remaining countdown time"))
                    Text(tr("诊断日志现在可以自定义导出位置", "Diagnostic logs can now be exported to a custom location"))
                    Text(tr("界面现在会自动适配系统浅色或深色外观", "The interface now follows the system light or dark appearance"))
                    Text(tr("优化了教程导航的字号和行间距", "Improved font size and spacing in the Tutorial Hub"))
                }
                Section("1.0.4") {
                    Text(tr("HoYo 启动帮助固定等待 15 秒后检测", "HoYo checks once after a 15-second wait"))
                    Text(tr("使用同一次检测结果提升优先级并恢复 hosts", "Uses one scan result to update process priority and restore hosts"))
                }
                Section("1.0.3") {
                    Text(tr("修复大输出子进程管道死锁", "Fixed a process pipe deadlock with large output"))
                    Text(tr("修复 HoYo、CrossOver 扫描与诊断导出卡住", "Fixed blocked HoYo and CrossOver scans and diagnostic exports"))
                    Text(tr("诊断文件立即落盘", "Diagnostic files are now created immediately"))
                }
                Section("1.0.2") {
                    Text(tr("修复授权辅助程序更新注册失败", "Fixed privileged helper update registration"))
                    Text(tr("为特权请求增加 8 秒超时", "Added an 8-second timeout for privileged requests"))
                    Text(tr("诊断日志固定保存并自动在访达中显示", "Made diagnostic export reliable and reveals the file in Finder"))
                }
                Section("1.0.1") {
                    Text(tr("修复 HoYoGames 与 CrossOver 进程识别", "Fixed HoYoGames and CrossOver process detection"))
                    Text(tr("修复 APFS 卷遗漏与系统卷过滤", "Fixed APFS volume discovery and system volume filtering"))
                    Text(tr("修复未设置设备名称时的 SteamDeck 切换", "Fixed SteamDeck switching when the hostname is missing"))
                    Text(tr("新增诊断日志导出", "Added diagnostic log export"))
                }
                Section("1.0.0") {
                    Text(tr("全新原生 SwiftUI 应用", "New native SwiftUI application"))
                    Text(tr("整合磁盘挂载工具", "Integrated volume mounting"))
                    Text(tr("统一系统授权与任务状态", "Unified system authorization and task status"))
                    Text(tr("支持 Intel 与 Apple Silicon", "Added Intel and Apple Silicon support"))
                }
            }
            .navigationTitle(tr("更新日志", "Changelog"))
            .toolbar { Button(tr("完成", "Done")) { dismiss() } }
        }
        .frame(minWidth: 580, minHeight: 420)
    }
}

struct TutorialsView: View {
    @Environment(\.dismiss) private var dismiss

    private var links: [(String, String)] {
        if AppLanguage.isChinese {
            return [
                ("Mac 玩游戏从入门到精通", "https://b23.tv/pEOGX4P"),
                ("CrossOver 零基础入门指南", "https://b23.tv/SlpOQoA"),
                ("CrossOver 全部教程合集", "https://b23.tv/V5xIKy4"),
                ("CrossOver 疑难解答合集", "https://b23.tv/8l2dLbN"),
                ("问题反馈与日志教程", "https://b23.tv/1UfRohG"),
                ("艾文的哔哩哔哩主页", "https://b23.tv/dV7YBJQ"),
                ("艾文的 YouTube 频道", "https://youtube.com/channel/UC0TgypOLHt2fXboVw34SKVQ")
            ]
        }
        return [
            ("Mac Gaming: Beginner to Advanced", "https://b23.tv/pEOGX4P"),
            ("CrossOver Beginner's Guide", "https://b23.tv/SlpOQoA"),
            ("Complete CrossOver Tutorial Collection", "https://b23.tv/V5xIKy4"),
            ("CrossOver Troubleshooting Collection", "https://b23.tv/8l2dLbN"),
            ("Feedback and Log Tutorial", "https://b23.tv/1UfRohG"),
            ("Iven's Bilibili Channel", "https://b23.tv/dV7YBJQ"),
            ("Iven's YouTube Channel", "https://youtube.com/channel/UC0TgypOLHt2fXboVw34SKVQ")
        ]
    }

    var body: some View {
        NavigationStack {
            List(links, id: \.1) { title, address in
                Link(destination: URL(string: address)!) {
                    HStack(spacing: 16) {
                        Text(title).font(.system(size: 18, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.right.square").font(.title3)
                    }
                    .padding(.vertical, 10)
                }
            }
            .navigationTitle(tr("教程总导航", "Tutorial Hub"))
            .toolbar { Button(tr("完成", "Done")) { dismiss() } }
        }
        .frame(minWidth: 620, minHeight: 500)
    }
}
