import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - UploadDestinationSnapshot

/// A `Sendable`, value-type projection of one upload destination, used to compare
/// the SwiftData and Rust backends field-for-field. Mirrors `FfiUploadDestination`
/// exactly so a round-trip through cw-store can be verified column-by-column.
/// Upload destinations are a tiny fixed set (one per service), so a plain list
/// read with a generous bound enables a true field + order parity check.
public struct UploadDestinationSnapshot: Sendable, Equatable {
    // MARK: Lifecycle

    public init(ffi: FfiUploadDestination) {
        id = ffi.id
        typeRawValue = ffi.typeRawValue
        isEnabled = ffi.isEnabled
        lastSyncAt = ffi.lastSyncAt
    }

    // MARK: Public

    public let id: String
    public let typeRawValue: String
    public let isEnabled: Bool
    public let lastSyncAt: Int64?
}

// MARK: - UploadDestinationReadSource

/// Reads UploadDestination records — the total count and the full, id-ordered
/// list. The set is bounded (a handful of service rows), so an unbounded-feeling
/// list read with a generous bound is acceptable here.
public protocol UploadDestinationReadSource: Sendable {
    func count() async throws -> Int
    func all() async throws -> [UploadDestinationSnapshot]
}

// MARK: - SwiftDataUploadDestinationReadSource

/// Reads UploadDestination from a SwiftData `ModelContext`. Snapshots are produced
/// via the canonical `SwiftDataStoreImporter.project(_:)` mapping so the comparison
/// against the Rust backend is a faithful round-trip check (no duplicated field
/// logic). `ModelContext` is not `Sendable`; this omits the conformance and uses an
/// `@unchecked Sendable` witness — callers should pin it to `@MainActor`.
public struct SwiftDataUploadDestinationReadSource: @unchecked Sendable, UploadDestinationReadSource {
    // MARK: Lifecycle

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Public

    public func count() async throws -> Int {
        try context.fetchCount(FetchDescriptor<UploadDestination>())
    }

    public func all() async throws -> [UploadDestinationSnapshot] {
        try context.fetch(FetchDescriptor<UploadDestination>())
            .map { UploadDestinationSnapshot(ffi: SwiftDataStoreImporter.project($0)) }
            .sorted { $0.id < $1.id }
    }

    // MARK: Private

    private let context: ModelContext
}

// MARK: - RustUploadDestinationReadSource

/// Reads UploadDestination from a `FieldStore` (Rust backend).
public struct RustUploadDestinationReadSource: UploadDestinationReadSource {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        self.store = store
    }

    // MARK: Public

    public func count() async throws -> Int {
        try Int(store.uploadDestinationCount())
    }

    public func all() async throws -> [UploadDestinationSnapshot] {
        try store.fetchUploadDestinations(limit: Self.listBound, offset: 0)
            .map(UploadDestinationSnapshot.init(ffi:))
            .sorted { $0.id < $1.id }
    }

    // MARK: Private

    /// Bounded scan. cw-store caps `fetch_*` at 1,000 rows; the destination set is
    /// a handful of rows, so this is ample.
    private static let listBound: Int64 = 1_000

    private let store: FieldStore
}
