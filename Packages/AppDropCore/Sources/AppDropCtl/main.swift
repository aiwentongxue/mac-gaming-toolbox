import Foundation
import AppDropCore
import SwiftData

// appdropctl — development and integration-testing tool for the shared store.
// It is not shipped inside AppDrop.app. It opens the same local store as the
// app and helper so scripts can seed and verify data cross-process.

struct CLIError: Error, LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("appdropctl: \(message)\n".utf8))
    exit(code)
}

func makeContainer() throws -> ModelContainer {
    try SharedStore.makeContainer()
}

func requireOption(_ options: [String: String], _ key: String) throws -> String {
    guard let value = options[key], !value.isEmpty else {
        throw CLIError(message: "missing --\(key)")
    }
    return value
}

func parseOptions(_ arguments: [String]) throws -> [String: String] {
    var options: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        guard argument.hasPrefix("--") else {
            throw CLIError(message: "unexpected argument \"\(argument)\"")
        }
        let key = String(argument.dropFirst(2))
        guard index + 1 < arguments.count else {
            throw CLIError(message: "missing value for --\(key)")
        }
        options[key] = arguments[index + 1]
        index += 2
    }
    return options
}

func printUsage() {
    let usage = """
    usage: appdropctl <command> [options]

      store-path
      info [--json]
      list [--json]
      add-test-entry --track-id <id> --country <cc> [--name <name>] [--price <decimal>] [--currency <code>] [--formatted <text>] [--without-price]
      set-price --track-id <id> --country <cc> --price <decimal> --currency <code> [--formatted <text>]
      simulate-drop --track-id <id> --country <cc> [--to-price <decimal>] [--currency <code>] [--formatted <text>]
      remove-test-entry --track-id <id> --country <cc>
      records --track-id <id> --country <cc> [--json]
      clear-runs
      search --term <text> --country <cc> [--platform mac|ios]
      lookup --track-id <id> --country <cc>
      export-wishdrop --output <path> [--title <title>]
      import-wishdrop --input <path>
      validate-wishdrop --input <path>
    """
    print(usage)
}

