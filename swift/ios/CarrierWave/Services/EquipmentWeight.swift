// Helpers for the equipment weight field. Conversion lives in one place so all
// catalog → inventory copies and UI displays agree on rounding rules.
//
// Catalog supplies grams (server's `weight_grams` column); inventory items
// store whole ounces (1 oz ≈ 28.3495 g). We round to nearest oz; sub-oz noise
// from spec sheets gets clamped, which is acceptable for TOTA's "+5 % per 5 lb"
// scoring granularity.

import CarrierWaveData
import Foundation

// MARK: - EquipmentWeight

enum EquipmentWeight {
    /// Convert grams (catalog) to whole ounces (inventory). Rounds to nearest
    /// integer; values < 1 g become 0 (caller should treat 0 as "unknown").
    static func gramsToOunces(_ grams: Int) -> Int {
        guard grams > 0 else {
            return 0
        }
        let measurement = Measurement(value: Double(grams), unit: UnitMass.grams)
        return Int(measurement.converted(to: .ounces).value.rounded())
    }

    /// Sum the weights (oz) of a list of items, ignoring those without a
    /// recorded weight. Returns 0 when nothing has weights set.
    static func totalOunces(_ items: [EquipmentItem]) -> Int {
        items.compactMap(\.weightOunces).reduce(0, +)
    }

    /// Convert ounces to pounds rounded to one decimal place.
    static func ouncesToPounds(_ ounces: Int) -> Double {
        (Double(ounces) / 1.6).rounded() / 10.0
    }
}

// MARK: - Backfill

extension EquipmentWeight {
    /// One-shot pass that fills in `weightOunces` for any inventory item that
    /// matches a catalog entry by `catalogId`. Idempotent — leaves
    /// already-populated weights alone.
    @MainActor
    static func backfill(
        items: [EquipmentItem],
        catalog: [CatalogEntry]
    ) -> Int {
        guard !catalog.isEmpty else {
            return 0
        }
        let byId = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        var updated = 0
        for item in items where item.weightOunces == nil {
            guard let entry = byId[item.catalogId],
                  let grams = entry.weightGrams,
                  grams > 0
            else {
                continue
            }
            item.weightOunces = gramsToOunces(grams)
            updated += 1
        }
        return updated
    }
}
