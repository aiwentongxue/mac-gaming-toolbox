import SwiftUI

struct DisclaimerView: View {
    var onAccept: () -> Void
    var onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(cf("disclaimer.title"))
                        .font(.title.bold())
                    Text(cf("disclaimer.acceptanceRequired"))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ScrollView {
                Text(cf("disclaimer.body"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(.trailing, 8)
            }

            Divider()

            HStack {
                Text("Copyright © 2026 我是艾文喵")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(cf("disclaimer.decline"), role: .destructive, action: onDecline)
                Button(cf("disclaimer.accept"), action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 520)
    }
}
