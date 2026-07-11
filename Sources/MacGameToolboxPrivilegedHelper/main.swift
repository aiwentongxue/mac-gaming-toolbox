import Darwin
import Foundation
#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif
import Security
import OSLog

private let serviceName = "com.iven.macgametoolbox.helper.v8"
private let installedHelperPath = "/Library/PrivilegedHelperTools/com.iven.macgametoolbox.helper.v8"
private let installedPlistPath = "/Library/LaunchDaemons/com.iven.macgametoolbox.helper.v8.plist"
private let requirementPath = "/Library/PrivilegedHelperTools/com.iven.macgametoolbox.helper.v8.requirement"
private let expectedAppPath = "/Applications/Mac 游戏工具箱.app"
private let hoyoDomains = GamingService.hoyoDomains
private let logger = Logger(subsystem: "com.iven.macgametoolbox", category: "PrivilegedHelper")

enum HelperError: LocalizedError {
    case notRoot, invalidClient, invalidArguments, invalidPath, invalidProcess, commandFailed(String)
    var errorDescription: String? {
        switch self {
        case .notRoot: "Helper is not running as root"
        case .invalidClient: "Untrusted XPC client"
        case .invalidArguments: "Invalid privileged operation arguments"
        case .invalidPath: "Invalid directory path"
        case .invalidProcess: "Invalid or missing process"
        case .commandFailed(let message): message
        }
    }
}

final class HelperService: NSObject, PrivilegedHelperXPCProtocol {
    func perform(request: Data, withReply reply: @escaping (Bool, String?) -> Void) {
        do {
            guard geteuid() == 0 else { throw HelperError.notRoot }
            let request = try JSONDecoder().decode(PrivilegedRequest.self, from: request)
            logger.info("Received request: \(String(describing: request), privacy: .public)")
            try performValidated(request)
            reply(true, nil)
        } catch {
            logger.error("Request failed: \(error.localizedDescription, privacy: .public)")
            reply(false, error.localizedDescription)
        }
    }

    private func performValidated(_ request: PrivilegedRequest) throws {
        switch request {
        case .healthCheck: break
        case .addHoYoHosts: try rewriteHosts(addBlock: true)
        case .removeHoYoHosts: try rewriteHosts(addBlock: false)
        case .renice(let pids):
            guard !pids.isEmpty, pids.count <= 64 else { throw HelperError.invalidArguments }
            var updatedCount = 0
            for pid in pids {
                guard pid > 1 else { throw HelperError.invalidArguments }
                // Process scans are inherently racy; a short-lived Wine child may
                // disappear before the helper handles the complete PID batch.
                guard kill(pid, 0) == 0 else { continue }
                if setpriority(PRIO_PROCESS, UInt32(pid), -10) == 0 {
                    updatedCount += 1
                } else if errno != ESRCH {
                    throw HelperError.commandFailed("setpriority failed for \(pid): errno \(errno)")
                }
            }
            guard updatedCount > 0 else { throw HelperError.invalidProcess }
        case .clearSystemCaches:
            for path in ["/Library/Caches", "/Library/Logs", "/private/var/log"] { try removeVisibleContents(path) }
        case .setHostnames(let names):
            guard InputValidation.computerName(names.computerName), InputValidation.hostname(names.hostName), InputValidation.hostname(names.localHostName) else { throw HelperError.invalidArguments }
            try run("/usr/sbin/scutil", ["--set", "ComputerName", names.computerName])
            try run("/usr/sbin/scutil", ["--set", "HostName", names.hostName])
            try run("/usr/sbin/scutil", ["--set", "LocalHostName", names.localHostName])
            try run("/usr/bin/dscacheutil", ["-flushcache"])
        case .createDirectory(let value):
            let path = try validatedPath(value)
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = HelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard trustedClient(connection) else {
            logger.error("Rejected XPC client pid \(connection.processIdentifier)")
            return false
        }
        logger.info("Accepted XPC client pid \(connection.processIdentifier)")
        connection.exportedInterface = NSXPCInterface(with: PrivilegedHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }

    private func trustedClient(_ connection: NSXPCConnection) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: connection.processIdentifier] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }

        let appURL = URL(fileURLWithPath: expectedAppPath)
        guard appURL.pathExtension == "app",
              let appBundle = Bundle(url: appURL),
              let expectedExecutable = appBundle.executableURL?.standardizedFileURL else { return false }
        var clientURL: CFURL?
        guard SecCodeCopyPath(staticCode, [], &clientURL) == errSecSuccess,
              let clientPath = (clientURL as URL?)?.standardizedFileURL,
              clientPath == appURL.standardizedFileURL || clientPath == expectedExecutable else { return false }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              dictionary[kSecCodeInfoIdentifier as String] as? String == "com.iven.macgametoolbox" else { return false }

