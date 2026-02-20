import CarrierWaveCore
import Foundation

// MARK: - Nonisolated Helpers

extension QSO {
    /// Deduplication key: callsign + band + mode + timestamp (rounded to 2 min)
    nonisolated var deduplicationKey: String {
        let roundedTimestamp = timestamp.timeIntervalSince1970
        let rounded = Int(roundedTimestamp / 120) * 120 // 2 minute buckets
        let trimmedCallsign = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let canonicalMode = ModeEquivalence.canonicalName(mode).uppercased()
        return "\(trimmedCallsign)|\(band.uppercased())|\(canonicalMode)|\(rounded)"
    }
}
