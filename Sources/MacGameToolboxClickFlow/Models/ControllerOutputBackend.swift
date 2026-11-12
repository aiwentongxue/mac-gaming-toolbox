import Foundation

enum ControllerOutputBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case xinput, ojd
    var id: Self { self }
    var title: String {
        switch self {
        case .xinput: cf("controller.backend.xinput")
        case .ojd: cf("controller.backend.ojd")
        }
    }
    var explanation: String {
        switch self {
        case .xinput: cf("controller.backend.xinput.description")
        case .ojd: cf("controller.backend.ojd.description")
        }
    }
}

struct OJDFrame: Encodable, Equatable, Sendable {
    var buttons: [String]
    var dpad: [String]
    var axes: [String: Double]

    init(state: CrossOverXInputState) {
        let mappings: [(UInt16, String)] = [
            (0x1000, "South"), (0x2000, "East"), (0x4000, "West"), (0x8000, "North"),
            (0x0100, "LeftShoulder"), (0x0200, "RightShoulder"), (0x0010, "Start"),
            (0x0020, "Back"), (0x0040, "LeftStickClick"), (0x0080, "RightStickClick"), (0x0400, "Guide")
        ]
        buttons = mappings.filter { state.buttons & $0.0 != 0 }.map(\.1).sorted()
        let directions: [(UInt16, String)] = [(1, "DpadUp"), (2, "DpadDown"), (4, "DpadLeft"), (8, "DpadRight")]
        dpad = directions.filter { state.buttons & $0.0 != 0 }.map(\.1).sorted()
        func axis(_ value: Int16) -> Double { Double(value) / (value < 0 ? 32768 : 32767) }
        axes = ["LeftStickX": axis(state.leftStickX), "LeftStickY": -axis(state.leftStickY),
                "RightStickX": axis(state.rightStickX), "RightStickY": -axis(state.rightStickY),
                "LeftTrigger": Double(state.leftTrigger) / 255, "RightTrigger": Double(state.rightTrigger) / 255]
    }
}