        guard let requirementText = try? String(contentsOfFile: requirementPath, encoding: .utf8),
              !requirementText.isEmpty else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess
    }
}

func containingAppURL() -> URL? {
    var selfCode: SecCode?
    var staticCode: SecStaticCode?
    var executableURL: CFURL?
    guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
          SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess, let staticCode,
          SecCodeCopyPath(staticCode, [], &executableURL) == errSecSuccess,
          var url = executableURL as URL? else { return nil }
    for _ in 0..<4 { url.deleteLastPathComponent() }
    return url.standardizedFileURL
}

func installPersistentHelper(for appPath: String) throws {
    guard URL(fileURLWithPath: appPath).standardizedFileURL.path == expectedAppPath else { throw HelperError.invalidPath }
    let appURL = URL(fileURLWithPath: expectedAppPath)
    var appCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &appCode) == errSecSuccess, let appCode,
          SecStaticCodeCheckValidity(appCode, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
        throw HelperError.invalidClient
    }
    var information: CFDictionary?
    guard SecCodeCopySigningInformation(appCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
          let dictionary = information as? [String: Any],
          dictionary[kSecCodeInfoIdentifier as String] as? String == "com.iven.macgametoolbox" else {
        throw HelperError.invalidClient
    }
    var requirement: SecRequirement?
    var requirementText: CFString?
    guard SecCodeCopyDesignatedRequirement(appCode, [], &requirement) == errSecSuccess, let requirement,
          SecRequirementCopyString(requirement, [], &requirementText) == errSecSuccess,
          let requirementText else { throw HelperError.invalidClient }

    let fileManager = FileManager.default
    try fileManager.createDirectory(atPath: "/Library/PrivilegedHelperTools", withIntermediateDirectories: true)
    _ = try? run("/bin/launchctl", ["bootout", "system/\(serviceName)"])

    guard let sourceURL = selfExecutableURL() else { throw HelperError.invalidPath }
    if fileManager.fileExists(atPath: installedHelperPath) { try fileManager.removeItem(atPath: installedHelperPath) }
    try fileManager.copyItem(at: sourceURL, to: URL(fileURLWithPath: installedHelperPath))
    try fileManager.setAttributes([.posixPermissions: 0o755, .ownerAccountID: 0, .groupOwnerAccountID: 0], ofItemAtPath: installedHelperPath)

    try (requirementText as String).write(toFile: requirementPath, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o600, .ownerAccountID: 0, .groupOwnerAccountID: 0], ofItemAtPath: requirementPath)

    let plist: [String: Any] = [
        "Label": serviceName,
        "ProgramArguments": [installedHelperPath],
        "MachServices": [serviceName: true],
        "RunAtLoad": true
    ]
    let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try plistData.write(to: URL(fileURLWithPath: installedPlistPath), options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o644, .ownerAccountID: 0, .groupOwnerAccountID: 0], ofItemAtPath: installedPlistPath)
    try run("/bin/launchctl", ["bootstrap", "system", installedPlistPath])
}

func selfExecutableURL() -> URL? {
    var selfCode: SecCode?
    var staticCode: SecStaticCode?
    var executableURL: CFURL?
    guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
          SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess, let staticCode,
          SecCodeCopyPath(staticCode, [], &executableURL) == errSecSuccess else { return nil }
    return executableURL as URL?
}

func validatedPath(_ value: String) throws -> String {
    let path = URL(fileURLWithPath: value).standardizedFileURL.path
    guard value.hasPrefix("/"), path != "/", !path.contains("\0") else { throw HelperError.invalidPath }
    return path
}

func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw HelperError.commandFailed(String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}

func rewriteHosts(addBlock: Bool) throws {
    let url = URL(fileURLWithPath: "/etc/hosts")
    let original = try String(contentsOf: url, encoding: .utf8)
    let updated = HostsFileEditor.replacingManagedBlock(in: original, domains: hoyoDomains, enabled: addBlock)
    let temporary = URL(fileURLWithPath: "/etc/.mac-game-toolbox-hosts-\(getpid())")
    try updated.write(to: temporary, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o644, .ownerAccountID: 0, .groupOwnerAccountID: 0], ofItemAtPath: temporary.path)
    _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    try run("/usr/bin/dscacheutil", ["-flushcache"])
}

func removeVisibleContents(_ path: String) throws {
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else { return }
    for entry in entries where !entry.hasPrefix(".") {
        try FileManager.default.removeItem(atPath: URL(fileURLWithPath: path).appendingPathComponent(entry).path)
    }
}

guard geteuid() == 0 else { fatalError(HelperError.notRoot.localizedDescription) }
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--install" {
    do {
        try installPersistentHelper(for: CommandLine.arguments[2])
        exit(EXIT_SUCCESS)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}
let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: serviceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
