import CarrierWaveCore
import Foundation

// MARK: - DXpeditionSpotGrouper

/// Groups RBN spots by band+mode for compact display on DXpedition cards.
enum DXpeditionSpotGrouper {
    /// A grouped band/mode entry with spot count.
    struct Entry {
        let band: String
        let mode: String
        let count: Int

        /// Display label like "20m CW" or "40m FT8 ×3"
        var label: String {
            if count > 1 {
                "\(band) \(mode) ×\(count)"
            } else {
                "\(band) \(mode)"
            }
        }
    }

    /// Group spots by band+mode, sorted by count descending.
    static func group(_ spots: [RBNSpot]) -> [Entry] {
        var entries: [String: Entry] = [:]
        for spot in spots {
            let band = spot.band.isEmpty ? "?" : spot.band
            let key = "\(band)-\(spot.mode)"
            if let existing = entries[key] {
                entries[key] = Entry(band: band, mode: spot.mode, count: existing.count + 1)
            } else {
                entries[key] = Entry(band: band, mode: spot.mode, count: 1)
            }
        }
        return entries.values.sorted { $0.count > $1.count }
    }
}
