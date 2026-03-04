import CarrierWaveData
import Foundation
import SwiftData

// MARK: - SpotContactMismatch

/// A near-miss between a spotted callsign and a logged QSO.
struct SpotContactMismatch: Identifiable, Sendable {
    let id = UUID()
    /// The callsign from the spot
    let spotCallsign: String
    /// The callsign logged in the QSO
    let qsoCallsign: String
    /// The QSO that may be a mislog
    let qsoId: UUID
    /// Levenshtein edit distance between the two callsigns
    let editDistance: Int
    /// Spot source ("rbn" or "pota")
    let spotSource: String
    /// Spot timestamp
    let spotTimestamp: Date
}

// MARK: - SpotContactValidator

/// Compares session spots against logged QSOs to find potential mislogs.
///
/// Session spots record spots **about** the operator: RBN nodes hearing your
/// signal, or POTA spotters spotting your activation. The `callsign` field is
/// always YOUR callsign. The relevant field for mismatch detection is `spotter`
/// on POTA spots — the hunter who spotted (and likely worked) you.
///
/// A spotter callsign within edit distance 2 of a logged QSO callsign (but not
/// an exact match) suggests the operator may have copied the callsign wrong.
enum SpotContactValidator {
    /// Maximum edit distance to consider a near-miss.
    static let maxEditDistance = 2

    /// Compare spots against QSOs for a session, returning potential mismatches.
    ///
    /// For POTA spots, compares the `spotter` (the hunter who spotted you) against
    /// QSO callsigns. RBN spots are skipped — their spotters are skimmer nodes,
    /// not stations you worked.
    ///
    /// - Parameters:
    ///   - spots: SessionSpot records for the session
    ///   - qsos: QSO records for the session (non-hidden, non-metadata)
    /// - Returns: Array of mismatches, deduplicated by QSO (keeps closest match)
    static func findMismatches(
        spots: [SessionSpot],
        qsos: [QSO]
    ) -> [SpotContactMismatch] {
        guard !spots.isEmpty, !qsos.isEmpty else {
            return []
        }

        // Extract spotter callsigns from POTA spots (non-self, non-RBN).
        // These are hunters who spotted (and likely worked) the operator.
        let spotterCallsigns = Set(
            spots
                .filter { $0.isPOTA && !$0.isSelfSpot }
                .compactMap { $0.spotter?.uppercased() }
        )

        guard !spotterCallsigns.isEmpty else {
            return []
        }

        let qsoCallsigns = Set(qsos.map { $0.callsign.uppercased() })

        // For each QSO callsign, check if any spotter is a near-match
        // Skip QSOs whose callsign exactly matches a spotter (that's correct)
        var bestByQSO: [UUID: SpotContactMismatch] = [:]

        for qso in qsos {
            let qsoCall = qso.callsign.uppercased()

            // If this QSO callsign exactly matches a spotter, no problem
            if spotterCallsigns.contains(qsoCall) {
                continue
            }

            // Find near-matches among spotter callsigns
            let nearMatches = CallsignEditDistance.findNearMatches(
                for: qsoCall,
                maxDistance: maxEditDistance,
                candidates: spotterCallsigns
            )

            guard let closest = nearMatches.first else {
                continue
            }

            // Also skip if the spotter callsign was already logged as a different QSO
            // (the operator worked both stations, no mismatch)
            if qsoCallsigns.contains(closest.callsign) {
                continue
            }

            // Find the actual spot record for context
            let matchingSpot = spots.first {
                $0.spotter?.uppercased() == closest.callsign
            }

            let mismatch = SpotContactMismatch(
                spotCallsign: closest.callsign,
                qsoCallsign: qsoCall,
                qsoId: qso.id,
                editDistance: closest.distance,
                spotSource: matchingSpot?.source ?? "unknown",
                spotTimestamp: matchingSpot?.timestamp ?? Date()
            )

            // Keep only the closest match per QSO
            if let existing = bestByQSO[qso.id] {
                if mismatch.editDistance < existing.editDistance {
                    bestByQSO[qso.id] = mismatch
                }
            } else {
                bestByQSO[qso.id] = mismatch
            }
        }

        return Array(bestByQSO.values).sorted { $0.spotTimestamp > $1.spotTimestamp }
    }

    /// Fetch session spots from SwiftData for a given session ID.
    static func fetchSessionSpots(
        sessionId: UUID,
        modelContext: ModelContext
    ) -> [SessionSpot] {
        let predicate = #Predicate<SessionSpot> { spot in
            spot.loggingSessionId == sessionId
        }
        var descriptor = FetchDescriptor<SessionSpot>(predicate: predicate)
        descriptor.fetchLimit = 5_000
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
