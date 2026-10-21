import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MacGameToolboxClickFlow
#endif

struct AppSidebarView: View {
    @ObservedObject var navigation: NavigationModel
    @ObservedObject var clickFlowController: ClickFlowFeatureController
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: LocalizationController
    @State private var sipState = SIPState.checking
    @State private var updateMessage: String?

    var body: some View {
        List(selection: selectionBinding) {
            ForEach(SidebarSection.allCases) { section in
                Section {
                    if navigation.isExpanded(section) {
                        ForEach(section.items) { item in
                            SidebarLabel(
                                item: item,
                                badge: badge(for: item),
                                isActive: item == .cfClicker ||
                                    item == .cfMacros ||
                                    item == .cfCombinedMacros
                                    ? clickFlowController.isAutomationActive
                                    : false
                            )
                            .tag(item)
                            .accessibilityIdentifier("sidebar.\(item.rawValue)")
                        }
                    }
                } header: {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            navigation.toggle(section)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .frame(width: 12)
                                .rotationEffect(
                                    .degrees(navigation.isExpanded(section) ? 90 : 0)
                                )
                            Text(section.localizedTitle)
                                .font(.caption.weight(.semibold))
                                .textCase(nil)
                            Spacer(minLength: 2)
                        }
                        .padding(.leading, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(section.localizedTitle)
                    .accessibilityValue(
                        navigation.isExpanded(section)
                            ? tr("已展开", "Expanded")
                            : tr("已收起", "Collapsed")
                    )
                    .accessibilityHint(tr("切换侧边栏分组", "Toggle sidebar group"))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
        .task { await refreshSIPStatus() }
        .alert(
            tr("检查更新", "Check for Updates"),
            isPresented: Binding(
                get: { updateMessage != nil },
                set: { if !$0 { updateMessage = nil } }
            )
        ) {
            Button(tr("好", "OK")) { updateMessage = nil }
        } message: {
            Text(updateMessage ?? "")
        }
    }

    private var selectionBinding: Binding<SidebarItem?> {
        Binding(
            get: { navigation.selection },
            set: { item in
                if let item {
                    navigation.select(item)
                }
            }
        )
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 7) {
                Button {
                    Task { await refreshSIPStatus() }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(sipState.color)
                            .frame(width: 7, height: 7)
                        Text(sipState.label)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tr("刷新系统完整性保护状态", "Refresh System Integrity Protection status"))

                HStack(spacing: 6) {
                    Menu {
                        ForEach(AppLanguage.Preference.allCases) { preference in
                            Button {
                                localization.setPreference(preference)
                            } label: {
                                if preference == localization.preference {
                                    Label(
                                        AppLanguage.preferenceName(preference),
                                        systemImage: "checkmark"
                                    )
                                } else {
                                    Text(AppLanguage.preferenceName(preference))
                                }
                            }
                        }
                    } label: {
                        Label(AppLanguage.preferenceName(localization.preference), systemImage: "globe")
                            .lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                    .help(tr("切换显示语言", "Change display language"))

                    Spacer(minLength: 2)

                    Button {
                        checkForUpdates()
                    } label: {
                        Label(tr("检查更新", "Updates"), systemImage: "arrow.triangle.2.circlepath")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .help(tr("检查 GitHub Releases", "Check GitHub Releases"))
                }
                .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial)
        }
    }

    private func badge(for item: SidebarItem) -> String? {
        switch item {
        case .metalHUD:
            return model.metalHUDEnabled ? tr("开", "ON") : nil
        case .diskManager:
            return model.disks.isEmpty ? nil : "\(model.disks.count)"
        case .cfClicker, .cfMacros, .cfCombinedMacros:
            return clickFlowController.isAutomationActive ? tr("运行中", "ACTIVE") : nil
        case .appDropWishlist, .appDropTodayDrops, .appDropHistoricalLows, .appDropSettings:
            return nil
        default:
            return nil
        }
    }

    private func refreshSIPStatus() async {
        sipState = .checking
        sipState = await SIPStatusReader.read()
    }

    private func checkForUpdates() {
        Task {
            let result = await GitHubReleaseChecker.check()
            await MainActor.run {
                switch result {
                case .available(let release):
                    updateMessage = tr(
                        "发现新版本 \(release.version)，当前版本为 \(GitHubReleaseChecker.currentVersion)。",
                        "Version \(release.version) is available; you are running \(GitHubReleaseChecker.currentVersion)."
                    )
                case .upToDate:
                    updateMessage = tr(
                        "当前已是最新可用版本。",
                        "You are running the latest available version."
                    )
                case .rateLimited:
                    updateMessage = tr(
                        "GitHub API 暂时限流，备用更新通道也未能读取版本，请稍后重试。",
                        "GitHub's API is temporarily rate-limited and the fallback channels could not read a version. Please try again later."
                    )
                case .failed(let message):
                    updateMessage = message
                }
            }
        }
    }
}

private struct SidebarLabel: View {
    let item: SidebarItem
    let badge: String?
    let isActive: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: item.iconName)
                .frame(width: 18)
            Text(item.sidebarTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if isActive {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    .symbolEffect(.pulse, options: .repeating)
                    .accessibilityHidden(true)
            } else if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}

private enum SIPState {
    case checking
    case enabled
    case disabled
    case unknown

    var label: String {
        switch self {
        case .checking: tr("正在检查 SIP", "Checking SIP")
        case .enabled: "SIP " + tr("已启用", "Enabled")
        case .disabled: "SIP " + tr("已停用", "Disabled")
        case .unknown: "SIP " + tr("状态未知", "Unknown")
        }
    }

    var color: Color {
        switch self {
        case .checking: .secondary
        case .enabled: .green
        case .disabled: .red
        case .unknown: .orange
        }
    }
}

private enum SIPStatusReader {
    static func read() async -> SIPState {
        await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
            process.arguments = ["status"]
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let output = String(
                    decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
                    as: UTF8.self
                ).lowercased()
                if output.contains("status: enabled") { return .enabled }
                if output.contains("status: disabled") { return .disabled }
                return .unknown
            } catch {
                return .unknown
            }
        }.value
    }
}
