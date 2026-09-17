import CoreGraphics
import Foundation

struct CapturedSystemInput: Sendable {
    enum Kind: Sendable {
        case mouseMove
        case mouseDown
        case mouseUp
        case scroll
        case keyDown
        case keyUp
    }

    var timestampNanoseconds: UInt64
    var kind: Kind
    var position: ScreenPoint?
    var button: MouseButton?
    var scrollDeltaX: Int32 = 0
    var scrollDeltaY: Int32 = 0
    var keyCode: UInt16?
    var keyboardModifiers: UInt64 = 0
}

final class CombinedEventTapWorker: @unchecked Sendable {
    typealias Handler = @Sendable (CapturedSystemInput) -> Void

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var handler: Handler?

    func start(handler: @escaping Handler) throws {
        lock.lock()
        defer { lock.unlock() }
        guard tap == nil else { return }

        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDragged, .scrollWheel, .keyDown, .keyUp, .flagsChanged
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let createdTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: combinedEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw EventTapWorkerError.creationFailed
        }

        self.handler = handler
        tap = createdTap
        let workerThread = Thread { [weak self] in self?.runEventLoop() }
        workerThread.name = "ClickFlow.CombinedEventTap"
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
        if let currentTap { CGEvent.tapEnable(tap: currentTap, enable: false) }
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
            if let currentTap { CGEvent.tapEnable(tap: currentTap, enable: true) }
            return
        }
        guard event.getIntegerValueField(.eventSourceUserData) != MouseEventService.syntheticEventMarker,
              let input = makeInput(type: type, event: event) else { return }
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

    private func makeInput(type: CGEventType, event: CGEvent) -> CapturedSystemInput? {
        let timestamp = event.timestamp > 0
            ? event.timestamp
            : DispatchTime.now().uptimeNanoseconds
        let location = event.location
        let point = ScreenPoint(x: location.x, y: location.y)
        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return CapturedSystemInput(timestampNanoseconds: timestamp, kind: .mouseMove, position: point)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return CapturedSystemInput(
                timestampNanoseconds: timestamp,
                kind: .mouseDown,
                position: point,
                button: mouseButton(type, event)
            )
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return CapturedSystemInput(
                timestampNanoseconds: timestamp,
                kind: .mouseUp,
                position: point,
                button: mouseButton(type, event)
            )
        case .scrollWheel:
            return CapturedSystemInput(
                timestampNanoseconds: timestamp,
                kind: .scroll,
                position: point,
                scrollDeltaX: Int32(clamping: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)),
                scrollDeltaY: Int32(clamping: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            )
        case .keyDown, .keyUp:
            return CapturedSystemInput(
                timestampNanoseconds: timestamp,
                kind: type == .keyDown ? .keyDown : .keyUp,
                keyCode: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)),
                keyboardModifiers: event.flags.rawValue
            )
        case .flagsChanged:
            let code = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
            return CapturedSystemInput(
                timestampNanoseconds: timestamp,
                kind: modifierIsDown(keyCode: code, flags: event.flags) ? .keyDown : .keyUp,
                keyCode: code,
                keyboardModifiers: event.flags.rawValue
            )
        default:
            return nil
        }
    }

    private func mouseButton(_ type: CGEventType, _ event: CGEvent) -> MouseButton? {
        switch type {
        case .leftMouseDown, .leftMouseUp: .left
        case .rightMouseDown, .rightMouseUp: .right
        case .otherMouseDown, .otherMouseUp:
            event.getIntegerValueField(.mouseEventButtonNumber) == 2 ? .middle : nil
        default: nil
        }
    }

    private func modifierIsDown(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 54, 55: flags.contains(.maskCommand)
        case 56, 60: flags.contains(.maskShift)
        case 58, 61: flags.contains(.maskAlternate)
        case 59, 62: flags.contains(.maskControl)
        case 57: flags.contains(.maskAlphaShift)
        case 63: flags.contains(.maskSecondaryFn)
        default: false
        }
    }
}

private let combinedEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let worker = Unmanaged<CombinedEventTapWorker>.fromOpaque(userInfo).takeUnretainedValue()
    worker.receive(type: type, event: event)
    return Unmanaged.passUnretained(event)
}
