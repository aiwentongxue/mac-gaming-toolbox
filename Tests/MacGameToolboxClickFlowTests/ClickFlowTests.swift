@preconcurrency import Carbon
import CoreGraphics
import XCTest
#if SWIFT_PACKAGE
@testable import MacGameToolboxClickFlow
#else
import SwiftUI
import SwiftData
import AppDropCore
@testable import Mac_游戏工具箱
#endif

final class ClickFlowTests: XCTestCase {
    nonisolated(unsafe) private static var timingActivity: NSObjectProtocol?

    override class func setUp() {
        super.setUp()
        // These tests assert real event timing. Prevent App Nap/timer coalescing
        // while the test host is in the background (for example, behind a game).
        timingActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Validate ClickFlow event timing"
        )
    }

    override class func tearDown() {
        if let timingActivity { ProcessInfo.processInfo.endActivity(timingActivity) }
        timingActivity = nil
        super.tearDown()
    }

    private func waitUntilStopped(
        _ service: AutoClickerService,
        timeout: Duration = .seconds(20)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while await service.isRunning() {
            if clock.now >= deadline {
                XCTFail("Auto clicker did not stop before the timeout")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func waitUntilStopped(
        _ player: MacroPlayer,
        timeout: Duration = .seconds(20)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while await player.isRunning() {
            if clock.now >= deadline {
                XCTFail("Macro player did not stop before the timeout")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func waitUntilStopped(
        _ player: CombinedMacroPlayer,
        timeout: Duration = .seconds(20)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while await player.isRunning() {
            if clock.now >= deadline {
                XCTFail("Combined macro player did not stop before the timeout")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    func testIntervalAndCPSConversion() {
        var configuration = ClickerConfiguration()
        configuration.setInterval(milliseconds: 1_000)
        XCTAssertEqual(configuration.clicksPerSecond, 1, accuracy: 0.000_1)
        configuration.setInterval(milliseconds: 100)
        XCTAssertEqual(configuration.clicksPerSecond, 10, accuracy: 0.000_1)
        configuration.clicksPerSecond = 100
        XCTAssertEqual(configuration.intervalMilliseconds, 10, accuracy: 0.000_1)
    }

    func testUnsafeClickerConfigurationIsClampedBeforeExecution() {
        var configuration = ClickerConfiguration()
        configuration.intervalMilliseconds = -1
        configuration.finiteClickCount = 0
        let safe = configuration.sanitizedForExecution()
        XCTAssertEqual(safe.intervalMilliseconds, 10)
        XCTAssertEqual(safe.finiteClickCount, 1)

        configuration.intervalMilliseconds = .infinity
        XCTAssertEqual(configuration.sanitizedForExecution().intervalMilliseconds, 60_000)
        XCTAssertEqual(ClickerConfiguration.clampedInterval(forCPS: 0), 60_000)
    }

    @MainActor
    func testSettingsPersistAndDamagedSettingsFallBackSafely() throws {
        let suiteName = "ClickFlowTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        var configuration = ClickerConfiguration()
        configuration.button = .middle
        configuration.countMode = .finite
        configuration.finiteClickCount = 10
        configuration.intervalMilliseconds = 100
        store.saveClickerConfiguration(configuration)
        XCTAssertEqual(SettingsStore(defaults: defaults).loadClickerConfiguration(), configuration)

        defaults.set(Data("damaged".utf8), forKey: "clickerConfiguration")
        XCTAssertEqual(SettingsStore(defaults: defaults).loadClickerConfiguration(), ClickerConfiguration())
    }

    @MainActor
    func testControllerPlaybackNoticeIsShownOnlyOnce() throws {
        let suiteName = "ClickFlowTests.ControllerPlaybackNotice.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.shouldShowControllerPlaybackNotice)
        store.markControllerPlaybackNoticeShown()
        XCTAssertFalse(store.shouldShowControllerPlaybackNotice)
        XCTAssertFalse(SettingsStore(defaults: defaults).shouldShowControllerPlaybackNotice)
    }

    @MainActor
    func testWindowsGamesSidebarSelectionMigratesIntoCombinedMacros() throws {
        let suiteName = "ClickFlowTests.WindowsGamesNavigation.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("windowsGames", forKey: "selectedPage")
        XCTAssertEqual(SettingsStore(defaults: defaults).loadSelectedPage(), .combinedMacros)
        XCTAssertEqual(
            SidebarPage.allCases,
            [.clicker, .macros, .combinedMacros, .settings]
        )
    }

    func testMacroStorageSavesReloadsAndDeletesEditedSteps() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = MacroStorage(directoryURL: root)
        var macro = MouseMacro(name: "Saved", events: [.init(timestampMilliseconds: 0, kind: .mouseMove, position: .init(x: 1, y: 2))])
        try await storage.save(macro)
        macro.events.append(.init(timestampMilliseconds: 100, kind: .mouseDown, button: .right))
        try await storage.save(macro)
        let loaded = await storage.loadAll()
        XCTAssertEqual(loaded.macros.count, 1)
        XCTAssertEqual(loaded.macros.first?.id, macro.id)
        XCTAssertEqual(loaded.macros.first?.name, macro.name)
        XCTAssertEqual(loaded.macros.first?.events, macro.events)
        try await storage.delete(id: macro.id)
        let afterDeletion = await storage.loadAll()
        XCTAssertTrue(afterDeletion.macros.isEmpty)
    }

    func testClickerPostsExactFiniteCountsForEveryMouseButton() async throws {
        for button in MouseButton.allCases {
            for count in [1, 10, 100, 1_000] {
                let recorder = RecordedMouseEvents()
                let clicker = AutoClickerService(mouseEvents: recorder)
                var configuration = ClickerConfiguration()
                configuration.button = button
                configuration.countMode = .finite
                configuration.finiteClickCount = count
                configuration.intervalMilliseconds = 10
                await clicker.start(configuration: configuration, progress: { _ in }, completion: { _ in })
                try await waitUntilStopped(clicker)
                let posted = recorder.snapshot()
                XCTAssertEqual(posted.count, count * 2, "\(button) \(count)")
                XCTAssertTrue(posted.allSatisfy { $0.button == button })
                XCTAssertEqual(posted.filter(\.isDown).count, count)
            }
        }
    }

    func testClickerUsesCurrentAndFixedPositionsAndRejectsDuplicateStarts() async throws {
        let recorder = RecordedMouseEvents(currentPosition: .init(x: 12, y: 34))
        let clicker = AutoClickerService(mouseEvents: recorder)
        var configuration = ClickerConfiguration()
        configuration.countMode = .unlimited
        configuration.intervalMilliseconds = 10
        configuration.positionMode = .current
        await clicker.start(configuration: configuration, progress: { _ in }, completion: { _ in })
        await clicker.start(configuration: configuration, progress: { _ in }, completion: { _ in })
        try await Task.sleep(for: .milliseconds(80))
        await clicker.stop()
        let current = recorder.snapshot()
        XCTAssertGreaterThan(current.count, 0)
        XCTAssertLessThan(current.count, 30, "duplicate start must not create a second loop")
        XCTAssertTrue(current.allSatisfy { $0.position == .init(x: 12, y: 34) })

        recorder.reset()
        configuration.positionMode = .fixed
        configuration.fixedPosition = .init(x: -500, y: 250)
        configuration.countMode = .finite
        configuration.finiteClickCount = 1
        await clicker.start(configuration: configuration, progress: { _ in }, completion: { _ in })
        try await waitUntilStopped(clicker)
        XCTAssertTrue(recorder.snapshot().allSatisfy { $0.position == .init(x: -500, y: 250) })
    }

    func testClickerRapidStartStopAndTenMillisecondSixtySecondStress() async throws {
        let recorder = RecordedMouseEvents()
        let clicker = AutoClickerService(mouseEvents: recorder)
        var configuration = ClickerConfiguration()
        configuration.intervalMilliseconds = 10
        configuration.countMode = .unlimited
        for _ in 0..<100 {
            await clicker.start(configuration: configuration, progress: { _ in }, completion: { _ in })
            await clicker.stop()
            let isRunning = await clicker.isRunning()
            XCTAssertFalse(isRunning)
        }
        await clicker.start(configuration: configuration, progress: { _ in }, completion: { _ in })
        try await Task.sleep(for: .seconds(60))
        await clicker.stop()
        let isRunning = await clicker.isRunning()
        XCTAssertFalse(isRunning)
        XCTAssertGreaterThan(recorder.snapshot().count, 10_000)
    }

    func testMacroOrderTimingLoopsAndStopReleasesPressedButton() async throws {
        let recorder = RecordedMouseEvents()
        let player = MacroPlayer(mouseEvents: recorder)
        let macro = MouseMacro(name: "Playback", events: [
            .init(timestampMilliseconds: 0, kind: .mouseMove, position: .init(x: 10, y: 20)),
            .init(timestampMilliseconds: 200, kind: .mouseDown, position: .init(x: 10, y: 20), button: .left),
            .init(timestampMilliseconds: 210, kind: .mouseUp, position: .init(x: 10, y: 20), button: .left),
            .init(timestampMilliseconds: 310, kind: .mouseMove, position: .init(x: -50, y: 40)),
            .init(timestampMilliseconds: 320, kind: .mouseDown, position: .init(x: -50, y: 40), button: .right),
            .init(timestampMilliseconds: 330, kind: .mouseUp, position: .init(x: -50, y: 40), button: .right)
        ])
        await player.start(macro: macro, progress: { _ in }, completion: { _ in })
        try await waitUntilStopped(player)
        let events = recorder.snapshot()
        XCTAssertEqual(events.map(\.kind), [.move, .button, .button, .move, .button, .button])
        XCTAssertEqual(events.map(\.position), [.init(x: 10, y: 20), .init(x: 10, y: 20), .init(x: 10, y: 20), .init(x: -50, y: 40), .init(x: -50, y: 40), .init(x: -50, y: 40)])
        XCTAssertEqual(events.map(\.button), [.left, .left, .left, .left, .right, .right])
        XCTAssertGreaterThanOrEqual(events[1].time - events[0].time, 0.17)
        XCTAssertGreaterThanOrEqual(events[3].time - events[1].time, 0.09)

        recorder.reset()
        let held = MouseMacro(name: "Held", events: [
            .init(timestampMilliseconds: 0, kind: .mouseDown, position: .init(x: 1, y: 2), button: .middle),
            .init(timestampMilliseconds: 2_000, kind: .mouseUp, position: .init(x: 1, y: 2), button: .middle)
        ])
        await player.start(macro: held, progress: { _ in }, completion: { _ in })
        try await Task.sleep(for: .milliseconds(30))
        await player.stop()
        let stopped = recorder.snapshot()
        XCTAssertEqual(stopped.map(\.isDown), [true, false])
        XCTAssertEqual(stopped.last?.button, .middle)

        recorder.reset()
        var looping = macro
        looping.repeatMode = .count
        looping.repeatCount = 1_000
        looping.events = [
            .init(timestampMilliseconds: 0, kind: .mouseDown, position: .init(x: 4, y: 5), button: .left),
            .init(timestampMilliseconds: 0, kind: .mouseUp, position: .init(x: 4, y: 5), button: .left)
        ]
        await player.start(macro: looping, progress: { _ in }, completion: { _ in })
        await player.start(macro: looping, progress: { _ in }, completion: { _ in })
        try await waitUntilStopped(player)
        XCTAssertEqual(recorder.snapshot().count, 2_000)
    }

    func testMouseMacroPauseFreezesTimelineAndRestoresHeldButton() async throws {
        let recorder = RecordedMouseEvents()
        let player = MacroPlayer(mouseEvents: recorder)
        let macro = MouseMacro(name: "Pause", events: [
            .init(timestampMilliseconds: 0, kind: .mouseDown, position: .init(x: 10, y: 20), button: .left),
            .init(timestampMilliseconds: 300, kind: .mouseUp, position: .init(x: 10, y: 20), button: .left)
        ])

        await player.start(macro: macro, progress: { _ in }, completion: { _ in })
        try await Task.sleep(for: .milliseconds(40))
        let mousePaused = await player.togglePause()
        XCTAssertEqual(mousePaused, true)
        XCTAssertEqual(recorder.snapshot().map(\.isDown), [true, false])

        try await Task.sleep(for: .milliseconds(140))
        XCTAssertEqual(recorder.snapshot().map(\.isDown), [true, false])

        let mouseResumed = await player.togglePause()
        XCTAssertEqual(mouseResumed, false)
        try await waitUntilStopped(player)
        let posted = recorder.snapshot()
        XCTAssertEqual(posted.map(\.isDown), [true, false, true, false])
        XCTAssertGreaterThanOrEqual(posted[3].time - posted[2].time, 0.22)
    }

    func testCombinedMacroPauseFreezesTimelineAndRestoresHeldKey() async throws {
        let recorder = RecordedMouseEvents()
        let player = CombinedMacroPlayer(events: recorder)
        let macro = CombinedMacro(name: "Pause", events: [
            .init(timestampMilliseconds: 0, kind: .keyDown, keyCode: 3, keyDisplayName: "F"),
            .init(timestampMilliseconds: 300, kind: .keyUp, keyCode: 3, keyDisplayName: "F")
        ])

        await player.start(macro: macro, progress: { _ in }, completion: { _ in })
        try await Task.sleep(for: .milliseconds(40))
        let combinedPaused = await player.togglePause()
        XCTAssertEqual(combinedPaused, true)
        XCTAssertEqual(recorder.snapshot().map(\.isDown), [true, false])

        try await Task.sleep(for: .milliseconds(140))
        XCTAssertEqual(recorder.snapshot().map(\.isDown), [true, false])

        let combinedResumed = await player.togglePause()
        XCTAssertEqual(combinedResumed, false)
        try await waitUntilStopped(player)
        let posted = recorder.snapshot()
        XCTAssertEqual(posted.map(\.kind), [.key, .key, .key, .key])
        XCTAssertEqual(posted.map(\.isDown), [true, false, true, false])
        XCTAssertGreaterThanOrEqual(posted[3].time - posted[2].time, 0.22)
    }

    func testMacroCodableRoundTrip() throws {
        let macro = MouseMacro(
            name: "Test",
            events: [MacroEvent(timestampMilliseconds: 100, kind: .mouseMove, position: .init(x: 10, y: 20))]
        )
        let data = try JSONEncoder().encode(macro)
        let decoded = try JSONDecoder().decode(MouseMacro.self, from: data)
        XCTAssertEqual(decoded, macro)
    }

    func testPlaybackSpeedScaling() {
        XCTAssertEqual(PlaybackTiming.scaledMilliseconds(100, speed: 2), 50, accuracy: 0.000_1)
        XCTAssertEqual(PlaybackTiming.scaledMilliseconds(100, speed: 0.5), 200, accuracy: 0.000_1)
    }

    func testLoopCounts() {
        XCTAssertEqual(MacroRepeatMode.once.resolvedLoopCount(configuredCount: 99), 1)
        XCTAssertEqual(MacroRepeatMode.count.resolvedLoopCount(configuredCount: 5), 5)
        XCTAssertNil(MacroRepeatMode.unlimited.resolvedLoopCount(configuredCount: 5))
    }

    func testDoubleClickOddRemainder() {
        XCTAssertEqual(ClickExecutionPlanner.clicksThisRound(gesture: .double, remaining: 10), 2)
        XCTAssertEqual(ClickExecutionPlanner.clicksThisRound(gesture: .double, remaining: 1), 1)
    }

    func testCoordinateVisibilityAcrossDisplays() {
        let bounds = [
            CGRect(x: 0, y: 0, width: 1_440, height: 900),
            CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        ]
        XCTAssertTrue(ScreenCoordinateConverter.isVisible(.init(x: -100, y: 500), in: bounds))
        XCTAssertFalse(ScreenCoordinateConverter.isVisible(.init(x: 2_000, y: 500), in: bounds))
    }

    func testMoveSamplerFlushesFinalPoint() {
        var sampler = MouseMoveSampler()
        let first = MacroEvent(timestampMilliseconds: 0, kind: .mouseMove, position: .init(x: 0, y: 0))
        let pending = MacroEvent(timestampMilliseconds: 5, kind: .mouseMove, position: .init(x: 1, y: 1))
        XCTAssertNotNil(sampler.consider(first))
        XCTAssertNil(sampler.consider(pending))
        XCTAssertEqual(sampler.flush()?.position, pending.position)
    }

    func testTimelineDelayShiftsFollowingEvents() {
        let first = MacroEvent(timestampMilliseconds: 0, kind: .mouseMove)
        let second = MacroEvent(timestampMilliseconds: 100, kind: .mouseDown, button: .left)
        let third = MacroEvent(timestampMilliseconds: 150, kind: .mouseUp, button: .left)
        var events = [first, second, third]
        MacroTimeline.setDelay(200, for: second.id, in: &events)
        XCTAssertEqual(events[1].timestampMilliseconds, 200)
        XCTAssertEqual(events[2].timestampMilliseconds, 250)
    }

    func testHotkeyDuplicateDetectionInput() {
        let chord = HotkeyConfiguration(keyCode: 0, modifiers: 0, keyDisplayName: "A")
        XCTAssertFalse(HotkeyConflictValidator.hasConflict([
            .startClicker: chord,
            .stopClicker: chord
        ]))
        XCTAssertFalse(HotkeyConflictValidator.hasConflict([
            .playRecentMacro: chord,
            .stopMacro: chord
        ]))
        XCTAssertFalse(HotkeyConflictValidator.hasConflict([
            .startMouseRecording: chord,
            .stopMouseRecording: chord
        ]))
        XCTAssertFalse(HotkeyConflictValidator.hasConflict([
            .playRecentCombinedMacro: chord,
            .stopCombinedMacro: chord
        ]))
        XCTAssertFalse(HotkeyConflictValidator.hasConflict([
            .startCombinedRecording: chord,
            .stopCombinedRecording: chord
        ]))
        XCTAssertTrue(HotkeyConflictValidator.hasConflict([
            .startClicker: chord,
            .playRecentMacro: chord
        ]))
        XCTAssertTrue(HotkeyConflictValidator.hasConflict([
            .pauseResumeMacro: chord,
            .pauseResumeCombinedMacro: chord
        ]))
        XCTAssertEqual(HotkeyAction.clickerCases, [.startClicker, .stopClicker])
        XCTAssertTrue(HotkeyAction.mouseMacroCases.contains(.pauseResumeMacro))
        XCTAssertTrue(HotkeyAction.combinedMacroCases.contains(.pauseResumeCombinedMacro))
    }

    func testFreshInstallHasNoGlobalHotkeys() {
        XCTAssertTrue(HotkeyConfiguration.defaults.isEmpty)
    }

    @MainActor
    func testDisclaimerAcceptancePersistsCurrentVersion() throws {
        let suiteName = "ClickFlowTests.Disclaimer.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DisclaimerAcceptanceStore(defaults: defaults)
        XCTAssertFalse(store.hasAcceptedCurrentDisclaimer)

        store.acceptCurrentDisclaimer()
        XCTAssertTrue(DisclaimerAcceptanceStore(defaults: defaults).hasAcceptedCurrentDisclaimer)

        defaults.set(
            DisclaimerAcceptanceStore.currentVersion - 1,
            forKey: DisclaimerAcceptanceStore.acceptanceVersionKey
        )
        XCTAssertFalse(DisclaimerAcceptanceStore(defaults: defaults).hasAcceptedCurrentDisclaimer)
    }

    func testStorageSkipsDamagedMacroWithoutDeletingIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let damagedURL = root.appendingPathComponent("damaged.json")
        try Data("not json".utf8).write(to: damagedURL)

        let storage = MacroStorage(directoryURL: root)
        let result = await storage.loadAll()
        XCTAssertTrue(result.macros.isEmpty)
        XCTAssertEqual(result.damagedFileNames, ["damaged.json"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: damagedURL.path))
    }

    func testAccessibilityPermissionAcceptsEitherTrustedSignal() {
        XCTAssertTrue(PermissionDecision.canPostEvents(accessibilityTrusted: true, postEventTrusted: false))
        XCTAssertTrue(PermissionDecision.canPostEvents(accessibilityTrusted: false, postEventTrusted: true))
        XCTAssertFalse(PermissionDecision.canPostEvents(accessibilityTrusted: false, postEventTrusted: false))
    }

    func testLegacyClickerConfigurationDecodesAsMouseInput() throws {
        let data = Data(#"{"button":"right","gesture":"single","intervalMilliseconds":100,"positionMode":"current","fixedPosition":{"x":0,"y":0},"countMode":"unlimited","finiteClickCount":100}"#.utf8)
        let configuration = try JSONDecoder().decode(ClickerConfiguration.self, from: data)
        XCTAssertEqual(configuration.inputKind, .mouse)
        XCTAssertEqual(configuration.button, .right)
        XCTAssertEqual(configuration.keyboardKey, .defaultKey)
    }

    func testClickPositionOnlyModeFiltersMovement() {
        XCTAssertFalse(MouseRecordingMode.clickPositionsOnly.records(.mouseMove))
        XCTAssertTrue(MouseRecordingMode.clickPositionsOnly.records(.mouseDown))
        XCTAssertTrue(MouseRecordingMode.clickPositionsOnly.records(.mouseUp))
        XCTAssertTrue(MouseRecordingMode.clickPositionsOnly.records(.scroll))
    }

    func testCombinedMacroCodableRoundTrip() throws {
        let macro = CombinedMacro(name: "Combined", events: [
            CombinedMacroEvent(
                timestampMilliseconds: 10,
                kind: .keyDown,
                keyCode: 3,
                keyDisplayName: "F"
            ),
            CombinedMacroEvent(
                timestampMilliseconds: 20,
                kind: .controller,
                controllerName: "Controller",
                controlName: "buttonA",
                controlValue: 1
            )
        ])
        let decoded = try JSONDecoder().decode(CombinedMacro.self, from: JSONEncoder().encode(macro))
        XCTAssertEqual(decoded, macro)
        XCTAssertTrue(decoded.containsControllerEvents)
    }

    func testControllerOnlyCombinedMacroDoesNotRequireAccessibilityPostingPermission() {
        let controllerOnly = CombinedMacro(name: "Controller", events: [
            .init(
                timestampMilliseconds: 0,
                kind: .controller,
                controllerName: "DualSense #1",
                controlName: "buttonA",
                controlValue: 1
            ),
        ])
        XCTAssertFalse(controllerOnly.requiresEventPostingPermission)

        var mixed = controllerOnly
        mixed.events.append(.init(timestampMilliseconds: 1, kind: .keyDown, keyCode: 0))
        XCTAssertTrue(mixed.requiresEventPostingPermission)
    }

    func testContinuationAppendsAfterExistingTimeline() {
        let existing = [MacroEvent(timestampMilliseconds: 100, kind: .mouseMove)]
        let newEvents = [
            MacroEvent(timestampMilliseconds: 0, kind: .mouseDown, button: .left),
            MacroEvent(timestampMilliseconds: 50, kind: .mouseUp, button: .left)
        ]
        let result = RecordingTimeline.appending(newEvents, to: existing)
        XCTAssertEqual(result.map(\.timestampMilliseconds), [100, 101, 151])
    }

    func testCombinedTimelineDelayAndReordering() {
        let first = CombinedMacroEvent(timestampMilliseconds: 0, kind: .keyDown, keyCode: 3)
        let second = CombinedMacroEvent(timestampMilliseconds: 100, kind: .keyUp, keyCode: 3)
        let third = CombinedMacroEvent(timestampMilliseconds: 200, kind: .controller)
        var events = [first, second, third]

        MacroTimeline.setDelay(250, for: second.id, in: &events)
        XCTAssertEqual(events.map(\.timestampMilliseconds), [0, 250, 350])

        MacroTimeline.move([third.id], direction: -1, in: &events)
        XCTAssertEqual(events.map(\.id), [first.id, third.id, second.id])
        XCTAssertEqual(events.map(\.timestampMilliseconds), [0, 250, 350])
    }

    func testTerminalStopButtonClickIsRemoved() {
        let intended = MacroEvent(timestampMilliseconds: 0, kind: .mouseMove)
        let stopDown = MacroEvent(timestampMilliseconds: 100, kind: .mouseDown, button: .left)
        let stopUp = MacroEvent(timestampMilliseconds: 140, kind: .mouseUp, button: .left)
        let result = RecordingTimeline.removingTerminalControlClick(
            from: [intended, stopDown, stopUp]
        )
        XCTAssertEqual(result, [intended])
    }

    func testTerminalStopButtonDownIsRemovedIfMouseUpRacesStop() {
        let intendedDown = MacroEvent(timestampMilliseconds: 0, kind: .mouseDown, button: .right)
        let intendedUp = MacroEvent(timestampMilliseconds: 50, kind: .mouseUp, button: .right)
        let stopDown = MacroEvent(timestampMilliseconds: 100, kind: .mouseDown, button: .left)
        XCTAssertEqual(
            RecordingTimeline.removingTerminalControlClick(from: [intendedDown, intendedUp, stopDown]),
            [intendedDown, intendedUp]
        )
    }

    func testCombinedTerminalStopButtonClickIsRemoved() {
        let intended = CombinedMacroEvent(
            timestampMilliseconds: 0,
            kind: .keyDown,
            keyCode: 3,
            keyDisplayName: "F"
        )
        let stopDown = CombinedMacroEvent(
            timestampMilliseconds: 100,
            kind: .mouseDown,
            button: .left
        )
        let stopUp = CombinedMacroEvent(
            timestampMilliseconds: 130,
            kind: .mouseUp,
            button: .left
        )
        XCTAssertEqual(
            RecordingTimeline.removingTerminalControlClick(from: [intended, stopDown, stopUp]),
            [intended]
        )
    }

    func testCombinedTerminalStopHotkeyIsRemovedWithoutDeletingPriorInput() {
        let priorDown = CombinedMacroEvent(
            timestampMilliseconds: 0,
            kind: .keyDown,
            keyCode: 3,
            keyDisplayName: "F"
        )
        let priorUp = CombinedMacroEvent(
            timestampMilliseconds: 20,
            kind: .keyUp,
            keyCode: 3,
            keyDisplayName: "F"
        )
        let priorCommandDown = CombinedMacroEvent(
            timestampMilliseconds: 40,
            kind: .keyDown,
            keyCode: 55,
            keyDisplayName: "Command",
            keyboardModifiers: CGEventFlags.maskCommand.rawValue
        )
        let priorCommandUp = CombinedMacroEvent(
            timestampMilliseconds: 60,
            kind: .keyUp,
            keyCode: 55,
            keyDisplayName: "Command",
            keyboardModifiers: 0
        )
        let commandDown = CombinedMacroEvent(
            timestampMilliseconds: 100,
            kind: .keyDown,
            keyCode: 55,
            keyDisplayName: "Command",
            keyboardModifiers: CGEventFlags.maskCommand.rawValue
        )
        let optionDown = CombinedMacroEvent(
            timestampMilliseconds: 110,
            kind: .keyDown,
            keyCode: 58,
            keyDisplayName: "Option",
            keyboardModifiers: (CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue)
        )
        let stopKeyDown = CombinedMacroEvent(
            timestampMilliseconds: 120,
            kind: .keyDown,
            keyCode: 7,
            keyDisplayName: "X",
            keyboardModifiers: (CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue)
        )
        let configuration = HotkeyConfiguration(
            keyCode: 7,
            modifiers: UInt32(cmdKey | optionKey),
            keyDisplayName: "X"
        )

        XCTAssertEqual(
            RecordingTimeline.removingTerminalHotkey(
                from: [
                    priorDown, priorUp, priorCommandDown, priorCommandUp,
                    commandDown, optionDown, stopKeyDown
                ],
                configuration: configuration
            ),
            [priorDown, priorUp, priorCommandDown, priorCommandUp]
        )
    }
}

extension ClickFlowTests {
#if !SWIFT_PACKAGE
    @MainActor
    func testGlobalSidebarOrderPersistenceAndLegacyMigration() {
        let suiteName = "MacGameToolboxClickFlowTests.tabs.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated preference suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(SidebarItem.allCases.count, 16)
        XCTAssertEqual(Set(SidebarItem.allCases).count, 16)
        XCTAssertEqual(SidebarSection.allCases, [.gaming, .storage, .clickFlow, .appDrop, .information])

        let clickFlowSettingsIndex = try! XCTUnwrap(SidebarItem.allCases.firstIndex(of: .cfSettings))
        let appDropIndex = try! XCTUnwrap(SidebarItem.allCases.firstIndex(of: .appDropWishlist))
        let appDropSettingsIndex = try! XCTUnwrap(SidebarItem.allCases.firstIndex(of: .appDropSettings))
        let settingsIndex = try! XCTUnwrap(SidebarItem.allCases.firstIndex(of: .settings))
        XCTAssertLessThan(clickFlowSettingsIndex, appDropIndex)
        XCTAssertLessThan(appDropSettingsIndex, settingsIndex)
        XCTAssertEqual(SidebarItem.appDropWishlist.appDropPage, .wishlist)
        XCTAssertEqual(SidebarItem.appDropTodayDrops.appDropPage, .todayDrops)
        XCTAssertEqual(SidebarItem.appDropHistoricalLows.appDropPage, .historicalLows)
        XCTAssertEqual(SidebarItem.appDropSettings.appDropPage, .settings)

        XCTAssertEqual(NavigationModel.persistedSelection(in: defaults), .metalHUD)
        defaults.set("appearanceWallpaper", forKey: SidebarItem.storageKey)
        XCTAssertEqual(NavigationModel.persistedSelection(in: defaults), .settings)
        XCTAssertEqual(defaults.string(forKey: SidebarItem.storageKey), SidebarItem.settings.rawValue)
        defaults.removeObject(forKey: SidebarItem.storageKey)
        defaults.set("steamDeckSpoof", forKey: SidebarItem.storageKey)
        XCTAssertEqual(NavigationModel.persistedSelection(in: defaults), .hoYoAssistant)
        defaults.set("clickFlow", forKey: SidebarItem.legacyStorageKey)
        defaults.removeObject(forKey: SidebarItem.storageKey)
        XCTAssertEqual(NavigationModel.persistedSelection(in: defaults), .cfClicker)
        defaults.set("appDrop", forKey: SidebarItem.storageKey)
        XCTAssertEqual(NavigationModel.persistedSelection(in: defaults), .appDropWishlist)
        defaults.removeObject(forKey: SidebarItem.legacyStorageKey)
        defaults.set("future-value", forKey: SidebarItem.storageKey)
        XCTAssertEqual(NavigationModel.persistedSelection(in: defaults), .metalHUD)

        let navigation = NavigationModel(defaults: defaults)
        XCTAssertTrue(navigation.isExpanded(.appDrop))
        navigation.toggle(.appDrop)
        XCTAssertFalse(navigation.isExpanded(.appDrop))
        XCTAssertFalse(NavigationModel(defaults: defaults).isExpanded(.appDrop))
        navigation.select(.appDropTodayDrops)
        XCTAssertTrue(navigation.isExpanded(.appDrop))
        navigation.select(.diskManager)
        XCTAssertEqual(defaults.string(forKey: SidebarItem.storageKey), SidebarItem.diskManager.rawValue)
    }

    func testProcessPriorityPreferencesAreIndependentAndValidateStoredValues() {
        let suiteName = "MacGameToolboxClickFlowTests.priorities.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated preference suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(Set(ProcessPriorityStorageKey.allCases.map(\.rawValue)).count, 3)
        for key in ProcessPriorityStorageKey.allCases {
            XCTAssertEqual(key.level(in: defaults), .highest)
        }

        ProcessPriorityStorageKey.crossOver.setLevel(.lower, in: defaults)
        ProcessPriorityStorageKey.manual.setLevel(.high, in: defaults)
        ProcessPriorityStorageKey.favorites.setLevel(.lowest, in: defaults)
        XCTAssertEqual(ProcessPriorityStorageKey.crossOver.level(in: defaults), .lower)
        XCTAssertEqual(ProcessPriorityStorageKey.manual.level(in: defaults), .high)
        XCTAssertEqual(ProcessPriorityStorageKey.favorites.level(in: defaults), .lowest)

        defaults.set(7, forKey: ProcessPriorityStorageKey.manual.rawValue)
        XCTAssertEqual(ProcessPriorityStorageKey.manual.level(in: defaults), .highest)
        XCTAssertEqual(ProcessPriorityStorageKey.crossOver.level(in: defaults), .lower)
        XCTAssertEqual(ProcessPriorityStorageKey.favorites.level(in: defaults), .lowest)
    }

    func testPrivilegedHelperClientAcceptsFiveLevelsAndRejectsOtherValues() {
        for level in ProcessPriorityLevel.allCases {
            XCTAssertNoThrow(
                try PrivilegedHelperClient.request(
                    for: .renice([42], level.rawValue)
                )
            )
        }
        for value: Int32 in [-21, -1, 1, 15, 21] {
            XCTAssertThrowsError(
                try PrivilegedHelperClient.request(for: .renice([42], value))
            )
        }
    }

    func testDismissedStatusBarStaysHiddenAcrossSidebarChanges() {
        let completed = TaskStatus(
            phase: .succeeded,
            message: "Completed process optimization",
            progress: 1
        )
        var state = ToolboxStatusBarState()

        XCTAssertTrue(state.shouldShow(completed, in: .gaming))
        state.dismiss(completed)

        XCTAssertFalse(state.shouldShow(completed, in: .gaming))
        XCTAssertFalse(state.shouldShow(completed, in: .storage))
        XCTAssertFalse(state.shouldShow(completed, in: .clickFlow))
        XCTAssertFalse(state.shouldShow(completed, in: .appDrop))
        XCTAssertFalse(state.shouldShow(completed, in: .information))
        XCTAssertFalse(state.shouldShow(completed, in: .gaming))
    }

    func testDismissedStatusBarReturnsForANewStatusPhase() {
        let completed = TaskStatus(
            phase: .succeeded,
            message: "Completed process optimization",
            progress: 1
        )
        let nextOperation = TaskStatus(
            phase: .running,
            message: "Completed process optimization"
        )
        var state = ToolboxStatusBarState()

        state.dismiss(completed)
        XCTAssertFalse(state.shouldShow(completed, in: .information))

        state.statusDidChange(from: completed, to: nextOperation)
        XCTAssertTrue(state.shouldShow(nextOperation, in: .information))
    }

    func testRunningStatusBarRemainsGlobalUntilDismissed() {
        let running = TaskStatus(phase: .running, message: "Restoring mounts")
        var state = ToolboxStatusBarState()

        XCTAssertTrue(state.shouldShow(running, in: .appDrop))
        state.dismiss(running)
        XCTAssertFalse(state.shouldShow(running, in: .appDrop))
        XCTAssertFalse(state.shouldShow(TaskStatus(phase: .idle), in: .appDrop))
    }
#endif

    @MainActor
    func testIntegratedFeatureRequiresConsentAndUsesIsolatedDefaults() async throws {
        XCTAssertEqual(ClickFlowFeatureController.integratedVersion, "1.0.1")
        let integratedSuite = "MacGameToolboxClickFlowTests.integrated.\(UUID().uuidString)"
        let standaloneSuite = "MacGameToolboxClickFlowTests.standalone.\(UUID().uuidString)"
        guard let integratedDefaults = UserDefaults(suiteName: integratedSuite),
              let standaloneDefaults = UserDefaults(suiteName: standaloneSuite) else {
            return XCTFail("Could not create isolated preference suites")
        }
        defer {
            integratedDefaults.removePersistentDomain(forName: integratedSuite)
            standaloneDefaults.removePersistentDomain(forName: standaloneSuite)
        }

        var standaloneConfiguration = ClickerConfiguration()
        standaloneConfiguration.finiteClickCount = 777
        SettingsStore(defaults: standaloneDefaults).saveClickerConfiguration(standaloneConfiguration)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = ClickFlowFeatureController(
            defaults: integratedDefaults,
            applicationSupportRoot: root
        )
        XCTAssertFalse(controller.isEnabled)
        XCTAssertNil(controller.appState)

        controller.acceptDisclaimer()
        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(
            integratedDefaults.integer(forKey: DisclaimerAcceptanceStore.acceptanceVersionKey),
            DisclaimerAcceptanceStore.currentVersion
        )
        XCTAssertEqual(controller.appState?.clickerConfiguration, ClickerConfiguration())
        XCTAssertNotEqual(controller.appState?.clickerConfiguration.finiteClickCount, 777)

        let mousePath = await controller.appState?.macroStorage.storagePath()
        XCTAssertEqual(mousePath, root.appendingPathComponent("Macros", isDirectory: true).path)
        controller.shutdown()
    }

    @MainActor
    func testAcceptedIntegratedFeatureInitializesAtLaunchAndShutsDownCleanly() {
        let suiteName = "MacGameToolboxClickFlowTests.accepted.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated preference suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            DisclaimerAcceptanceStore.currentVersion,
            forKey: DisclaimerAcceptanceStore.acceptanceVersionKey
        )

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = ClickFlowFeatureController(
            defaults: defaults,
            applicationSupportRoot: root
        )
        XCTAssertTrue(controller.isEnabled, "Accepted ClickFlow must initialize before its tab is opened")
        XCTAssertNotNil(controller.appState?.hotkeyManager, "Global hotkeys must be active on the Toolbox page")

        controller.appState?.isClickerRunning = true
        controller.appState?.isRecording = true
        controller.appState?.isPlayingMacro = true
        controller.appState?.isRecordingCombinedMacro = true
        controller.appState?.isPlayingCombinedMacro = true
        controller.shutdown()

        XCTAssertFalse(controller.appState?.isClickerRunning ?? true)
        XCTAssertFalse(controller.appState?.isRecording ?? true)
        XCTAssertFalse(controller.appState?.isPlayingMacro ?? true)
        XCTAssertFalse(controller.appState?.isRecordingCombinedMacro ?? true)
        XCTAssertFalse(controller.appState?.isPlayingCombinedMacro ?? true)
    }

    @MainActor
    func testIntegratedLanguageSwitchAppliesImmediately() {
        let suiteName = "MacGameToolboxClickFlowTests.language.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated preference suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = ClickFlowFeatureController(defaults: defaults)
        for language in ClickFlowLanguage.allCases {
            controller.setLanguage(language)
            XCTAssertEqual(cf("sidebar.clicker"), ClickFlowL10n.catalog(for: language)["sidebar.clicker"])
        }
    }

    func testAllIntegratedLanguagesHaveCompleteCatalogsAndMatchingPlaceholders() throws {
        let english = ClickFlowL10n.catalog(for: .english)
        XCTAssertFalse(english.isEmpty)
        let placeholderExpression = try NSRegularExpression(pattern: "%(?:lld|@|d)")

        for language in ClickFlowLanguage.allCases {
            let catalog = ClickFlowL10n.catalog(for: language)
            XCTAssertEqual(Set(catalog.keys), Set(english.keys), "Incomplete catalog for \(language.rawValue)")
            for key in english.keys {
                let source = english[key] ?? ""
                let translated = catalog[key] ?? ""
                let sourceRange = NSRange(source.startIndex..., in: source)
                let translatedRange = NSRange(translated.startIndex..., in: translated)
                let sourcePlaceholders = placeholderExpression.matches(in: source, range: sourceRange).map {
                    String(source[Range($0.range, in: source)!])
                }
                let translatedPlaceholders = placeholderExpression.matches(in: translated, range: translatedRange).map {
                    String(translated[Range($0.range, in: translated)!])
                }
                XCTAssertEqual(sourcePlaceholders.sorted(), translatedPlaceholders.sorted(), "Placeholder mismatch for \(key) in \(language.rawValue)")
            }
        }

        XCTAssertTrue(english["error.accessibilityRequired"]?.contains("Mac Game Toolbox") == true)
        XCTAssertTrue(
            ClickFlowL10n.catalog(for: .simplifiedChinese)["error.accessibilityRequired"]?
                .contains("Mac 游戏工具箱") == true
        )
    }
}

private final class RecordedMouseEvents: MouseEventPosting, @unchecked Sendable {
    enum Kind: Equatable {
        case move
        case button
        case scroll
        case key
    }

    struct Event: Equatable {
        let kind: Kind
        let button: MouseButton
        let isDown: Bool
        let position: ScreenPoint
        let time: TimeInterval
    }

    private let lock = NSLock()
    private let configuredCurrentPosition: ScreenPoint
    private let postingDelay: TimeInterval
    private var events: [Event] = []

    init(
        currentPosition: ScreenPoint = .init(x: 0, y: 0),
        postingDelayMilliseconds: Double = 0
    ) {
        configuredCurrentPosition = currentPosition
        postingDelay = postingDelayMilliseconds / 1_000
    }

    func currentPosition() -> ScreenPoint { configuredCurrentPosition }

    func postClick(button: MouseButton, at position: ScreenPoint, clickState: Int64) throws {
        try postButton(button, down: true, at: position, clickState: clickState)
        try postButton(button, down: false, at: position, clickState: clickState)
    }

    func postKeyPress(_ key: KeyboardKey) throws {
        try postKey(key, down: true, flags: [])
        try postKey(key, down: false, flags: [])
    }

    func postKey(_ key: KeyboardKey, down: Bool, flags: CGEventFlags) throws {
        append(.init(kind: .key, button: .left, isDown: down, position: configuredCurrentPosition, time: Date.timeIntervalSinceReferenceDate))
    }

    func postButton(_ button: MouseButton, down: Bool, at position: ScreenPoint, clickState: Int64) throws {
        append(.init(kind: .button, button: button, isDown: down, position: position, time: Date.timeIntervalSinceReferenceDate))
    }

    func postMove(to position: ScreenPoint, dragging button: MouseButton?) throws {
        append(.init(kind: .move, button: button ?? .left, isDown: false, position: position, time: Date.timeIntervalSinceReferenceDate))
    }

    func postScroll(deltaX: Int32, deltaY: Int32, at position: ScreenPoint?) throws {
        append(.init(kind: .scroll, button: .left, isDown: false, position: position ?? configuredCurrentPosition, time: Date.timeIntervalSinceReferenceDate))
    }

    func snapshot() -> [Event] {
        lock.withLock { events }
    }

    func reset() {
        lock.withLock { events.removeAll() }
    }

    private func append(_ event: Event) {
        if postingDelay > 0 {
            Thread.sleep(forTimeInterval: postingDelay)
        }
        lock.withLock { events.append(event) }
    }
}

extension ClickFlowTests {
    func testSharingRoundTripPreservesBothMacroTypesAndPlaybackSettings() throws {
        let mouse = MouseMacro(name: "共享鼠标", events: [
            .init(timestampMilliseconds: 12, kind: .scroll, position: .init(x: -20, y: 30), scrollDeltaX: 2, scrollDeltaY: -3)
        ], repeatMode: .count, repeatCount: 7, repeatDelayMilliseconds: 250, playbackSpeed: 1.5)
        let combined = CombinedMacro(name: "共享组合", events: [
            .init(timestampMilliseconds: 0, kind: .keyDown, keyCode: 3, keyboardModifiers: CGEventFlags.maskShift.rawValue),
            .init(timestampMilliseconds: 10, kind: .keyUp, keyCode: 3),
            .init(timestampMilliseconds: 20, kind: .controller, controllerName: "Xbox", controlName: "A", controlValue: 1)
        ], repeatMode: .unlimited, repeatCount: 9, repeatDelayMilliseconds: 300, playbackSpeed: 2)
        guard case .mouse(let mouseCopy) = try MacroExchange.decode(MacroExchange.encode(.mouse(mouse))),
              case .combined(let combinedCopy) = try MacroExchange.decode(MacroExchange.encode(.combined(combined))) else {
            return XCTFail("Macro type was not preserved")
        }
        XCTAssertEqual(mouseCopy.events, mouse.events)
        XCTAssertEqual(mouseCopy.name, mouse.name)
        XCTAssertEqual(mouseCopy.repeatMode, .count)
        XCTAssertEqual(mouseCopy.repeatCount, 7)
        XCTAssertEqual(mouseCopy.repeatDelayMilliseconds, 250)
        XCTAssertEqual(mouseCopy.playbackSpeed, 1.5)
        XCTAssertEqual(combinedCopy.events, combined.events)
        XCTAssertEqual(combinedCopy.repeatMode, .unlimited)
        XCTAssertEqual(combinedCopy.repeatCount, 9)
        XCTAssertEqual(combinedCopy.repeatDelayMilliseconds, 300)
        XCTAssertEqual(combinedCopy.playbackSpeed, 2)
        // A combined macro with only mouse events must remain a combined macro.
        let mouseOnly = CombinedMacro(name: "Mouse only", events: [.init(timestampMilliseconds: 0, kind: .mouseMove)])
        guard case .combined = try MacroExchange.decode(MacroExchange.encode(.combined(mouseOnly))) else {
            return XCTFail("Combined macro was misclassified")
        }
    }

    func testImportedFilesCreateIndependentPersistedCopies() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("shared.json")
        let original = MouseMacro(name: "Same name", events: [.init(timestampMilliseconds: 0, kind: .mouseMove)], repeatMode: .count, repeatCount: 4)
        try MacroExchange.encode(.mouse(original)).write(to: url)
        guard case .mouse(let first) = try MacroExchange.read(from: url),
              case .mouse(let second) = try MacroExchange.read(from: url) else { return XCTFail("Wrong type") }
        XCTAssertNotEqual(first.id, original.id)
        XCTAssertNotEqual(first.id, second.id)
        let storage = MacroStorage(directoryURL: directory.appendingPathComponent("mouse"))
        try await storage.save(original)
        try await storage.save(first)
        try await storage.save(second)
        let loaded = await storage.loadAll()
        XCTAssertEqual(loaded.macros.count, 3)
        XCTAssertTrue(loaded.macros.allSatisfy { $0.repeatCount == 4 })
        let combined = CombinedMacro(name: "Combined", repeatMode: .unlimited, repeatDelayMilliseconds: 100)
        try MacroExchange.encode(.combined(combined)).write(to: url)
        guard case .combined(let copy) = try MacroExchange.read(from: url) else { return XCTFail("Wrong type") }
        XCTAssertNotEqual(copy.id, combined.id)
        let combinedStorage = CombinedMacroStorage(directoryURL: directory.appendingPathComponent("combined"))
        try await combinedStorage.save(copy)
        let combinedLoaded = await combinedStorage.loadAll()
        XCTAssertEqual(combinedLoaded.macros.first?.repeatMode, .unlimited)
        XCTAssertEqual(combinedLoaded.macros.first?.repeatDelayMilliseconds, 100)
    }

    func testSharingRejectsMalformedVersionsTypesAndUnsafeTimelines() throws {
        let macro = MouseMacro(name: "Valid", events: [.init(timestampMilliseconds: 0, kind: .mouseMove)])
        let data = try MacroExchange.encode(.mouse(macro))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for change: (String, Any) in [("version", 999), ("kind", "combined"), ("format", "Other")] {
            var object = original
            object[change.0] = change.1
            XCTAssertThrowsError(try MacroExchange.decode(JSONSerialization.data(withJSONObject: object)))
        }
        for field in ["timestampMilliseconds"] {
            for value in [-1.0, 1e100] {
                var object = original
                var payload = try XCTUnwrap(object["mouseMacro"] as? [String: Any])
                var events = try XCTUnwrap(payload["events"] as? [[String: Any]])
                events[0][field] = value
                payload["events"] = events
                object["mouseMacro"] = payload
                XCTAssertThrowsError(try MacroExchange.decode(JSONSerialization.data(withJSONObject: object)))
            }
        }
        var invalid = macro
        invalid.events.append(invalid.events[0])
        XCTAssertThrowsError(try MacroExchange.encode(.mouse(invalid)))
        invalid = macro
        invalid.repeatDelayMilliseconds = .infinity
        XCTAssertThrowsError(try MacroExchange.encode(.mouse(invalid)))
        invalid = macro
        invalid.events[0].kind = .mouseDown
        XCTAssertThrowsError(try MacroExchange.encode(.mouse(invalid)))
        XCTAssertThrowsError(try MacroExchange.decode(Data("not JSON".utf8)))
        XCTAssertThrowsError(try MacroExchange.decode(Data(repeating: 0, count: MacroExchange.maximumFileSize + 1)))
    }

    func testBothPlayersRepeatExactCountAndReleaseInputsBetweenLoops() async throws {
        let recorder = RecordedMouseEvents()
        let mouse = MacroPlayer(mouseEvents: recorder)
        let mouseMacro = MouseMacro(name: "Three", events: [
            .init(timestampMilliseconds: 0, kind: .mouseDown, button: .left)
        ], repeatMode: .count, repeatCount: 3, repeatDelayMilliseconds: 60, playbackSpeed: 4)
        await mouse.start(macro: mouseMacro, progress: { _ in }, completion: { error in XCTAssertNil(error) })
        try await waitUntilStopped(mouse)
        var events = recorder.snapshot()
        XCTAssertEqual(events.map(\.isDown), [true, false, true, false, true, false])
        XCTAssertGreaterThanOrEqual(events[2].time - events[1].time, 0.05)
        recorder.reset()
        let combined = CombinedMacroPlayer(events: recorder)
        let combinedMacro = CombinedMacro(name: "Three", events: [
            .init(timestampMilliseconds: 0, kind: .keyDown, keyCode: 3)
        ], repeatMode: .count, repeatCount: 3, repeatDelayMilliseconds: 60, playbackSpeed: 4)
        await combined.start(macro: combinedMacro, progress: { _ in }, completion: { error in XCTAssertNil(error) })
        try await waitUntilStopped(combined)
        events = recorder.snapshot()
        XCTAssertEqual(events.map(\.isDown), [true, false, true, false, true, false])
        XCTAssertGreaterThanOrEqual(events[2].time - events[1].time, 0.05)
    }

    func testUnlimitedMouseLoopPausesResumesAndStopsWithZeroDelay() async throws {
        let recorder = RecordedMouseEvents()
        let player = MacroPlayer(mouseEvents: recorder)
        let macro = MouseMacro(name: "Unlimited", events: [
            .init(timestampMilliseconds: 0, kind: .mouseDown, button: .left),
            .init(timestampMilliseconds: 0, kind: .mouseUp, button: .left)
        ], repeatMode: .unlimited)
        await player.start(macro: macro, progress: { progress in XCTAssertNil(progress.loopCount) }, completion: { error in XCTAssertNil(error) })
        try await Task.sleep(for: .milliseconds(30))
        let paused = await player.togglePause()
        XCTAssertEqual(paused, true)
        let count = recorder.snapshot().count
        XCTAssertGreaterThan(count, 2)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(recorder.snapshot().count, count)
        _ = await player.togglePause()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertGreaterThan(recorder.snapshot().count, count)
        await player.stop()
        let stoppedCount = recorder.snapshot().count
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(recorder.snapshot().count, stoppedCount)
        let running = await player.isRunning()
        XCTAssertFalse(running)
    }

    func testUnlimitedCombinedLoopPausesResumesAndStopsWithZeroDelay() async throws {
        let recorder = RecordedMouseEvents()
        let player = CombinedMacroPlayer(events: recorder)
        let macro = CombinedMacro(name: "Unlimited", events: [
            .init(timestampMilliseconds: 0, kind: .keyDown, keyCode: 3),
            .init(timestampMilliseconds: 0, kind: .keyUp, keyCode: 3)
        ], repeatMode: .unlimited)
        await player.start(macro: macro, progress: { progress in XCTAssertNil(progress.loopCount) }, completion: { error in XCTAssertNil(error) })
        try await Task.sleep(for: .milliseconds(30))
        let paused = await player.togglePause()
        XCTAssertEqual(paused, true)
        let count = recorder.snapshot().count
        XCTAssertGreaterThan(count, 2)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(recorder.snapshot().count, count)
        _ = await player.togglePause()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertGreaterThan(recorder.snapshot().count, count)
        await player.stop()
        let stoppedCount = recorder.snapshot().count
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(recorder.snapshot().count, stoppedCount)
        let running = await player.isRunning()
        XCTAssertFalse(running)
    }

    func testStopWhilePausedInLongLoopDelayForBothPlayers() async throws {
        let recorder = RecordedMouseEvents()
        let mouse = MacroPlayer(mouseEvents: recorder)
        let combined = CombinedMacroPlayer(events: recorder)
        await mouse.start(macro: MouseMacro(name: "Delay", events: [.init(timestampMilliseconds: 0, kind: .mouseDown, button: .left)], repeatMode: .unlimited, repeatDelayMilliseconds: 60_000), progress: { _ in }, completion: { _ in })
        try await Task.sleep(for: .milliseconds(40))
        _ = await mouse.togglePause()
        XCTAssertEqual(recorder.snapshot().map(\.isDown), [true, false])
        await mouse.stop()
        recorder.reset()
        await combined.start(macro: CombinedMacro(name: "Delay", events: [.init(timestampMilliseconds: 0, kind: .keyDown, keyCode: 3)], repeatMode: .unlimited, repeatDelayMilliseconds: 60_000), progress: { _ in }, completion: { _ in })
        try await Task.sleep(for: .milliseconds(40))
        _ = await combined.togglePause()
        XCTAssertEqual(recorder.snapshot().map(\.isDown), [true, false])
        await combined.stop()
        let mouseRunning = await mouse.isRunning()
        let combinedRunning = await combined.isRunning()
        XCTAssertFalse(mouseRunning)
        XCTAssertFalse(combinedRunning)
    }

    func testMousePlaybackUsesAbsoluteTimelineWhenPostingHasLatency() async throws {
        let recorder = RecordedMouseEvents(postingDelayMilliseconds: 10)
        let player = MacroPlayer(mouseEvents: recorder)
        let events = (0...30).map { index in
            MacroEvent(
                timestampMilliseconds: Double(index) * 25,
                kind: .mouseMove,
                position: .init(x: Double(index), y: 0)
            )
        }
        await player.start(
            macro: MouseMacro(name: "Absolute timeline", events: events),
            progress: { _ in },
            completion: { error in XCTAssertNil(error) }
        )
        try await waitUntilStopped(player)

        let posted = recorder.snapshot()
        let elapsed = try XCTUnwrap(posted.last?.time) - XCTUnwrap(posted.first?.time)
        XCTAssertEqual(posted.count, events.count)
        XCTAssertGreaterThan(elapsed, 0.65)
        XCTAssertLessThan(elapsed, 0.92)
    }

    func testCombinedPlaybackKeepsHeldKeyDurationOnAbsoluteTimeline() async throws {
        let recorder = RecordedMouseEvents(postingDelayMilliseconds: 10)
        let player = CombinedMacroPlayer(events: recorder)
        var events = (0..<30).map { index in
            CombinedMacroEvent(
                timestampMilliseconds: Double(index) * 25,
                kind: .keyDown,
                keyCode: 13,
                keyDisplayName: "W"
            )
        }
        events.append(.init(
            timestampMilliseconds: 750,
            kind: .keyUp,
            keyCode: 13,
            keyDisplayName: "W"
        ))
        await player.start(
            macro: CombinedMacro(name: "Held W", events: events),
            progress: { _ in },
            completion: { error in XCTAssertNil(error) }
        )
        try await waitUntilStopped(player)

        let posted = recorder.snapshot()
        let heldDuration = try XCTUnwrap(posted.last?.time) - XCTUnwrap(posted.first?.time)
        XCTAssertEqual(posted.count, events.count)
        XCTAssertGreaterThan(heldDuration, 0.65)
        XCTAssertLessThan(heldDuration, 0.92)
        XCTAssertEqual(posted.last?.isDown, false)
    }

    func testCrossOverXInputPublisherMapsFiltersPausesAndDisconnects() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ClickFlow.xinput")
        let publisher = CrossOverXInputPublisher(url: url, heartbeatInterval: .seconds(60))

        try publisher.begin(primaryControllerName: "DualSense #1")
        try publisher.apply(controllerName: "Xbox #2", controlName: "buttonA", value: 1)
        var data = try Data(contentsOf: url)
        XCTAssertEqual(readUInt32LE(data, at: 12), 1)
        XCTAssertEqual(readUInt16LE(data, at: 16), 0)

        try publisher.apply(controllerName: "DualSense #1", controlName: "buttonA", value: 1)
        try publisher.apply(controllerName: "DualSense #1", controlName: "dpad.x", value: 1)
        try publisher.apply(controllerName: "DualSense #1", controlName: "dpad.y", value: 1)
        try publisher.apply(controllerName: "DualSense #1", controlName: "leftTrigger", value: 0.25)
        try publisher.apply(controllerName: "DualSense #1", controlName: "rightTrigger", value: 1)
        try publisher.apply(controllerName: "DualSense #1", controlName: "leftThumbstick.x", value: -1)
        try publisher.apply(controllerName: "DualSense #1", controlName: "leftThumbstick.y", value: 1)
        data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data[0..<4]), [0x56, 0x47, 0x50, 0x31])
        XCTAssertEqual(readUInt16LE(data, at: 16), 0x1009)
        XCTAssertEqual(data[18], 64)
        XCTAssertEqual(data[19], 255)
        XCTAssertEqual(readInt16LE(data, at: 20), -32_768)
        XCTAssertEqual(readInt16LE(data, at: 22), 32_767)

        try publisher.pause()
        data = try Data(contentsOf: url)
        XCTAssertEqual(readUInt16LE(data, at: 16), 0)
        XCTAssertEqual(data[18], 0)
        XCTAssertEqual(readInt16LE(data, at: 20), 0)

        try publisher.resume()
        data = try Data(contentsOf: url)
        XCTAssertEqual(readUInt16LE(data, at: 16), 0x1009)
        XCTAssertEqual(data[18], 64)
        XCTAssertEqual(readInt16LE(data, at: 20), -32_768)

        try publisher.end()
        data = try Data(contentsOf: url)
        XCTAssertEqual(readUInt32LE(data, at: 12), 0)
        XCTAssertEqual(readUInt16LE(data, at: 16), 0)
    }

    func testCrossOverXInputPublisherMixesPhysicalAndMacroState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ClickFlow.xinput")

        var physicalState = CrossOverXInputState()
        physicalState.apply(control: .buttonA, value: 1)
        physicalState.apply(control: .leftStickX, value: 0.5)
        physicalState.apply(control: .rightTrigger, value: 0.25)
        let physicalController = MutablePhysicalControllerStateProvider(state: physicalState)
        let publisher = CrossOverXInputPublisher(
            url: url,
            physicalController: physicalController,
            pollInterval: .seconds(60),
            heartbeatInterval: .seconds(60)
        )

        try publisher.startPhysicalPassthrough()
        var data = try Data(contentsOf: url)
        XCTAssertTrue(physicalController.isMonitoring)
        XCTAssertEqual(readUInt32LE(data, at: 12), 1)
        XCTAssertEqual(readUInt16LE(data, at: 16), 0x1000)
        XCTAssertEqual(data[19], 64)
        XCTAssertEqual(readInt16LE(data, at: 20), 16_384)

        try publisher.begin(primaryControllerName: "DualSense #1")
        try publisher.apply(controllerName: "DualSense #1", controlName: "buttonB", value: 1)
        try publisher.apply(controllerName: "DualSense #1", controlName: "leftThumbstick.x", value: -1)
        data = try Data(contentsOf: url)
        XCTAssertEqual(readUInt16LE(data, at: 16), 0x3000)
        XCTAssertEqual(data[19], 64)
        XCTAssertEqual(readInt16LE(data, at: 20), -32_768)

        try publisher.pause()
        data = try Data(contentsOf: url)
        XCTAssertEqual(readUInt16LE(data, at: 16), 0x1000)
        XCTAssertEqual(readInt16LE(data, at: 20), 16_384)

        try publisher.resume()
        data = try Data(contentsOf: url)
        XCTAssertEqual(readUInt16LE(data, at: 16), 0x3000)
        XCTAssertEqual(readInt16LE(data, at: 20), -32_768)

        try publisher.apply(controllerName: "DualSense #1", controlName: "buttonB", value: 0)
        try publisher.apply(controllerName: "DualSense #1", controlName: "leftThumbstick.x", value: 0)
        data = try Data(contentsOf: url)
        XCTAssertEqual(readUInt16LE(data, at: 16), 0x1000)
        XCTAssertEqual(readInt16LE(data, at: 20), 16_384)

        var updatedPhysicalState = CrossOverXInputState()
        updatedPhysicalState.apply(control: .buttonX, value: 1)
        updatedPhysicalState.apply(control: .leftTrigger, value: 1)
        physicalController.state = updatedPhysicalState
        try publisher.refreshPhysicalState()
        data = try Data(contentsOf: url)
        XCTAssertEqual(readUInt16LE(data, at: 16), 0x4000)
        XCTAssertEqual(data[18], 255)

        try publisher.end()
        data = try Data(contentsOf: url)
        XCTAssertEqual(readUInt32LE(data, at: 12), 1)
        XCTAssertEqual(readUInt16LE(data, at: 16), 0x4000)
        XCTAssertEqual(data[18], 255)

        publisher.stopPhysicalPassthrough()
        data = try Data(contentsOf: url)
        XCTAssertFalse(physicalController.isMonitoring)
        XCTAssertEqual(readUInt32LE(data, at: 12), 0)
        XCTAssertEqual(readUInt16LE(data, at: 16), 0)
    }

    func testCrossOverXInputStateMapsEveryRecordedControllerControl() {
        var state = CrossOverXInputState()
        for control in ["buttonA", "buttonB", "buttonX", "buttonY"] {
            XCTAssertTrue(state.apply(controlName: control, value: 1))
        }
        for control in [
            "leftShoulder", "rightShoulder", "leftThumbstickButton",
            "rightThumbstickButton", "menu", "options", "home",
        ] {
            XCTAssertTrue(state.apply(controlName: control, value: 1))
        }
        XCTAssertTrue(state.apply(controlName: "dpad.x", value: 1))
        XCTAssertTrue(state.apply(controlName: "dpad.y", value: 1))
        XCTAssertTrue(state.apply(controlName: "leftTrigger", value: 0.25))
        XCTAssertTrue(state.apply(controlName: "rightTrigger", value: 1))
        XCTAssertTrue(state.apply(controlName: "leftThumbstick.x", value: -1))
        XCTAssertTrue(state.apply(controlName: "leftThumbstick.y", value: 1))
        XCTAssertTrue(state.apply(controlName: "rightThumbstick.x", value: 0.5))
        XCTAssertTrue(state.apply(controlName: "rightThumbstick.y", value: -0.5))

        XCTAssertEqual(state.buttons, 0xF7F9)
        XCTAssertEqual(state.leftTrigger, 64)
        XCTAssertEqual(state.rightTrigger, 255)
        XCTAssertEqual(state.leftStickX, -32_768)
        XCTAssertEqual(state.leftStickY, 32_767)
        XCTAssertEqual(state.rightStickX, 16_384)
        XCTAssertEqual(state.rightStickY, -16_384)

        XCTAssertTrue(state.apply(controlName: "buttonA", value: 0))
        XCTAssertEqual(state.buttons, 0xE7F9)
        XCTAssertFalse(state.apply(controlName: "unsupportedControl", value: 1))
    }

    func testCombinedPlayerPublishesControllerTimelineAndSelectsPrimaryController() async throws {
        let output = RecordedControllerOutput()
        let player = CombinedMacroPlayer(
            events: RecordedMouseEvents(),
            controllerOutput: output
        )
        let macro = CombinedMacro(name: "Controller output", events: [
            .init(
                timestampMilliseconds: 0,
                kind: .controller,
                controllerName: "DualSense #1",
                controlName: "buttonA",
                controlValue: 1
            ),
            .init(
                timestampMilliseconds: 1,
                kind: .controller,
                controllerName: "Xbox #2",
                controlName: "buttonB",
                controlValue: 1
            ),
            .init(
                timestampMilliseconds: 2,
                kind: .controller,
                controllerName: "DualSense #1",
                controlName: "buttonA",
                controlValue: 0
            ),
        ])
        await player.start(
            macro: macro,
            progress: { _ in },
            completion: { error in XCTAssertNil(error) }
        )
        try await waitUntilStopped(player)

        let operations = output.snapshot()
        XCTAssertEqual(operations.first, .begin("DualSense #1"))
        XCTAssertEqual(operations.filter { if case .apply = $0 { true } else { false } }.count, 3)
        XCTAssertTrue(operations.contains(.reset))
        XCTAssertEqual(operations.last, .end)
    }

    func testCombinedPlayerRepeatsControllerMacroAndNeutralizesEveryLoop() async throws {
        let output = RecordedControllerOutput()
        let player = CombinedMacroPlayer(
            events: RecordedMouseEvents(),
            controllerOutput: output
        )
        let macro = CombinedMacro(
            name: "Repeated controller output",
            events: [
                .init(
                    timestampMilliseconds: 0,
                    kind: .controller,
                    controllerName: "DualSense #1",
                    controlName: "buttonA",
                    controlValue: 1
                ),
                .init(
                    timestampMilliseconds: 1,
                    kind: .controller,
                    controllerName: "DualSense #1",
                    controlName: "buttonA",
                    controlValue: 0
                ),
            ],
            repeatMode: .count,
            repeatCount: 3,
            repeatDelayMilliseconds: 5
        )
        await player.start(
            macro: macro,
            progress: { _ in },
            completion: { error in XCTAssertNil(error) }
        )
        try await waitUntilStopped(player)

        let operations = output.snapshot()
        XCTAssertEqual(operations.first, .begin("DualSense #1"))
        XCTAssertEqual(operations.filter { if case .apply = $0 { true } else { false } }.count, 6)
        XCTAssertEqual(operations.filter { $0 == .reset }.count, 3)
        XCTAssertEqual(operations.last, .end)
    }

    func testCrossOverXInputLiveIntegrationWindow() async throws {
        guard ProcessInfo.processInfo.environment["CLICKFLOW_LIVE_XINPUT_TEST"] == "1" else {
            throw XCTSkip("Manual CrossOver integration test")
        }

        let player = CombinedMacroPlayer(events: RecordedMouseEvents())
        let macro = CombinedMacro(name: "Live XInput integration", events: [
            .init(
                timestampMilliseconds: 0,
                kind: .controller,
                controllerName: "Integration Controller",
                controlName: "buttonA",
                controlValue: 1
            ),
            .init(
                timestampMilliseconds: 3_000,
                kind: .controller,
                controllerName: "Integration Controller",
                controlName: "buttonA",
                controlValue: 0
            ),
            .init(
                timestampMilliseconds: 3_500,
                kind: .controller,
                controllerName: "Integration Controller",
                controlName: "buttonB",
                controlValue: 1
            ),
            .init(
                timestampMilliseconds: 3_500,
                kind: .controller,
                controllerName: "Integration Controller",
                controlName: "leftTrigger",
                controlValue: 0.25
            ),
            .init(
                timestampMilliseconds: 3_500,
                kind: .controller,
                controllerName: "Integration Controller",
                controlName: "rightTrigger",
                controlValue: 1
            ),
            .init(
                timestampMilliseconds: 3_500,
                kind: .controller,
                controllerName: "Integration Controller",
                controlName: "leftThumbstick.x",
                controlValue: -1
            ),
            .init(
                timestampMilliseconds: 3_500,
                kind: .controller,
                controllerName: "Integration Controller",
                controlName: "leftThumbstick.y",
                controlValue: 1
            ),
            .init(
                timestampMilliseconds: 7_000,
                kind: .controller,
                controllerName: "Integration Controller",
                controlName: "buttonB",
                controlValue: 0
            ),
        ])
        await player.start(
            macro: macro,
            progress: { _ in },
            completion: { error in XCTAssertNil(error) }
        )
        try await waitUntilStopped(player)
    }

    func testOneMinuteCombinedTimelineDoesNotAccumulateSchedulerOrPostingDelay() async throws {
        let recorder = RecordedMouseEvents(postingDelayMilliseconds: 1)
        let player = CombinedMacroPlayer(events: recorder)
        var events = stride(from: 0.0, through: 59_940.0, by: 90.0).map { timestamp in
            CombinedMacroEvent(
                timestampMilliseconds: timestamp,
                kind: .keyDown,
                keyCode: 13,
                keyDisplayName: "W"
            )
        }
        events.append(.init(
            timestampMilliseconds: 60_000,
            kind: .keyUp,
            keyCode: 13,
            keyDisplayName: "W"
        ))
        await player.start(
            macro: CombinedMacro(name: "One minute held W", events: events),
            progress: { _ in },
            completion: { error in XCTAssertNil(error) }
        )
        try await waitUntilStopped(player, timeout: .seconds(65))

        let posted = recorder.snapshot()
        let heldDuration = try XCTUnwrap(posted.last?.time) - XCTUnwrap(posted.first?.time)
        print("One-minute combined timeline elapsed: \(heldDuration) seconds")
        XCTAssertEqual(posted.count, events.count)
        XCTAssertGreaterThan(heldDuration, 59.85)
        XCTAssertLessThan(heldDuration, 60.20)
        XCTAssertEqual(posted.last?.isDown, false)
    }
}

private func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
    UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
}

