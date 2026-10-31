import Foundation
import AppDropCore

// AppDropHelper — background price-check helper.
//
// Execution modes (arguments):
//   --scheduled (default)                 honour the 20-hour minimum interval
//   --run-now                             ignore the interval and check now
//   --request-notification-authorization  trigger the helper's own permission prompt
//   --dump-store-info                     print the shared store report as JSON
//
// The helper shares the local SwiftData store with the main app and exits
// as soon as its task (and any scheduled notifications) are finished.

let arguments = Array(CommandLine.arguments.dropFirst())

func hasFlag(_ flag: String) -> Bool {
    arguments.contains(flag)
}

func writeErrorLine(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func emitNotificationResult<T: Encodable>(_ value: T, prefix: String) {
    do {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else { exit(1) }
        print(prefix + json)
    } catch {
        writeErrorLine(error.localizedDescription)
        exit(1)
    }
}

// Status/test modes intentionally run before resolving storage or a log file.
if hasFlag("--notification-status") {
    let report = await UserNotificationScheduler().statusReport()
    emitNotificationResult(report, prefix: "APPDROP_NOTIFICATION_STATUS ")
    exit(0)
}

if hasFlag("--test-notification") {
    let result = await UserNotificationScheduler().submitTestNotification()
    emitNotificationResult(result, prefix: "APPDROP_NOTIFICATION_TEST ")
    exit(0)
}

let helperLogURL = RefreshEngine.defaultLogURL()
AppLog.info("AppDropHelper started (arguments: \(arguments.joined(separator: " ")))", fileURL: helperLogURL)

if hasFlag("--dump-store-info") {
    do {
        let container = try SharedStore.makeContainer()
        let report = try await Diagnostics.storeInfo(container: container)
        print(Diagnostics.jsonString(report))
        exit(0)
    } catch {
        AppLog.error("store info failed: \(error.localizedDescription)", fileURL: helperLogURL)
        writeErrorLine("error: \(error.localizedDescription)")
        exit(1)
    }
}

if hasFlag("--store-diagnose") {
    var lines: [String] = []
    lines.append("process: \(ProcessInfo.processInfo.processName) pid=\(ProcessInfo.processInfo.processIdentifier)")
    lines.append("HOME: \(ProcessInfo.processInfo.environment["HOME"] ?? "-")")
    lines.append("sandbox container id: \(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] ?? "-")")
    lines.append("storage root: \(SharedStore.resolvedStorageRoot?.url.path ?? "<none>")")
    lines.append("storeURL: \(String(describing: try? SharedStore.storeURL()))")
    do {
        let container = try SharedStore.makeContainer()
        let report = try await Diagnostics.storeInfo(container: container)
        lines.append("ModelContainer: OK")
        lines.append("trackedApps=\(report.trackedApps) priceRecords=\(report.priceRecords) checkRuns=\(report.checkRuns)")
    } catch {
        lines.append("ModelContainer: FAILED \(error.localizedDescription)")
    }
    let permission = await UserNotificationScheduler().permission()
    lines.append("notification permission: \(permission.rawValue)")
    let text = lines.joined(separator: "\n")
    print(text)
    if let home = ProcessInfo.processInfo.environment["HOME"] {
        try? text.write(
            to: URL(fileURLWithPath: home).appendingPathComponent("appdrop-helper-diagnose.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
    exit(0)
}

if hasFlag("--request-notification-authorization") {
    let scheduler = UserNotificationScheduler()
    let current = await scheduler.permission()
    let status = current == .notDetermined ? await scheduler.requestPermission() : current
    AppLog.info("notification permission is \(status.rawValue)", fileURL: helperLogURL)
    print("notification-permission: \(status.rawValue)")
    exit(0)
}

do {
    let container = try SharedStore.makeContainer()
    let engine = RefreshEngine(
        container: container,
        fetcher: AppStoreService(),
        notifier: UserNotificationScheduler(),
        lockURL: RefreshEngine.defaultLockURL(),
        logURL: helperLogURL
    )
    let force = hasFlag("--run-now")
    let summary = await engine.run(source: .background, mode: .skipIfBusy, force: force)
    print("APPDROP_RESULT \(Diagnostics.jsonString(summary))")
    exit(0)
} catch {
    AppLog.error("helper run failed: \(error.localizedDescription)", fileURL: helperLogURL)
    writeErrorLine("error: \(error.localizedDescription)")
    exit(1)
}
