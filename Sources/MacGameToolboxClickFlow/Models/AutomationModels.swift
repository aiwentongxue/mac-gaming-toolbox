import Foundation

struct ScreenPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
}
enum MouseButton: String, Codable, CaseIterable, Identifiable, Sendable {
    case left
    case right
    case middle

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .left: cf("mouseButton.left")
        case .right: cf("mouseButton.right")
        case .middle: cf("mouseButton.middle")
        }
    }
}

enum ClickGesture: String, Codable, CaseIterable, Identifiable, Sendable {
    case single
    case double

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .single: cf("clickGesture.single")
        case .double: cf("clickGesture.double")
        }
    }
}

enum ClickCountMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case unlimited
    case finite

    var id: Self { self }
}

enum ClickPositionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case current
    case fixed

    var id: Self { self }
}

enum ClickerInputKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case mouse
    case keyboard

    var id: Self { self }
}

struct KeyboardKey: Codable, Hashable, Sendable {
    var keyCode: UInt16
    var displayName: String

    static let defaultKey = KeyboardKey(keyCode: 3, displayName: "F")

    static func name(for keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
            45: "N", 46: "M", 49: "Space", 53: "Esc", 36: "Return", 48: "Tab",
            51: "Delete", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
            97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            54: "Right Command", 55: "Command", 56: "Shift", 60: "Right Shift",
            58: "Option", 61: "Right Option", 59: "Control", 62: "Right Control", 63: "Fn"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

struct ClickerConfiguration: Codable, Hashable, Sendable {
    static let minimumIntervalMilliseconds = 10.0
    static let maximumIntervalMilliseconds = 60_000.0

    var inputKind: ClickerInputKind = .mouse
    var button: MouseButton = .left
    var keyboardKey: KeyboardKey = .defaultKey
    var gesture: ClickGesture = .single
    var intervalMilliseconds: Double = 100.0
    var positionMode: ClickPositionMode = .current
    var fixedPosition = ScreenPoint(x: 0, y: 0)
    var countMode: ClickCountMode = .unlimited
    var finiteClickCount = 100

    private enum CodingKeys: String, CodingKey {
        case inputKind, button, keyboardKey, gesture, intervalMilliseconds
        case positionMode, fixedPosition, countMode, finiteClickCount
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputKind = try container.decodeIfPresent(ClickerInputKind.self, forKey: .inputKind) ?? .mouse
        button = try container.decodeIfPresent(MouseButton.self, forKey: .button) ?? .left
        keyboardKey = try container.decodeIfPresent(KeyboardKey.self, forKey: .keyboardKey) ?? .defaultKey
        gesture = try container.decodeIfPresent(ClickGesture.self, forKey: .gesture) ?? .single
        intervalMilliseconds = try container.decodeIfPresent(Double.self, forKey: .intervalMilliseconds) ?? 100
        positionMode = try container.decodeIfPresent(ClickPositionMode.self, forKey: .positionMode) ?? .current
        fixedPosition = try container.decodeIfPresent(ScreenPoint.self, forKey: .fixedPosition) ?? ScreenPoint(x: 0, y: 0)
        countMode = try container.decodeIfPresent(ClickCountMode.self, forKey: .countMode) ?? .unlimited
        finiteClickCount = try container.decodeIfPresent(Int.self, forKey: .finiteClickCount) ?? 100
    }

    var clicksPerSecond: Double {
        get { 1_000.0 / intervalMilliseconds }
        set { intervalMilliseconds = Self.clampedInterval(forCPS: newValue) }
    }

    mutating func setInterval(milliseconds: Double) {
        intervalMilliseconds = Self.clampedInterval(milliseconds)
    }

    /// Returns a configuration that is safe to execute even when it originated
    /// from an older or manually damaged preferences payload.
    func sanitizedForExecution() -> Self {
        var result = self
        result.intervalMilliseconds = Self.clampedInterval(intervalMilliseconds)
        result.finiteClickCount = min(max(finiteClickCount, 1), 1_000_000)
        return result
    }

    static func clampedInterval(_ milliseconds: Double) -> Double {
        guard milliseconds.isFinite else { return maximumIntervalMilliseconds }
        return min(max(milliseconds, minimumIntervalMilliseconds), maximumIntervalMilliseconds)
    }

    static func clampedInterval(forCPS cps: Double) -> Double {
        guard cps.isFinite, cps > 0 else { return maximumIntervalMilliseconds }
        let safeCPS = min(max(cps, 1_000.0 / maximumIntervalMilliseconds), 100.0)
        return 1_000.0 / safeCPS
    }
}

enum MacroEventKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case mouseMove
    case mouseDown
    case mouseUp
    case scroll

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .mouseMove: cf("macroEvent.mouseMove")
        case .mouseDown: cf("macroEvent.mouseDown")
        case .mouseUp: cf("macroEvent.mouseUp")
        case .scroll: cf("macroEvent.scroll")
        }
    }
}

struct MacroEvent: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var timestampMilliseconds: Double
    var kind: MacroEventKind
    var position: ScreenPoint?
    var button: MouseButton?
    var scrollDeltaX: Int32?
    var scrollDeltaY: Int32?

    init(
        id: UUID = UUID(),
        timestampMilliseconds: Double,
        kind: MacroEventKind,
        position: ScreenPoint? = nil,
        button: MouseButton? = nil,
        scrollDeltaX: Int32? = nil,
        scrollDeltaY: Int32? = nil
    ) {
        self.id = id
        self.timestampMilliseconds = timestampMilliseconds
        self.kind = kind
        self.position = position
        self.button = button
        self.scrollDeltaX = scrollDeltaX
        self.scrollDeltaY = scrollDeltaY
    }
}

