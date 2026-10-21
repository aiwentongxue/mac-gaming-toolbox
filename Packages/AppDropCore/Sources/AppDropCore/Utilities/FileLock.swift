import Darwin
import Foundation

/// How to behave when the cross-process refresh lock is already held.
public enum FileLockMode: Sendable, Equatable {
    /// Fail immediately when the lock is busy.
    case skipIfBusy
    /// Retry until `timeout` seconds have passed.
    case wait(timeout: TimeInterval)
}

/// Raised when the lock could not be acquired.
public struct FileLockBusyError: Error, LocalizedError {
    public var url: URL
    public var errorDescription: String? {
        "Another AppDrop refresh is already running (lock: \(url.path))."
    }
}

/// Advisory `flock`-based lock used to serialize refresh cycles between the main
/// app and the background helper.
public final class FileLock: @unchecked Sendable {
    public final class Handle: @unchecked Sendable {
        fileprivate let descriptor: Int32

        fileprivate init(descriptor: Int32) {
            self.descriptor = descriptor
        }

        deinit {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }

        public func release() {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
    }

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Acquires the lock. Throws `FileLockBusyError` when the lock is held and
    /// the mode does not allow waiting long enough.
    public func acquire(_ mode: FileLockMode) throws -> Handle {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            throw FileLockBusyError(url: url)
        }

        let deadline: Date?
        switch mode {
        case .skipIfBusy:
            deadline = nil
        case .wait(let timeout):
            deadline = Date().addingTimeInterval(timeout)
        }

        while true {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                return Handle(descriptor: descriptor)
            }
            guard let deadline, Date() < deadline else {
                close(descriptor)
                throw FileLockBusyError(url: url)
            }
            usleep(150_000)
        }
    }
}
