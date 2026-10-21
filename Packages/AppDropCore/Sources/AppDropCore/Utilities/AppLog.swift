import Foundation

/// Very small diagnostic logger: everything goes to stderr (captured by
/// launchd/scripts) and optionally to an append-only file inside the shared
/// local storage directory so integration tests can inspect background runs.
public enum AppLog {
    private static let maximumLogSize = 1_048_576

    public static func info(_ message: String, fileURL: URL? = nil) {
        write("INFO  \(message)", to: fileURL)
    }

    public static func error(_ message: String, fileURL: URL? = nil) {
        write("ERROR \(message)", to: fileURL)
    }

    private static func write(_ message: String, to fileURL: URL?) {
        let line = "\(Self.timestamp()) \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        guard let fileURL else { return }
        try? append(line, to: fileURL)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func append(_ line: String, to fileURL: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = try? manager.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
           size > maximumLogSize {
            try? manager.removeItem(at: fileURL)
        }
        if !manager.fileExists(atPath: fileURL.path) {
            manager.createFile(atPath: fileURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
    }
}
