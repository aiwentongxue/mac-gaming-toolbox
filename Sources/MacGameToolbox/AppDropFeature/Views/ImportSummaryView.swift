import SwiftUI
import AppDropCore

struct ImportSummaryView: View {
    let summary: WishdropImportSummary
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppStrings.string("import.title"))
                .font(.title3.weight(.semibold))
            if !summary.fileName.isEmpty {
                Text(summary.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = summary.errorMessage {
                Text(AppStrings.format("import.errorFormat", error))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(AppStrings.format(
                    "import.summaryFormat",
                    summary.addedCount,
                    summary.existingCount,
                    summary.invalidCount
                ))
            }
            if !summary.issues.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(summary.issues.enumerated()), id: \.offset) { _, issue in
                            Text("• \(issue.reason)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
            HStack {
                Spacer()
                Button(AppStrings.string("common.done")) { onClose() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
