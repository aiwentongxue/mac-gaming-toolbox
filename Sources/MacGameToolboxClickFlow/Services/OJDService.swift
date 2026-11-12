import AppKit
import CryptoKit
import Foundation

struct OJDError: LocalizedError, Sendable {
    var detail: String
    var errorDescription: String? { detail }
    static func message(_ key: String) -> OJDError { OJDError(detail: cf(key)) }
}

/// Shell-free process arguments and bounded execution for dependency inspection.
enum OJDCommand {
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 20, environment: [String: String]? = nil) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        // Files avoid deadlocking when a child fills stderr/stdout before exiting.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let out = root.appendingPathComponent("stdout"), err = root.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        FileManager.default.createFile(atPath: err.path, contents: nil)
        let output = try FileHandle(forWritingTo: out), errors = try FileHandle(forWritingTo: err)
        defer { try? output.close(); try? errors.close() }
        process.standardOutput = output; process.standardError = errors
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            let grace = Date().addingTimeInterval(1)
            while process.isRunning, Date() < grace { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw OJDError.message("ojd.error.timeout")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = (try? Data(contentsOf: err)) ?? Data()
            throw OJDError(detail: String(decoding: data.suffix(4096), as: UTF8.self))
        }
        return try Data(contentsOf: out)
    }
}

struct OJDPermissionStatus: Decodable, Sendable {
    var inputRead: String
    var inputInject: String
    static let unknown = OJDPermissionStatus(inputRead: "Unknown", inputInject: "Unknown")

    static func decodeStatus(_ data: Data) throws -> OJDPermissionStatus {
        struct Status: Decodable { var permissions: OJDPermissionStatus }
        return try JSONDecoder().decode(Status.self, from: data).permissions
    }
}

/// The official bundle stays outside ClickFlow.app so updates do not alter its seal.
struct OJDPaths: Sendable {
    var supportURL: URL
    var legacyAppURL: URL
    static let current = OJDPaths(
        supportURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacGameToolbox/ClickFlow/OJD", isDirectory: true),
        legacyAppURL: URL(fileURLWithPath: "/Applications/OpenJoystickDriver.app"))
    var appURL: URL { supportURL.appendingPathComponent("OpenJoystickDriver.app", isDirectory: true) }
    var cliURL: URL { supportURL.appendingPathComponent("ojd") }
    func executable(in app: URL) -> URL { app.appendingPathComponent("Contents/MacOS/OpenJoystickDriver") }
}

enum OJDInstallResult: Sendable { case installed, reused, migrated }

struct OJDRunningInstance: Sendable, Equatable {
    var pid: pid_t
    var executableURL: URL
}

struct OJDRuntime: Sendable {
    var instances: @Sendable () throws -> [OJDRunningInstance]
    var terminate: @Sendable (OJDRunningInstance) -> Bool
    static let live = OJDRuntime(instances: {
        try NSRunningApplication.runningApplications(withBundleIdentifier: "com.openjoystickdriver").map { app in
            var buffer = [CChar](repeating: 0, count: 4096)
            guard proc_pidpath(app.processIdentifier, &buffer, UInt32(buffer.count)) > 0 else {
                throw OJDError.message("ojd.error.processPath")
            }
            return OJDRunningInstance(pid: app.processIdentifier,
                executableURL: URL(fileURLWithPath: String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)))
        }
    }, terminate: { instance in
        // Recheck identity immediately before a normal quit; never terminate a reused PID.
        guard let app = NSRunningApplication(processIdentifier: instance.pid),
              app.executableURL?.resolvingSymlinksInPath() == instance.executableURL.resolvingSymlinksInPath() else { return false }
        return app.terminate()
    })
}

struct OJDInstallOperations: Sendable {
    var verify: @Sendable (URL) throws -> Void
    var copy: @Sendable (URL, URL) throws -> Void
    var trash: @Sendable (URL) throws -> Void
    static let live = OJDInstallOperations(verify: OJDService.verifyOfficialBundle, copy: { source, target in
        _ = try OJDCommand.run("/usr/bin/ditto", ["--norsrc", "--noextattr", source.path, target.path], timeout: 60)
    }, trash: { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    })
}

