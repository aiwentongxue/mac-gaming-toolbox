import Foundation

public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: Data
    public let standardError: Data

    public init(exitCode: Int32, standardOutput: Data, standardError: Data) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var outputString: String {
        String(decoding: standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var errorString: String {
        String(decoding: standardError, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = error
            do {
                try process.run()
            } catch {
                throw ToolboxError.commandFailed(error.localizedDescription)
            }
            // Drain both pipes while the child is running. Waiting first can
            // deadlock as soon as either pipe exceeds the kernel pipe buffer.
            let outputCollector = PipeDataCollector()
            let errorCollector = PipeDataCollector()
            let readers = DispatchGroup()
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                outputCollector.store(output.fileHandleForReading.readDataToEndOfFile())
                readers.leave()
            }
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                errorCollector.store(error.fileHandleForReading.readDataToEndOfFile())
                readers.leave()
            }
            process.waitUntilExit()
            await withCheckedContinuation { continuation in
                readers.notify(queue: .global(qos: .utility)) { continuation.resume() }
            }
            let result = CommandResult(
                exitCode: process.terminationStatus,
                standardOutput: outputCollector.data,
                standardError: errorCollector.data
            )
            guard result.exitCode == 0 else {
                throw ToolboxError.commandFailed(result.errorString.isEmpty ? "Command failed (\(result.exitCode))" : result.errorString)
            }
            return result
        }.value
    }
}

private final class PipeDataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func store(_ data: Data) {
        lock.lock()
        storage = data
        lock.unlock()
    }
}

public enum InputValidation {
    public static func diskIdentifier(_ value: String) -> Bool {
        value.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil
    }

    public static func normalizedAbsolutePath(_ value: String, home: String = NSHomeDirectory()) throws -> String {
        var path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("~/") { path = home + String(path.dropFirst()) }
        path = URL(fileURLWithPath: path).standardizedFileURL.path
        guard path.hasPrefix("/"), path != "/", !path.contains("\0") else {
            throw ToolboxError.invalidPath(value)
        }
        return path
    }

    public static func hostname(_ value: String) -> Bool {
        value.count <= 63 && value.range(of: #"^[A-Za-z0-9][A-Za-z0-9.-]*$"#, options: .regularExpression) != nil
    }

    public static func computerName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 255 && !trimmed.contains("\0") && !trimmed.contains("\n")
    }
}
