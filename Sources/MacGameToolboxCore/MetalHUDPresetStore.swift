import Foundation

/// Owns imported HUD files so a launch preset remains available if its original export is moved or deleted.
public actor MetalHUDPresetStore {
    private let directoryURL: URL
    private let fileManager: FileManager

    public init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.iven.macgametoolbox", isDirectory: true)
            self.directoryURL = support.appendingPathComponent("MetalHUDPresets", isDirectory: true)
        }
    }

    public func importPreset(from sourceURL: URL, forApplicationPath applicationPath: String) throws -> MetalHUDPreset {
        let source = sourceURL.standardizedFileURL
        guard fileManager.fileExists(atPath: source.path), !source.hasDirectoryPath else {
            throw ToolboxError.invalidPath(source.path)
        }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let suffix = source.pathExtension.isEmpty ? "hud" : source.pathExtension
        let destination = directoryURL
            .appendingPathComponent("\(stableName(for: applicationPath))-\(UUID().uuidString)")
            .appendingPathExtension(suffix)
        try fileManager.copyItem(at: source, to: destination)
        return MetalHUDPreset(path: destination.path, displayName: source.deletingPathExtension().lastPathComponent)
    }

    private func stableName(for applicationPath: String) -> String {
        let candidate = URL(fileURLWithPath: applicationPath).deletingPathExtension().lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let result = candidate.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        return result.isEmpty ? "MetalHUD" : result
    }
}
