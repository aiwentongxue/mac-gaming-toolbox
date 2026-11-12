@preconcurrency import GameController
import Foundation
import XCTest
@testable import MacGameToolboxClickFlow

final class OJDControllerTests: XCTestCase {
    func testLegacyMacroMigratesAndNewModeSurvivesExchange() throws {
        let macro = CombinedMacro(name: "Native", events: [CombinedMacroEvent(timestampMilliseconds: 0, kind: .controller, controlName: "buttonA", controlValue: 1)], controllerBackend: .ojd)
        let encoded = try MacroExchange.encode(.combined(macro))
        guard case .combined(let decoded) = try MacroExchange.decode(encoded) else { return XCTFail() }
        XCTAssertEqual(decoded.controllerBackend, .ojd)
        XCTAssertEqual(decoded.schemaVersion, 2)
        guard case .combined(let copy) = SharedMacro.combined(decoded).importedCopy() else { return XCTFail() }
        XCTAssertEqual(copy.controllerBackend, .ojd)
        XCTAssertNotEqual(copy.id, decoded.id)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var legacy = try XCTUnwrap(envelope["combinedMacro"] as? [String: Any])
        legacy["schemaVersion"] = 1; legacy.removeValue(forKey: "controllerBackend")
        envelope["combinedMacro"] = legacy
        guard case .combined(let migrated) = try MacroExchange.decode(JSONSerialization.data(withJSONObject: envelope)) else { return XCTFail() }
        XCTAssertEqual(migrated.controllerBackend, .xinput)
        XCTAssertEqual(migrated.schemaVersion, 2)
        legacy["schemaVersion"] = 2; legacy["controllerBackend"] = "future"
        envelope["combinedMacro"] = legacy
        XCTAssertThrowsError(try MacroExchange.decode(JSONSerialization.data(withJSONObject: envelope)))
    }

    func testCompleteFrameMapsButtonsTriggersDpadAndYDirection() throws {
        var state = CrossOverXInputState()
        for (name, value): (String, Float) in [("buttonA", 1), ("rightShoulder", 1), ("menu", 1), ("leftTrigger", 0.5), ("dpad.y", 1), ("leftThumbstick.y", 1), ("rightThumbstick.x", -1)] {
            state.apply(controlName: name, value: value)
        }
        let frame = OJDFrame(state: state)
        XCTAssertEqual(Set(frame.buttons), ["South", "RightShoulder", "Start"])
        XCTAssertEqual(frame.dpad, ["DpadUp"])
        XCTAssertEqual(frame.axes["LeftStickY"], -1)
        XCTAssertEqual(frame.axes["RightStickX"], -1)
        XCTAssertEqual(frame.axes["LeftTrigger"]!, 0.5, accuracy: 1.0 / 255)
        XCTAssertEqual(frame.axes["RightTrigger"], 0)
        XCTAssertEqual(frame.axes.count, 6)
        let neutral = OJDFrame(state: CrossOverXInputState())
        XCTAssertTrue(neutral.buttons.isEmpty)
        XCTAssertTrue(neutral.axes.values.allSatisfy { $0 == 0 })
    }

    func testOJDPhysicalMixPauseStopAndFailure() throws {
        var physical = CrossOverXInputState()
        physical.apply(controlName: "leftThumbstick.x", value: 0.7)
        physical.apply(controlName: "buttonB", value: 1)
        let source = FixedPhysicalState(state: physical)
        let transport = RecordingOJDTransport()
        let publisher = OJDControllerPublisher(physical: source)
        try publisher.connect(transport: transport)
        defer { publisher.disconnect() }
        try publisher.begin(primaryControllerName: "recorded")
        try publisher.apply(controllerName: "recorded", controlName: "buttonA", value: 1)
        XCTAssertEqual(transport.last?.buttons, physical.buttons | 0x1000)
        XCTAssertEqual(transport.last?.leftStickX, physical.leftStickX)
        try publisher.apply(controllerName: "other", controlName: "buttonX", value: 1)
        XCTAssertEqual(transport.last?.buttons, physical.buttons | 0x1000)
        try publisher.pause()
        XCTAssertEqual(transport.last, physical)
        try publisher.resume()
        XCTAssertEqual(transport.last?.buttons, physical.buttons | 0x1000)
        try publisher.apply(controllerName: "recorded", controlName: "buttonA", value: 0)
        XCTAssertEqual(transport.last, physical)
        try publisher.end()
        XCTAssertEqual(transport.last, physical)
        transport.fail()
        XCTAssertTrue(publisher.hasTransport)
        XCTAssertFalse(publisher.isConnected)
        XCTAssertThrowsError(try publisher.checkHealth())
        XCTAssertThrowsError(try publisher.begin(primaryControllerName: nil))
        publisher.disconnect()
        XCTAssertFalse(publisher.hasTransport)
        XCTAssertTrue(transport.closed)
    }

