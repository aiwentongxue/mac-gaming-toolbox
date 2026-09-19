@preconcurrency import GameController
import Foundation

protocol ControllerOutputPublishing: Sendable {
    func begin(primaryControllerName: String?) throws
    func apply(controllerName: String?, controlName: String?, value: Float?) throws
    func pause() throws
    func resume() throws
    func reset() throws
    func end() throws
}

/// Publishes ClickFlow controller macro events to the native XInput proxy used
/// by one CrossOver/Wine game process. This is deliberately not presented as a
/// macOS virtual controller: IORegistry, GameController, and other apps do not
/// see it.
final class CrossOverXInputPublisher: ControllerOutputPublishing, @unchecked Sendable {
    static let defaultURL = URL(fileURLWithPath: "/private/tmp/ClickFlow.xinput")

    let url: URL
    private let physicalController: any PhysicalControllerStateProviding
    private let pollInterval: Duration
    private let heartbeatInterval: Duration
    private let lock = NSLock()
    private var sequence: UInt32 = 0
    private var connected = false
    private var physicalPassthroughActive = false
    private var macroActive = false
    private var primaryControllerName: String?
    private var physicalState: CrossOverXInputState?
    private var macroState = CrossOverXInputState()
    private var macroOverrides: Set<CrossOverXInputControl> = []
    private var suspendedMacroState: CrossOverXInputState?
    private var suspendedMacroOverrides: Set<CrossOverXInputControl>?
    private var publishedState = CrossOverXInputState()
    private var lastWrite: ContinuousClock.Instant?
    private var workerTask: Task<Void, Never>?

    init(
        url: URL = defaultURL,
        physicalController: any PhysicalControllerStateProviding = GameControllerPhysicalStateProvider(),
        pollInterval: Duration = .milliseconds(8),
        heartbeatInterval: Duration = .seconds(1)
    ) {
        self.url = url.standardizedFileURL
        self.physicalController = physicalController
        self.pollInterval = pollInterval
        self.heartbeatInterval = heartbeatInterval
    }

    deinit {
        workerTask?.cancel()
    }

    /// Keeps the proxy connected to the first physical controller even when no
    /// macro is playing. Macro input is mixed into this state by `apply`.
    func startPhysicalPassthrough() throws {
        physicalController.startMonitoring()
        let sample = physicalController.currentState(preferredControllerName: nil)
        try lock.withLock {
            physicalPassthroughActive = true
            physicalState = sample
            try publishIfNeeded(force: true)
        }
        startWorkerIfNeeded()
    }

    func stopPhysicalPassthrough() {
        physicalController.stopMonitoring()
        try? lock.withLock {
            physicalPassthroughActive = false
            physicalState = nil
            try publishIfNeeded(force: true)
        }
        stopWorkerIfIdle()
    }

    /// Exposed internally for deterministic diagnostics and tests.
    func refreshPhysicalState() throws {
        let preferredName = lock.withLock { primaryControllerName }
        let sample = physicalController.currentState(preferredControllerName: preferredName)
        try lock.withLock {
            physicalState = sample
            try publishIfNeeded(force: heartbeatExpired())
        }
    }

    func begin(primaryControllerName: String?) throws {
        try lock.withLock {
            macroActive = true
            self.primaryControllerName = primaryControllerName
            macroState = CrossOverXInputState()
            macroOverrides.removeAll()
            suspendedMacroState = nil
            suspendedMacroOverrides = nil
            try publishIfNeeded(force: true)
        }
        startWorkerIfNeeded()
    }

    func apply(controllerName: String?, controlName: String?, value: Float?) throws {
        guard let controlName, let value, value.isFinite else { return }
        try lock.withLock {
            guard macroActive, matchesPrimary(controllerName),
                  let control = CrossOverXInputControl(controlName: controlName) else { return }
            var updated = macroState
            updated.apply(control: control, value: value)
            let wasOverridden = macroOverrides.contains(control)
            let shouldOverride = !control.isNeutral(value)
            guard updated != macroState || wasOverridden != shouldOverride else { return }
            macroState = updated
            if shouldOverride {
                macroOverrides.insert(control)
            } else {
                macroOverrides.remove(control)
            }
            suspendedMacroState = nil
            suspendedMacroOverrides = nil
            try publishIfNeeded()
        }
    }

    func pause() throws {
        try lock.withLock {
            guard macroActive, suspendedMacroState == nil else { return }
            suspendedMacroState = macroState
            suspendedMacroOverrides = macroOverrides
            macroState = CrossOverXInputState()
            macroOverrides.removeAll()
            try publishIfNeeded(force: true)
        }
    }

