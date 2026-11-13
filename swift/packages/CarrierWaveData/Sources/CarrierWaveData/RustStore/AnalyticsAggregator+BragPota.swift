import CarrierWaveCore
import Foundation

// Oracle for the POTA-category brag-sheet stats (`BragSheetComputationActor+POTA`). Split from
// AnalyticsAggregator.swift for file length. Re-derives the stats from `[QSO]` independently of
// the SQL so the cross-impl parity harness can assert oracle == Rust.

public extension AnalyticsAggregator {
    /// POTA stats re-derived independently of the SQL for cross-impl parity. `qsos` is the period
    /// set; `allQSOs` is the all-time log (only `newParks` consults it). Mirrors the actor's
    /// `computeParksActivated` / `computeParksHunted` / `computeP2P` / `computeBestActivation` /
    /// `computeNewParks` math, with day grouping normalized to UTC.
    static func bragPota(over qsos: [QSO], allQSOs: [QSO]) -> BragPotaResult {
        let visible = visibleOnly(qsos)
        return BragPotaResult(
            parksActivated: parksActivated(visible),
            parksHunted: distinctHuntedParks(visible).count,
            parkToPark: parkToPark(visible),
            bestActivation: bestActivation(visible),
            newParks: newParks(period: visible, all: visibleOnly(allQSOs))
        )
    }

    // MARK: Private

    private static var utcDayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Non-empty `parkReference`s with their QSOs.
    private static func parkedQSOs(_ qsos: [QSO]) -> [QSO] {
        qsos.filter { ($0.parkReference?.isEmpty == false) }
    }

    /// Activation groups keyed by `rawPark|utcStartOfDay` (mirrors `activationGroups`).
    private static func activationGroups(_ qsos: [QSO]) -> [String: [QSO]] {
        let calendar = utcDayCalendar
        return Dictionary(grouping: parkedQSOs(qsos)) { qso in
            let park = qso.parkReference ?? ""
            let day = calendar.startOfDay(for: qso.timestamp).timeIntervalSince1970
            return "\(park)|\(day)"
        }
    }

    /// Count of unique QSOs in a group (dedupe by `UPPER(call)|band|mode|UPPER(park)`).
    private static func uniqueQSOCount(_ qsos: [QSO]) -> Int {
        var seen = Set<String>()
        for qso in qsos {
            let park = (qso.parkReference ?? "").uppercased()
            seen.insert("\(qso.callsign.uppercased())|\(qso.band)|\(qso.mode)|\(park)")
        }
        return seen.count
    }

    /// Distinct parks whose (park, UTC-day) group has ≥ 10 unique QSOs (`computeParksActivated`).
    private static func parksActivated(_ qsos: [QSO]) -> Int {
        let successful = activationGroups(qsos).values.filter { uniqueQSOCount($0) >= 10 }
        return Set(successful.compactMap { $0.first?.parkReference }).count
    }

    /// Distinct non-empty raw their-park references (`computeParksHunted`).
    private static func distinctHuntedParks(_ qsos: [QSO]) -> Set<String> {
        Set(qsos.compactMap(\.theirParkReference).filter { !$0.isEmpty })
    }

    /// QSOs with both a non-empty park and their-park (`computeP2P`).
    private static func parkToPark(_ qsos: [QSO]) -> Int {
        qsos.filter {
            ($0.parkReference?.isEmpty == false) && ($0.theirParkReference?.isEmpty == false)
        }.count
    }

    /// The (park, UTC-day) activation group with the most raw QSOs (`computeBestActivation`).
    /// Deterministic tie-break: count DESC, park ASC, day ASC (so it matches the Rust ORDER BY).
    private static func bestActivation(_ qsos: [QSO]) -> BragBestActivationRow? {
        let calendar = utcDayCalendar
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let rows = activationGroups(qsos).values.compactMap { group -> BragBestActivationRow? in
            guard let first = group.first, let park = first.parkReference else {
                return nil
            }
            let day = formatter.string(from: calendar.startOfDay(for: first.timestamp))
            return BragBestActivationRow(park: park, day: day, count: group.count)
        }
        return rows.max { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count < rhs.count
            }
            if lhs.park != rhs.park {
                return lhs.park > rhs.park
            }
            return lhs.day > rhs.day
        }
    }

    /// Parks (activated ∪ hunted) in the period whose all-time-earliest contact (on either column)
    /// is at/after the period's earliest QSO (`computeNewParks`).
    private static func newParks(period: [QSO], all: [QSO]) -> Int {
        guard let periodStart = period.map(\.timestamp).min() else {
            return 0
        }
        let periodParks = Set(period.compactMap(\.parkReference).filter { !$0.isEmpty })
        let periodAll = periodParks.union(distinctHuntedParks(period))

        var count = 0
        for park in periodAll {
            let forPark = all.filter { $0.parkReference == park || $0.theirParkReference == park }
            guard let earliest = forPark.map(\.timestamp).min() else {
                continue
            }
            if earliest >= periodStart {
                count += 1
            }
        }
        return count
    }
}
