import CryptoKit
import Foundation

struct CrossOverCommandResult: Sendable {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String
}

protocol CrossOverCommandRunning: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> CrossOverCommandResult
}

actor CrossOverProcessRunner: CrossOverCommandRunning {
    func run(executable: URL, arguments: [String]) async throws -> CrossOverCommandResult {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        async let outputData = output.fileHandleForReading.readToEnd() ?? Data()
        async let errorData = error.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        let (capturedOutput, capturedError) = try await (outputData, errorData)
        return CrossOverCommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: String(decoding: capturedOutput, as: UTF8.self),
            standardError: String(decoding: capturedError, as: UTF8.self)
        )
    }
}

struct CrossOverEnvironment: Sendable {
    let applications: [CrossOverApplication]
    let bottles: [ClickFlowCrossOverBottle]
}

actor CrossOverGameIntegrationService {
    static let registryKey = #"HKCU\Software\Wine\DllOverrides"#
    static let supportedDLLNames = [
        "xinput1_1.dll", "xinput1_2.dll", "xinput1_3.dll", "xinput1_4.dll", "xinput9_1_0.dll"
    ]

    private let fileManager: FileManager
    private let commandRunner: any CrossOverCommandRunning
    private let proxyRootURL: URL?
    private let recordsRootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        commandRunner: any CrossOverCommandRunning = CrossOverProcessRunner(),
        proxyRootURL: URL? = nil,
        recordsRootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
        self.proxyRootURL = proxyRootURL ?? ClickFlowL10n.resourceBundle.resourceURL
        self.recordsRootURL = recordsRootURL ?? ClickFlowFeatureController.defaultApplicationSupportRoot()
        .appendingPathComponent("CrossOverGameAdapters", isDirectory: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func discoverEnvironment() -> CrossOverEnvironment {
        CrossOverEnvironment(
            applications: discoverCrossOverApplications(),
            bottles: discoverBottles()
        )
    }

    func plan(gameURL: URL, preset requestedPreset: CrossOverGamePreset) throws -> CrossOverAdapterPlan {
        guard fileManager.fileExists(atPath: gameURL.path),
              gameURL.pathExtension.lowercased() == "exe" else {
            throw CrossOverIntegrationError.invalidSelection(
                cf("windowsGames.error.chooseExecutable")
            )
        }
        let architecture = try inspectPEArchitecture(at: gameURL)
        guard architecture != .unsupported else {
            throw CrossOverIntegrationError.unsupportedExecutable
        }

        let resolvedPreset: CrossOverGamePreset
        if requestedPreset == .automatic {
            resolvedPreset = CrossOverGamePreset.knownPreset(for: gameURL.lastPathComponent) ?? .automatic
        } else {
            resolvedPreset = requestedPreset
        }

        var detected: [String] = []
        let dllNames: [String]
        if let fixed = resolvedPreset.fixedDLLNames {
            dllNames = fixed
        } else {
            let nearbyUnityPlayer = gameURL.deletingLastPathComponent().appendingPathComponent("UnityPlayer.dll")
            var scannedURLs = [gameURL]
            if fileManager.fileExists(atPath: nearbyUnityPlayer.path) {
                scannedURLs.append(nearbyUnityPlayer)
            }
            detected = detectXInputDLLNames(in: scannedURLs)
            guard !detected.isEmpty else {
                throw CrossOverIntegrationError.invalidSelection(
                    cf("windowsGames.error.noXInputEvidence")
                )
            }
            dllNames = Self.supportedDLLNames.filter { detected.contains($0) }
        }

        return CrossOverAdapterPlan(
            preset: resolvedPreset,
            architecture: architecture,
            dllNames: dllNames,
            disableWindowsGamingInput: resolvedPreset.disablesWindowsGamingInput,
            detectedDLLNames: detected,
            antiCheatFiles: detectAntiCheatFiles(near: gameURL)
        )
    }

    func diagnose(
        gameURL: URL?,
        bottle: ClickFlowCrossOverBottle?,
        application: CrossOverApplication?,
        preset: CrossOverGamePreset
    ) async -> CrossOverDiagnosticReport {
        var items: [CrossOverDiagnosticItem] = []
        var resolvedPlan: CrossOverAdapterPlan?

        guard let gameURL else {
            items.append(.init(
                id: "game", severity: .failed,
                title: cf("windowsGames.check.game"),
                detail: cf("windowsGames.error.chooseExecutable")
            ))
            return .init(generatedAt: .now, plan: nil, items: items, installedManifest: nil)
        }

        do {
            let plan = try plan(gameURL: gameURL, preset: preset)
            resolvedPlan = plan
            items.append(.init(
                id: "game", severity: .passed,
                title: cf("windowsGames.check.game"),
                detail: "\(gameURL.lastPathComponent) · \(plan.architecture.rawValue)"
            ))
            items.append(.init(
                id: "plan", severity: .information,
                title: cf("windowsGames.check.plan"),
                detail: plan.dllNames.joined(separator: ", ")
            ))
            if !plan.antiCheatFiles.isEmpty {
                items.append(.init(
                    id: "anticheat", severity: .warning,
                    title: cf("windowsGames.check.antiCheat"),
                    detail: plan.antiCheatFiles.joined(separator: ", ")
                ))
            }
        } catch {
            items.append(.init(
                id: "game", severity: .failed,
                title: cf("windowsGames.check.game"),
                detail: error.localizedDescription
            ))
        }

        if let bottle, fileManager.fileExists(atPath: bottle.registryURL.path) {
            items.append(.init(
                id: "bottle", severity: .passed,
                title: cf("windowsGames.check.bottle"),
                detail: "\(bottle.name) · \(bottle.version)"
            ))
        } else {
            items.append(.init(
                id: "bottle", severity: .failed,
                title: cf("windowsGames.check.bottle"),
                detail: cf("windowsGames.error.chooseBottle")
            ))
        }

        if let application, fileManager.isExecutableFile(atPath: application.wineURL.path) {
            items.append(.init(
                id: "crossover", severity: .passed,
                title: cf("windowsGames.check.crossOver"),
                detail: "\(application.displayName) · \(application.version)"
            ))
        } else {
            items.append(.init(
                id: "crossover", severity: .failed,
                title: cf("windowsGames.check.crossOver"),
                detail: cf("windowsGames.error.chooseCrossOver")
            ))
        }

        if let resolvedPlan, let directory = resolvedPlan.architecture.resourceDirectoryName,
           resolvedPlan.dllNames.allSatisfy({ proxyURL(named: $0, architectureDirectory: directory) != nil }) {
            items.append(.init(
                id: "resources", severity: .passed,
                title: cf("windowsGames.check.resources"),
                detail: cf("windowsGames.check.resources.ready")
            ))
        } else {
            items.append(.init(
                id: "resources", severity: .failed,
                title: cf("windowsGames.check.resources"),
                detail: cf("windowsGames.check.resources.missing")
            ))
        }

        let running = isGameRunning(gameURL)
        items.append(.init(
            id: "process",
            severity: running ? .warning : .passed,
            title: cf("windowsGames.check.process"),
            detail: cf(running ? "windowsGames.check.process.running" : "windowsGames.check.process.stopped")
        ))

        let heartbeat = controllerHeartbeatDescription()
        items.append(.init(
            id: "publisher",
            severity: heartbeat.active ? .passed : .information,
            title: cf("windowsGames.check.publisher"),
            detail: heartbeat.detail
        ))

        let installed = manifest(for: gameURL, bottle: bottle)
        if let installed {
            items.append(.init(
                id: "installation",
                severity: installed.state == .installed ? .passed : .information,
                title: cf("windowsGames.check.installation"),
                detail: cf(installed.state == .installed
                    ? "windowsGames.check.installation.installed"
                    : "windowsGames.check.installation.restored")
            ))
            if installed.state == .installed,
               let bottle, let application, let resolvedPlan {
                let gameDirectory = gameURL.deletingLastPathComponent()
                for file in installed.files {
                    let target = gameDirectory.appendingPathComponent(file.name)
                    let currentHash = try? sha256(of: target)
                    let intact = currentHash == file.installedSHA256
                    items.append(.init(
                        id: "file.\(file.name)",
                        severity: intact ? .passed : .failed,
                        title: file.name,
                        detail: cf(intact
                            ? "windowsGames.check.file.intact"
                            : "windowsGames.check.file.changed")
                    ))
                }
                for dll in resolvedPlan.dllNames {
                    let value = try? await queryRegistryValue(
                        named: dll.replacingOccurrences(of: ".dll", with: ""),
                        application: application,
                        bottle: bottle
                    )
                    items.append(.init(
                        id: "registry.\(dll)",
                        severity: value == "native,builtin" ? .passed : .warning,
                        title: dll,
                        detail: value ?? cf("windowsGames.check.registry.missing")
                    ))
                }
            }
        }

        return .init(
            generatedAt: .now,
            plan: resolvedPlan,
            items: items,
            installedManifest: installed
        )
    }

    func install(
        gameURL: URL,
        bottle: ClickFlowCrossOverBottle,
        application: CrossOverApplication,
        preset: CrossOverGamePreset
    ) async throws -> CrossOverIntegrationManifest {
        guard !isGameRunning(gameURL) else { throw CrossOverIntegrationError.gameIsRunning }
        guard fileManager.fileExists(atPath: bottle.registryURL.path) else {
            throw CrossOverIntegrationError.invalidSelection(cf("windowsGames.error.chooseBottle"))
        }
        guard fileManager.isExecutableFile(atPath: application.wineURL.path) else {
            throw CrossOverIntegrationError.invalidSelection(cf("windowsGames.error.chooseCrossOver"))
        }
        if let existing = manifest(for: gameURL, bottle: bottle), existing.state == .installed {
            return existing
        }

        let plan = try plan(gameURL: gameURL, preset: preset)
        guard let architectureDirectory = plan.architecture.resourceDirectoryName else {
            throw CrossOverIntegrationError.unsupportedExecutable
        }

        try fileManager.createDirectory(at: recordsRootURL, withIntermediateDirectories: true)
        let id = UUID()
        let recordURL = recordsRootURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let backupURL = recordURL.appendingPathComponent("Files", isDirectory: true)
        try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)
        let gameDirectory = gameURL.deletingLastPathComponent()
        var installedFiles: [CrossOverInstalledFile] = []

        for dllName in plan.dllNames {
            guard let source = proxyURL(named: dllName, architectureDirectory: architectureDirectory) else {
                throw CrossOverIntegrationError.missingProxy(dllName)
            }
            let target = gameDirectory.appendingPathComponent(dllName)
            let sourceHash = try sha256(of: source)
            var originalExisted = false
            var backupName: String?
            if fileManager.fileExists(atPath: target.path) {
                originalExisted = true
                backupName = dllName + ".original"
                try fileManager.copyItem(at: target, to: backupURL.appendingPathComponent(backupName!))
            }
            installedFiles.append(.init(
                name: dllName,
                installedSHA256: sourceHash,
                originalExisted: originalExisted,
                originalBackupName: backupName
            ))
        }

        let registryNames = plan.dllNames.map { $0.replacingOccurrences(of: ".dll", with: "") }
            + (plan.disableWindowsGamingInput ? ["windows.gaming.input"] : [])
        var registryBackups: [CrossOverRegistryValueBackup] = []
        for name in registryNames {
            let previous = try await queryRegistryValue(named: name, application: application, bottle: bottle)
            registryBackups.append(.init(
                name: name,
                previousValue: previous,
                installedValue: name == "windows.gaming.input" ? "disabled" : "native,builtin"
            ))
        }

        var manifest = CrossOverIntegrationManifest(
            id: id,
            state: .pending,
            gameExecutablePath: gameURL.standardizedFileURL.path,
            bottleName: bottle.name,
            bottlePath: bottle.url.standardizedFileURL.path,
            crossOverApplicationPath: application.url.standardizedFileURL.path,
            preset: plan.preset,
            architecture: plan.architecture,
            files: installedFiles,
            registryValues: registryBackups
        )
        try save(manifest, in: recordURL)

        do {
            for file in installedFiles {
                guard let source = proxyURL(named: file.name, architectureDirectory: architectureDirectory) else {
                    throw CrossOverIntegrationError.missingProxy(file.name)
                }
                try replaceFile(at: gameDirectory.appendingPathComponent(file.name), with: source)
            }
            for value in registryBackups {
                try await setRegistryValue(
                    named: value.name,
                    value: value.installedValue,
                    application: application,
                    bottle: bottle
                )
            }
            manifest.state = .installed
            manifest.updatedAt = .now
            try save(manifest, in: recordURL)
            return manifest
        } catch {
            try? await restore(manifest: manifest, allowPending: true)
            throw error
        }
    }

    func restore(manifest: CrossOverIntegrationManifest) async throws {
        try await restore(manifest: manifest, allowPending: false)
    }

    private func restore(
        manifest: CrossOverIntegrationManifest,
        allowPending: Bool
    ) async throws {
        guard manifest.state == .installed || (allowPending && manifest.state == .pending) else { return }
        let gameURL = URL(fileURLWithPath: manifest.gameExecutablePath)
        guard !isGameRunning(gameURL) else { throw CrossOverIntegrationError.gameIsRunning }
        let recordURL = recordsRootURL.appendingPathComponent(manifest.id.uuidString, isDirectory: true)
        let backupURL = recordURL.appendingPathComponent("Files", isDirectory: true)
        let gameDirectory = gameURL.deletingLastPathComponent()

        for file in manifest.files {
            let target = gameDirectory.appendingPathComponent(file.name)
            if fileManager.fileExists(atPath: target.path) {
                let targetHash = try sha256(of: target)
                if targetHash == file.installedSHA256 { continue }
                if allowPending, file.originalExisted, let backupName = file.originalBackupName {
                    let backup = backupURL.appendingPathComponent(backupName)
                    if fileManager.fileExists(atPath: backup.path),
                       targetHash == (try sha256(of: backup)) {
                        continue
                    }
                }
                throw CrossOverIntegrationError.unsafeRestore(file.name)
            }
        }

        let application = CrossOverApplication(
            url: URL(fileURLWithPath: manifest.crossOverApplicationPath),
            displayName: URL(fileURLWithPath: manifest.crossOverApplicationPath).deletingPathExtension().lastPathComponent,
            version: ""
        )
        let bottle = ClickFlowCrossOverBottle(
            name: manifest.bottleName,
            url: URL(fileURLWithPath: manifest.bottlePath),
            version: "",
            is64Bit: manifest.architecture == .x64
        )

        // Restore registry values first. These operations are idempotent, so a
        // command failure can be retried without leaving file restoration half done.
        for value in manifest.registryValues {
            if let previous = value.previousValue {
                try await setRegistryValue(
                    named: value.name,
                    value: previous,
                    application: application,
                    bottle: bottle
                )
            } else {
                try await deleteRegistryValue(
                    named: value.name,
                    application: application,
                    bottle: bottle
                )
            }
        }
        for file in manifest.files {
            let target = gameDirectory.appendingPathComponent(file.name)
            if file.originalExisted, let backupName = file.originalBackupName {
                try replaceFile(at: target, with: backupURL.appendingPathComponent(backupName))
            } else if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
        }
        var restored = manifest
        restored.state = .restored
        restored.updatedAt = .now
        try save(restored, in: recordURL)
    }

    func manifests() -> [CrossOverIntegrationManifest] {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: recordsRootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return directories.compactMap { directory in
            let url = directory.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(CrossOverIntegrationManifest.self, from: data)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func manifest(
        for gameURL: URL,
        bottle: ClickFlowCrossOverBottle?
    ) -> CrossOverIntegrationManifest? {
        guard let bottle else { return nil }
        let gamePath = gameURL.standardizedFileURL.path
        let bottlePath = bottle.url.standardizedFileURL.path
        return manifests().first {
            $0.gameExecutablePath == gamePath && $0.bottlePath == bottlePath
        }
    }

    private func discoverCrossOverApplications() -> [CrossOverApplication] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        var results: [CrossOverApplication] = []
        for root in roots {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for appURL in children where appURL.pathExtension == "app" {
                let wineURL = appURL.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine")
                guard fileManager.isExecutableFile(atPath: wineURL.path) else { continue }
                let info = Bundle(url: appURL)?.infoDictionary
                let version = info?["CFBundleShortVersionString"] as? String ?? ""
                results.append(.init(
                    url: appURL,
                    displayName: appURL.deletingPathExtension().lastPathComponent,
                    version: version
                ))
            }
        }
        return results.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private func discoverBottles() -> [ClickFlowCrossOverBottle] {
        let root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CrossOver/Bottles", isDirectory: true)
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return children.compactMap { url in
            let configURL = url.appendingPathComponent("cxbottle.conf")
            let driveCURL = url.appendingPathComponent("drive_c", isDirectory: true)
            guard fileManager.fileExists(atPath: configURL.path),
                  fileManager.fileExists(atPath: driveCURL.path),
                  let text = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }
            let version = quotedConfigurationValue(named: "Version", in: text) ?? ""
            let is64Bit = fileManager.fileExists(
                atPath: driveCURL.appendingPathComponent("windows/syswow64", isDirectory: true).path
            )
            return ClickFlowCrossOverBottle(name: url.lastPathComponent, url: url, version: version, is64Bit: is64Bit)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func quotedConfigurationValue(named name: String, in text: String) -> String? {
        let prefix = "\"\(name)\""
        guard let line = text.split(whereSeparator: \.isNewline)
            .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }),
              let first = line.firstIndex(of: "="),
              let opening = line[line.index(after: first)...].firstIndex(of: "\"") else { return nil }
        let remainder = line[line.index(after: opening)...]
        guard let closing = remainder.firstIndex(of: "\"") else { return nil }
        return String(remainder[..<closing])
    }

    private func inspectPEArchitecture(at url: URL) throws -> WindowsPEArchitecture {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 64) ?? Data()
        guard header.count >= 64, header[0] == 0x4D, header[1] == 0x5A else {
            return .unsupported
        }
        let peOffset = UInt64(header[0x3C])
            | UInt64(header[0x3D]) << 8
            | UInt64(header[0x3E]) << 16
            | UInt64(header[0x3F]) << 24
        try handle.seek(toOffset: peOffset)
        let peHeader = try handle.read(upToCount: 6) ?? Data()
        guard peHeader.count == 6,
              Array(peHeader.prefix(4)) == [0x50, 0x45, 0x00, 0x00] else {
            return .unsupported
        }
        let machine = UInt16(peHeader[4]) | UInt16(peHeader[5]) << 8
        switch machine {
        case 0x8664: return .x64
        case 0x014C: return .x86
        default: return .unsupported
        }
    }

    private func detectXInputDLLNames(in urls: [URL]) -> [String] {
        var found: Set<String> = []
        let patterns = Self.supportedDLLNames.map { ($0, Data($0.utf8)) }
        for url in urls {
            scanLowercasedASCII(in: url) { chunk in
                for (name, pattern) in patterns where chunk.range(of: pattern) != nil {
                    found.insert(name)
                }
            }
            if found.count == Self.supportedDLLNames.count { break }
        }
        return Self.supportedDLLNames.filter { found.contains($0) }
    }

    /// Scans arbitrary PE bytes without decoding them as Unicode. Treating a
    /// large executable as UTF-8 makes invalid-sequence repair and Unicode
    /// lowercasing pathologically expensive.
    private func scanLowercasedASCII(in url: URL, match: (Data) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        var overlap = Data()
        while let data = try? handle.read(upToCount: 1_048_576), !data.isEmpty {
            var bytes = [UInt8](overlap + data)
            for index in bytes.indices where bytes[index] >= 0x41 && bytes[index] <= 0x5A {
                bytes[index] += 0x20
            }
            let normalized = Data(bytes)
            match(normalized)
            overlap = Data(normalized.suffix(64))
        }
    }

    private func detectAntiCheatFiles(near gameURL: URL) -> [String] {
        let root = gameURL.deletingLastPathComponent()
        let needles = ["anticheat", "anti-cheat", "nep2", "nepkernel", "hoyokprotect", "mhyp", "easyanticheat", "battleye"]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        let rootDepth = root.pathComponents.count
        var found: Set<String> = []
        var inspected = 0
        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - rootDepth
            if depth > 4 {
                enumerator.skipDescendants()
                continue
            }
            inspected += 1
            if inspected > 4_000 { break }
            let name = url.lastPathComponent.lowercased()
            if needles.contains(where: name.contains) {
                found.insert(url.lastPathComponent)
            }
        }
        return found.sorted()
    }

    private func proxyURL(named name: String, architectureDirectory: String) -> URL? {
        guard let root = proxyRootURL else { return nil }
        let fileName = "\(architectureDirectory)-\(name)"
        let candidates = [
            root.appendingPathComponent(fileName),
            root.appendingPathComponent("CrossOverXInputProxy", isDirectory: true)
                .appendingPathComponent(fileName)
        ]
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func replaceFile(at target: URL, with source: URL) throws {
        let temporary = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).clickflow-\(UUID().uuidString)")
        try fileManager.copyItem(at: source, to: temporary)
        do {
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.moveItem(at: temporary, to: target)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func save(_ manifest: CrossOverIntegrationManifest, in directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func queryRegistryValue(
        named name: String,
        application: CrossOverApplication,
        bottle: ClickFlowCrossOverBottle
    ) async throws -> String? {
        let result = try await commandRunner.run(
            executable: application.wineURL,
            arguments: ["--bottle", bottle.name, "--no-gui", "reg", "query", Self.registryKey, "/v", name]
        )
        guard result.terminationStatus == 0 else { return nil }
        for line in result.standardOutput.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count >= 3, fields[0].lowercased() == name.lowercased() {
                return fields.dropFirst(2).joined(separator: " ")
            }
        }
        return nil
    }

    private func setRegistryValue(
        named name: String,
        value: String,
        application: CrossOverApplication,
        bottle: ClickFlowCrossOverBottle
    ) async throws {
        let result = try await commandRunner.run(
            executable: application.wineURL,
            arguments: [
                "--bottle", bottle.name, "--no-gui", "reg", "add", Self.registryKey,
                "/v", name, "/d", value, "/f"
            ]
        )
        guard result.terminationStatus == 0 else {
            throw CrossOverIntegrationError.commandFailed(
                result.standardError.isEmpty ? result.standardOutput : result.standardError
            )
        }
    }

    private func deleteRegistryValue(
        named name: String,
        application: CrossOverApplication,
        bottle: ClickFlowCrossOverBottle
    ) async throws {
        let result = try await commandRunner.run(
            executable: application.wineURL,
            arguments: [
                "--bottle", bottle.name, "--no-gui", "reg", "delete", Self.registryKey,
                "/v", name, "/f"
            ]
        )
        if result.terminationStatus != 0,
           !result.standardError.localizedCaseInsensitiveContains("unable to find"),
           !result.standardOutput.localizedCaseInsensitiveContains("unable to find") {
            throw CrossOverIntegrationError.commandFailed(
                result.standardError.isEmpty ? result.standardOutput : result.standardError
            )
        }
    }

    private func isGameRunning(_ gameURL: URL) -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "command="]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        let executableName = gameURL.lastPathComponent.lowercased()
        return text.split(whereSeparator: \.isNewline).contains {
            $0.lowercased().contains(executableName)
        }
    }

    private func controllerHeartbeatDescription() -> (active: Bool, detail: String) {
        let url = CrossOverXInputPublisher.defaultURL
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date,
              let data = try? Data(contentsOf: url), data.count == 32 else {
            return (false, cf("windowsGames.check.publisher.inactive"))
        }
        let magic = UInt32(data[0]) | UInt32(data[1]) << 8 | UInt32(data[2]) << 16 | UInt32(data[3]) << 24
        let connected = UInt32(data[12]) | UInt32(data[13]) << 8 | UInt32(data[14]) << 16 | UInt32(data[15]) << 24
        let active = magic == 0x31504756 && connected != 0 && Date().timeIntervalSince(date) <= 3
        return (
            active,
            cf(active
                ? "windowsGames.check.publisher.active"
                : "windowsGames.check.publisher.inactive")
        )
    }
}
