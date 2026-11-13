import Foundation
import SwiftData

/// A Repair shape: scan rows in batches, apply a per-row mutation, save per batch.
///
/// Use for one-time data fixes that operate row-by-row with no cross-row state
/// (e.g. clear a corrupt field, normalize a string, backfill from notes).
/// For repairs that need cross-row matching (dedup, merge), use CrossBatchMerge.
///
/// Invariants the runner enforces (so callers don't have to):
/// - Fresh ModelContext per batch with autosaveEnabled = false.
/// - BoundedDescriptor (≤ BoundedDescriptor.maxLimit per batch).
/// - Save only when the batch produced at least one mutation.
/// - Cooperative yield between batches so the runner doesn't starve other work.
/// - Stop when a fetch returns fewer rows than the batch size.
public actor BatchedRewrite<Model: PersistentModel> {
    // MARK: Lifecycle

    // MARK: - Init

    public init(
        label: String,
        container: ModelContainer,
        batchSize: Int = 500,
        predicate: Predicate<Model>? = nil,
        sortBy: [SortDescriptor<Model>] = [],
        mutate: @Sendable @escaping (Model, ModelContext) -> Bool,
        commit: (@Sendable ([Model], ModelContext) throws -> Void)? = nil
    ) {
        precondition(
            batchSize >= 1 && batchSize <= BoundedDescriptor<Model>.maxLimit,
            "BatchedRewrite batchSize must be 1...\(BoundedDescriptor<Model>.maxLimit), got \(batchSize)"
        )
        self.label = label
        self.container = container
        self.batchSize = batchSize
        self.predicate = predicate
        self.sortBy = sortBy
        self.mutate = mutate
        self.commit = commit
    }

    // MARK: Public

    // MARK: - Result

    public struct Result: Sendable, Equatable {
        // MARK: Lifecycle

        public init(scanned: Int, mutated: Int) {
            self.scanned = scanned
            self.mutated = mutated
        }

        // MARK: Public

        public let scanned: Int
        public let mutated: Int
    }

    // MARK: - Run

    public func run() async throws -> Result {
        var totalScanned = 0
        var totalMutated = 0
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

            totalScanned += batch.count

            // Collect the mutated rows (not just a count) so an injected `commit`
            // can write their canonical cw-store rows before saving SwiftData.
            var mutatedRows: [Model] = []
            for row in batch where mutate(row, context) {
                mutatedRows.append(row)
            }

            if !mutatedRows.isEmpty {
                if let commit {
                    try commit(mutatedRows, context)
                } else {
                    try context.save()
                }
                totalMutated += mutatedRows.count
            }

            offset += batch.count
            if batch.count < batchSize {
                break
            }
            await Task.yield()
        }

        return Result(scanned: totalScanned, mutated: totalMutated)
    }

    // MARK: Private

    private let label: String
    private let container: ModelContainer
    private let batchSize: Int
    private let predicate: Predicate<Model>?
    private let sortBy: [SortDescriptor<Model>]
    private let mutate: @Sendable (Model, ModelContext) -> Bool
    /// Optional seam-aware commit: write canonical cw-store rows for the mutated
    /// models, then save. `nil` → plain `context.save()` (default / `off` mode).
    private let commit: (@Sendable ([Model], ModelContext) throws -> Void)?
}
