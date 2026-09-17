@preconcurrency import Carbon
import CoreGraphics
import XCTest
#if SWIFT_PACKAGE
@testable import MacGameToolboxClickFlow
#else
@testable import Mac_游戏工具箱
#endif

final class ClickFlowTests: XCTestCase {
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
    func testTopLevelTabDefaultsToToolboxAndRemembersClickFlow() {
        let suiteName = "MacGameToolboxClickFlowTests.tabs.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated preference suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(MainSection.persisted(in: defaults), .toolbox)
        defaults.set(MainSection.clickFlow.rawValue, forKey: MainSection.storageKey)
        XCTAssertEqual(MainSection.persisted(in: defaults), .clickFlow)
        defaults.set("future-value", forKey: MainSection.storageKey)
        XCTAssertEqual(MainSection.persisted(in: defaults), .toolbox)
    }
#endif

    @MainActor
    func testIntegratedFeatureRequiresConsentAndUsesIsolatedDefaults() async throws {
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
