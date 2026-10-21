import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import MacGameToolboxClickFlow
#else
@testable import Mac_游戏工具箱
#endif

final class CrossOverGameIntegrationTests: XCTestCase {
    func testVerifiedProfilesUseTheRuntimeValidatedDLLPlans() {
        XCTAssertEqual(CrossOverGamePreset.aniimo.fixedDLLNames, ["xinput1_3.dll"])
        XCTAssertTrue(CrossOverGamePreset.aniimo.disablesWindowsGamingInput)
        XCTAssertEqual(CrossOverGamePreset.aniimo.preferredCrossOverDisplayName, "CrossOver Preview")

        XCTAssertEqual(
            CrossOverGamePreset.genshinImpact.fixedDLLNames,
            ["xinput1_3.dll", "xinput1_4.dll", "xinput9_1_0.dll"]
        )
        XCTAssertFalse(CrossOverGamePreset.genshinImpact.disablesWindowsGamingInput)
        XCTAssertEqual(CrossOverGamePreset.genshinImpact.preferredCrossOverDisplayName, "CrossOver 25.1.1")

        XCTAssertEqual(
            CrossOverGamePreset.zenlessZoneZero.fixedDLLNames,
            ["xinput1_3.dll", "xinput1_4.dll"]
        )
        XCTAssertTrue(CrossOverGamePreset.zenlessZoneZero.disablesWindowsGamingInput)
        XCTAssertEqual(CrossOverGamePreset.zenlessZoneZero.preferredCrossOverDisplayName, "CrossOver")
    }

    func testUnknownGameDetectsXInputWithBinarySafeCaseInsensitiveScan() async throws {
        let fixture = try CrossOverIntegrationFixture()
        defer { fixture.remove() }
        let unknownGame = fixture.gameDirectory.appendingPathComponent("UnknownGame.exe")
        try fixture.writePE64(to: unknownGame, imports: ["XINPUT1_4.DLL"])
        let service = fixture.makeService(runner: MockCrossOverCommandRunner())

        let plan = try await service.plan(gameURL: unknownGame, preset: .automatic)

        XCTAssertEqual(plan.preset, .automatic)
        XCTAssertEqual(plan.detectedDLLNames, ["xinput1_4.dll"])
        XCTAssertEqual(plan.dllNames, ["xinput1_4.dll"])
    }

    func testInstallAndRestorePreserveOriginalDLLAndRegistryValues() async throws {
        let fixture = try CrossOverIntegrationFixture()
        defer { fixture.remove() }
        let runner = MockCrossOverCommandRunner(values: ["xinput1_3": "builtin"])
        let service = fixture.makeService(runner: runner)

        let originalDLL = Data("original game DLL".utf8)
        try originalDLL.write(to: fixture.gameDirectory.appendingPathComponent("xinput1_3.dll"))

        let manifest = try await service.install(
            gameURL: fixture.gameURL,
            bottle: fixture.bottle,
            application: fixture.application,
            preset: .aniimo
        )

        XCTAssertEqual(manifest.state, .installed)
        XCTAssertEqual(manifest.files.count, 1)
        XCTAssertTrue(manifest.files[0].originalExisted)
        XCTAssertEqual(
            try Data(contentsOf: fixture.gameDirectory.appendingPathComponent("xinput1_3.dll")),
            fixture.proxyData
        )
        var values = await runner.snapshot()
        XCTAssertEqual(values["xinput1_3"], "native,builtin")
        XCTAssertEqual(values["windows.gaming.input"], "disabled")

        try await service.restore(manifest: manifest)

        XCTAssertEqual(
            try Data(contentsOf: fixture.gameDirectory.appendingPathComponent("xinput1_3.dll")),
            originalDLL
        )
        values = await runner.snapshot()
        XCTAssertEqual(values["xinput1_3"], "builtin")
        XCTAssertNil(values["windows.gaming.input"])
        let restored = await service.manifests().first { $0.id == manifest.id }
        XCTAssertEqual(restored?.state, .restored)
    }

    func testRestoreRefusesToOverwriteAProxyChangedAfterInstallation() async throws {
        let fixture = try CrossOverIntegrationFixture()
        defer { fixture.remove() }
        let runner = MockCrossOverCommandRunner()
        let service = fixture.makeService(runner: runner)
        let manifest = try await service.install(
            gameURL: fixture.gameURL,
            bottle: fixture.bottle,
            application: fixture.application,
            preset: .aniimo
        )
        let target = fixture.gameDirectory.appendingPathComponent("xinput1_3.dll")
        try Data("changed by game update".utf8).write(to: target)

        do {
            try await service.restore(manifest: manifest)
            XCTFail("Restore should stop rather than overwrite a changed DLL")
        } catch let error as CrossOverIntegrationError {
            guard case .unsafeRestore(let name) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(name, "xinput1_3.dll")
        }
        XCTAssertEqual(try Data(contentsOf: target), Data("changed by game update".utf8))
    }

