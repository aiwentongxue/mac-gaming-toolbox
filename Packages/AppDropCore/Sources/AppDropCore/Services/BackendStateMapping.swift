import Foundation
import ServiceManagement

/// Maps `SMAppService.Status` onto the AppDropCore `BackendState` value type so
/// that both the UI and diagnostics/tests share one mapping.
public extension BackendState {
    init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered:
            self = .notRegistered
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .notFound
        @unknown default:
            self = .unknown
        }
    }
}