private func readInt16LE(_ data: Data, at offset: Int) -> Int16 {
    Int16(bitPattern: readUInt16LE(data, at: offset))
}

private final class MutablePhysicalControllerStateProvider: PhysicalControllerStateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var storedState: CrossOverXInputState?
    private var monitoring = false

    init(state: CrossOverXInputState?) {
        storedState = state
    }

    var state: CrossOverXInputState? {
        get { lock.withLock { storedState } }
        set { lock.withLock { storedState = newValue } }
    }

    var isMonitoring: Bool {
        lock.withLock { monitoring }
    }

    func startMonitoring() {
        lock.withLock { monitoring = true }
    }

    func stopMonitoring() {
        lock.withLock { monitoring = false }
    }

    func currentState(preferredControllerName: String?) -> CrossOverXInputState? {
        lock.withLock { storedState }
    }
}

private final class RecordedControllerOutput: ControllerOutputPublishing, @unchecked Sendable {
    enum Operation: Equatable {
        case begin(String?)
        case apply(String?, String?, Float?)
        case pause
        case resume
        case reset
        case end
    }

    private let lock = NSLock()
    private var operations: [Operation] = []

    func begin(primaryControllerName: String?) throws {
        append(.begin(primaryControllerName))
    }

    func apply(controllerName: String?, controlName: String?, value: Float?) throws {
        append(.apply(controllerName, controlName, value))
    }

