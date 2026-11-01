import Foundation

public actor DiskService {
    public static let maximumBatchMounts = Int.max

    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func listEligibleVolumes() async throws -> [DiskVolume] {
        let list = try await runner.run("/usr/sbin/diskutil", arguments: ["list", "-plist"])
        let boot = try await runner.run("/usr/sbin/diskutil", arguments: ["info", "-plist", "/"])
        let listInfo = try Self.propertyList(list.standardOutput)
        let bootInfo = try Self.propertyList(boot.standardOutput)
        let reserved = Set(Self.nestedVolumeDictionaries(in: listInfo).compactMap { item -> String? in
            guard let content = Self.string(item, keys: ["Content"])?.uppercased(),
                  content == "EFI" || content == "C12A7328-F81F-11D2-BA4B-00A0C93EC93B" else { return nil }
            return Self.string(item, keys: ["DeviceIdentifier"])
        })
        let identifiers = (listInfo["AllDisks"] as? [String] ?? []).filter { InputValidation.diskIdentifier($0) && !reserved.contains($0) }
        var volumes: [DiskVolume] = []
        for identifier in identifiers {
            guard let result = try? await runner.run("/usr/sbin/diskutil", arguments: ["info", "-plist", identifier]),
                  let info = try? Self.propertyList(result.standardOutput),
                  let volume = Self.parseVolumeInfo(info, bootInfo: bootInfo) else { continue }
            volumes.append(volume)
        }
        return volumes.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    private var operationInProgress = false

    /// Validates the entire immutable request before any directory or mount is changed.
    public static func validateMountRequests(_ requests: [DiskMountRequest], volumes: [DiskVolume]) throws -> [DiskMountRequest] {
        guard !requests.isEmpty else { throw ToolboxError.invalidPath(coreText("请选择磁盘", "Select a volume")) }
        var identifiers = Set<String>()
        let byID = Dictionary(volumes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sourceMounts = requests.compactMap { request -> (String, String)? in
            guard let live = byID[request.volume.id], sameIdentity(live, request.volume), let mount = live.mountPoint else { return nil }
            return (live.id, canonicalMountPath(mount))
        }
        let occupied = volumes.compactMap { volume in volume.mountPoint.map { (volume.id, canonicalMountPath($0)) } }
        var normalized: [DiskMountRequest] = []
        var canonicalPaths: [String] = []
        for request in requests {
            guard identifiers.insert(request.volume.id).inserted,
                  let live = byID[request.volume.id], sameIdentity(live, request.volume) else {
                throw ToolboxError.invalidDisk(request.volume.id)
            }
            let path = try InputValidation.normalizedAbsolutePath(request.path)
            let canonical = canonicalMountPath(path)
            guard canonical != "/", !isWithin(canonical, directory: "/System"),
                  !isWithin(canonical, directory: "/dev"),
                  !isWithin(canonical, directory: "/private/var/run") else { throw ToolboxError.invalidPath(path) }
            for previous in canonicalPaths {
                guard !isWithin(canonical, directory: previous), !isWithin(previous, directory: canonical) else {
                    throw ToolboxError.invalidPath(coreText("挂载路径重复或相互包含：", "Mount paths overlap: ") + path)
                }
            }
            for (id, mount) in occupied where id != live.id && mount == canonical {
                throw ToolboxError.invalidPath(coreText("目标路径已被其他卷占用：", "Destination is mounted by another volume: ") + path)
            }
            for (id, sourcePath) in sourceMounts {
                if !(id == live.id && canonical == sourcePath), isWithin(canonical, directory: sourcePath) {
                    throw ToolboxError.invalidPath(coreText("目标目录位于本次操作的磁盘内：", "Destination is inside a volume being remounted: ") + path)
                }
                if canonical != sourcePath, isWithin(sourcePath, directory: canonical) { throw ToolboxError.invalidPath(path) }
            }
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &directory) {
                guard directory.boolValue else { throw ToolboxError.invalidPath(path) }
                if live.mountPoint.map(canonicalMountPath) != canonical {
                    guard try FileManager.default.contentsOfDirectory(atPath: path).isEmpty else {
                        throw ToolboxError.invalidPath(coreText("目标目录必须为空：", "Destination must be empty: ") + path)
                    }
                }
            }
            canonicalPaths.append(canonical)
            normalized.append(DiskMountRequest(volume: live, path: path))
        }
        return normalized
    }

    public static func sameIdentity(_ lhs: DiskVolume, _ rhs: DiskVolume) -> Bool {
        guard lhs.id == rhs.id else { return false }
        if let uuid = rhs.volumeUUID { return lhs.volumeUUID?.caseInsensitiveCompare(uuid) == .orderedSame }
        return lhs.volumeUUID == nil && lhs.name == rhs.name && lhs.fileSystem == rhs.fileSystem && lhs.wholeDisk == rhs.wholeDisk
    }

    /// Batch mounts are transactional. Every entry has a final result, including rollback failures.
    public func mountVolumes(_ requests: [DiskMountRequest]) async -> DiskBatchResult {
        guard !operationInProgress else { return .rejected(requests.map(\.volume), message: coreText("磁盘操作正在进行", "A volume operation is in progress")) }
        operationInProgress = true
        defer { operationInProgress = false }
        let prepared: [DiskMountRequest]
        do {
            let volumes = try await listEligibleVolumes()
            prepared = try Self.validateMountRequests(requests, volumes: volumes)
            for request in prepared {
                try FileManager.default.createDirectory(atPath: request.path, withIntermediateDirectories: true)
            }
        } catch { return .rejected(requests.map(\.volume), message: error.localizedDescription) }

        var items = prepared.map { DiskOperationResult(volume: $0.volume, outcome: .notAttempted) }
        var touched: [Int] = []
        for index in prepared.indices {
            var changed = false
            do {
                if prepared[index].volume.mountPoint.map(Self.canonicalMountPath) == Self.canonicalMountPath(prepared[index].path) {
                    // Revalidate identity even when the requested mount is already in place.
                    let live = try await verifiedVolume(prepared[index].volume)
                    guard live.mountPoint.map(Self.canonicalMountPath) == Self.canonicalMountPath(prepared[index].path) else {
                        throw ToolboxError.commandFailed(coreText("挂载状态已改变，请刷新后重试", "Mount state changed; refresh and try again"))
                    }
                    items[index].outcome = .unchanged
                    continue
                }
                try await replaceMount(prepared[index].volume, at: prepared[index].path, changed: &changed)
                if changed { touched.append(index) }
                items[index].outcome = .succeeded
            } catch {
                items[index].outcome = .failed
                items[index].message = error.localizedDescription
                if changed { touched.append(index) }
                for changedIndex in touched.reversed() {
                    do {
                        try await restoreSnapshot(prepared[changedIndex].volume)
                        items[changedIndex].outcome = .rolledBack
                    } catch {
                        items[changedIndex].outcome = .rollbackFailed
                        items[changedIndex].message += " " + coreText("回滚失败：", "Rollback failed: ") + error.localizedDescription
                    }
                }
                break
            }
        }
        return DiskBatchResult(items: items)
    }

    /// Default restoration reports each result and only rolls back the failed item.
    public func restoreVolumes(_ volumes: [DiskVolume]) async -> DiskBatchResult {
        guard !volumes.isEmpty, Set(volumes.map(\.id)).count == volumes.count else {
            return .rejected(volumes, message: coreText("磁盘清单为空或重复", "Volume list is empty or contains duplicates"))
        }
        guard !operationInProgress else { return .rejected(volumes, message: coreText("磁盘操作正在进行", "A volume operation is in progress")) }
        operationInProgress = true
        defer { operationInProgress = false }
        var items: [DiskOperationResult] = []
        for volume in volumes {
            var item = DiskOperationResult(volume: volume, outcome: .failed)
            var changed = false
            var snapshot: DiskVolume?
            do {
                let original = try await verifiedVolume(volume)
                snapshot = original
                if original.mountPoint.map(Self.canonicalMountPath) == Self.canonicalMountPath("/Volumes/" + original.name) {
                    item.outcome = .unchanged
                    items.append(item)
                    continue
                }
                try await replaceMount(original, at: nil, changed: &changed)
                item.outcome = .succeeded
            } catch {
                item.message = error.localizedDescription
                if changed, let snapshot {
                    do { try await restoreSnapshot(snapshot); item.outcome = .rolledBack }
                    catch { item.outcome = .rollbackFailed; item.message += " " + coreText("回滚失败：", "Rollback failed: ") + error.localizedDescription }
                }
            }
            items.append(item)
        }
        return DiskBatchResult(items: items)
    }

    private func verifiedVolume(_ expected: DiskVolume) async throws -> DiskVolume {
        let live = try await readEligibleVolume(expected.id)
        guard Self.sameIdentity(live, expected) else { throw ToolboxError.invalidDisk(expected.id) }
        return live
    }

    private func readEligibleVolume(_ identifier: String) async throws -> DiskVolume {
        guard InputValidation.diskIdentifier(identifier) else { throw ToolboxError.invalidDisk(identifier) }
        let boot = try await runner.run("/usr/sbin/diskutil", arguments: ["info", "-plist", "/"])
        let info = try await runner.run("/usr/sbin/diskutil", arguments: ["info", "-plist", identifier])
        guard let volume = Self.parseVolumeInfo(try Self.propertyList(info.standardOutput), bootInfo: try Self.propertyList(boot.standardOutput)) else {
            throw ToolboxError.invalidDisk(identifier)
        }
        return volume
    }

    private func replaceMount(_ volume: DiskVolume, at path: String?, changed: inout Bool) async throws {
        let live = try await verifiedVolume(volume)
        // A changed mount since preflight is an external operation; do not overwrite it.
        guard live.mountPoint.map(Self.canonicalMountPath) == volume.mountPoint.map(Self.canonicalMountPath) else {
            throw ToolboxError.commandFailed(coreText("挂载状态已改变，请刷新后重试", "Mount state changed; refresh and try again"))
        }
        if live.mountPoint != nil {
            _ = try await runner.run("/usr/sbin/diskutil", arguments: ["unmount", live.id])
            changed = true
        }
        _ = try await verifiedVolume(volume)
        changed = true
        let arguments = path.map { ["mount", "-mountPoint", $0, "/dev/\(volume.id)"] } ?? ["mount", volume.id]
        _ = try await runner.run("/usr/sbin/diskutil", arguments: arguments)
        try await confirm(volume, path: path, mounted: true)
    }

    private func confirm(_ volume: DiskVolume, path: String?, mounted: Bool) async throws {
        for attempt in 0..<10 {
            let live = try await verifiedVolume(volume)
            if mounted {
                if let actual = live.mountPoint, path == nil || Self.canonicalMountPath(actual) == path.map(Self.canonicalMountPath) { return }
            } else if live.mountPoint == nil { return }
            if attempt < 9 { try await Task.sleep(for: .milliseconds(200)) }
        }
        throw ToolboxError.commandFailed(coreText("磁盘挂载状态验证失败", "Volume mount verification failed"))
    }

    private func restoreSnapshot(_ original: DiskVolume) async throws {
        let live = try await verifiedVolume(original)
        if live.mountPoint.map(Self.canonicalMountPath) == original.mountPoint.map(Self.canonicalMountPath) { return }
        if live.mountPoint != nil { _ = try await runner.run("/usr/sbin/diskutil", arguments: ["unmount", original.id]) }
        _ = try await verifiedVolume(original)
        if let path = original.mountPoint {
            _ = try await runner.run("/usr/sbin/diskutil", arguments: ["mount", "-mountPoint", path, "/dev/\(original.id)"])
        }
        try await confirm(original, path: original.mountPoint, mounted: original.mountPoint != nil)
    }

    public func mount(_ identifier: String, at path: String) async throws {
        let volume = try await readEligibleVolume(identifier)
        let result = await mountVolumes([DiskMountRequest(volume: volume, path: path)])
        guard result.isSuccess else { throw ToolboxError.commandFailed(result.description) }
    }

    public func restoreDefaultMount(_ identifier: String) async throws {
        let volume = try await readEligibleVolume(identifier)
        let result = await restoreVolumes([volume])
        guard result.isSuccess else { throw ToolboxError.commandFailed(result.description) }
    }

    public static func matchingVolume(for preset: DiskPreset, in volumes: [DiskVolume]) -> DiskVolume? {
        // A record without a stable identity must be explicitly associated by the user.
        guard let uuid = preset.volumeUUID else { return nil }
        let matches = volumes.filter { $0.volumeUUID?.caseInsensitiveCompare(uuid) == .orderedSame }
        return matches.count == 1 ? matches[0] : nil
    }

    public static func canonicalMountPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func isWithin(_ path: String, directory: String) -> Bool {
        path == directory || path.hasPrefix(directory + "/")
    }

    public static func parseVolumes(_ data: Data, excludingWholeDisk bootWholeDisk: String?) throws -> [DiskVolume] {
        let root = try propertyList(data)
        guard let disks = root["AllDisksAndPartitions"] as? [[String: Any]] else {
            throw ToolboxError.malformedOutput("AllDisksAndPartitions")
        }
        var volumes: [DiskVolume] = []
        for disk in disks {
            let wholeDisk = string(disk, keys: ["DeviceIdentifier"]) ?? ""
            guard !wholeDisk.isEmpty, wholeDisk != bootWholeDisk else { continue }
            let isInternal = (disk["Internal"] as? Bool) ?? false
            for volume in nestedVolumeDictionaries(in: disk) {
                guard let identifier = string(volume, keys: ["DeviceIdentifier"]), InputValidation.diskIdentifier(identifier) else { continue }
                let content = string(volume, keys: ["Content", "FilesystemType", "Type"]) ?? "unknown"
                guard let name = string(volume, keys: ["VolumeName"]) else { continue }
                let mountPoint = string(volume, keys: ["MountPoint"])
                let size = (volume["Size"] as? NSNumber)?.uint64Value ?? 0
                let volumeUUID = string(volume, keys: ["VolumeUUID", "DiskUUID"])
                volumes.append(DiskVolume(id: identifier, volumeUUID: volumeUUID, name: name, fileSystem: content, mountPoint: mountPoint, size: size, wholeDisk: wholeDisk, isInternal: isInternal))
            }
        }
        return volumes.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    public static func systemWholeDisks(from bootInfo: [String: Any]) -> Set<String> {
        var disks = Set<String>()
        if let parent = string(bootInfo, keys: ["ParentWholeDisk", "PartOfWhole"]) { disks.insert(parent) }
        if let stores = bootInfo["APFSPhysicalStores"] as? [[String: Any]] {
            for store in stores {
                if let identifier = string(store, keys: ["APFSPhysicalStore", "DeviceIdentifier"]),
                   let match = identifier.range(of: #"^disk[0-9]+"#, options: .regularExpression) {
                    disks.insert(String(identifier[match]))
                }
            }
        }
        return disks
    }

    public static func parseVolumeInfo(_ info: [String: Any], bootInfo: [String: Any]) -> DiskVolume? {
        guard let identifier = string(info, keys: ["DeviceIdentifier"]),
              InputValidation.diskIdentifier(identifier),
              let parent = string(info, keys: ["ParentWholeDisk"]),
              (info["WholeDisk"] as? Bool) != true,
              let name = string(info, keys: ["VolumeName"]),
              let fileSystem = string(info, keys: ["FilesystemType", "FilesystemName"]) else { return nil }
        let mountPoint = string(info, keys: ["MountPoint"])
        let reservedIdentifiers = ["DeviceIdentifier", "BooterDeviceIdentifier", "RecoveryDeviceIdentifier"]
            .compactMap { string(bootInfo, keys: [$0]) }
        let bootGroup = string(bootInfo, keys: ["APFSVolumeGroupID"])
        let volumeGroup = string(info, keys: ["APFSVolumeGroupID"])
        let content = string(info, keys: ["Content"])?.uppercased() ?? ""
        let roles = (info["APFSVolumeRole"] as? [String] ?? []) + (info["Roles"] as? [String] ?? [])
        let role = string(info, keys: ["APFSVolumeRole"]).map { [$0] } ?? []
        let protectedRoles = Set(["SYSTEM", "PREBOOT", "RECOVERY", "VM", "UPDATE", "XART", "HARDWARE", "ISCPreboot".uppercased()])
        if content == "EFI" || content == "C12A7328-F81F-11D2-BA4B-00A0C93EC93B" || !(Set((roles + role).map { $0.uppercased() }).intersection(protectedRoles)).isEmpty { return nil }
        let reservedNames = Set(["Recovery", "Update", "Preboot", "VM", "xART", "Hardware", "iSCPreboot"])
        if reservedIdentifiers.contains(identifier) || (bootGroup != nil && volumeGroup == bootGroup) { return nil }
        if mountPoint == "/" || mountPoint?.hasPrefix("/System/") == true || mountPoint?.hasPrefix("/private/var/run/com.apple") == true { return nil }
        if (info["Internal"] as? Bool) == true && reservedNames.contains(name) { return nil }
        let size = (info["TotalSize"] as? NSNumber)?.uint64Value ?? (info["Size"] as? NSNumber)?.uint64Value ?? 0
        return DiskVolume(
            id: identifier,
            volumeUUID: string(info, keys: ["VolumeUUID", "DiskUUID"]),
            name: name,
            fileSystem: fileSystem,
            mountPoint: mountPoint,
            size: size,
            wholeDisk: parent,
            isInternal: (info["Internal"] as? Bool) ?? false,
            isRemovable: (info["RemovableMedia"] as? Bool) == true || (info["Removable"] as? Bool) == true
        )
    }

    private static func nestedVolumeDictionaries(in dictionary: [String: Any]) -> [[String: Any]] {
        dictionary.values.flatMap { value -> [[String: Any]] in
            if let child = value as? [String: Any] { return [child] + nestedVolumeDictionaries(in: child) }
            if let children = value as? [[String: Any]] {
                return children.flatMap { [$0] + nestedVolumeDictionaries(in: $0) }
            }
            return []
        }
    }

    fileprivate static func propertyList(_ data: Data) throws -> [String: Any] {
        guard let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ToolboxError.malformedOutput("property list root")
        }
        return value
    }

    fileprivate static func string(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

}

public struct DiskMountRequest: Sendable {
    public let volume: DiskVolume
    public let path: String
    public init(volume: DiskVolume, path: String) { self.volume = volume; self.path = path }
}

public enum DiskOperationOutcome: String, Sendable {
    case succeeded, unchanged, failed, rolledBack, rollbackFailed, notAttempted
}

public struct DiskOperationResult: Sendable {
    public let volume: DiskVolume
    public var outcome: DiskOperationOutcome
    public var message: String
    public init(volume: DiskVolume, outcome: DiskOperationOutcome, message: String = "") {
        self.volume = volume; self.outcome = outcome; self.message = message
    }
    public var succeeded: Bool { outcome == .succeeded || outcome == .unchanged }
}

public struct DiskBatchResult: Sendable {
    public var items: [DiskOperationResult]
    public var preflightError: String?
    public init(items: [DiskOperationResult], preflightError: String? = nil) { self.items = items; self.preflightError = preflightError }
    public var isSuccess: Bool { preflightError == nil && !items.isEmpty && items.allSatisfy(\.succeeded) }
    public var description: String {
        if let preflightError { return preflightError }
        return items.map { "\($0.volume.name) (\($0.volume.id)): \($0.outcome.rawValue) \($0.message)" }.joined(separator: "\n")
    }
    public static func rejected(_ volumes: [DiskVolume], message: String) -> Self {
        Self(items: volumes.map { DiskOperationResult(volume: $0, outcome: .notAttempted, message: message) }, preflightError: message)
    }
}

public enum DiskRestorationState: Sendable { case ready, alreadyMounted, offline, needsAssociation, invalidPath }
public struct DiskRestorationEntry: Sendable {
    public let preset: DiskPreset
    public let state: DiskRestorationState
}
public struct DiskRestorationPlan: Sendable {
    public let requests: [DiskMountRequest]
    public let entries: [DiskRestorationEntry]
    public init(presets: [DiskPreset], volumes: [DiskVolume]) {
        var requests: [DiskMountRequest] = []
        var entries: [DiskRestorationEntry] = []
        var seen = Set<String>()
        for preset in presets {
            let state: DiskRestorationState
            if preset.volumeUUID == nil { state = .needsAssociation }
            else if let volume = DiskService.matchingVolume(for: preset, in: volumes) {
                var directory: ObjCBool = false
                if let value = preset.mountPath, let path = try? InputValidation.normalizedAbsolutePath(value),
                   FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue {
                    if volume.mountPoint.map(DiskService.canonicalMountPath) == DiskService.canonicalMountPath(path) { state = .alreadyMounted }
                    else if seen.insert(volume.id).inserted { requests.append(DiskMountRequest(volume: volume, path: path)); state = .ready }
                    else { state = .invalidPath }
                } else { state = .invalidPath }
            } else { state = .offline }
            entries.append(DiskRestorationEntry(preset: preset, state: state))
        }
        self.requests = requests
        self.entries = entries
    }
}
