import Foundation

struct MouseMoveSampler: Sendable {
    var minimumIntervalMilliseconds = 16.0
    var minimumDistance = 2.0
    var maximumLatencyMilliseconds = 50.0

    private(set) var lastEmitted: MacroEvent?
    private(set) var pending: MacroEvent?

    mutating func consider(_ event: MacroEvent) -> MacroEvent? {
        guard event.kind == .mouseMove, let position = event.position else { return event }
        guard let last = lastEmitted, let lastPosition = last.position else {
            lastEmitted = event
            pending = nil
            return event
        }

        let elapsed = event.timestampMilliseconds - last.timestampMilliseconds
        let distance = hypot(position.x - lastPosition.x, position.y - lastPosition.y)
        if elapsed >= maximumLatencyMilliseconds ||
            (elapsed >= minimumIntervalMilliseconds && distance >= minimumDistance) {
            lastEmitted = event
            pending = nil
            return event
        }

        pending = event
        return nil
    }

    mutating func flush() -> MacroEvent? {
        defer { pending = nil }
        guard let pending, pending.id != lastEmitted?.id else { return nil }
        lastEmitted = pending
        return pending
    }

    mutating func reset() {
        lastEmitted = nil
        pending = nil
    }
}
