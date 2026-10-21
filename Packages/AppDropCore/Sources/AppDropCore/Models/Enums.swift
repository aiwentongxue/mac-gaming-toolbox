import Foundation

/// Type of a price history record.
public enum PriceRecordType: String, Codable, Sendable, CaseIterable {
    /// First successfully observed price for an app/storefront pair.
    case initial
    /// Price dropped compared with the previous effective price.
    case decrease
    /// Price rose compared with the previous effective price.
    case increase
    /// The storefront returned a different currency; treated as a fresh baseline.
    case currencyChange
}

/// Result of the most recent check attempt for a tracked app.
public enum CheckStatus: String, Codable, Sendable {
    /// The app has not been checked successfully yet.
    case unknown
    /// The most recent lookup succeeded.
    case ok
    /// The lookup succeeded but the app was not part of the storefront results.
    case notFound
    /// The lookup failed (network, HTTP, decoding, ...).
    case error
}

/// What triggered a refresh cycle.
public enum CheckSource: String, Codable, Sendable {
    case manual
    case background
    case onboarding
    case diagnostics
}

/// Aggregate result of a refresh cycle.
public enum CheckRunOutcome: String, Codable, Sendable {
    case success
    case partial
    case failed
    case skipped
}

/// Registration state of the background helper, mirroring `SMAppService.Status`.
public enum BackendState: String, Codable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown
}
