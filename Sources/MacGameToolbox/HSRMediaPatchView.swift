import AppKit
import CryptoKit
import Darwin
import SwiftUI

private enum HSRProduct: String, CaseIterable, Identifiable {
    case stable, preview
    var id: String { rawValue }
    var name: String { self == .stable ? "CrossOver" : "CrossOver Preview" }
    var expectedVersion: String { self == .stable ? "26.3.0.39832" : "27.0.0.41073" }
    var source: URL { URL(fileURLWithPath: self == .stable ? "/Applications/CrossOver.app" : "/Applications/CrossOver Preview.app") }
    var target: URL { URL(fileURLWithPath: self == .stable ? "/Applications/CrossOver-HSR-MediaFix.app" : "/Applications/CrossOver Preview-HSR-MediaFix.app") }
    var config: URL { source.appendingPathComponent("Contents/SharedSupport/CrossOver/etc/CrossOver.conf") }
}

private struct HSRBackup: Identifiable {
    let id: String
    let product: HSRProduct
    let target: URL
}

private struct HSRInspection {
    let version: String?
    let targetExists: Bool
    let backup: HSRBackup?
    var sourceExists: Bool { version != nil }
}

@MainActor
private final class HSRMediaPatchModel: ObservableObject {
    enum Phase { case ready, working, installed, restored, diagnosed, failed, cancelled }
    @Published var inspections: [HSRProduct: HSRInspection] = [:]
    @Published var phase: Phase = .ready
    @Published var activeProduct: HSRProduct?
    @Published var packageValid = false

    nonisolated static let packageName = "HSR-Media-Patch-v1.0.0"
    nonisolated static let packageSHA256 = "e136a9f5191c4082d2081f8afde333169e6399762b082c84f04b3c72c38ea8a8"
    private static let backupIDPattern = try! NSRegularExpression(pattern: #"^[0-9]{8}-[0-9]{6}-[0-9]+-[0-9]+$"#)

    static var packageURL: URL? {
        #if SWIFT_PACKAGE
        Bundle.module.url(forResource: packageName, withExtension: "zip")
        #else
        Bundle.main.url(forResource: packageName, withExtension: "zip")
        #endif
    }

    static var backupRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/HSR-Media-Patch/Backups", isDirectory: true)
    }

