import Foundation
import Testing
@testable import AppDropCore

@Suite(.serialized) struct AppStoreServiceTests {
    private func makeService(retry: RetryPolicy = .immediate) -> AppStoreService {
        AppStoreService(
            session: MockURLProtocol.makeSession(),
            configuration: AppStoreService.Configuration(retryPolicy: retry)
        )
    }

    @Test func lookupParsesFieldsAndDecimalsExactly() async throws {
        MockURLProtocol.reset { request in
            MockURLProtocol.Response(body: Fixtures.lookupResponse(items: [
                Fixtures.item(trackId: 123456789, name: "Example")
            ]))
        }
        let outcome = await makeService().lookup(appIds: ["123456789"], country: "us")
        #expect(outcome.failedIds.isEmpty)
        #expect(outcome.missingIds.isEmpty)
        let app = try #require(outcome.apps.first)
        #expect(app.trackId == "123456789")
        #expect(app.name == "Example")
        #expect(app.developerName == "Example Developer")
        #expect(app.price == Decimal(string: "4.99"))
        #expect(app.formattedPrice == "$4.99")
        #expect(app.currency == "USD")
        #expect(app.appStoreURL == "https://apps.apple.com/us/app/id123456789")
        #expect(app.platform == .iOS)
    }

    @Test func lookupDetectsMacAppsFromTheirKind() async throws {
        MockURLProtocol.reset { _ in
            MockURLProtocol.Response(body: Fixtures.lookupResponse(items: [
                Fixtures.item(trackId: 6503918400, name: "Palworld", price: Decimal(string: "29.99"), formattedPrice: "$29.99", kind: "mac-software")
            ]))
        }
        let outcome = await makeService().lookup(appIds: ["6503918400"], country: "us")
        #expect(outcome.apps.first?.platform == .macOS)
    }

    @Test func lookupHandlesFreeAppsAndMissingPriceFields() async throws {
        MockURLProtocol.reset { _ in
            MockURLProtocol.Response(body: Fixtures.lookupResponse(items: [
                Fixtures.item(trackId: 100000001, name: "Free App", price: 0, formattedPrice: "Free"),
                Fixtures.item(trackId: 100000002, name: "No Price", price: nil, formattedPrice: nil)
            ]))
        }
        let outcome = await makeService().lookup(appIds: ["100000001", "100000002"], country: "us")
        let free = try #require(outcome.apps.first { $0.trackId == "100000001" })
        #expect(free.price == 0)
        let missing = try #require(outcome.apps.first { $0.trackId == "100000002" })
        #expect(missing.price == nil)
    }

    @Test func lookupReportsMissingIdsForSuccessfulRequests() async {
        MockURLProtocol.reset { _ in
            MockURLProtocol.Response(body: Fixtures.lookupResponse(items: [
                Fixtures.item(trackId: 123456789, name: "Example")
            ]))
        }
        let outcome = await makeService().lookup(appIds: ["123456789", "999999999"], country: "us")
        #expect(outcome.missingIds == ["999999999"])
        #expect(outcome.failedIds.isEmpty)
    }

    @Test func lookupSplitsLargeRequestsIntoBatches() async {
        MockURLProtocol.reset { request in
            let ids = Self.requestedIds(request)
            let items = ids.map { Fixtures.item(trackId: Int($0)!, name: "App \($0)") }
            return MockURLProtocol.Response(body: Fixtures.lookupResponse(items: items))
        }
        let ids = (1...120).map { String(1_000_000_000 + $0) }
        let outcome = await makeService().lookup(appIds: ids, country: "us")
        #expect(outcome.apps.count == 120)
        let requests = MockURLProtocol.recordedRequests
        #expect(requests.count == 3)
        for request in requests {
            let batch = Self.requestedIds(request)
            #expect(batch.count <= SharedConstants.lookupBatchSize)
            #expect(!batch.isEmpty)
        }
    }

    @Test func httpServerErrorIsRetriedThenReportedAsFailedBatch() async {
        MockURLProtocol.reset { _ in
            MockURLProtocol.Response(statusCode: 500, body: Data("{}".utf8))
        }
        let outcome = await makeService().lookup(appIds: ["123456789"], country: "us")
        #expect(outcome.failedIds == ["123456789"])
        #expect(outcome.apps.isEmpty)
        #expect(MockURLProtocol.recordedRequests.count == 3) // initial attempt + 2 retries
    }

