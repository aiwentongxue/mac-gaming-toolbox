import Foundation

public enum PrivilegedRequest: Codable, Equatable, Sendable {
    case healthCheck
    case addHoYoHosts
    case removeHoYoHosts
    case renice([Int32])
    case clearSystemCaches
    case setHostnames(HostnameBackup)
    case createDirectory(String)
}

public enum HelperRegistrationState: Sendable {
    case enabled, notRegistered, requiresApproval, notFound
}

public enum HelperRegistrationDecision: Equatable, Sendable {
    case connect, register, requestApproval, unavailable
}

public func helperRegistrationDecision(for state: HelperRegistrationState) -> HelperRegistrationDecision {
    switch state {
    case .enabled: .connect
    case .notRegistered: .register
    case .requiresApproval: .requestApproval
    case .notFound: .unavailable
    }
}

@objc(PrivilegedHelperXPCProtocol) public protocol PrivilegedHelperXPCProtocol {
    func perform(request: Data, withReply reply: @escaping (Bool, String?) -> Void)
}
