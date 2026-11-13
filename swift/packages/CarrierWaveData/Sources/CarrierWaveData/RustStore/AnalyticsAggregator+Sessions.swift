import CarrierWaveCore
import Foundation

// Oracle methods for the park / state / equipment / brag surfaces. Split from
// AnalyticsAggregator.swift for file length; reuses its internal helpers
// (visibleOnly / dayKey / modeFamilyLabel / normalizeStateAbbreviation / validUSStates).

public extension AnalyticsAggregator {
    /// Per-park activity rollup (mirrors the SQL / `MyParksView`): activations contribute
    /// distinct UTC days per split park reference; hunts contribute raw counts;
    /// `lastWorked` is the max timestamp across both. Sorted by park.
    static func parkRollup(over qsos: [QSO]) -> [ParkRollupRow] {
        struct Acc {
            var days = Set<String>()
            var hunts = 0
            var last = Int.min
        }
        var parks: [String: Acc] = [:]
        for qso in visibleOnly(qsos) {
            let timestamp = Int(qso.timestamp.timeIntervalSince1970)
            if let park = qso.parkReference, !park.isEmpty {
                let day = dayKey(qso.timestamp)
                for ref in splitParkRefs(park) {
                    var acc = parks[ref] ?? Acc()
                    acc.days.insert(day)
                    acc.last = max(acc.last, timestamp)
                    parks[ref] = acc
                }
            }
            if let theirPark = qso.theirParkReference, !theirPark.isEmpty {
                for ref in splitParkRefs(theirPark) {
                    var acc = parks[ref] ?? Acc()
                    acc.hunts += 1
                    acc.last = max(acc.last, timestamp)
                    parks[ref] = acc
                }
            }
        }
        return parks
            .map { park, acc in
                ParkRollupRow(park: park, activationDays: acc.days.count, huntQSOs: acc.hunts, lastWorked: acc.last)
            }
            .sorted { $0.park < $1.park }
    }

    /// Per-state QSO counts over visible QSOs with a valid normalized US state. Ordered
    /// count-desc then state-asc (matches the SQL).
    static func stateCounts(over qsos: [QSO]) -> [StateCountRow] {
        var counts: [String: Int] = [:]
        for qso in visibleOnly(qsos) {
            guard let raw = qso.state else {
                continue
            }
            let state = normalizeStateAbbreviation(raw)
            guard validUSStates.contains(state) else {
                continue
            }
            counts[state, default: 0] += 1
        }
        return counts
            .map { StateCountRow(state: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.state < $1.state }
    }

    /// Equipment rollup over sessions with `qsoCount > 0` (mirrors the SQL): per
    /// (kind, name), session count, total QSOs, first/last use. Ordered session-count
    /// desc, then kind asc, name asc.
    static func sessionEquipmentRollup(over sessions: [SessionInput]) -> [SessionEquipmentRow] {
        struct EquipKey: Hashable {
            let kind: String
            let name: String
        }
        struct Acc {
            var sessions = 0
            var qsos = 0
            var first = Int.max
            var last = Int.min
        }
        var groups: [EquipKey: Acc] = [:]
        func add(_ kind: String, _ name: String?, _ session: SessionInput) {
            guard let name, !name.isEmpty else {
                return
            }
            var acc = groups[EquipKey(kind: kind, name: name)] ?? Acc()
            acc.sessions += 1
            acc.qsos += session.qsoCount
            acc.first = min(acc.first, session.startedAt)
            acc.last = max(acc.last, session.startedAt)
            groups[EquipKey(kind: kind, name: name)] = acc
        }
        for session in sessions where session.qsoCount > 0 {
            add("radio", session.myRig, session)
            add("antenna", session.myAntenna, session)
            add("key", session.myKey, session)
            add("mic", session.myMic, session)
        }
        return groups
            .map { key, acc in
                SessionEquipmentRow(
                    kind: key.kind,
                    name: key.name,
                    sessionCount: acc.sessions,
                    totalQSOs: acc.qsos,
                    firstUsed: acc.first,
                    lastUsed: acc.last
                )
            }
            .sorted {
                if $0.sessionCount != $1.sessionCount {
                    return $0.sessionCount > $1.sessionCount
                }
                return $0.kind != $1.kind ? $0.kind < $1.kind : $0.name < $1.name
            }
    }

    /// Rig+antenna combo rollup over sessions with `qsoCount > 0` and both fields set.
    static func sessionComboRollup(over sessions: [SessionInput]) -> [SessionComboRow] {
        struct ComboKey: Hashable {
            let rig: String
            let antenna: String
        }
        var groups: [ComboKey: (sessions: Int, qsos: Int)] = [:]
        for session in sessions where session.qsoCount > 0 {
            guard let rig = session.myRig, !rig.isEmpty,
                  let antenna = session.myAntenna, !antenna.isEmpty
            else {
                continue
            }
            var entry = groups[ComboKey(rig: rig, antenna: antenna)] ?? (0, 0)
            entry.sessions += 1
            entry.qsos += session.qsoCount
            groups[ComboKey(rig: rig, antenna: antenna)] = entry
        }
        return groups
            .map { key, value in
                SessionComboRow(rig: key.rig, antenna: key.antenna, sessionCount: value.sessions, totalQSOs: value.qsos)
            }
            .sorted {
                if $0.sessionCount != $1.sessionCount {
                    return $0.sessionCount > $1.sessionCount
                }
                return $0.rig != $1.rig ? $0.rig < $1.rig : $0.antenna < $1.antenna
            }
    }

    /// SQL-trivial brag-sheet period metrics over visible QSOs (mirrors the SQL subset).
    /// Multiple passes over the (period-windowed, small) set keep each metric a clear
    /// one-liner.
    static func bragPeriodMetrics(over qsos: [QSO]) -> BragPeriodMetrics {
        let visible = visibleOnly(qsos)
        let families = visible.map { modeFamilyLabel($0.mode) }
        let powers = visible.compactMap(\.power)
        return BragPeriodMetrics(
            totalQSOs: visible.count,
            cwQSOs: families.filter { $0 == "CW" }.count,
            phoneQSOs: families.filter { $0 == "Phone" }.count,
            digitalQSOs: families.filter { $0 == "Digital" }.count,
            operatingDays: Set(visible.map { dayKey($0.timestamp) }).count,
            activeBands: Set(visible.map { $0.band.lowercased() }).count,
            uniqueCallsigns: Set(visible.map { $0.callsign.uppercased() }).count,
            dxccEntities: Set(visible.compactMap(\.dxcc)).count,
            qrpQSOs: powers.filter { $0 <= 5 }.count,
            milliwattQSOs: powers.filter { $0 < 1 }.count,
            parksHunted: Set(visible.compactMap(\.theirParkReference)).count,
            parkToPark: visible.filter { isParkToPark($0) }.count,
            perfectReports: visible.filter { isPerfectReport($0) }.count
        )
    }

    /// Split a comma-separated park field into trimmed, non-empty references. Mirrors
    /// `MyParksView.splitParkRefs` and the Rust `split_refs`.
    private static func splitParkRefs(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// A park-to-park QSO: both own and contacted park references are non-empty.
    private static func isParkToPark(_ qso: QSO) -> Bool {
        guard let park = qso.parkReference, !park.isEmpty else {
            return false
        }
        guard let theirPark = qso.theirParkReference, !theirPark.isEmpty else {
            return false
        }
        return true
    }

    /// A "perfect report": RST received of "599" or "59".
    private static func isPerfectReport(_ qso: QSO) -> Bool {
        qso.rstReceived == "599" || qso.rstReceived == "59"
    }
}
