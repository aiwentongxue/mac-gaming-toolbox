import Foundation
import ServiceManagement
import AppDropCore
import SwiftUI

/// Registers and monitors the embedded background helper through SMAppService.
@MainActor
final class BackendManager: ObservableObject {
    @Published private(set) var state: BackendState = .unknown
    @Published private(set) var lastError: String?

    private var service: SMAppService {
        SMAppService.agent(plistName: SharedConstants.helperAgentPlistName)
    }

    var helperExecutableURL: URL {
        Bundle.main.bundleURL.appendingPathComponent(SharedConstants.helperExecutableRelativePath)
    }

    func refreshStatus() {
        state = BackendState(service.status)
    }

    func enable() throws {
        lastError = nil
        do {
            try service.register()
            refreshStatus()
        } catch {
            lastError = error.localizedDescription
            refreshStatus()
            throw error
        }
    }

    func disable() throws {
        lastError = nil
        do {
            try service.unregister()
            refreshStatus()
        } catch {
            lastError = error.localizedDescription
            refreshStatus()
            throw error
        }
    }

    /// Runs the helper in warm-up mode so the user sees the helper's own
    /// notification permission prompt during onboarding.
    @discardableResult
    func warmUpHelperNotifications(timeout: TimeInterval = 180) async -> String? {
        await runHelper(arguments: ["--request-notification-authorization"], timeout: timeout)
    }

    /// Convenience used by diagnostics and future UI surfaces.
    @discardableResult
    func runHelperOnce(timeout: TimeInterval = 120) async -> String? {
        await runHelper(arguments: ["--run-now"], timeout: timeout)
    }

    private func runHelper(arguments: [String], timeout: TimeInterval) async -> String? {
        let executable = helperExecutableURL
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            lastError = "Helper executable missing at \(executable.path)"
            return nil
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return await withCheckedContinuation { continuation in
            let hasResumed = LockedFlag()
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)
                if hasResumed.setIfUnset() {
                    continuation.resume(returning: output)
                }
            }
            do {
                try process.run()
            } catch {
                lastError = error.localizedDescription
                if hasResumed.setIfUnset() {
                    continuation.resume(returning: nil)
                }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }
}

/// Small helper that guarantees a continuation resumes exactly once.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func setIfUnset() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !value else { return false }
        value = true
        return true
    }
}
