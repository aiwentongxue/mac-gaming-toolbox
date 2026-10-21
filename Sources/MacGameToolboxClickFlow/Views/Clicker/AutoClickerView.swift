import AppKit
import SwiftUI

struct AutoClickerView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section(cf("clicker.status")) {
                LabeledContent(cf("common.state")) {
                    Text(cf(appState.isClickerRunning ? "status.running" : "status.stopped"))
                }
                LabeledContent(cf("clicker.count")) {
                    if appState.clickerConfiguration.countMode == .finite {
                        Text("\(appState.clickCount) / \(appState.clickerConfiguration.finiteClickCount)")
                    } else {
                        Text(appState.clickCount.formatted())
                    }
                }
                if appState.isClickerRunning {
                    LabeledContent(cf("clicker.cps")) {
                        Text("\(appState.clickerConfiguration.clicksPerSecond.formatted(.number.precision(.fractionLength(0...2)))) CPS")
                    }
                }
            }

            Section(cf("clicker.configuration")) {
                Picker(cf("clicker.inputKind"), selection: $appState.clickerConfiguration.inputKind) {
                    Text(cf("clicker.input.mouse")).tag(ClickerInputKind.mouse)
                    Text(cf("clicker.input.keyboard")).tag(ClickerInputKind.keyboard)
                }
                if appState.clickerConfiguration.inputKind == .mouse {
                    Picker(cf("clicker.button"), selection: $appState.clickerConfiguration.button) {
                        ForEach(MouseButton.allCases) { button in
                            Text(button.localizedName).tag(button)
                        }
                    }
                } else {
                    LabeledContent(cf("clicker.keyboardKey")) {
                        KeyboardKeyRecorderButton(key: $appState.clickerConfiguration.keyboardKey)
                            .frame(width: 150)
                    }
                }
                Picker(cf("clicker.gesture"), selection: $appState.clickerConfiguration.gesture) {
                    ForEach(ClickGesture.allCases) { gesture in
                        Text(gesture.localizedName).tag(gesture)
                    }
                }
                LabeledContent(cf("clicker.interval")) {
                    TextField("", value: intervalBinding, format: .number.precision(.fractionLength(0...2)))
                        .frame(width: 100)
                    Text("ms")
                }
                LabeledContent(cf("clicker.cps")) {
                    TextField("", value: cpsBinding, format: .number.precision(.fractionLength(0...3)))
                        .frame(width: 100)
                    Text("CPS")
                }
            }

            if appState.clickerConfiguration.inputKind == .mouse {
              Section(cf("clicker.position")) {
                Picker(cf("clicker.position.mode"), selection: $appState.clickerConfiguration.positionMode) {
                    Text(cf("clicker.position.current")).tag(ClickPositionMode.current)
                    Text(cf("clicker.position.fixed")).tag(ClickPositionMode.fixed)
                }
                if appState.clickerConfiguration.positionMode == .fixed {
                    HStack {
                        TextField("X", value: $appState.clickerConfiguration.fixedPosition.x, format: .number)
                        TextField("Y", value: $appState.clickerConfiguration.fixedPosition.y, format: .number)
                        Button(cf("clicker.position.capture")) { appState.captureCurrentPosition() }
                    }
                    Text(cf("clicker.position.shortcutHint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
              }
            }

            Section(cf("clicker.repeat")) {
                Picker(cf("clicker.count.mode"), selection: $appState.clickerConfiguration.countMode) {
                    Text(cf("clicker.unlimited")).tag(ClickCountMode.unlimited)
                    Text(cf("clicker.finite")).tag(ClickCountMode.finite)
                }
                if appState.clickerConfiguration.countMode == .finite {
                    Stepper(value: $appState.clickerConfiguration.finiteClickCount, in: 1...1_000_000) {
                        Text(appState.clickerConfiguration.finiteClickCount.formatted())
                    }
                }
            }

            Button(cf(appState.isClickerRunning ? "clicker.stop" : "clicker.start")) {
                appState.toggleClicker()
            }
                .buttonStyle(.borderedProminent)
        }
        .formStyle(.grouped)
        .onChange(of: appState.clickerConfiguration) { _, configuration in
            appState.settingsStore.saveClickerConfiguration(configuration)
        }
    }

    private var intervalBinding: Binding<Double> {
        Binding(
            get: { appState.clickerConfiguration.intervalMilliseconds },
            set: { appState.clickerConfiguration.setInterval(milliseconds: $0) }
        )
    }

    private var cpsBinding: Binding<Double> {
        Binding(
            get: { appState.clickerConfiguration.clicksPerSecond },
            set: { appState.clickerConfiguration.clicksPerSecond = $0 }
        )
    }
}

private struct KeyboardKeyRecorderButton: NSViewRepresentable {
    @Binding var key: KeyboardKey

    func makeNSView(context: Context) -> SingleKeyCaptureButton {
        let button = SingleKeyCaptureButton()
        button.bezelStyle = .rounded
        button.key = key
        button.onChange = { key = $0 }
        button.updateTitle()
        return button
    }

    func updateNSView(_ button: SingleKeyCaptureButton, context: Context) {
        button.key = key
        button.onChange = { key = $0 }
        button.updateTitle()
    }
}

private final class SingleKeyCaptureButton: NSButton {
    var key: KeyboardKey = .defaultKey
    var onChange: ((KeyboardKey) -> Void)?
    private var isCapturing = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        isCapturing = true
        title = cf("clicker.keyboardKey.pressNow")
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }
        let code = UInt16(event.keyCode)
        let known = HotkeyConfiguration.keyNames[UInt32(code)]
        let characters = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let name = known ?? ((characters?.isEmpty == false) ? characters : nil) ?? "Key \(code)"
        let captured = KeyboardKey(keyCode: code, displayName: name)
        key = captured
        isCapturing = false
        updateTitle()
        window?.makeFirstResponder(nil)
        onChange?(captured)
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        isCapturing = false
        updateTitle()
        return result
    }

    func updateTitle() {
        guard !isCapturing else { return }
        title = key.displayName
    }
}
