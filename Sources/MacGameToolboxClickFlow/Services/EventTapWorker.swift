import CoreGraphics
import Foundation

struct CapturedMouseInput: Sendable {
    enum Kind: Sendable {
        case move
        case down
        case up
        case scroll
    }

    var timestampNanoseconds: UInt64
    var kind: Kind
    var position: ScreenPoint
    var button: MouseButton?
    var scrollDeltaX: Int32
    var scrollDeltaY: Int32
}
enum EventTapWorkerError: LocalizedError, Sendable {
    case creationFailed

    var errorDescription: String? {
        cf("error.eventTapCreation")
    }
}

final class EventTapWorker: @unchecked Sendable {
    typealias Handler = @Sendable (CapturedMouseInput) -> Void

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var handler: Handler?

    func start(handler: @escaping Handler) throws {
        lock.lock()
        defer { lock.unlock() }
        guard tap == nil else { return }

        let mask = [
            CGEventType.mouseMoved,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel
        ].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

        guard let createdTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: clickFlowEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw EventTapWorkerError.creationFailed
        }

        self.handler = handler
        tap = createdTap
        let workerThread = Thread { [weak self] in self?.runEventLoop() }
        workerThread.name = "ClickFlow.EventTap"
        workerThread.qualityOfService = .userInteractive
        thread = workerThread
        workerThread.start()
    }

    func stop() {
        lock.lock()
        let currentTap = tap
        let currentRunLoop = runLoop
        handler = nil
        tap = nil
        runLoop = nil
        thread = nil
        lock.unlock()

        if let currentTap {
            CGEvent.tapEnable(tap: currentTap, enable: false)
        }
        if let currentRunLoop {
            CFRunLoopStop(currentRunLoop)
            CFRunLoopWakeUp(currentRunLoop)
        }
    }

    fileprivate func receive(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let currentTap = tap
            lock.unlock()
            if let currentTap {
                CGEvent.tapEnable(tap: currentTap, enable: true)
                AppLogger.recording.warning("Event tap was disabled and has been re-enabled")
            }
            return
        }

        guard event.getIntegerValueField(.eventSourceUserData) != MouseEventService.syntheticEventMarker,
              let input = makeInput(type: type, event: event) else {
            return
        }

        lock.lock()
        let currentHandler = handler
        lock.unlock()
        currentHandler?(input)
    }

    private func runEventLoop() {
        lock.lock()
        guard let currentTap = tap else {
            lock.unlock()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, currentTap, 0)
        let currentRunLoop = CFRunLoopGetCurrent()
        runLoop = currentRunLoop
        lock.unlock()

        guard let source else { return }
        CFRunLoopAddSource(currentRunLoop, source, .commonModes)
        CGEvent.tapEnable(tap: currentTap, enable: true)
        CFRunLoopRun()
        CFRunLoopRemoveSource(currentRunLoop, source, .commonModes)
    }

    private func makeInput(type: CGEventType, event: CGEvent) -> CapturedMouseInput? {
        let kind: CapturedMouseInput.Kind
        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            kind = .move
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            kind = .down
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            kind = .up
        case .scrollWheel:
            kind = .scroll
        default:
            return nil
        }

        let location = event.location
        return CapturedMouseInput(
            timestampNanoseconds: event.timestamp,
            kind: kind,
            position: ScreenPoint(x: location.x, y: location.y),
            button: mouseButton(for: type, event: event),
            scrollDeltaX: clampedInt32(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)),
            scrollDeltaY: clampedInt32(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        )
    }

    private func mouseButton(for type: CGEventType, event: CGEvent) -> MouseButton? {
        switch type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged: .left
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: .right
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            event.getIntegerValueField(.mouseEventButtonNumber) == 2 ? .middle : nil
        default: nil
        }
    }

    private func clampedInt32(_ value: Int64) -> Int32 {
        Int32(clamping: value)
    }
}

private let clickFlowEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let worker = Unmanaged<EventTapWorker>.fromOpaque(userInfo).takeUnretainedValue()
    worker.receive(type: type, event: event)
    return Unmanaged.passUnretained(event)
}
