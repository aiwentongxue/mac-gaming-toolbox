import Foundation

enum RelativeTime {
    static func string(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: AppStrings.localeIdentifier)
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
