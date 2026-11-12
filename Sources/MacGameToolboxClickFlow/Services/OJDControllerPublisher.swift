import Foundation
import Darwin

protocol OJDFrameTransport: Sendable {
    func send(_ state: CrossOverXInputState) throws
    func checkHealth() throws
    func close()
}

/// One persistent CLI and one serialized writer. Frames are paced instead of
/// queued in memory; no multi-second hold is submitted to the service.
final class OJDCLITransport: OJDFrameTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private let input = Pipe()
    private var lastWrite: ContinuousClock.Instant?
    private var closed = false
    private var started = false
    private let minimumFrameSeconds: TimeInterval
    private let errorURL: URL
    private let errorFile: FileHandle

    init(cli: URL, minimumFrameSeconds: TimeInterval = 0.010) throws {
        self.minimumFrameSeconds = minimumFrameSeconds
        errorURL = FileManager.default.temporaryDirectory.appendingPathComponent("ClickFlow-OJD-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        errorFile = try FileHandle(forWritingTo: errorURL)
        process.executableURL = cli
        process.environment = OJDService.cliEnvironment
        process.arguments = ["--json", "--no-input", "--no-color", "--timeout", "2", "virtual", "feed", "--as", "game-controller-compatible"]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorFile
        try process.run()
        started = true
        let fd = input.fileHandleForWriting.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        _ = fcntl(fd, F_SETNOSIGPIPE, 1)
    }

    deinit { close(); try? errorFile.close(); try? FileManager.default.removeItem(at: errorURL) }

    func checkHealth() throws {
        try lock.withLock { try requireRunning() }
    }

    private func requireRunning() throws {
        guard !closed, process.isRunning else {
            let detail = (try? Data(contentsOf: errorURL)) ?? Data()
            throw OJDError(detail: cf("ojd.error.disconnected") + "\n" + String(decoding: detail.suffix(2048), as: UTF8.self))
        }
    }

    func send(_ state: CrossOverXInputState) throws {
        try lock.withLock {
            try requireRunning()
            if let lastWrite {
                let elapsed = ContinuousClock().now - lastWrite
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                if seconds < minimumFrameSeconds { Thread.sleep(forTimeInterval: minimumFrameSeconds - seconds) }
            }
            var data = try JSONEncoder().encode(OJDFrame(state: state))
            data.append(10)
            let fd = input.fileHandleForWriting.fileDescriptor
            let deadline = Date().addingTimeInterval(0.25)
            try data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    if count > 0 { offset += count; continue }
                    if count < 0, errno == EINTR { continue }
                    guard count < 0, errno == EAGAIN || errno == EWOULDBLOCK else { throw OJDError.message("ojd.error.disconnected") }
                    guard Date() < deadline else { throw OJDError.message("ojd.error.timeout") }
                    var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    _ = poll(&descriptor, 1, 10)
                }
            }
            lastWrite = ContinuousClock().now
        }
    }

    func close() {
        lock.withLock {
            guard !closed else { return }
            closed = true
            // SIGTERM invokes CLI shutdown cleanup rather than draining stdin's old frames.
            if process.isRunning { process.terminate() }
            try? input.fileHandleForWriting.close()
            let deadline = Date().addingTimeInterval(3)
            while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            if started { process.waitUntilExit() }
        }
    }
}

