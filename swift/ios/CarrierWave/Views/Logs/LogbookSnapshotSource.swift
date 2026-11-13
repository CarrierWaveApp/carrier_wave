import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - LogbookSnapshotSource

/// The Logbook list renders `[QSORowSnapshot]` from this. The only backend is the
/// shared Rust store (`RustLogbookSource`); `EmptyLogbookSource` is a no-data
/// stand-in for the rare case the store can't be opened.
/// An empty `query` means "all non-hidden, newest first" — the Logbook base predicate.
@MainActor
protocol LogbookSnapshotSource {
    func page(query: String, limit: Int, offset: Int) async throws -> [QSORowSnapshot]
    func count(query: String) async throws -> Int

    /// `true` when a filtered (non-empty) query paginates over the whole match set.
    var paginatesFilteredFully: Bool { get }
}

// MARK: - EmptyLogbookSource

/// Yields no rows. Used only when the Rust store can't be opened — there is no
/// SwiftData fallback anymore.
@MainActor
struct EmptyLogbookSource: LogbookSnapshotSource {
    var paginatesFilteredFully: Bool {
        true
    }

    func page(query _: String, limit _: Int, offset _: Int) async throws -> [QSORowSnapshot] {
        []
    }

    func count(query _: String) async throws -> Int {
        0
    }
}

// MARK: - RustLogbookSource

/// The cutover backend. Delegates to `RustQSOReadSource`, which compiles the query
/// to SQL and filters the whole table — so filtered search paginates fully and
/// supports "Load More". The async FFI calls run off the main actor automatically
/// (nonisolated async on a value type).
@MainActor
struct RustLogbookSource: LogbookSnapshotSource {
    let rustSource: RustQSOReadSource

    var paginatesFilteredFully: Bool {
        true
    }

    func count(query: String) async throws -> Int {
        try await rustSource.count(query: query)
    }

    func page(query: String, limit: Int, offset: Int) async throws -> [QSORowSnapshot] {
        try await rustSource.page(query: query, limit: limit, offset: offset)
    }
}
