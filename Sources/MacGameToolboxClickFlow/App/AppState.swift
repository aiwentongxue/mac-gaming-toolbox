import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var selectedPage: SidebarPage
    @Published var clickerConfiguration: ClickerConfiguration
    @Published var isClickerRunning = false
    @Published var clickCount = 0
    @Published var macros: [MouseMacro] = []
    @Published var selectedMacroID: UUID?
    @Published var isRecording = false
    @Published var recordingElapsedMilliseconds = 0.0
    @Published var recordingEventCount = 0
    @Published var mouseRecordingMode: MouseRecordingMode
    @Published var isPlayingMacro = false
    @Published var isMouseMacroPaused = false
    @Published var playingMacroID: UUID?
    @Published var playbackProgress = 0.0
    @Published var playbackLoop = 0
    @Published var playbackLoopCount: Int?
    @Published var combinedMacros: [CombinedMacro] = []
    @Published var selectedCombinedMacroID: UUID?
    @Published var isRecordingCombinedMacro = false
    @Published var combinedRecordingElapsedMilliseconds = 0.0
    @Published var combinedRecordingEventCount = 0
    @Published var isPlayingCombinedMacro = false
    @Published var isCombinedMacroPaused = false
    @Published var playingCombinedMacroID: UUID?
    @Published var combinedPlaybackProgress = 0.0
    @Published var combinedPlaybackLoop = 0
    @Published var combinedPlaybackLoopCount: Int?
    @Published var isImportingMacro = false
    @Published var userMessage: String?

    private var clickerSessionID: UUID?
    private var playbackSessionID: UUID?
    private var combinedPlaybackSessionID: UUID?
    private var recordingContinuationMacroID: UUID?
    private var combinedRecordingContinuationMacroID: UUID?

    let permissionManager: PermissionManager
    let mouseEvents = MouseEventService()
    let autoClicker = AutoClickerService()
    let macroRecorder = MacroRecorder()
    let macroPlayer = MacroPlayer()
    let macroStorage: MacroStorage
    let combinedMacroRecorder = CombinedMacroRecorder()
    let combinedMacroPlayer = CombinedMacroPlayer()
    let combinedMacroStorage: CombinedMacroStorage
    let automationCoordinator = AutomationCoordinator()
    let settingsStore: SettingsStore
    private(set) var hotkeyManager: GlobalHotkeyManager?

    init(
        settings: SettingsStore = SettingsStore(),
        macroStorage: MacroStorage = MacroStorage(),
        combinedMacroStorage: CombinedMacroStorage = CombinedMacroStorage(),
        permissionManager: PermissionManager = PermissionManager()
    ) {
        settingsStore = settings
        self.macroStorage = macroStorage
        self.combinedMacroStorage = combinedMacroStorage
        self.permissionManager = permissionManager
        selectedPage = settings.loadSelectedPage()
        clickerConfiguration = settings.loadClickerConfiguration()
        mouseRecordingMode = settings.loadMouseRecordingMode()
        permissionManager.onPostingPermissionLost = { [weak self] in
            guard let self else { return }
            self.userMessage = cf("error.accessibilityRequired")
            self.emergencyStop()
        }

        do {
            let manager = try GlobalHotkeyManager()
            hotkeyManager = manager
            manager.onAction = { [weak self] actions in self?.handleHotkeys(actions) }
            try manager.register(settings.hotkeys)
        } catch {
            userMessage = error.localizedDescription
            AppLogger.hotkeys.error("Hotkey setup failed: \(error.localizedDescription, privacy: .public)")
        }
        Task {
            await loadMacros()
            await loadCombinedMacros()
        }
    }

    var selectedMacro: MouseMacro? {
        macros.first { $0.id == selectedMacroID }
    }

    var selectedCombinedMacro: CombinedMacro? {
        combinedMacros.first { $0.id == selectedCombinedMacroID }
    }

    func importMacro(from url: URL) {
        guard !isImportingMacro else { return }
        isImportingMacro = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isImportingMacro = false }
            do {
                let imported = try await Task.detached { try MacroExchange.read(from: url) }.value
                switch imported {
                case .mouse(let macro):
                    try await macroStorage.save(macro)
                    macros.insert(macro, at: 0)
                    selectedMacroID = macro.id
                    selectedPage = .macros
                case .combined(let macro):
                    try await combinedMacroStorage.save(macro)
                    combinedMacros.insert(macro, at: 0)
                    selectedCombinedMacroID = macro.id
                    selectedPage = .combinedMacros
                }
            } catch { userMessage = error.localizedDescription }
        }
    }

    func captureCurrentPosition() {
        clickerConfiguration.fixedPosition = mouseEvents.currentPosition()
        settingsStore.saveClickerConfiguration(clickerConfiguration)
    }

    func toggleClicker() {
        if isClickerRunning {
            stopClicker()
        } else {
            startClicker()
        }
    }

    func startClicker() {
        guard !isClickerRunning else { return }
        guard permissionManager.canPostEvents else {
            permissionManager.requestEventPostingAccess()
            userMessage = cf("error.accessibilityRequired")
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await stopOtherActivities(except: .clicker)
            clickCount = 0
            isClickerRunning = true
            let sessionID = UUID()
            clickerSessionID = sessionID
            automationCoordinator.begin(.clicker)
            permissionManager.beginPostingPermissionMonitoring()
            let configuration = clickerConfiguration
            settingsStore.saveClickerConfiguration(configuration)
            let service = autoClicker
            await service.start(
                configuration: configuration,
                progress: { [weak self] count in
                    Task { @MainActor in self?.clickCount = count }
                },
                completion: { [weak self] errorMessage in
                    Task { @MainActor in
                        guard self?.clickerSessionID == sessionID else { return }
                        self?.clickerSessionID = nil
                        self?.isClickerRunning = false
                        self?.permissionManager.stopPostingPermissionMonitoring()
                        self?.automationCoordinator.end(.clicker)
                        if let errorMessage { self?.userMessage = errorMessage }
                    }
                }
            )
        }
    }

    func stopClicker() {
        isClickerRunning = false
        clickerSessionID = nil
        permissionManager.stopPostingPermissionMonitoring()
        Task { await autoClicker.stop() }
    }

    func emergencyStop() {
        isClickerRunning = false
        clickerSessionID = nil
        isRecording = false
        isPlayingMacro = false
        isMouseMacroPaused = false
        isRecordingCombinedMacro = false
        isPlayingCombinedMacro = false
        isCombinedMacroPaused = false
        playbackSessionID = nil
        playbackLoopCount = nil
        automationCoordinator.end()
        combinedPlaybackSessionID = nil
        recordingContinuationMacroID = nil
        combinedRecordingContinuationMacroID = nil
        permissionManager.stopPostingPermissionMonitoring()
        Task { [autoClicker, macroPlayer, macroRecorder, combinedMacroPlayer, combinedMacroRecorder] in
            await autoClicker.stop()
            await macroPlayer.stop()
            _ = await macroRecorder.stop()
            await combinedMacroPlayer.stop()
            _ = await combinedMacroRecorder.stop()
        }
        AppLogger.automation.critical("Emergency stop requested")
    }

    func toggleRecording(stoppedByMouseControl: Bool = false) {
        if isRecording {
            Task { @MainActor [weak self] in
                await self?.finishRecording(
                    save: true,
                    discardTerminalMouseClick: stoppedByMouseControl
                )
            }
        } else {
            startRecording()
        }
    }

    func continueRecordingSelectedMacro() {
        guard let selectedMacroID else { return }
        startRecording(continuingMacroID: selectedMacroID)
    }

    func startRecording(continuingMacroID: UUID? = nil) {
        guard !isRecording else { return }
        guard permissionManager.canListenToEvents else {
            permissionManager.requestEventListeningAccess()
            userMessage = cf("error.inputMonitoringRequired")
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await stopOtherActivities(except: .recording)
            do {
                recordingContinuationMacroID = continuingMacroID
                try await macroRecorder.start(mode: mouseRecordingMode) { [weak self] progress in
                    Task { @MainActor in
                        self?.recordingElapsedMilliseconds = progress.elapsedMilliseconds
                        self?.recordingEventCount = progress.eventCount
                    }
                }
                recordingElapsedMilliseconds = 0
                recordingEventCount = 0
                isRecording = true
                automationCoordinator.begin(.recording)
            } catch {
                recordingContinuationMacroID = nil
                userMessage = error.localizedDescription
                isRecording = false
            }
        }
    }

    func finishRecording(
        save: Bool,
        discardTerminalMouseClick: Bool = false
    ) async {
        let continuingID = recordingContinuationMacroID
        recordingContinuationMacroID = nil
        let capturedEvents = await macroRecorder.stop(
            discardTerminalMouseClick: discardTerminalMouseClick
        )
        isRecording = false
        automationCoordinator.end(.recording)
        guard save, !capturedEvents.isEmpty else { return }
        if let continuingID,
           var existing = macros.first(where: { $0.id == continuingID }) {
            existing.events = RecordingTimeline.appending(capturedEvents, to: existing.events)
            existing.updatedAt = .now
            await storeAndSelect(existing)
            selectedPage = .macros
            return
        }
        var macro = MouseMacro(
            name: cf("macro.defaultName %lld", Int64(macros.count + 1)),
            events: capturedEvents
        )
        macro.updatedAt = .now
        await storeAndSelect(macro)
        selectedPage = .macros
    }

    func newMacro() {
        let macro = MouseMacro(name: cf("macro.defaultName %lld", Int64(macros.count + 1)))
        Task { @MainActor [weak self] in await self?.storeAndSelect(macro) }
    }

    func updateMacro(_ macro: MouseMacro) {
        var updated = macro
        updated.updatedAt = .now
        if let index = macros.firstIndex(where: { $0.id == updated.id }) {
            macros[index] = updated
        } else {
            macros.append(updated)
        }
        macros.sort { $0.updatedAt > $1.updatedAt }
        Task { @MainActor [weak self, macroStorage] in
            do { try await macroStorage.save(updated) }
            catch {
                self?.userMessage = error.localizedDescription
                AppLogger.storage.error("Save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func duplicateSelectedMacro() {
        guard var copy = selectedMacro else { return }
        copy.id = UUID()
        copy.name = cf("macro.copyName %@", copy.name)
        copy.createdAt = .now
        copy.updatedAt = .now
        Task { @MainActor [weak self] in await self?.storeAndSelect(copy) }
    }

    func deleteSelectedMacro() {
        guard let id = selectedMacroID else { return }
        // Dismiss the editor before invalidating its model. SwiftUI can evaluate
        // a Binding once more while removing the detail view.
        selectedMacroID = nil
        macros.removeAll { $0.id == id }
        if settingsStore.recentMacroID == id { settingsStore.setRecentMacroID(nil) }
        Task { @MainActor [weak self, macroStorage] in
            do { try await macroStorage.delete(id: id) }
            catch {
                self?.userMessage = error.localizedDescription
                AppLogger.storage.error("Delete failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func playSelectedMacro() {
        guard let selectedMacro else { return }
        play(macro: selectedMacro)
    }

    func playRecentMacro() {
        guard !isPlayingMacro else { return }
        let macro = settingsStore.recentMacroID.flatMap { id in macros.first { $0.id == id } }
            ?? selectedMacro
            ?? macros.first
        guard let macro else {
            userMessage = cf("error.noMacro")
            return
        }
        play(macro: macro)
    }

    func stopPlayback() {
        isPlayingMacro = false
        isMouseMacroPaused = false
        playingMacroID = nil
        playbackSessionID = nil
        playbackLoopCount = nil
        automationCoordinator.end()
        permissionManager.stopPostingPermissionMonitoring()
        Task { await macroPlayer.stop() }
    }

    func toggleMouseMacroPause() {
        guard isPlayingMacro else { return }
        Task { @MainActor [weak self, macroPlayer] in
            guard let paused = await macroPlayer.togglePause() else { return }
            self?.isMouseMacroPaused = paused
        }
    }

    func saveNavigationState() {
        settingsStore.saveSelectedPage(selectedPage)
        settingsStore.saveClickerConfiguration(clickerConfiguration)
        settingsStore.saveMouseRecordingMode(mouseRecordingMode)
    }

    @discardableResult
    func updateHotkey(action: HotkeyAction, configuration: HotkeyConfiguration?) -> Bool {
        guard let hotkeyManager else { return false }
        var updated = settingsStore.hotkeys
        updated[action] = configuration
        do {
            try hotkeyManager.register(updated)
            settingsStore.saveHotkeys(updated)
            return true
        } catch {
            userMessage = error.localizedDescription
            return false
        }
    }

    func beginHotkeyCapture() {
        hotkeyManager?.suspendForCapture()
    }

    func cancelHotkeyCapture() {
        guard let hotkeyManager else { return }
        do {
            try hotkeyManager.register(settingsStore.hotkeys)
        } catch {
            userMessage = error.localizedDescription
        }
    }

    @discardableResult
    func applyHotkeys(_ configurations: [HotkeyAction: HotkeyConfiguration]) -> Bool {
        guard let hotkeyManager else { return false }
        do {
            try hotkeyManager.register(configurations)
            settingsStore.saveHotkeys(configurations)
            return true
        } catch {
            userMessage = error.localizedDescription
            return false
        }
    }

    func resetHotkeys() {
        guard let hotkeyManager else { return }
        do {
            try hotkeyManager.register(HotkeyConfiguration.defaults)
            settingsStore.saveHotkeys(HotkeyConfiguration.defaults)
        } catch {
            userMessage = error.localizedDescription
        }
    }

    func shutdown() {
        emergencyStop()
        saveNavigationState()
        hotkeyManager?.shutdown()
    }

    func loadMacros() async {
        let result = await macroStorage.loadAll()
        macros = result.macros
        if !result.damagedFileNames.isEmpty {
            userMessage = cf("error.damagedMacros %@", result.damagedFileNames.joined(separator: ", "))
        }
    }

    func toggleCombinedRecording(
        stoppedByMouseControl: Bool = false,
        terminalHotkey: HotkeyConfiguration? = nil
    ) {
        if isRecordingCombinedMacro {
            Task { @MainActor [weak self] in
                await self?.finishCombinedRecording(
                    save: true,
                    discardTerminalMouseClick: stoppedByMouseControl,
                    terminalHotkey: terminalHotkey
                )
            }
        } else {
            startCombinedRecording()
        }
    }

    func continueRecordingSelectedCombinedMacro() {
        guard let selectedCombinedMacroID else { return }
        startCombinedRecording(continuingMacroID: selectedCombinedMacroID)
    }

    func startCombinedRecording(continuingMacroID: UUID? = nil) {
        guard !isRecordingCombinedMacro else { return }
        guard permissionManager.canListenToEvents else {
            permissionManager.requestEventListeningAccess()
            userMessage = cf("error.inputMonitoringRequired")
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await stopOtherActivities(except: .combinedRecording)
            do {
                combinedRecordingContinuationMacroID = continuingMacroID
                try await combinedMacroRecorder.start(mouseMode: mouseRecordingMode) { [weak self] progress in
                    Task { @MainActor in
                        self?.combinedRecordingElapsedMilliseconds = progress.elapsedMilliseconds
                        self?.combinedRecordingEventCount = progress.eventCount
                    }
                }
                combinedRecordingElapsedMilliseconds = 0
                combinedRecordingEventCount = 0
                isRecordingCombinedMacro = true
                automationCoordinator.begin(.combinedRecording)
            } catch {
                combinedRecordingContinuationMacroID = nil
                userMessage = error.localizedDescription
            }
        }
    }

    func finishCombinedRecording(
        save: Bool,
        discardTerminalMouseClick: Bool = false,
        terminalHotkey: HotkeyConfiguration? = nil
    ) async {
        let continuingID = combinedRecordingContinuationMacroID
        combinedRecordingContinuationMacroID = nil
        let captured = await combinedMacroRecorder.stop(
            discardTerminalMouseClick: discardTerminalMouseClick,
            terminalHotkey: terminalHotkey
        )
        isRecordingCombinedMacro = false
        automationCoordinator.end(.combinedRecording)
        guard save, !captured.isEmpty else { return }
        if let continuingID,
           var existing = combinedMacros.first(where: { $0.id == continuingID }) {
            existing.events = RecordingTimeline.appending(captured, to: existing.events)
            existing.updatedAt = .now
            await storeAndSelectCombinedMacro(existing)
            selectedPage = .combinedMacros
            return
        }
        let macro = CombinedMacro(
            name: cf("combined.defaultName %lld", Int64(combinedMacros.count + 1)),
            events: captured
        )
        await storeAndSelectCombinedMacro(macro)
        selectedPage = .combinedMacros
    }

    func newCombinedMacro() {
        let macro = CombinedMacro(name: cf("combined.defaultName %lld", Int64(combinedMacros.count + 1)))
        Task { @MainActor [weak self] in await self?.storeAndSelectCombinedMacro(macro) }
    }

    func updateCombinedMacro(_ macro: CombinedMacro) {
        var updated = macro
        updated.updatedAt = .now
        if let index = combinedMacros.firstIndex(where: { $0.id == updated.id }) {
            combinedMacros[index] = updated
        } else {
            combinedMacros.append(updated)
        }
        combinedMacros.sort { $0.updatedAt > $1.updatedAt }
        Task { @MainActor [weak self, combinedMacroStorage] in
            do { try await combinedMacroStorage.save(updated) }
            catch { self?.userMessage = error.localizedDescription }
        }
    }

    func duplicateSelectedCombinedMacro() {
        guard var copy = selectedCombinedMacro else { return }
        copy.id = UUID()
        copy.name = cf("macro.copyName %@", copy.name)
        copy.createdAt = .now
        copy.updatedAt = .now
        Task { @MainActor [weak self] in await self?.storeAndSelectCombinedMacro(copy) }
    }

    func deleteSelectedCombinedMacro() {
        guard let id = selectedCombinedMacroID else { return }
        selectedCombinedMacroID = nil
        combinedMacros.removeAll { $0.id == id }
        if settingsStore.recentCombinedMacroID == id { settingsStore.setRecentCombinedMacroID(nil) }
        Task { @MainActor [weak self, combinedMacroStorage] in
            do { try await combinedMacroStorage.delete(id: id) }
            catch { self?.userMessage = error.localizedDescription }
        }
    }

    func playSelectedCombinedMacro() {
        guard let selectedCombinedMacro else { return }
        play(combinedMacro: selectedCombinedMacro)
    }

    func playRecentCombinedMacro() {
        guard !isPlayingCombinedMacro else { return }
        let macro = settingsStore.recentCombinedMacroID.flatMap { id in
            combinedMacros.first { $0.id == id }
        } ?? selectedCombinedMacro ?? combinedMacros.first
        guard let macro else {
            userMessage = cf("error.noCombinedMacro")
            return
        }
        play(combinedMacro: macro)
    }

    func stopCombinedPlayback() {
        isPlayingCombinedMacro = false
        isCombinedMacroPaused = false
        playingCombinedMacroID = nil
        combinedPlaybackSessionID = nil
        combinedPlaybackLoopCount = nil
        automationCoordinator.end()
        permissionManager.stopPostingPermissionMonitoring()
        Task { await combinedMacroPlayer.stop() }
    }

    func toggleCombinedMacroPause() {
        guard isPlayingCombinedMacro else { return }
        Task { @MainActor [weak self, combinedMacroPlayer] in
            guard let paused = await combinedMacroPlayer.togglePause() else { return }
            self?.isCombinedMacroPaused = paused
        }
    }

    func loadCombinedMacros() async {
        let result = await combinedMacroStorage.loadAll()
        combinedMacros = result.macros
        if !result.damagedFileNames.isEmpty {
            userMessage = cf("error.damagedCombinedMacros %@", result.damagedFileNames.joined(separator: ", "))
        }
    }

    private func handleHotkeys(_ actions: [HotkeyAction]) {
        let actionSet = Set(actions)
        if actionSet == Set([.startClicker, .stopClicker]) {
            toggleClicker()
            return
        }
        if actionSet == Set([.playRecentMacro, .stopMacro]) {
            if isPlayingMacro { stopPlayback() } else { playRecentMacro() }
            return
        }
        if actionSet == Set([.startMouseRecording, .stopMouseRecording]) {
            toggleRecording()
            return
        }
        if actionSet == Set([.startCombinedRecording, .stopCombinedRecording]) {
            toggleCombinedRecording(
                terminalHotkey: isRecordingCombinedMacro
                    ? settingsStore.hotkeys[.stopCombinedRecording]
                    : nil
            )
            return
        }
        if actionSet == Set([.playRecentCombinedMacro, .stopCombinedMacro]) {
            if isPlayingCombinedMacro { stopCombinedPlayback() } else { playRecentCombinedMacro() }
            return
        }

        guard let action = actions.first else { return }
        switch action {
        case .startClicker:
            startClicker()
        case .stopClicker:
            stopClicker()
        case .startMouseRecording:
            startRecording()
        case .stopMouseRecording:
            if isRecording {
                Task { @MainActor [weak self] in await self?.finishRecording(save: true) }
            }
        case .playRecentMacro:
            playRecentMacro()
        case .pauseResumeMacro:
            toggleMouseMacroPause()
        case .stopMacro:
            stopPlayback()
        case .startCombinedRecording:
            startCombinedRecording()
        case .stopCombinedRecording:
            if isRecordingCombinedMacro {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.finishCombinedRecording(
                        save: true,
                        terminalHotkey: self.settingsStore.hotkeys[.stopCombinedRecording]
                    )
                }
            }
        case .playRecentCombinedMacro:
            playRecentCombinedMacro()
        case .pauseResumeCombinedMacro:
            toggleCombinedMacroPause()
        case .stopCombinedMacro:
            stopCombinedPlayback()
        case .captureFixedPosition:
            if clickerConfiguration.inputKind == .mouse,
               clickerConfiguration.positionMode == .fixed {
                captureCurrentPosition()
            }
        }
    }

    private func play(combinedMacro: CombinedMacro) {
        guard permissionManager.canPostEvents else {
            userMessage = cf("error.accessibilityRequired")
            return
        }
        guard !combinedMacro.events.isEmpty else {
            userMessage = cf("error.emptyMacro")
            return
        }
        let invisible = ScreenCoordinateConverter.invisibleEventIndices(in: combinedMacro)
        guard invisible.isEmpty else {
            let rows = invisible.prefix(8).map { String($0 + 1) }.joined(separator: ", ")
            userMessage = cf("error.offscreenEvents %@", rows)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await stopOtherActivities(except: .combinedPlayback(combinedMacro.id))
            isPlayingCombinedMacro = true
            isCombinedMacroPaused = false
            playingCombinedMacroID = combinedMacro.id
            let sessionID = UUID()
            combinedPlaybackSessionID = sessionID
            combinedPlaybackProgress = 0
            combinedPlaybackLoop = 1
            combinedPlaybackLoopCount = combinedMacro.repeatMode.resolvedLoopCount(
                configuredCount: combinedMacro.repeatCount
            )
            automationCoordinator.begin(.combinedPlayback(combinedMacro.id))
            permissionManager.beginPostingPermissionMonitoring()
            settingsStore.setRecentCombinedMacroID(combinedMacro.id)
            await combinedMacroPlayer.start(
                macro: combinedMacro,
                progress: { [weak self] progress in
                    Task { @MainActor in
                        guard self?.combinedPlaybackSessionID == sessionID else { return }
                        self?.combinedPlaybackProgress = progress.eventCount == 0
                            ? 0 : Double(progress.eventIndex) / Double(progress.eventCount)
                        self?.combinedPlaybackLoop = progress.loopIndex
                        self?.combinedPlaybackLoopCount = progress.loopCount
                    }
                },
                completion: { [weak self] errorMessage in
                    Task { @MainActor in
                        guard self?.combinedPlaybackSessionID == sessionID else { return }
                        self?.combinedPlaybackSessionID = nil
                        self?.isPlayingCombinedMacro = false
                        self?.isCombinedMacroPaused = false
                        self?.permissionManager.stopPostingPermissionMonitoring()
                        self?.playingCombinedMacroID = nil
                        self?.combinedPlaybackLoopCount = nil
                        self?.automationCoordinator.end(.combinedPlayback(combinedMacro.id))
                        if let errorMessage { self?.userMessage = errorMessage }
                    }
                }
            )
            if combinedMacro.containsControllerEvents {
                userMessage = cf("combined.controller.playbackLimitation")
            }
        }
    }

    private func play(macro: MouseMacro) {
        guard permissionManager.canPostEvents else {
            userMessage = cf("error.accessibilityRequired")
            return
        }
        guard !macro.events.isEmpty else {
            userMessage = cf("error.emptyMacro")
            return
        }
        let invisibleIndices = ScreenCoordinateConverter.invisibleEventIndices(in: macro)
        guard invisibleIndices.isEmpty else {
            let displayIndices = invisibleIndices.prefix(8).map { String($0 + 1) }.joined(separator: ", ")
            userMessage = cf("error.offscreenEvents %@", displayIndices)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await stopOtherActivities(except: .playback(macro.id))
            isPlayingMacro = true
            isMouseMacroPaused = false
            playingMacroID = macro.id
            let sessionID = UUID()
            playbackSessionID = sessionID
            playbackProgress = 0
            playbackLoop = 1
            playbackLoopCount = macro.repeatMode.resolvedLoopCount(configuredCount: macro.repeatCount)
            automationCoordinator.begin(.playback(macro.id))
            permissionManager.beginPostingPermissionMonitoring()
            settingsStore.setRecentMacroID(macro.id)
            await macroPlayer.start(
                macro: macro,
                progress: { [weak self] progress in
                    Task { @MainActor in
                        guard self?.playbackSessionID == sessionID else { return }
                        self?.playbackProgress = progress.eventCount == 0
                            ? 0
                            : Double(progress.eventIndex) / Double(progress.eventCount)
                        self?.playbackLoop = progress.loopIndex
                        self?.playbackLoopCount = progress.loopCount
                    }
                },
                completion: { [weak self] errorMessage in
                    Task { @MainActor in
                        guard self?.playbackSessionID == sessionID else { return }
                        self?.playbackSessionID = nil
                        self?.isPlayingMacro = false
                        self?.isMouseMacroPaused = false
                        self?.permissionManager.stopPostingPermissionMonitoring()
                        self?.playingMacroID = nil
                        self?.playbackLoopCount = nil
                        self?.automationCoordinator.end(.playback(macro.id))
                        if let errorMessage { self?.userMessage = errorMessage }
                    }
                }
            )
        }
    }

    private func stopOtherActivities(except activity: AutomationCoordinator.Activity) async {
        if activity != .clicker {
            await autoClicker.stop()
            isClickerRunning = false
            clickerSessionID = nil
        }
        if activity != .recording, isRecording {
            await finishRecording(save: true)
        }
        if activity != .combinedRecording, isRecordingCombinedMacro {
            await finishCombinedRecording(save: true)
        }
        if case .playback = activity {
            // Keep the requested playback slot; any existing task is still cancelled below.
        }
        await macroPlayer.stop()
        isPlayingMacro = false
        isMouseMacroPaused = false
        playingMacroID = nil
        playbackSessionID = nil
        playbackLoopCount = nil
        await combinedMacroPlayer.stop()
        isPlayingCombinedMacro = false
        isCombinedMacroPaused = false
        playingCombinedMacroID = nil
        combinedPlaybackSessionID = nil
        combinedPlaybackLoopCount = nil
    }

    private func storeAndSelect(_ macro: MouseMacro) async {
        do {
            try await macroStorage.save(macro)
            if let index = macros.firstIndex(where: { $0.id == macro.id }) {
                macros[index] = macro
            } else {
                macros.append(macro)
            }
            macros.sort { $0.updatedAt > $1.updatedAt }
            selectedMacroID = macro.id
            settingsStore.setRecentMacroID(macro.id)
        } catch {
            userMessage = error.localizedDescription
        }
    }

    private func storeAndSelectCombinedMacro(_ macro: CombinedMacro) async {
        do {
            try await combinedMacroStorage.save(macro)
            if let index = combinedMacros.firstIndex(where: { $0.id == macro.id }) {
                combinedMacros[index] = macro
            } else {
                combinedMacros.append(macro)
            }
            combinedMacros.sort { $0.updatedAt > $1.updatedAt }
            selectedCombinedMacroID = macro.id
            settingsStore.setRecentCombinedMacroID(macro.id)
        } catch {
            userMessage = error.localizedDescription
        }
    }
}
