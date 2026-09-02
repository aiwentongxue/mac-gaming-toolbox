import Foundation

public enum PrivilegedOperation: Sendable, Equatable {
    case healthCheck
    case addHoYoHosts
    case removeHoYoHosts
    /// `-20` is the highest scheduling priority and `20` is the lowest user-process priority.
    /// Keep the value in the request so the privileged helper, rather than the UI,
    /// remains the only component that changes a process's scheduling priority.
    case renice([Int32], Int32)
    case clearSystemCaches
    case setHostnames(HostnameBackup)
    case createDirectory(String)
}

public protocol PrivilegedOperating: Sendable {
    func perform(_ operation: PrivilegedOperation) async throws
}

public actor GamingService {
    public static let hoyoDomains = [
        "globaldp-prod-cn01.bhsr.com", "globaldp-prod-os01.starrails.com",
        "dispatchcnglobal.yuanshen.com", "dispatchosglobal.yuanshen.com",
        "globaldp-prod-cn01.juequling.com", "globaldp-prod-cn02.juequling.com",
        "globaldp-prod-os01.zenlesszonezero.com", "globaldp-prod-os02.zenlesszonezero.com"
    ]

    private let runner: any CommandRunning
    private let privileged: any PrivilegedOperating

    public init(runner: any CommandRunning = ProcessCommandRunner(), privileged: any PrivilegedOperating) {
        self.runner = runner
        self.privileged = privileged
    }

    public func metalHUDEnabled() async -> Bool {
        guard let result = try? await runner.run("/bin/launchctl", arguments: ["getenv", "MTL_HUD_ENABLED"]) else { return false }
        return result.outputString == "1"
    }

    public func setMetalHUD(enabled: Bool) async throws {
        let arguments = enabled ? ["setenv", "MTL_HUD_ENABLED", "1"] : ["unsetenv", "MTL_HUD_ENABLED"]
        _ = try await runner.run("/bin/launchctl", arguments: arguments)
    }

    public func launchWithMetalHUD(applicationPath: String, presetPath: String? = nil) async throws {
        let applicationURL = URL(fileURLWithPath: applicationPath).standardizedFileURL
        guard applicationURL.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: applicationURL.path) else {
            throw ToolboxError.invalidPath(applicationPath)
        }
        var environment: [String] = []
        if let presetPath, !presetPath.isEmpty {
            let presetURL = URL(fileURLWithPath: presetPath).standardizedFileURL
            guard FileManager.default.fileExists(atPath: presetURL.path) else {
                throw ToolboxError.invalidPath(presetPath)
            }
            // Recent MetalHUD exports may contain legacy numeric alignment values.
            // Expand the plist into the app's launch environment instead of relying on
            // MTL_HUD_CONFIG_FILE, which currently ignores those values on some macOS builds.
            environment = try Self.metalHUDEnvironment(from: presetURL)
        }
        environment.removeAll { $0.hasPrefix("MTL_HUD_ENABLED=") }
        environment.append("MTL_HUD_ENABLED=1")
        _ = try await runner.run(
            "/usr/bin/env",
            arguments: environment + ["/usr/bin/open", "-a", applicationURL.path]
        )
    }

    /// Reads Xcode's CoreDevice inventory. This is intentionally read-only.
    public func iosDevices() async throws -> [IOSDevice] {
        let result = try await runner.run(
            "/usr/bin/xcrun",
            arguments: ["devicectl", "list", "devices", "--json-output", "-"]
        )
        return try Self.parseIOSDevices(result.outputString)
    }

    /// Lists installed apps exposed by CoreDevice for one selected iOS device.
    public func iosApps(on deviceID: String) async throws -> [IOSInstalledApp] {
        guard Self.isDeviceIdentifier(deviceID) else { throw ToolboxError.invalidPath(deviceID) }
        let result = try await runner.run(
            "/usr/bin/xcrun",
            arguments: ["devicectl", "device", "info", "apps", "--include-all-apps", "--device", deviceID, "--json-output", "-"]
        )
        return try Self.parseIOSApps(result.outputString)
    }

    /// Launches only the selected bundle with a process-scoped Metal HUD environment.
    public func launchIOSAppWithMetalHUD(deviceID: String, bundleIdentifier: String, launchArguments: [String] = []) async throws {
        guard Self.isDeviceIdentifier(deviceID), Self.isBundleIdentifier(bundleIdentifier) else {
            throw ToolboxError.invalidPath(bundleIdentifier)
        }
        guard launchArguments.count <= 128,
              launchArguments.allSatisfy({ !$0.contains("\0") && !$0.contains("\n") }) else {
            throw ToolboxError.invalidPath(coreText("iOS 启动参数", "iOS launch arguments"))
        }
        let environment = "{\"MTL_HUD_ENABLED\":\"1\"}"
        var arguments = [
            "devicectl", "device", "process", "launch", "--device", deviceID,
            "--environment-variables", environment, "--terminate-existing", bundleIdentifier
        ]
        if !launchArguments.isEmpty { arguments += ["--"] + launchArguments }
        _ = try await runner.run(
            "/usr/bin/xcrun",
            arguments: arguments
        )
    }

    public static func parseIOSDevices(_ text: String) throws -> [IOSDevice] {
        let objects = try jsonRows(text, arrayKeys: ["devices"])
        return objects.compactMap { object in
            guard let identifier = string(in: object, keys: ["identifier", "udid", "deviceIdentifier"]),
                  isDeviceIdentifier(identifier) else { return nil }
            let name = string(in: object, keys: ["name", "deviceName"]) ?? identifier
            return IOSDevice(
                id: identifier,
                name: name,
                model: string(in: object, keys: ["modelName", "productType", "model"]) ?? "",
                state: string(in: object, keys: ["state", "connectionState"]) ?? ""
            )
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public static func parseIOSApps(_ text: String) throws -> [IOSInstalledApp] {
        let objects = try jsonRows(text, arrayKeys: ["apps", "applications"])
        var seen = Set<String>()
        return objects.compactMap { object in
            guard let bundleIdentifier = string(in: object, keys: ["bundleIdentifier", "bundleID"]),
                  isBundleIdentifier(bundleIdentifier), seen.insert(bundleIdentifier).inserted else { return nil }
            return IOSInstalledApp(
                bundleIdentifier: bundleIdentifier,
                displayName: string(in: object, keys: ["displayName", "name"]) ?? bundleIdentifier,
                version: string(in: object, keys: ["version", "shortVersion", "CFBundleShortVersionString"]) ?? ""
            )
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private static func jsonRows(_ text: String, arrayKeys: Set<String>) throws -> [[String: Any]] {
        guard let data = text.data(using: .utf8) else { throw ToolboxError.malformedOutput(coreText("无法读取 devicectl 输出", "Unable to read devicectl output")) }
        let root: Any
        do { root = try JSONSerialization.jsonObject(with: data) }
        catch { throw ToolboxError.malformedOutput(coreText("devicectl 没有返回可识别的 JSON", "devicectl did not return valid JSON")) }
        var rows: [[String: Any]] = []
        func visit(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                for (key, nested) in dictionary where arrayKeys.contains(key) {
                    if let items = nested as? [Any] {
                        rows.append(contentsOf: items.compactMap { $0 as? [String: Any] })
                    }
                }
                dictionary.values.forEach(visit)
            } else if let array = value as? [Any] {
                array.forEach(visit)
            }
        }
        visit(root)
        return rows
    }

    private static func string(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        for value in object.values {
            if let nested = value as? [String: Any], let match = string(in: nested, keys: keys) { return match }
        }
        return nil
    }

    private static func isDeviceIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 255 && !value.contains("\0") && !value.contains("\n")
    }

    private static func isBundleIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil
    }

    public static func metalHUDEnvironment(from presetURL: URL) throws -> [String] {
        let data = try Data(contentsOf: presetURL)
        let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let properties = value as? [String: Any] else {
            throw ToolboxError.malformedOutput(coreText("MetalHUD 预设不是有效的属性列表", "The MetalHUD preset is not a valid property list"))
        }
        return try properties.keys.sorted().compactMap { key in
            guard key.hasPrefix("MTL_HUD_") else { return nil }
            guard let text = metalHUDValue(properties[key], for: key) else {
                throw ToolboxError.malformedOutput(coreText("MetalHUD 预设包含不支持的值：\(key)", "The MetalHUD preset contains an unsupported value: \(key)"))
            }
            return "\(key)=\(text)"
        }
    }

    private static func metalHUDValue(_ value: Any?, for key: String) -> String? {
        if let string = value as? String {
            if key == "MTL_HUD_ALIGNMENT", let number = Int(string) {
                return legacyAlignmentName(number) ?? string
            }
            return string
        }
        guard let number = value as? NSNumber else { return nil }
        if key == "MTL_HUD_ALIGNMENT", let alignment = legacyAlignmentName(number.intValue) {
            return alignment
        }
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "1" : "0"
        }
        return number.stringValue
    }

    private static func legacyAlignmentName(_ value: Int) -> String? {
        [
            10: "topleft", 11: "topcenter", 12: "topright",
            14: "centerleft", 15: "centered", 16: "centerright",
            18: "bottomleft", 19: "bottomcenter", 20: "bottomright"
        ][value]
    }

    public func wineProcesses(crossOverOnly: Bool = false) async throws -> [(pid: Int32, command: String)] {
        let result = try await runner.run("/bin/ps", arguments: ["-axo", "pid=,ppid=,command="])
        return Self.matchingProcesses(Self.parseProcessTable(result.outputString), crossOverOnly: crossOverOnly)
            .map { ($0.pid, $0.command) }
    }

    public func runningProcesses() async throws -> [SystemProcess] {
        let result = try await runner.run("/bin/ps", arguments: ["-axo", "pid=,ppid=,%cpu=,command="])
        return Self.sortedRunningProcesses(Self.parseProcessTable(result.outputString)
            .filter { $0.pid > 1 && !$0.command.lowercased().contains("macgametoolbox") }
        )
    }

    public func increasePriority(crossOverOnly: Bool = true) async throws -> Int {
        let processes = try await wineProcesses(crossOverOnly: crossOverOnly)
        guard !processes.isEmpty else { throw ToolboxError.commandFailed(coreText("未检测到 Wine 进程", "No Wine process found")) }
        try await privileged.perform(.renice(processes.map(\.pid), -20))
        return processes.count
    }

    public func beginHoYoLaunch() async throws {
        try await privileged.perform(.addHoYoHosts)
    }

    public func finishHoYoLaunch() async throws {
        try await privileged.perform(.removeHoYoHosts)
    }

    public func cleanStaleHoYoEntries() async {
        try? await privileged.perform(.removeHoYoHosts)
    }

    public static func parseProcessTable(_ text: String) -> [SystemProcess] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 3, let pid = Int32(fields[0]), let parentPID = Int32(fields[1]) else { return nil }
            guard fields.count == 4 else {
                return SystemProcess(pid: pid, parentPID: parentPID, command: String(fields[2]))
            }
            let cpuUsage = Double(fields[2]).flatMap { $0.isFinite ? $0 : nil } ?? 0
            return SystemProcess(pid: pid, parentPID: parentPID, command: String(fields[3]), cpuUsage: cpuUsage)
        }
    }

    static func sortedRunningProcesses(_ processes: [SystemProcess]) -> [SystemProcess] {
        processes.sorted {
            if $0.cpuUsage != $1.cpuUsage { return $0.cpuUsage > $1.cpuUsage }
            let commandOrder = $0.command.localizedStandardCompare($1.command)
            if commandOrder != .orderedSame { return commandOrder == .orderedAscending }
            return $0.pid < $1.pid
        }
    }

    public static func matchingFavoriteProcesses(_ processes: [SystemProcess], favoriteNames: [String]) -> [SystemProcess] {
        let names = Set(favoriteNames)
        return processes.filter { names.contains($0.displayName) }
    }

    public static func matchingProcesses(_ processes: [SystemProcess], crossOverOnly: Bool) -> [SystemProcess] {
        let roots = Set(processes.filter {
            let value = $0.command.lowercased()
            return value.contains("crossover.app/contents/macos/crossover") || value.hasSuffix("/crossover")
        }.map(\.pid))
        var descendants = roots
        var addedDescendant = true
        while addedDescendant {
            addedDescendant = false
            for process in processes where descendants.contains(process.parentPID) && !descendants.contains(process.pid) {
                descendants.insert(process.pid)
                addedDescendant = true
            }
        }
        return processes.filter { process in
            let value = process.command.lowercased()
            guard !value.contains("macgametoolbox") else { return false }
            let isWine = value.contains("wine") || value.contains("wineserver") || value.contains("winedevice")
            if !crossOverOnly { return isWine }
            // Wine services commonly detach from CrossOver and are re-parented to
            // launchd. If the CrossOver root has exited, retain Wine detection.
            return roots.isEmpty ? isWine : descendants.contains(process.pid) || (value.contains("crossover") && isWine)
        }
    }
}

public actor HostnameService {
    private let runner: any CommandRunning
    private let privileged: any PrivilegedOperating

    public init(runner: any CommandRunning = ProcessCommandRunner(), privileged: any PrivilegedOperating) {
        self.runner = runner
        self.privileged = privileged
    }

    public func current() async throws -> HostnameBackup {
        let computer = try await read("ComputerName")
        let local = (try? await read("LocalHostName")) ?? Self.slug(computer)
        let host = (try? await read("HostName")) ?? local
        return HostnameBackup(computerName: computer, hostName: host, localHostName: local)
    }

    public func setSteamDeck() async throws {
        try await privileged.perform(.setHostnames(HostnameBackup(computerName: "steamdeck", hostName: "steamdeck", localHostName: "steamdeck")))
    }

    public func restore(_ backup: HostnameBackup) async throws {
        try await privileged.perform(.setHostnames(backup))
    }

    private func read(_ key: String) async throws -> String {
        try await runner.run("/usr/sbin/scutil", arguments: ["--get", key]).outputString
    }

    private static func slug(_ value: String) -> String {
        let mapped = value.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "-" }
        return String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
    }
}