    func resume() throws {
        try lock.withLock {
            guard macroActive,
                  let suspendedMacroState,
                  let suspendedMacroOverrides else { return }
            self.suspendedMacroState = nil
            self.suspendedMacroOverrides = nil
            macroState = suspendedMacroState
            macroOverrides = suspendedMacroOverrides
            try publishIfNeeded(force: true)
        }
    }

    func reset() throws {
        try lock.withLock {
            guard macroActive else { return }
            suspendedMacroState = nil
            suspendedMacroOverrides = nil
            macroState = CrossOverXInputState()
            macroOverrides.removeAll()
            try publishIfNeeded(force: true)
        }
    }

    func end() throws {
        try lock.withLock {
            guard macroActive else { return }
            macroActive = false
            primaryControllerName = nil
            macroState = CrossOverXInputState()
            macroOverrides.removeAll()
            suspendedMacroState = nil
            suspendedMacroOverrides = nil
            try publishIfNeeded(force: true)
        }
        stopWorkerIfIdle()
    }

    private func startWorkerIfNeeded() {
        let shouldStart = lock.withLock {
            guard workerTask == nil, physicalPassthroughActive || macroActive else { return false }
            return true
        }
        guard shouldStart else { return }
        let interval = pollInterval
        let task = Task.detached(priority: .high) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if !Task.isCancelled { try? self?.refreshPhysicalState() }
            }
        }
        lock.withLock {
            if workerTask == nil {
                workerTask = task
            } else {
                task.cancel()
            }
        }
    }

    private func stopWorkerIfIdle() {
        let task = lock.withLock { () -> Task<Void, Never>? in
            guard !physicalPassthroughActive, !macroActive else { return nil }
            let task = workerTask
            workerTask = nil
            return task
        }
        task?.cancel()
    }

    private func matchesPrimary(_ controllerName: String?) -> Bool {
        guard let primaryControllerName else { return true }
        return controllerName == primaryControllerName
    }

    private func publishIfNeeded(force: Bool = false) throws {
        let nextConnected = macroActive || (physicalPassthroughActive && physicalState != nil)
        let base = physicalPassthroughActive ? (physicalState ?? CrossOverXInputState()) : CrossOverXInputState()
        let nextState = base.merging(macroState, overriding: macroOverrides)
        let changed = nextConnected != connected || nextState != publishedState
        guard force || changed else { return }
        if changed { sequence &+= 1 }
        connected = nextConnected
        publishedState = nextState
        try writeCurrentState()
    }

    private func heartbeatExpired() -> Bool {
        guard let lastWrite else { return true }
        return ContinuousClock().now - lastWrite >= heartbeatInterval
    }

    private func writeCurrentState() throws {
        let data = CrossOverXInputSharedState(
            sequence: sequence,
            connected: connected,
            state: publishedState
        ).encoded()
        try data.write(to: url, options: .atomic)
        lastWrite = ContinuousClock().now
    }
}

protocol PhysicalControllerStateProviding: Sendable {
    func startMonitoring()
    func stopMonitoring()
    func currentState(preferredControllerName: String?) -> CrossOverXInputState?
}

extension PhysicalControllerStateProviding {
    func startMonitoring() {}
    func stopMonitoring() {}
}

final class GameControllerPhysicalStateProvider: PhysicalControllerStateProviding, @unchecked Sendable {
    func startMonitoring() {
        GCController.shouldMonitorBackgroundEvents = true
    }

    func stopMonitoring() {
        GCController.shouldMonitorBackgroundEvents = false
    }

    func currentState(preferredControllerName: String?) -> CrossOverXInputState? {
        let candidates = GCController.controllers().enumerated().compactMap { index, controller in
            controller.extendedGamepad.map {
                (name: "\(controller.vendorName ?? "Controller") #\(index + 1)", gamepad: $0)
            }
        }
        guard let selected = candidates.first(where: { $0.name == preferredControllerName })
                ?? candidates.first else { return nil }

        let gamepad = selected.gamepad
        var state = CrossOverXInputState()
        state.apply(control: .buttonA, value: gamepad.buttonA.value)
        state.apply(control: .buttonB, value: gamepad.buttonB.value)
        state.apply(control: .buttonX, value: gamepad.buttonX.value)
        state.apply(control: .buttonY, value: gamepad.buttonY.value)
        state.apply(control: .leftShoulder, value: gamepad.leftShoulder.value)
        state.apply(control: .rightShoulder, value: gamepad.rightShoulder.value)
        state.apply(control: .leftTrigger, value: gamepad.leftTrigger.value)
        state.apply(control: .rightTrigger, value: gamepad.rightTrigger.value)
        state.apply(control: .dpadX, value: gamepad.dpad.xAxis.value)
        state.apply(control: .dpadY, value: gamepad.dpad.yAxis.value)
        state.apply(control: .leftStickX, value: gamepad.leftThumbstick.xAxis.value)
        state.apply(control: .leftStickY, value: gamepad.leftThumbstick.yAxis.value)
        state.apply(control: .rightStickX, value: gamepad.rightThumbstick.xAxis.value)
        state.apply(control: .rightStickY, value: gamepad.rightThumbstick.yAxis.value)
        state.apply(control: .menu, value: gamepad.buttonMenu.value)
        if let button = gamepad.buttonOptions { state.apply(control: .view, value: button.value) }
        if let button = gamepad.buttonHome { state.apply(control: .home, value: button.value) }
        if let button = gamepad.leftThumbstickButton {
            state.apply(control: .leftStickButton, value: button.value)
        }
        if let button = gamepad.rightThumbstickButton {
            state.apply(control: .rightStickButton, value: button.value)
        }
        return state
    }
}

