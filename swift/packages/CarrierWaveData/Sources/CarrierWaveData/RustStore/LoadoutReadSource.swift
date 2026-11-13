import CarrierWaveCore
import Foundation

// MARK: - Loadout

/// A named, equipment-only station preset — the portable replacement for the
/// iOS `SavedSessionTemplate` UserDefaults blob, backed by the cw-store
/// `loadout` table. A loadout is a name plus up to four equipment display names
/// and an optional `radioItemID` (an `EquipmentItem.id`) for CAT auto-connect.
public struct Loadout: Sendable, Identifiable, Equatable {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(),
        name: String,
        radio: String? = nil,
        antenna: String? = nil,
        key: String? = nil,
        mic: String? = nil,
        radioItemID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.radio = radio
        self.antenna = antenna
        self.key = key
        self.mic = mic
        self.radioItemID = radioItemID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(ffi: FfiLoadout) {
        id = UUID(uuidString: ffi.id) ?? UUID()
        name = ffi.name
        radio = ffi.radio
        antenna = ffi.antenna
        key = ffi.key
        mic = ffi.mic
        radioItemID = ffi.radioItemId.flatMap { UUID(uuidString: $0) }
        createdAt = Date(timeIntervalSince1970: TimeInterval(ffi.createdAt))
        updatedAt = Date(timeIntervalSince1970: TimeInterval(ffi.updatedAt))
    }

    // MARK: Public

    public let id: UUID
    public var name: String
    public var radio: String?
    public var antenna: String?
    public var key: String?
    public var mic: String?
    public var radioItemID: UUID?
    public let createdAt: Date
    public var updatedAt: Date

    /// The FFI record — id lowercased to the store's convention.
    public var ffi: FfiLoadout {
        FfiLoadout(
            id: SwiftDataStoreImporter.uuid(id),
            name: name,
            radio: radio,
            antenna: antenna,
            key: key,
            mic: mic,
            radioItemId: radioItemID.map { SwiftDataStoreImporter.uuid($0) },
            createdAt: Int64(createdAt.timeIntervalSince1970),
            updatedAt: Int64(updatedAt.timeIntervalSince1970)
        )
    }

    /// Whether any equipment slot is filled.
    public var hasAnyGear: Bool {
        [radio, antenna, key, mic].contains { !($0?.isEmpty ?? true) }
    }
}

// MARK: - LoadoutStore

/// Thin seam over the `FieldStore` loadout FFI. Loadouts are Rust-native (no
/// SwiftData model), so writes go straight through here. The table is tiny, but
/// methods are `async` so callers hop off the main actor for the DB touch.
public struct LoadoutStore: Sendable {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        self.store = store
    }

    // MARK: Public

    /// All loadouts, most-recently-edited first.
    public func all() async throws -> [Loadout] {
        try store.fetchLoadouts(limit: Self.listBound, offset: 0).map(Loadout.init(ffi:))
    }

    public func upsert(_ loadout: Loadout) async throws {
        try store.upsertLoadout(item: loadout.ffi)
    }

    public func delete(id: UUID) async throws {
        try store.deleteLoadout(id: SwiftDataStoreImporter.uuid(id))
    }

    // MARK: Private

    /// cw-store caps `fetch_*` at 1,000 rows; loadouts are a handful.
    private static let listBound: Int64 = 1_000

    private let store: FieldStore
}
