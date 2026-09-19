import SwiftUI

struct CombinedMacroListView: View {
    var body: some View {
        NavigationStack {
            CombinedMacroLibraryView()
                .navigationTitle(cf("sidebar.combinedMacros"))
        }
    }
}

private struct CombinedMacroLibraryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack {
                    if appState.combinedMacros.isEmpty {
                        ContentUnavailableView(
                            cf("combined.empty.title"),
                            systemImage: "gamecontroller",
                            description: Text(cf("combined.empty.description"))
                        )
                    } else {
                        Table(appState.combinedMacros, selection: $appState.selectedCombinedMacroID) {
                            TableColumn(cf("macros.name"), value: \.name)
                            TableColumn(cf("macros.events")) { Text($0.events.count.formatted()) }
                            TableColumn(cf("macros.duration")) {
                                Text(Duration.milliseconds($0.durationMilliseconds).formatted(.time(pattern: .minuteSecond)))
                            }
                            TableColumn(cf("macros.modified")) {
                                Text($0.updatedAt, format: .dateTime.year().month().day().hour().minute())
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                Divider()

                NavigationLink {
                    CrossOverGameSetupView()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "pc")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 24)
                        Text(cf("combined.windowsGames.entry"))
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
            }
            .frame(minWidth: 300, idealWidth: 360, maxWidth: 430, maxHeight: .infinity)

            Divider()

            if let id = appState.selectedCombinedMacroID,
               let snapshot = appState.combinedMacros.first(where: { $0.id == id }) {
                CombinedMacroEditorView(macro: Binding(
                    get: { appState.combinedMacros.first(where: { $0.id == id }) ?? snapshot },
                    set: { updated in
                        guard appState.combinedMacros.contains(where: { $0.id == id }) else { return }
                        appState.updateCombinedMacro(updated)
                    }
                ))
                .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(cf("combined.select"), systemImage: "tablecells")
                    .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            MacroSharingControls(macro: appState.selectedCombinedMacro.map { SharedMacro.combined($0) })
        }
        .toolbar {
            Menu(cf("macros.recordingOptions"), systemImage: "slider.horizontal.3") {
                Picker(cf("macros.mouseRecordingMode"), selection: $appState.mouseRecordingMode) {
                    Text(cf("macros.recordMotion")).tag(MouseRecordingMode.fullMotion)
                    Text(cf("macros.recordClickPositionsOnly")).tag(MouseRecordingMode.clickPositionsOnly)
                }
            }
            Button(
                cf(appState.isRecordingCombinedMacro ? "macros.stopRecording" : "macros.record"),
                systemImage: appState.isRecordingCombinedMacro ? "stop.fill" : "record.circle"
            ) {
                appState.toggleCombinedRecording(
                    stoppedByMouseControl: appState.isRecordingCombinedMacro &&
                        ControlActivation.isMouseTriggered
                )
            }
            Button(cf("macros.duplicate"), systemImage: "plus.square.on.square") {
                appState.duplicateSelectedCombinedMacro()
            }
            .disabled(appState.selectedCombinedMacroID == nil || appState.isRecordingCombinedMacro)
            Button(
                cf(appState.isCombinedMacroPaused ? "macros.resumePlayback" : "macros.pause"),
                systemImage: appState.isCombinedMacroPaused ? "play.fill" : "pause.fill"
            ) {
                appState.toggleCombinedMacroPause()
            }
            .disabled(!appState.isPlayingCombinedMacro || appState.isRecordingCombinedMacro)
            Button(cf("macros.delete"), systemImage: "trash") { showingDeleteConfirmation = true }
                .disabled(appState.selectedCombinedMacroID == nil || appState.isRecordingCombinedMacro)
            Button(
                cf(appState.isPlayingCombinedMacro ? "macros.stop" : "macros.play"),
                systemImage: appState.isPlayingCombinedMacro ? "stop.fill" : "play.fill"
            ) {
                if appState.isPlayingCombinedMacro {
                    appState.stopCombinedPlayback()
                } else {
                    appState.playSelectedCombinedMacro()
                }
            }
            .disabled(appState.selectedCombinedMacroID == nil || appState.isRecordingCombinedMacro)
        }
        .confirmationDialog(cf("combined.delete.confirm"), isPresented: $showingDeleteConfirmation) {
            Button(cf("macros.delete"), role: .destructive) { appState.deleteSelectedCombinedMacro() }
        }
        .onChange(of: appState.mouseRecordingMode) { _, mode in
            appState.settingsStore.saveMouseRecordingMode(mode)
        }
        .safeAreaInset(edge: .bottom) {
            if appState.isRecordingCombinedMacro {
                HStack {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("\(appState.combinedRecordingElapsedMilliseconds / 1_000, format: .number.precision(.fractionLength(1))) s")
                    Text(cf("macros.recordingEvents %lld", Int64(appState.combinedRecordingEventCount)))
                    Spacer()
                    Button(cf("macros.stopRecording")) {
                        appState.toggleCombinedRecording(
                            stoppedByMouseControl: ControlActivation.isMouseTriggered
                        )
                    }
                }
                .padding(10)
                .background(.bar)
            } else if appState.isPlayingCombinedMacro {
                HStack {
                    ProgressView(value: appState.combinedPlaybackProgress).frame(width: 160)
                    if let total = appState.combinedPlaybackLoopCount {
                        Text("\(appState.combinedPlaybackLoop) / \(total)")
                    } else {
                        Text(cf("macros.playingLoop %lld", Int64(appState.combinedPlaybackLoop)))
                    }
                    Spacer()
                    Button(cf(appState.isCombinedMacroPaused ? "macros.resumePlayback" : "macros.pause")) {
                        appState.toggleCombinedMacroPause()
                    }
                    Button(cf("macros.stop")) { appState.stopCombinedPlayback() }
                }
                .padding(10)
                .background(.bar)
            }
        }
    }
}

