import AppKit
import AppDropCore
import SwiftData
import SwiftUI

struct AppDropSettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    @Query(sort: [SortDescriptor(\CheckRunLog.startedAt, order: .reverse)])
    private var runs: [CheckRunLog]

    @State private var notificationStatus: NotificationPermissionStatus = .notDetermined
    @State private var backendError: String?
    @State private var busy = false
    @State private var changingAllRegions = false
    @State private var confirmingChangeAllRegions = false
    @State private var changeAllResultMessage: String?

    var body: some View {
        Form {
            Section {
                Picker(AppStrings.string("settings.defaultRegion"), selection: Binding(
                    get: { environment.defaultCountryCode },
                    set: { environment.setDefaultCountryCode($0) }
                )) {
                    ForEach(SharedConstants.supportedCountryCodes, id: \.self) { code in
                        Text(AppStrings.regionLabel(code)).tag(code)
                    }
                }
                HStack(alignment: .center, spacing: 12) {
                    Text(AppStrings.string("settings.defaultRegionCaption"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 16)

                    if changingAllRegions {
                        ProgressView().controlSize(.small)
                    }

                    Button(AppStrings.string("settings.changeAllToDefaultRegion")) {
                        confirmingChangeAllRegions = true
                    }
                    .disabled(changingAllRegions || busy || environment.refresh?.isRefreshing == true)
                }
            }

            Section(AppStrings.string("settings.notifications")) {
                LabeledContent(AppStrings.string("settings.notificationStatus")) {
                    Text(AppStrings.string(notificationStatusKey(notificationStatus)))
                }
                HStack {
                    Button(AppStrings.string("settings.requestNotification")) {
                        Task {
                            notificationStatus = await environment.notificationScheduler.requestPermission()
                        }
                    }
                    .disabled(notificationStatus == .authorized)
                    Button(AppStrings.string("settings.openNotificationSettings")) {
                        openSystemSettings("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
                    }
                }
                Text(AppStrings.string("settings.helperPermissionHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(AppStrings.string("settings.background")) {
                Toggle(AppStrings.string("settings.backgroundToggle"), isOn: backgroundBinding)
                    .toggleStyle(.switch)
                LabeledContent(AppStrings.string("settings.background")) {
                    Text(AppStrings.string(backendStateKey(environment.backend.state)))
                }
                if environment.backend.state == .requiresApproval {
                    Text(AppStrings.string("settings.backend.requiresApprovalHint"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(AppStrings.string("settings.openLoginItems")) {
                        openSystemSettings("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
                    }
                }
                if let backendError {
                    Text(backendError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                LabeledContent(AppStrings.string("settings.lastAttempt")) {
                    Text(lastRunDateText)
                }
                LabeledContent(AppStrings.string("settings.lastSuccess")) {
                    Text(lastSuccessDateText)
                }
                if let errorText = lastErrorText {
                    LabeledContent(AppStrings.string("settings.lastError")) {
                        Text(errorText)
                            .lineLimit(2)
                            .foregroundStyle(.red)
                    }
                }
                HStack {
                    Button(AppStrings.string("settings.runCheck")) {
                        Task { await environment.refreshAll() }
                    }
                    .disabled(environment.refresh?.isRefreshing == true || busy)
                    if environment.refresh?.isRefreshing == true {
                        ProgressView().controlSize(.small)
                    }
                    Button(AppStrings.string("settings.reRegister")) {
                        reRegister()
                    }
                    .disabled(busy)
                }
                if let summary = environment.refresh?.lastSummary {
                    Text(AppStrings.format(
                        "refresh.summaryFormat",
                        summary.checkedCount,
                        summary.changedCount,
                        summary.failedCount
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Text(AppStrings.string("settings.backgroundNote"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(AppStrings.string("settings.storage")) {
                if let storeURL = try? SharedStore.storeURL(createDirectory: false) {
                    LabeledContent(AppStrings.string("settings.storePath")) {
                        Text(storeURL.path)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    Button(AppStrings.string("settings.revealInFinder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([storeURL])
                    }
                }
            }

            Section(AppStrings.string("settings.about")) {
                LabeledContent("AppDrop", value: versionString)
                Text("Copyright (C) 2026 我是艾文喵")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(AppStrings.format(
                    "settings.storageIdentity",
                    SharedConstants.storageDirectoryName,
                    SharedConstants.helperBundleIdentifier
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(AppStrings.string("settings.title"))
        .confirmationDialog(
            AppStrings.string("settings.changeAllConfirmTitle"),
            isPresented: $confirmingChangeAllRegions,
            titleVisibility: .visible
        ) {
            Button(AppStrings.string("settings.changeAllConfirmAction")) {
                performChangeAllRegions()
            }
            Button(AppStrings.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(AppStrings.format(
                "settings.changeAllConfirmMessage",
                AppStrings.regionLabel(environment.defaultCountryCode)
            ))
        }
        .alert(
            AppStrings.string("settings.changeAllResultTitle"),
            isPresented: Binding(
                get: { changeAllResultMessage != nil },
                set: { if !$0 { changeAllResultMessage = nil } }
            )
        ) {
            Button(AppStrings.string("common.ok")) {
                changeAllResultMessage = nil
            }
        } message: {
            Text(changeAllResultMessage ?? "")
        }
        .task {
            notificationStatus = await environment.notificationScheduler.permission()
            environment.backend.refreshStatus()
        }
    }

    private func performChangeAllRegions() {
        changingAllRegions = true
        let targetCode = environment.defaultCountryCode
        Task {
            let result = await environment.changeAllAppsRegion(to: targetCode)
            changingAllRegions = false
            let targetLabel = AppStrings.regionLabel(targetCode)
            changeAllResultMessage = AppStrings.format(
                "settings.changeAllResultMessage",
                result.updatedCount,
                targetLabel,
                result.unchangedCount,
                result.unavailableCount + result.duplicateCount
            )
        }
    }

    private var backgroundBinding: Binding<Bool> {
        Binding(
            get: {
                environment.backend.state == .enabled || environment.backend.state == .requiresApproval
            },
            set: { enabled in
                backendError = nil
                do {
                    if enabled {
                        try environment.backend.enable()
                    } else {
                        try environment.backend.disable()
                    }
                } catch {
                    backendError = error.localizedDescription
                }
                environment.backend.refreshStatus()
            }
        )
    }

    private var lastRunDateText: String {
        guard let run = runs.first else { return "—" }
        return RelativeTime.string(for: run.startedAt)
    }

    private var lastSuccessDateText: String {
        guard let run = runs.first(where: { $0.outcome == .success || $0.outcome == .partial }) else { return "—" }
        return RelativeTime.string(for: run.finishedAt ?? run.startedAt)
    }

    private var lastErrorText: String? {
        guard let latest = runs.first else { return nil }
        if (latest.outcome == .failed || latest.outcome == .partial),
           let summary = latest.errorSummary, !summary.isEmpty {
            return summary
        }
        return nil
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return AppStrings.format("settings.versionFormat", version, build)
    }

    private func reRegister() {
        backendError = nil
        busy = true
        do {
            try environment.backend.disable()
        } catch {
            // Re-registration is best effort; enabling below reports real errors.
        }
        do {
            try environment.backend.enable()
        } catch {
            backendError = error.localizedDescription
        }
        environment.backend.refreshStatus()
        busy = false
    }

    private func openSystemSettings(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

func notificationStatusKey(_ status: NotificationPermissionStatus) -> String {
    switch status {
    case .notDetermined: "permission.notDetermined"
    case .denied: "permission.denied"
    case .authorized: "permission.authorized"
    case .provisional: "permission.provisional"
    case .ephemeral: "permission.ephemeral"
    case .unknown: "permission.unknown"
    }
}

func backendStateKey(_ state: BackendState) -> String {
    switch state {
    case .notRegistered: "settings.backend.notRegistered"
    case .enabled: "settings.backend.enabled"
    case .requiresApproval: "settings.backend.requiresApproval"
    case .notFound: "settings.backend.notFound"
    case .unknown: "settings.backend.unknown"
    }
}