final class OJDControllerPublisher: ControllerOutputPublishing, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let physical: any PhysicalControllerStateProviding
    private var transport: (any OJDFrameTransport)?
    private var mixer: CrossOverXInputPublisher?

    init(physical: any PhysicalControllerStateProviding = GameControllerPhysicalStateProvider()) { self.physical = physical }
    var isConnected: Bool { lock.withLock { transport != nil && (try? checkHealth()) != nil } }
    var hasTransport: Bool { lock.withLock { transport != nil } }

    func connect(transport: any OJDFrameTransport) throws {
        try lock.withLock {
            guard self.transport == nil else { return }
            self.transport = transport
            let mixer = CrossOverXInputPublisher(physicalController: physical, pollInterval: .milliseconds(16), stateSink: { state, _ in
                try transport.checkHealth()
                try transport.send(state)
            })
            self.mixer = mixer
            do { try mixer.startPhysicalPassthrough() }
            catch { disconnect(); throw error }
        }
    }

    func disconnect() {
        lock.withLock {
            try? mixer?.end()
            mixer?.stopPhysicalPassthrough()
            mixer = nil
            transport?.close(); transport = nil
        }
    }
    func begin(primaryControllerName: String?) throws {
        try lock.withLock { try checkHealth(); try mixer?.begin(primaryControllerName: primaryControllerName) }
    }
    func apply(controllerName: String?, controlName: String?, value: Float?) throws {
        try lock.withLock { try checkHealth(); try mixer?.apply(controllerName: controllerName, controlName: controlName, value: value) }
    }
    func applyBatch(_ events: [CombinedMacroEvent]) throws {
        try lock.withLock { try checkHealth(); try mixer?.applyBatch(events) }
    }
    func pause() throws { try lock.withLock { try checkHealth(); try mixer?.pause() } }
    func resume() throws { try lock.withLock { try checkHealth(); try mixer?.resume() } }
    func reset() throws { try lock.withLock { try checkHealth(); try mixer?.reset() } }
    func end() throws { try lock.withLock { try mixer?.end() } }
    func checkHealth() throws {
        try lock.withLock {
            guard let transport else { throw OJDError.message("ojd.error.disconnected") }
            try transport.checkHealth(); try mixer?.checkHealth()
        }
    }
}

final class ControllerOutputRouter: ControllerOutputPublishing, @unchecked Sendable {
    let xinput = CrossOverXInputPublisher()
    let ojd = OJDControllerPublisher()
    private let lock = NSRecursiveLock()
    private var backend: ControllerOutputBackend = .xinput
    private var active: any ControllerOutputPublishing { backend == .xinput ? xinput : ojd }
    var isOJDConnected: Bool { ojd.isConnected }
    var hasOJDFeed: Bool { ojd.hasTransport }

    func startPhysicalPassthrough() throws { try xinput.startPhysicalPassthrough() }
    func stopPhysicalPassthrough() { disconnectOJD(); xinput.stopPhysicalPassthrough() }

    func connectOJD() throws {
        try lock.withLock {
            if ojd.isConnected { return }
            ojd.disconnect()
            ControllerDeviceRegistry.shared.endFeed()
            ControllerDeviceRegistry.shared.beginFeed()
            xinput.stopPhysicalPassthrough()
            do {
                let cli = try OJDService().start()
                try ojd.connect(transport: OJDCLITransport(cli: cli))
                let deadline = Date().addingTimeInterval(4)
                while !ControllerDeviceRegistry.shared.hasFeedDevice(), Date() < deadline {
                    try ojd.checkHealth()
                    Thread.sleep(forTimeInterval: 0.02)
                }
                guard ControllerDeviceRegistry.shared.hasFeedDevice() else {
                    throw OJDError.message("ojd.error.notEnumerated")
                }
            } catch {
                ojd.disconnect()
                ControllerDeviceRegistry.shared.endFeed()
                try? xinput.startPhysicalPassthrough()
                throw error
            }
        }
    }
    func disconnectOJD() {
        lock.withLock {
            ojd.disconnect()
            ControllerDeviceRegistry.shared.endFeed()
            try? xinput.startPhysicalPassthrough()
        }
    }
    func selectBackend(_ backend: ControllerOutputBackend) throws {
        try lock.withLock {
            if backend == .ojd { try connectOJD() }
            else { disconnectOJD() }
            self.backend = backend
        }
    }
    func begin(primaryControllerName: String?) throws { try lock.withLock { try active.begin(primaryControllerName: primaryControllerName) } }
    func apply(controllerName: String?, controlName: String?, value: Float?) throws {
        try lock.withLock { try active.apply(controllerName: controllerName, controlName: controlName, value: value) }
    }
    func applyBatch(_ events: [CombinedMacroEvent]) throws { try lock.withLock { try active.applyBatch(events) } }
    func pause() throws { try lock.withLock { try active.pause() } }
    func resume() throws { try lock.withLock { try active.resume() } }
    func reset() throws { try lock.withLock { try active.reset() } }
    func end() throws { try lock.withLock { try active.end() } }
    func checkHealth() throws { try lock.withLock { try active.checkHealth() } }
}