private struct CombinedMacroEditorView: View {
    @Binding var macro: CombinedMacro
    @EnvironmentObject private var appState: AppState
    @Environment(\.undoManager) private var undoManager
    @State private var selection: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField(cf("macros.name"), text: macroBinding(\.name))
                    .font(.title2.bold())
                Button(cf("macros.continueRecording"), systemImage: "record.circle") {
                    appState.continueRecordingSelectedCombinedMacro()
                }
                .disabled(appState.isRecordingCombinedMacro)
            }
            MacroPlaybackSettingsView(
                repeatMode: macroBinding(\.repeatMode),
                repeatCount: macroBinding(\.repeatCount),
                repeatDelayMilliseconds: macroBinding(\.repeatDelayMilliseconds),
                playbackSpeed: macroBinding(\.playbackSpeed)
            )
            if macro.containsControllerEvents {
                Label(cf("combined.controller.playbackLimitation"), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Table(macro.events, selection: $selection) {
                TableColumn(cf("macro.time")) { event in
                    TextField(
                        "",
                        value: eventBinding(event.id, \.timestampMilliseconds, default: 0),
                        format: .number
                    )
                }
                .width(min: 70, ideal: 85)

                TableColumn(cf("macro.type")) { event in
                    Picker("", selection: eventBinding(event.id, \.kind, default: .mouseMove)) {
                        ForEach(CombinedMacroEventKind.allCases) { kind in
                            Text(kind.localizedName).tag(kind)
                        }
                    }
                    .labelsHidden()
                }
                .width(min: 105, ideal: 125)

                TableColumn("X") { event in
                    TextField("", value: positionBinding(event.id, axis: .x), format: .number)
                        .disabled(!event.kind.usesMousePosition)
                }
                .width(min: 65, ideal: 80)

                TableColumn("Y") { event in
                    TextField("", value: positionBinding(event.id, axis: .y), format: .number)
                        .disabled(!event.kind.usesMousePosition)
                }
                .width(min: 65, ideal: 80)

                TableColumn(cf("combined.detail")) { event in
                    inputDetailEditor(for: event)
                }
                .width(min: 105, ideal: 145)

                TableColumn(cf("combined.value")) { event in
                    inputValueEditor(for: event)
                }
                .width(min: 110, ideal: 135)

                TableColumn(cf("macro.delay")) { event in
                    TextField("", value: delayBinding(event.id), format: .number)
                }
                .width(min: 70, ideal: 85)
            }

            HStack {
                Button(cf("macro.deleteEvents"), systemImage: "trash", action: deleteSelection)
                    .disabled(selection.isEmpty)
                Spacer()
                Button(cf("macro.moveUp"), systemImage: "arrow.up", action: moveSelectionUp)
                    .disabled(selection.isEmpty)
                Button(cf("macro.moveDown"), systemImage: "arrow.down", action: moveSelectionDown)
                    .disabled(selection.isEmpty)
            }
        }
        .padding()
    }

    private enum Axis { case x, y }

    private func macroBinding<Value>(
        _ keyPath: WritableKeyPath<CombinedMacro, Value>
    ) -> Binding<Value> {
        Binding(
            get: { macro[keyPath: keyPath] },
            set: { newValue in
                var copy = macro
                copy[keyPath: keyPath] = newValue
                apply(copy)
            }
        )
    }

    private func eventBinding<Value>(
        _ id: UUID,
        _ keyPath: WritableKeyPath<CombinedMacroEvent, Value>,
        default defaultValue: Value
    ) -> Binding<Value> {
        Binding(
            get: { macro.events.first(where: { $0.id == id })?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                var copy = macro
                guard let index = copy.events.firstIndex(where: { $0.id == id }) else { return }
                copy.events[index][keyPath: keyPath] = newValue
                copy.events.sort { $0.timestampMilliseconds < $1.timestampMilliseconds }
                apply(copy)
            }
        )
    }

    private func positionBinding(_ id: UUID, axis: Axis) -> Binding<Double> {
        Binding(
            get: {
                let position = macro.events.first(where: { $0.id == id })?.position
                return axis == .x ? position?.x ?? 0 : position?.y ?? 0
            },
            set: { newValue in
                updateEvent(id) { event in
                    var position = event.position ?? ScreenPoint(x: 0, y: 0)
                    if axis == .x { position.x = newValue } else { position.y = newValue }
                    event.position = position
                }
            }
        )
    }

    private func buttonBinding(_ id: UUID) -> Binding<MouseButton> {
        Binding(
            get: { macro.events.first(where: { $0.id == id })?.button ?? .left },
            set: { newValue in updateEvent(id) { $0.button = newValue } }
        )
    }

    private func keyCodeBinding(_ id: UUID) -> Binding<Int> {
        Binding(
            get: { Int(macro.events.first(where: { $0.id == id })?.keyCode ?? 0) },
            set: { newValue in
                updateEvent(id) {
                    let code = UInt16(clamping: newValue)
                    $0.keyCode = code
                    $0.keyDisplayName = KeyboardKey.name(for: code)
                }
            }
        )
    }

    private func stringBinding(
        _ id: UUID,
        _ keyPath: WritableKeyPath<CombinedMacroEvent, String?>
    ) -> Binding<String> {
        Binding(
            get: { macro.events.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { newValue in updateEvent(id) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func scrollBinding(_ id: UUID, xAxis: Bool) -> Binding<Int> {
        Binding(
            get: {
                guard let event = macro.events.first(where: { $0.id == id }) else { return 0 }
                return Int(xAxis ? event.scrollDeltaX ?? 0 : event.scrollDeltaY ?? 0)
            },
            set: { newValue in
                updateEvent(id) {
                    if xAxis { $0.scrollDeltaX = Int32(clamping: newValue) }
                    else { $0.scrollDeltaY = Int32(clamping: newValue) }
                }
            }
        )
    }

    private func controllerValueBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: { Double(macro.events.first(where: { $0.id == id })?.controlValue ?? 0) },
            set: { newValue in updateEvent(id) { $0.controlValue = Float(newValue) } }
        )
    }

    private func delayBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: {
                guard let index = macro.events.firstIndex(where: { $0.id == id }) else { return 0 }
                let previous = index == 0 ? 0 : macro.events[index - 1].timestampMilliseconds
                return max(0, macro.events[index].timestampMilliseconds - previous)
            },
            set: { newDelay in
                var copy = macro
                MacroTimeline.setDelay(newDelay, for: id, in: &copy.events)
                apply(copy)
            }
        )
    }

    @ViewBuilder
    private func inputDetailEditor(for event: CombinedMacroEvent) -> some View {
        switch event.kind {
        case .mouseDown, .mouseUp:
            Picker("", selection: buttonBinding(event.id)) {
                ForEach(MouseButton.allCases) { button in Text(button.localizedName).tag(button) }
            }
            .labelsHidden()
        case .keyDown, .keyUp:
            TextField(cf("combined.keyCode"), value: keyCodeBinding(event.id), format: .number)
        case .controller:
            HStack(spacing: 4) {
                TextField(cf("combined.controllerName"), text: stringBinding(event.id, \.controllerName))
                TextField(cf("combined.controlName"), text: stringBinding(event.id, \.controlName))
            }
        case .mouseMove, .scroll:
            Text("—").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func inputValueEditor(for event: CombinedMacroEvent) -> some View {
        switch event.kind {
        case .scroll:
            HStack(spacing: 4) {
                TextField("X", value: scrollBinding(event.id, xAxis: true), format: .number)
                TextField("Y", value: scrollBinding(event.id, xAxis: false), format: .number)
            }
        case .controller:
            TextField("", value: controllerValueBinding(event.id), format: .number)
        case .mouseMove, .mouseDown, .mouseUp, .keyDown, .keyUp:
            Text("—").foregroundStyle(.secondary)
        }
    }

    private func updateEvent(_ id: UUID, mutation: (inout CombinedMacroEvent) -> Void) {
        var copy = macro
        guard let index = copy.events.firstIndex(where: { $0.id == id }) else { return }
        mutation(&copy.events[index])
        apply(copy)
    }

    private func deleteSelection() {
        var copy = macro
        copy.events.removeAll { selection.contains($0.id) }
        selection.removeAll()
        apply(copy)
    }

    private func moveSelectionUp() {
        var copy = macro
        MacroTimeline.move(selection, direction: -1, in: &copy.events)
        apply(copy)
    }

    private func moveSelectionDown() {
        var copy = macro
        MacroTimeline.move(selection, direction: 1, in: &copy.events)
        apply(copy)
    }

    private func apply(_ newValue: CombinedMacro) {
        let oldValue = macro
        undoManager?.registerUndo(withTarget: CombinedUndoProxy { restored in macro = restored }) {
            proxy in proxy.restore(oldValue)
        }
        macro = newValue
    }
}

private final class CombinedUndoProxy {
    private let action: (CombinedMacro) -> Void
    init(action: @escaping (CombinedMacro) -> Void) { self.action = action }
    func restore(_ macro: CombinedMacro) { action(macro) }
}

private extension CombinedMacroEventKind {
    var localizedName: String {
        switch self {
        case .mouseMove: cf("macroEvent.mouseMove")
        case .mouseDown: cf("macroEvent.mouseDown")
        case .mouseUp: cf("macroEvent.mouseUp")
        case .scroll: cf("macroEvent.scroll")
        case .keyDown: cf("combined.keyDown")
        case .keyUp: cf("combined.keyUp")
        case .controller: cf("combined.controller")
        }
    }

    var usesMousePosition: Bool {
        switch self {
        case .mouseMove, .mouseDown, .mouseUp, .scroll: true
        case .keyDown, .keyUp, .controller: false
        }
    }
}

private extension CombinedMacroEvent {
    var detailText: String {
        if let keyDisplayName { return keyDisplayName }
        if let controlName { return "\(controllerName ?? "") · \(controlName)" }
        if let button { return button.localizedName }
        if let position { return "X \(position.x.formatted())  Y \(position.y.formatted())" }
        if kind == .scroll { return "\(scrollDeltaX ?? 0) / \(scrollDeltaY ?? 0)" }
        return "—"
    }
}
