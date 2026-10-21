import Foundation
import Testing
@testable import AppDropCore

@Suite struct WishdropTests {
    private func makePreset(apps: [WishdropApp]) -> WishdropPreset {
        WishdropPreset(
            title: "AppDrop Wishlist",
            author: "Iven",
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            apps: apps
        )
    }

    @Test func roundTripEncodeDecode() throws {
        let preset = makePreset(apps: [
            WishdropApp(trackId: "123456789", name: "Example", countryCode: "us", appStoreURL: "https://apps.apple.com/us/app/id123456789"),
            WishdropApp(trackId: "987654321", name: "Another", countryCode: "jp")
        ])
        let data = try WishdropCodec.encode(preset)
        let decoded = try WishdropCodec.decode(data)
        #expect(decoded == preset)
    }

    @Test func invalidJSONIsRejected() {
        do {
            _ = try WishdropCodec.decode(Data("not json".utf8))
            Issue.record("expected invalidJSON")
        } catch let error as WishdropError {
            if case .invalidJSON = error {} else { Issue.record("wrong error \(error)") }
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func wrongFormatIdentifierIsRejected() throws {
        var preset = makePreset(apps: [])
        preset.formatIdentifier = "com.example.other"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(preset)
        do {
            _ = try WishdropCodec.decode(data)
            Issue.record("expected wrongFormatIdentifier")
        } catch let error as WishdropError {
            #expect(error == .wrongFormatIdentifier("com.example.other"))
        }
    }

    @Test func futureVersionsAreRejectedWithAMeaningfulError() throws {
        var preset = makePreset(apps: [])
        preset.version = SharedConstants.wishdropFormatVersion + 1
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(preset)
        do {
            _ = try WishdropCodec.decode(data)
            Issue.record("expected unsupportedVersion")
        } catch let error as WishdropError {
            #expect(error == .unsupportedVersion(SharedConstants.wishdropFormatVersion + 1))
            #expect(error.errorDescription?.contains("newer") == true)
        }
    }

    @Test func validationReportsPerEntryIssues() {
        let preset = makePreset(apps: [
            WishdropApp(trackId: "123456789", name: "Good", countryCode: "us"),
            WishdropApp(trackId: "12", name: "Bad Id", countryCode: "us"),
            WishdropApp(trackId: "123456789", name: "Bad Country", countryCode: "zz"),
            WishdropApp(trackId: "223456789", name: "   ", countryCode: "us"),
            WishdropApp(trackId: "323456789", name: "Bad URL", countryCode: "us", appStoreURL: "not a url")
        ])
        let result = WishdropCodec.validateEntries(preset)
        #expect(result.valid.count == 1)
        #expect(result.valid.first?.name == "Good")
        #expect(result.issues.count == 4)
        #expect(result.issues.map(\.code) == [.invalidTrackId, .unsupportedCountry, .emptyName, .invalidURL])
        #expect(result.issues.map(\.index) == [1, 2, 3, 4])
    }

    @Test func makePresetFromSnapshotsUsesCanonicalURL() {
        let snapshot = TrackedAppSnapshot(
            id: UUID(),
            trackId: "123456789",
            countryCode: "hk",
            name: "Example",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let preset = WishdropCodec.makePreset(title: "T", snapshots: [snapshot], exportedAt: Date(timeIntervalSince1970: 0))
        #expect(preset.apps.first?.appStoreURL == "https://apps.apple.com/hk/app/id123456789")
        #expect(preset.formatIdentifier == SharedConstants.wishdropFormatIdentifier)
        #expect(preset.version == SharedConstants.wishdropFormatVersion)
    }
}
