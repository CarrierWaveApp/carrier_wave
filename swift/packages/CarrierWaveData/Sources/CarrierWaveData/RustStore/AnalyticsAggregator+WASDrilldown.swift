import CarrierWaveCore
import Foundation

// MARK: - AnalyticsAggregator + WAS drilldown

/// Pure-Swift oracle for the WAS drilldown — the parity counterpart to cw-store's
/// `was_drilldown`, mirroring `StatsComputationActor`'s `wasData` accumulation. Each
/// visible, valid-state QSO contributes to its `(all, mode)` and `(all, nil)` buckets,
/// and—when not at a park—its `(qth, mode)` and `(qth, nil)` buckets.
public extension AnalyticsAggregator {
    static func wasDrilldown(over qsos: [QSO]) -> [WASDrilldownRow] {
        // Key: source + mode (nil = all modes) + state → count + distinct callsigns.
        var acc: [DrilldownKey: (count: Int, callsigns: Set<String>)] = [:]

        func bump(_ source: String, _ mode: String?, _ state: String, _ call: String) {
            let key = DrilldownKey(source: source, mode: mode, state: state)
            var entry = acc[key] ?? (0, [])
            entry.count += 1
            entry.callsigns.insert(call)
            acc[key] = entry
        }

        for qso in visibleOnly(qsos) {
            guard let raw = qso.state, !raw.isEmpty else {
                continue
            }
            let state = normalizeStateAbbreviation(raw)
            guard validUSStates.contains(state) else {
                continue
            }
            let call = qso.callsign.uppercased()
            let mode = qso.mode.uppercased()
            bump("all", nil, state, call)
            bump("all", mode, state, call)
            if (qso.parkReference ?? "").isEmpty {
                bump("qth", nil, state, call)
                bump("qth", mode, state, call)
            }
        }

        return acc
            .map { key, value in
                WASDrilldownRow(
                    source: key.source,
                    mode: key.mode,
                    state: key.state,
                    count: value.count,
                    callsigns: value.callsigns.sorted()
                )
            }
            .sorted(by: drilldownOrder)
    }

    // MARK: Private

    private struct DrilldownKey: Hashable {
        let source: String
        let mode: String?
        let state: String
    }

    /// Canonical order matching the Rust `BTreeMap<(source, Option<mode>, state)>`:
    /// source ascending, then nil-mode rows before named modes, then mode/state ascending.
    private static func drilldownOrder(_ lhs: WASDrilldownRow, _ rhs: WASDrilldownRow) -> Bool {
        if lhs.source != rhs.source {
            return lhs.source < rhs.source
        }
        switch (lhs.mode, rhs.mode) {
        case (nil, nil):
            break
        case (nil, _):
            return true
        case (_, nil):
            return false
        case let (left?, right?):
            if left != right {
                return left < right
            }
        }
        return lhs.state < rhs.state
    }
}
