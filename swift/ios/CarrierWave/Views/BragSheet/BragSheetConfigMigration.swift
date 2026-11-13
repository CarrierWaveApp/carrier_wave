import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - BragSheetConfigMigration

/// One-time migration of the legacy iOS brag-sheet configuration
/// (JSON blob in `UserDefaults["bragSheetConfiguration"]`) into the shared
/// cw-store kv, via `BragSheetApi.importLegacyConfig`. Idempotent: the Rust
/// side only writes when the kv key is empty, and this marks a local flag so
/// repeat launches skip the UserDefaults read entirely.
nonisolated enum BragSheetConfigMigration {
    // MARK: Internal

    /// Import the legacy blob into the store if present and not already migrated.
    /// Runs off-main (call site is a detached task). Failures are benign — the
    /// store simply keeps its default config.
    static func migrateLegacyIfNeeded(api: BragSheetApi) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else {
            return
        }
        defer { defaults.set(true, forKey: migratedKey) }

        guard let json = legacyJSON(from: defaults) else {
            return
        }
        // `importLegacyConfig` is idempotent (no-op when kv already populated).
        _ = try? api.importLegacyConfig(legacyJson: json)
    }

    // MARK: Private

    private static let legacyKey = "bragSheetConfiguration"
    private static let migratedKey = "bragSheetConfigurationMigratedToStore"

    /// Read the legacy config as a JSON string. It was stored as `Data`
    /// (JSONEncoder output); tolerate a String value too.
    private static func legacyJSON(from defaults: UserDefaults) -> String? {
        if let data = defaults.data(forKey: legacyKey) {
            return String(data: data, encoding: .utf8)
        }
        if let string = defaults.string(forKey: legacyKey), !string.isEmpty {
            return string
        }
        return nil
    }
}
