import Foundation

public enum ProcessPriorityBoost {
    public static let niceValue: Int32 = -20
    public static let taskpolicyExecutable = "/usr/sbin/taskpolicy"

    public static func taskpolicyArguments(pid: Int32) -> [String] {
        ["-B", "-t", "0", "-l", "0", "-p", String(pid)]
    }

    public static func taskpolicyFallbackArguments(pid: Int32) -> [String] {
        ["-t", "0", "-l", "0", "-p", String(pid)]
    }

    public static func isMissingProcess(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("no such process")
    }
}