    func pause() throws { append(.pause) }
    func resume() throws { append(.resume) }
    func reset() throws { append(.reset) }
    func end() throws { append(.end) }

    func snapshot() -> [Operation] {
        lock.withLock { operations }
    }

    private func append(_ operation: Operation) {
        lock.withLock { operations.append(operation) }
    }
}

#if !SWIFT_PACKAGE
final class UpdateCheckerURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension ClickFlowTests {
    @MainActor
    func testUpdateCheckerFallsBackToAtomWhenAPIIsRateLimited() async {
        let session = makeUpdateCheckSession()
        defer { UpdateCheckerURLProtocol.handler = nil }
        UpdateCheckerURLProtocol.handler = { request in
            if request.url?.host == "api.github.com" {
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 403,
                        httpVersion: nil,
                        headerFields: ["x-ratelimit-remaining": "0"]
                    )!,
                    Data()
                )
            }
            if request.url?.path.hasSuffix("releases.atom") == true {
                let xml = """
                <?xml version="1.0" encoding="UTF-8"?>
                <feed xmlns="http://www.w3.org/2005/Atom">
                  <entry>
                    <id>tag:github.com,2008:Repository/1/v3.2.2</id>
                    <link rel="alternate" href="https://github.com/aiwentongxue/mac-gaming-toolbox/releases/tag/v3.2.2"/>
                  </entry>
                </feed>
                """
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/atom+xml"]
                    )!,
                    Data(xml.utf8)
                )
            }
            throw URLError(.badServerResponse)
        }

        let result = await GitHubReleaseChecker.check(
            currentVersion: "3.2.1",
            session: session
        )
        XCTAssertEqual(result, .available(GitHubRelease(version: "v3.2.2")))
    }

    @MainActor
    func testUpdateCheckerReportsCurrentVersionFromAPI() async {
        let session = makeUpdateCheckSession()
        defer { UpdateCheckerURLProtocol.handler = nil }
        UpdateCheckerURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"tag_name":"v3.2.1"}"#.utf8)
            )
        }

        let result = await GitHubReleaseChecker.check(
            currentVersion: "3.2.1",
            session: session
        )
        XCTAssertEqual(result, .upToDate(currentVersion: "3.2.1"))
    }

    @MainActor
    func testUpdateCheckerReportsNetworkFailureAfterAllFallbacksFail() async {
        let session = makeUpdateCheckSession()
        defer { UpdateCheckerURLProtocol.handler = nil }
        UpdateCheckerURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let result = await GitHubReleaseChecker.check(
            currentVersion: "3.2.1",
            session: session
        )
        guard case .failed = result else {
            return XCTFail("Expected a structured failure result")
        }
    }

    func testReleaseVersionPathParserAcceptsEncodedTags() {
        XCTAssertEqual(
            GitHubReleaseChecker.versionFromReleasePath(
                "/aiwentongxue/mac-gaming-toolbox/releases/tag/v3.3.0"
            ),
            "v3.3.0"
        )
        XCTAssertNil(GitHubReleaseChecker.versionFromReleasePath("/releases/latest"))
    }

    private func makeUpdateCheckSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateCheckerURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}