enum CrossOverXInputControl: Hashable, Sendable {
    case buttonA, buttonB, buttonX, buttonY
    case leftShoulder, rightShoulder
    case leftTrigger, rightTrigger
    case leftStickButton, rightStickButton
    case menu, view, home
    case dpadX, dpadY
    case leftStickX, leftStickY, rightStickX, rightStickY

    init?(controlName: String) {
        let normalized = controlName.lowercased().filter { $0.isLetter || $0.isNumber }
        switch normalized {
        case "buttona", "a", "cross": self = .buttonA
        case "buttonb", "b", "circle": self = .buttonB
        case "buttonx", "x", "square": self = .buttonX
        case "buttony", "y", "triangle": self = .buttonY
        case "leftshoulder", "leftbumper", "lb", "l1": self = .leftShoulder
        case "rightshoulder", "rightbumper", "rb", "r1": self = .rightShoulder
        case "leftthumbstickbutton", "leftstickbutton", "ls", "l3": self = .leftStickButton
        case "rightthumbstickbutton", "rightstickbutton", "rs", "r3": self = .rightStickButton
        case "menu", "start": self = .menu
        case "view", "back", "create", "share", "options": self = .view
        case "home", "guide", "ps": self = .home
        case "lefttrigger", "lt", "l2": self = .leftTrigger
        case "righttrigger", "rt", "r2": self = .rightTrigger
        case "dpadx": self = .dpadX
        case "dpady": self = .dpadY
        case "leftthumbstickx", "leftstickx": self = .leftStickX
        case "leftthumbsticky", "leftsticky": self = .leftStickY
        case "rightthumbstickx", "rightstickx": self = .rightStickX
        case "rightthumbsticky", "rightsticky": self = .rightStickY
        default: return nil
        }
    }

    func isNeutral(_ value: Float) -> Bool {
        switch self {
        case .buttonA, .buttonB, .buttonX, .buttonY,
             .leftShoulder, .rightShoulder, .leftStickButton, .rightStickButton,
             .menu, .view, .home, .leftTrigger, .rightTrigger:
            value < 0.01
        case .dpadX, .dpadY, .leftStickX, .leftStickY, .rightStickX, .rightStickY:
            abs(value) < 0.01
        }
    }
}

struct CrossOverXInputState: Equatable, Sendable {
    private(set) var buttonBits: UInt16 = 0
    private(set) var dpadX: Float = 0
    private(set) var dpadY: Float = 0
    private(set) var leftTrigger: UInt8 = 0
    private(set) var rightTrigger: UInt8 = 0
    private(set) var leftStickX: Int16 = 0
    private(set) var leftStickY: Int16 = 0
    private(set) var rightStickX: Int16 = 0
    private(set) var rightStickY: Int16 = 0

    var buttons: UInt16 {
        var result = buttonBits
        if dpadY >= 0.5 { result |= 0x0001 }
        if dpadY <= -0.5 { result |= 0x0002 }
        if dpadX <= -0.5 { result |= 0x0004 }
        if dpadX >= 0.5 { result |= 0x0008 }
        return result
    }

    @discardableResult
    mutating func apply(controlName: String, value: Float) -> Bool {
        guard let control = CrossOverXInputControl(controlName: controlName) else { return false }
        apply(control: control, value: value)
        return true
    }

