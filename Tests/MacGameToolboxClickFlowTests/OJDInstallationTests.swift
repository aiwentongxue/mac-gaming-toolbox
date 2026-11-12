import Foundation
import XCTest
@testable import MacGameToolboxClickFlow

final class OJDInstallationTests: XCTestCase {
    private func fixture() throws -> (URL, OJDService, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClickFlow-install-tests-\(UUID().uuidString)")
        let source = root.appendingPathComponent("download/OpenJoystickDriver.app")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("official fixture".utf8).write(to: source.appendingPathComponent("verified"))
        let paths = OJDPaths(supportURL: root.appendingPathComponent("Application Support/ClickFlow/OJD"),
                             legacyAppURL: root.appendingPathComponent("Applications/OpenJoystickDriver.app"))
        let operations = OJDInstallOperations(verify: { app in
            guard try Data(contentsOf: app.appendingPathComponent("verified")) == Data("official fixture".utf8) else {
                throw OJDError(detail: "Invalid fixture signature")
            }
        }, copy: { try FileManager.default.copyItem(at: $0, to: $1) }, trash: { _ in throw OJDError(detail: "Trash unavailable") })
        let service = OJDService(paths: paths, operations: operations, runtime: OJDRuntime(instances: { [] }, terminate: { _ in false }))
        return (root, service, source)
    }

