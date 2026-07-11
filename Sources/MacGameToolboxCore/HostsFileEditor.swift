import Foundation

public enum HostsFileEditor {
    public static let markerStart = "# BEGIN MAC GAME TOOLBOX HOYO"
    public static let markerEnd = "# END MAC GAME TOOLBOX HOYO"

    public static func replacingManagedBlock(in original: String, domains: [String], enabled: Bool) -> String {
        var lines: [String] = []
        var insideBlock = false
        let managedLines = Set(domains.map { "0.0.0.0 \($0)" })
        for line in original.components(separatedBy: .newlines) {
            if line == markerStart { insideBlock = true; continue }
            if line == markerEnd { insideBlock = false; continue }
            if !insideBlock && !managedLines.contains(line.trimmingCharacters(in: .whitespaces)) { lines.append(line) }
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        if enabled {
            lines.append(markerStart)
            lines.append(contentsOf: domains.map { "0.0.0.0 \($0)" })
            lines.append(markerEnd)
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
