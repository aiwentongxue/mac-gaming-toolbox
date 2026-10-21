import Foundation

/// URLProtocol test double: lets every test script responses per request.
/// Always used together with `@Suite(.serialized)` because the handler is
/// process-global static state.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        var statusCode: Int
        var headers: [String: String]
        var body: Data
        var error: Error?

        init(
            statusCode: Int = 200,
            headers: [String: String] = ["Content-Type": "application/json"],
            body: Data = Data(),
            error: Error? = nil
        ) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
            self.error = error
        }
    }

    typealias Handler = @Sendable (URLRequest) -> Response

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func reset(handler: Handler? = nil) {
        lock.lock()
        self.handler = handler
        self.requests = []
        lock.unlock()
    }

    static var recordedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let response = handler(request)
        if let error = response.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let http = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.invalid")!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

enum Fixtures {
    static func lookupResponse(items: [[String: Any]]) -> Data {
        let payload: [String: Any] = ["resultCount": items.count, "results": items]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    static func item(
        trackId: Int,
        name: String,
        price: Any? = Decimal(string: "4.99"),
        formattedPrice: Any? = "$4.99",
        currency: Any? = "USD",
        kind: String = "software"
    ) -> [String: Any] {
        var item: [String: Any] = [
            "trackId": trackId,
            "trackName": name,
            "artistName": "\(name) Developer",
            "artworkUrl100": "https://example.com/\(trackId)/100x100bb.jpg",
            "trackViewUrl": "https://apps.apple.com/us/app/id\(trackId)",
            "kind": kind
        ]
        if let price { item["price"] = price }
        if let formattedPrice { item["formattedPrice"] = formattedPrice }
        if let currency { item["currency"] = currency }
        return item
    }
}
