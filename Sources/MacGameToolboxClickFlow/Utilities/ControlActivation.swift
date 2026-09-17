import AppKit

@MainActor
enum ControlActivation {
    static var isMouseTriggered: Bool {
        guard let type = NSApplication.shared.currentEvent?.type else { return false }
        switch type {
        case .leftMouseDown, .leftMouseUp,
             .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp:
            return true
        default:
            return false
        }
    }
}
