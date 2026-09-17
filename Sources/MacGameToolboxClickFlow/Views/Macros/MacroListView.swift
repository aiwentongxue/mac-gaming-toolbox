import SwiftUI

struct MacroListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if appState.macros.isEmpty {
                    ContentUnavailableView(
                        cf("macros.empty.title"),
                        systemImage: "record.circle",
                        description: Text(cf("macros.empty.description"))
                    )
                } else {
                    Table(appState.macros, selection: $appState.selectedMacroID) {
                        TableColumn(cf("macros.name"), value: \.name)
                        TableColumn(cf("macros.events")) { macro in
                            Text(macro.events.count.formatted())
                        }
                        TableColumn(cf("macros.duration")) { macro in
                            Text(Duration.milliseconds(macro.durationMilliseconds).formatted(.time(pattern: .minuteSecond)))
                        }
                        TableColumn(cf("macros.modified")) { macro in
                            Text(macro.updatedAt, format: .dateTime.year().month().day().hour().minute())
                        }
                    }
                }
            }
            .frame(minWidth: 300, idealWidth: 360, maxWidth: 430, maxHeight: .infinity)

            Divider()

            if let selectedID = appState.selectedMacroID,
               let selectedMacro = appState.macros.first(where: { $0.id == selectedID }) {
                MacroEditorView(
                    macro: Binding(
                        get: {
                            appState.macros.first(where: { $0.id == selectedID }) ?? selectedMacro
                        },
                        set: { updatedMacro in
                            guard appState.macros.contains(where: { $0.id == selectedID }) else { return }
                            appState.updateMacro(updatedMacro)
                        }
                    )
                )
                .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(cf("macros.select"), systemImage: "tablecells")
                    .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .toolbar {
            MacroSharingControls(macro: appState.selectedMacro.map { SharedMacro.mouse($0) })
        }
        .toolbar {
            Menu(cf("macros.recordingOptions"), systemImage: "slider.horizontal.3") {
                Picker(cf("macros.mouseRecordingMode"), selection: $appState.mouseRecordingMode) {
                    Text(cf("macros.recordMotion")).tag(MouseRecordingMode.fullMotion)
                    Text(cf("macros.recordClickPositionsOnly")).tag(MouseRecordingMode.clickPositionsOnly)
                }
            }
            Button(cf(appState.isRecording ? "macros.stopRecording" : "macros.record"), systemImage: appState.isRecording ? "stop.fill" : "record.circle") {
                appState.toggleRecording(
                    stoppedByMouseControl: appState.isRecording && ControlActivation.isMouseTriggered
                )
            }
            Button(cf("macros.duplicate"), systemImage: "plus.square.on.square") { appState.duplicateSelectedMacro() }
                .disabled(appState.selectedMacroID == nil || appState.isRecording)
            Button(cf("macros.delete"), systemImage: "trash") { showingDeleteConfirmation = true }
                .disabled(appState.selectedMacroID == nil || appState.isRecording)
            Button(cf(appState.isPlayingMacro ? "macros.stop" : "macros.play"), systemImage: appState.isPlayingMacro ? "stop.fill" : "play.fill") {
                if appState.isPlayingMacro { appState.stopPlayback() } else { appState.playSelectedMacro() }
            }
                .disabled(appState.selectedMacroID == nil || appState.isRecording)
            Button(
                cf(appState.isMouseMacroPaused ? "macros.resumePlayback" : "macros.pause"),
                systemImage: appState.isMouseMacroPaused ? "play.fill" : "pause.fill"
            ) {
                appState.toggleMouseMacroPause()
            }
            .disabled(!appState.isPlayingMacro || appState.isRecording)
        }
        .onChange(of: appState.mouseRecordingMode) { _, mode in
            appState.settingsStore.saveMouseRecordingMode(mode)
        }
        .confirmationDialog(cf("macros.delete.confirm"), isPresented: $showingDeleteConfirmation) {
            Button(cf("macros.delete"), role: .destructive) { appState.deleteSelectedMacro() }
        }
        .safeAreaInset(edge: .bottom) {
            if appState.isRecording {
                HStack {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("\(appState.recordingElapsedMilliseconds / 1_000, format: .number.precision(.fractionLength(1))) s")
                    Text(cf("macros.recordingEvents %lld", Int64(appState.recordingEventCount)))
                    Spacer()
                    Button(cf("macros.stopRecording")) {
                        appState.toggleRecording(
                            stoppedByMouseControl: ControlActivation.isMouseTriggered
                        )
                    }
                }
                .padding(10)
                .background(.bar)
            } else if appState.isPlayingMacro {
                HStack {
                    ProgressView(value: appState.playbackProgress).frame(width: 160)
                    if let total = appState.playbackLoopCount {
                        Text("\(appState.playbackLoop) / \(total)")
                    } else {
                        Text(cf("macros.playingLoop %lld", Int64(appState.playbackLoop)))
                    }
                    Spacer()
                    Button(cf(appState.isMouseMacroPaused ? "macros.resumePlayback" : "macros.pause")) {
                        appState.toggleMouseMacroPause()
                    }
                    Button(cf("macros.stop")) { appState.stopPlayback() }
                }
                .padding(10)
                .background(.bar)
            }
        }
    }
}
