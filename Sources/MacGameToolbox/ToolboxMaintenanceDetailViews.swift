import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif

struct DiskManagerDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedVolume: String?

    var body: some View {
        ToolboxPage(
            icon: SidebarItem.diskManager.iconName,
            title: tr("磁盘挂载管理", "Volume Mounting"),
            subtitle: tr(
                "管理外接卷的自定义挂载路径、默认路径和自动恢复记录。启动磁盘会自动排除。",
                "Manage custom mount paths, default destinations, and automatic restoration for external volumes. The startup disk is excluded."
            )
        ) {
            actionBar
            HStack(alignment: .top, spacing: 16) {
                volumeList
                    .frame(minWidth: 290, idealWidth: 350, maxWidth: 430)
                volumeDetail
                    .frame(minWidth: 330, maxWidth: .infinity)
            }
            configurationCard
            automaticRestoreCard
        }
        .task {
            if model.disks.isEmpty { model.refreshDisks() }
        }
        .onAppear {
            if selectedVolume == nil {
                selectedVolume = model.disks.first?.id
            }
        }
        .onChange(of: model.disks) { _, disks in
            if let selectedVolume, !disks.contains(where: { $0.id == selectedVolume }) {
                self.selectedVolume = nil
            }
            if selectedVolume == nil {
                selectedVolume = disks.first?.id
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                model.refreshDisks()
            } label: {
                Label(tr("刷新磁盘", "Refresh Volumes"), systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            Button {
                model.restorePreviousMounts()
            } label: {
                Label(tr("恢复上次挂载", "Restore Last Mounts"), systemImage: "arrow.uturn.backward")
            }
            Spacer()
            Text(tr("已选择 \(model.selectedDiskIDs.count)", "\(model.selectedDiskIDs.count) selected"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var automaticRestoreCard: some View {
        ToolboxCard(
            tr("启动时自动恢复", "Automatic Restoration"),
            subtitle: tr(
                "开启后每秒检测可用磁盘，应用启动 10 秒后尝试恢复上次自定义挂载。推出或卸载磁盘不会清除记录，恢复默认挂载会停止下次恢复。",
                "When enabled, available volumes are checked every second and previous custom mounts are restored 10 seconds after launch. Ejecting does not clear records; restoring defaults does."
            )
        ) {
            Toggle(
                tr("开启应用时自动恢复上次挂载", "Restore Previous Mounts at Launch"),
                isOn: Binding(
                    get: { model.configuration.automaticallyRestoreMountsOnLaunch },
                    set: { model.setAutomaticallyRestoreMountsOnLaunch($0) }
                )
            )
            .toggleStyle(.switch)
        }
    }

    private var volumeList: some View {
        ToolboxCard(tr("可用磁盘", "Available Volumes")) {
            if model.disks.isEmpty {
                ContentUnavailableText(
                    icon: "externaldrive.badge.questionmark",
                    title: tr("未发现可用卷", "No Available Volumes"),
                    message: tr("连接外接磁盘后刷新。", "Connect an external volume and refresh.")
                )
            } else {
                List(selection: Binding(
                    get: { model.selectedDiskIDs },
                    set: { model.selectedDiskIDs = $0 }
                )) {
                    ForEach(model.disks) { disk in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 7) {
                                Image(systemName: diskIcon(disk))
                                    .foregroundStyle(.purple)
                                Text(disk.name)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if disk.isInternal {
                                    Text(tr("内置", "Internal"))
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Text("\(disk.fileSystem.uppercased()) · \(formattedSize(disk.size))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(disk.id)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 4)
                        .tag(disk.id)
                        .onTapGesture { selectedVolume = disk.id }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 300, maxHeight: 420)
            }
        }
    }

    @ViewBuilder
    private var volumeDetail: some View {
        if let disk = activeVolume {
            ToolboxCard(
                disk.name,
                subtitle: "\(disk.fileSystem.uppercased()) · \(formattedSize(disk.size))"
            ) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                    detailRow(tr("磁盘标识", "Volume ID"), disk.id)
                    detailRow(
                        tr("挂载状态", "Mount Status"),
                        disk.mountPoint == nil ? tr("未挂载", "Unmounted") : tr("已挂载", "Mounted")
                    )
                    detailRow(tr("挂载点", "Mount Point"), disk.mountPoint ?? "—")
                    if let uuid = disk.volumeUUID {
                        detailRow("UUID", uuid)
                    }
                }
                .font(.caption)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("自定义挂载路径", "Custom Mount Path"))
                        .font(.subheadline.weight(.semibold))
                    HStack {
                        TextField(
                            tr("选择一个目录", "Choose a directory"),
                            text: Binding(
                                get: { model.diskPaths[disk.id, default: ""] },
                                set: { model.diskPaths[disk.id] = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        Button(tr("浏览", "Browse")) { model.choosePath(for: disk.id) }
                        if !model.configuration.defaultPaths.isEmpty {
                            Menu(tr("默认路径", "Defaults")) {
                                ForEach(model.configuration.defaultPaths, id: \.self) { path in
                                    Button(path) { model.diskPaths[disk.id] = path }
                                }
                            }
                            .frame(width: 105)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Toggle(
                        tr("选择此磁盘", "Select This Volume"),
                        isOn: Binding(
                            get: { model.selectedDiskIDs.contains(disk.id) },
                            set: { selected in
                                if selected {
                                    model.selectedDiskIDs.insert(disk.id)
                                } else {
                                    model.selectedDiskIDs.remove(disk.id)
                                }
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    Spacer()
                    if disk.mountPoint != nil {
                        Button(tr("在 Finder 中打开", "Show in Finder")) {
                            guard let mountPoint = disk.mountPoint else { return }
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mountPoint)
                        }
                    }
                }

                HStack {
                    Button(tr("保存为预设", "Save as Preset")) {
                        model.saveDiskPreset(disk.id)
                    }
                    .disabled(model.diskPaths[disk.id, default: ""].isEmpty)
                    Spacer()
                    Button(tr("恢复默认挂载", "Restore Default")) {
                        model.restoreSelectedDisks()
                    }
                    .disabled(model.selectedDiskIDs.isEmpty)
                    Button(tr("挂载到指定路径", "Mount")) {
                        model.mountSelectedDisks()
                    }
                    .toolboxProminentButton()
                    .disabled(model.selectedDiskIDs.isEmpty)
                }
            }
        } else {
            ToolboxCard(tr("磁盘详情", "Volume Details")) {
                ContentUnavailableText(
                    icon: "externaldrive",
                    title: tr("选择一个磁盘", "Select a Volume"),
                    message: tr("选择后可编辑挂载路径并执行批量操作。", "Select a volume to edit its mount path and use batch actions.")
                )
            }
        }
    }

    private var activeVolume: DiskVolume? {
        if let selectedVolume,
           let disk = model.disks.first(where: { $0.id == selectedVolume }) {
            return disk
        }
        return model.disks.first { model.selectedDiskIDs.contains($0.id) }
    }

    private var configurationCard: some View {
        ToolboxCard(
            tr("默认路径与磁盘预设", "Default Paths & Volume Presets"),
            subtitle: tr(
                "默认路径用于快速填入目标目录；磁盘预设可保存当前卷标识和挂载路径。",
                "Default paths provide quick destinations. Volume presets save a volume identifier and mount path."
            )
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tr("默认路径", "Default Paths"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(tr("添加路径", "Add Path")) { model.addDefaultPath() }
                }
                if model.configuration.defaultPaths.isEmpty {
                    Text(tr("尚未添加默认路径。", "No default paths added."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.configuration.defaultPaths, id: \.self) { path in
                        HStack {
                            Text(path)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(tr("删除", "Delete"), role: .destructive) {
                                model.deleteDefaultPath(path)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Divider()

                HStack {
                    Text(tr("磁盘预设", "Volume Presets"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                if model.configuration.diskPresets.isEmpty {
                    Text(tr("尚未保存磁盘预设。", "No volume presets saved."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.configuration.diskPresets, id: \.diskIdentifier) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.diskIdentifier)
                                    .font(.caption.monospaced())
                                Text(preset.mountPath ?? tr("未绑定路径", "No path"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(tr("删除", "Delete"), role: .destructive) {
                                model.deleteDiskPreset(preset.diskIdentifier)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func diskIcon(_ disk: DiskVolume) -> String {
        if disk.isInternal { return "internaldrive" }
        return disk.fileSystem.uppercased() == "NTFS"
            ? "externaldrive.badge.exclamationmark"
            : "externaldrive"
    }

    private func formattedSize(_ size: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

struct SystemCleanerDetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ToolboxPage(
            icon: SidebarItem.systemCleaner.iconName,
            title: tr("缓存与日志清理", "Cache & Log Cleanup"),
            subtitle: tr(
                "扫描用户缓存和日志；关闭敏感文件排除后会同时包含更多系统目录，需要额外授权。",
                "Scan user caches and logs. Disabling sensitive-file exclusion includes more system locations and may require additional authorization."
            )
        ) {
            ToolboxCard(
                tr("安全设置", "Safety Settings"),
                subtitle: tr(
                    "推荐保持“排除敏感文件”开启。关闭后会纳入 Application Support、Containers 和系统日志目录，并在删除前进行双重确认。",
                    "Keep sensitive-file exclusion enabled when possible. Disabling it includes Application Support, Containers, and system log locations with two confirmations."
                )
            ) {
                Toggle(
                    tr("排除敏感文件", "Exclude Sensitive Files"),
                    isOn: Binding(
                        get: { model.configuration.excludesSensitiveCacheFiles },
                        set: { model.setExcludesSensitiveCacheFiles($0) }
                    )
                )
                .toggleStyle(.switch)
                .disabled(model.isCacheBusy)
                HStack {
                    Text(model.configuration.excludesSensitiveCacheFiles
                        ? tr("将只扫描 ~/Library/Caches 与 ~/Library/Logs", "Only ~/Library/Caches and ~/Library/Logs will be scanned")
                        : tr("将扫描更多缓存、容器和系统日志目录", "More caches, containers, and system logs will be scanned"))
                        .font(.caption)
                        .foregroundStyle(model.configuration.excludesSensitiveCacheFiles ? Color.secondary : Color.orange)
                    Spacer()
                    Button(tr("开始扫描", "Start Scan")) {
                        model.prepareCacheScan()
                    }
                    .toolboxProminentButton()
                    .disabled(model.isCacheBusy)
                }
                if model.isCacheBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(tr("正在处理缓存，请稍候…", "Processing caches, please wait…"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if let result = model.cacheCleanupResult {
                cleanupSummary(result)
            }
            if let scan = model.cacheScan {
                scanSummary(scan)
            } else if model.cacheCleanupResult == nil {
                ToolboxCard(tr("扫描结果", "Scan Results")) {
                    ContentUnavailableText(
                        icon: "internaldrive",
                        title: tr("尚未扫描", "Not Scanned Yet"),
                        message: tr("扫描只统计大小，不会自动删除内容。", "A scan only measures size and never deletes content automatically.")
                    )
                }
            }

            ToolboxCard(
                tr("清理边界", "Cleanup Boundary"),
                subtitle: tr(
                    "工具箱只清理扫描列表中缓存和日志目录的内容，不会直接删除用户文档、桌面文件或游戏存档目录。",
                    "The toolbox clears cache and log directory contents from the scan results. It does not directly target Documents, Desktop files, or game save folders."
                )
            ) {
                Label(
                    tr(
                        "缓存删除不可撤销。应用可能需要重新构建缓存、重新登录，或短暂变慢。",
                        "Cache deletion cannot be undone. Apps may need to rebuild caches, sign in again, or slow down briefly."
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
        }
    }

    private func cleanupSummary(_ result: CacheCleanupResult) -> some View {
        ToolboxCard(tr("清理结果", "Cleanup Results")) {
            HStack(spacing: 22) {
                ScanMetric(title: tr("已清理", "Removed"), value: "\(result.removedCount)", icon: "checkmark.circle")
                ScanMetric(title: tr("已跳过", "Skipped"), value: "\(result.skippedItems.count)", icon: "minus.circle")
                ScanMetric(title: tr("失败", "Failed"), value: "\(result.failedItems.count)", icon: "exclamationmark.triangle")
            }
            issueList(result.failedItems + result.skippedItems)
            Text(tr("扫描结果已失效。再次清理前请重新扫描。", "The previous scan is no longer valid. Scan again before another cleanup."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func issueList(_ issues: [CacheScanIssue]) -> some View {
        if !issues.isEmpty {
            DisclosureGroup(tr("查看跳过或失败的项目", "View Skipped or Failed Items") + " (\(issues.count))") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                            Text("\(issue.path.path)：\(issue.reason)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private func scanSummary(_ scan: CacheScan) -> some View {
        ToolboxCard(
            tr("扫描结果", "Scan Results"),
            subtitle: tr("预计可清理", "Estimated Cleanable Size") + " " + ByteCountFormatter.string(
                fromByteCount: Int64(clamping: scan.estimatedBytes),
                countStyle: .file
            )
        ) {
            HStack(spacing: 22) {
                ScanMetric(
                    title: tr("用户目录", "User Targets"),
                    value: "\(scan.userTargets.count)",
                    icon: "person.crop.circle"
                )
                ScanMetric(
                    title: tr("系统目录", "System Targets"),
                    value: "\(scan.systemTargets.count)",
                    icon: "gearshape.2"
                )
                ScanMetric(
                    title: tr("已跳过", "Skipped"),
                    value: "\(scan.inaccessibleTargets.count)",
                    icon: "lock.slash"
                )
            }

            if !scan.inaccessibleTargets.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Label(
                        tr("部分项目已跳过，其余项目可继续清理", "Some Items Were Skipped; Other Items Can Be Cleaned"),
                        systemImage: "lock.shield"
                    )
                    .font(.subheadline.weight(.medium))
                    issueList(scan.inaccessibleTargets)
                    Text(tr("无法访问可能由文件权限或系统保护造成，不代表未授予完全磁盘访问权限。若用户目录仍无法读取，可检查授权并退出、重新打开应用后扫描。", "File permissions or system protection can prevent access even with Full Disk Access. If user folders remain unreadable, check the permission, quit and reopen the app, then scan again."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(tr("打开完全磁盘访问设置", "Open Full Disk Access Settings")) {
                        model.openFullDiskAccessSettings()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(tr("扫描目录", "Scanned Locations"))
                    .font(.subheadline.weight(.semibold))
                ForEach(Array((scan.userTargets + scan.systemTargets).prefix(12).enumerated()), id: \.offset) { _, url in
                    Text(url.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            HStack {
                Button(tr("重新扫描", "Scan Again")) {
                    model.prepareCacheScan()
                }
                .disabled(model.isCacheBusy)
                Spacer()
                Button(tr("清理扫描结果", "Clean Scan Results"), role: .destructive) {
                    model.requestCacheCleaning()
                }
                .disabled(model.isCacheBusy || !scan.hasCleanableEntries)
            }
        }
    }
}

private struct ScanMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.title3.bold())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
