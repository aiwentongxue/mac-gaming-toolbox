@preconcurrency import GameController
import Foundation

actor CombinedMacroRecorder {
    private let worker: CombinedEventTapWorker
    private var startTimestampNanoseconds: UInt64?
    private var events: [CombinedMacroEvent] = []
    private var mouseRecordingMode: MouseRecordingMode = .fullMotion
    private var progressHandler: (@Sendable (RecorderProgress) -> Void)?
    private var progressTask: Task<Void, Never>?
    private var controllerTask: Task<Void, Never>?
    private var previousControllerValues: [String: Float] = [:]
    private var hasControllerBaseline = false
    private var lastMove: CombinedMacroEvent?
    private var pendingMove: CombinedMacroEvent?
    private(set) var isRecording = false

    init(worker: CombinedEventTapWorker = CombinedEventTapWorker()) {
        self.worker = worker
    }

    func start(
        mouseMode: MouseRecordingMode,
        progress: @escaping @Sendable (RecorderProgress) -> Void
    ) throws {
        guard !isRecording else { return }
        events = []
        previousControllerValues = [:]
        hasControllerBaseline = false
        lastMove = nil
        pendingMove = nil
        mouseRecordingMode = mouseMode
        progressHandler = progress
        startTimestampNanoseconds = DispatchTime.now().uptimeNanoseconds
        GCController.shouldMonitorBackgroundEvents = true

        try worker.start { [weak self] input in
            Task { await self?.consume(input) }
        }
        isRecording = true
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                await self?.publishProgress()
            }
        }
        controllerTask = Task { [weak self] in
            await self?.pollControllers()
        }
        AppLogger.recording.notice("Combined macro recording started")
    }

    func stop(
        discardTerminalMouseClick: Bool = false,
        terminalHotkey: HotkeyConfiguration? = nil
    ) -> [CombinedMacroEvent] {
        guard isRecording else { return events }
        isRecording = false
        worker.stop()
        progressTask?.cancel()
        controllerTask?.cancel()
        progressTask = nil
        controllerTask = nil
        GCController.shouldMonitorBackgroundEvents = false
        flushPendingMove()
        progressHandler = nil
        startTimestampNanoseconds = nil
        let ordered = events.sorted { $0.timestampMilliseconds < $1.timestampMilliseconds }
        guard let first = ordered.first?.timestampMilliseconds else { return [] }
        var result = ordered.map {
            var copy = $0
            copy.timestampMilliseconds = max(0, copy.timestampMilliseconds - first)
            return copy
        }
        if discardTerminalMouseClick {
            result = RecordingTimeline.removingTerminalControlClick(from: result)
        }
        if let terminalHotkey {
            result = RecordingTimeline.removingTerminalHotkey(
                from: result,
                configuration: terminalHotkey
            )
        }
        AppLogger.recording.notice("Combined macro recording stopped with \(result.count) events")
        return result
    }

    private func consume(_ input: CapturedSystemInput) {
        guard isRecording else { return }
        let event = CombinedMacroEvent(
            timestampMilliseconds: elapsedMilliseconds(at: input.timestampNanoseconds),
            kind: combinedKind(input.kind),
            position: input.position,
            button: input.button,
            scrollDeltaX: input.kind == .scroll ? input.scrollDeltaX : nil,
            scrollDeltaY: input.kind == .scroll ? input.scrollDeltaY : nil,
            keyCode: input.keyCode,
            keyDisplayName: input.keyCode.map(KeyboardKey.name(for:)),
            keyboardModifiers: input.keyCode == nil ? nil : input.keyboardModifiers
        )

        if input.kind == .mouseMove {
            guard mouseRecordingMode == .fullMotion else { return }
            sampleMove(event)
        } else {
            flushPendingMove()
            events.append(event)
        }
        publishProgress()
    }

    private func sampleMove(_ event: CombinedMacroEvent) {
        guard let lastMove,
              let oldPosition = lastMove.position,
              let newPosition = event.position else {
            events.append(event)
            lastMove = event
            return
        }
        let elapsed = event.timestampMilliseconds - lastMove.timestampMilliseconds
        let distance = hypot(newPosition.x - oldPosition.x, newPosition.y - oldPosition.y)
        if elapsed >= 16.67, distance >= 2 || elapsed >= 100 {
            events.append(event)
            self.lastMove = event
            pendingMove = nil
        } else {
            pendingMove = event
        }
    }

    private func flushPendingMove() {
        if let pendingMove {
            events.append(pendingMove)
            lastMove = pendingMove
            self.pendingMove = nil
        }
    }

    private func pollControllers() async {
        while !Task.isCancelled, isRecording {
            let values = controllerValues()
            if !hasControllerBaseline {
                previousControllerValues = values
                hasControllerBaseline = true
                try? await Task.sleep(for: .milliseconds(8))
                continue
            }
            for (key, value) in values {
                let previous = previousControllerValues[key]
                if (previous == nil && abs(value) >= 0.01) ||
                    (previous != nil && abs((previous ?? 0) - value) >= 0.01) {
                    let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
                    events.append(CombinedMacroEvent(
                        timestampMilliseconds: elapsedMilliseconds(),
                        kind: .controller,
                        controllerName: parts.first ?? cf("combined.controller.unknown"),
                        controlName: parts.count > 1 ? parts[1] : key,
                        controlValue: value
                    ))
                }
            }
            previousControllerValues = values
            try? await Task.sleep(for: .milliseconds(8))
        }
    }

    private func controllerValues() -> [String: Float] {
        var result: [String: Float] = [:]
        for (index, controller) in GCController.controllers().enumerated() {
            guard let gamepad = controller.extendedGamepad else { continue }
            let name = "\(controller.vendorName ?? "Controller") #\(index + 1)"
            func add(_ control: String, _ value: Float) { result["\(name)|\(control)"] = value }
            add("buttonA", gamepad.buttonA.value)
            add("buttonB", gamepad.buttonB.value)
            add("buttonX", gamepad.buttonX.value)
            add("buttonY", gamepad.buttonY.value)
            add("leftShoulder", gamepad.leftShoulder.value)
            add("rightShoulder", gamepad.rightShoulder.value)
            add("leftTrigger", gamepad.leftTrigger.value)
            add("rightTrigger", gamepad.rightTrigger.value)
            add("dpad.x", gamepad.dpad.xAxis.value)
            add("dpad.y", gamepad.dpad.yAxis.value)
            add("leftThumbstick.x", gamepad.leftThumbstick.xAxis.value)
            add("leftThumbstick.y", gamepad.leftThumbstick.yAxis.value)
            add("rightThumbstick.x", gamepad.rightThumbstick.xAxis.value)
            add("rightThumbstick.y", gamepad.rightThumbstick.yAxis.value)
            add("menu", gamepad.buttonMenu.value)
            if let button = gamepad.buttonOptions { add("options", button.value) }
            if let button = gamepad.buttonHome { add("home", button.value) }
            if let button = gamepad.leftThumbstickButton { add("leftThumbstickButton", button.value) }
            if let button = gamepad.rightThumbstickButton { add("rightThumbstickButton", button.value) }
        }
        return result
    }

    private func elapsedMilliseconds() -> Double {
        elapsedMilliseconds(at: DispatchTime.now().uptimeNanoseconds)
    }

    private func elapsedMilliseconds(at timestampNanoseconds: UInt64) -> Double {
        guard let startTimestampNanoseconds else { return 0 }
        let elapsed = timestampNanoseconds >= startTimestampNanoseconds
            ? timestampNanoseconds - startTimestampNanoseconds
            : 0
        return Double(elapsed) / 1_000_000
    }

    private func publishProgress() {
        guard isRecording else { return }
        progressHandler?(RecorderProgress(
            elapsedMilliseconds: elapsedMilliseconds(),
            eventCount: events.count + (pendingMove == nil ? 0 : 1)
        ))
    }

    private func combinedKind(_ kind: CapturedSystemInput.Kind) -> CombinedMacroEventKind {
        switch kind {
        case .mouseMove: .mouseMove
        case .mouseDown: .mouseDown
        case .mouseUp: .mouseUp
        case .scroll: .scroll
        case .keyDown: .keyDown
        case .keyUp: .keyUp
        }
    }
}
