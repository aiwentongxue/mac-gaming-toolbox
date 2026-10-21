import Foundation
import Testing
@testable import AppDropCore

@Suite struct FileLockTests {
    private func makeLock() -> FileLock {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("appdrop-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("refresh.lock")
        return FileLock(url: url)
    }

    @Test func secondAcquisitionFailsFastInSkipMode() throws {
        let lock = makeLock()
        let handle = try lock.acquire(.skipIfBusy)
        defer { handle.release() }
        do {
            _ = try lock.acquire(.skipIfBusy)
            Issue.record("expected busy")
        } catch is FileLockBusyError {
            // expected
        }
    }

    @Test func waitingAcquisitionTimesOutAndSucceedsAfterRelease() throws {
        let lock = makeLock()
        let handle = try lock.acquire(.skipIfBusy)
        let start = Date()
        do {
            let second = try lock.acquire(.wait(timeout: 0.4))
            second.release()
            Issue.record("expected busy timeout")
        } catch is FileLockBusyError {
            #expect(Date().timeIntervalSince(start) >= 0.3)
        }
        handle.release()
        let third = try lock.acquire(.wait(timeout: 1))
        third.release()
    }

    @Test func independentInstancesContendForTheSameFile() throws {
        let lockA = makeLock()
        let lockB = FileLock(url: lockA.url)
        let handle = try lockA.acquire(.skipIfBusy)
        defer { handle.release() }
        do {
            _ = try lockB.acquire(.skipIfBusy)
            Issue.record("expected busy")
        } catch is FileLockBusyError {
            // expected
        }
    }
}