    mutating func apply(control: CrossOverXInputControl, value: Float) {
        switch control {
        case .buttonA: setButton(0x1000, value: value)
        case .buttonB: setButton(0x2000, value: value)
        case .buttonX: setButton(0x4000, value: value)
        case .buttonY: setButton(0x8000, value: value)
        case .leftShoulder: setButton(0x0100, value: value)
        case .rightShoulder: setButton(0x0200, value: value)
        case .leftStickButton: setButton(0x0040, value: value)
        case .rightStickButton: setButton(0x0080, value: value)
        case .menu: setButton(0x0010, value: value)
        case .view: setButton(0x0020, value: value)
        case .home: setButton(0x0400, value: value)
        case .leftTrigger: leftTrigger = Self.trigger(value)
        case .rightTrigger: rightTrigger = Self.trigger(value)
        case .dpadX: dpadX = Self.clampedAxis(value)
        case .dpadY: dpadY = Self.clampedAxis(value)
        case .leftStickX: leftStickX = Self.stick(value)
        case .leftStickY: leftStickY = Self.stick(value)
        case .rightStickX: rightStickX = Self.stick(value)
        case .rightStickY: rightStickY = Self.stick(value)
        }
    }

    func merging(
        _ overlay: CrossOverXInputState,
        overriding controls: Set<CrossOverXInputControl>
    ) -> CrossOverXInputState {
        var result = self
        for control in controls {
            switch control {
            case .buttonA: result.copyButton(0x1000, from: overlay)
            case .buttonB: result.copyButton(0x2000, from: overlay)
            case .buttonX: result.copyButton(0x4000, from: overlay)
            case .buttonY: result.copyButton(0x8000, from: overlay)
            case .leftShoulder: result.copyButton(0x0100, from: overlay)
            case .rightShoulder: result.copyButton(0x0200, from: overlay)
            case .leftStickButton: result.copyButton(0x0040, from: overlay)
            case .rightStickButton: result.copyButton(0x0080, from: overlay)
            case .menu: result.copyButton(0x0010, from: overlay)
            case .view: result.copyButton(0x0020, from: overlay)
            case .home: result.copyButton(0x0400, from: overlay)
            case .leftTrigger: result.leftTrigger = overlay.leftTrigger
            case .rightTrigger: result.rightTrigger = overlay.rightTrigger
            case .dpadX: result.dpadX = overlay.dpadX
            case .dpadY: result.dpadY = overlay.dpadY
            case .leftStickX: result.leftStickX = overlay.leftStickX
            case .leftStickY: result.leftStickY = overlay.leftStickY
            case .rightStickX: result.rightStickX = overlay.rightStickX
            case .rightStickY: result.rightStickY = overlay.rightStickY
            }
        }
        return result
    }

    private mutating func setButton(_ mask: UInt16, value: Float) {
        if value >= 0.5 {
            buttonBits |= mask
        } else {
            buttonBits &= ~mask
        }
    }

    private mutating func copyButton(_ mask: UInt16, from state: CrossOverXInputState) {
        if state.buttonBits & mask != 0 {
            buttonBits |= mask
        } else {
            buttonBits &= ~mask
        }
    }

    private static func clampedAxis(_ value: Float) -> Float {
        min(1, max(-1, value))
    }

    private static func trigger(_ value: Float) -> UInt8 {
        UInt8(clamping: Int((min(1, max(0, value)) * 255).rounded()))
    }

    private static func stick(_ value: Float) -> Int16 {
        let clamped = clampedAxis(value)
        let scale: Float = clamped < 0 ? 32_768 : 32_767
        return Int16(clamping: Int((clamped * scale).rounded()))
    }
}

struct CrossOverXInputSharedState: Equatable, Sendable {
    static let magic: UInt32 = 0x3150_4756
    static let version: UInt16 = 1
    static let encodedSize: UInt16 = 32

    var sequence: UInt32
    var connected: Bool
    var state: CrossOverXInputState

    func encoded() -> Data {
        var result = Data(capacity: Int(Self.encodedSize))
        result.appendLittleEndian(Self.magic)
        result.appendLittleEndian(Self.version)
        result.appendLittleEndian(Self.encodedSize)
        result.appendLittleEndian(sequence)
        result.appendLittleEndian(connected ? UInt32(1) : UInt32(0))
        result.appendLittleEndian(state.buttons)
        result.append(state.leftTrigger)
        result.append(state.rightTrigger)
        result.appendLittleEndian(UInt16(bitPattern: state.leftStickX))
        result.appendLittleEndian(UInt16(bitPattern: state.leftStickY))
        result.appendLittleEndian(UInt16(bitPattern: state.rightStickX))
        result.appendLittleEndian(UInt16(bitPattern: state.rightStickY))
        result.appendLittleEndian(UInt32(0))
        precondition(result.count == Int(Self.encodedSize))
        return result
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
