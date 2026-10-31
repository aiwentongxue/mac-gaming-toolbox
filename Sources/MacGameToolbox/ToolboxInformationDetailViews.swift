import AppKit
import SwiftUI

struct ToolboxSettingsDetailView: View {
    @EnvironmentObject private var localization: LocalizationController
    @AppStorage(UpdateCheckPreference.key) private var automaticallyCheckForUpdates = true
    @State private var isCheckingUpdate = false
    @State private var updateResult: GitHubUpdateCheckResult?

    var body: some View {
        ToolboxPage(
            icon: SidebarItem.settings.iconName,
            title: tr("设置", "Settings"),
            subtitle: tr("管理显示语言与应用更新。", "Manage your display language and app updates.")
        ) {
            ToolboxCard(
                tr("语言", "Language"),
                subtitle: tr("默认跟随 macOS 系统语言；选择语言后会立即应用，并在下次启动时保留。", "By default, the app follows the macOS language. Your selected language applies immediately and is remembered for future launches.")
            ) {
                Picker(tr("显示语言", "Display language"), selection: Binding(
                    get: { localization.preference },
                    set: { localization.setPreference($0) }
                )) {
                    ForEach(AppLanguage.Preference.allCases) { preference in
                        Text(AppLanguage.preferenceName(preference)).tag(preference)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 360, alignment: .leading)
                .accessibilityIdentifier("settings.language")
            }

            ToolboxCard(
                tr("更新", "Updates"),
                subtitle: tr("默认开启。每次打开 Mac游戏工具箱时静默检查 GitHub Releases；仅发现新版本时才会提示。", "Enabled by default. Mac Game Toolbox silently checks GitHub Releases every time it opens and only notifies you when a newer version is available.")
            ) {
                Toggle(tr("启动时检查更新", "Check for updates at launch"), isOn: $automaticallyCheckForUpdates)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("settings.automaticUpdates")
                Divider()
                HStack(spacing: 12) {
                    Text(tr("当前版本", "Current Version") + " " + GitHubReleaseChecker.currentVersion)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isCheckingUpdate {
                        ProgressView().controlSize(.small)
                    }
                    Button(isCheckingUpdate ? tr("正在检查…", "Checking…") : tr("立即检查更新", "Check Now")) {
                        checkForUpdates()
                    }
                    .disabled(isCheckingUpdate)
                    .accessibilityIdentifier("settings.checkUpdates")
                }
                if let result = updateResult {
                    Text(updateMessage(for: result))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if case .available = result {
                        Button(tr("前往更新", "Download Update")) {
                            NSWorkspace.shared.open(GitHubReleaseChecker.releasesPageURL)
                        }
                        .toolboxProminentButton()
                    }
                }
            }
        }
    }

    private func checkForUpdates() {
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        updateResult = nil
        Task {
            updateResult = await GitHubReleaseChecker.check()
            isCheckingUpdate = false
        }
    }

    private func updateMessage(for result: GitHubUpdateCheckResult) -> String {
        switch result {
        case .available(let release):
            tr("发现新版本 \(release.version)。", "Version \(release.version) is available.")
        case .upToDate:
            tr("当前已是最新可用版本。", "You are running the latest available version.")
        case .rateLimited:
            tr("GitHub API 暂时限流，备用更新通道也未能读取版本，请稍后重试。", "GitHub's API is temporarily rate-limited and the fallback channels could not read a version. Please try again later.")
        case .failed(let message):
            message
        }
    }
}

struct TutorialsDetailView: View {
    @State private var searchText = ""
    @State private var filter = TutorialCategory.all

