import Combine
import Foundation

/// Delivers AppKit delegate events (Finder "open with") to the SwiftUI layer
/// even when they arrive before the environment is wired up.
@MainActor
final class AppEventBus: ObservableObject {
    static let shared = AppEventBus()

    @Published var queuedFileURLs: [URL] = []

    private init() {}
}
