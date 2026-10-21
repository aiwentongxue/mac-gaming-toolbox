import Foundation
import Testing
@testable import AppDropCore

@Suite struct StorageTests {
    private func makeTemporaryApplicationSupport() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppDropStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func storeLivesInApplicationSupportAndNeverGroupContainers() throws {
        let applicationSupport = try makeTemporaryApplicationSupport()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }

        let support = try SharedStore.supportDirectoryURL(
            applicationSupportDirectory: applicationSupport
        )
        let store = try SharedStore.storeURL(applicationSupportDirectory: applicationSupport)

        #expect(
            support == applicationSupport
                .appendingPathComponent("MacGameToolbox", isDirectory: true)
                .appendingPathComponent("AppDrop", isDirectory: true)
        )
        #expect(store == support.appendingPathComponent("AppDrop.store"))
        #expect(!support.path.contains("Group Containers"))
        #expect(!store.path.contains("Group Containers"))
        #expect(SharedStore.isDirectoryWritable(support))
    }

    @Test func supportDirectoryHoldsSharedLockAndHelperLog() throws {
        let applicationSupport = try makeTemporaryApplicationSupport()
        defer { try? FileManager.default.removeItem(at: applicationSupport) }

        let support = try SharedStore.supportDirectoryURL(
            applicationSupportDirectory: applicationSupport
        )
        #expect(support.appendingPathComponent(SharedConstants.refreshLockFileName).lastPathComponent == "refresh.lock")
        #expect(support.appendingPathComponent(SharedConstants.helperLogFileName).lastPathComponent == "helper.log")
    }
}
