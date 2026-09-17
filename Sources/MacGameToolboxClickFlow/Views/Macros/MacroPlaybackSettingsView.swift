import SwiftUI

struct MacroPlaybackSettingsView: View {
    @Binding var repeatMode: MacroRepeatMode
    @Binding var repeatCount: Int
    @Binding var repeatDelayMilliseconds: Double
    @Binding var playbackSpeed: Double

    var body: some View {
        GroupBox(cf("macro.playbackSettings")) {
            VStack(alignment: .leading, spacing: 10) {
                Picker(cf("macro.repeatMode"), selection: $repeatMode) {
                    Text(cf("macro.repeat.once")).tag(MacroRepeatMode.once)
                    Text(cf("macro.repeat.count")).tag(MacroRepeatMode.count)
                    Text(cf("macro.repeat.unlimited")).tag(MacroRepeatMode.unlimited)
                }
                .pickerStyle(.segmented)
                if repeatMode == .count {
                    LabeledContent(cf("macro.repeatCount")) {
                        TextField(cf("macro.repeatCount"), value: Binding(
                            get: { repeatCount },
                            set: { repeatCount = max(1, $0) }
                        ), format: .number.grouping(.never))
                        .frame(width: 90)
                        .textFieldStyle(.roundedBorder)
                    }
                    Text(cf("macro.repeatCount.help")).font(.caption).foregroundStyle(.secondary)
                } else if repeatMode == .unlimited {
                    Text(cf("macro.repeatUnlimited.help")).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Picker(cf("macro.speed"), selection: $playbackSpeed) {
                        ForEach(Array(Set([0.25, 0.5, 1, 1.5, 2, 4, playbackSpeed])).sorted(), id: \.self) { speed in
                            Text("\(speed.formatted(.number.precision(.fractionLength(0...2))))×").tag(speed)
                        }
                    }
                    if repeatMode != .once {
                        LabeledContent(cf("macro.repeatDelay")) {
                            TextField(cf("macro.repeatDelay"), value: Binding(
                                get: { repeatDelayMilliseconds },
                                set: { repeatDelayMilliseconds = $0.isFinite ? max(0, min(1_000_000_000_000, $0)) : 0 }
                            ), format: .number)
                            .frame(width: 75)
                            Text("ms")
                        }
                    }
                }
            }
            .padding(6)
        }
    }
}
