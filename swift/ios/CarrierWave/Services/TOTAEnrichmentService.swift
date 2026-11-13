// TOTA enrichment: tile detection + T3 spot correlation persistence.
//
// Bridges between the iOS data layer (`LoggingSession`, `QSO`, `TrackPoint`)
// and the pure scoring engine in `CarrierWaveCore`. Owns the side effects:
//  - Computes the activated/candidate tile sets at session end and caches.
//  - Fetches the TOTA spots feed once per session-end (and on lazy refresh
//    when the cached snapshot is > 5 min old) and writes back T3 candidates.
//  - Builds `TOTAScoringInputs` from a session + QSOs for the score view.

import CarrierWaveCore
import CarrierWaveData
import Foundation

@MainActor
enum TOTAEnrichmentService {
    /// Lazy-refresh threshold for the T3 snapshot in the detail view.
    static let t3RefreshStaleness: TimeInterval = 5 * 60

    /// Recompute and persist the activated/candidate tile sets for a session.
    /// Idempotent — safe to call after track or QSO changes.
    static func recomputeTiles(
        for session: LoggingSession,
        qsos: [QSO]
    ) -> TileDetectionResult {
        let track = session.trackPoints.map { point in
            TilePathSample(
                timestamp: point.timestamp,
                latitude: point.latitude,
                longitude: point.longitude
            )
        }
        let qsoTimes = qsos.map(\.timestamp)
        let coord: (Double, Double)? = {
            guard let lat = session.activationLatitude,
                  let lon = session.activationLongitude
            else {
                return nil
            }
            return (lat, lon)
        }()

        let result = TOTATileDetector.detect(
            track: track,
            qsoTimestamps: qsoTimes,
            activationCoord: coord
        )
        session.tilesActivated = result.activated
        return result
    }

    /// Fetch spots covering the session, correlate, and persist T3 candidates.
    /// Pass an existing `TOTAClient` so callers can inject a stub in tests.
    static func refreshT3Snapshot(
        for session: LoggingSession,
        qsos: [QSO],
        client: TOTAClient
    ) async {
        guard session.activationType == .tota else {
            return
        }
        let endedAt = session.endedAt ?? Date()
        let durationHours = endedAt.timeIntervalSince(session.startedAt) / 3_600
        // Pad +6h so the correlator's preceding-spot window is fully covered.
        // Clamp to TOTA spots API max (168h) to be defensive.
        let activeHours = min(durationHours + 6, 168)

        let spots: [TOTASpot]
        do {
            spots = try await client.fetchSpots(activeHours: activeHours)
        } catch {
            // Offline / rate-limited / decode failure → leave snapshot as-is.
            return
        }

        let records = spots.compactMap { spot -> T3SpotRecord? in
            guard let createdAt = spot.createdAt else {
                return nil
            }
            return T3SpotRecord(
                callsign: spot.callSign,
                maidenheadTile: spot.maidenheadGrid,
                createdAt: createdAt
            )
        }

        let scoringQSOs = qsos.map { qso in
            TOTAScoringQSO(
                id: qso.id,
                mode: qso.mode,
                callsign: qso.callsign,
                timestamp: qso.timestamp
            )
        }

        let correlated = TOTAT3Correlator.correlate(spots: records, qsos: scoringQSOs)
        session.totaT3Candidates = correlated.map { match in
            T3Candidate(
                callsign: match.callsign,
                theirTile: match.theirTile,
                qsoId: match.qsoId,
                spotCreatedAt: match.spotCreatedAt
            )
        }
        session.totaT3SnapshotAt = Date()
    }

    /// Build the scoring inputs for a session + QSO set. Reads cached fields
    /// (`tilesActivated`, `totaT3Candidates`) — caller is responsible for
    /// having recomputed them when the session is fresh.
    static func makeScoringInputs(
        for session: LoggingSession,
        qsos: [QSO]
    ) -> TOTAScoringInputs {
        let scoringQSOs = qsos.map { qso in
            TOTAScoringQSO(
                id: qso.id,
                mode: qso.mode,
                callsign: qso.callsign,
                timestamp: qso.timestamp
            )
        }
        var t3Map: [String: String] = [:]
        for candidate in session.totaT3Candidates {
            t3Map[candidate.callsign.uppercased()] = candidate.theirTile
        }
        let isWinter = session.winterActivationOverride
            ?? TOTAWinterDetector.isWinter(
                latitude: session.activationLatitude,
                date: session.startedAt
            )
        let category: TOTACategoryKind = (session.totaCategory == .mobile) ? .mobile : .standard
        return TOTAScoringInputs(
            category: category,
            qsos: scoringQSOs,
            t3CallsignToTile: t3Map,
            distanceMiles: session.activationDistanceMiles,
            elevationGainFeet: session.activationElevationGainFeet,
            ruckWeightPounds: session.ruckWeightPounds,
            personalEffortFactor: session.personalEffortFactor,
            qrpActivation: session.qrpActivation,
            isWinter: isWinter,
            withPets: session.withPets,
            withKids: session.withKids,
            winlinkSent: session.winlinkSent,
            aprsSent: session.aprsSent,
            varacSent: session.varacSent,
            firstActivationOfTileEver: session.firstActivationOfTileEver,
            tileCount: max(session.tilesActivated.count, 1)
        )
    }

    /// Whether the cached T3 snapshot is older than the staleness threshold.
    static func t3SnapshotIsStale(_ session: LoggingSession) -> Bool {
        guard let snapshotAt = session.totaT3SnapshotAt else {
            return true
        }
        return Date().timeIntervalSince(snapshotAt) > t3RefreshStaleness
    }
}
