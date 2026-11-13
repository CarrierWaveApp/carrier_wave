import CarrierWaveCore
import Foundation

// Oracle for the per-equipment-item QSO breakdown (`EquipmentItemDetailActor.computeQSOStats`).
// Split from AnalyticsAggregator.swift for file length.

public extension AnalyticsAggregator {
    /// Per-item QSO breakdown for the item named `name`, re-derived independently of the SQL
    /// for cross-impl parity. Mirrors `EquipmentItemDetailActor`: a session matches when it
    /// has QSOs (`qsoCount > 0`) and uses `name` as rig / antenna / key / mic (exact,
    /// case-sensitive); the item's QSOs are those sessions' QSOs that are not a metadata
    /// pseudo-mode. Unlike the other oracles this does NOT drop hidden QSOs — the consumer
    /// only excludes metadata when tallying snapshots. Distances use the same haversine as the
    /// Rust `cw_grid_distance_km` UDF (`MaidenheadConverter.distanceKm`), counting only QSOs
    /// with two parseable grids and a positive distance.
    static func sessionItemDetail(
        name: String,
        over qsos: [QSO],
        sessions: [SessionItemInput]
    ) -> SessionItemDetailResult {
        let matchingIDs = Set(
            sessions
                .filter { session in
                    session.qsoCount > 0
                        && [session.myRig, session.myAntenna, session.myKey, session.myMic]
                        .contains { $0 == name }
                }
                .map(\.id)
        )
        let relevant = qsos.filter { qso in
            guard let sessionID = qso.loggingSessionId, matchingIDs.contains(sessionID) else {
                return false
            }
            return !QSOMode.isMetadata(qso.mode)
        }

        let entities = Set(relevant.compactMap { qso -> Int? in
            guard let dxcc = qso.dxcc, dxcc > 0 else {
                return nil
            }
            return dxcc
        }).count

        let distances = relevant.compactMap { qso -> Double? in
            guard let myGrid = qso.myGrid, let theirGrid = qso.theirGrid,
                  let km = MaidenheadConverter.distanceKm(from: myGrid, to: theirGrid), km > 0
            else {
                return nil
            }
            return km
        }
        let average = distances.isEmpty ? nil : distances.reduce(0, +) / Double(distances.count)

        return SessionItemDetailResult(
            totalQSOs: relevant.count,
            uniqueEntities: entities,
            farthestKm: distances.max(),
            shortestKm: distances.min(),
            averageKm: average,
            bandBreakdown: tally(relevant.map(\.band)),
            modeBreakdown: tally(relevant.map(\.mode))
        )
    }

    /// Count raw values into `ItemTallyRow`s, sorted count-desc then name-asc (matches the SQL
    /// `GROUP BY … ORDER BY COUNT(*) DESC, k ASC`).
    private static func tally(_ values: [String]) -> [ItemTallyRow] {
        var counts: [String: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }
        return counts
            .map { ItemTallyRow(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }
}
