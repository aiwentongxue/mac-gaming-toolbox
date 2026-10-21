import AppKit
import SwiftUI

struct AppearanceSettingsDetailView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("app.wallpaper.overlayOpacity") private var overlayOpacity = 0.18
    @AppStorage("app.wallpaper.blurRadius") private var blurRadius = 0.0

    var body: some View {
        ToolboxPage(
            icon: SidebarItem.appearanceWallpaper.iconName,
            title: tr("外观与壁纸", "Appearance & Wallpaper"),
            subtitle: tr(
                "导入自定义壁纸，并调整遮罩和模糊程度。右侧内容和侧边栏使用半透明材质，让背景柔和透出。",
                "Import a custom wallpaper and adjust its overlay and blur. The sidebar and detail surfaces use translucent materials so the background remains visible."
            )
        ) {
            HStack(alignment: .top, spacing: 18) {
                wallpaperCard
                    .frame(minWidth: 300, maxWidth: .infinity)
                adjustmentCard
                    .frame(minWidth: 300, maxWidth: .infinity)
            }
            ToolboxCard(
                tr("显示行为", "Display Behavior"),
                subtitle: tr(
                    "导入壁纸后界面会使用深色半透明表面，确保文字与图表保持可读。旧版 macOS 会自动使用稳定的材质回退。",
                    "With a custom wallpaper, the interface uses dark translucent surfaces for readable text and charts. Older macOS versions automatically use a stable material fallback."
                )
            ) {
                Label(
                    currentModeDescription,
                    systemImage: model.wallpaperImage == nil ? "circle.lefthalf.filled" : "photo.fill"
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    private var wallpaperCard: some View {
        ToolboxCard(
            tr("背景图", "Background Image"),
            subtitle: model.configuration.customWallpaperPath == nil
                ? tr("当前使用系统渐变背景。", "Using the built-in gradient background.")
                : tr("图片按比例填充窗口，不会拉伸。", "The image fills the window proportionally without stretching.")
        ) {
            GeometryReader { proxy in
                backgroundPreview
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(.white.opacity(0.15))
                    }
            }
            .frame(height: 190)

            HStack {
                Button(model.wallpaperImage == nil ? tr("导入壁纸", "Import Wallpaper") : tr("更换壁纸", "Replace Wallpaper")) {
                    model.importWallpaper()
                }
                .toolboxProminentButton()
                if model.wallpaperImage != nil {
                    Button(tr("恢复默认", "Restore Default")) {
                        model.resetWallpaper()
                    }
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var backgroundPreview: some View {
        if let image = model.wallpaperImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .scaleEffect(1.03)
                .blur(radius: blurRadius * 0.65)
                .overlay(Color.black.opacity(overlayOpacity))
        } else {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.12, blue: 0.36), Color(red: 0.52, green: 0.22, blue: 0.68)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    private var adjustmentCard: some View {
        ToolboxCard(tr("玻璃与遮罩", "Glass & Overlay")) {
            VStack(alignment: .leading, spacing: 18) {
                sliderRow(
                    title: tr("遮罩浓度", "Overlay Density"),
                    value: $overlayOpacity,
                    range: 0...0.7,
                    display: "\(Int(overlayOpacity * 100))%"
                )
                sliderRow(
                    title: tr("背景模糊", "Background Blur"),
                    value: $blurRadius,
                    range: 0...24,
                    display: "\(Int(blurRadius.rounded())) pt"
                )
                Button(tr("恢复外观默认值", "Reset Appearance")) {
                    overlayOpacity = 0.18
                    blurRadius = 0
                }
            }
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(display)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private var currentModeDescription: String {
        if model.wallpaperImage != nil {
            return tr("自定义壁纸 + 深色半透明界面", "Custom wallpaper with dark translucent surfaces")
        }
        return tr("内置渐变背景 + 跟随系统浅色/深色外观", "Built-in gradient with system light or dark appearance")
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
    @State private var updateStatus = ""
    @State private var isCheckingUpdate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ToolboxPageHeader(
                icon: SidebarItem.changelogAbout.iconName,
                title: tr("更新日志与关于", "Changelog & About"),
                subtitle: tr(
                    "查看当前本机构建信息、历史版本变化、诊断与更新入口。",
                    "Review this local build, version history, diagnostics, and update options."
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
                            Text(tr("本机界面重写候选版", "Local UI Rewrite Candidate"))
                        }
                    }
                    HStack {
                        Button(tr("检查更新", "Check for Updates")) {
                            checkForUpdates()
                        }
                        .disabled(isCheckingUpdate)
                        Button(tr("打开 Releases", "Open Releases")) {
                            NSWorkspace.shared.open(GitHubReleaseChecker.releasesPageURL)
                        }
                    }
                    if !updateStatus.isEmpty {
                        Text(updateStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    private func checkForUpdates() {
        isCheckingUpdate = true
        updateStatus = tr("正在检查…", "Checking…")
        Task {
            let result = await GitHubReleaseChecker.check()
            await MainActor.run {
                isCheckingUpdate = false
                switch result {
                case .available(let release):
                    updateStatus = tr(
                        "发现新版本 \(release.version)。",
                        "Version \(release.version) is available."
                    )
                case .upToDate:
                    updateStatus = tr(
                        "当前已是最新可用版本。",
                        "You are running the latest available version."
                    )
                case .rateLimited:
                    updateStatus = tr(
                        "GitHub API 暂时限流，请稍后重试。",
                        "GitHub's API is temporarily rate-limited. Please try again later."
                    )
                case .failed(let message):
                    updateStatus = message
                }
            }
        }
    }
}
