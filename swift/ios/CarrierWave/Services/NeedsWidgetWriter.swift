// Needs Widget Writer
//
// Writes matched needs spots to shared UserDefaults for the widget extension.
// Called from SpotMonitoringService after needs matching completes.

import CarrierWaveData
import Foundation

// MARK: - NeedsWidgetSpotData

/// Codable transport for sharing between app and widget.
struct NeedsWidgetSpotData: Codable {
    let id: String
    let callsign: String
    let frequencyMHz: Double
    let mode: String
    let needLabel: String
    let priority: Int
    let timestamp: Date
}

// MARK: - NeedsWidgetWriter

enum NeedsWidgetWriter {
    /// Write the current needs-matched spots to shared UserDefaults for the widget.
    static func update(spots: [EnrichedSpot]) {
        let needsSpots = spots
            .filter(\.hasNeeds)
            .sorted { ($0.highestNeedPriority?.rawValue ?? 0) > ($1.highestNeedPriority?.rawValue ?? 0) }
            .prefix(20)
            .map { spot in
                NeedsWidgetSpotData(
                    id: spot.id,
                    callsign: spot.spot.callsign,
                    frequencyMHz: spot.spot.frequencyMHz,
                    mode: spot.spot.mode,
                    needLabel: spot.matchedNeeds.first?.label ?? "",
                    priority: spot.highestNeedPriority?.rawValue ?? 0,
                    timestamp: spot.spot.timestamp
                )
            }

        guard let defaults = UserDefaults(suiteName: WidgetShared.appGroupID),
              let data = try? JSONEncoder().encode(Array(needsSpots))
        else {
            return
        }

        defaults.set(data, forKey: "needsWidgetSpots")
    }
}