func run() async throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        printUsage()
        exit(64)
    }
    arguments.removeFirst()
    let options = try parseOptions(arguments)

    switch command {
    case "store-path":
        let support = try SharedStore.supportDirectoryURL()
        let storeURL = try SharedStore.storeURL()
        print("storageRoot: \(support.path)")
        print("supportDirectory: \(support.path)")
        print("storeURL: \(storeURL.path)")

    case "info":
        let container = try makeContainer()
        let report = try await Diagnostics.storeInfo(container: container)
        if options["json"] != nil {
            print(Diagnostics.jsonString(report))
        } else {
            print("store: \(report.storePath)")
            print("trackedApps: \(report.trackedApps) priceRecords: \(report.priceRecords) checkRuns: \(report.checkRuns)")
            if let lastRun = report.lastRun {
                print("lastRun: \(lastRun.source) \(lastRun.outcome) checked=\(lastRun.checkedCount) changed=\(lastRun.changedCount) failed=\(lastRun.failedCount)")
            }
        }

    case "list":
        let container = try makeContainer()
        let store = AppDataStore(modelContainer: container)
        let snapshots = try await store.allSnapshots()
        if options["json"] != nil {
            let rows = snapshots.map { snapshot -> [String: String] in
                [
                    "trackId": snapshot.trackId,
                    "countryCode": snapshot.countryCode,
                    "name": snapshot.name,
                    "price": snapshot.price.price.map { "\($0)" } ?? "",
                    "formattedPrice": snapshot.price.formattedPrice ?? "",
                    "currency": snapshot.price.currency ?? "",
                    "status": snapshot.lastCheckStatus.rawValue,
                    "lastCheckedAt": snapshot.lastCheckedAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
                ]
            }
            print(Diagnostics.jsonString(rows))
        } else {
            for snapshot in snapshots {
                let price = snapshot.price.formattedPrice ?? "-"
                let currency = snapshot.price.currency ?? "-"
                print("\(snapshot.trackId) [\(snapshot.countryCode)] \(snapshot.name) price=\(price) \(currency) status=\(snapshot.lastCheckStatus.rawValue)")
            }
            print("total: \(snapshots.count)")
        }

    case "add-test-entry":
        let trackId = try requireOption(options, "track-id")
        let country = try requireOption(options, "country")
        let name = options["name"] ?? "Test App \(trackId)"
        let container = try makeContainer()
        let store = AppDataStore(modelContainer: container)
        let withoutPrice = options["without-price"] != nil
        let price = withoutPrice ? nil : Decimal(string: options["price"] ?? "9.99")
        let currency = withoutPrice ? nil : (options["currency"] ?? "USD")
        let formatted = withoutPrice ? nil : (options["formatted"] ?? price.map { "\($0) \(currency ?? "")" })
        let snapshot = try await store.insert(NewTrackedAppDraft(
            trackId: trackId,
            countryCode: country,
            name: name,
            appStoreURL: "https://apps.apple.com/\(StoreCountry.normalized(country))/app/id\(trackId)",
            price: price,
            formattedPrice: formatted,
            currency: currency
        ), now: Date())
        print("added \(snapshot.logicalKey)")

    case "set-price", "simulate-drop":
        let trackId = try requireOption(options, "track-id")
        let country = try requireOption(options, "country")
        let container = try makeContainer()
        let store = AppDataStore(modelContainer: container)
        let existing = try await store.snapshot(trackId: trackId, countryCode: country)
        guard let existing else {
            throw CLIError(message: "no tracked entry for \(trackId) in \(country); run add-test-entry first")
        }
        let defaultPrice: Decimal = command == "simulate-drop"
            ? (existing.price.price.map { $0 + 5 } ?? Decimal(string: "9.99") ?? 0)
            : (existing.price.price ?? 0)
        let price = Decimal(string: options["to-price"] ?? options["price"] ?? "\(defaultPrice)") ?? defaultPrice
        let currency = options["currency"] ?? existing.price.currency ?? "USD"
        let formatted = options["formatted"] ?? "\(price) \(currency)"
        let snapshot = try await store.setStoredPrice(
            trackId: trackId,
            countryCode: country,
            price: price,
            formattedPrice: formatted,
            currency: currency,
            now: Date()
        )
        print("stored price for \(snapshot.logicalKey) is now \(formatted)")

    case "remove-test-entry":
        let trackId = try requireOption(options, "track-id")
        let country = try requireOption(options, "country")
        let container = try makeContainer()
        let store = AppDataStore(modelContainer: container)
        guard let snapshot = try await store.snapshot(trackId: trackId, countryCode: country) else {
            throw CLIError(message: "no tracked entry for \(trackId) in \(country)")
        }
        try await store.delete(appID: snapshot.id)
        print("removed \(snapshot.logicalKey)")

    case "records":
        let trackId = try requireOption(options, "track-id")
        let country = try requireOption(options, "country")
        let container = try makeContainer()
        let store = AppDataStore(modelContainer: container)
        let records = try await store.records(trackId: trackId, countryCode: country)
        if options["json"] != nil {
            let rows = records.map { record -> [String: String] in
                [
                    "timestamp": ISO8601DateFormatter().string(from: record.timestamp),
                    "type": record.recordType.rawValue,
                    "price": "\(record.price)",
                    "formattedPrice": record.formattedPrice,
                    "currency": record.currency,
                    "notifiedAt": record.notifiedAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
                ]
            }
            print(Diagnostics.jsonString(rows))
        } else {
            for record in records {
                let notified = record.notifiedAt == nil ? "" : " notified"
                print("\(record.timestamp) \(record.recordType.rawValue) \(record.formattedPrice) \(record.currency)\(notified)")
            }
            print("total: \(records.count)")
        }

    case "clear-runs":
        let container = try makeContainer()
        let store = AppDataStore(modelContainer: container)
        try await store.clearRunLogs()
        print("cleared check-run history")

    case "search":
        let term = try requireOption(options, "term")
        let country = try requireOption(options, "country")
        let platform = AppStoreSearchPlatform(rawValue: options["platform"] ?? "mac") ?? .macOS
        let results = try await AppStoreService().search(keyword: term, country: country, platform: platform)
        let rows = results.map { app -> [String: String] in
            [
                "trackId": app.trackId,
                "name": app.name,
                "developerName": app.developerName ?? "",
                "price": app.price.map { "\($0)" } ?? "",
                "formattedPrice": app.formattedPrice ?? "",
                "currency": app.currency ?? "",
                "platform": app.platform.rawValue
            ]
        }
        print(Diagnostics.jsonString(rows))

    case "lookup":
        let trackId = try requireOption(options, "track-id")
        let country = try requireOption(options, "country")
        let service = AppStoreService()
        guard let app = try await service.lookupOne(appId: trackId, country: country) else {
            throw CLIError(message: "app \(trackId) not found in storefront \(country)")
        }
        let report: [String: String] = [
            "trackId": app.trackId,
            "name": app.name,
            "developerName": app.developerName ?? "",
            "price": app.price.map { "\($0)" } ?? "",
            "formattedPrice": app.formattedPrice ?? "",
            "currency": app.currency ?? "",
            "appStoreURL": app.appStoreURL ?? ""
        ]
        print(Diagnostics.jsonString(report))

    case "export-wishdrop":
        let output = try requireOption(options, "output")
        let title = options["title"] ?? "AppDrop Wishlist"
        let container = try makeContainer()
        let store = AppDataStore(modelContainer: container)
        let snapshots = try await store.allSnapshots()
        let preset = WishdropCodec.makePreset(title: title, snapshots: snapshots, exportedAt: Date())
        let data = try WishdropCodec.encode(preset)
        try data.write(to: URL(fileURLWithPath: output))
        print("exported \(snapshots.count) entries to \(output)")

    case "import-wishdrop":
        let input = try requireOption(options, "input")
        let data = try Data(contentsOf: URL(fileURLWithPath: input))
        let preset = try WishdropCodec.decode(data)
        let validation = WishdropCodec.validateEntries(preset)
        let container = try makeContainer()
        let store = AppDataStore(modelContainer: container)
        let outcome = try await store.importWishdrop(entries: validation.valid, now: Date())
        print("added: \(outcome.addedKeys.count), alreadyTracked: \(outcome.alreadyTrackedKeys.count), invalid: \(validation.issues.count)")
        for issue in validation.issues {
            print("  entry[\(issue.index)] \(issue.code.rawValue): \(issue.reason)")
        }

    case "validate-wishdrop":
        let input = try requireOption(options, "input")
        let data = try Data(contentsOf: URL(fileURLWithPath: input))
        let preset = try WishdropCodec.decode(data)
        let validation = WishdropCodec.validateEntries(preset)
        print("title: \"\(preset.title)\", version: \(preset.version), author: \"\(preset.author ?? "")\", total: \(preset.apps.count)")
        print("valid: \(validation.valid.count), invalid: \(validation.issues.count)")
        for issue in validation.issues {
            print("  entry[\(issue.index)] \(issue.code.rawValue): \(issue.reason)")
        }

    default:
        printUsage()
        exit(64)
    }
}

do {
    try await run()
    exit(0)
} catch {
    fail("\(error.localizedDescription)")
}
