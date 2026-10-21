import SwiftUI

struct MacroEditorView: View {
    @Binding var macro: MouseMacro
    @EnvironmentObject private var appState: AppState
    @Environment(\.undoManager) private var undoManager
    @State private var selection: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField(cf("macros.name"), text: binding(\.name))
                    .font(.title2.weight(.semibold))
                Button(cf("macros.continueRecording"), systemImage: "record.circle") {
                    appState.continueRecordingSelectedMacro()
                }
                .disabled(appState.isRecording)
            }

            MacroPlaybackSettingsView(
                repeatMode: binding(\.repeatMode),
                repeatCount: binding(\.repeatCount),
                repeatDelayMilliseconds: binding(\.repeatDelayMilliseconds),
                playbackSpeed: binding(\.playbackSpeed)
            )

            Table(macro.events, selection: $selection) {
                TableColumn(cf("macro.time")) { event in
                    TextField("", value: eventBinding(event.id, \.timestampMilliseconds, default: 0), format: .number)
                }
                .width(min: 70, ideal: 85)

                TableColumn(cf("macro.type")) { event in
                    Picker("", selection: eventBinding(event.id, \.kind, default: .mouseMove)) {
                        ForEach(MacroEventKind.allCases) { kind in Text(kind.localizedName).tag(kind) }
                    }
                    .labelsHidden()
                }
                .width(min: 105, ideal: 125)

                TableColumn("X") { event in
                    TextField("", value: positionBinding(event.id, axis: .x), format: .number)
                }
                .width(min: 65, ideal: 80)

                TableColumn("Y") { event in
                    TextField("", value: positionBinding(event.id, axis: .y), format: .number)
                }
                .width(min: 65, ideal: 80)

                TableColumn(cf("macro.button")) { event in
                    Picker("", selection: buttonBinding(event.id)) {
                        ForEach(MouseButton.allCases) { button in Text(button.localizedName).tag(button) }
                    }
                    .labelsHidden()
                    .disabled(event.kind == .mouseMove || event.kind == .scroll)
                }
                .width(min: 80, ideal: 95)

                TableColumn(cf("macro.scroll")) { event in
                    HStack(spacing: 4) {
                        TextField("X", value: scrollBinding(event.id, xAxis: true), format: .number)
                        TextField("Y", value: scrollBinding(event.id, xAxis: false), format: .number)
                    }
                    .disabled(event.kind != .scroll)
                }
                .width(min: 110, ideal: 130)

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

    private func binding<Value>(_ keyPath: WritableKeyPath<MouseMacro, Value>) -> Binding<Value> {
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
        _ keyPath: WritableKeyPath<MacroEvent, Value>,
        default defaultValue: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                macro.events.first(where: { $0.id == id })?[keyPath: keyPath] ?? defaultValue
            },
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
                var copy = macro
                guard let index = copy.events.firstIndex(where: { $0.id == id }) else { return }
                var position = copy.events[index].position ?? ScreenPoint(x: 0, y: 0)
                if axis == .x { position.x = newValue } else { position.y = newValue }
                copy.events[index].position = position
                apply(copy)
            }
        )
    }

    private func buttonBinding(_ id: UUID) -> Binding<MouseButton> {
        Binding(
            get: { macro.events.first(where: { $0.id == id })?.button ?? .left },
            set: { newValue in
                var copy = macro
                guard let index = copy.events.firstIndex(where: { $0.id == id }) else { return }
                copy.events[index].button = newValue
                apply(copy)
            }
        )
    }

    private func scrollBinding(_ id: UUID, xAxis: Bool) -> Binding<Int> {
        Binding(
            get: {
                guard let event = macro.events.first(where: { $0.id == id }) else { return 0 }
                return Int(xAxis ? event.scrollDeltaX ?? 0 : event.scrollDeltaY ?? 0)
            },
            set: { newValue in
                var copy = macro
                guard let index = copy.events.firstIndex(where: { $0.id == id }) else { return }
                if xAxis {
                    copy.events[index].scrollDeltaX = Int32(clamping: newValue)
                } else {
                    copy.events[index].scrollDeltaY = Int32(clamping: newValue)
                }
                apply(copy)
            }
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
                guard copy.events.contains(where: { $0.id == id }) else { return }
                MacroTimeline.setDelay(newDelay, for: id, in: &copy.events)
                apply(copy)
            }
        )
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

    private func apply(_ newValue: MouseMacro) {
        let oldValue = macro
        undoManager?.registerUndo(withTarget: UndoProxy { restored in macro = restored }) { proxy in
            proxy.restore(oldValue)
        }
        macro = newValue
    }
}

private final class UndoProxy {
    private let action: (MouseMacro) -> Void
    init(action: @escaping (MouseMacro) -> Void) { self.action = action }
    func restore(_ macro: MouseMacro) { action(macro) }
}