#endif

#if !SWIFT_PACKAGE
extension ClickFlowTests {
    @MainActor
    func testCacheScopeChangeInvalidatesScanAndConfirmation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigurationStore(configurationURL: root.appendingPathComponent("configuration.json"))
        let model = AppModel(configurationStore: store, launchAutomatically: false)
        let item = root.appendingPathComponent("cache")
        model.cacheScan = CacheScan(userTargets: [root], systemTargets: [], userEntries: [item], estimatedBytes: 1)
        model.requestCacheCleaning()
        XCTAssertTrue(model.showingCacheConfirmation)
        XCTAssertEqual(model.cacheConfirmationStage, 1)
        model.setExcludesSensitiveCacheFiles(false)
        XCTAssertNil(model.cacheScan)
        XCTAssertFalse(model.showingCacheConfirmation)
        XCTAssertEqual(model.cacheConfirmationStage, 0)
        model.confirmCacheCleaning()
        XCTAssertFalse(model.isCacheBusy)
        // Allow the asynchronous config save to complete before removing the fixture.
        for _ in 0..<40 {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("configuration.json").path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let saved = try await store.load(importLegacy: false)
        XCTAssertFalse(saved.excludesSensitiveCacheFiles)
    }

    @MainActor
    func testSkippedCacheItemsDoNotBlockConfirmationAndEmptyScansDo() {
        let model = AppModel(launchAutomatically: false)
        let root = URL(fileURLWithPath: "/unused-fixture")
        let skipped = CacheScanIssue(path: root.appendingPathComponent("blocked"), reason: "denied")
        model.cacheScan = CacheScan(userTargets: [root], systemTargets: [], estimatedBytes: 0, inaccessibleTargets: [skipped])
        model.requestCacheCleaning()
        XCTAssertFalse(model.showingCacheConfirmation)
        model.cacheScan = CacheScan(userTargets: [root], systemTargets: [], userEntries: [root.appendingPathComponent("readable")], estimatedBytes: 1, inaccessibleTargets: [skipped])
        model.requestCacheCleaning()
        XCTAssertTrue(model.showingCacheConfirmation)
    }