    func testFreshInstallAndRepeatedInstallStayInsideSupportDirectory() async throws {
        let (root, service, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try await service.install(from: source)
        XCTAssertEqual(first, .installed)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: service.paths.cliURL.path), service.paths.executable(in: service.paths.appURL).path)
        let again = try await service.install(from: root.appendingPathComponent("missing"))
        XCTAssertEqual(again, .reused)
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.paths.legacyAppURL.deletingLastPathComponent().path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: service.paths.supportURL.path).sorted(), ["OpenJoystickDriver.app", "ojd"])
        XCTAssertTrue(OJDPaths.current.appURL.path.hasPrefix(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].path))
    }

    func testLegacyMigrationPreservesOriginalAndAtomicallyUpdatesKnownLink() async throws {
        let (root, service, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: service.paths.legacyAppURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: service.paths.legacyAppURL)
        try FileManager.default.createDirectory(at: service.paths.supportURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: service.paths.cliURL, withDestinationURL: service.paths.executable(in: service.paths.legacyAppURL))
        let result = try await service.install()
        XCTAssertEqual(result, .migrated)
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.paths.legacyAppURL.path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: service.paths.cliURL.path), service.paths.executable(in: service.paths.appURL).path)
    }

    func testUnrelatedCommandFileAndLinkAreNeverOverwritten() throws {
        let (root, service, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: service.paths.supportURL, withIntermediateDirectories: true)
        let content = Data("user file".utf8)
        try content.write(to: service.paths.cliURL)
        XCTAssertThrowsError(try service.cli())
        XCTAssertEqual(try Data(contentsOf: service.paths.cliURL), content)
        try FileManager.default.removeItem(at: service.paths.cliURL)
        try FileManager.default.createSymbolicLink(atPath: service.paths.cliURL.path, withDestinationPath: "/other/ojd")
        XCTAssertThrowsError(try service.cli())
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: service.paths.cliURL.path), "/other/ojd")
    }

    func testInvalidLegacyIsPreservedAndNotInstalled() async throws {
        let (root, service, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: service.paths.legacyAppURL, withIntermediateDirectories: true)
        do { try await service.install(); XCTFail("Must reject unverified legacy copy") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.paths.legacyAppURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.paths.appURL.path))
    }

    func testFailedCopyAndFailedStagedVerificationLeaveNoPartialBundle() async throws {
        let (root, initial, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for corrupt in [false, true] {
            var service = initial
            service.operations.copy = { _, target in
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                if !corrupt { throw OJDError(detail: "Disk full") }
            }
            do { try await service.install(from: source); XCTFail("Must not install partial copy") } catch {}
            XCTAssertFalse(FileManager.default.fileExists(atPath: service.paths.appURL.path))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: service.paths.supportURL.path), [])
        }
        _ = try await initial.install(from: source)
        var noOverwrite = initial
        noOverwrite.operations.copy = { _, _ in XCTFail("Must not overwrite installed copy") }
        let reused = try await noOverwrite.install(from: source)
        XCTAssertEqual(reused, .reused)
    }

    func testExternalServiceBlocksConnectionWithoutExecutingCLI() throws {
        let (root, initial, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var service = initial
        let running = InstallRuntimeState([OJDRunningInstance(pid: 123, executableURL: service.paths.executable(in: service.paths.legacyAppURL))])
        service.runtime = running.runtime
        service.operations.verify = { _ in }
        service.command = { _, _, _ in XCTFail("External service must not be silently reused"); return Data() }
        XCTAssertThrowsError(try service.start())
        XCTAssertThrowsError(try service.status())
        XCTAssertEqual(running.quitCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testCancelledSwitchAndForeignLocationDoNotQuitAnything() throws {
        let (root, initial, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let running = InstallRuntimeState([OJDRunningInstance(pid: 123, executableURL: URL(fileURLWithPath: "/other/OJD.app/Contents/MacOS/OpenJoystickDriver"))])
        var service = initial
        service.runtime = running.runtime
        service.operations.verify = { _ in }
        XCTAssertThrowsError(try service.switchService(confirmed: false)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertThrowsError(try service.switchService(confirmed: true))
        XCTAssertEqual(running.quitCount, 0)
    }

    func testNormalSwitchChecksNewProcessAndUncooperativeServiceIsNotKilled() throws {
        let (root, initial, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var service = initial
        let running = InstallRuntimeState([OJDRunningInstance(pid: 123, executableURL: service.paths.executable(in: service.paths.legacyAppURL))])
        service.runtime = running.runtime
        service.operations.verify = { _ in }
        let privateInstance = OJDRunningInstance(pid: 456, executableURL: service.paths.executable(in: service.paths.appURL))
        service.command = { _, args, _ in
            if args.contains("start") { running.set([privateInstance]) }
            return Self.statusData
        }
        running.refuseQuit = true
        XCTAssertThrowsError(try service.switchService(confirmed: true, timeout: 0.01))
        XCTAssertEqual(running.quitCount, 1)
        running.refuseQuit = false
        try service.switchService(confirmed: true)
        try service.requirePrivateService()
        XCTAssertEqual(running.quitCount, 2)
    }

    func testTrashFailurePreservesLegacyAndRequiresInputConfirmation() async throws {
        let (root, initial, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var service = initial
        try FileManager.default.createDirectory(at: service.paths.legacyAppURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: service.paths.legacyAppURL)
        _ = try await service.install()
        let own = OJDRunningInstance(pid: 456, executableURL: service.paths.executable(in: service.paths.appURL))
        service.runtime = OJDRuntime(instances: { [own] }, terminate: { _ in XCTFail(); return false })
        service.command = { _, _, _ in Self.statusData }
        XCTAssertThrowsError(try service.trashLegacy(inputConfirmed: false))
        XCTAssertThrowsError(try service.trashLegacy(inputConfirmed: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.paths.legacyAppURL.path))
        try service.verify()
        // Test the success path using an isolated, recoverable test Trash directory.
        let testTrash = root.appendingPathComponent("Trash.app")
        service.operations.trash = { try FileManager.default.moveItem(at: $0, to: testTrash) }
        try service.trashLegacy(inputConfirmed: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.paths.legacyAppURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: testTrash.path))
    }

    func testPrivateCLIStartAndStatusDisableVendorLegacyForwarding() async throws {
        let (root, service, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = service.paths.executable(in: source)
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = "#!/bin/sh\n[ \"$OJD_RUN_REPOSITORY_CLI\" = 1 ] || exit 42\nprintf '%s' '" + String(decoding: Self.statusData, as: UTF8.self) + "'\n"
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        _ = try await service.install(from: source)
        var runningService = service
        let own = OJDRunningInstance(pid: 456, executableURL: service.paths.executable(in: service.paths.appURL))
        runningService.runtime = OJDRuntime(instances: { [own] }, terminate: { _ in false })
        XCTAssertEqual(try runningService.start(), service.paths.cliURL)
        XCTAssertEqual(try runningService.status(), Self.statusData)
    }

    private static let statusData = Data(#"{"service":{"state":"Running","version":"0.6.0-alpha.1"},"permissions":{"inputRead":"Granted","inputInject":"Granted"}}"#.utf8)
}

private final class InstallRuntimeState: @unchecked Sendable {
    private let lock = NSLock()
    private var instances: [OJDRunningInstance]
    private var quits = 0
    var refuseQuit = false
    init(_ instances: [OJDRunningInstance]) { self.instances = instances }
    var quitCount: Int { lock.withLock { quits } }
    func set(_ instances: [OJDRunningInstance]) { lock.withLock { self.instances = instances } }
    var runtime: OJDRuntime {
        OJDRuntime(instances: { self.lock.withLock { self.instances } }, terminate: { instance in
            self.lock.withLock {
                self.quits += 1
                if !self.refuseQuit { self.instances.removeAll { $0 == instance } }
                return true
            }
        })
    }
}
