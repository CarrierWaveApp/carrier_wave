import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - ActivityLogSnapshot

/// A `Sendable`, value-type projection of one activity log, used to compare the
/// SwiftData and Rust backends field-for-field. Mirrors `FfiActivityLog` exactly so
/// a round-trip through cw-store can be verified column-by-column.
public struct ActivityLogSnapshot: Sendable, Equatable {
    // MARK: Lifecycle

    public init(ffi: FfiActivityLog) {
        id = ffi.id
        name = ffi.name
        myCallsign = ffi.myCallsign
        createdAt = ffi.createdAt
        stationProfileId = ffi.stationProfileId
        currentGrid = ffi.currentGrid
        locationLabel = ffi.locationLabel
        isActive = ffi.isActive
        cloudDirtyFlag = ffi.cloudDirtyFlag
    }

    // MARK: Public

    public let id: String
    public let name: String
    public let myCallsign: String
    public let createdAt: Int64
    public let stationProfileId: String?
    public let currentGrid: String?
    public let locationLabel: String?
    public let isActive: Bool
    public let cloudDirtyFlag: Bool
}

// MARK: - ActivityLogReadSource

/// Reads ActivityLog records — the total count and the full, id-ordered list.
public protocol ActivityLogReadSource: Sendable {
    func count() async throws -> Int
    func all() async throws -> [ActivityLogSnapshot]
}

// MARK: - SwiftDataActivityLogReadSource

/// Reads ActivityLog from a SwiftData `ModelContext`. Snapshots are produced via the
/// canonical `SwiftDataStoreImporter.project(_:)` mapping so the comparison against
/// the Rust backend is a faithful round-trip check (no duplicated field logic).
/// `ModelContext` is not `Sendable`; this omits the conformance and uses an
/// `@unchecked Sendable` witness — callers should pin it to `@MainActor`.
public struct SwiftDataActivityLogReadSource: @unchecked Sendable, ActivityLogReadSource {
    // MARK: Lifecycle

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Public

    public func count() async throws -> Int {
        try context.fetchCount(FetchDescriptor<ActivityLog>())
    }

    public func all() async throws -> [ActivityLogSnapshot] {
        try context.fetch(FetchDescriptor<ActivityLog>())
            .map { ActivityLogSnapshot(ffi: SwiftDataStoreImporter.project($0)) }
            .sorted { $0.id < $1.id }
    }

    // MARK: Private

    private let context: ModelContext
}

// MARK: - RustActivityLogReadSource

/// Reads ActivityLog from a `FieldStore` (Rust backend).
public struct RustActivityLogReadSource: ActivityLogReadSource {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        self.store = store
    }

    // MARK: Public

    public func count() async throws -> Int {
        try Int(store.activityLogCount())
    }

    public func all() async throws -> [ActivityLogSnapshot] {
        let filter = FfiActivityLogFilter(myCallsign: nil, isActive: nil, dirtyOnly: false)
        return try store.fetchActivityLogs(filter: filter, limit: Self.listBound, offset: 0)
            .map(ActivityLogSnapshot.init(ffi:))
            .sorted { $0.id < $1.id }
    }

    // MARK: Private

    /// Bounded scan. cw-store caps `fetch_*` at 1,000 rows; activity logs number a
    /// handful per operator, well within the bound.
    private static let listBound: Int64 = 1_000

    private let store: FieldStore
}
