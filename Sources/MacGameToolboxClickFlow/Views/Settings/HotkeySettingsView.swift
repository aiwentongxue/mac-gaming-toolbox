import AppKit
@preconcurrency import Carbon
import SwiftUI

struct HotkeySettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var configurations: [HotkeyAction: HotkeyConfiguration] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cf("hotkey.captureHint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            hotkeyGroup(cf("hotkey.group.clicker"), actions: HotkeyAction.clickerCases)
            hotkeyGroup(cf("hotkey.group.mouseMacro"), actions: HotkeyAction.mouseMacroCases)
            hotkeyGroup(cf("hotkey.group.combinedMacro"), actions: HotkeyAction.combinedMacroCases)

            Button(cf("hotkey.clearAll")) {
                guard appState.applyHotkeys([:]) else { return }
                configurations = [:]
            }
        }
        .onAppear {
            configurations = appState.settingsStore.hotkeys
        }
    }

    private func hotkeyGroup(_ title: String, actions: [HotkeyAction]) -> some View {
        GroupBox {
            VStack(spacing: 10) {
                ForEach(actions) { action in
                    hotkeyRow(for: action)
                }
            }
            .padding(.vertical, 2)
        } label: {
            Text(title)
                .font(.headline)
        }
    }

    private func hotkeyRow(for action: HotkeyAction) -> some View {
        HStack(spacing: 10) {
            Text(action.displayName)
            Spacer()
            HotkeyRecorderButton(
                configuration: configurations[action],
                onCaptureBegan: { appState.beginHotkeyCapture() },
                onCaptureCancelled: { appState.cancelHotkeyCapture() }
            ) { newConfiguration in
                let previous = configurations[action]
                if appState.updateHotkey(action: action, configuration: newConfiguration) {
                    configurations = appState.settingsStore.hotkeys
                } else {
                    configurations[action] = previous
                }
            }
            .frame(width: 180)

            Button {
                if appState.updateHotkey(action: action, configuration: nil) {
                    configurations = appState.settingsStore.hotkeys
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help(cf("hotkey.clear"))
            .disabled(configurations[action] == nil)
        }
    }
}

private struct HotkeyRecorderButton: NSViewRepresentable {
    var configuration: HotkeyConfiguration?
    var onCaptureBegan: () -> Void
    var onCaptureCancelled: () -> Void
    var onChange: (HotkeyConfiguration) -> Void

    func makeNSView(context: Context) -> KeyCaptureButton {
        let button = KeyCaptureButton()
        button.bezelStyle = .rounded
        button.configuration = configuration
        button.onCaptureBegan = onCaptureBegan
        button.onCaptureCancelled = onCaptureCancelled
        button.onChange = onChange
        button.updateTitle()
        return button
    }

    func updateNSView(_ button: KeyCaptureButton, context: Context) {
        button.configuration = configuration
        button.onCaptureBegan = onCaptureBegan
        button.onCaptureCancelled = onCaptureCancelled
        button.onChange = onChange
        button.updateTitle()
    }
}

private final class KeyCaptureButton: NSButton {
    var configuration: HotkeyConfiguration?
    var onCaptureBegan: (() -> Void)?
    var onCaptureCancelled: (() -> Void)?
    var onChange: ((HotkeyConfiguration) -> Void)?
    private var isCapturing = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !isCapturing else { return }
        isCapturing = true
        onCaptureBegan?()
        title = cf("hotkey.pressNow")
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }

        let keyCode = UInt32(event.keyCode)
        let captured = HotkeyConfiguration(
            keyCode: keyCode,
            modifiers: Self.carbonModifiers(from: event.modifierFlags),
            keyDisplayName: Self.keyName(for: event)
        )
        configuration = captured
        isCapturing = false
        updateTitle()
        window?.makeFirstResponder(nil)
        onChange?(captured)
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if isCapturing {
            isCapturing = false
            updateTitle()
            onCaptureCancelled?()
        }
        return result
    }

    func updateTitle() {
        guard !isCapturing else { return }
        title = configuration?.displayString ?? cf("hotkey.notSet")
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static func keyName(for event: NSEvent) -> String {
        let keyCode = UInt32(event.keyCode)
        if let knownName = HotkeyConfiguration.keyNames[keyCode] {
            return knownName
        }
        let characters = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if let characters, !characters.isEmpty {
            return characters
        }
        return "Key \(keyCode)"
    }
}
