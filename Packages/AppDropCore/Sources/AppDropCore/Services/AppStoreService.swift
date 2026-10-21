import Foundation

/// Which App Store catalog a lookup/search result belongs to.
public enum AppStoreAppPlatform: String, Sendable, Equatable {
    /// Mac App Store app.
    case macOS
    /// iPhone / iPad app.
    case iOS
}

/// Search scope: the Mac App Store catalog or the iPhone/iPad catalog.
public enum AppStoreSearchPlatform: String, Sendable, CaseIterable {
    case macOS
    case iOS

    /// Value for the iTunes `entity` query item.
    var entityValue: String {
        switch self {
        case .macOS: return "macSoftware"
        case .iOS: return "software"
        }
    }

    /// The Mac catalog query (`entity=macSoftware`) also returns a few iOS
    /// items, so results are filtered by the response's `kind`.
    func includes(_ app: AppStoreApp) -> Bool {
        switch self {
        case .macOS: return app.platform == .macOS
        case .iOS: return app.platform == .iOS
        }
    }
}

/// Business model for one App Store search/lookup result.
public struct AppStoreApp: Sendable, Equatable, Identifiable {
    public var trackId: String
    public var name: String
    public var developerName: String?
    public var artworkURL: String?
    public var appStoreURL: String?
    public var price: Decimal?
    public var formattedPrice: String?
    public var currency: String?
    /// Catalog the app belongs to (derived from the API `kind` field).
    public var platform: AppStoreAppPlatform

    public var id: String { trackId }

    public init(
        trackId: String,
        name: String,
        developerName: String? = nil,
        artworkURL: String? = nil,
        appStoreURL: String? = nil,
        price: Decimal? = nil,
        formattedPrice: String? = nil,
        currency: String? = nil,
        platform: AppStoreAppPlatform = .iOS
    ) {
        self.trackId = trackId
        self.name = name
        self.developerName = developerName
        self.artworkURL = artworkURL
        self.appStoreURL = appStoreURL
        self.price = price
        self.formattedPrice = formattedPrice
        self.currency = currency
        self.platform = platform
    }
}

public extension AppStoreApp {
    /// Returns a copy with missing price/currency fields filled in from a
    /// lookup result. Search responses occasionally omit the price (observed
    /// for some Mac catalog entries); a follow-up lookup usually has it.
    func fillingMissingPrice(from other: AppStoreApp?) -> AppStoreApp {
        guard let other else { return self }
        var merged = self
        if merged.price == nil { merged.price = other.price }
        if merged.formattedPrice == nil { merged.formattedPrice = other.formattedPrice }
        if merged.currency == nil { merged.currency = other.currency }
        if merged.appStoreURL == nil { merged.appStoreURL = other.appStoreURL }
        if merged.artworkURL == nil { merged.artworkURL = other.artworkURL }
        if merged.developerName == nil { merged.developerName = other.developerName }
        return merged
    }
}

/// Failure of one batch of a lookup request.
public struct LookupBatchFailure: Sendable, Equatable {
    public var ids: [String]
    public var message: String

    public init(ids: [String], message: String) {
        self.ids = ids
        self.message = message
    }
}

/// Aggregated, partial-success aware lookup result.
public struct LookupOutcome: Sendable, Equatable {
    public var apps: [AppStoreApp]
    /// Requested ids that a successful request did not return.
    public var missingIds: [String]
    /// Requested ids whose request failed entirely.
    public var failedIds: [String]
    public var failures: [LookupBatchFailure]

    public init(
        apps: [AppStoreApp] = [],
        missingIds: [String] = [],
        failedIds: [String] = [],
        failures: [LookupBatchFailure] = []
    ) {
        self.apps = apps
        self.missingIds = missingIds
        self.failedIds = failedIds
        self.failures = failures
    }
}

/// Errors surfaced by the App Store service.
public enum AppStoreServiceError: Error, LocalizedError, Equatable {
    case invalidURL
    case httpStatus(code: Int)
    case decodingFailed(message: String)
    case network(message: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not build a valid App Store request."
        case .httpStatus(let code):
            return "The App Store responded with HTTP status \(code)."
        case .decodingFailed(let message):
            return "Could not read the App Store response: \(message)"
        case .network(let message):
            return "Network error: \(message)"
        case .cancelled:
            return "The request was cancelled."
        }
    }
}

/// Retry configuration, injectable so tests can run without delays.
public struct RetryPolicy: Sendable, Equatable {
    public var maximumRetries: Int
    public var initialDelay: TimeInterval
    public var multiplier: Double

    public init(maximumRetries: Int, initialDelay: TimeInterval, multiplier: Double) {
        self.maximumRetries = maximumRetries
        self.initialDelay = initialDelay
        self.multiplier = multiplier
    }

    public static let `default` = RetryPolicy(
        maximumRetries: SharedConstants.transientRetryCount,
        initialDelay: 0.6,
        multiplier: 2.0
    )

    public static let immediate = RetryPolicy(
        maximumRetries: SharedConstants.transientRetryCount,
        initialDelay: 0,
        multiplier: 1.0
    )
}