struct OJDService: Sendable {
    static let version = "0.6.0-alpha.1"
    static let sha256 = "d2b771ffe4382b7bfd218932c7003227216d334a14154e95976c4f114b1c2056"
    static var appURL: URL { OJDPaths.current.appURL }
    static var supportURL: URL { OJDPaths.current.supportURL }
    static let downloadURL = URL(string: "https://github.com/xsyetopz/OpenJoystickDriver/releases/download/0.6.0-alpha.1/OpenJoystickDriver-0.6.0-alpha.1-macOS.dmg")!
    var paths: OJDPaths = .current
    var operations: OJDInstallOperations = .live
    var runtime: OJDRuntime = .live
    // The official CLI otherwise forwards an external `ojd` symlink to /Applications.
    static var cliEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["OJD_RUN_REPOSITORY_CLI"] = "1"
        return environment
    }
    var command: @Sendable (String, [String], TimeInterval) throws -> Data = {
        try OJDCommand.run($0, $1, timeout: $2, environment: OJDService.cliEnvironment)
    }

    func verify(app: URL? = nil) throws { try operations.verify(app ?? paths.appURL) }

    static func verifyOfficialBundle(_ app: URL) throws {
        guard FileManager.default.fileExists(atPath: app.path) else { throw OJDError.message("ojd.error.missing") }
        // Do not adopt symlinks in place of an independently verified full bundle.
        guard (try app.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else {
            throw OJDError.message("ojd.error.version")
        }
        let info = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: info, format: nil) as? [String: Any]
        guard plist?["CFBundleIdentifier"] as? String == "com.openjoystickdriver",
              plist?["CFBundleShortVersionString"] as? String == Self.version else { throw OJDError.message("ojd.error.version") }
        _ = try OJDCommand.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R",
            "=anchor apple generic and identifier \"com.openjoystickdriver\" and certificate leaf[subject.OU] = \"9PQP6CDMQT\"", app.path])
        let data = try OJDCommand.run("/usr/bin/codesign", ["-d", "--entitlements", ":-", "--xml", app.path])
        let entitlements = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        guard entitlements?["com.apple.developer.hid.virtual.device"] as? Bool == true else { throw OJDError.message("ojd.error.entitlement") }
        _ = try OJDCommand.run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path], timeout: 45)
    }

    private func itemExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    func cli() throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.supportURL, withIntermediateDirectories: true)
        let target = paths.executable(in: paths.appURL).path
        let link = paths.cliURL
        func checkLink() throws {
            if itemExists(link) {
                let existing = try? fm.destinationOfSymbolicLink(atPath: link.path)
                guard existing == target || existing == paths.executable(in: paths.legacyAppURL).path else {
                    throw OJDError.message("ojd.error.cliConflict")
                }
            }
        }
        try checkLink()
        if (try? fm.destinationOfSymbolicLink(atPath: link.path)) == target { return link }
        let staging = paths.supportURL.appendingPathComponent(".ojd-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try fm.createSymbolicLink(atPath: staging.path, withDestinationPath: target)
        try checkLink()
        let result = itemExists(link) ? rename(staging.path, link.path) : renamex_np(staging.path, link.path, UInt32(RENAME_EXCL))
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return link
    }

    func externalInstances() throws -> [OJDRunningInstance] {
        let expected = paths.executable(in: paths.appURL).resolvingSymlinksInPath()
        return try runtime.instances().filter { $0.executableURL.resolvingSymlinksInPath() != expected }
    }
    func requirePrivateService() throws {
        let instances = try runtime.instances()
        let expected = paths.executable(in: paths.appURL).resolvingSymlinksInPath()
        guard !instances.isEmpty, instances.allSatisfy({ $0.executableURL.resolvingSymlinksInPath() == expected }) else {
            throw OJDError.message("ojd.error.serviceLocation")
        }
    }
    func requireNoExternalService() throws {
        let external = try externalInstances()
        guard external.isEmpty else {
            throw OJDError(detail: cf("ojd.error.externalService") + "\n" + external.map { $0.executableURL.path }.joined(separator: "\n"))
        }
    }

    /// Called only by the explicit switch action. Cancellation never quits a service.
    func switchService(confirmed: Bool, timeout: TimeInterval = 8) throws {
        guard confirmed else { throw CancellationError() }
        try Task.checkCancellation()
        try verify()
        let external = try externalInstances()
        for instance in external {
            guard instance.executableURL.resolvingSymlinksInPath() == paths.executable(in: paths.legacyAppURL).resolvingSymlinksInPath() else {
                throw OJDError.message("ojd.error.otherService")
            }
        }
        for instance in external {
            guard runtime.terminate(instance) else { throw OJDError.message("ojd.error.quit") }
        }
        let deadline = Date().addingTimeInterval(timeout)
        while !(try externalInstances()).isEmpty {
            try Task.checkCancellation()
            guard Date() < deadline else { throw OJDError.message("ojd.error.quit") }
            Thread.sleep(forTimeInterval: 0.05)
        }
        _ = try start()
    }

    func start() throws -> URL {
        try verify()
        try requireNoExternalService()
        let cli = try cli()
        _ = try command(cli.path, ["--json", "--no-input", "--no-color", "--timeout", "8", "service", "start"], 12)
        try requirePrivateService()
        let data = try status(cli: cli)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let service = json["service"] as? [String: Any], service["state"] as? String == "Running",
              service["version"] as? String == Self.version else { throw OJDError.message("ojd.error.notRunning") }
        let permissions = try OJDPermissionStatus.decodeStatus(data)
        guard permissions.inputRead == "Granted", permissions.inputInject == "Granted" else {
            throw OJDError.message("ojd.error.permissions")
        }
        return cli
    }

    func status(cli: URL? = nil) throws -> Data {
        try requireNoExternalService()
        let executable: URL
        if let cli { executable = cli }
        else { try verify(); executable = try self.cli() }
        return try command(executable.path, ["--json", "--no-input", "--no-color", "--timeout", "2", "status"], 5)
    }

    @discardableResult
    func install(from source: URL? = nil) async throws -> OJDInstallResult {
        if itemExists(paths.appURL) { try verify(); _ = try cli(); return .reused }
        if let source { try installBundle(from: source); return .installed }
        if itemExists(paths.legacyAppURL) {
            do { try installBundle(from: paths.legacyAppURL) }
            catch { throw OJDError(detail: cf("ojd.error.legacyPreserved") + "\n" + error.localizedDescription) }
            return .migrated
        }
        let (download, response) = try await URLSession.shared.download(from: Self.downloadURL)
        defer { try? FileManager.default.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw OJDError.message("ojd.error.download") }
        let data = try Data(contentsOf: download, options: .mappedIfSafe)
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == Self.sha256 else {
            throw OJDError.message("ojd.error.hash")
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ClickFlow-OJD-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let dmg = temporary.appendingPathComponent("OJD.dmg"), mount = temporary.appendingPathComponent("volume")
        try FileManager.default.copyItem(at: download, to: dmg)
        _ = try OJDCommand.run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, dmg.path], timeout: 30)
        defer { _ = try? OJDCommand.run("/usr/bin/hdiutil", ["detach", mount.path], timeout: 30) }
        try installBundle(from: mount.appendingPathComponent("OpenJoystickDriver.app"))
        return .installed
    }

    private func installBundle(from source: URL) throws {
        let fm = FileManager.default
        try verify(app: source)
        try fm.createDirectory(at: paths.supportURL, withIntermediateDirectories: true)
        let staging = paths.supportURL.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let app = staging.appendingPathComponent("OpenJoystickDriver.app", isDirectory: true)
        try operations.copy(source, app)
        try verify(app: app)
        // Same-volume, atomic and exclusive: a concurrent installation is never overwritten.
        guard renamex_np(app.path, paths.appURL.path, UInt32(RENAME_EXCL)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        _ = try cli()
    }

    /// The caller confirms real input acceptance; connection alone is not game verification.
    func trashLegacy(inputConfirmed: Bool) throws {
        guard inputConfirmed else { throw OJDError.message("ojd.error.confirmInput") }
        try verify()
        try requirePrivateService()
        let permissions = try OJDPermissionStatus.decodeStatus(status())
        guard permissions.inputRead == "Granted", permissions.inputInject == "Granted" else { throw OJDError.message("ojd.error.permissions") }
        guard itemExists(paths.legacyAppURL) else { return }
        try verify(app: paths.legacyAppURL)
        try operations.trash(paths.legacyAppURL)
    }
}
