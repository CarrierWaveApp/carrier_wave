import CarrierWaveCore
import Foundation

public extension QSO {
    /// Deduplication key: callsign + band + mode + timestamp (rounded to 2 min)
    nonisolated var deduplicationKey: String {
        Self.makeDeduplicationKey(
            callsign: callsign, band: band, mode: mode, timestamp: timestamp
        )
    }

    /// Deduplication key using `originalCallsign` (the pre-edit contact
    /// callsign), or nil when no edit has occurred. Used by download-merge so a
    /// remote service still holding the pre-edit callsign re-merges into this
    /// QSO instead of inserting a duplicate. See CAR-245.
    nonisolated var originalDeduplicationKey: String? {
        guard let original = originalCallsign,
              !original.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return nil
        }
        return Self.makeDeduplicationKey(
            callsign: original, band: band, mode: mode, timestamp: timestamp
        )
    }

    nonisolated static func makeDeduplicationKey(
        callsign: String, band: String, mode: String, timestamp: Date
    ) -> String {
        let roundedTimestamp = timestamp.timeIntervalSince1970
        let rounded = Int(roundedTimestamp / 120) * 120
        let trimmedCallsign = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let canonicalMode = ModeEquivalence.canonicalNameForDedup(mode)
        return "\(trimmedCallsign)|\(band.uppercased())|\(canonicalMode)|\(rounded)"
    }
}