    @MainActor
    func testGlobalLanguageAppliesImmediatelyAndPersistsForNextController() {
        let defaults = UserDefaults.standard
        let oldValue = defaults.object(forKey: AppLanguage.preferenceKey)
        defer {
            if let oldValue { defaults.set(oldValue, forKey: AppLanguage.preferenceKey) }
            else { defaults.removeObject(forKey: AppLanguage.preferenceKey) }
        }
        let controller = LocalizationController()
        controller.setPreference(.simplifiedChinese)
        let previousToken = controller.refreshToken
        controller.setPreference(.english)
        XCTAssertNotEqual(previousToken, controller.refreshToken)
        XCTAssertEqual(tr("设置", "Settings"), "Settings")
        XCTAssertEqual(LocalizationController().preference, .english)
        controller.setPreference(.simplifiedChinese)
        XCTAssertEqual(tr("设置", "Settings"), "设置")
    }

    @MainActor
    func testUpdateCheckerReportsRateLimitingWhenFallbacksFail() async {
        let session = makeUpdateCheckSession()
        defer { UpdateCheckerURLProtocol.handler = nil }
        UpdateCheckerURLProtocol.handler = { request in
            if request.url?.host == "api.github.com" {
                return (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!, Data())
            }
            throw URLError(.notConnectedToInternet)
        }
        let result = await GitHubReleaseChecker.check(currentVersion: "4.0.0", session: session)
        XCTAssertEqual(result, .rateLimited)
    }
}
#endif

