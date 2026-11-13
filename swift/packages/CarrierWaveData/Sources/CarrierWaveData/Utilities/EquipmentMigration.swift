import Foundation
import SwiftData

// MARK: - EquipmentMigration

/// Migrates legacy string-based equipment lists (EquipmentStorage + StationProfile)
/// to the new structured EquipmentItem model.
///
/// Migration flow:
/// 1. Read old string lists from iCloud KVS (antennas, keys, mics)
/// 2. Read rig names from LoggingSession history
/// 3. Fuzzy-match each against the catalog
/// 4. Create EquipmentItem entries (matched or unmatched)
/// 5. Mark migration complete in UserDefaults
public enum EquipmentMigration {
    // MARK: Public

    /// Whether the migration has already been completed.
    public static var isMigrated: Bool {
        UserDefaults.standard.bool(forKey: migrationKey)
    }

    /// Run the migration, matching legacy equipment strings against the catalog.
    ///
    /// - Parameters:
    ///   - catalog: The full equipment catalog for fuzzy matching.
    ///   - container: SwiftData model container for creating EquipmentItems.
    /// - Returns: Summary of migration results.
    @MainActor
    public static func migrate(
        catalog: [CatalogEntry],
        container: ModelContainer
    ) -> MigrationResult {
        guard !isMigrated else {
            return MigrationResult(migrated: 0, matched: 0, unmatched: 0)
        }

        let context = ModelContext(container)
        var counts = MigrationResult(migrated: 0, matched: 0, unmatched: 0)

        let legacySources: [(String, EquipmentCategory)] = [
            ("userAntennaList", .antenna),
            ("userKeyList", .key),
            ("userMicList", .microphone),
        ]

        for (key, category) in legacySources {
            let names = loadLegacyList(key: key)
            migrateNames(names, category: category, catalog: catalog, context: context, counts: &counts)
        }

        // Migrate unique rigs from session history
        let rigs = collectUniqueRigs(context: context)
        migrateNames(rigs, category: .radio, catalog: catalog, context: context, counts: &counts)

        try? context.save()
        UserDefaults.standard.set(true, forKey: migrationKey)

        return counts
    }

    /// Reset migration flag (for testing or re-migration after catalog update).
    public static func resetMigration() {
        UserDefaults.standard.removeObject(forKey: migrationKey)
    }

    /// Delete all equipment items and reset migration flag so the
    /// interactive migration sheet can be re-presented.
    @MainActor
    public static func resetAndClearItems(container: ModelContainer) {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<EquipmentItem>()
        descriptor.fetchLimit = 500
        if let items = try? context.fetch(descriptor) {
            for item in items {
                context.delete(item)
            }
            try? context.save()
        }
        resetMigration()
    }

    // MARK: Private

    private static let migrationKey = "equipmentInventory.migrated"

    private static func migrateNames(
        _ names: [String],
        category: EquipmentCategory,
        catalog: [CatalogEntry],
        context: ModelContext,
        counts: inout MigrationResult
    ) {
        for name in names {
            let didMatch = migrateItem(
                name: name,
                category: category,
                catalog: catalog,
                context: context
            )
            counts.migrated += 1
            if didMatch {
                counts.matched += 1
            } else {
                counts.unmatched += 1
            }
        }
    }

    private static func loadLegacyList(key: String) -> [String] {
        let kvs = NSUbiquitousKeyValueStore.default
        return kvs.array(forKey: key) as? [String] ?? []
    }

    /// Collect unique rig names from session history.
    private static func collectUniqueRigs(context: ModelContext) -> [String] {
        var descriptor = FetchDescriptor<LoggingSession>()
        descriptor.fetchLimit = 500
        guard let sessions = try? context.fetch(descriptor) else {
            return []
        }
        var seen = Set<String>()
        var rigs: [String] = []
        for session in sessions {
            if let rig = session.myRig, !rig.isEmpty, !seen.contains(rig) {
                seen.insert(rig)
                rigs.append(rig)
            }
        }
        return rigs
    }

    /// Migrate a single equipment name. Returns true if matched to catalog.
    @discardableResult
    private static func migrateItem(
        name: String,
        category: EquipmentCategory,
        catalog: [CatalogEntry],
        context: ModelContext
    ) -> Bool {
        // Check if already migrated (avoid duplicates on re-run)
        var checkDescriptor = FetchDescriptor<EquipmentItem>()
        checkDescriptor.fetchLimit = 1
        let normalizedName = name.lowercased()
        checkDescriptor.predicate = #Predicate<EquipmentItem> { item in
            item.catalogName.localizedStandardContains(normalizedName)
        }
        if let existing = try? context.fetch(checkDescriptor), !existing.isEmpty {
            return true
        }

        if let match = CatalogMatcher.bestMatch(
            for: name,
            in: catalog,
            category: category
        ) {
            let item = EquipmentItem(
                catalogId: match.entry.id,
                catalogName: match.entry.name,
                category: category,
                nickname: name != match.entry.name ? name : nil,
                bands: match.entry.bands,
                modes: match.entry.modes.map(\.rawValue),
                maxPowerWatts: match.entry.maxPowerWatts,
                portability: match.entry.portability,
                manufacturer: match.entry.manufacturer
            )
            context.insert(item)
            return true
        } else {
            // No catalog match — create unlinked entry with user's name
            let item = EquipmentItem(
                catalogId: "custom-\(UUID().uuidString.prefix(8))",
                catalogName: name,
                category: category,
                manufacturer: ""
            )
            context.insert(item)
            return false
        }
    }
}

// MARK: - MigrationResult

/// Summary of equipment migration results.
public struct MigrationResult: Sendable {
    /// Total items migrated.
    public var migrated: Int
    /// Items matched to catalog entries.
    public var matched: Int
    /// Items created without catalog match.
    public var unmatched: Int
}
