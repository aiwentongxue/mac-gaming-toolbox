import AppDropCore
import Combine
import SwiftData
import SwiftUI

@MainActor
final class AppDropFeatureController: ObservableObject {
    let environment: AppEnvironment
    private var cancellables = Set<AnyCancellable>()

    init(environment: AppEnvironment = AppEnvironment()) {
        self.environment = environment
        AppEventBus.shared.$queuedFileURLs
            .sink { [weak self] urls in
                guard let self, !urls.isEmpty else { return }
                self.environment.handleIncomingFiles(urls)
                AppEventBus.shared.queuedFileURLs.removeAll()
                NotificationCenter.default.post(
                    name: .toolboxNavigateToAppDropWishlist,
                    object: nil
                )
            }
            .store(in: &cancellables)
    }

    func open(urls: [URL]) {
        guard !urls.isEmpty else { return }
        environment.handleIncomingFiles(urls)
        NotificationCenter.default.post(
            name: .toolboxNavigateToAppDropWishlist,
            object: nil
        )
    }
}

struct AppDropFeatureHost: View {
    @ObservedObject var controller: AppDropFeatureController
    let page: AppDropPage

    var body: some View {
        Group {
            if let startupError = controller.environment.startupError {
                AppDropStartupErrorView(message: startupError)
            } else if let container = controller.environment.container {
                AppDropPageView(page: page)
                    .environmentObject(controller.environment)
                    .modelContainer(container)
            } else {
                AppDropStartupErrorView(message: AppStrings.string("startup.storageHint"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AppDropStartupErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(AppStrings.string("startup.title"))
                .font(.title2.weight(.semibold))
            Text(AppStrings.string("startup.storageHint"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 620)
        }
        .padding(28)
    }
}

extension Notification.Name {
    static let toolboxNavigateToAppDropWishlist = Notification.Name(
        "toolbox.navigate.appdrop.wishlist"
    )
}
