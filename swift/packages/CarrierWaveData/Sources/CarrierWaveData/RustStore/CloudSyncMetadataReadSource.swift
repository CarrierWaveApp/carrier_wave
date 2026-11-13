import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - CloudSyncMetadataSnapshot

/// A `Sendable`, value-type projection of one cloud-sync metadata row, used to
/// compare the SwiftData and Rust backends field-for-field. Mirrors
/// `FfiCloudSyncMetadata` exactly so a round-trip through cw-store can be verified
/// column-by-column. The table has no surface `id`; rows are keyed by the unique
/// CloudKit `recordName`, which is also the stable ordering key.
public struct CloudSyncMetadataSnapshot: Sendable, Equatable {
    // MARK: Lifecycle

    public init(ffi: FfiCloudSyncMetadata) {
        entityType = ffi.entityType
        localId = ffi.localId
        recordName = ffi.recordName
        encodedSystemFields = ffi.encodedSystemFields
        lastSyncedAt = ffi.lastSyncedAt
    }

    // MARK: Public

    public let entityType: String
    public let localId: String
    public let recordName: String
    public let encodedSystemFields: Data?
    public let lastSyncedAt: Int64?
}

// MARK: - CloudSyncMetadataReadSource

/// Reads CloudSyncMetadata records — the total count and the full,
/// `recordName`-ordered list.
public protocol CloudSyncMetadataReadSource: Sendable {
    func count() async throws -> Int
    func all() async throws -> [CloudSyncMetadataSnapshot]
}

// MARK: - SwiftDataCloudSyncMetadataReadSource

/// Reads CloudSyncMetadata from a SwiftData `ModelContext`. Snapshots are produced
/// via the canonical `SwiftDataStoreImporter.project(_:)` mapping so the comparison
/// against the Rust backend is a faithful round-trip check (no duplicated field
/// logic). `ModelContext` is not `Sendable`; this omits the conformance and uses an
/// `@unchecked Sendable` witness — callers should pin it to `@MainActor`.
public struct SwiftDataCloudSyncMetadataReadSource: @unchecked Sendable, CloudSyncMetadataReadSource {
    // MARK: Lifecycle

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Public

    public func count() async throws -> Int {
        try context.fetchCount(FetchDescriptor<CloudSyncMetadata>())
    }

    public func all() async throws -> [CloudSyncMetadataSnapshot] {
        try context.fetch(FetchDescriptor<CloudSyncMetadata>())
            .map { CloudSyncMetadataSnapshot(ffi: SwiftDataStoreImporter.project($0)) }
            .sorted { $0.recordName < $1.recordName }
    }

    // MARK: Private

    private let context: ModelContext
}

// MARK: - RustCloudSyncMetadataReadSource

/// Reads CloudSyncMetadata from a `FieldStore` (Rust backend).
public struct RustCloudSyncMetadataReadSource: CloudSyncMetadataReadSource {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        self.store = store
    }

    // MARK: Public

    public func count() async throws -> Int {
        try Int(store.cloudSyncMetadataCount())
    }

    public func all() async throws -> [CloudSyncMetadataSnapshot] {
        let filter = FfiCloudSyncMetadataFilter(entityType: nil)
        return try store.fetchCloudSyncMetadatas(filter: filter, limit: Self.listBound, offset: 0)
            .map(CloudSyncMetadataSnapshot.init(ffi:))
            .sorted { $0.recordName < $1.recordName }
    }

    // MARK: Private

    /// Bounded scan. cw-store caps `fetch_*` at 1,000 rows; sync metadata tracks
    /// active CloudKit records, well within the bound for a single fetch.
    private static let listBound: Int64 = 1_000

    private let store: FieldStore
}
