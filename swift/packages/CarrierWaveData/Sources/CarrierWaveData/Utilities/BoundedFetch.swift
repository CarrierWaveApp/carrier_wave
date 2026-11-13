// Bounded Fetch — Compile-time enforced fetch limit for large SwiftData tables
//
// Wraps FetchDescriptor to guarantee that no single fetch can load more than
// 1,000 QSO or ServicePresence objects. This is the primary defense against
// unbounded fetches that cause OOM crashes on 4 GB devices.

import Foundation
import SwiftData

// MARK: - BoundedDescriptor

/// A `FetchDescriptor` wrapper that enforces a maximum fetch limit of 1,000.
///
/// Use this instead of raw `FetchDescriptor` for QSO and ServicePresence.
/// The initializer requires a `limit` parameter and rejects values above
/// `maxLimit`, making unbounded fetches a compile-time error (missing arg)
/// and over-limit fetches a runtime precondition failure.
///
/// ```swift
/// let desc = BoundedDescriptor<QSO>(
///     predicate: #Predicate { !$0.isHidden },
///     sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
///     limit: 100
/// )
/// let qsos = try context.boundedFetch(desc)
/// ```
public struct BoundedDescriptor<T: PersistentModel> {
    // MARK: Lifecycle

    public init(
        predicate: Predicate<T>? = nil,
        sortBy: [SortDescriptor<T>] = [],
        limit: Int,
        offset: Int = 0
    ) {
        precondition(
            limit >= 1 && limit <= Self.maxLimit,
            "Fetch limit must be 1...\(Self.maxLimit), got \(limit)"
        )
        precondition(offset >= 0, "Fetch offset must be non-negative")
        var desc = if let predicate {
            FetchDescriptor<T>(predicate: predicate, sortBy: sortBy)
        } else {
            FetchDescriptor<T>(sortBy: sortBy)
        }
        desc.fetchLimit = limit
        desc.fetchOffset = offset
        underlying = desc
    }

    public init(
        predicate: Predicate<T>? = nil,
        sortBy: [SortDescriptor<T>] = [],
        limit: Int,
        offset: Int = 0,
        relationshipKeyPathsForPrefetching: [KeyPath<T, some Any>]
    ) {
        precondition(
            limit >= 1 && limit <= Self.maxLimit,
            "Fetch limit must be 1...\(Self.maxLimit), got \(limit)"
        )
        precondition(offset >= 0, "Fetch offset must be non-negative")
        var desc = if let predicate {
            FetchDescriptor<T>(predicate: predicate, sortBy: sortBy)
        } else {
            FetchDescriptor<T>(sortBy: sortBy)
        }
        desc.fetchLimit = limit
        desc.fetchOffset = offset
        desc.relationshipKeyPathsForPrefetching = relationshipKeyPathsForPrefetching
        underlying = desc
    }

    // MARK: Public

    /// Hard ceiling: no single fetch may load more than 1,000 objects.
    public static var maxLimit: Int {
        1_000
    }

    /// The wrapped descriptor with fetchLimit and fetchOffset set.
    public let underlying: FetchDescriptor<T>
}

// MARK: - ModelContext + BoundedFetch

public extension ModelContext {
    /// Fetch using a `BoundedDescriptor`, guaranteeing the result set ≤ 1,000.
    func boundedFetch<T>(_ descriptor: BoundedDescriptor<T>) throws -> [T] {
        try fetch(descriptor.underlying)
    }

    /// Count matching records without loading objects. No limit needed.
    func boundedCount<T: PersistentModel>(
        _ type: T.Type,
        predicate: Predicate<T>? = nil
    ) throws -> Int {
        let descriptor = if let predicate {
            FetchDescriptor<T>(predicate: predicate)
        } else {
            FetchDescriptor<T>()
        }
        return try fetchCount(descriptor)
    }
}
