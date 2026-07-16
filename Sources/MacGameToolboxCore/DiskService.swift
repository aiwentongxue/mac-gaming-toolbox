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
        let identifiers = (listInfo["AllDisks"] as? [String] ?? []).filter(InputValidation.diskIdentifier)
        var volumes: [DiskVolume] = []
        for identifier in identifiers {
            guard let result = try? await runner.run("/usr/sbin/diskutil", arguments: ["info", "-plist", identifier]),
                  let info = try? Self.propertyList(result.standardOutput),
                  let volume = Self.parseVolumeInfo(info, bootInfo: bootInfo) else { continue }
            volumes.append(volume)
        }
        return volumes.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    public func mount(_ identifier: String, at path: String) async throws {
        guard InputValidation.diskIdentifier(identifier) else { throw ToolboxError.invalidDisk(identifier) }
        let normalizedPath = try InputValidation.normalizedAbsolutePath(path)
        _ = try? await runner.run("/usr/sbin/diskutil", arguments: ["unmount", identifier])
        do {
            _ = try await runner.run("/usr/sbin/diskutil", arguments: ["mount", "-mountPoint", normalizedPath, "/dev/\(identifier)"])
            for attempt in 0..<10 {
                if let info = try? await runner.run("/usr/sbin/diskutil", arguments: ["info", "-plist", identifier]),
                   let plist = try? Self.propertyList(info.standardOutput),
                   let reportedPath = Self.string(plist, keys: ["MountPoint"]),
                   Self.canonicalMountPath(reportedPath) == Self.canonicalMountPath(normalizedPath) {
                    return
                }
                if attempt < 9 { try await Task.sleep(for: .milliseconds(200)) }
            }
            throw ToolboxError.commandFailed(coreText("磁盘未挂载到指定路径", "Volume did not mount at requested path"))
        } catch {
            // A successful diskutil mount can become visible to `info` slightly later.
            // If confirmation ultimately fails, also roll back this current volume;
            // mountBatch only knows about volumes that were already confirmed.
            try? await restoreDefaultMount(identifier)
            throw error
        }
    }

    public func restoreDefaultMount(_ identifier: String) async throws {
        guard InputValidation.diskIdentifier(identifier) else { throw ToolboxError.invalidDisk(identifier) }
        _ = try? await runner.run("/usr/sbin/diskutil", arguments: ["unmount", identifier])
        _ = try await runner.run("/usr/sbin/diskutil", arguments: ["mount", identifier])
    }

    public func mountBatch(_ assignments: [(String, String)]) async -> [String: Result<Void, Error>] {
        var results: [String: Result<Void, Error>] = [:]
        var mounted: [String] = []
        for (identifier, path) in assignments {
            do {
                try await mount(identifier, at: path)
                mounted.append(identifier)
                results[identifier] = .success(())
            } catch {
                results[identifier] = .failure(error)
                for mountedIdentifier in mounted { try? await restoreDefaultMount(mountedIdentifier) }
                break
            }
        }
        return results
    }

    public static func matchingVolume(for preset: DiskPreset, in volumes: [DiskVolume]) -> DiskVolume? {
        if let volumeUUID = preset.volumeUUID,
           let volume = volumes.first(where: { $0.volumeUUID?.caseInsensitiveCompare(volumeUUID) == .orderedSame }) {
            return volume
        }
        return volumes.first { $0.id == preset.diskIdentifier }
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
            isInternal: (info["Internal"] as? Bool) ?? false
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

    private static func canonicalMountPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