    func testFailedRegistryInstallRollsBackFilesAndEarlierRegistryChanges() async throws {
        let fixture = try CrossOverIntegrationFixture()
        defer { fixture.remove() }
        let runner = MockCrossOverCommandRunner(failOnAddName: "windows.gaming.input")
        let service = fixture.makeService(runner: runner)
        let target = fixture.gameDirectory.appendingPathComponent("xinput1_3.dll")
        let originalDLL = Data("original before failed install".utf8)
        try originalDLL.write(to: target)

        do {
            _ = try await service.install(
                gameURL: fixture.gameURL,
                bottle: fixture.bottle,
                application: fixture.application,
                preset: .aniimo
            )
            XCTFail("Install should surface the registry failure")
        } catch {
            XCTAssertTrue(error is CrossOverIntegrationError)
        }

        XCTAssertEqual(try Data(contentsOf: target), originalDLL)
        let values = await runner.snapshot()
        XCTAssertNil(values["xinput1_3"])
        XCTAssertNil(values["windows.gaming.input"])
        let manifests = await service.manifests()
        let manifest = try XCTUnwrap(manifests.first)
        XCTAssertEqual(manifest.state, .restored)
    }
}

private final class CrossOverIntegrationFixture: @unchecked Sendable {
    let root: URL
    let gameDirectory: URL
    let gameURL: URL
    let proxyRootURL: URL
    let recordsRootURL: URL
    let bottle: ClickFlowCrossOverBottle
    let application: CrossOverApplication
    let proxyData = Data("ClickFlow test XInput proxy".utf8)

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClickFlow-CrossOver-\(UUID().uuidString)", isDirectory: true)
        gameDirectory = root.appendingPathComponent("Game", isDirectory: true)
        gameURL = gameDirectory.appendingPathComponent("Aniimo.exe")
        proxyRootURL = root.appendingPathComponent("Resources", isDirectory: true)
        recordsRootURL = root.appendingPathComponent("Records", isDirectory: true)
        let bottleURL = root.appendingPathComponent("Bottles/aniimo", isDirectory: true)
        let applicationURL = root.appendingPathComponent("CrossOver Test.app", isDirectory: true)
        let wineURL = applicationURL.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine")

        try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: proxyRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: wineURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("registry fixture".utf8).write(to: bottleURL.appendingPathComponent("user.reg"))
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: wineURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wineURL.path)
        try proxyData.write(to: proxyRootURL.appendingPathComponent("x64-xinput1_3.dll"))
        try Self.writePE64(to: gameURL, imports: ["xinput1_3.dll"])

        bottle = ClickFlowCrossOverBottle(name: "aniimo", url: bottleURL, version: "26.3", is64Bit: true)
        application = CrossOverApplication(
            url: applicationURL,
            displayName: "CrossOver Test",
            version: "26.3"
        )
    }

    func makeService(runner: MockCrossOverCommandRunner) -> CrossOverGameIntegrationService {
        CrossOverGameIntegrationService(
            commandRunner: runner,
            proxyRootURL: proxyRootURL,
            recordsRootURL: recordsRootURL
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func writePE64(to url: URL, imports: [String]) throws {
        try Self.writePE64(to: url, imports: imports)
    }

    private static func writePE64(to url: URL, imports: [String]) throws {
        var bytes = Data(repeating: 0, count: 128)
        bytes[0] = 0x4D
        bytes[1] = 0x5A
        bytes[0x3C] = 0x40
        bytes[0x40] = 0x50
        bytes[0x41] = 0x45
        bytes[0x42] = 0
        bytes[0x43] = 0
        bytes[0x44] = 0x64
        bytes[0x45] = 0x86
        bytes.append(Data(imports.joined(separator: "\0").utf8))
        try bytes.write(to: url)
    }
}

private actor MockCrossOverCommandRunner: CrossOverCommandRunning {
    private var values: [String: String]
    private let failOnAddName: String?

    init(values: [String: String] = [:], failOnAddName: String? = nil) {
        self.values = values
        self.failOnAddName = failOnAddName
    }

    func run(executable: URL, arguments: [String]) async throws -> CrossOverCommandResult {
        guard let valueFlag = arguments.firstIndex(of: "/v"),
              arguments.indices.contains(valueFlag + 1) else {
            return .init(terminationStatus: 2, standardOutput: "", standardError: "missing value name")
        }
        let name = arguments[valueFlag + 1]
        if arguments.contains("query") {
            guard let value = values[name] else {
                return .init(terminationStatus: 1, standardOutput: "", standardError: "unable to find")
            }
            return .init(
                terminationStatus: 0,
                standardOutput: "    \(name)    REG_SZ    \(value)\n",
                standardError: ""
            )
        }
        if arguments.contains("add"), let dataFlag = arguments.firstIndex(of: "/d"),
           arguments.indices.contains(dataFlag + 1) {
            if name == failOnAddName {
                return .init(terminationStatus: 1, standardOutput: "", standardError: "injected failure")
            }
            values[name] = arguments[dataFlag + 1]
            return .init(terminationStatus: 0, standardOutput: "", standardError: "")
        }
        if arguments.contains("delete") {
            values.removeValue(forKey: name)
            return .init(terminationStatus: 0, standardOutput: "", standardError: "")
        }
        return .init(terminationStatus: 2, standardOutput: "", standardError: "unsupported command")
    }

    func snapshot() -> [String: String] { values }
}
