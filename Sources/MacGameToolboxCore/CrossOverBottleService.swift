import Foundation

public actor CrossOverBottleService {
    private let bottlesDirectory: URL
    private let fileManager: FileManager

    public init(bottlesDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.bottlesDirectory = bottlesDirectory ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CrossOver/Bottles", isDirectory: true)
    }

    public func bottles() throws -> [CrossOverBottle] {
        guard fileManager.fileExists(atPath: bottlesDirectory.path) else { return [] }
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        return try fileManager.contentsOfDirectory(at: bottlesDirectory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
            .filter { url in
                let isDirectory = (try? url.resourceValues(forKeys: keys).isDirectory) == true
                return isDirectory
                    && fileManager.fileExists(atPath: url.appendingPathComponent("cxbottle.conf").path)
                    && fileManager.fileExists(atPath: url.appendingPathComponent("drive_c", isDirectory: true).path)
            }
            .map { CrossOverBottle(path: $0.path, displayName: $0.lastPathComponent) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public func applyMetalHUDPreset(_ presetURL: URL, to bottle: CrossOverBottle) throws {
        let bottleURL = URL(fileURLWithPath: bottle.path).standardizedFileURL
        let configurationURL = bottleURL.appendingPathComponent("cxbottle.conf")
        guard fileManager.fileExists(atPath: configurationURL.path),
              fileManager.fileExists(atPath: bottleURL.appendingPathComponent("drive_c", isDirectory: true).path) else {
            throw ToolboxError.invalidPath(bottle.path)
        }
        var variables = Dictionary(uniqueKeysWithValues: try GamingService.metalHUDEnvironment(from: presetURL).compactMap { assignment -> (String, String)? in
            guard let separator = assignment.firstIndex(of: "=") else { return nil }
            return (String(assignment[..<separator]), String(assignment[assignment.index(after: separator)...]))
        })
        // Keep the bottle's own HUD enablement policy unchanged. The preset only supplies its configuration.
        variables.removeValue(forKey: "MTL_HUD_ENABLED")
        variables["MTL_HUD_CONFIG_FILE"] = presetURL.standardizedFileURL.path
        let source = try String(contentsOf: configurationURL, encoding: .utf8)
        let updated = Self.updatingEnvironmentVariables(in: source, values: variables)
        try updated.write(to: configurationURL, atomically: true, encoding: .utf8)
    }

    static func updatingEnvironmentVariables(in source: String, values: [String: String]) -> String {
        var result = source
        let sectionPattern = "(?m)^\\[EnvironmentVariables\\]\\s*$"
        let sectionRegex = try! NSRegularExpression(pattern: sectionPattern)
        let fullRange = NSRange(result.startIndex..., in: result)
        guard let section = sectionRegex.firstMatch(in: result, range: fullRange) else {
            let lines = values.keys.sorted().map { key in format(key, values[key] ?? "") }.joined(separator: "\n")
            return result + (result.hasSuffix("\n") ? "\n" : "\n\n") + "[EnvironmentVariables]\n" + lines + "\n"
        }

        let bodyStart = section.range.location + section.range.length
        let remainderRange = NSRange(location: bodyStart, length: (result as NSString).length - bodyStart)
        let nextSectionRegex = try! NSRegularExpression(pattern: "(?m)^\\[[^\\]]+\\]\\s*$")
        let bodyEnd = nextSectionRegex.firstMatch(in: result, range: remainderRange)?.range.location ?? (result as NSString).length
        var body = (result as NSString).substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))

        for key in values.keys.sorted() {
            let escapedKey = NSRegularExpression.escapedPattern(for: key)
            let variableRegex = try! NSRegularExpression(pattern: "(?m)^\\s*\\\"\(escapedKey)\\\"\\s*=\\s*\\\"[^\\\"]*\\\"\\s*$")
            let replacement = format(key, values[key] ?? "")
            let bodyRange = NSRange(body.startIndex..., in: body)
            if variableRegex.firstMatch(in: body, range: bodyRange) != nil {
                body = variableRegex.stringByReplacingMatches(in: body, range: bodyRange, withTemplate: replacement)
            } else {
                if !body.hasSuffix("\n") { body += "\n" }
                body += replacement + "\n"
            }
        }
        let range = NSRange(location: bodyStart, length: bodyEnd - bodyStart)
        result = (result as NSString).replacingCharacters(in: range, with: body)
        return result
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func format(_ key: String, _ value: String) -> String {
        "\"\(key)\" = \"\(escaped(value))\""
    }
}
