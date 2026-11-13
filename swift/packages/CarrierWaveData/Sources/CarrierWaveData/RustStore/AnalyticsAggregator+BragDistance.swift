import CarrierWaveCore
import Foundation

// Oracle for the distance-shaped brag-sheet stats (`BragSheetComputationActor+Distance` /
// `+Records`). Split from AnalyticsAggregator.swift for file length. Distances use the same
// haversine as the Rust `cw_grid_distance_km` UDF (`MaidenheadConverter.distanceKm`).

public extension AnalyticsAggregator {
    /// Distance-shaped brag stats re-derived independently of the SQL for cross-impl parity.
    /// Mirrors the actor's distance/records math over visible QSOs. Each "furthest" is the
    /// max-distance contact within a filtered subset, tie-broken by callsign asc (matching the
    /// Rust `ORDER BY d DESC, callsign ASC`).
    static func bragDistanceStats(over qsos: [QSO]) -> BragDistanceStatsResult {
        let visible = visibleOnly(qsos)
        let distances = visible.compactMap(distanceKm)
        let average = distances.isEmpty ? nil : distances.reduce(0, +) / Double(distances.count)

        return BragDistanceStatsResult(
            furthest: furthest(visible) { _ in true },
            furthestQRP: furthest(visible, where: isQRP),
            furthestCW: furthest(visible) { modeFamilyLabel($0.mode) == "CW" },
            furthestCWQRP: furthest(visible) { modeFamilyLabel($0.mode) == "CW" && isQRP($0) },
            furthestPerfectRST: furthest(visible, where: isPerfectReport),
            furthestPerBand: furthestPerBand(visible),
            averageKm: average,
            lowestPower: lowestPower(visible),
            bestWattsPerMile: bestWattsPerMile(visible)
        )
    }

    // MARK: Private

    /// Great-circle distance (km) to the contacted station, or `nil` for missing/invalid
    /// grids. Haversine via `MaidenheadConverter`, matching the cw-store UDF.
    private static func distanceKm(_ qso: QSO) -> Double? {
        guard let myGrid = qso.myGrid, let theirGrid = qso.theirGrid else {
            return nil
        }
        return MaidenheadConverter.distanceKm(from: myGrid, to: theirGrid)
    }

    private static func isQRP(_ qso: QSO) -> Bool {
        guard let power = qso.power else {
            return false
        }
        return power <= 5
    }

    private static func isPerfectReport(_ qso: QSO) -> Bool {
        qso.rstReceived == "599" || qso.rstReceived == "59"
    }

    /// The max-distance contact among `qsos` matching `predicate`, tie-broken by callsign asc.
    private static func furthest(_ qsos: [QSO], where predicate: (QSO) -> Bool) -> BragContactRow? {
        let candidates = qsos.filter(predicate).compactMap { qso -> (QSO, Double)? in
            guard let km = distanceKm(qso) else {
                return nil
            }
            return (qso, km)
        }
        guard let best = candidates.max(by: lessFar) else {
            return nil
        }
        return BragContactRow(callsign: best.0.callsign, band: best.0.band, distanceKm: best.1)
    }

    /// Per-band furthest contact (lowercased band key), distance-desc then band-asc.
    private static func furthestPerBand(_ qsos: [QSO]) -> [BragBandRecordRow] {
        let candidates = qsos.compactMap { qso -> (QSO, Double)? in
            guard let km = distanceKm(qso) else {
                return nil
            }
            return (qso, km)
        }
        let byBand = Dictionary(grouping: candidates) { $0.0.band.lowercased() }
        return byBand
            .compactMap { band, group -> BragBandRecordRow? in
                guard let best = group.max(by: lessFar) else {
                    return nil
                }
                return BragBandRecordRow(band: band, callsign: best.0.callsign, distanceKm: best.1)
            }
            .sorted { $0.distanceKm != $1.distanceKm ? $0.distanceKm > $1.distanceKm : $0.band < $1.band }
    }

    private static func lowestPower(_ qsos: [QSO]) -> BragPowerContactRow? {
        let candidates = qsos.filter { ($0.power ?? 0) > 0 }
        guard let best = candidates.min(by: { lhs, rhs in
            let lhsPower = lhs.power ?? 0
            let rhsPower = rhs.power ?? 0
            return lhsPower != rhsPower ? lhsPower < rhsPower : lhs.callsign < rhs.callsign
        }) else {
            return nil
        }
        return BragPowerContactRow(
            watts: best.power ?? 0,
            callsign: best.callsign,
            band: best.band,
            distanceKm: distanceKm(best)
        )
    }

    private static func bestWattsPerMile(_ qsos: [QSO]) -> BragEfficiencyRow? {
        struct Candidate {
            let qso: QSO
            let wattsPerMile: Double
            let km: Double
        }
        let candidates = qsos.compactMap { qso -> Candidate? in
            guard let power = qso.power, power > 0, let km = distanceKm(qso), km > 0 else {
                return nil
            }
            return Candidate(qso: qso, wattsPerMile: Double(power) / (km * 0.621371), km: km)
        }
        guard let best = candidates.min(by: { lhs, rhs in
            lhs.wattsPerMile != rhs.wattsPerMile
                ? lhs.wattsPerMile < rhs.wattsPerMile
                : lhs.qso.callsign < rhs.qso.callsign
        }) else {
            return nil
        }
        return BragEfficiencyRow(
            watts: best.qso.power ?? 0,
            callsign: best.qso.callsign,
            band: best.qso.band,
            distanceKm: best.km
        )
    }

    /// Ordering for `max(by:)` so the result is the greatest distance, ties broken by the
    /// SMALLER callsign (mirrors `ORDER BY d DESC, callsign ASC LIMIT 1`). `a` is "less" than
    /// `b` when `b` should win: `b` farther, or equal distance with a smaller callsign.
    private static func lessFar(_ lhs: (QSO, Double), _ rhs: (QSO, Double)) -> Bool {
        lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0.callsign > rhs.0.callsign
    }
}
