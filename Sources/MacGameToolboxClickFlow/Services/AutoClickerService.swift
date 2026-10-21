import Foundation

actor AutoClickerService {
    private let mouseEvents: any MouseEventPosting
    private var runTask: Task<Void, Never>?
    private var runID: UUID?

    init(mouseEvents: any MouseEventPosting = MouseEventService()) {
        self.mouseEvents = mouseEvents
    }

    func start(
        configuration: ClickerConfiguration,
        progress: @escaping @Sendable (Int) -> Void,
        completion: @escaping @Sendable (String?) -> Void
    ) {
        guard runTask == nil else { return }
        let configuration = configuration.sanitizedForExecution()
        let currentRunID = UUID()
        runID = currentRunID
        runTask = Task { [weak self] in
            guard let self else { return }
            let error = await self.run(configuration: configuration, progress: progress)
            await self.finish(id: currentRunID)
            completion(error)
        }
        AppLogger.automation.notice("Auto clicker started")
    }

    func stop() async {
        let task = runTask
        task?.cancel()
        await task?.value
        AppLogger.automation.notice("Auto clicker stopped")
    }

    func isRunning() -> Bool { runTask != nil }

    private func finish(id: UUID) {
        guard runID == id else { return }
        runTask = nil
        runID = nil
    }

    private func run(
        configuration: ClickerConfiguration,
        progress: @escaping @Sendable (Int) -> Void
    ) async -> String? {
        let interval = duration(milliseconds: configuration.intervalMilliseconds)
        let doubleGap = duration(milliseconds: min(80, max(10, configuration.intervalMilliseconds / 4)))
        let clock = ContinuousClock()
        var nextDeadline = clock.now
        var completedClicks = 0

        do {
            while !Task.isCancelled {
                let remaining: Int? = configuration.countMode == .finite
                    ? max(0, configuration.finiteClickCount - completedClicks)
                    : nil
                if remaining == 0 { break }

                let clicksThisRound = ClickExecutionPlanner.clicksThisRound(
                    gesture: configuration.gesture,
                    remaining: remaining
                )
                for clickIndex in 0..<clicksThisRound {
                    try Task.checkCancellation()
                    switch configuration.inputKind {
                    case .mouse:
                        let position = configuration.positionMode == .current
                            ? mouseEvents.currentPosition()
                            : configuration.fixedPosition
                        try mouseEvents.postClick(
                            button: configuration.button,
                            at: position,
                            clickState: Int64(clickIndex + 1)
                        )
                    case .keyboard:
                        try mouseEvents.postKeyPress(configuration.keyboardKey)
                    }
                    completedClicks += 1
                    progress(completedClicks)
                    if clickIndex + 1 < clicksThisRound {
                        try await clock.sleep(for: doubleGap)
                    }
                }

                nextDeadline += interval
                if nextDeadline > clock.now {
                    try await clock.sleep(until: nextDeadline)
                } else {
                    nextDeadline = clock.now
                    await Task.yield()
                }
            }
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            AppLogger.automation.error("Auto clicker failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    private func duration(milliseconds: Double) -> Duration {
        .nanoseconds(Int64(max(0, milliseconds) * 1_000_000))
    }
}
