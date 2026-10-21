import Foundation

@MainActor
struct DisclaimerAcceptanceStore {
    static let currentVersion = 1
    static let acceptanceVersionKey = "acceptedDisclaimerVersion"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasAcceptedCurrentDisclaimer: Bool {
        defaults.integer(forKey: Self.acceptanceVersionKey) >= Self.currentVersion
    }

    func acceptCurrentDisclaimer() {
        defaults.set(Self.currentVersion, forKey: Self.acceptanceVersionKey)
    }
}
