import Foundation
#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif
import OSLog
import Security

public final class PrivilegedHelperClient: PrivilegedOperating, @unchecked Sendable {
    static let serviceName = "com.iven.macgametoolbox.helper.v10"
    static let installedHelperPath = "/Library/PrivilegedHelperTools/com.iven.macgametoolbox.helper.v10"
    private let coordinator = PrivilegedHelperCoordinator()

    public init() {}

    public func diagnosticStatus() -> String {
        let installed = FileManager.default.fileExists(atPath: Self.installedHelperPath)
        let signing = Self.teamIdentifier() == nil ? "development signing" : "Developer ID signing"
        return "persistent helper v10: \(installed ? "installed" : "not installed"), \(signing)"
    }

    public func perform(_ operation: PrivilegedOperation) async throws {
        try await coordinator.perform(Self.request(for: operation))
    }

    public func clearSystemCacheEntries(_ entries: [URL]) async throws -> CacheCleanupResult {
        try await coordinator.clearSystemCacheEntries(entries)
    }

    static func request(for operation: PrivilegedOperation) throws -> PrivilegedRequest {
        switch operation {
        case .healthCheck: return .healthCheck
        case .addHoYoHosts: return .addHoYoHosts
        case .removeHoYoHosts: return .removeHoYoHosts
        case .renice(let pids, let priority):
            if pids.isEmpty || pids.count > 64 || pids.contains(where: { $0 <= 1 }) {
                throw ToolboxError.commandFailed("Invalid process list")
            }
            guard ProcessPriorityLevel(rawValue: priority) != nil else {
                throw ToolboxError.commandFailed("Invalid process priority")
            }
            return .renice(pids, priority)
        case .setHostnames(let names):
            guard InputValidation.computerName(names.computerName),
                  InputValidation.hostname(names.hostName),
                  InputValidation.hostname(names.localHostName) else {
                throw ToolboxError.commandFailed("Invalid hostname")
            }
            return .setHostnames(names)
        case .createDirectory(let path):
            return .createDirectory(try InputValidation.normalizedAbsolutePath(path))
        }
    }

    private static func teamIdentifier() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any] else { return nil }
        return values[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

private actor PrivilegedHelperCoordinator {
    private let logger = Logger(subsystem: "com.iven.macgametoolbox", category: "PrivilegedClient")
    private var installedThisSession = false

    func perform(_ request: PrivilegedRequest) async throws {
        let data = try JSONEncoder().encode(request)
        _ = try await execute(data, cacheCleanup: false)
    }

    func clearSystemCacheEntries(_ entries: [URL]) async throws -> CacheCleanupResult {
        let request = try JSONEncoder().encode(entries)
        guard let data = try await execute(request, cacheCleanup: true) else {
            throw ToolboxError.malformedOutput("Missing cache cleanup result")
        }
        return try JSONDecoder().decode(CacheCleanupResult.self, from: data)
    }

    private func execute(_ data: Data, cacheCleanup: Bool) async throws -> Data? {
        if !FileManager.default.fileExists(atPath: PrivilegedHelperClient.installedHelperPath) {
            try await install()
        }
        // Authorization/healthCheck precedes deletions. Do not replay a destructive
        // request after a connection loss: its outcome may already be committed.
        if cacheCleanup { return try await sendOnce(data, cacheCleanup: true) }
        do {
            return try await sendWithStartupRetries(data)
        } catch let error as ToolboxError {
            guard case .helperUnavailable = error, !installedThisSession else { throw error }
            try await install()
            return try await sendWithStartupRetries(data)
        }
    }

    private func install() async throws {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices/MacGameToolboxPrivilegedHelper")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path),
              Bundle.main.bundleURL.standardizedFileURL.path == "/Applications/Mac 游戏工具箱.app" else {
            throw ToolboxError.helperUnavailable("Install the app in /Applications before enabling privileged features")
        }
        DiagnosticFileLogger.write("Requesting one-time persistent helper installation")
        let script = """
        on run argv
            do shell script quoted form of (item 1 of argv) & " --install " & quoted form of (item 2 of argv) with administrator privileges
        end run
        """
        let result: (Int32, String) = try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script, "--", helperURL.path, Bundle.main.bundleURL.path]
            process.standardOutput = Pipe()
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()
            let message = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (process.terminationStatus, message)
        }.value
        guard result.0 == 0 else {
            if result.1.contains("(-128)") { throw ToolboxError.authorizationCancelled }
            throw ToolboxError.helperUnavailable(result.1.isEmpty ? "Helper installation failed" : result.1)
        }
        installedThisSession = true
        DiagnosticFileLogger.write("Persistent helper installation completed")
    }

    private func sendWithStartupRetries(_ data: Data) async throws -> Data? {
        var lastError: Error = ToolboxError.helperUnavailable("XPC service did not start")
        for attempt in 0..<5 {
            do {
                return try await sendOnce(data)
            } catch let error as ToolboxError {
                lastError = error
                guard case .helperUnavailable = error, attempt < 4 else { throw error }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        throw lastError
    }

    private func sendOnce(_ data: Data, cacheCleanup: Bool = false) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(machServiceName: PrivilegedHelperClient.serviceName, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperXPCProtocol.self)
            let reply = XPCReply(connection: connection, continuation: continuation)
            connection.interruptionHandler = { reply.finish(.failure(ToolboxError.helperUnavailable("XPC connection interrupted"))) }
            connection.invalidationHandler = { reply.finish(.failure(ToolboxError.helperUnavailable("XPC connection invalidated"))) }
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                reply.finish(.failure(ToolboxError.helperUnavailable(error.localizedDescription)))
            }) as? PrivilegedHelperXPCProtocol else {
                reply.finish(.failure(ToolboxError.helperUnavailable("Invalid XPC proxy")))
                return
            }
            if cacheCleanup {
                proxy.clearSystemCacheEntries(request: data) { result, message in
                    if let result { reply.finish(.success(result)) }
                    else { reply.finish(.failure(ToolboxError.commandFailed(message ?? "System cache cleanup failed"))) }
                }
            } else {
                proxy.perform(request: data) { success, message in
                    reply.finish(success
                        ? .success(nil)
                        : .failure(ToolboxError.commandFailed(message ?? "Privileged operation failed")))
                }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + (cacheCleanup ? 300 : 8)) {
                reply.finish(.failure(ToolboxError.helperTimedOut))
            }
        }
    }
}

private final class XPCReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Error>?
    private var connection: NSXPCConnection?

    init(connection: NSXPCConnection, continuation: CheckedContinuation<Data?, Error>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ result: Result<Data?, Error>) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        self.continuation = nil
        let connection = self.connection
        self.connection = nil
        lock.unlock()
        continuation.resume(with: result)
        connection?.interruptionHandler = nil
        connection?.invalidationHandler = nil
        connection?.invalidate()
    }
}
