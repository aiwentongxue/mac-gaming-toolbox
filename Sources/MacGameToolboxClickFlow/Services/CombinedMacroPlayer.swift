import CoreGraphics
import Foundation

actor CombinedMacroPlayer {
    private let events: any MouseEventPosting
    private let controllerOutput: any ControllerOutputPublishing
    private var runTask: Task<Void, Never>?
    private var delayTask: Task<Void, Never>?
    private var runID: UUID?
    private var isPaused = false
    private var pressedButtons: Set<MouseButton> = []
    private var pressedKeys: [UInt16: CGEventFlags] = [:]
    private var suspendedButtons: Set<MouseButton> = []
    private var suspendedKeys: [UInt16: CGEventFlags] = [:]
    private var lastPosition: ScreenPoint?
    private var timelineClock = PlaybackTimelineClock()
    private var controllerOutputActive = false

    init(
        events: any MouseEventPosting = MouseEventService(),
        controllerOutput: any ControllerOutputPublishing = CrossOverXInputPublisher()
    ) {
        self.events = events
        self.controllerOutput = controllerOutput
    }

    func start(
        macro: CombinedMacro,
        progress: @escaping @Sendable (MacroPlaybackProgress) -> Void,
        completion: @escaping @Sendable (String?) -> Void
    ) {
        guard runTask == nil else { return }
        guard !macro.events.isEmpty else {
            completion(cf("error.emptyMacro"))
            return
        }
        do { try MacroExchange.validate(.combined(macro)) }
        catch {
            completion(error.localizedDescription)
            return
        }
        lastPosition = nil
        let id = UUID()
        runID = id
        runTask = Task { [weak self] in
            guard let self else { return }
            let error = await self.run(macro, progress: progress)
            await self.cleanupAllPressedInputs()
            await self.finish(id)
            completion(error)
        }
        AppLogger.automation.notice("Combined macro playback started: \(macro.name, privacy: .public)")
    }

    func stop() async {
        let task = runTask
        task?.cancel()
        delayTask?.cancel()
        isPaused = false
        await task?.value
        if task == nil { cleanupAllPressedInputs() }
        AppLogger.automation.notice("Combined macro playback stopped")
    }

    func isRunning() -> Bool { runTask != nil }

    func togglePause() -> Bool? {
        guard runTask != nil else { return nil }
        if isPaused {
            timelineClock.resume()
            isPaused = false
            if controllerOutputActive { try? controllerOutput.resume() }
            AppLogger.automation.notice("Combined macro playback resumed")
        } else {
            isPaused = true
            timelineClock.pause()
            delayTask?.cancel()
            suspendedButtons = pressedButtons
            suspendedKeys = pressedKeys
            releaseActiveInputs()
            if controllerOutputActive { try? controllerOutput.pause() }
            AppLogger.automation.notice("Combined macro playback paused")
        }
        return isPaused
    }

    private func finish(_ id: UUID) {
        guard runID == id else { return }
        delayTask = nil
        isPaused = false
        timelineClock.resume()
        runID = nil
        runTask = nil
    }

    private func run(
        _ macro: CombinedMacro,
        progress: @escaping @Sendable (MacroPlaybackProgress) -> Void
    ) async -> String? {
        let totalLoops = macro.repeatMode.resolvedLoopCount(configuredCount: macro.repeatCount)
        var loopIndex = 0
        do {
            if macro.containsControllerEvents {
                try controllerOutput.selectBackend(macro.controllerBackend)
                try controllerOutput.begin(primaryControllerName: primaryControllerName(in: macro))
                controllerOutputActive = true
            }
            defer {
                if controllerOutputActive {
                    try? controllerOutput.end()
                    controllerOutputActive = false
                }
            }
            while !Task.isCancelled {
                if let totalLoops, loopIndex >= totalLoops { break }
                loopIndex += 1
                timelineClock.restart()
                var controllerBatchEnd = -1
                for (index, event) in macro.events.enumerated() {
                    if index <= controllerBatchEnd { continue }
                    try Task.checkCancellation()
                    if controllerOutputActive { try controllerOutput.checkHealth() }
                    try await pauseAwareSleep(untilMilliseconds: PlaybackTiming.scaledMilliseconds(
                        event.timestampMilliseconds,
                        speed: macro.playbackSpeed
                    ))
                    if isPaused {
                        try await waitUntilResumed()
                    } else {
                        try restoreSuspendedInputs()
                    }
                    var reportedIndex = index
                    if event.kind == .controller, controllerOutputActive {
                        var end = index + 1
                        var controls = Set<CrossOverXInputControl>()
                        if let name = event.controlName, let control = CrossOverXInputControl(controlName: name) { controls.insert(control) }
                        while end < macro.events.count, macro.events[end].kind == .controller,
                              macro.events[end].timestampMilliseconds == event.timestampMilliseconds {
                            if let name = macro.events[end].controlName, let control = CrossOverXInputControl(controlName: name),
                               !controls.insert(control).inserted { break }
                            end += 1
                        }
                        try controllerOutput.applyBatch(Array(macro.events[index..<end]))
                        controllerBatchEnd = end - 1
                        reportedIndex = end - 1
                    } else {
                        try post(event)
                    }
                    progress(MacroPlaybackProgress(
                        eventIndex: reportedIndex + 1,
                        eventCount: macro.events.count,
                        loopIndex: loopIndex,
                        loopCount: totalLoops
                    ))
                    // A paced controller feed may make later timestamps overdue.
                    // Give stop/pause actor calls a chance between frames instead
                    // of draining the overdue events before accepting them.
                    await Task.yield()
                }
                // Each iteration starts with released input, including incomplete recordings.
                cleanupAllPressedInputs()
                if totalLoops.map({ loopIndex < $0 }) ?? true {
                    if macro.repeatDelayMilliseconds > 0 {
                        timelineClock.restart()
                        try await pauseAwareSleep(untilMilliseconds: macro.repeatDelayMilliseconds)
                    } else {
                        await Task.yield()
                        try Task.checkCancellation()
                        if isPaused { try await waitUntilResumed() }
                    }
                }
            }
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            AppLogger.automation.error("Combined playback failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    private func post(_ event: CombinedMacroEvent) throws {
        if let position = event.position { lastPosition = position }
        let position = event.position ?? lastPosition ?? events.currentPosition()
        switch event.kind {
        case .mouseMove:
            try events.postMove(to: position, dragging: pressedButtons.first)
        case .mouseDown:
            guard let button = event.button else { return }
            try events.postButton(button, down: true, at: position)
            pressedButtons.insert(button)
        case .mouseUp:
            guard let button = event.button else { return }
            try events.postButton(button, down: false, at: position)
            pressedButtons.remove(button)
        case .scroll:
            try events.postScroll(
                deltaX: event.scrollDeltaX ?? 0,
                deltaY: event.scrollDeltaY ?? 0,
                at: position
            )
        case .keyDown, .keyUp:
            guard let code = event.keyCode else { return }
            let key = KeyboardKey(keyCode: code, displayName: event.keyDisplayName ?? KeyboardKey.name(for: code))
            let down = event.kind == .keyDown
            let flags = CGEventFlags(rawValue: event.keyboardModifiers ?? 0)
            try events.postKey(key, down: down, flags: flags)
            if down { pressedKeys[code] = flags } else { pressedKeys.removeValue(forKey: code) }
        case .controller:
            guard controllerOutputActive else { return }
            try controllerOutput.apply(
                controllerName: event.controllerName,
                controlName: event.controlName,
                value: event.controlValue
            )
        }
    }

    private func pauseAwareSleep(untilMilliseconds milliseconds: Double) async throws {
        while true {
            if controllerOutputActive { try controllerOutput.checkHealth() }
            try await waitUntilResumed()
            let sleepDuration = timelineClock.remaining(untilMilliseconds: milliseconds)
            guard sleepDuration > .zero else { return }
            let deadline = min(timelineClock.deadline(untilMilliseconds: milliseconds), ContinuousClock().now.advanced(by: .milliseconds(100)))
            let sleeper = Task<Void, Never>(priority: .high) { @Sendable [deadline] in
                try? await ContinuousClock().sleep(until: deadline, tolerance: .zero)
            }
            delayTask = sleeper
            await sleeper.value
            delayTask = nil
            try Task.checkCancellation()
        }
    }

    private func waitUntilResumed() async throws {
        while isPaused {
            if controllerOutputActive { try controllerOutput.checkHealth() }
            try await Task.sleep(for: .milliseconds(20))
        }
        try Task.checkCancellation()
        try restoreSuspendedInputs()
    }

    private func restoreSuspendedInputs() throws {
        guard !isPaused else { return }
        let position = lastPosition ?? events.currentPosition()
        for button in suspendedButtons {
            try events.postButton(button, down: true, at: position)
            pressedButtons.insert(button)
        }
        for (keyCode, flags) in suspendedKeys {
            let key = KeyboardKey(keyCode: keyCode, displayName: KeyboardKey.name(for: keyCode))
            try events.postKey(key, down: true, flags: flags)
            pressedKeys[keyCode] = flags
        }
        suspendedButtons.removeAll()
        suspendedKeys.removeAll()
        if controllerOutputActive { try controllerOutput.resume() }
    }

    private func releaseActiveInputs() {
        let position = lastPosition ?? events.currentPosition()
        for button in pressedButtons { try? events.postButton(button, down: false, at: position) }
        for keyCode in pressedKeys.keys {
            try? events.postKey(KeyboardKey(keyCode: keyCode, displayName: KeyboardKey.name(for: keyCode)), down: false)
        }
        pressedButtons.removeAll()
        pressedKeys.removeAll()
    }

    private func cleanupAllPressedInputs() {
        releaseActiveInputs()
        suspendedButtons.removeAll()
        suspendedKeys.removeAll()
        if controllerOutputActive { try? controllerOutput.reset() }
    }

    private func primaryControllerName(in macro: CombinedMacro) -> String? {
        var candidates: [String: (count: Int, firstIndex: Int)] = [:]
        for (index, event) in macro.events.enumerated() where event.kind == .controller {
            guard let name = event.controllerName, !name.isEmpty else { continue }
            if let candidate = candidates[name] {
                candidates[name] = (candidate.count + 1, candidate.firstIndex)
            } else {
                candidates[name] = (1, index)
            }
        }
        return candidates.sorted { lhs, rhs in
            if lhs.value.count != rhs.value.count {
                return lhs.value.count > rhs.value.count
            }
            if lhs.value.firstIndex != rhs.value.firstIndex {
                return lhs.value.firstIndex < rhs.value.firstIndex
            }
            return lhs.key < rhs.key
        }.first?.key
    }
}