/// Abstraction so that refresh logic can be tested without the network.
public protocol AppStoreFetching: Sendable {
    func lookup(appIds: [String], country: String) async -> LookupOutcome
    func search(keyword: String, country: String, platform: AppStoreSearchPlatform) async throws -> [AppStoreApp]
    func lookupOne(appId: String, country: String) async throws -> AppStoreApp?
}

/// URLSession based client for the public iTunes Search/Lookup API.
public final class AppStoreService: AppStoreFetching, @unchecked Sendable {
    public struct Configuration: Sendable {
        public var host: String
        public var requestTimeout: TimeInterval
        public var resourceTimeout: TimeInterval
        public var batchSize: Int
        public var maximumConcurrentRequests: Int
        public var searchLimit: Int
        public var retryPolicy: RetryPolicy

        public init(
            host: String = "itunes.apple.com",
            requestTimeout: TimeInterval = 15,
            resourceTimeout: TimeInterval = 40,
            batchSize: Int = SharedConstants.lookupBatchSize,
            maximumConcurrentRequests: Int = SharedConstants.maximumConcurrentRequests,
            searchLimit: Int = 25,
            retryPolicy: RetryPolicy = .default
        ) {
            self.host = host
            self.requestTimeout = requestTimeout
            self.resourceTimeout = resourceTimeout
            self.batchSize = batchSize
            self.maximumConcurrentRequests = maximumConcurrentRequests
            self.searchLimit = searchLimit
            self.retryPolicy = retryPolicy
        }
    }

    private let session: URLSession
    private let configuration: Configuration

