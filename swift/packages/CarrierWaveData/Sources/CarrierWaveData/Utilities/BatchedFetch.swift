// Batched Fetch — Memory-safe iteration over large SwiftData tables
//
// Encapsulates the "fresh ModelContext per batch" pattern required by
// PERFORMANCE.md. Each batch uses a new context so SwiftData can release
// row caches between batches, keeping peak memory at ~5 MB per batch
// instead of ~400 MB for a full table scan.

import Foundation
import SwiftData

// MARK: - BatchedFetch

/// Iterates over all matching records in batches of up to 1,000,
/// using a fresh `ModelContext` per batch to cap peak memory.
///
/// ```swift
/// let fetch = BatchedFetch<QSO>(
///     predicate: #Predicate { !$0.isHidden },
///     sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
/// )
/// let snapshots: [MySnapshot] = try await fetch.map(
///     container: container
/// ) { qso in
///     MySnapshot(from: qso)
/// }
/// ```
public struct BatchedFetch<T: PersistentModel> {
    // MARK: Lifecycle

    public init(
        predicate: Predicate<T>? = nil,
        sortBy: [SortDescriptor<T>] = [],
        batchSize: Int = Self.defaultBatchSize
    ) {
        precondition(
            batchSize >= 1 && batchSize <= Self.maxBatchSize,
            "Batch size must be 1...\(Self.maxBatchSize), got \(batchSize)"
        )
        self.predicate = predicate
        self.sortBy = sortBy
        self.batchSize = batchSize
    }

    // MARK: Public

    /// Default batch size matching PERFORMANCE.md recommendation.
    public static var defaultBatchSize: Int {
        1_000
    }

    /// Hard ceiling per batch — same as BoundedDescriptor.maxLimit.
    public static var maxBatchSize: Int {
        1_000
    }

    public let predicate: Predicate<T>?
    public let sortBy: [SortDescriptor<T>]
    public let batchSize: Int

    /// Transform each record into a `Sendable` snapshot, accumulating results.
    /// Uses a fresh `ModelContext` per batch to release row caches.
    ///
    /// - Parameters:
    ///   - container: The model container to create contexts from.
    ///   - transform: Converts a managed object to a lightweight value.
    ///     Return `nil` to skip (e.g. filtering metadata modes).
    ///   - onProgress: Called after each batch with total records processed.
    /// - Returns: Array of transformed results.
    public func map<Result: Sendable>(
        container: ModelContainer,
        transform: (T) -> Result?,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async throws -> [Result] {
        var results: [Result] = []
        try await forEach(
            container: container,
            onProgress: onProgress
        ) { item in
            if let result = transform(item) {
                results.append(result)
            }
        }
        return results
    }

    /// Process each record without accumulating results.
    /// Useful for streaming (e.g. writing to a file handle).
    ///
    /// - Parameters:
    ///   - container: The model container to create contexts from.
    ///   - onProgress: Called after each batch with total records processed.
    ///   - body: Called for each record in each batch.
    public func forEach(
        container: ModelContainer,
        onProgress: (@Sendable (Int) -> Void)? = nil,
        body: (T) throws -> Void
    ) async throws {
        var offset = 0

        while true {
            try Task.checkCancellation()

            let batchContext = ModelContext(container)
            batchContext.autosaveEnabled = false

            let descriptor = BoundedDescriptor<T>(
                predicate: predicate,
                sortBy: sortBy,
                limit: batchSize,
                offset: offset
            )

            let batch = try batchContext.boundedFetch(descriptor)
            guard !batch.isEmpty else {
                break
            }

            for item in batch {
                try body(item)
            }

            offset += batch.count
            onProgress?(offset)
            if batch.count < batchSize {
                break
            }
        }
    }

    /// Reduce all matching records into a single accumulated value.
    ///
    /// - Parameters:
    ///   - initial: The starting accumulator value.
    ///   - container: The model container to create contexts from.
    ///   - onProgress: Called after each batch with total records processed.
    ///   - combine: Folds each record into the accumulator.
    /// - Returns: The final accumulated value.
    public func reduce<Accumulator>(
        into initial: Accumulator,
        container: ModelContainer,
        onProgress: (@Sendable (Int) -> Void)? = nil,
        combine: (inout Accumulator, T) throws -> Void
    ) async throws -> Accumulator {
        var accumulator = initial
        try await forEach(
            container: container,
            onProgress: onProgress
        ) { item in
            try combine(&accumulator, item)
        }
        return accumulator
    }

    /// Count matching records without loading objects.
    public func count(container: ModelContainer) throws -> Int {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try context.boundedCount(T.self, predicate: predicate)
    }
}