#if !SWIFT_PACKAGE
extension ClickFlowTests {
    @MainActor
    func testSettingsAndDiskPagesRenderInBothAppearancesAtMinimumWidth() throws {
        let output = URL(fileURLWithPath: "/tmp/mac-toolbox-ui-qa")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let model = AppModel(launchAutomatically: false)
        let localization = LocalizationController()
        let pages: [(String, AnyView)] = [
            ("settings", AnyView(ToolboxSettingsDetailView())),
            ("disk", AnyView(DiskManagerDetailView()))
        ]
        for (name, page) in pages {
            for (style, scheme, appearance) in [("light", ColorScheme.light, NSAppearance.Name.aqua), ("dark", ColorScheme.dark, NSAppearance.Name.darkAqua)] {
                let rootView = ZStack {
                    AppBackgroundView()
                    page
                }
                .environmentObject(model)
                .environmentObject(localization)
                .environment(\.colorScheme, scheme)
                .preferredColorScheme(scheme)
                let host = NSHostingView(rootView: rootView)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 640), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                host.frame = NSRect(x: 0, y: 0, width: 720, height: 640)
                host.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                window.appearance?.performAsCurrentDrawingAppearance {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                }
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                XCTAssertGreaterThan(data.count, 1_000)
                try data.write(to: output.appendingPathComponent("\(name)-\(style).png"))
                window.close()
            }
        }
    }
}
#endif

