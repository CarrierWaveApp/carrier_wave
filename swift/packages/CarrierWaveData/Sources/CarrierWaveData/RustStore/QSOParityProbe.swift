import Foundation

// MARK: - QSOParityProbe

/// Compares SwiftData (authoritative) against the Rust mirror. This slice covers
/// the total-count invariant; richer field/order checks arrive with the list
/// migration.
public struct QSOParityProbe: Sendable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public struct CountResult: Sendable, Equatable {
        public let swiftData: Int
        public let rust: Int

        public var matches: Bool {
            swiftData == rust
        }
    }

    public func compareCounts(swiftData: Int, rust: Int) -> CountResult {
        CountResult(swiftData: swiftData, rust: rust)
    }

    public func compareQuery(
        query: String,
        swiftDataIDs: [String],
        rustIDs: [String]
    ) -> QueryParityResult {
        let status: QueryParityStatus = if swiftDataIDs == rustIDs {
            .match
        } else if rustIDs.count > swiftDataIDs.count,
                  Array(rustIDs.prefix(swiftDataIDs.count)) == swiftDataIDs
        {
            // Swift's bounded search window truncated; Rust returns the complete set.
            .rustSupersetLikelyBatchWindow
        } else {
            .mismatch
        }
        return QueryParityResult(
            query: query,
            swiftDataCount: swiftDataIDs.count,
            rustCount: rustIDs.count,
            status: status
        )
    }
}

// MARK: - QueryParityStatus

public enum QueryParityStatus: Sendable, Equatable {
    case match
    case rustSupersetLikelyBatchWindow // Swift IDs are a prefix of Rust IDs (Swift truncated)
    case mismatch
}

// MARK: - QueryParityResult

public struct QueryParityResult: Sendable, Equatable {
    // MARK: Lifecycle

    public init(query: String, swiftDataCount: Int, rustCount: Int, status: QueryParityStatus) {
        self.query = query
        self.swiftDataCount = swiftDataCount
        self.rustCount = rustCount
        self.status = status
    }

    // MARK: Public

    public let query: String
    public let swiftDataCount: Int
    public let rustCount: Int
    public let status: QueryParityStatus
}