    static var logRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/HSR-Media-Patch", isDirectory: true)
    }

    func refresh() {
        packageValid = Self.verifyPackage()
        inspections = Dictionary(uniqueKeysWithValues: HSRProduct.allCases.map { ($0, Self.inspect($0)) })
    }

    private static func verifyPackage() -> Bool {
        guard let url = packageURL, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return hash == packageSHA256
    }

    private static func inspect(_ product: HSRProduct) -> HSRInspection {
        let version = (try? String(contentsOf: product.config, encoding: .utf8))?
            .split(separator: "\n")
            .first { $0.hasPrefix("\"ProductVersion\"") }?
            .split(separator: "\"")
            .dropFirst(2).first.map(String.init)
        let backup = (try? FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil))?
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .compactMap { url -> HSRBackup? in
                let id = url.lastPathComponent
                guard validBackupID(id),
                      let data = try? Data(contentsOf: url.appendingPathComponent("backup-manifest.json")),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["mode"] as? String == "copy",
                      object["product"] as? String == product.rawValue,
                      object["backup_id"] as? String == id,
                      object["target_app"] as? String == product.target.path else { return nil }
                return HSRBackup(id: id, product: product, target: product.target)
            }.first
        let targetExists = FileManager.default.fileExists(atPath: product.target.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: product.target.path)) != nil
        return HSRInspection(version: version,
                             targetExists: targetExists,
                             backup: backup)
    }

    private static func validBackupID(_ id: String) -> Bool {
        backupIDPattern.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil
    }

    func install(_ product: HSRProduct) {
        guard phase != .working,
              packageValid,
              let state = inspections[product],
              state.version == product.expectedVersion,
              !state.targetExists else { return }
        run(.install, product: product, backupID: nil)
    }

    func restore(_ product: HSRProduct) {
        guard phase != .working,
              let state = inspections[product],
              state.targetExists,
              let backup = state.backup,
              Self.validBackupID(backup.id) else { return }
        run(.restore, product: product, backupID: backup.id)
    }

    func open(_ product: HSRProduct) {
        guard inspections[product]?.targetExists == true else { return }
        NSWorkspace.shared.open(product.target)
    }

    func openLogs() { NSWorkspace.shared.open(Self.logRoot) }

    func diagnose() {
        guard phase != .working, packageValid, let package = Self.packageURL else { return }
        phase = .working
        Task {
            do {
                try FileManager.default.createDirectory(at: Self.logRoot, withIntermediateDirectories: true)
                try await Self.runDiagnosis(package: package)
                phase = .diagnosed
            } catch {
                phase = .failed
            }
            refresh()
        }
    }

    private enum Action: String { case install, restore }

    private func run(_ action: Action, product: HSRProduct, backupID: String?) {
        guard let package = Self.packageURL else { return }
        phase = .working
        activeProduct = product
        Task {
            do {
                try FileManager.default.createDirectory(at: Self.backupRoot, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: Self.logRoot, withIntermediateDirectories: true)
                try await Self.runAuthorized(package: package, action: action, product: product, backupID: backupID)
                phase = action == .install ? .installed : .restored
            } catch {
                phase = error.localizedDescription.contains("(-128)") ? .cancelled : .failed
            }
            refresh()
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runDiagnosis(package: URL) async throws {
        let result = try await Task.detached(priority: .userInitiated) { () throws -> Int32 in
            let stage = FileManager.default.temporaryDirectory.appendingPathComponent("HSRMediaPatch-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: stage) }
            let archive = stage.appendingPathComponent("archive.zip")
            try FileManager.default.copyItem(at: package, to: archive)
            let hash = SHA256.hash(data: try Data(contentsOf: archive, options: .mappedIfSafe))
                .map { String(format: "%02x", $0) }.joined()
            guard hash == packageSHA256 else { throw NSError(domain: "HSRMediaPatch", code: 4) }
            let unpack = Process()
            unpack.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unpack.arguments = ["-x", "-k", archive.path, stage.path]
            try unpack.run()
            unpack.waitUntilExit()
            guard unpack.terminationStatus == 0 else { throw NSError(domain: "HSRMediaPatch", code: 4) }
            let script = stage.appendingPathComponent("\(packageName)/scripts/hsr-media-patch")
            let process = Process()
            let output = stage.appendingPathComponent("diagnose.txt")
            FileManager.default.createFile(atPath: output.path, contents: nil)
            let stream = try FileHandle(forWritingTo: output)
            defer { try? stream.close() }
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [script.path, "diagnose"]
            process.standardOutput = stream
            process.standardError = stream
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }.value
        guard result == 0 else { throw NSError(domain: "HSRMediaPatch", code: Int(result)) }
    }

    private static func runAuthorized(package: URL, action: Action, product: HSRProduct, backupID: String?) async throws {
        let script = #"""
        set -euo pipefail
        archive="$1"; home="$2"; uid="$3"; action="$4"; product="$5"; backup="$6"
        [[ "$action" == install || "$action" == restore ]] || exit 2
        [[ "$product" == stable || "$product" == preview ]] || exit 2
        [[ "$uid" == <-> && "$(/usr/bin/stat -f %u "$home")" == "$uid" ]] || exit 2
        stage="$(/usr/bin/mktemp -d /private/tmp/HSRMediaPatch.XXXXXXXX)"
        trap '/bin/rm -rf "$stage"' EXIT
        /usr/bin/ditto --norsrc --noextattr "$archive" "$stage/archive.zip"
        hash="$(/usr/bin/shasum -a 256 "$stage/archive.zip" | /usr/bin/awk '{print $1}')"
        [[ "$hash" == e136a9f5191c4082d2081f8afde333169e6399762b082c84f04b3c72c38ea8a8 ]] || exit 4
        /usr/bin/ditto -x -k "$stage/archive.zip" "$stage"
        root="$stage/HSR-Media-Patch-v1.0.0"
        [[ -f "$root/scripts/hsr-media-patch" && -f "$root/payload/GStreamer.framework.tar.xz" ]] || exit 4
        expected="$(/usr/bin/tr -d '[:space:]' < "$root/payload/GStreamer.framework.tar.xz.sha256")"
        actual="$(/usr/bin/shasum -a 256 "$root/payload/GStreamer.framework.tar.xz" | /usr/bin/awk '{print $1}')"
        [[ "$actual" == "$expected" ]] || exit 4
        if [[ "$action" == install ]]; then
            if [[ "$product" == stable ]]; then
                target='/Applications/CrossOver-HSR-MediaFix.app'
            else
                target='/Applications/CrossOver Preview-HSR-MediaFix.app'
            fi
            [[ ! -e "$target" && ! -L "$target" ]] || exit 3
            /usr/bin/env HSR_MEDIA_USER_HOME="$home" /bin/zsh "$root/scripts/hsr-media-patch" patch --product "$product" --mode copy --yes
        else
            [[ "$backup" =~ '^[0-9]{8}-[0-9]{6}-[0-9]+-[0-9]+$' ]] || exit 2
            manifest="$home/Library/Application Support/HSR-Media-Patch/Backups/$backup/backup-manifest.json"
            [[ -f "$manifest" ]] || exit 3
            [[ "$(/usr/bin/plutil -extract backup_id raw -o - "$manifest")" == "$backup" ]] || exit 3
            [[ "$(/usr/bin/plutil -extract product raw -o - "$manifest")" == "$product" ]] || exit 3
            [[ "$(/usr/bin/plutil -extract mode raw -o - "$manifest")" == copy ]] || exit 3
            if [[ "$product" == stable ]]; then
                target='/Applications/CrossOver-HSR-MediaFix.app'
            else
                target='/Applications/CrossOver Preview-HSR-MediaFix.app'
            fi
            [[ "$(/usr/bin/plutil -extract target_app raw -o - "$manifest")" == "$target" ]] || exit 3
            /usr/bin/env HSR_MEDIA_USER_HOME="$home" /bin/zsh "$root/scripts/hsr-media-patch" restore --backup-id "$backup"
        fi
        """#
        let arguments = [package.path, FileManager.default.homeDirectoryForCurrentUser.path,
                         String(getuid()), action.rawValue, product.rawValue, backupID ?? "-"]
        let command = "/bin/zsh -c \(shellQuote(script)) -- " + arguments.map(shellQuote).joined(separator: " ")
        let result = try await Task.detached(priority: .userInitiated) { () throws -> (Int32, String) in
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "on run argv", "-e", "do shell script (item 1 of argv) with administrator privileges", "-e", "end run", "--", command]
            process.standardOutput = output
            process.standardError = output
            try process.run()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }.value
        guard result.0 == 0 else { throw NSError(domain: "HSRMediaPatch", code: Int(result.0), userInfo: [NSLocalizedDescriptionKey: result.1]) }
    }
}

struct HSRMediaPatchView: View {
    @StateObject private var model = HSRMediaPatchModel()

    var body: some View {
        ToolboxCard(
            tr("HSR 过场动画黑屏修复", "HSR Cutscene Black Screen Fix"),
            subtitle: tr("为兼容版本的 CrossOver 创建修复副本，解决《崩坏：星穹铁道》新版本过场动画黑屏。", "Create a patched copy of a compatible CrossOver version to fix black cutscenes in Honkai: Star Rail.")
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(HSRProduct.allCases) { product in
                    productRow(product)
                    if product != .preview { Divider() }
                }
                if model.phase == .working { ProgressView(tr("正在处理补丁…", "Applying patch…")) }
                if model.phase == .installed { Text(tr("修复副本已安装。请从修复版 CrossOver 启动游戏。", "Patched copy installed. Launch the game from the patched CrossOver app.")).foregroundStyle(.green) }
                if model.phase == .restored { Text(tr("修复副本已移除，原版 CrossOver 已保留。", "Patched copy removed; the original CrossOver app is preserved.")).foregroundStyle(.green) }
                if model.phase == .diagnosed { Text(tr("诊断完成，请查看诊断日志。", "Diagnosis complete. Review the diagnostic logs.")).foregroundStyle(.green) }
                if model.phase == .failed { Text(tr("操作失败。请检查诊断日志。", "Operation failed. Check the diagnostic logs.")).foregroundStyle(.red) }
                if model.phase == .cancelled { Text(tr("已取消管理员授权，未执行补丁操作。", "Administrator authorization was cancelled. No patch operation was run.")).foregroundStyle(.secondary) }
                HStack {
                    Button(tr("刷新状态", "Refresh Status")) { model.refresh() }
                    Button(tr("运行诊断", "Run Diagnosis")) { model.diagnose() }
                        .disabled(model.phase == .working || !model.packageValid)
                    Button(tr("打开诊断日志", "Open Diagnostic Logs")) { model.openLogs() }
                    Spacer()
                    Text(tr("补丁版本 1.0.0", "Patch version 1.0.0")).foregroundStyle(.secondary)
                }
                Text(tr("安装前请退出 CrossOver 和游戏。修复仅修改新副本；原版、游戏文件和容器保持原样。", "Quit CrossOver and the game before installing. Only the new copy is patched; the original app, game files, and bottle remain intact."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { model.refresh() }
    }

    private func productRow(_ product: HSRProduct) -> some View {
        let inspection = model.inspections[product]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(product.name).font(.headline)
                Spacer()
                Text(inspection?.version ?? tr("未检测到", "Not detected"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.packageValid {
                Text(tr("内置补丁文件缺失或校验失败。", "The bundled patch is missing or failed verification.")).foregroundStyle(.red)
            } else if inspection?.targetExists == true {
                Text(inspection?.backup == nil
                     ? tr("检测到已有修复副本，缺少可用备份记录。不会覆盖该副本。", "An existing patched copy has no usable backup record and will not be overwritten.")
                     : tr("已安装修复副本。", "Patched copy installed."))
            } else if inspection?.version != nil && inspection?.version != product.expectedVersion {
                Text(tr("当前 CrossOver 版本未经此补丁验证。", "This CrossOver version has not been verified with the patch."))
                    .foregroundStyle(.orange)
            } else if inspection?.sourceExists == false {
                Text(tr("未检测到原版 CrossOver。", "Original CrossOver app not found."))
                    .foregroundStyle(.secondary)
            } else {
                Text(tr("已检测到兼容版本，可创建安全副本。", "Compatible version found; a safe patched copy can be created."))
                    .foregroundStyle(.green)
            }
            HStack {
                Button(tr("安装修复副本", "Install Patched Copy")) { model.install(product) }
                    .disabled(model.phase == .working || !model.packageValid || inspection?.version != product.expectedVersion || inspection?.targetExists == true)
                Button(tr("打开修复版", "Open Patched App")) { model.open(product) }
                    .disabled(inspection?.targetExists != true || model.phase == .working)
                Button(tr("恢复／移除", "Restore / Remove")) { model.restore(product) }
                    .disabled(model.phase == .working || !model.packageValid || inspection?.targetExists != true || inspection?.backup == nil)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
