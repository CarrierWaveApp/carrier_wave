import Foundation
import SwiftData

// MARK: - EquipmentItem

/// A piece of equipment the user owns, linked to a canonical catalog entry.
///
/// Replaces the old string-based `EquipmentStorage` with structured data.
/// Each item references a `CatalogEntry` by its slug ID and stores
/// user-specific metadata (nickname, notes, acquired date).
@Model
public final class EquipmentItem {
    // MARK: Lifecycle

    public init(
        catalogId: String,
        catalogName: String,
        category: EquipmentCategory,
        nickname: String? = nil,
        notes: String? = nil,
        acquiredDate: Date? = nil,
        isRetired: Bool = false,
        bands: [String] = [],
        modes: [String] = [],
        maxPowerWatts: Int? = nil,
        portability: PortabilityClass = .portable,
        manufacturer: String = "",
        weightOunces: Int? = nil
    ) {
        id = UUID()
        self.catalogId = catalogId
        self.catalogName = catalogName
        categoryRawValue = category.rawValue
        self.nickname = nickname
        self.notes = notes
        self.acquiredDate = acquiredDate
        self.isRetired = isRetired
        bandsJSON = (try? JSONEncoder().encode(bands)) ?? Data()
        modesJSON = (try? JSONEncoder().encode(modes)) ?? Data()
        self.maxPowerWatts = maxPowerWatts
        portabilityRawValue = portability.rawValue
        self.manufacturer = manufacturer
        createdAt = Date()
        self.weightOunces = weightOunces
    }

    // MARK: Public

    public var id: UUID
    public var catalogId: String
    public var catalogName: String
    public var categoryRawValue: String
    public var nickname: String?
    public var notes: String?
    public var acquiredDate: Date?
    public var isRetired: Bool
    public var bandsJSON: Data
    public var modesJSON: Data
    public var maxPowerWatts: Int?
    public var portabilityRawValue: String
    public var manufacturer: String
    public var createdAt: Date
    /// User-entered weight in whole ounces. Used by TOTA to estimate ruck
    /// weight from the selected gear at session start.
    public var weightOunces: Int?

    /// Encoded `RadioConnectionProfile` for radio-class items.
    /// Optional / unset for non-radio gear or unconfigured radios.
    /// Stored as JSON to avoid a schema migration whenever the profile
    /// gains new fields.
    public var connectionProfileJSON: Data?

    public var category: EquipmentCategory {
        EquipmentCategory(rawValue: categoryRawValue) ?? .accessory
    }

    public var portability: PortabilityClass {
        PortabilityClass(rawValue: portabilityRawValue) ?? .portable
    }

    public var bands: [String] {
        (try? JSONDecoder().decode([String].self, from: bandsJSON)) ?? []
    }

    public var modes: [String] {
        (try? JSONDecoder().decode([String].self, from: modesJSON)) ?? []
    }

    /// Display name: nickname if set, otherwise catalog name.
    public var displayName: String {
        if let nickname, !nickname.isEmpty {
            return nickname
        }
        return catalogName
    }

    /// Full display with manufacturer.
    public var fullDisplayName: String {
        if let nickname, !nickname.isEmpty {
            return "\(nickname) (\(manufacturer) \(catalogName))"
        }
        if !manufacturer.isEmpty {
            return "\(manufacturer) \(catalogName)"
        }
        return catalogName
    }

    /// Whether this is user-defined equipment not linked to the catalog.
    /// Custom items use the user's own name and manually-entered specs.
    public var isCustom: Bool {
        catalogId.hasPrefix("custom-")
    }

    /// Decoded radio connection profile. nil for non-radio items or
    /// radios the user hasn't configured yet.
    public var connectionProfile: RadioConnectionProfile? {
        get {
            guard let data = connectionProfileJSON else {
                return nil
            }
            return try? JSONDecoder().decode(
                RadioConnectionProfile.self, from: data
            )
        }
        set {
            connectionProfileJSON = newValue.flatMap {
                try? JSONEncoder().encode($0)
            }
        }
    }

    /// Create a custom equipment item not linked to any catalog entry.
    /// Users can name it however they want and manually set specs.
    public static func custom(
        name: String,
        category: EquipmentCategory,
        bands: [String] = [],
        modes: [String] = [],
        maxPowerWatts: Int? = nil,
        portability: PortabilityClass = .portable
    ) -> EquipmentItem {
        EquipmentItem(
            catalogId: "custom-\(UUID().uuidString.prefix(8))",
            catalogName: name,
            category: category,
            bands: bands,
            modes: modes,
            maxPowerWatts: maxPowerWatts,
            portability: portability
        )
    }

    /// Whether this equipment covers a given band.
    public func supportsBand(_ band: String) -> Bool {
        let decoded = bands
        return decoded.isEmpty || decoded.contains(band)
    }

    /// Whether this equipment supports a given mode family.
    public func supportsMode(_ mode: String) -> Bool {
        let decoded = modes
        if decoded.isEmpty {
            return true
        }
        let upper = mode.uppercased()
        return decoded.contains { $0.uppercased() == upper }
    }
}

// MARK: - EquipmentInventorySnapshot

/// Lightweight sendable snapshot of an EquipmentItem for cross-actor use.
public struct EquipmentInventorySnapshot: Sendable, Identifiable, Equatable {
    // MARK: Lifecycle

    public init(item: EquipmentItem) {
        id = item.id
        catalogId = item.catalogId
        catalogName = item.catalogName
        category = item.category
        nickname = item.nickname
        bands = item.bands
        modes = item.modes
        maxPowerWatts = item.maxPowerWatts
        portability = item.portability
        manufacturer = item.manufacturer
        isRetired = item.isRetired
        acquiredDate = item.acquiredDate
        createdAt = item.createdAt
        weightOunces = item.weightOunces
        connectionProfile = item.connectionProfile
    }

    // MARK: Public

    public let id: UUID
    public let catalogId: String
    public let catalogName: String
    public let category: EquipmentCategory
    public let nickname: String?
    public let bands: [String]
    public let modes: [String]
    public let maxPowerWatts: Int?
    public let portability: PortabilityClass
    public let manufacturer: String
    public let isRetired: Bool
    public let acquiredDate: Date?
    public let createdAt: Date
    public let weightOunces: Int?
    public let connectionProfile: RadioConnectionProfile?

    /// Best-effort date the equipment was added to the inventory.
    /// Prefers the user-set acquired date when available, otherwise falls
    /// back to the record creation date.
    public var dateAdded: Date {
        acquiredDate ?? createdAt
    }

    /// Whether this is user-defined equipment not linked to the catalog.
    public var isCustom: Bool {
        catalogId.hasPrefix("custom-")
    }

    public var displayName: String {
        if let nickname, !nickname.isEmpty {
            return nickname
        }
        return catalogName
    }

    public func supportsBand(_ band: String) -> Bool {
        bands.isEmpty || bands.contains(band)
    }

    public func supportsMode(_ mode: String) -> Bool {
        if modes.isEmpty {
            return true
        }
        let upper = mode.uppercased()
        return modes.contains { $0.uppercased() == upper }
    }
}
