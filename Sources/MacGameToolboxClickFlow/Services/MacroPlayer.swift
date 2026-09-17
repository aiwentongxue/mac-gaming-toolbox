import Foundation

struct MacroPlaybackProgress: Sendable {
    var eventIndex: Int
    var eventCount: Int
    var loopIndex: Int
    var loopCount: Int?
}

actor MacroPlayer {
    private let mouseEvents: any MouseEventPosting
    private var runTask: Task<Void, Never>?
    private var delayTask: Task<Void, Never>?
    private var runID: UUID?
    private var isPaused = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var pressedButtons: Set<MouseButton> = []
    private var suspendedButtons: Set<MouseButton> = []
    private var lastPosition: ScreenPoint?
    private var timelineClock = PlaybackTimelineClock()

    init(mouseEvents: any MouseEventPosting = MouseEventService()) {
        self.mouseEvents = mouseEvents
    }

    func start(
        macro: MouseMacro,
        progress: @escaping @Sendable (MacroPlaybackProgress) -> Void,
        completion: @escaping @Sendable (String?) -> Void
    ) {
        guard runTask == nil else { return }
        guard !macro.events.isEmpty else {
            completion(cf("error.emptyMacro"))
            return
        }
        do { try MacroExchange.validate(.mouse(macro)) }
        catch {
            completion(error.localizedDescription)
            return
        }
        lastPosition = nil
        let currentRunID = UUID()
        runID = currentRunID
        runTask = Task { [weak self] in
            guard let self else { return }
            let error = await self.run(macro: macro, progress: progress)
            await self.cleanupAllPressedButtons()
            await self.finish(id: currentRunID)
            completion(error)
        }
        AppLogger.automation.notice("Macro playback started: \(macro.name, privacy: .public)")
    }

    func stop() async {
        let task = runTask
        task?.cancel()
        delayTask?.cancel()
        isPaused = false
        resumePauseWaiters()
        await task?.value
        if task == nil {
            cleanupAllPressedButtons()
        }
        AppLogger.automation.notice("Macro playback stopped")
    }

    func isRunning() -> Bool { runTask != nil }

    func togglePause() -> Bool? {
        guard runTask != nil else { return nil }
        if isPaused {
            timelineClock.resume()
            isPaused = false
            resumePauseWaiters()
            AppLogger.automation.notice("Macro playback resumed")
        } else {
            isPaused = true
            timelineClock.pause()
            delayTask?.cancel()
            suspendedButtons = pressedButtons
            releaseActiveButtons()
            AppLogger.automation.notice("Macro playback paused")
        }
        return isPaused
    }

    private func finish(id: UUID) {
        guard runID == id else { return }
        delayTask = nil
        isPaused = false
        timelineClock.resume()
        resumePauseWaiters()
        runTask = nil
        runID = nil
    }

    private func run(
        macro: MouseMacro,
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
                        try restoreSuspendedButtons()
                    }
                    try post(event)
                    progress(
                        MacroPlaybackProgress(
                            eventIndex: index + 1,
                            eventCount: macro.events.count,
                            loopIndex: loopIndex,
                            loopCount: totalLoops
                        )
                    )
                }

                // Each iteration starts with released input, including incomplete recordings.
                cleanupAllPressedButtons()
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
            AppLogger.automation.error("Macro playback failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    private func post(_ event: MacroEvent) throws {
        if let position = event.position {
            lastPosition = position
        }
        let position = event.position ?? lastPosition ?? mouseEvents.currentPosition()
        switch event.kind {
        case .mouseMove:
            try mouseEvents.postMove(to: position, dragging: pressedButtons.first)
        case .mouseDown:
            guard let button = event.button else { return }
            try mouseEvents.postButton(button, down: true, at: position)
            pressedButtons.insert(button)
        case .mouseUp:
            guard let button = event.button else { return }
            try mouseEvents.postButton(button, down: false, at: position)
            pressedButtons.remove(button)
        case .scroll:
            try mouseEvents.postScroll(
                deltaX: event.scrollDeltaX ?? 0,
                deltaY: event.scrollDeltaY ?? 0,
                at: position
            )
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
        try restoreSuspendedButtons()
    }

    private func resumePauseWaiters() {
        let waiters = pauseWaiters
        pauseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func restoreSuspendedButtons() throws {
        guard !isPaused, !suspendedButtons.isEmpty else { return }
        let position = lastPosition ?? mouseEvents.currentPosition()
        for button in suspendedButtons {
            try mouseEvents.postButton(button, down: true, at: position)
            pressedButtons.insert(button)
        }
        suspendedButtons.removeAll()
    }

    private func releaseActiveButtons() {
        let position = lastPosition ?? mouseEvents.currentPosition()
        for button in pressedButtons {
            try? mouseEvents.postButton(button, down: false, at: position)
        }
        pressedButtons.removeAll()
    }

    private func cleanupAllPressedButtons() {
        releaseActiveButtons()
        suspendedButtons.removeAll()
    }

}
