import Foundation

public enum PrivilegedRequest: Codable, Equatable, Sendable {
    case healthCheck
    case addHoYoHosts
    case removeHoYoHosts
    case renice([Int32], Int32)
    case setHostnames(HostnameBackup)
    case createDirectory(String)
}

@objc(PrivilegedHelperXPCProtocol) public protocol PrivilegedHelperXPCProtocol {
    func perform(request: Data, withReply reply: @escaping (Bool, String?) -> Void)
    func clearSystemCacheEntries(request: Data, withReply reply: @escaping (Data?, String?) -> Void)
}