    @Test func httpClientErrorIsNotRetried() async {
        MockURLProtocol.reset { _ in
            MockURLProtocol.Response(statusCode: 404, body: Data("{}".utf8))
        }
        let outcome = await makeService().lookup(appIds: ["123456789"], country: "us")
        #expect(outcome.failedIds == ["123456789"])
        #expect(MockURLProtocol.recordedRequests.count == 1)
    }

    @Test func networkTimeoutIsRetriedThenReported() async {
        MockURLProtocol.reset { _ in
            MockURLProtocol.Response(error: URLError(.timedOut))
        }
        let outcome = await makeService().lookup(appIds: ["123456789"], country: "us")
        #expect(outcome.failedIds == ["123456789"])
        #expect(MockURLProtocol.recordedRequests.count == 3)
    }

    @Test func networkOfflineIsRetriedThenReported() async {
        MockURLProtocol.reset { _ in
            MockURLProtocol.Response(error: URLError(.notConnectedToInternet))
        }
        let outcome = await makeService().lookup(appIds: ["123456789"], country: "us")
        #expect(outcome.failedIds == ["123456789"])
        #expect(MockURLProtocol.recordedRequests.count == 3)
    }

    @Test func decodingFailureIsReported() async {
        MockURLProtocol.reset { _ in
            MockURLProtocol.Response(body: Data("this is not json".utf8))
        }
        let outcome = await makeService().lookup(appIds: ["123456789"], country: "us")
        #expect(outcome.failedIds == ["123456789"])
        #expect(outcome.failures.first?.message.isEmpty == false)
    }

    @Test func partialSuccessKeepsSuccessfulBatches() async {
        let counter = Counter()
        MockURLProtocol.reset { request in
            if counter.next() == 0 {
                let ids = Self.requestedIds(request)
                let items = ids.map { Fixtures.item(trackId: Int($0)!, name: "App \($0)") }
                return MockURLProtocol.Response(body: Fixtures.lookupResponse(items: items))
            }
            return MockURLProtocol.Response(statusCode: 503, body: Data("{}".utf8))
        }
        let ids = (1...60).map { String(1_000_000_000 + $0) }
        let outcome = await makeService().lookup(appIds: ids, country: "us")
        #expect(outcome.apps.count > 0)
        #expect(!outcome.failedIds.isEmpty)
        #expect(Set(outcome.apps.map(\.trackId)).isDisjoint(with: Set(outcome.failedIds)))
    }

    @Test func searchReturnsResultsAndSkipsEmptyKeyword() async throws {
        MockURLProtocol.reset { _ in
            MockURLProtocol.Response(body: Fixtures.lookupResponse(items: [
                Fixtures.item(trackId: 310633997, name: "Chat App")
            ]))
        }
        let service = makeService()
        let results = try await service.search(keyword: "chat", country: "cn", platform: .iOS)
        #expect(results.count == 1)
        #expect(results.first?.trackId == "310633997")

        MockURLProtocol.reset { _ in
            MockURLProtocol.Response(body: Fixtures.lookupResponse(items: []))
        }
        let empty = try await service.search(keyword: "   ", country: "us")
        #expect(empty.isEmpty)
        #expect(MockURLProtocol.recordedRequests.isEmpty)
    }

