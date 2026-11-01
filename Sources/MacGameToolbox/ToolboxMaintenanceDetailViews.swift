import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif

struct DiskManagerDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var batchMode: Bool
    init(initialBatchMode: Bool = false) { _batchMode = State(initialValue: initialBatchMode) }
    @State private var pendingAction: PendingDiskAction?
    @State private var pendingAssociation: DiskAssociation?

    private struct PendingDiskAction: Identifiable {
        let id = UUID()
        let requests: [DiskMountRequest]
        let restore: Bool
    }
    private struct DiskAssociation: Identifiable {
        let id = UUID()
        let preset: DiskPreset
        let volume: DiskVolume
        let automatic: Bool
    }
    private var busy: Bool { model.isDiskBusy || model.isRefreshingDisks }
    private var activeVolume: DiskVolume? { model.disks.first { $0.id == model.activeDiskID } }
    private var batchVolumes: [DiskVolume] { model.disks.filter { model.selectedDiskIDs.contains($0.id) } }

    var body: some View {
        GeometryReader { viewport in
        ToolboxPage(icon: SidebarItem.diskManager.iconName,
                    title: tr("磁盘挂载管理", "Volume Mounting"),
                    subtitle: tr("选择磁盘查看详情。右侧操作仅作用于当前磁盘；多个磁盘请使用批量操作。", "Select a volume to inspect it. Detail actions affect only that volume; use Batch Operations for multiple volumes.")) {
            actionBar
            if busy { ProgressView(tr("正在读取或处理磁盘…", "Reading or updating volumes…")).controlSize(.small) }
            if viewport.size.width >= 720 {
                HStack(alignment: .top, spacing: 16) {
                    volumeList.frame(minWidth: 240, idealWidth: 300, maxWidth: 350)
                    volumeDetail.frame(minWidth: 300, maxWidth: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) { volumeList; volumeDetail }
            }
            if batchMode { batchCard }
            if let result = model.diskOperationResult { resultCard(result) }
            configurationCard
            automaticRestoreCard
        }
        .frame(width: viewport.size.width, height: viewport.size.height)
        .task { if model.disks.isEmpty { model.refreshDisks() } }
        .onDisappear { batchMode = false; model.selectedDiskIDs.removeAll() }
        .sheet(item: $pendingAction) { action in confirmation(action) }
        .confirmationDialog(tr("确认关联旧记录", "Associate Legacy Record"), isPresented: Binding(
            get: { pendingAssociation != nil }, set: { if !$0 { pendingAssociation = nil } }
        ), titleVisibility: .visible) {
            if let association = pendingAssociation {
                Button(tr("关联当前磁盘", "Associate Current Volume")) {
                    model.associateDiskRecord(association.preset, with: association.volume, automatic: association.automatic)
                    pendingAssociation = nil
                }
            }
            Button(tr("取消", "Cancel"), role: .cancel) { pendingAssociation = nil }
        } message: {
            if let association = pendingAssociation {
                Text("\(association.preset.diskIdentifier) → \(association.volume.name) (\(association.volume.id))\n\(association.preset.mountPath ?? "—")\n\(tr("请确认该记录属于此磁盘。", "Confirm that this record belongs to this volume."))")
            }
        }
        .accessibilityIdentifier("disk.page")
        }
    }

    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { refreshButton; previousButton; Spacer(); batchButton }
            VStack(alignment: .leading, spacing: 10) { refreshButton; previousButton; batchButton }
        }
    }
    private var refreshButton: some View {
        Button { model.refreshDisks() } label: { Label(tr("刷新磁盘", "Refresh Volumes"), systemImage: "arrow.clockwise") }
            .keyboardShortcut("r", modifiers: .command).disabled(busy)
    }
    private var previousButton: some View {
        Button { model.restorePreviousMounts() } label: { Label(tr("恢复上次挂载", "Restore Last Mounts"), systemImage: "arrow.uturn.backward") }
            .disabled(busy || model.configuration.restorableDiskMounts.isEmpty)
    }
    private var batchButton: some View {
        Button {
            batchMode.toggle()
            if !batchMode { model.selectedDiskIDs.removeAll() }
        } label: { Label(batchMode ? tr("结束批量操作", "Done with Batch") : tr("批量操作", "Batch Operations"), systemImage: "checklist") }.disabled(model.isDiskBusy)
    }

    private var volumeList: some View {
        ToolboxCard(tr("可用磁盘", "Available Volumes")) {
            if model.disks.isEmpty && model.isRefreshingDisks {
                ProgressView().frame(maxWidth: .infinity, minHeight: 130)
            } else if model.disks.isEmpty {
                ContentUnavailableText(icon: "externaldrive.badge.questionmark", title: tr("未发现可用卷", "No Available Volumes"), message: tr("连接外接磁盘后刷新。", "Connect an external volume and refresh."))
            } else {
                List(selection: $model.activeDiskID) {
                    ForEach(model.disks) { disk in
                        HStack(alignment: .top, spacing: 8) {
                            if batchMode {
                                Toggle(tr("加入批量操作", "Include in Batch"), isOn: Binding(
                                    get: { model.selectedDiskIDs.contains(disk.id) },
                                    set: { if $0 { model.selectedDiskIDs.insert(disk.id) } else { model.selectedDiskIDs.remove(disk.id) } }
                                ))
                                .labelsHidden().toggleStyle(.checkbox)
                                .accessibilityLabel("\(tr("加入批量操作", "Include in Batch")): \(disk.name)")
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Image(systemName: disk.isRemovable ? "externaldrive" : disk.isInternal ? "internaldrive" : "externaldrive").foregroundStyle(.purple)
                                    Text(disk.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                }
                                Text("\(disk.fileSystem.uppercased()) · \(formattedSize(disk.size))").font(.caption).foregroundStyle(.secondary)
                                Text("\(disk.id) · \(disk.isRemovable ? tr("可移除介质", "Removable") : disk.isInternal ? tr("内置", "Internal") : tr("外置", "External"))")
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .tag(disk.id)
                    }
                }
                .listStyle(.inset)
                .frame(height: 310)
                .accessibilityIdentifier("disk.volumes")
            }
        }
        .disabled(model.isDiskBusy)
    }

    @ViewBuilder private var volumeDetail: some View {
        if let disk = activeVolume {
            ToolboxCard(disk.name, subtitle: "\(disk.fileSystem.uppercased()) · \(formattedSize(disk.size))") {
                VStack(alignment: .leading, spacing: 8) {
                    detailRow(tr("磁盘标识", "Volume ID"), disk.id)
                    detailRow(tr("挂载状态", "Mount Status"), disk.mountPoint == nil ? tr("未挂载", "Unmounted") : tr("已挂载", "Mounted"))
                    detailRow(tr("挂载点", "Mount Point"), disk.mountPoint ?? "—")
                    if let uuid = disk.volumeUUID { detailRow("UUID", uuid) }
                }
                Divider()
                pathEditor(disk)
                if let mount = disk.mountPoint {
                    Button(tr("在 Finder 中打开", "Show in Finder")) { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mount) }
                }
                ViewThatFits(in: .horizontal) {
                    HStack { presetButton(disk); restoreButton(disk); mountButton(disk) }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 10) { presetButton(disk); restoreButton(disk); mountButton(disk) }
                }
            }
            .disabled(model.isDiskBusy)
            .accessibilityIdentifier("disk.detail")
        } else {
            ToolboxCard(tr("磁盘详情", "Volume Details")) {
                ContentUnavailableText(icon: "externaldrive", title: tr("选择一个磁盘", "Select a Volume"), message: tr("选择后可编辑挂载路径。", "Select a volume to edit its mount path."))
            }
        }
    }

    private func pathEditor(_ disk: DiskVolume) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("自定义挂载路径", "Custom Mount Path")).font(.subheadline.weight(.semibold))
            TextField(tr("选择一个目录", "Choose a directory"), text: Binding(get: { model.diskPaths[disk.id, default: ""] }, set: { model.diskPaths[disk.id] = $0 }))
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("disk.path.\(disk.id)")
            HStack {
                Button(tr("浏览", "Browse")) { model.choosePath(for: disk.id) }
                if !model.configuration.defaultPaths.isEmpty {
                    Menu(tr("默认路径", "Defaults")) {
                        ForEach(model.configuration.defaultPaths, id: \.self) { path in Button(path) { model.diskPaths[disk.id] = path } }
                    }
                }
            }
        }
    }
    private func presetButton(_ disk: DiskVolume) -> some View {
        Button(tr("保存为预设", "Save as Preset")) { model.saveDiskPreset(disk.id) }
            .disabled(disk.volumeUUID == nil || !validPath(disk))
    }
    private func restoreButton(_ disk: DiskVolume) -> some View {
        Button(tr("恢复默认挂载", "Restore Default")) { pendingAction = PendingDiskAction(requests: [request(disk)], restore: true) }.disabled(busy)
    }
    private func mountButton(_ disk: DiskVolume) -> some View {
        Button(tr("挂载到指定路径", "Mount")) { pendingAction = PendingDiskAction(requests: [request(disk)], restore: false) }
            .toolboxProminentButton().disabled(busy || !validPath(disk))
    }
    private func request(_ disk: DiskVolume) -> DiskMountRequest { DiskMountRequest(volume: disk, path: model.diskPaths[disk.id, default: ""]) }
    private func validPath(_ disk: DiskVolume) -> Bool { (try? InputValidation.normalizedAbsolutePath(model.diskPaths[disk.id, default: ""])) != nil }

    private var batchCard: some View {
        ToolboxCard(tr("批量操作清单", "Batch Operation List"), subtitle: tr("仅操作下方列出的磁盘。请分别设置挂载路径。", "Only the volumes listed below will be affected. Set a destination for each volume.")) {
            Text("\(tr("已选择", "Selected")) \(batchVolumes.count)").font(.subheadline)
            ForEach(batchVolumes) { disk in
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(disk.name) · \(disk.id)").font(.headline)
                    pathEditor(disk)
                    Divider()
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack { batchRestoreButton; batchMountButton }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading) { batchRestoreButton; batchMountButton }
            }
        }
        .disabled(model.isDiskBusy)
    }
    private var batchRestoreButton: some View {
        Button(tr("批量恢复默认挂载", "Restore Batch Defaults")) { pendingAction = PendingDiskAction(requests: batchVolumes.map(request), restore: true) }
            .disabled(busy || batchVolumes.isEmpty)
    }
    private var batchMountButton: some View {
        Button(tr("批量挂载", "Mount Batch")) { pendingAction = PendingDiskAction(requests: batchVolumes.map(request), restore: false) }
            .toolboxProminentButton().disabled(busy || batchVolumes.isEmpty || !batchVolumes.allSatisfy(validPath))
    }

    private func confirmation(_ action: PendingDiskAction) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(action.restore ? tr("确认恢复默认挂载", "Confirm Default Restoration") : tr("确认挂载", "Confirm Mount")).font(.title2.bold())
            Text(tr("以下清单为本次操作对象。", "This list contains all volumes affected by this operation."))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(action.requests, id: \.volume.id) { request in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(request.volume.name) · \(request.volume.id)").font(.headline)
                            Text(request.volume.volumeUUID ?? "—").font(.caption.monospaced())
                            Text(request.volume.mountPoint ?? tr("未挂载", "Unmounted"))
                            Text("→ " + (action.restore ? tr("系统默认路径", "System Default") : request.path))
                        }.textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 300)
            HStack {
                Button(tr("取消", "Cancel"), role: .cancel) { pendingAction = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(tr("确认", "Confirm")) {
                    if action.restore { model.restoreDisks(action.requests.map(\.volume)) } else { model.mountDisks(action.requests) }
                    pendingAction = nil
                }.toolboxProminentButton().disabled(busy)
            }
        }.padding(24).frame(width: 500)
    }

    private func resultCard(_ result: DiskBatchResult) -> some View {
        ToolboxCard(tr("操作结果", "Operation Results")) {
            if let warning = model.diskRefreshError { Text(warning).foregroundStyle(.orange).textSelection(.enabled) }
            if let error = result.preflightError { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            ForEach(Array(result.items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(item.volume.name) · \(item.volume.id): \(outcomeText(item.outcome))").font(.subheadline.weight(.medium))
                    if !item.message.isEmpty { Text(item.message).font(.caption).textSelection(.enabled) }
                }.fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func outcomeText(_ outcome: DiskOperationOutcome) -> String {
        switch outcome {
        case .succeeded: return tr("成功", "Succeeded")
        case .unchanged: return tr("无需更改", "No Change Needed")
        case .failed: return tr("失败", "Failed")
        case .rolledBack: return tr("已恢复操作前状态", "Rolled Back to Previous State")
        case .rollbackFailed: return tr("回滚失败，请检查挂载状态", "Rollback Failed; Check Mount State")
        case .notAttempted: return tr("未执行", "Not Attempted")
        }
    }

    private var automaticRestoreCard: some View {
        ToolboxCard(tr("启动时自动恢复", "Automatic Restoration"), subtitle: tr("开启后每秒检测可用磁盘，应用启动 10 秒后尝试恢复上次自定义挂载。推出或卸载磁盘不会清除记录，恢复默认挂载会停止下次恢复。", "When enabled, available volumes are checked every second and previous custom mounts are restored 10 seconds after launch. Ejecting does not clear records; restoring defaults does.")) {
            Toggle(tr("开启应用时自动恢复上次挂载", "Restore Previous Mounts at Launch"), isOn: Binding(get: { model.configuration.automaticallyRestoreMountsOnLaunch }, set: { model.setAutomaticallyRestoreMountsOnLaunch($0) })).toggleStyle(.switch)
            ForEach(model.configuration.restorableDiskMounts, id: \.self) { record in recordRow(record, automatic: true) }
        }.disabled(model.isDiskBusy)
    }

    private var configurationCard: some View {
        ToolboxCard(tr("默认路径与磁盘预设", "Default Paths & Volume Presets"), subtitle: tr("默认路径用于快速填入目标目录；磁盘预设按 UUID 关联，不会因编号变化而改用其他磁盘。", "Default paths fill destinations quickly. Presets use UUIDs so device renumbering cannot select another volume.")) {
            HStack { Text(tr("默认路径", "Default Paths")).font(.headline); Spacer(); Button(tr("添加路径", "Add Path")) { model.addDefaultPath() } }
            if model.configuration.defaultPaths.isEmpty { Text(tr("尚未添加默认路径。", "No default paths added.")).font(.caption).foregroundStyle(.secondary) }
            ForEach(model.configuration.defaultPaths, id: \.self) { path in
                HStack {
                    Text(path).font(.caption.monospaced()).lineLimit(2).textSelection(.enabled)
                    Spacer()
                    Button(tr("删除", "Delete"), role: .destructive) { model.deleteDefaultPath(path) }.buttonStyle(.borderless)
                }
            }
            Divider()
            Text(tr("磁盘预设", "Volume Presets")).font(.headline)
            if model.configuration.diskPresets.isEmpty { Text(tr("尚未保存磁盘预设。", "No volume presets saved.")).font(.caption).foregroundStyle(.secondary) }
            ForEach(model.configuration.diskPresets, id: \.self) { record in recordRow(record, automatic: false) }
        }.disabled(model.isDiskBusy)
    }
    private func recordRow(_ record: DiskPreset, automatic: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DiskService.matchingVolume(for: record, in: model.disks)?.name ?? record.diskIdentifier).font(.subheadline.weight(.medium))
            Text(record.mountPath ?? tr("未绑定路径", "No path")).font(.caption.monospaced()).textSelection(.enabled)
            if record.volumeUUID == nil { Text(tr("旧记录需要重新关联", "Legacy record needs association")).font(.caption).foregroundStyle(.orange) }
            if automatic, let entry = DiskRestorationPlan(presets: [record], volumes: model.disks).entries.first { Text(model.restorationStateText(entry.state)).font(.caption).foregroundStyle(.secondary) }
            HStack {
                if record.volumeUUID == nil, let disk = activeVolume, disk.volumeUUID != nil {
                    Button(tr("关联当前磁盘", "Associate Current Volume")) { pendingAssociation = DiskAssociation(preset: record, volume: disk, automatic: automatic) }
                }
                Button(tr("删除", "Delete"), role: .destructive) { model.deleteDiskPreset(record, automatic: automatic) }.buttonStyle(.borderless)
            }
            Divider()
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
            Text(value).font(.caption.monospaced()).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.caption)
    }
    private func formattedSize(_ size: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }
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
