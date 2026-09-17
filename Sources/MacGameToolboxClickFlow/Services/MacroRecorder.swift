import Foundation

struct RecorderProgress: Sendable {
    var elapsedMilliseconds: Double
    var eventCount: Int
}

actor MacroRecorder {
    private let worker: EventTapWorker
    private var events: [MacroEvent] = []
    private var firstTimestampNanoseconds: UInt64?
    private var sampler = MouseMoveSampler()
    private var progressTask: Task<Void, Never>?
    private var progressHandler: (@Sendable (RecorderProgress) -> Void)?
    private var recordingStart: ContinuousClock.Instant?
    private(set) var isRecording = false
    private var recordingMode: MouseRecordingMode = .fullMotion

    init(worker: EventTapWorker = EventTapWorker()) {
        self.worker = worker
    }

    func start(
        mode: MouseRecordingMode = .fullMotion,
        progress: @escaping @Sendable (RecorderProgress) -> Void
    ) throws {
        guard !isRecording else { return }
        events = []
        sampler.reset()
        firstTimestampNanoseconds = nil
        progressHandler = progress
        recordingStart = ContinuousClock().now
        recordingMode = mode

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
        AppLogger.recording.notice("Macro recording started")
    }

    func stop(discardTerminalMouseClick: Bool = false) -> [MacroEvent] {
        guard isRecording else { return events }
        isRecording = false
        worker.stop()
        progressTask?.cancel()
        progressTask = nil
        if let finalMove = sampler.flush() {
            events.append(finalMove)
        }
        progressHandler = nil
        recordingStart = nil
        var result = normalized(events)
        if discardTerminalMouseClick {
            result = RecordingTimeline.removingTerminalControlClick(from: result)
        }
        AppLogger.recording.notice("Macro recording stopped with \(result.count) events")
        return result
    }

    private func consume(_ input: CapturedMouseInput) {
        guard isRecording else { return }
        if !recordingMode.records(macroKind(for: input.kind)) { return }
        if firstTimestampNanoseconds == nil {
            firstTimestampNanoseconds = input.timestampNanoseconds
        }
        let baseline = firstTimestampNanoseconds ?? input.timestampNanoseconds
        let timestamp = Double(input.timestampNanoseconds >= baseline ? input.timestampNanoseconds - baseline : 0) / 1_000_000
        let event = MacroEvent(
            timestampMilliseconds: timestamp,
            kind: macroKind(for: input.kind),
            position: input.position,
            button: input.button,
            scrollDeltaX: input.kind == .scroll ? input.scrollDeltaX : nil,
            scrollDeltaY: input.kind == .scroll ? input.scrollDeltaY : nil
        )

        if input.kind == .move {
            if let sampled = sampler.consider(event) {
                events.append(sampled)
            }
        } else {
            if let pendingMove = sampler.flush() {
                events.append(pendingMove)
            }
            events.append(event)
        }
        publishProgress()
    }

    private func publishProgress() {
        guard isRecording, let recordingStart else { return }
        let elapsed = recordingStart.duration(to: ContinuousClock().now)
        progressHandler?(
            RecorderProgress(
                elapsedMilliseconds: Double(elapsed.components.seconds) * 1_000 +
                    Double(elapsed.components.attoseconds) / 1_000_000_000_000_000,
                eventCount: events.count + (sampler.pending == nil ? 0 : 1)
            )
        )
    }

    private func macroKind(for kind: CapturedMouseInput.Kind) -> MacroEventKind {
        switch kind {
        case .move: .mouseMove
        case .down: .mouseDown
        case .up: .mouseUp
        case .scroll: .scroll
        }
    }

    private func normalized(_ source: [MacroEvent]) -> [MacroEvent] {
        let ordered = source.sorted { $0.timestampMilliseconds < $1.timestampMilliseconds }
        guard let first = ordered.first?.timestampMilliseconds else { return [] }
        return ordered.map { event in
            var copy = event
            copy.timestampMilliseconds = max(0, event.timestampMilliseconds - first)
            return copy
        }
    }
}
