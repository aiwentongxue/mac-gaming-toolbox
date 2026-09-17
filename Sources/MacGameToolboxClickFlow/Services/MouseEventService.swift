import CoreGraphics
import Foundation

enum MouseEventServiceError: LocalizedError, Sendable {
    case eventCreationFailed

    var errorDescription: String? {
        cf("error.eventCreation")
    }
}
protocol MouseEventPosting: Sendable {
    func currentPosition() -> ScreenPoint
    func postClick(button: MouseButton, at position: ScreenPoint, clickState: Int64) throws
    func postKeyPress(_ key: KeyboardKey) throws
    func postKey(_ key: KeyboardKey, down: Bool, flags: CGEventFlags) throws
    func postButton(_ button: MouseButton, down: Bool, at position: ScreenPoint, clickState: Int64) throws
    func postMove(to position: ScreenPoint, dragging button: MouseButton?) throws
    func postScroll(deltaX: Int32, deltaY: Int32, at position: ScreenPoint?) throws
}

extension MouseEventPosting {
    func postKey(_ key: KeyboardKey, down: Bool) throws {
        try postKey(key, down: down, flags: [])
    }

    func postButton(_ button: MouseButton, down: Bool, at position: ScreenPoint) throws {
        try postButton(button, down: down, at: position, clickState: 1)
    }
}

struct MouseEventService: MouseEventPosting, Sendable {
    static let syntheticEventMarker: Int64 = 0x434C49434B464C4F

    func currentPosition() -> ScreenPoint {
        guard let event = CGEvent(source: nil) else {
            return ScreenPoint(x: 0, y: 0)
        }
        return ScreenPoint(x: event.location.x, y: event.location.y)
    }

    func postClick(button: MouseButton, at position: ScreenPoint, clickState: Int64 = 1) throws {
        try postButton(button, down: true, at: position, clickState: clickState)
        try postButton(button, down: false, at: position, clickState: clickState)
    }

    func postKey(_ key: KeyboardKey, down: Bool, flags: CGEventFlags = []) throws {
        guard let event = CGEvent(
            keyboardEventSource: makeSource(),
            virtualKey: CGKeyCode(key.keyCode),
            keyDown: down
        ) else {
            throw MouseEventServiceError.eventCreationFailed
        }
        event.flags = flags
        configure(event)
        event.post(tap: .cghidEventTap)
    }

    func postKeyPress(_ key: KeyboardKey) throws {
        try postKey(key, down: true)
        try postKey(key, down: false)
    }

    func postButton(
        _ button: MouseButton,
        down: Bool,
        at position: ScreenPoint,
        clickState: Int64 = 1
    ) throws {
        guard let event = CGEvent(
            mouseEventSource: makeSource(),
            mouseType: eventType(for: button, down: down),
            mouseCursorPosition: CGPoint(x: position.x, y: position.y),
            mouseButton: cgButton(for: button)
        ) else {
            throw MouseEventServiceError.eventCreationFailed
        }
        configure(event, clickState: clickState)
        event.post(tap: .cghidEventTap)
    }

    func postMove(to position: ScreenPoint, dragging button: MouseButton? = nil) throws {
        guard let event = CGEvent(
            mouseEventSource: makeSource(),
            mouseType: moveEventType(for: button),
            mouseCursorPosition: CGPoint(x: position.x, y: position.y),
            mouseButton: button.map(cgButton(for:)) ?? .left
        ) else {
            throw MouseEventServiceError.eventCreationFailed
        }
        configure(event)
        event.post(tap: .cghidEventTap)
    }

    func postScroll(deltaX: Int32, deltaY: Int32, at position: ScreenPoint?) throws {
        guard let event = CGEvent(
            scrollWheelEvent2Source: makeSource(),
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) else {
            throw MouseEventServiceError.eventCreationFailed
        }
        if let position {
            event.location = CGPoint(x: position.x, y: position.y)
        }
        configure(event)
        event.post(tap: .cghidEventTap)
    }

    private func makeSource() -> CGEventSource? {
        CGEventSource(stateID: .hidSystemState)
    }

    private func configure(_ event: CGEvent, clickState: Int64? = nil) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        if let clickState {
            event.setIntegerValueField(.mouseEventClickState, value: clickState)
        }
    }

    private func cgButton(for button: MouseButton) -> CGMouseButton {
        switch button {
        case .left: .left
        case .right: .right
        case .middle: .center
        }
    }

    private func eventType(for button: MouseButton, down: Bool) -> CGEventType {
        switch (button, down) {
        case (.left, true): .leftMouseDown
        case (.left, false): .leftMouseUp
        case (.right, true): .rightMouseDown
        case (.right, false): .rightMouseUp
        case (.middle, true): .otherMouseDown
        case (.middle, false): .otherMouseUp
        }
    }

    private func moveEventType(for button: MouseButton?) -> CGEventType {
        switch button {
        case .left: .leftMouseDragged
        case .right: .rightMouseDragged
        case .middle: .otherMouseDragged
        case nil: .mouseMoved
        }
    }
}
