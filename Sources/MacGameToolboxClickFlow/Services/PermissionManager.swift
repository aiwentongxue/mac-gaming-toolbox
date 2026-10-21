import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var canPostEvents = false
    @Published private(set) var canListenToEvents = false

    var onPostingPermissionLost: (() -> Void)?

    private var refreshTask: Task<Void, Never>?
    private var postingPermissionMonitorTask: Task<Void, Never>?

    init() {
        refresh()
    }

    func refresh() {
        // Accessibility and CoreGraphics expose separate views of the same TCC
        // capability. On recent macOS releases they do not always update in the
        // same process at the same moment, so either positive result is enough.
        canPostEvents = PermissionDecision.canPostEvents(
            accessibilityTrusted: AXIsProcessTrusted(),
            postEventTrusted: CGPreflightPostEventAccess()
        )
        canListenToEvents = CGPreflightListenEventAccess()
    }

    func requestEventPostingAccess() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        _ = CGRequestPostEventAccess()
        refresh()
        if !canPostEvents {
            openAccessibilitySettings()
        }
        scheduleRefresh()
        AppLogger.permissions.notice("Requested Accessibility event posting permission")
    }

    func requestEventListeningAccess() {
        _ = CGRequestListenEventAccess()
        refresh()
        if !canListenToEvents {
            openInputMonitoringSettings()
        }
        scheduleRefresh()
        AppLogger.permissions.notice("Requested Input Monitoring permission")
    }

    /// CGEvent posting can be revoked in System Settings while automation is
    /// active. Polling only while automation is running makes that transition a
    /// safe stop instead of a silent no-op loop.
    func beginPostingPermissionMonitoring() {
        guard postingPermissionMonitorTask == nil else { return }
        refresh()
        postingPermissionMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self else { return }
                self.refresh()
                if !self.canPostEvents {
                    self.postingPermissionMonitorTask = nil
                    self.onPostingPermissionLost?()
                    return
                }
            }
        }
    }

    func stopPostingPermissionMonitoring() {
        postingPermissionMonitorTask?.cancel()
        postingPermissionMonitorTask = nil
    }

    deinit {
        refreshTask?.cancel()
        postingPermissionMonitorTask?.cancel()
    }

    func openAccessibilitySettings() {
        openPrivacyPane(anchor: "Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openPrivacyPane(anchor: "Privacy_ListenEvent")
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            for delay in [0.5, 1.5, 3.0] {
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                self?.refresh()
            }
        }
    }

    private func openPrivacyPane(anchor: String) {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
        AppLogger.permissions.error("Could not open the System Settings privacy pane")
    }
}

enum PermissionDecision {
    static func canPostEvents(accessibilityTrusted: Bool, postEventTrusted: Bool) -> Bool {
        accessibilityTrusted || postEventTrusted
    }
}
