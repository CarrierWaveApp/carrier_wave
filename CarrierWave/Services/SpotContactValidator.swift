import CarrierWaveCore
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
/// A spot callsign within edit distance 2 of a logged QSO callsign (but not
/// an exact match) suggests the operator may have copied the callsign wrong.
enum SpotContactValidator {
    /// Maximum edit distance to consider a near-miss.
    static let maxEditDistance = 2

    /// Compare spots against QSOs for a session, returning potential mismatches.
    ///
    /// - Parameters:
    ///   - spots: SessionSpot records for the session
    ///   - qsos: QSO records for the session (non-hidden, non-metadata)
    /// - Returns: Array of mismatches, deduplicated by QSO (keeps closest match)
    static func findMismatches(
        spots: [SessionSpot],
        qsos: [QSO]
    ) -> [SpotContactMismatch] {
        guard !spots.isEmpty, !qsos.isEmpty else { return [] }

        let spotCallsigns = Set(spots.map { $0.callsign.uppercased() })
        let qsoCallsigns = Set(qsos.map { $0.callsign.uppercased() })

        // For each QSO callsign, check if any spot is a near-match
        // Skip QSOs whose callsign exactly matches a spot (that's correct)
        var bestByQSO: [UUID: SpotContactMismatch] = [:]

        for qso in qsos {
            let qsoCall = qso.callsign.uppercased()

            // If this QSO callsign exactly matches a spot, no problem
            if spotCallsigns.contains(qsoCall) { continue }

            // Find near-matches among spot callsigns
            let nearMatches = CallsignEditDistance.findNearMatches(
                for: qsoCall,
                maxDistance: maxEditDistance,
                candidates: spotCallsigns
            )

            guard let closest = nearMatches.first else { continue }

            // Also skip if the spot callsign was already logged as a different QSO
            // (the operator worked both stations, no mismatch)
            if qsoCallsigns.contains(closest.callsign) { continue }

            // Find the actual spot record for context
            let matchingSpot = spots.first {
                $0.callsign.uppercased() == closest.callsign
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