    func testFeedOutputCannotBecomePhysicalSourceAndDisconnectDoesNotSwitch() {
        let physical = GCController.withExtendedGamepad()
        let output = GCController.withExtendedGamepad()
        let other = GCController.withExtendedGamepad()
        let inventory = ControllerInventory([physical])
        let registry = ControllerDeviceRegistry(controllers: { inventory.read() }, virtualDeviceIDs: { inventory.read().count > 1 ? [1] : [] })
        XCTAssertTrue(registry.selectedController(preferredName: nil) === physical)
        registry.beginFeed()
        inventory.set([physical, output])
        XCTAssertTrue(registry.hasFeedDevice())
        inventory.set([physical, output, other])
        XCTAssertEqual(registry.physicalControllers().count, 1)
        inventory.set([output, other])
        XCTAssertNil(registry.selectedController(preferredName: nil))
        registry.endFeed()
        XCTAssertEqual(registry.physicalControllers().count, 1)
        XCTAssertTrue(registry.physicalControllers().first === other)
        inventory.set([physical])
        XCTAssertTrue(registry.selectedController(preferredName: nil) === physical)
    }

    func testPlayerSelectsSavedBackendAndDetectsFailureDuringWait() async throws {
        let spy = BackendSpy()
        let player = CombinedMacroPlayer(controllerOutput: spy)
        let macro = CombinedMacro(name: "Native", events: [
            CombinedMacroEvent(timestampMilliseconds: 0, kind: .controller, controlName: "buttonA", controlValue: 1),
            CombinedMacroEvent(timestampMilliseconds: 10_000, kind: .controller, controlName: "buttonA", controlValue: 0)
        ], controllerBackend: .ojd)
        let completion = expectation(description: "Disconnected feed ends playback")
        await player.start(macro: macro, progress: { _ in }, completion: { error in
            XCTAssertNotNil(error); completion.fulfill()
        })
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(spy.backend, .ojd)
        spy.fail()
        await fulfillment(of: [completion], timeout: 1)
        let running = await player.isRunning()
        XCTAssertFalse(running)
        XCTAssertTrue(spy.ended)
    }

