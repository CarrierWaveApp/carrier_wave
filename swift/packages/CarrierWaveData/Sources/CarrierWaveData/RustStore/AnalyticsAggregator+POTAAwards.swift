import CarrierWaveCore
import Foundation

// MARK: - AnalyticsAggregator + POTA awards / WAS250

/// Pure-Swift oracles for the POTA activator awards and America 250 WAS aggregates —
/// the parity counterparts to cw-store's `pota_awards` / `was250`, re-deriving the
/// math independently (the point of cross-impl parity). Mirror of `POTAAwardsActor`
/// + `POTAAwardsComputation` and `WAS250Computation`.
public extension AnalyticsAggregator {
    /// POTA activator awards over the QSOs. `parkLocationDescs` maps an uppercased
    /// park reference → its `location_desc` (the `pota_park` data the Rust path joins);
    /// state resolution uses only that cache path. The Maidenhead grid fallback the
    /// Rust path also applies is covered by cw-domain's `us_grid_state` unit tests, so
    /// parity callers supply a `location_desc` for every US/K park they exercise.
    static func potaAwards(
        over qsos: [QSO],
        parkLocationDescs: [String: String]
    ) -> POTAAwardsResult {
        // Raw park QSOs: non-hidden with a park, metadata INCLUDED (matches the actor's
        // `allSnapshots` used for the raw totals / kilo / park-to-park).
        let parkQSOs = qsos.filter { !$0.isHidden && !($0.parkReference ?? "").isEmpty }

        let parkCounts = parkQSOCounts(parkQSOs)
        let activations = groupActivations(parkQSOs)
        let valid = activations.filter { uniqueQSOCount($0) >= POTAOracleRules.minQSOs }

        let laPorta = laPortaCount(valid)
        return POTAAwardsResult(
            uniqueParksCount: uniqueParks(valid).count,
            dxEntitiesCount: dxEntities(valid).count,
            statesActivated: workedAllStates(valid, parkLocationDescs: parkLocationDescs),
            roverMaxParks: roverMax(valid),
            repeatOffenderMaxCount: repeatOffenderMax(valid),
            parkToParkCount: parkQSOs.filter { !($0.theirParkReference ?? "").isEmpty }.count,
            kiloParks: parkCounts.filter { $0.value >= POTAOracleRules.kilo }.keys.sorted(),
            nearKiloParks: nearKilo(parkCounts),
            laPortaEarned: laPorta >= POTAOracleRules.laPortaParks,
            laPortaQualifyingParks: laPorta,
            sixPackEarned: sixPack(valid),
            bestSingleParkTotal: parkCounts.values.max() ?? 0,
            totalParkQSOs: parkQSOs.count,
            metadataExcluded: parkQSOs.filter { QSOMode.isMetadata($0.mode) }.count,
            totalActivationGroups: activations.count,
            validActivationGroups: valid.count
        )
    }

    /// America 250 WAS over the QSOs (2026 window baked in, matching the Rust path).
    static func was250(over qsos: [QSO]) -> WAS250Result {
        // Non-hidden, in-window, state present (metadata included — matches the fetch).
        let fetched = qsos.filter { qso in
            guard !qso.isHidden, qso.state != nil else {
                return false
            }
            let ts = qso.timestamp.timeIntervalSince1970
            return ts >= POTAOracleRules.was250Start && ts < POTAOracleRules.was250End
        }
        var all = Set<String>()
        var cw = Set<String>()
        var phone = Set<String>()
        var digital = Set<String>()
        var metadataCount = 0
        var withState = 0
        var withValid = 0
        for qso in fetched {
            if QSOMode.isMetadata(qso.mode) {
                metadataCount += 1
                continue
            }
            withState += 1
            guard let raw = qso.state else {
                continue
            }
            let state = normalizeStateAbbreviation(raw)
            guard validUSStates.contains(state) else {
                continue
            }
            withValid += 1
            all.insert(state)
            switch modeFamilyLabel(qso.mode) {
            case "CW": cw.insert(state)
            case "Phone": phone.insert(state)
            case "Digital": digital.insert(state)
            default: break
            }
        }
        return WAS250Result(
            statesWorked: all.sorted(),
            cwStates: cw.sorted(),
            phoneStates: phone.sorted(),
            digitalStates: digital.sorted(),
            totalQSOs: fetched.count,
            metadataExcluded: metadataCount,
            withStateField: withState,
            withValidState: withValid
        )
    }

    // MARK: Private

    /// One activation group: an uppercased full park ref + UTC day + its QSOs in
    /// newest-first order (so `first` matches the Rust fetch's `qso_date DESC`).
    private struct OracleActivation {
        let parkReference: String
        let day: String
        let qsos: [QSO]
    }

    private static func groupActivations(_ parkQSOs: [QSO]) -> [OracleActivation] {
        // Newest-first, so per-group `first` (dxcc / grid) matches the Rust order.
        let nonMetadata = parkQSOs
            .filter { !QSOMode.isMetadata($0.mode) }
            .sorted { $0.timestamp > $1.timestamp }
        var order: [String] = []
        var groups: [String: [QSO]] = [:]
        for qso in nonMetadata {
            let park = (qso.parkReference ?? "").uppercased()
            let key = "\(park)|\((qso.myCallsign ?? "").uppercased())|\(dayKey(qso.timestamp))"
            if groups[key] == nil {
                order.append(key)
            }
            groups[key, default: []].append(qso)
        }
        return order.compactMap { key -> OracleActivation? in
            guard let groupQSOs = groups[key], let first = groupQSOs.first else {
                return nil
            }
            return OracleActivation(
                parkReference: (first.parkReference ?? "").uppercased(),
                day: dayKey(first.timestamp),
                qsos: groupQSOs
            )
        }
    }

