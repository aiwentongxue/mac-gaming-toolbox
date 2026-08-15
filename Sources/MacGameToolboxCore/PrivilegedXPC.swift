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

@objc(PrivilegedHelperXPCProtocol) public protocol PrivilegedHelperXPCProtocol {
    func perform(request: Data, withReply reply: @escaping (Bool, String?) -> Void)
}
