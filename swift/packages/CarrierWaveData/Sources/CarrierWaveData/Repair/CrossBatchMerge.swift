import Foundation
import SwiftData

/// A Repair shape: collect Sendable snapshots across all batches, then group/match
/// them to build merge actions, then apply each action by re-fetching winner+loser
/// in a save context, mutating winner, deleting loser.
///
/// Use for one-time dedup/merge fixes (e.g. PHONE/SSB duplicates, ServicePresence
/// dedup, two-fer reconciliation). For row-by-row mutations with no cross-row
/// state, use BatchedRewrite instead.
///
/// The seam is split into two phases so dry-run is free:
/// - plan() collects snapshots and runs match() — read-only.
/// - apply(_:) opens a save context, performs each merge, deletes losers, saves.
/// - run() is plan() + apply() for the common case.
///
/// Invariants the runner enforces:
/// - Snapshot collection uses fresh ModelContext per batch (≤ batchSize each).
/// - The matcher sees a Sendable [Snapshot] — never holds Models across batches.
/// - apply() uses one save context for all merges and saves once at the end.
///   (For very large action counts, callers can chunk plan.actions and call
///   apply() multiple times; the seam is intentionally simple.)
/// - The actor deletes the loser after the merge closure returns.
public actor CrossBatchMerge<Model: PersistentModel, Snapshot: Sendable> {
    // MARK: Lifecycle

    // MARK: - Init

    public init(
        label: String,
        container: ModelContainer,
        batchSize: Int = BoundedDescriptor<Model>.maxLimit,
        predicate: Predicate<Model>? = nil,
        sortBy: [SortDescriptor<Model>] = [],
        snapshot: @Sendable @escaping (Model) -> Snapshot?,
        match: @Sendable @escaping ([Snapshot]) -> [MergeAction],
        merge: @Sendable @escaping (_ winner: Model, _ loser: Model, _ context: ModelContext) -> Void
    ) {
        precondition(
            batchSize >= 1 && batchSize <= BoundedDescriptor<Model>.maxLimit,
            "CrossBatchMerge batchSize must be 1...\(BoundedDescriptor<Model>.maxLimit), got \(batchSize)"
        )
        self.label = label
        self.container = container
        self.batchSize = batchSize
        self.predicate = predicate
        self.sortBy = sortBy
        self.snapshot = snapshot
        self.match = match
        self.merge = merge
    }

    // MARK: Public

    // MARK: - Types

    public struct MergeAction: Sendable, Equatable {
        // MARK: Lifecycle

        public init(winnerId: PersistentIdentifier, loserId: PersistentIdentifier) {
            self.winnerId = winnerId
            self.loserId = loserId
        }

        // MARK: Public

        public let winnerId: PersistentIdentifier
        public let loserId: PersistentIdentifier
    }

    public struct Plan: Sendable {
        // MARK: Lifecycle

        public init(snapshotsCollected: Int, actions: [MergeAction]) {
            self.snapshotsCollected = snapshotsCollected
            self.actions = actions
        }

        // MARK: Public

        public let snapshotsCollected: Int
        public let actions: [MergeAction]
    }

    public struct Result: Sendable, Equatable {
        // MARK: Lifecycle

        public init(snapshotsCollected: Int, pairsFound: Int, merged: Int) {
            self.snapshotsCollected = snapshotsCollected
            self.pairsFound = pairsFound
            self.merged = merged
        }

        // MARK: Public

        public let snapshotsCollected: Int
        public let pairsFound: Int
        public let merged: Int
    }

    // MARK: - Phases

    /// Read-only. Collects snapshots, runs the matcher, returns the planned actions.
    public func plan() async throws -> Plan {
        var snapshots: [Snapshot] = []
        var offset = 0

        while !Task.isCancelled {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let descriptor = BoundedDescriptor<Model>(
                predicate: predicate,
                sortBy: sortBy,
                limit: batchSize,
                offset: offset
            )

            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }

            for row in batch {
                if let snap = snapshot(row) {
                    snapshots.append(snap)
                }
            }

            offset += batch.count
            if batch.count < batchSize {
                break
            }
            await Task.yield()
        }

        let actions = match(snapshots)
        return Plan(snapshotsCollected: snapshots.count, actions: actions)
    }

    /// Performs every action in a single save context. Each action: fetch winner +
    /// loser by PersistentIdentifier, run the merge closure, delete the loser.
    /// Saves once at the end.
    public func apply(_ plan: Plan) async throws -> Result {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var merged = 0
        for action in plan.actions {
            guard !Task.isCancelled else {
                break
            }
            guard
                let winner = context.model(for: action.winnerId) as? Model,
                let loser = context.model(for: action.loserId) as? Model
            else {
                continue
            }
            merge(winner, loser, context)
            context.delete(loser)
            merged += 1
        }

        if merged > 0 {
            try context.save()
        }

        return Result(
            snapshotsCollected: plan.snapshotsCollected,
            pairsFound: plan.actions.count,
            merged: merged
        )
    }

    // Convenience: plan then apply.
    public func run() async throws -> Result {
        let plan = try await plan()
        return try await apply(plan)
    }

    // MARK: Private

    private let label: String
    private let container: ModelContainer
    private let batchSize: Int
    private let predicate: Predicate<Model>?
    private let sortBy: [SortDescriptor<Model>]
    private let snapshot: @Sendable (Model) -> Snapshot?
    private let match: @Sendable ([Snapshot]) -> [MergeAction]
    private let merge: @Sendable (Model, Model, ModelContext) -> Void
}
