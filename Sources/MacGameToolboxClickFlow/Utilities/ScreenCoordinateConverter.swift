import CoreGraphics

enum ScreenCoordinateConverter {
    static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }

        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return []
        }

        return displays.prefix(Int(count)).map(CGDisplayBounds)
    }

    static func isVisible(_ point: ScreenPoint, in bounds: [CGRect]? = nil) -> Bool {
        let target = CGPoint(x: point.x, y: point.y)
        return (bounds ?? activeDisplayBounds()).contains { $0.contains(target) }
    }

    static func invisibleEventIndices(in macro: MouseMacro, bounds: [CGRect]? = nil) -> [Int] {
        let displayBounds = bounds ?? activeDisplayBounds()
        return macro.events.enumerated().compactMap { index, event in
            guard let position = event.position else { return nil }
            return isVisible(position, in: displayBounds) ? nil : index
        }
    }

    static func invisibleEventIndices(in macro: CombinedMacro, bounds: [CGRect]? = nil) -> [Int] {
        let displayBounds = bounds ?? activeDisplayBounds()
        return macro.events.enumerated().compactMap { index, event in
            guard let position = event.position else { return nil }
            return isVisible(position, in: displayBounds) ? nil : index
        }
    }
}
