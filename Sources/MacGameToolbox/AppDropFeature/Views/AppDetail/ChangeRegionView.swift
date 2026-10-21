import AppDropCore
import SwiftUI

/// Sheet used to move a tracked app to another storefront.
///
/// A `confirmationDialog` renders only a couple of action buttons on macOS and
/// silently drops the rest, so the full storefront list is presented as a
/// scrollable list instead.
struct ChangeRegionView: View {
    let currentCountryCode: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private var otherRegions: [StoreRegion] {
        let current = StoreCountry.normalized(currentCountryCode)
        return StoreCountry.regions.filter { $0.code != current }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppStrings.string("detail.changeRegionTitle"))
                .font(.headline)
            Text(AppStrings.string("detail.changeRegionMessage"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(otherRegions) { region in
                Button {
                    onSelect(region.code)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Text(AppStrings.regionLabel(region.code))
                        Spacer(minLength: 12)
                        Text("\(region.currency) \(region.symbol)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
            .frame(minHeight: 260)

            HStack {
                Spacer()
                Button(AppStrings.string("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 460)
    }
}