    var body: some View {
        ToolboxPage(
            icon: SidebarItem.tutorials.iconName,
            title: tr("游戏教程", "Tutorials"),
            subtitle: tr(
                "按主题查找 Mac 游戏、CrossOver、游戏启动与故障排查教程。链接会在默认浏览器中打开。",
                "Find Mac gaming, CrossOver, game launch, and troubleshooting tutorials. Links open in your default browser."
            )
        ) {
            HStack(spacing: 10) {
                TextField(tr("搜索教程", "Search Tutorials"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker(tr("分类", "Category"), selection: $filter) {
                    ForEach(TutorialCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .frame(width: 190)
            }

            if filteredTutorials.isEmpty {
                ToolboxCard(tr("没有匹配的教程", "No Matching Tutorials")) {
                    ContentUnavailableText(
                        icon: "magnifyingglass",
                        title: tr("调整搜索或分类", "Adjust Search or Category"),
                        message: tr("尝试清空搜索词或选择“全部”。", "Clear the search field or select All.")
                    )
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 285), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(filteredTutorials) { tutorial in
                        Link(destination: tutorial.url) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: tutorial.category.icon)
                                    .font(.title3)
                                    .foregroundStyle(.purple)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(tutorial.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Text(tutorial.category.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
                            .toolboxCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var filteredTutorials: [TutorialItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return TutorialItem.all.filter { item in
            let matchesCategory = filter == .all || item.category == filter
            let matchesSearch = query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
            return matchesCategory && matchesSearch
        }
    }
}

private enum TutorialCategory: String, CaseIterable, Identifiable {
    case all
    case gettingStarted
    case crossOver
    case games
    case support

    var id: Self { self }

    var title: String {
        switch self {
        case .all: tr("全部", "All")
        case .gettingStarted: tr("入门", "Getting Started")
        case .crossOver: "CrossOver"
        case .games: tr("游戏专项", "Game Guides")
        case .support: tr("反馈与支持", "Feedback & Support")
        }
    }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .gettingStarted: "book"
        case .crossOver: "wineglass"
        case .games: "gamecontroller"
        case .support: "lifepreserver"
        }
    }
}

private struct TutorialItem: Identifiable {
    let title: String
    let address: String
    let category: TutorialCategory
    var id: String { address }
    var url: URL { URL(string: address)! }

    static var all: [TutorialItem] {
        let chinese = AppLanguage.isChinese
        return [
            TutorialItem(
                title: chinese ? "Mac 玩游戏从入门到精通" : "Mac Gaming: Beginner to Advanced",
                address: "https://b23.tv/pEOGX4P",
                category: .gettingStarted
            ),
            TutorialItem(
                title: chinese ? "CrossOver 零基础入门指南" : "CrossOver Beginner's Guide",
                address: "https://b23.tv/RiWoTPB",
                category: .crossOver
            ),
            TutorialItem(
                title: chinese ? "CrossOver 全部教程合集" : "Complete CrossOver Tutorial Collection",
                address: "https://b23.tv/V5xIKy4",
                category: .crossOver
            ),
            TutorialItem(
                title: chinese ? "CrossOver 疑难解答合集" : "CrossOver Troubleshooting Collection",
                address: "https://b23.tv/8l2dLbN",
                category: .support
            ),
            TutorialItem(
                title: chinese ? "Mac 玩 PC 原神详细教程" : "Mac PC Genshin Impact Detailed Guide",
                address: "https://b23.tv/aVH2i2K",
                category: .games
            ),
            TutorialItem(
                title: chinese ? "Mac 玩 PC 崩坏：星穹铁道详细教程" : "Mac PC Honkai: Star Rail Detailed Guide",
                address: "https://b23.tv/OZ5wkvd",
                category: .games
            ),
            TutorialItem(
                title: chinese ? "Mac 玩 PC 绝区零详细教程" : "Mac PC Zenless Zone Zero Detailed Guide",
                address: "https://b23.tv/B8Fb50K",
                category: .games
            ),
            TutorialItem(
                title: chinese ? "Mac 玩 PC 鸣潮详细教程" : "Mac PC Wuthering Waves Detailed Guide",
                address: "https://b23.tv/HTFJ478",
                category: .games
            ),
            TutorialItem(
                title: chinese ? "问题反馈与日志教程" : "Feedback and Log Tutorial",
                address: "https://b23.tv/1UfRohG",
                category: .support
            ),
            TutorialItem(
                title: chinese ? "艾文的哔哩哔哩主页" : "Iven's Bilibili Channel",
                address: "https://b23.tv/dV7YBJQ",
                category: .support
            ),
            TutorialItem(
                title: chinese ? "艾文的 YouTube 频道" : "Iven's YouTube Channel",
                address: "https://youtube.com/channel/UC0TgypOLHt2fXboVw34SKVQ",
                category: .support
            )
        ]
    }
}

struct ChangelogAboutDetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ToolboxPageHeader(
                icon: SidebarItem.changelogAbout.iconName,
                title: tr("更新日志与关于", "Changelog & About"),
                subtitle: tr(
                    "查看当前本机构建信息、历史版本变化与诊断工具。",
                    "Review this local build, version history, and diagnostic tools."
                )
            )

            HStack(alignment: .top, spacing: 16) {
                ToolboxCard("Mac 游戏工具箱") {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                        GridRow {
                            Text(tr("版本", "Version")).foregroundStyle(.secondary)
                            Text(GitHubReleaseChecker.currentVersion)
                        }
                        GridRow {
                            Text(tr("界面语言", "Language")).foregroundStyle(.secondary)
                            Text(AppLanguage.preferenceName(localization.preference))
                        }
                        GridRow {
                            Text(tr("构建状态", "Build")).foregroundStyle(.secondary)
                            Text("Release \(GitHubReleaseChecker.currentVersion)")
                        }
                    }
                    Button(tr("打开 Releases", "Open Releases")) {
                        NSWorkspace.shared.open(GitHubReleaseChecker.releasesPageURL)
                    }
                }
                .frame(maxWidth: .infinity)

                ToolboxCard(tr("支持工具", "Support Tools")) {
                    Text(tr("诊断日志、核心功能修复和教程可继续从“帮助”菜单访问。", "Diagnostics, core feature repair, and tutorials remain available from the Help menu."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(tr("导出诊断", "Export Diagnostics")) {
                            model.requestDiagnosticsExport()
                        }
                        Button(tr("修复核心功能", "Repair Core Features")) {
                            model.repairCoreFeatures()
                        }
                    }
                    Text("Copyright © 2026 我是艾文喵")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }

            Divider()

            ChangelogView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

}