enum MacroRepeatMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case once
    case count
    case unlimited

    var id: Self { self }
}

enum MouseRecordingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fullMotion
    case clickPositionsOnly

    var id: Self { self }

    func records(_ kind: MacroEventKind) -> Bool {
        self == .fullMotion || kind != .mouseMove
    }
}

struct MouseMacro: Codable, Identifiable, Hashable, Sendable {
    static let schemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var events: [MacroEvent]
    var repeatMode: MacroRepeatMode
    var repeatCount: Int
    var repeatDelayMilliseconds: Double
    var playbackSpeed: Double

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        events: [MacroEvent] = [],
        repeatMode: MacroRepeatMode = .once,
        repeatCount: Int = 1,
        repeatDelayMilliseconds: Double = 0,
        playbackSpeed: Double = 1
    ) {
        self.schemaVersion = Self.schemaVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.events = events
        self.repeatMode = repeatMode
        self.repeatCount = repeatCount
        self.repeatDelayMilliseconds = repeatDelayMilliseconds
        self.playbackSpeed = playbackSpeed
    }

    var durationMilliseconds: Double {
        events.map(\.timestampMilliseconds).max() ?? 0
    }
}

enum HotkeyAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case startClicker
    case stopClicker
    case startMouseRecording
    case stopMouseRecording
    case playRecentMacro
    case pauseResumeMacro
    case stopMacro
    case startCombinedRecording
    case stopCombinedRecording
    case playRecentCombinedMacro
    case pauseResumeCombinedMacro
    case stopCombinedMacro
    case captureFixedPosition

    var id: Self { self }

    static var configurableCases: [Self] {
        allCases.filter { $0 != .captureFixedPosition }
    }

    static let clickerCases: [Self] = [
        .startClicker,
        .stopClicker
    ]

    static let mouseMacroCases: [Self] = [
        .startMouseRecording,
        .stopMouseRecording,
        .playRecentMacro,
        .pauseResumeMacro,
        .stopMacro
    ]

    static let combinedMacroCases: [Self] = [
        .startCombinedRecording,
        .stopCombinedRecording,
        .playRecentCombinedMacro,
        .pauseResumeCombinedMacro,
        .stopCombinedMacro
    ]
}

enum CombinedMacroEventKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case mouseMove
    case mouseDown
    case mouseUp
    case scroll
    case keyDown
    case keyUp
    case controller

    var id: Self { self }
}

struct CombinedMacroEvent: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var timestampMilliseconds: Double
    var kind: CombinedMacroEventKind
    var position: ScreenPoint?
    var button: MouseButton?
    var scrollDeltaX: Int32?
    var scrollDeltaY: Int32?
    var keyCode: UInt16?
    var keyDisplayName: String?
    var keyboardModifiers: UInt64?
    var controllerName: String?
    var controlName: String?
    var controlValue: Float?

    init(
        id: UUID = UUID(),
        timestampMilliseconds: Double,
        kind: CombinedMacroEventKind,
        position: ScreenPoint? = nil,
        button: MouseButton? = nil,
        scrollDeltaX: Int32? = nil,
        scrollDeltaY: Int32? = nil,
        keyCode: UInt16? = nil,
        keyDisplayName: String? = nil,
        keyboardModifiers: UInt64? = nil,
        controllerName: String? = nil,
        controlName: String? = nil,
        controlValue: Float? = nil
    ) {
        self.id = id
        self.timestampMilliseconds = timestampMilliseconds
        self.kind = kind
        self.position = position
        self.button = button
        self.scrollDeltaX = scrollDeltaX
        self.scrollDeltaY = scrollDeltaY
        self.keyCode = keyCode
        self.keyDisplayName = keyDisplayName
        self.keyboardModifiers = keyboardModifiers
        self.controllerName = controllerName
        self.controlName = controlName
        self.controlValue = controlValue
    }
}

struct CombinedMacro: Codable, Identifiable, Hashable, Sendable {
    static let schemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var events: [CombinedMacroEvent]
    var repeatMode: MacroRepeatMode
    var repeatCount: Int
    var repeatDelayMilliseconds: Double
    var playbackSpeed: Double

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        events: [CombinedMacroEvent] = [],
        repeatMode: MacroRepeatMode = .once,
        repeatCount: Int = 1,
        repeatDelayMilliseconds: Double = 0,
        playbackSpeed: Double = 1
    ) {
        schemaVersion = Self.schemaVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.events = events
        self.repeatMode = repeatMode
        self.repeatCount = repeatCount
        self.repeatDelayMilliseconds = repeatDelayMilliseconds
        self.playbackSpeed = playbackSpeed
    }

    var durationMilliseconds: Double {
        events.map(\.timestampMilliseconds).max() ?? 0
    }

    var containsControllerEvents: Bool {
        events.contains { $0.kind == .controller }
    }
}

struct HotkeyConfiguration: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyDisplayName: String?

    init(keyCode: UInt32, modifiers: UInt32, keyDisplayName: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyDisplayName = keyDisplayName
    }

    static let defaults: [HotkeyAction: HotkeyConfiguration] = [:]

    var chord: HotkeyChord {
        HotkeyChord(keyCode: keyCode, modifiers: modifiers)
    }
}

struct HotkeyChord: Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
}

enum SidebarPage: String, Codable, CaseIterable, Identifiable, Sendable {
    case clicker
    case macros
    case combinedMacros
    case settings

    var id: Self { self }
}
