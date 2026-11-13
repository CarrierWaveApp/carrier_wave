import CarrierWaveCwFfi
import Foundation

// MARK: - CallsignEditDistance

/// Levenshtein edit distance for callsign comparison.
/// Used to detect near-misses between spotted callsigns and logged QSOs.
///
/// A thin Swift facade over the Rust core
/// (`cw_domain::callsign_edit_distance`) — the distance + near-match logic is
/// shared with the Android app and covered by parity tests.
public enum CallsignEditDistance {
    /// Calculate Levenshtein edit distance between two strings (case-insensitive).
    /// - Returns: Minimum number of single-character insertions, deletions, or substitutions.
    public static func distance(_ s1: String, _ s2: String) -> Int {
        Int(callsignDistance(s1: s1, s2: s2))
    }

    /// Find candidates within a given edit distance of a target callsign.
    /// Skips exact matches (distance == 0).
    /// - Returns: Array of (candidate, distance) sorted by distance ascending.
    public static func findNearMatches(
        for callsign: String,
        maxDistance: Int,
        candidates: some Collection<String>
    ) -> [(callsign: String, distance: Int)] {
        callsignFindNearMatches(
            callsign: callsign,
            maxDistance: UInt32(max(0, maxDistance)),
            candidates: Array(candidates)
        )
        .map { (callsign: $0.callsign, distance: Int($0.distance)) }
    }
}
