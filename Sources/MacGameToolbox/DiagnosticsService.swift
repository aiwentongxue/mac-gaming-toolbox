import Foundation
#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif

actor DiagnosticsService {
    private let runner: any CommandRunning

    init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    func collect(taskStatus: TaskStatus, helperStatus: String, configuration: AppConfiguration) async -> String {
        var sections: [(String, String)] = []
        sections.append(("Report", "Generated: \(ISO8601DateFormatter().string(from: Date()))\nApp: Mac Game Toolbox 3.0.0\nHelper: \(helperStatus)\nTask phase: \(taskStatus.phase.rawValue)\nTask message: \(taskStatus.message)"))
        let restorableMounts = configuration.restorableDiskMounts.map {
            "\($0.diskIdentifier) [\($0.volumeUUID ?? "no UUID")] -> \($0.mountPath ?? "no path")"
        }.joined(separator: "\n")
        sections.append(("Configuration Summary", "Default paths: \(configuration.defaultPaths.count)\nDisk presets: \(configuration.diskPresets.count)\nAutomatic restore enabled: \(configuration.automaticallyRestoreMountsOnLaunch)\nRestorable mounts:\n\(restorableMounts.isEmpty ? "(none)" : restorableMounts)\nMetalHUD recent apps: \(configuration.recentMetalHUDApps.count)\nHoYo wait: \(configuration.hoYoWaitSeconds)s\nSensitive cache exclusion: \(configuration.excludesSensitiveCacheFiles)\nLegacy imported: \(configuration.didImportLegacyConfiguration)\nHostname backup present: \(configuration.hostnameBackup != nil)"))
        sections.append(("Task Log", taskStatus.log.isEmpty ? "(empty)" : taskStatus.log.joined(separator: "\n")))
        let appLog = (try? String(contentsOf: DiagnosticFileLogger.logURL, encoding: .utf8)) ?? "(not available)"
        sections.append(("Persistent App Log", appLog))
        sections.append(("macOS", await command("/usr/bin/sw_vers", [])))
        sections.append(("Kernel and Architecture", await command("/usr/bin/uname", ["-a"])))
        sections.append(("Hostnames", await hostnames()))
        sections.append(("diskutil list -plist", await command("/usr/sbin/diskutil", ["list", "-plist"])))
        sections.append(("CrossOver and Wine Processes", await relevantProcesses()))
        sections.append(("Unified Log Hint", "Run this in Terminal if deeper system logs are needed:\nlog show --last 10m --style compact --predicate 'subsystem == \"com.iven.macgametoolbox\"'"))
        return sections.map { "===== \($0.0) =====\n\($0.1)" }.joined(separator: "\n\n") + "\n"
    }

    private func hostnames() async -> String {
        var lines: [String] = []
        for key in ["ComputerName", "HostName", "LocalHostName"] {
            lines.append("\(key): \(await command("/usr/sbin/scutil", ["--get", key]))")
        }
        return lines.joined(separator: "\n")
    }

    private func relevantProcesses() async -> String {
        guard let result = try? await runner.run("/bin/ps", arguments: ["-axo", "pid=,ppid=,command="]) else { return "Unable to read process list" }
        let lines = result.outputString.components(separatedBy: .newlines).filter {
            let value = $0.lowercased()
            return value.contains("crossover") || value.contains("wine")
        }
        return lines.isEmpty ? "(none)" : lines.joined(separator: "\n")
    }

    private func command(_ executable: String, _ arguments: [String]) async -> String {
        do {
            let result = try await runner.run(executable, arguments: arguments)
            return result.outputString.isEmpty ? "(empty)" : result.outputString
        } catch {
            return "ERROR: \(error.localizedDescription)"
        }
    }
}
