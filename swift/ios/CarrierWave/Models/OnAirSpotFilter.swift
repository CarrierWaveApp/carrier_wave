import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - OnAirSpotFilter

/// Encoding/decoding and filtering for On Air Now band/mode preferences.
/// Empty selections mean "show all".
enum OnAirSpotFilter {
    // MARK: Internal

    // MARK: - Set Encoding

    static func decodeSet(from raw: String) -> Set<String> {
        guard !raw.isEmpty else {
            return []
        }
        return Set(raw.components(separatedBy: ","))
    }

    static func encodeSet(_ values: Set<String>) -> String {
        values.sorted().joined(separator: ",")
    }

    // MARK: - POTA Filtering

    static func filterPOTA(
        _ spots: [POTASpot],
        bands: Set<String>,
        modes: Set<String>,
        maxAgeMinutes: Int? = nil
    ) -> [POTASpot] {
        spots.filter { spot in
            matchesBand(spot.frequencyKHz, bands: bands)
                && matchesMode(spot.mode, modes: modes)
                && matchesAge(spot.timestamp, maxAgeMinutes: maxAgeMinutes)
        }
    }

    // MARK: - SOTA Filtering

    static func filterSOTA(
        _ spots: [SOTASpot],
        bands: Set<String>,
        modes: Set<String>,
        maxAgeMinutes: Int? = nil
    ) -> [SOTASpot] {
        spots.filter { spot in
            matchesBand(spot.frequencyKHz, bands: bands)
                && matchesMode(spot.mode, modes: modes)
                && matchesAge(spot.parsedTimestamp, maxAgeMinutes: maxAgeMinutes)
        }
    }

    // MARK: - Friend Spot Filtering

    static func filterFriends(
        _ spots: [(callsign: String, spot: POTASpot)],
        bands: Set<String>,
        modes: Set<String>,
        maxAgeMinutes: Int? = nil
    ) -> [(callsign: String, spot: POTASpot)] {
        spots.filter { item in
            matchesBand(item.spot.frequencyKHz, bands: bands)
                && matchesMode(item.spot.mode, modes: modes)
                && matchesAge(
                    item.spot.timestamp, maxAgeMinutes: maxAgeMinutes
                )
        }
    }

    // MARK: - Age Matching

    static func matchesAge(
        _ timestamp: Date?,
        maxAgeMinutes: Int?
    ) -> Bool {
        guard let maxAge = maxAgeMinutes, let ts = timestamp else {
            return true
        }
        return Date().timeIntervalSince(ts) <= Double(maxAge) * 60
    }

    // MARK: - Band/Mode Match by Name (for P2P, where band is already a string)

    static func matchesBandByName(
        _ bandName: String,
        bands: Set<String>
    ) -> Bool {
        guard !bands.isEmpty else {
            return true
        }
        return bands.contains(bandName)
    }

    static func matchesModeValue(
        _ mode: String,
        modes: Set<String>
    ) -> Bool {
        guard !modes.isEmpty else {
            return true
        }
        return modes.contains { selected in
            let filter = ModeFilter(rawValue: selected) ?? .all
            return filter.matches(mode)
        }
    }

    // MARK: Private

    // MARK: - Match Helpers

    private static func matchesBand(
        _ frequencyKHz: Double?,
        bands: Set<String>
    ) -> Bool {
        guard !bands.isEmpty else {
            return true
        }
        guard let khz = frequencyKHz,
              let band = BandUtilities.deriveBand(from: khz)
        else {
            return false
        }
        return bands.contains(band)
    }

    private static func matchesMode(
        _ mode: String,
        modes: Set<String>
    ) -> Bool {
        guard !modes.isEmpty else {
            return true
        }
        return modes.contains { selected in
            let filter = ModeFilter(rawValue: selected) ?? .all
            return filter.matches(mode)
        }
    }
}
