import CoreGraphics
import Foundation

actor CombinedMacroPlayer {
    private let events: any MouseEventPosting
    private var runTask: Task<Void, Never>?
    private var delayTask: Task<Void, Never>?
    private var runID: UUID?
    private var isPaused = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var pressedButtons: Set<MouseButton> = []
    private var pressedKeys: [UInt16: CGEventFlags] = [:]
    private var suspendedButtons: Set<MouseButton> = []
    private var suspendedKeys: [UInt16: CGEventFlags] = [:]
    private var lastPosition: ScreenPoint?
    private var timelineClock = PlaybackTimelineClock()

    init(events: any MouseEventPosting = MouseEventService()) {
        self.events = events
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
        resumePauseWaiters()
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
            resumePauseWaiters()
            AppLogger.automation.notice("Combined macro playback resumed")
        } else {
            isPaused = true
            timelineClock.pause()
            delayTask?.cancel()
            suspendedButtons = pressedButtons
            suspendedKeys = pressedKeys
            releaseActiveInputs()
            AppLogger.automation.notice("Combined macro playback paused")
        }
        return isPaused
    }

    private func finish(_ id: UUID) {
        guard runID == id else { return }
        delayTask = nil
        isPaused = false
        timelineClock.resume()
        resumePauseWaiters()
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
            while !Task.isCancelled {
                if let totalLoops, loopIndex >= totalLoops { break }
                loopIndex += 1
                timelineClock.restart()
                for (index, event) in macro.events.enumerated() {
                    try Task.checkCancellation()
                    try await pauseAwareSleep(untilMilliseconds: PlaybackTiming.scaledMilliseconds(
                        event.timestampMilliseconds,
                        speed: macro.playbackSpeed
                    ))
                    if isPaused {
                        try await waitUntilResumed()
                    } else {
                        try restoreSuspendedInputs()
                    }
                    try post(event)
                    progress(MacroPlaybackProgress(
                        eventIndex: index + 1,
                        eventCount: macro.events.count,
                        loopIndex: loopIndex,
                        loopCount: totalLoops
                    ))
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
            // GameController exposes controller state to the foreground app, but
            // does not provide a public API for injecting it into another app.
            break
        }
    }

    private func pauseAwareSleep(untilMilliseconds milliseconds: Double) async throws {
        while true {
            try await waitUntilResumed()
            let sleepDuration = timelineClock.remaining(untilMilliseconds: milliseconds)
            guard sleepDuration > .zero else { return }
            let deadline = timelineClock.deadline(untilMilliseconds: milliseconds)
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
        if isPaused {
            await withCheckedContinuation { continuation in
                pauseWaiters.append(continuation)
            }
        }
        try Task.checkCancellation()
        try restoreSuspendedInputs()
    }

    private func resumePauseWaiters() {
        let waiters = pauseWaiters
        pauseWaiters.removeAll()
        waiters.forEach { $0.resume() }
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
    }
}