    func testPermissionStatusIsReadFromOJDNotClickFlow() throws {
        let granted = try OJDPermissionStatus.decodeStatus(Data(#"{"permissions":{"inputRead":"Granted","inputInject":"Granted"}}"#.utf8))
        XCTAssertEqual(granted.inputRead, "Granted")
        let denied = try OJDPermissionStatus.decodeStatus(Data(#"{"permissions":{"inputRead":"Denied","inputInject":"Unknown"}}"#.utf8))
        XCTAssertEqual(denied.inputRead, "Denied")
        XCTAssertEqual(denied.inputInject, "Unknown")
        XCTAssertThrowsError(try OJDPermissionStatus.decodeStatus(Data(#"{"permissions":{}}"#.utf8)))
    }

    func testSameTimestampChordPreservesPressAndReleaseEdges() async {
        let spy = BackendSpy()
        let player = CombinedMacroPlayer(controllerOutput: spy)
        let macro = CombinedMacro(name: "Chord", events: [
            CombinedMacroEvent(timestampMilliseconds: 0, kind: .controller, controlName: "buttonA", controlValue: 1),
            CombinedMacroEvent(timestampMilliseconds: 0, kind: .controller, controlName: "buttonB", controlValue: 1),
            CombinedMacroEvent(timestampMilliseconds: 0, kind: .controller, controlName: "a", controlValue: 0),
            CombinedMacroEvent(timestampMilliseconds: 0, kind: .controller, controlName: "buttonB", controlValue: 0)
        ], controllerBackend: .ojd)
        let completion = expectation(description: "Short chord played")
        await player.start(macro: macro, progress: { _ in }, completion: { error in
            XCTAssertNil(error); completion.fulfill()
        })
        await fulfillment(of: [completion], timeout: 2)
        XCTAssertEqual(spy.batches.map { $0.map(\.controlValue) }, [[1, 1], [0, 0]])
    }

    func testStopDoesNotDrainOverdueControllerFrames() async throws {
        let spy = BackendSpy(frameDelay: 0.01)
        let player = CombinedMacroPlayer(controllerOutput: spy)
        let macro = CombinedMacro(name: "Dense frames", events: (0..<2000).map { index in
            CombinedMacroEvent(timestampMilliseconds: 0, kind: .controller, controlName: "buttonA", controlValue: index.isMultiple(of: 2) ? 1 : 0)
        }, controllerBackend: .ojd)
        await player.start(macro: macro, progress: { _ in }, completion: { _ in })
        try await Task.sleep(for: .milliseconds(40))
        let clock = ContinuousClock()
        let start = clock.now
        await player.stop()
        XCTAssertLessThan(clock.now - start, .seconds(1))
        XCTAssertLessThan(spy.batches.count, 100)
        XCTAssertTrue(spy.ended)
    }

    func testCLIWriteFailureAndCloseAreBounded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = directory.appendingPathComponent("ojd")
        try Data("#!/bin/sh\nexec /bin/sleep 10\n".utf8).write(to: fake)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let transport = try OJDCLITransport(cli: fake, minimumFrameSeconds: 0)
        let clock = ContinuousClock()
        let began = clock.now
        XCTAssertThrowsError(try { for _ in 0..<1000 { try transport.send(CrossOverXInputState()) } }())
        transport.close()
        XCTAssertLessThan(clock.now - began, .seconds(5))
        XCTAssertThrowsError(try transport.checkHealth())
        transport.close()
    }
}

private final class FixedPhysicalState: PhysicalControllerStateProviding, @unchecked Sendable {
    let state: CrossOverXInputState
    init(state: CrossOverXInputState) { self.state = state }
    func currentState(preferredControllerName: String?) -> CrossOverXInputState? { state }
}

private final class RecordingOJDTransport: OJDFrameTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var states: [CrossOverXInputState] = []
    private var failed = false
    private var isClosed = false
    var last: CrossOverXInputState? { lock.withLock { states.last } }
    var closed: Bool { lock.withLock { isClosed } }
    func send(_ state: CrossOverXInputState) throws { try lock.withLock { if failed { throw OJDError(detail: "failure") }; states.append(state) } }
    func checkHealth() throws { try lock.withLock { if failed || isClosed { throw OJDError(detail: "failure") } } }
    func fail() { lock.withLock { failed = true } }
    func close() { lock.withLock { isClosed = true } }
}

private final class ControllerInventory: @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [GCController]
    init(_ devices: [GCController]) { self.devices = devices }
    func read() -> [GCController] { lock.withLock { devices } }
    func set(_ devices: [GCController]) { lock.withLock { self.devices = devices } }
}

private final class BackendSpy: ControllerOutputPublishing, @unchecked Sendable {
    private let lock = NSLock()
    private let frameDelay: TimeInterval
    private var selected: ControllerOutputBackend?
    private var failed = false
    private var didEnd = false
    private var recordedBatches: [[CombinedMacroEvent]] = []
    init(frameDelay: TimeInterval = 0) { self.frameDelay = frameDelay }
    var backend: ControllerOutputBackend? { lock.withLock { selected } }
    var ended: Bool { lock.withLock { didEnd } }
    var batches: [[CombinedMacroEvent]] { lock.withLock { recordedBatches } }
    func selectBackend(_ backend: ControllerOutputBackend) throws { lock.withLock { selected = backend } }
    func begin(primaryControllerName: String?) throws {}
    func apply(controllerName: String?, controlName: String?, value: Float?) throws {}
    func applyBatch(_ events: [CombinedMacroEvent]) throws {
        if frameDelay > 0 { Thread.sleep(forTimeInterval: frameDelay) }
        lock.withLock { recordedBatches.append(events) }
    }
    func pause() throws {}
    func resume() throws {}
    func reset() throws {}
    func end() throws { lock.withLock { didEnd = true } }
    func fail() { lock.withLock { failed = true } }
    func checkHealth() throws { try lock.withLock { if failed { throw OJDError(detail: "Disconnected") } } }
}
