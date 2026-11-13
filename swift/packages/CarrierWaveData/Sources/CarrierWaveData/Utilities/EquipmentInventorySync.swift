import Foundation
import SwiftData

// MARK: - EquipmentRef

/// Lightweight reference to an EquipmentItem stored in iCloud KVS.
/// Contains enough data to reconstruct the item on a new device
/// and to provide display names for CWSweep (which lacks SwiftData).
public struct EquipmentRef: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        id: String,
        catalogId: String,
        name: String,
        category: String,
        manufacturer: String = ""
    ) {
        self.id = id
        self.catalogId = catalogId
        self.name = name
        self.category = category
        self.manufacturer = manufacturer
    }

    // MARK: Public

    /// EquipmentItem UUID string.
    public let id: String

    /// Catalog slug (e.g., "elecraft-kx2") or "custom-XXXXXXXX".
    public let catalogId: String

    /// Display name for tombstone recovery and CWSweep display.
    public let name: String

    /// EquipmentCategory raw value.
    public let category: String

    /// Manufacturer name (empty for custom items).
    public let manufacturer: String
}

// MARK: - EquipmentInventorySync

/// Syncs EquipmentItem inventory to/from iCloud KVS as JSON-encoded refs.
///
/// Each equipment category gets its own KVS key storing `[EquipmentRef]`.
/// This replaces the old string-array KVS keys while maintaining backward
/// compatibility by also writing the old format for CWSweep.
public enum EquipmentInventorySync {
    // MARK: Public

    /// KVS key names per category (SettingsSyncService adds the `v1.` prefix).
    public static func kvsKey(for category: EquipmentCategory) -> String {
        switch category {
        case .radio: "equipmentRefs.radio"
        case .antenna: "equipmentRefs.antenna"
        case .key: "equipmentRefs.key"
        case .microphone: "equipmentRefs.mic"
        case .accessory: "equipmentRefs.accessory"
        }
    }

    /// Push current inventory for a category to iCloud KVS.
    /// Also writes old-format string arrays for CWSweep backward compat.
    public static func pushToKVS(
        category: EquipmentCategory,
        items: [EquipmentItem]
    ) {
        let refs = items.map { item in
            EquipmentRef(
                id: item.id.uuidString,
                catalogId: item.catalogId,
                name: item.displayName,
                category: item.categoryRawValue,
                manufacturer: item.manufacturer
            )
        }

        // Write new format
        let key = kvsKey(for: category)
        if let data = try? JSONEncoder().encode(refs) {
            kvs.set(data, forKey: "v1.\(key)")
        }

        // Write old format for CWSweep backward compat
        if let oldKey = legacyKey(for: category) {
            let names = items
                .filter { !$0.isRetired }
                .map(\.displayName)
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            kvs.set(names, forKey: oldKey)
        }

        kvs.synchronize()
    }

    /// Push current inventory for a category to iCloud KVS from Rust-backed
    /// snapshots (the read-flip path — inventory now lives in cw-store, so the
    /// KVS publish sources from snapshots rather than SwiftData `EquipmentItem`s).
    /// Also writes old-format string arrays for CWSweep backward compat.
    public static func pushSnapshotsToKVS(
        category: EquipmentCategory,
        snapshots: [EquipmentInventorySnapshot]
    ) {
        let refs = snapshots.map { snapshot in
            EquipmentRef(
                id: snapshot.id.uuidString,
                catalogId: snapshot.catalogId,
                name: snapshot.displayName,
                category: snapshot.category.rawValue,
                manufacturer: snapshot.manufacturer
            )
        }

        let key = kvsKey(for: category)
        if let data = try? JSONEncoder().encode(refs) {
            kvs.set(data, forKey: "v1.\(key)")
        }

        if let oldKey = legacyKey(for: category) {
            let names = snapshots
                .filter { !$0.isRetired }
                .map(\.displayName)
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            kvs.set(names, forKey: oldKey)
        }

        kvs.synchronize()
    }

    /// Read refs from KVS without touching SwiftData.
    /// Falls back to old string keys if new format is absent.
    public static func loadRefsFromKVS(
        category: EquipmentCategory
    ) -> [EquipmentRef] {
        let key = "v1.\(kvsKey(for: category))"
        if let data = kvs.data(forKey: key),
           let refs = try? JSONDecoder().decode([EquipmentRef].self, from: data)
        {
            return refs.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }

        // Fallback: read old string keys
        guard let oldKey = legacyKey(for: category),
              let names = kvs.array(forKey: oldKey) as? [String]
        else {
            return []
        }

        return names.map { name in
            EquipmentRef(
                id: UUID().uuidString,
                catalogId: "custom-\(name.hashValue)",
                name: name,
                category: category.rawValue
            )
        }
    }

    /// Pull refs from KVS and reconcile with local SwiftData inventory.
    /// Creates items that exist in KVS but not locally (union-merge).
    @MainActor
    public static func pullFromKVS(
        category: EquipmentCategory,
        container: ModelContainer
    ) {
        let refs = loadRefsFromKVS(category: category)
        guard !refs.isEmpty else {
            return
        }

        let context = ModelContext(container)

        // Fetch existing items for this category
        var descriptor = FetchDescriptor<EquipmentItem>()
        descriptor.fetchLimit = 500
        let categoryRaw = category.rawValue
        descriptor.predicate = #Predicate<EquipmentItem> { item in
            item.categoryRawValue == categoryRaw
        }

        let existing: [EquipmentItem]
        do {
            existing = try context.fetch(descriptor)
        } catch {
            return
        }

        let existingIds = Set(existing.map(\.catalogId))
        let existingNames = Set(existing.map {
            $0.catalogName.lowercased()
        })

        // Create items for refs not in local inventory
        // Check both catalogId and name to avoid duplicates
        var didInsert = false
        for ref in refs {
            let nameLower = ref.name.lowercased()
            guard !existingIds.contains(ref.catalogId),
                  !existingNames.contains(nameLower)
            else {
                continue
            }
            let item = EquipmentItem(
                catalogId: ref.catalogId,
                catalogName: ref.name,
                category: category,
                manufacturer: ref.manufacturer
            )
            context.insert(item)
            didInsert = true
        }

        if didInsert {
            try? context.save()
        }
    }

    /// Pull all categories from KVS. Call from SettingsSyncService onPull.
    @MainActor
    public static func pullAllCategories(container: ModelContainer) {
        for category in EquipmentCategory.allCases {
            pullFromKVS(category: category, container: container)
        }
    }

    // MARK: Private

    private static let kvs = NSUbiquitousKeyValueStore.default

    /// Map new categories to old KVS string-array keys for backward compat.
    private static func legacyKey(
        for category: EquipmentCategory
    ) -> String? {
        switch category {
        case .radio: "userRadioList"
        case .antenna: "userAntennaList"
        case .key: "userKeyList"
        case .microphone: "userMicList"
        case .accessory: nil
        }
    }
}
