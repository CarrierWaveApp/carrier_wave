import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - EquipmentItemSnapshot

/// A `Sendable`, value-type projection of one equipment item, used to compare the
/// SwiftData and Rust backends field-for-field. Mirrors `FfiEquipmentItem` exactly
/// so a round-trip through cw-store can be verified column-by-column. Unlike QSO
/// (whose list read needs the app-target query compiler), EquipmentItem list reads
/// are a plain table scan, so BOTH backends can produce snapshots — enabling a true
/// field + order parity check in the package.
public struct EquipmentItemSnapshot: Sendable, Equatable {
    // MARK: Lifecycle

    public init(ffi: FfiEquipmentItem) {
        id = ffi.id
        catalogId = ffi.catalogId
        catalogName = ffi.catalogName
        categoryRawValue = ffi.categoryRawValue
        nickname = ffi.nickname
        notes = ffi.notes
        acquiredDate = ffi.acquiredDate
        isRetired = ffi.isRetired
        bandsJSON = ffi.bandsJson
        modesJSON = ffi.modesJson
        maxPowerWatts = ffi.maxPowerWatts
        portabilityRawValue = ffi.portabilityRawValue
        manufacturer = ffi.manufacturer
        createdAt = ffi.createdAt
        weightOunces = ffi.weightOunces
        connectionProfileJSON = ffi.connectionProfileJson
    }

    // MARK: Public

    public let id: String
    public let catalogId: String
    public let catalogName: String
    public let categoryRawValue: String
    public let nickname: String?
    public let notes: String?
    public let acquiredDate: Int64?
    public let isRetired: Bool
    public let bandsJSON: Data
    public let modesJSON: Data
    public let maxPowerWatts: Int64?
    public let portabilityRawValue: String
    public let manufacturer: String
    public let createdAt: Int64
    public let weightOunces: Int64?
    public let connectionProfileJSON: Data?
}

// MARK: - EquipmentItemReadSource

/// Reads EquipmentItem records — the total count and the full, id-ordered list.
/// The equipment catalog is small (dozens of rows), so an unbounded-feeling list
/// read with a generous bound is acceptable here (this is NOT a QSO/ServicePresence
/// hot path subject to the 1,000-row cap).
public protocol EquipmentItemReadSource: Sendable {
    func count() async throws -> Int
    func all() async throws -> [EquipmentItemSnapshot]
}

// MARK: - SwiftDataEquipmentItemReadSource

/// Reads EquipmentItem from a SwiftData `ModelContext`. Snapshots are produced via
/// the canonical `SwiftDataStoreImporter.project(_:)` mapping so the comparison
/// against the Rust backend is a faithful round-trip check (no duplicated field
/// logic). `ModelContext` is not `Sendable`; this omits the conformance and uses an
/// `@unchecked Sendable` witness — callers should pin it to `@MainActor`.
public struct SwiftDataEquipmentItemReadSource: @unchecked Sendable, EquipmentItemReadSource {
    // MARK: Lifecycle

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Public

    public func count() async throws -> Int {
        try context.fetchCount(FetchDescriptor<EquipmentItem>())
    }

    public func all() async throws -> [EquipmentItemSnapshot] {
        try context.fetch(FetchDescriptor<EquipmentItem>())
            .map { EquipmentItemSnapshot(ffi: SwiftDataStoreImporter.project($0)) }
            .sorted { $0.id < $1.id }
    }

    // MARK: Private

    private let context: ModelContext
}

// MARK: - RustEquipmentItemReadSource

/// Reads EquipmentItem from a `FieldStore` (Rust backend).
public struct RustEquipmentItemReadSource: EquipmentItemReadSource {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        self.store = store
    }

    // MARK: Public

    public func count() async throws -> Int {
        try Int(store.equipmentItemCount())
    }

    public func all() async throws -> [EquipmentItemSnapshot] {
        let filter = FfiEquipmentItemFilter(categoryRawValue: nil, isRetired: nil, sort: .createdAtDesc)
        return try store.fetchEquipmentItems(filter: filter, limit: Self.listBound, offset: 0)
            .map(EquipmentItemSnapshot.init(ffi:))
            .sorted { $0.id < $1.id }
    }

    // MARK: Private

    /// Catalog scan bound. cw-store caps `fetch_*` at 1,000 rows (the bounded-fetch
    /// invariant); the equipment inventory is a few dozen rows, so this is ample.
    private static let listBound: Int64 = 1_000

    private let store: FieldStore
}
