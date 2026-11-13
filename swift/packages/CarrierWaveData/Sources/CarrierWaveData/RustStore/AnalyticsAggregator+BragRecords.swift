import CarrierWaveCore
import Foundation

// Oracle for the SQL-expressible volume / records / "fun" brag-sheet stats
// (`BragSheetComputationActor`'s volume + fun + misc-totals set). Split from
// AnalyticsAggregator.swift for file length. Day-bucketing is UTC; distances use the same
// haversine as the cw-store UDF.

public extension AnalyticsAggregator {
    /// Records stats re-derived independently of the SQL for cross-impl parity. Tie-breaks
    /// match the Rust `ORDER BY count DESC, key ASC` (the production actor's dictionary order is
    /// nondeterministic; parity is oracle == Rust).
    static func bragRecords(over qsos: [QSO]) -> BragRecordsResult {
        let visible = visibleOnly(qsos)
        let calendar = utcCalendar
        return BragRecordsResult(
            mostQSOsDay: maxGroupCount(visible) { calendar.startOfDay(for: $0.timestamp) },
            mostQSOsSession: maxGroupCount(visible) { ($0.loggingSessionId ?? $0.id).uuidString },
            mostCountriesDay: maxDistinctPerDay(visible, calendar) { $0.dxcc.map(String.init) },
            mostBandsDay: maxDistinctPerDay(visible, calendar) { $0.band.lowercased() },
            mostActiveWeekday: mostActiveWeekday(visible, calendar),
            busiestBand: bestTally(visible) { $0.band.lowercased() },
            busiestMode: bestTally(visible) { ModeEquivalence.canonicalName($0.mode) },
            repeatCustomer: repeatCustomer(visible),
            earliestQSO: extremeByTimeOfDay(visible, earliest: true),
            latestQSO: extremeByTimeOfDay(visible, earliest: false),
            totalDistanceKm: totalDistance(visible),
            activeModes: Set(visible.map { ModeEquivalence.canonicalName($0.mode) }).count
        )
    }

    // MARK: Private

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func maxGroupCount(_ qsos: [QSO], key: (QSO) -> some Hashable) -> Int {
        Dictionary(grouping: qsos, by: key).values.map(\.count).max() ?? 0
    }

    private static func maxDistinctPerDay(_ qsos: [QSO], _ calendar: Calendar, value: (QSO) -> String?) -> Int {
        let byDay = Dictionary(grouping: qsos) { calendar.startOfDay(for: $0.timestamp) }
        return byDay.values.map { Set($0.compactMap(value)).count }.max() ?? 0
    }

    private static func mostActiveWeekday(_ qsos: [QSO], _ calendar: Calendar) -> ItemTallyRow? {
        var counts: [Int: Int] = [:]
        for qso in qsos {
            counts[calendar.component(.weekday, from: qso.timestamp), default: 0] += 1
        }
        guard let best = counts.min(by: tieByCountThenKey) else {
            return nil
        }
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let name = best.key < names.count ? names[best.key] : "?"
        return ItemTallyRow(name: name, count: best.value)
    }

    private static func bestTally(_ qsos: [QSO], key: (QSO) -> String) -> ItemTallyRow? {
        var counts: [String: Int] = [:]
        for qso in qsos {
            counts[key(qso), default: 0] += 1
        }
        return topTally(counts)
    }

    private static func repeatCustomer(_ qsos: [QSO]) -> ItemTallyRow? {
        var counts: [String: Int] = [:]
        for qso in qsos {
            counts[qso.callsign.uppercased(), default: 0] += 1
        }
        return topTally(counts.filter { $0.value > 1 })
    }

    private static func topTally(_ counts: [some Hashable & Comparable: Int]) -> ItemTallyRow? {
        guard let best = counts.min(by: tieByCountThenKey) else {
            return nil
        }
        return ItemTallyRow(name: "\(best.key)", count: best.value)
    }

    /// Order dictionary `(key, count)` pairs count-desc then key-asc (the Rust ORDER BY).
    private static func tieByCountThenKey<Key: Comparable>(
        _ lhs: (key: Key, value: Int),
        _ rhs: (key: Key, value: Int)
    ) -> Bool {
        lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
    }

    private static func extremeByTimeOfDay(_ qsos: [QSO], earliest: Bool) -> Int? {
        let entries = qsos.map { qso -> (ts: Int, tod: Int) in
            let ts = Int(qso.timestamp.timeIntervalSince1970)
            return (ts, ((ts % 86_400) + 86_400) % 86_400)
        }
        let lessByTimeOfDay: ((ts: Int, tod: Int), (ts: Int, tod: Int)) -> Bool = { lhs, rhs in
            lhs.tod != rhs.tod ? lhs.tod < rhs.tod : lhs.ts < rhs.ts
        }
        return earliest ? entries.min(by: lessByTimeOfDay)?.ts : entries.max(by: lessByTimeOfDay)?.ts
    }

    private static func totalDistance(_ qsos: [QSO]) -> Double? {
        let sum = qsos.compactMap(recordDistanceKm).reduce(0, +)
        return sum > 0 ? sum : nil
    }

    private static func recordDistanceKm(_ qso: QSO) -> Double? {
        guard let myGrid = qso.myGrid, let theirGrid = qso.theirGrid else {
            return nil
        }
        return MaidenheadConverter.distanceKm(from: myGrid, to: theirGrid)
    }
}
