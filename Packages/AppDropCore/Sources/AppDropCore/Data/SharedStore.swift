import Foundation
import SwiftData

/// Errors raised while resolving or opening the shared local store.
public enum SharedStoreError: Error, LocalizedError, Equatable {
    case applicationSupportDirectoryUnavailable
    case storageDirectoryUnavailable(path: String, underlying: String)
    case storageDirectoryNotWritable(path: String)
    case containerInitializationFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryUnavailable:
            return "The current user's Application Support directory could not be resolved."
        case .storageDirectoryUnavailable(let path, let underlying):
            return "Could not create the shared support directory at \(path): \(underlying)"
        case .storageDirectoryNotWritable(let path):
            return "The shared support directory at \(path) is not writable by this process."
        case .containerInitializationFailed(let message):
            return "Could not open the shared SwiftData container: \(message)"
        }
    }
}

/// The local storage root this process actually resolved.
public struct StorageLocationResolution: Sendable, Equatable {
    public var url: URL

    public init(url: URL) {
        self.url = url
    }
}

/// Central place that resolves the local store so that the main app and the
/// helper always agree on exactly one database file.
public enum SharedStore {
    public static var schema: Schema {
        Schema([TrackedApp.self, PriceRecord.self, CheckRunLog.self])
    }

    // MARK: - Storage resolution

    /// Verifies with a real write that this process may use the directory.
    public static func isDirectoryWritable(_ url: URL, fileManager: FileManager = .default) -> Bool {
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        let probe = url.appendingPathComponent(".appdrop-write-probe-\(UUID().uuidString)")
        do {
            try Data("probe".utf8).write(to: probe, options: .atomic)
            try? fileManager.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    /// The requested local storage root. An explicit base is used by tests;
    /// production callers receive the current user's Application Support dir.
    public static func storageRootURL(
        applicationSupportDirectory: URL? = nil,
        create: Bool = true,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let base = applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            throw SharedStoreError.applicationSupportDirectoryUnavailable
        }
        let root = base
            .appendingPathComponent(SharedConstants.applicationSupportContainerName, isDirectory: true)
            .appendingPathComponent(SharedConstants.storageDirectoryName, isDirectory: true)
        if create {
            do {
                try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            } catch {
                throw SharedStoreError.storageDirectoryUnavailable(
                    path: root.path,
                    underlying: error.localizedDescription
                )
            }
            guard isDirectoryWritable(root, fileManager: fileManager) else {
                throw SharedStoreError.storageDirectoryNotWritable(path: root.path)
            }
        }
        return root
    }

    /// Resolution cached for the lifetime of the process (diagnostics/UI).
    public static let resolvedStorageRoot: StorageLocationResolution? = {
        guard let url = try? storageRootURL(create: false) else { return nil }
        return StorageLocationResolution(url: url)
    }()

    // MARK: - Store location

    /// Resolves (and optionally creates) the shared support directory that holds
    /// the store, the refresh lock and the helper log.
    public static func supportDirectoryURL(
        applicationSupportDirectory: URL? = nil,
        create: Bool = true,
        fileManager: FileManager = .default
    ) throws -> URL {
        try storageRootURL(
            applicationSupportDirectory: applicationSupportDirectory,
            create: create,
            fileManager: fileManager
        )
    }

    /// URL of the shared SwiftData store file.
    public static func storeURL(
        applicationSupportDirectory: URL? = nil,
        createDirectory: Bool = true,
        fileManager: FileManager = .default
    ) throws -> URL {
        try supportDirectoryURL(
            applicationSupportDirectory: applicationSupportDirectory,
            create: createDirectory,
            fileManager: fileManager
        )
            .appendingPathComponent(SharedConstants.storeFileName, isDirectory: false)
    }

    // MARK: - Container

    /// Opens the shared store. Fails loudly when the local storage directory is
    /// unavailable; never silently creates a second private database.
    public static func makeContainer() throws -> ModelContainer {
        let url = try storeURL()
        do {
            let configuration = ModelConfiguration(
                "AppDrop",
                schema: schema,
                url: url,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            throw SharedStoreError.containerInitializationFailed(message: error.localizedDescription)
        }
    }

    /// In-memory container used by unit tests and previews.
    public static func makeInMemoryContainer(allowsSave: Bool = true) throws -> ModelContainer {
        do {
            let configuration = ModelConfiguration(
                "AppDropMemory",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: allowsSave,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            throw SharedStoreError.containerInitializationFailed(message: error.localizedDescription)
        }
    }
}
