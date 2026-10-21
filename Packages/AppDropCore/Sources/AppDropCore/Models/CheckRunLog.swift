import Foundation
import SwiftData

/// Summary of one refresh cycle (manual or background).
@Model
public final class CheckRunLog {
    public var id: UUID
    public var startedAt: Date
    public var finishedAt: Date?
    public var sourceRaw: String
    public var outcomeRaw: String
    public var checkedCount: Int
    public var changedCount: Int
    public var failedCount: Int
    public var errorSummary: String?

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        finishedAt: Date? = nil,
        source: CheckSource,
        outcome: CheckRunOutcome,
        checkedCount: Int = 0,
        changedCount: Int = 0,
        failedCount: Int = 0,
        errorSummary: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.sourceRaw = source.rawValue
        self.outcomeRaw = outcome.rawValue
        self.checkedCount = checkedCount
        self.changedCount = changedCount
        self.failedCount = failedCount
        self.errorSummary = errorSummary
    }

    public var source: CheckSource {
        get { CheckSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public var outcome: CheckRunOutcome {
        get { CheckRunOutcome(rawValue: outcomeRaw) ?? .failed }
        set { outcomeRaw = newValue.rawValue }
    }

    public func makeEntry() -> CheckRunEntry {
        CheckRunEntry(
            id: id,
            startedAt: startedAt,
            finishedAt: finishedAt,
            source: source,
            outcome: outcome,
            checkedCount: checkedCount,
            changedCount: changedCount,
            failedCount: failedCount,
            errorSummary: errorSummary
        )
    }
}
