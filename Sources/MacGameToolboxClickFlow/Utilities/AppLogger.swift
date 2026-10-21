import OSLog

enum AppLogger {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.iven.macgametoolbox.clickflow"
    static let automation = Logger(subsystem: subsystem, category: "Automation")
    static let recording = Logger(subsystem: subsystem, category: "Recording")
    static let hotkeys = Logger(subsystem: subsystem, category: "Hotkeys")
    static let permissions = Logger(subsystem: subsystem, category: "Permissions")
    static let storage = Logger(subsystem: subsystem, category: "Storage")
}
