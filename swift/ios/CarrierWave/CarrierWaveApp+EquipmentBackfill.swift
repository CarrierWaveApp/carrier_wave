// One-shot startup pass that copies equipment weight metadata from the
// activities-server catalog onto inventory items the user has already added.
// Lives in its own file because it pushed the main app struct over
// SwiftLint's type-body-length cap.

import CarrierWaveData
import SwiftData
import SwiftUI

extension CarrierWaveApp {
    /// Backfill `EquipmentItem.weightOunces` from `CatalogEntry.weightGrams`
    /// for any inventory item that's missing a weight. Runs after the catalog
    /// finishes loading so we have current data.
    func backfillEquipmentWeights() {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<EquipmentItem>()
        guard let items = try? context.fetch(descriptor) else {
            return
        }
        let updated = EquipmentWeight.backfill(
            items: items,
            catalog: EquipmentCatalogService.shared.catalog
        )
        if updated > 0 {
            try? context.save()
        }
    }

    /// Lift the global `RadioService` UserDefaults state onto the
    /// matching `EquipmentItem.connectionProfile` and back-fill
    /// `LoggingSession.radioItemID`. One-shot, idempotent.
    func runRadioConfigMigrationIfNeeded() {
        guard EquipmentMigration.isMigrated else {
            return
        }
        RadioConfigMigration.run(container: sharedModelContainer)
    }
}