    @Test func searchSurfacesHTTPErrors() async {
        MockURLProtocol.reset { _ in
            MockURLProtocol.Response(statusCode: 403, body: Data("{}".utf8))
        }
        do {
            _ = try await makeService().search(keyword: "chat", country: "us", platform: .iOS)
            Issue.record("expected an error")
        } catch let error as AppStoreServiceError {
            #expect(error == .httpStatus(code: 403))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func searchMacPlatformUsesTheMacSoftwareEntity() async throws {
        MockURLProtocol.reset { _ in
            MockURLProtocol.Response(body: Fixtures.lookupResponse(items: [
                Fixtures.item(trackId: 497799835, name: "Xcode", price: 0, formattedPrice: "Free", kind: "mac-software")
            ]))
        }
        let results = try await makeService().search(keyword: "Xcode", country: "us", platform: .macOS)
        #expect(results.first?.trackId == "497799835")
        #expect(results.first?.platform == .macOS)
        let request = try #require(MockURLProtocol.recordedRequests.first)
        let components = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(components.queryItems?.first(where: { $0.name == "entity" })?.value == "macSoftware")
    }

    @Test func searchDefaultsToTheMacCatalog() async throws {
        MockURLProtocol.reset { _ in
            MockURLProtocol.Response(body: Fixtures.lookupResponse(items: [
                Fixtures.item(trackId: 6499559693, name: "iStat Menus 7", price: nil, formattedPrice: nil, kind: "mac-software")
            ]))
        }
        let results = try await makeService().search(keyword: "iStat Menus", country: "us")
        #expect(results.map(\.trackId) == ["6499559693"])
        #expect(MockURLProtocol.recordedRequests.count == 1)
        let request = try #require(MockURLProtocol.recordedRequests.first)
        let components = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(components.queryItems?.first(where: { $0.name == "entity" })?.value == "macSoftware")
    }

    @Test func searchMacPlatformDropsMixedInIOSResults() async throws {
        MockURLProtocol.reset { _ in
            MockURLProtocol.Response(body: Fixtures.lookupResponse(items: [
                Fixtures.item(trackId: 1496833156, name: "Swift Playground", price: nil, formattedPrice: nil, kind: "mac-software"),
                Fixtures.item(trackId: 310633997, name: "Chat App", kind: "software")
            ]))
        }
        let results = try await makeService().search(keyword: "playground", country: "us", platform: .macOS)
        #expect(results.map(\.trackId) == ["1496833156"])
    }

    @Test func priceLessSearchResultsCanBeCompletedByALookupResult() {
        let searchResult = AppStoreApp(
            trackId: "1450874784",
            name: "Beyond a Steel Sky",
            developerName: "Revolution",
            appStoreURL: nil,
            price: nil,
            formattedPrice: nil,
            currency: nil,
            platform: .macOS
        )
        let lookup = AppStoreApp(
            trackId: "1450874784",
            name: "Beyond a Steel Sky",
            price: Decimal(string: "24.99"),
            formattedPrice: "$24.99",
            currency: "USD",
            platform: .macOS
        )
        let filled = searchResult.fillingMissingPrice(from: lookup)
        #expect(filled.price == Decimal(string: "24.99"))
        #expect(filled.formattedPrice == "$24.99")
        #expect(filled.currency == "USD")
        #expect(filled.name == "Beyond a Steel Sky")
        let priced = AppStoreApp(trackId: "1", name: "X", price: 1, formattedPrice: "$1", currency: "USD")
        #expect(priced.fillingMissingPrice(from: lookup).price == 1)
        #expect(searchResult.fillingMissingPrice(from: nil).price == nil)
    }

    @Test func cancelledLookupStillReturnsATotalOutcome() async {
        MockURLProtocol.reset { _ in
            MockURLProtocol.Response(statusCode: 500, body: Data("{}".utf8))
        }
        let service = makeService()
        let task = Task { await service.lookup(appIds: ["123456789", "223456789"], country: "us") }
        task.cancel()
        let outcome = await task.value
        let accounted = Set(outcome.apps.map(\.trackId))
            .union(outcome.missingIds)
            .union(outcome.failedIds)
        #expect(accounted.isSuperset(of: ["123456789", "223456789"]))
    }

    @Test func lookupURLUsesDocumentedShape() async throws {
        MockURLProtocol.reset { _ in
            MockURLProtocol.Response(body: Fixtures.lookupResponse(items: []))
        }
        _ = await makeService().lookup(appIds: ["123456789"], country: "JP")
        let request = MockURLProtocol.recordedRequests.first
        let url = try #require(request?.url)
        #expect(url.host == "itunes.apple.com")
        #expect(url.path == "/lookup")
        #expect(url.query?.contains("id=123456789") == true)
        #expect(url.query?.contains("country=jp") == true)
    }

    private static func requestedIds(_ request: URLRequest) -> [String] {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "id" })?.value else {
            return []
        }
        return value.split(separator: ",").map(String.init)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let current = value
        value += 1
        return current
    }
}
