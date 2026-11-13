import Foundation

// MARK: - QueryPlanRow

public struct QueryPlanRow: Sendable, Equatable, Identifiable {
    // MARK: Lifecycle

    public init(id: Int = 0, parent: Int = 0, detail: String) {
        self.id = id
        self.parent = parent
        self.detail = detail
    }

    // MARK: Public

    public let id: Int
    public let parent: Int
    public let detail: String
}

// MARK: - QueryProfile

public struct QueryProfile: Sendable {
    // MARK: Lifecycle

    public init(plan: [QueryPlanRow], wallClockMillis: Double) {
        self.plan = plan
        self.wallClockMillis = wallClockMillis
    }

    // MARK: Public

    public let plan: [QueryPlanRow]
    public let wallClockMillis: Double
}
