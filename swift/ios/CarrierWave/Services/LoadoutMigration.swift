// Loadout Migration
//
// One-time, non-destructive copy of the operator's saved loadouts from the
// legacy UserDefaults blob (`SavedSessionTemplateStore`) into the Rust
// `loadout` table. The UserDefaults copy is KEPT (never deleted) so the move is
// reversible and other consumers (e.g. session presets) are unaffected.

import CarrierWaveData
import Foundation

enum LoadoutMigration {
    // MARK: Internal

    /// Idempotent: gated on a UserDefaults marker, safe to call every launch.
    static func runIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: migratedKey) else {
            return
        }
        let templates = SavedSessionTemplateStore.load()
        // Loadouts are equipment-only — skip templates that carry no gear.
        let gearTemplates = templates.filter {
            $0.radio != nil || $0.antenna != nil || $0.key != nil || $0.mic != nil
        }
        guard !gearTemplates.isEmpty else {
            // Nothing to migrate — still set the marker so we don't re-scan.
            UserDefaults.standard.set(true, forKey: migratedKey)
            return
        }
        guard let store = try? await Equipment.loadouts() else {
            return // Store unavailable; retry next launch (marker unset).
        }
        for template in gearTemplates {
            let loadout = Loadout(
                id: template.id,
                name: template.name,
                radio: template.radio,
                antenna: template.antenna,
                key: template.key,
                mic: template.mic,
                radioItemID: nil,
                createdAt: template.createdAt,
                updatedAt: template.createdAt
            )
            try? await store.upsert(loadout)
        }
        UserDefaults.standard.set(true, forKey: migratedKey)
    }

    // MARK: Private

    private static let migratedKey = "loadouts.migratedToRust.v1"
}