    private static func uniqueQSOCount(_ activation: OracleActivation) -> Int {
        var seen = Set<String>()
        for qso in activation.qsos {
            seen.insert("\(qso.callsign.uppercased())|\(qso.band)|\(qso.mode)|\(activation.parkReference)")
        }
        return seen.count
    }

    private static func uniqueParks(_ valid: [OracleActivation]) -> Set<String> {
        var parks = Set<String>()
        for activation in valid {
            for park in ParkReference.split(activation.parkReference) {
                parks.insert(park)
            }
        }
        return parks
    }

    private static func dxEntities(_ valid: [OracleActivation]) -> Set<Int> {
        var entities = Set<Int>()
        for activation in valid {
            for qso in activation.qsos {
                if let dxcc = qso.dxcc, dxcc > 0 {
                    entities.insert(dxcc)
                    break
                }
            }
        }
        return entities
    }

    private static func workedAllStates(
        _ valid: [OracleActivation],
        parkLocationDescs: [String: String]
    ) -> [String] {
        var states = Set<String>()
        for activation in valid {
            for park in ParkReference.split(activation.parkReference) {
                for state in statesForPark(park, parkLocationDescs: parkLocationDescs) {
                    states.insert(state)
                }
            }
        }
        return states.sorted()
    }

    /// Cache-path state resolution: park found, US/K prefix, non-empty parsed states.
    private static func statesForPark(_ park: String, parkLocationDescs: [String: String]) -> [String] {
        guard isUSPrefix(park), let locationDesc = parkLocationDescs[park] else {
            return []
        }
        return locationDesc
            .split(separator: ",")
            .compactMap { segment -> String? in
                let parts = segment.trimmingCharacters(in: .whitespaces).split(separator: "-")
                guard parts.count >= 2 else {
                    return nil
                }
                return String(parts[1])
            }
            .filter { !$0.isEmpty }
    }

    private static func isUSPrefix(_ park: String) -> Bool {
        let prefix = park.split(separator: "-").first.map(String.init) ?? ""
        return prefix == "US" || prefix == "K"
    }

    private static func roverMax(_ valid: [OracleActivation]) -> Int {
        var parksByDate: [String: Set<String>] = [:]
        for activation in valid {
            for park in ParkReference.split(activation.parkReference) {
                parksByDate[activation.day, default: []].insert(park)
            }
        }
        return parksByDate.values.map(\.count).max() ?? 0
    }

    private static func repeatOffenderMax(_ valid: [OracleActivation]) -> Int {
        var countByPark: [String: Int] = [:]
        for activation in valid {
            for park in ParkReference.split(activation.parkReference) {
                countByPark[park, default: 0] += 1
            }
        }
        return countByPark.values.max() ?? 0
    }

    private static func parkQSOCounts(_ parkQSOs: [QSO]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for qso in parkQSOs {
            for park in ParkReference.split(qso.parkReference ?? "") {
                counts[park, default: 0] += 1
            }
        }
        return counts
    }

    private static func nearKilo(_ counts: [String: Int]) -> [NearKiloParkRow] {
        counts
            .filter { $0.value >= POTAOracleRules.nearKiloLower && $0.value < POTAOracleRules.kilo }
            .map { NearKiloParkRow(reference: $0.key, qsoCount: $0.value) }
            .sorted { $0.qsoCount != $1.qsoCount ? $0.qsoCount > $1.qsoCount : $0.reference < $1.reference }
    }

    private static func laPortaCount(_ valid: [OracleActivation]) -> Int {
        var bandsByPark: [String: Set<String>] = [:]
        for activation in valid {
            for park in ParkReference.split(activation.parkReference) {
                for qso in activation.qsos {
                    bandsByPark[park, default: []].insert(qso.band.uppercased())
                }
            }
        }
        return bandsByPark.values.filter { $0.count >= POTAOracleRules.laPortaBands }.count
    }

    private static func sixPack(_ valid: [OracleActivation]) -> Bool {
        var parks = Set<String>()
        for activation in valid {
            let sixMeter = activation.qsos.filter { $0.band == "6m" }.count
            guard sixMeter >= POTAOracleRules.sixPackMin6m else {
                continue
            }
            for park in ParkReference.split(activation.parkReference) {
                parks.insert(park)
            }
        }
        return parks.count >= POTAOracleRules.sixPackParks
    }
}

// MARK: - POTAOracleRules

/// Award thresholds, mirroring the Rust `pota_awards` constants + the WAS250 window.
private enum POTAOracleRules {
    static let minQSOs = 10
    static let kilo = 1_000
    static let nearKiloLower = 900
    static let laPortaBands = 10
    static let laPortaParks = 10
    static let sixPackMin6m = 10
    static let sixPackParks = 6
    /// 2026-01-01 .. 2027-01-01 UTC, unix seconds (matches cw-store `WAS250_*`).
    static let was250Start: TimeInterval = 1_767_225_600
    static let was250End: TimeInterval = 1_798_761_600
}