#if !SWIFT_PACKAGE
extension ClickFlowTests {
    @MainActor
    func testAppDropNineLanguagesHaveCompleteCompiledTablesAndMatchingFormats() throws {
        let languages = ["zh-Hans", "zh-Hant", "en", "ja", "ko", "de", "fr", "es", "pt"]
        let expression = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|d|@)"#)
        func placeholders(_ value: String) -> [String] {
            expression.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { match in
                let token = (value as NSString).substring(with: match.range)
                return token.replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression)
            }.sorted()
        }
        for language in languages {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path + "/AppDrop.strings") as? [String: String])
            XCTAssertEqual(Set(table.keys), Set(AppStrings.englishFallbacks.keys), "Incomplete \(language) table")
            for (key, english) in AppStrings.englishFallbacks {
                let translated = try XCTUnwrap(table[key])
                XCTAssertFalse(translated.isEmpty, "\(language):\(key)")
                XCTAssertEqual(placeholders(translated), placeholders(english), "\(language):\(key)")
                XCTAssertEqual(AppStrings.resolve(key, localeIdentifier: language), translated)
            }
            for code in ["us", "gb", "cn", "hk", "tw", "jp", "kr", "de", "fr", "ar", "au", "br", "ca", "in", "ng", "sg", "tr"] {
                let key = "region.\(code).name"
                XCTAssertNotEqual(AppStrings.resolve(key, localeIdentifier: language), key)
            }
        }
    }

    @MainActor
    func testAppDropFallbackWorksWhenLanguageDirectoryLacksItsTable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        for language in ["ja", "en"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(language + ".lproj"), withIntermediateDirectories: true)
        }
        try #""other.module" = "別のモジュール";"#.write(to: root.appendingPathComponent("ja.lproj/Localizable.strings"), atomically: true, encoding: .utf8)
        try #""settings.title" = "Settings from table";"#.write(to: root.appendingPathComponent("en.lproj/AppDrop.strings"), atomically: true, encoding: .utf8)
        let fixture = try XCTUnwrap(Bundle(url: root))
        XCTAssertEqual(AppStrings.resolve("settings.title", localeIdentifier: "ja", bundles: [fixture]), "Settings from table")
        XCTAssertEqual(AppStrings.resolve("common.cancel", localeIdentifier: "ja", bundles: [fixture]), "Cancel")
        XCTAssertEqual(AppStrings.resolve("future.readableTitle", localeIdentifier: "ja", bundles: [], fallbacks: [:]), "Readable Title")
    }

    @MainActor
    func testAppDropLanguageChangesAndPersistsWithoutExposingKeys() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: AppLanguage.preferenceKey)
        defer {
            if let previous { defaults.set(previous, forKey: AppLanguage.preferenceKey) }
            else { defaults.removeObject(forKey: AppLanguage.preferenceKey) }
        }
        let localization = LocalizationController()
        let cases: [(AppLanguage.Preference, String, String)] = [
            (.simplifiedChinese, "zh-Hans", "设置"), (.traditionalChinese, "zh-Hant", "設定"),
            (.english, "en", "Settings"), (.japanese, "ja", "設定"), (.korean, "ko", "설정"),
            (.german, "de", "Einstellungen"), (.french, "fr", "Réglages"),
            (.spanish, "es", "Ajustes"), (.portuguese, "pt", "Ajustes")
        ]
        for (preference, identifier, title) in cases {
            localization.setPreference(preference)
            XCTAssertEqual(AppStrings.localeIdentifier, identifier)
            XCTAssertEqual(AppStrings.string("settings.title"), title)
            XCTAssertEqual(LocalizationController().preference, preference)
        }
    }

    @MainActor
    func testAppDropValidationAndImportErrorsFollowSelectedLanguage() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: AppLanguage.preferenceKey)
        defer {
            if let previous { defaults.set(previous, forKey: AppLanguage.preferenceKey) }
            else { defaults.removeObject(forKey: AppLanguage.preferenceKey) }
        }
        let localization = LocalizationController()
        for language in AppLanguage.Preference.allCases where language != .system {
            localization.setPreference(language)
            XCTAssertEqual(AppStrings.errorDescription(AppStoreURLParserError.notAURL), AppStrings.string("error.link.invalid"))
            XCTAssertTrue(AppStrings.errorDescription(AppStoreURLParserError.unsupportedHost("example.com")).contains("example.com"))
            let duplicate = AppStrings.errorDescription(AppDataStoreError.duplicateTrackedApp(trackId: "123456789", countryCode: "jp"))
            XCTAssertTrue(duplicate.contains("123456789"))
            XCTAssertTrue(duplicate.contains("JP"))
            XCTAssertTrue(AppStrings.errorDescription(WishdropError.unsupportedVersion(99)).contains("99"))
            XCTAssertTrue(AppStrings.errorDescription(AppStoreServiceError.httpStatus(code: 503)).contains("503"))
            let issue = WishdropEntryIssue(index: 4, code: .invalidURL, reason: "Diagnostic English only")
            let text = AppStrings.issueDescription(issue)
            XCTAssertTrue(text.contains("5"))
            XCTAssertTrue(text.contains(AppStrings.string("import.issue.invalidURL")))
            XCTAssertFalse(text.contains(issue.reason))
        }
    }

    @MainActor
    func testAboutPageHasOneBoundedScrollableRegionInAllLanguages() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: AppLanguage.preferenceKey)
        defer {
            if let previous { defaults.set(previous, forKey: AppLanguage.preferenceKey) }
            else { defaults.removeObject(forKey: AppLanguage.preferenceKey) }
        }
        let output = URL(fileURLWithPath: "/tmp/mac-toolbox-402-ui-qa")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let model = AppModel(launchAutomatically: false)
        let localization = LocalizationController()
        func scrollViews(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
        }
        for language in AppLanguage.Preference.allCases where language != .system {
            localization.setPreference(language)
            for size in [NSSize(width: 672, height: 612), NSSize(width: 880, height: 732)] {
                for scheme in [ColorScheme.light, .dark] {
                    let root = ZStack {
                        AppBackgroundView()
                        ChangelogAboutDetailView()
                    }
                        .environmentObject(model)
                        .environmentObject(localization)
                        .environment(\.colorScheme, scheme)
                        .preferredColorScheme(scheme)
                    let host = NSHostingView(rootView: root)
                    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    host.frame = NSRect(origin: .zero, size: size)
                    host.layoutSubtreeIfNeeded()
                    window.displayIfNeeded()
                    XCTAssertEqual(window.frame.size, size)
                    XCTAssertLessThanOrEqual(host.fittingSize.width, size.width + 1, "Intrinsic width \(language)")
                    let scroll = try XCTUnwrap(scrollViews(host).first)
                    XCTAssertEqual(scrollViews(host).count, 1, "Nested scroll regions \(language)")
                    XCTAssertLessThanOrEqual(scroll.frame.maxY, host.bounds.maxY + 1)
                    XCTAssertGreaterThan(try XCTUnwrap(scroll.documentView).frame.height, scroll.contentView.bounds.height)
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    let nsAppearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                    nsAppearance?.performAsCurrentDrawingAppearance {
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                    }
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    let appearance = scheme == .dark ? "dark" : "light"
                    try data.write(to: output.appendingPathComponent("about-\(language.rawValue)-\(Int(size.width))-\(appearance).png"))
                    window.close()
                }
            }
        }
    }
}
#endif