    public init(session: URLSession? = nil, configuration: Configuration = Configuration()) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let sessionConfiguration = URLSessionConfiguration.default
            sessionConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
            sessionConfiguration.timeoutIntervalForResource = configuration.resourceTimeout
            sessionConfiguration.requestCachePolicy = .useProtocolCachePolicy
            sessionConfiguration.httpAdditionalHeaders = ["Accept": "application/json"]
            self.session = URLSession(configuration: sessionConfiguration)
        }
    }

    // MARK: - Lookup

    public func lookup(appIds: [String], country: String) async -> LookupOutcome {
        var seen = Set<String>()
        let uniqueIds = appIds.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !uniqueIds.isEmpty else { return LookupOutcome() }

        let batches = uniqueIds.chunked(into: max(1, configuration.batchSize))
        let limiter = AsyncSlotLimiter(limit: max(1, configuration.maximumConcurrentRequests))

        let batchResults = await withTaskGroup(of: (ids: [String], result: Result<[AppStoreApp], AppStoreServiceError>).self) { group in
            for batch in batches {
                group.addTask { [self] in
                    await limiter.acquire()
                    let result = await self.performLookupBatch(ids: batch, country: country)
                    await limiter.release()
                    return (batch, result)
                }
            }
            var collected: [(ids: [String], result: Result<[AppStoreApp], AppStoreServiceError>)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        var outcome = LookupOutcome()
        for (ids, result) in batchResults {
            switch result {
            case .success(let apps):
                outcome.apps.append(contentsOf: apps)
                let returnedIds = Set(apps.map(\.trackId))
                outcome.missingIds.append(contentsOf: ids.filter { !returnedIds.contains($0) })
            case .failure(let error):
                outcome.failedIds.append(contentsOf: ids)
                outcome.failures.append(LookupBatchFailure(ids: ids, message: error.localizedDescription))
            }
        }
        return outcome
    }

    /// Single id convenience used by "add app" and "replace storefront".
    public func lookupOne(appId: String, country: String) async throws -> AppStoreApp? {
        guard let url = lookupURL(ids: [appId], country: country) else {
            throw AppStoreServiceError.invalidURL
        }
        let data = try await performWithRetry(url: url)
        let response = try decode(ITunesResponse.self, from: data)
        return response.results.compactMap { $0.businessModel }.first
    }

    // MARK: - Search

    /// Searches one App Store catalog (Mac by default).
    ///
    /// The iTunes Search API exposes two catalogs: `entity=software` covers
    /// iPhone/iPad apps while macOS apps live in `entity=macSoftware`. The Mac
    /// catalog response is mixed, so results are filtered by `kind`.
    public func search(
        keyword: String,
        country: String,
        platform: AppStoreSearchPlatform = .macOS
    ) async throws -> [AppStoreApp] {
        let term = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return try await searchCatalog(term: term, country: country, platform: platform)
    }

    private func searchCatalog(
        term: String,
        country: String,
        platform: AppStoreSearchPlatform
    ) async throws -> [AppStoreApp] {
        switch await searchCatalogResult(term: term, country: country, platform: platform) {
        case .success(let apps): return apps
        case .failure(let error): throw error
        }
    }

    private func searchCatalogResult(
        term: String,
        country: String,
        platform: AppStoreSearchPlatform
    ) async -> Result<[AppStoreApp], AppStoreServiceError> {
        guard let url = searchURL(term: term, country: country, platform: platform) else {
            return .failure(.invalidURL)
        }
        do {
            let data = try await performWithRetry(url: url)
            let response = try decode(ITunesResponse.self, from: data)
            return .success(
                response.results
                    .compactMap { $0.businessModel }
                    .filter { platform.includes($0) }
            )
        } catch let error as AppStoreServiceError {
            return .failure(error)
        } catch {
            return .failure(.network(message: error.localizedDescription))
        }
    }

    // MARK: - Request plumbing

    private func lookupURL(ids: [String], country: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = configuration.host
        components.path = "/lookup"
        components.queryItems = [
            URLQueryItem(name: "id", value: ids.joined(separator: ",")),
            URLQueryItem(name: "country", value: StoreCountry.normalized(country))
        ]
        return components.url
    }

    private func searchURL(term: String, country: String, platform: AppStoreSearchPlatform) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = configuration.host
        components.path = "/search"
        var queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: StoreCountry.normalized(country))
        ]
        queryItems.append(URLQueryItem(name: "entity", value: platform.entityValue))
        queryItems.append(URLQueryItem(name: "limit", value: String(configuration.searchLimit)))
        components.queryItems = queryItems
        return components.url
    }

    private func performLookupBatch(ids: [String], country: String) async -> Result<[AppStoreApp], AppStoreServiceError> {
        guard let url = lookupURL(ids: ids, country: country) else {
            return .failure(.invalidURL)
        }
        do {
            let data = try await performWithRetry(url: url)
            let response = try decode(ITunesResponse.self, from: data)
            return .success(response.results.compactMap { $0.businessModel })
        } catch let error as AppStoreServiceError {
            return .failure(error)
        } catch {
            return .failure(.network(message: error.localizedDescription))
        }
    }

    private func performWithRetry(url: URL) async throws -> Data {
        var attempt = 0
        var lastError: AppStoreServiceError = .network(message: "Unknown error")

        while attempt <= configuration.retryPolicy.maximumRetries {
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = configuration.requestTimeout

            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    let error = AppStoreServiceError.httpStatus(code: http.statusCode)
                    if Self.isTransient(statusCode: http.statusCode), attempt < configuration.retryPolicy.maximumRetries {
                        lastError = error
                        try await Self.sleep(attempt: attempt, policy: configuration.retryPolicy)
                        attempt += 1
                        continue
                    }
                    throw error
                }
                return data
            } catch is CancellationError {
                throw AppStoreServiceError.cancelled
            } catch let error as AppStoreServiceError {
                throw error
            } catch {
                let serviceError = Self.mapNetworkError(error)
                if Self.isTransient(error: error), attempt < configuration.retryPolicy.maximumRetries {
                    lastError = serviceError
                    try await Self.sleep(attempt: attempt, policy: configuration.retryPolicy)
                    attempt += 1
                    continue
                }
                throw serviceError
            }
        }
        throw lastError
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AppStoreServiceError.decodingFailed(message: error.localizedDescription)
        }
    }

    private static func sleep(attempt: Int, policy: RetryPolicy) async throws {
        guard policy.initialDelay > 0 else { return }
        let base = policy.initialDelay * pow(policy.multiplier, Double(attempt))
        let jitter = Double.random(in: 0.9...1.1)
        let delay = base * jitter
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    private static func isTransient(statusCode: Int) -> Bool {
        statusCode == 429 || (500..<600).contains(statusCode)
    }

    private static func isTransient(error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private static func mapNetworkError(_ error: Error) -> AppStoreServiceError {
        if let urlError = error as? URLError {
            return .network(message: urlError.localizedDescription)
        }
        return .network(message: error.localizedDescription)
    }
}

/// Decoding model of the iTunes JSON payload.
struct ITunesResponse: Decodable {
    var resultCount: Int
    var results: [ITunesItem]
}

struct ITunesItem: Decodable {
    var trackId: Int?
    var trackName: String?
    var artistName: String?
    var artworkUrl100: String?
    var artworkUrl512: String?
    var trackViewUrl: String?
    var price: Decimal?
    var formattedPrice: String?
    var currency: String?
    /// `mac-software` for Mac App Store apps, `software` for iPhone/iPad apps.
    var kind: String?

    var businessModel: AppStoreApp? {
        guard let trackId, let trackName, !trackName.isEmpty else { return nil }
        return AppStoreApp(
            trackId: String(trackId),
            name: trackName,
            developerName: artistName,
            artworkURL: artworkUrl512 ?? artworkUrl100,
            appStoreURL: trackViewUrl,
            price: price,
            formattedPrice: formattedPrice,
            currency: currency,
            platform: kind == "mac-software" ? .macOS : .iOS
        )
    }
}

/// Simple async slot limiter used to cap concurrent requests.
actor AsyncSlotLimiter {
    private let limit: Int
    private var inUse = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if inUse < limit {
            inUse += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            inUse = max(0, inUse - 1)
        } else {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return [self] }
        var chunks: [[Element]] = []
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            chunks.append(Array(self[index..<end]))
            index = end
        }
        return chunks
    }
}
