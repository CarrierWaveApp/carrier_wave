import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - EquipmentItem ← FfiEquipmentItem (SwiftData mirror)

public extension EquipmentItem {
    /// Build a SwiftData mirror of a Rust-constructed item, preserving its id
    /// and timestamps so cw-store and SwiftData stay id-matched. Used by the
    /// gear picker's add path (Rust constructs + persists to cw-store; this
    /// keeps SwiftData readers — Settings browser, stats, CAT-connect — in sync).
    convenience init(ffiMirror ffi: FfiEquipmentItem) {
        self.init(
            catalogId: ffi.catalogId,
            catalogName: ffi.catalogName,
            category: EquipmentCategory(rawValue: ffi.categoryRawValue) ?? .accessory,
            nickname: ffi.nickname,
            notes: ffi.notes,
            acquiredDate: ffi.acquiredDate.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            isRetired: ffi.isRetired,
            bands: (try? JSONDecoder().decode([String].self, from: ffi.bandsJson)) ?? [],
            modes: (try? JSONDecoder().decode([String].self, from: ffi.modesJson)) ?? [],
            maxPowerWatts: ffi.maxPowerWatts.map { Int($0) },
            portability: PortabilityClass(rawValue: ffi.portabilityRawValue) ?? .portable,
            manufacturer: ffi.manufacturer,
            weightOunces: ffi.weightOunces.map { Int($0) }
        )
        id = UUID(uuidString: ffi.id) ?? id
        createdAt = Date(timeIntervalSince1970: TimeInterval(ffi.createdAt))
        connectionProfileJSON = ffi.connectionProfileJson
    }
}

// MARK: - EquipmentInventorySnapshot ← FfiEquipmentItem

/// Build an inventory snapshot from the Rust `FfiEquipmentItem`. This is the
/// load-bearing adapter for the read-flip: inventory read sites keep consuming
/// `EquipmentInventorySnapshot` (rich `[String]` bands/modes, decoded
/// `RadioConnectionProfile`, `Date`s) while the data now originates from
/// cw-store. Mirrors `init(item:)` field-for-field.
public extension EquipmentInventorySnapshot {
    init(ffi: FfiEquipmentItem) {
        // cw-store ids are lowercase UUID strings; `UUID(uuidString:)` is
        // case-insensitive, so this round-trips without uppercasing.
        id = UUID(uuidString: ffi.id) ?? UUID()
        catalogId = ffi.catalogId
        catalogName = ffi.catalogName
        category = EquipmentCategory(rawValue: ffi.categoryRawValue) ?? .accessory
        nickname = ffi.nickname
        bands = (try? JSONDecoder().decode([String].self, from: ffi.bandsJson)) ?? []
        modes = (try? JSONDecoder().decode([String].self, from: ffi.modesJson)) ?? []
        maxPowerWatts = ffi.maxPowerWatts.map { Int($0) }
        portability = PortabilityClass(rawValue: ffi.portabilityRawValue) ?? .portable
        manufacturer = ffi.manufacturer
        isRetired = ffi.isRetired
        acquiredDate = ffi.acquiredDate.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        createdAt = Date(timeIntervalSince1970: TimeInterval(ffi.createdAt))
        weightOunces = ffi.weightOunces.map { Int($0) }
        connectionProfile = ffi.connectionProfileJson.flatMap {
            try? JSONDecoder().decode(RadioConnectionProfile.self, from: $0)
        }
    }
}
