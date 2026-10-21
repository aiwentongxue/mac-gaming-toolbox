import AppKit
import AppDropCore
import SwiftUI

struct TrackedAppIconView: View {
    let artworkURL: String?
    var size: CGFloat = 42

    var body: some View {
        AsyncImage(url: artworkURL.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            default:
                RoundedRectangle(cornerRadius: size * 0.22)
                    .fill(.quaternary)
                    .overlay(
                        Image(systemName: "app")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }
}

struct RegionBadge: View {
    let countryCode: String

    var body: some View {
        Text(StoreCountry.displayCode(for: countryCode))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.quaternary))
    }
}

/// Shows whether a search result comes from the Mac or the iPhone/iPad catalog.
struct PlatformBadge: View {
    let platform: AppStoreAppPlatform

    var body: some View {
        Text(AppStrings.string(platform == .macOS ? "platform.mac" : "platform.ios"))
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(.secondary)
            .background(Capsule().fill(.quaternary))
    }
}

struct NewLowBadge: View {
    var body: some View {
        Text(AppStrings.string("card.newLowBadge"))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.green)
            .background(Capsule().fill(.green.opacity(0.14)))
    }
}

struct PriceWithCurrency: View {
    let formattedPrice: String?
    let currency: String?
    var font: Font = .title3

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(formattedPrice ?? AppStrings.string("card.pendingPrice"))
                .font(font.weight(.semibold))
            if let currency {
                Text(currency)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DiscountLine: View {
    let app: TrackedApp

    var body: some View {
        if app.isDiscounted, app.discountRate > 0 {
            Text(AppStrings.format("card.discountSinceLast", PriceFormatting.percentString(app.discountRate) + "%"))
                .font(.caption)
                .foregroundStyle(.green)
        }
    }
}

struct LastCheckedLine: View {
    let date: Date?

    var body: some View {
        if let date {
            Text(AppStrings.format("card.lastCheckedFormat", RelativeTime.string(for: date)))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(AppStrings.string("card.neverChecked"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct TrackedAppCardView: View {
    let app: TrackedApp
    var isSelectMode: Bool = false
    var isSelected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                TrackedAppIconView(artworkURL: app.artworkURL)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        RegionBadge(countryCode: app.countryCode)
                        if app.isAtHistoricalLow {
                            NewLowBadge()
                        }
                    }
                }
                Spacer(minLength: 0)
                if isSelectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
            }
            PriceWithCurrency(formattedPrice: app.formattedPrice, currency: app.currency)
            VStack(alignment: .leading, spacing: 3) {
                DiscountLine(app: app)
                if let lowest = app.lowestPrice {
                    // A single observation is a baseline, not a verified low;
                    // keep the wording honest until a comparison exists.
                    let key = app.priceObservationCount >= 2 ? "card.lowestFormat" : "card.firstRecordFormat"
                    Text(AppStrings.format(key, PriceFormatting.priceString(lowest, currency: app.currency ?? "")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LastCheckedLine(date: app.lastCheckedAt)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct TrackedAppRowView: View {
    let app: TrackedApp
    var isSelectMode: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if isSelectMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            TrackedAppIconView(artworkURL: app.artworkURL, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    RegionBadge(countryCode: app.countryCode)
                    DiscountLine(app: app)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                PriceWithCurrency(
                    formattedPrice: app.formattedPrice,
                    currency: app.currency,
                    font: .body
                )
                HStack(spacing: 6) {
                    if app.isAtHistoricalLow {
                        NewLowBadge()
                    }
                    LastCheckedLine(date: app.lastCheckedAt)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
