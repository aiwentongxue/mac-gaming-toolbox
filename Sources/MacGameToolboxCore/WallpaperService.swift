import Foundation

public struct WallpaperService {
    public let wallpaperDirectory: URL
    private let fileManager: FileManager

    public init(wallpaperDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let wallpaperDirectory {
            self.wallpaperDirectory = wallpaperDirectory
        } else {
            let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.iven.macgametoolbox", isDirectory: true)
            self.wallpaperDirectory = supportDirectory.appendingPathComponent("Wallpapers", isDirectory: true)
        }
    }

    public func importWallpaper(from source: URL, replacing oldPath: String? = nil) throws -> URL {
        try fileManager.createDirectory(at: wallpaperDirectory, withIntermediateDirectories: true)
        let extensionName = source.pathExtension.isEmpty ? "image" : source.pathExtension
        let destination = wallpaperDirectory.appendingPathComponent("wallpaper-\(UUID().uuidString).\(extensionName)")
        try fileManager.copyItem(at: source, to: destination)
        try removeManagedWallpaper(at: oldPath, keeping: destination)
        return destination
    }

    @discardableResult
    public func removeManagedWallpaper(at path: String?, keeping keptURL: URL? = nil) throws -> Bool {
        guard let path, !path.isEmpty else { return false }
        let url = URL(fileURLWithPath: path)
        guard isManagedWallpaper(url), url.standardizedFileURL != keptURL?.standardizedFileURL else { return false }
        guard fileManager.fileExists(atPath: url.path) else { return false }
        try fileManager.removeItem(at: url)
        return true
    }

    public func isManagedWallpaper(_ url: URL) -> Bool {
        let directoryPath = wallpaperDirectory.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath.hasPrefix(directoryPath + "/")
    }
}
