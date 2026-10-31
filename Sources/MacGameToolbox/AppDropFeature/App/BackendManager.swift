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
            lastError = AppStrings.errorDescription(error)
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
            lastError = AppStrings.errorDescription(error)
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

    func notificationStatus() async throws -> NotificationStatusReport {
        let output = await runHelper(arguments: ["--notification-status"], timeout: 15)
        return try decodeNotificationOutput(output, prefix: "APPDROP_NOTIFICATION_STATUS ", as: NotificationStatusReport.self)
    }

    func submitTestNotification() async throws -> NotificationTestResult {
        let output = await runHelper(arguments: ["--test-notification"], timeout: 15)
        return try decodeNotificationOutput(output, prefix: "APPDROP_NOTIFICATION_TEST ", as: NotificationTestResult.self)
    }

    private func decodeNotificationOutput<T: Decodable>(_ output: String?, prefix: String, as type: T.Type) throws -> T {
        guard let line = output?.split(separator: "\n").last(where: { $0.hasPrefix(prefix) }),
              let data = String(line.dropFirst(prefix.count)).data(using: .utf8),
              let value = try? JSONDecoder().decode(type, from: data) else {
            throw NSError(domain: "AppDropHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: lastError ?? AppStrings.string("notifications.helperUnavailable")])
        }
        return value
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
                lastError = AppStrings.errorDescription(error)
                if hasResumed.setIfUnset() {
                    continuation.resume(returning: nil)
                }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
                if hasResumed.setIfUnset() { continuation.resume(returning: nil) }
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