#if !SWIFT_PACKAGE
extension ClickFlowTests {
    final class AppDropDelayedFetcher: AppStoreFetching, @unchecked Sendable {
        var result = AppStoreApp(trackId: "6497794841", name: "Fixture", price: Decimal(string: "27.99"), formattedPrice: "$27.99", currency: "USD")
        var fail = false
        private(set) var lookupCount = 0
        func lookup(appIds: [String], country: String) async -> LookupOutcome {
            lookupCount += 1
            try? await Task.sleep(for: .milliseconds(150))
            return fail ? LookupOutcome(apps: [], failedIds: appIds, failures: [LookupBatchFailure(ids: appIds, message: "fixture offline")]) : LookupOutcome(apps: [result])
        }
        func lookupOne(appId: String, country: String) async throws -> AppStoreApp? { result }
        func search(keyword: String, country: String, platform: AppStoreSearchPlatform) async throws -> [AppStoreApp] { [] }
    }

    @MainActor
    func testAppDropDetailUsesExplicitEnvironmentAndKeepsHistoryAfterSingleCheck() async throws {
        let container = try SharedStore.makeInMemoryContainer()
        let store = AppDataStore(modelContainer: container)
        let snapshot = try await store.insert(NewTrackedAppDraft(trackId: "6497794841", countryCode: "us", name: "Fixture", price: Decimal(string: "69.99"), formattedPrice: "$69.99", currency: "USD"), now: Date().addingTimeInterval(-100))
        let fetcher = AppDropDelayedFetcher()
        let environment = AppEnvironment(container: container, fetcher: fetcher, notifier: NoopNotifier(), automaticallyStart: false)
        let id = snapshot.id
        let app = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TrackedApp>(predicate: #Predicate { $0.id == id })).first)
        // The detail intentionally has no ambient AppEnvironment. Navigation
        // destinations must work from their explicit dependency alone.
        let view = AppDetailView(app: app, environment: environment).modelContainer(container)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 750, height: 640), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let coordinator = try XCTUnwrap(environment.refresh)
        let first = Task { await coordinator.refreshSingle(appID: id) }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(coordinator.isRefreshing)
        let duplicate = await coordinator.refreshSingle(appID: id)
        XCTAssertNil(duplicate)
        let summary = await first.value
        XCTAssertEqual(summary?.outcome, .success)
        XCTAssertFalse(coordinator.isRefreshing)
        XCTAssertEqual(fetcher.lookupCount, 1)
        let records = try await store.records(trackId: snapshot.trackId, countryCode: "us")
        XCTAssertEqual(records.map(\.price), [Decimal(string: "69.99")!, Decimal(string: "27.99")!])
        fetcher.fail = true
        let failed = await coordinator.refreshSingle(appID: id)
        XCTAssertEqual(failed?.outcome, .failed)
        XCTAssertFalse(coordinator.isRefreshing)
        let preserved = try await store.records(trackId: snapshot.trackId, countryCode: "us")
        XCTAssertEqual(preserved.count, 2)
        window.close()
    }
}
#endif

#if !SWIFT_PACKAGE
extension ClickFlowTests {
    @MainActor
    func testAppDropAllLibraryDestinationsKeepContextAndHistory() async throws {
        let container = try SharedStore.makeInMemoryContainer()
        let store = AppDataStore(modelContainer: container)
        let snapshot = try await store.insert(NewTrackedAppDraft(trackId: "6497794841", countryCode: "us", name: "Fixture", price: Decimal(string: "69.99"), formattedPrice: "$69.99", currency: "USD"), now: Date().addingTimeInterval(-100))
        let fetcher = AppDropDelayedFetcher()
        let environment = AppEnvironment(container: container, fetcher: fetcher, notifier: NoopNotifier(), automaticallyStart: false)
        _ = await environment.refresh?.refreshSingle(appID: snapshot.id)
        func hasRenderedStep(_ host: NSView) throws -> Bool {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            var count = 0
            var minX = bitmap.pixelsWide, maxX = 0, minY = bitmap.pixelsHigh, maxY = 0
            // The lower chart must contain both a long horizontal segment and
            // a price decrease, rather than the empty-history placeholder.
            for y in stride(from: bitmap.pixelsHigh * 2 / 5, to: bitmap.pixelsHigh, by: 2) {
                for x in stride(from: bitmap.pixelsWide / 3, to: bitmap.pixelsWide, by: 2) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.blueComponent > 0.75 && color.redComponent < 0.35 && color.blueComponent - color.redComponent > 0.5 && color.greenComponent > 0.2 && color.greenComponent < 0.7 {
                        count += 1
                        minX = min(minX, x); maxX = max(maxX, x)
                        minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
            }
            return count > 300 && maxX - minX > bitmap.pixelsWide / 3 && maxY - minY > bitmap.pixelsHigh / 15
        }
        for page in [AppDropPage.wishlist, .todayDrops, .historicalLows] {
            for layout in [AppDropLayoutMode.grid, .list] {
                let root = NavigationSplitView {
                    Text("Fixture sidebar")
                } detail: {
                    AppDropPageView(page: page, environment: environment, initialPath: [snapshot.id], initialLayout: layout)
                        .modelContainer(container)
                        .environmentObject(environment)
                }
                let host = NSHostingView(rootView: root.background(AppBackgroundView()).tint(.blue).preferredColorScheme(.light))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                var rendered = false
                for _ in 0..<20 {
                    host.layoutSubtreeIfNeeded()
                    rendered = try hasRenderedStep(host)
                    if rendered { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                XCTAssertTrue(rendered, "\(page) / \(layout): expected the two-price step chart")
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/appdrop-route-\(page.rawValue)-\(layout.rawValue).png"))
                }
                window.close()
            }
        }
    }
}
#endif
