import Foundation

@MainActor
final class AutomationCoordinator: ObservableObject {
    enum Activity: Equatable {
        case idle
        case clicker
        case recording
        case playback(UUID)
        case combinedRecording
        case combinedPlayback(UUID)
    }

    @Published private(set) var activity: Activity = .idle

    func begin(_ activity: Activity) {
        self.activity = activity
    }

    func end(_ expected: Activity? = nil) {
        guard expected == nil || activity == expected else { return }
        activity = .idle
    }
}
