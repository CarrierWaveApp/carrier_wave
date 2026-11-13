import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - PresenceInput

/// Flattened service-presence row + its QSO's relevant fields — the oracle input for
/// `AnalyticsAggregator.servicePresenceCounts` (the SQL has the same columns via the
/// `service_presence`↔`qso` join). Keeps the oracle free of SwiftData relationships.
public struct PresenceInput: Sendable {
    // MARK: Lifecycle

    public init(
        service: String,
        isPresent: Bool,
        needsUpload: Bool,
        qsoID: String,
        qsoMyCallsign: String,
        qsoIsHidden: Bool
    ) {
        self.service = service
        self.isPresent = isPresent
        self.needsUpload = needsUpload
        self.qsoID = qsoID
        self.qsoMyCallsign = qsoMyCallsign
        self.qsoIsHidden = qsoIsHidden
    }

    // MARK: Public

    public let service: String
    public let isPresent: Bool
    public let needsUpload: Bool
    public let qsoID: String
    public let qsoMyCallsign: String
    public let qsoIsHidden: Bool
}

// MARK: - AnalyticsAggregator

/// Pure aggregation over in-memory QSOs — the math shared by the SwiftData fallback
/// and the cross-impl parity oracle. Applies the visible filter (not hidden, not a
/// metadata pseudo-mode) to match the Rust `VISIBLE_QSO` SQL. Kept free of SwiftData
/// fetching so it can run on QSO objects directly (the package test environment can
/// crash materializing the heavy QSO `@Model` via `context.fetch`).
public enum AnalyticsAggregator {
    // MARK: Public

    public static func distinctCounts(over qsos: [QSO]) -> AnalyticsCounts {
        let visible = visibleOnly(qsos)
        return AnalyticsCounts(
            qsos: visible.count,
            bands: Set(visible.map(\.band).filter { !$0.isEmpty }).count,
            grids: Set(visible.compactMap(\.theirGrid).filter { !$0.isEmpty }).count,
            entities: Set(visible.compactMap(\.dxcc).filter { $0 > 0 }).count,
            parks: Set(visible.compactMap(\.parkReference).filter { !$0.isEmpty }).count,
            confirmed: visible.filter { $0.qrzConfirmed || $0.lotwConfirmed }.count,
            qrzConfirmed: visible.filter(\.qrzConfirmed).count,
            lotwConfirmed: visible.filter(\.lotwConfirmed).count,
            withGrid: visible.filter { !($0.theirGrid ?? "").isEmpty }.count,
            withPark: visible.filter { !($0.parkReference ?? "").isEmpty }.count,
            withDXCC: visible.filter { ($0.dxcc ?? 0) > 0 }.count,
            uniqueCallsigns: Set(visible.map(\.callsign)).count
        )
    }

    public static func countBy(over qsos: [QSO], dimension: AnalyticsDimension) -> [AnalyticsBucket] {
        let visible = visibleOnly(qsos)
        switch dimension {
        case .band:
            return buckets(visible, byCountDesc: true) { $0.band.isEmpty ? nil : $0.band }
        case .modeFamily:
            return buckets(visible, byCountDesc: true) { modeFamilyLabel($0.mode) }
        case .dxcc:
            return buckets(visible, byCountDesc: true) { qso in
                guard let dxcc = qso.dxcc, dxcc > 0 else {
                    return nil
                }
                return String(dxcc)
            }
        case .month:
            return buckets(visible, byCountDesc: false) { monthKey($0.timestamp) }
        }
    }

    public static func activationRollup(over qsos: [QSO], minQSOs: Int) -> [ActivationRollupRow] {
        let parked = visibleOnly(qsos).filter { !($0.parkReference ?? "").isEmpty }
        var groups: [ActivationKey: (total: Int, unique: Set<String>)] = [:]
        for qso in parked {
            let key = ActivationKey(
                park: (qso.parkReference ?? "").uppercased(),
                operatorCallsign: (qso.myCallsign ?? "").uppercased(),
                day: dayKey(qso.timestamp)
            )
            var entry = groups[key] ?? (0, [])
            entry.total += 1
            entry.unique.insert("\(qso.callsign.uppercased())|\(qso.band)|\(qso.mode)")
            groups[key] = entry
        }
        return groups
            .map { key, value in
                ActivationRollupRow(
                    park: key.park,
                    operatorCallsign: key.operatorCallsign,
                    utcDate: key.day,
                    uniqueQSOs: value.unique.count,
                    totalQSOs: value.total,
                    successful: value.unique.count >= minQSOs
                )
            }
            .sorted {
                ($0.park, $0.utcDate, $0.operatorCallsign) < ($1.park, $1.utcDate, $1.operatorCallsign)
            }
    }

    public static func gridTiles(over qsos: [QSO], precision: Int) -> [GridTileRow] {
        var groups: [String: GridAccumulator] = [:]
        for qso in visibleOnly(qsos) {
            guard let grid = qso.theirGrid, grid.count >= precision else {
                continue
            }
            let tile = String(grid.prefix(precision)).uppercased()
            var entry = groups[tile] ?? GridAccumulator()
            entry.count += 1
            if qso.qrzConfirmed || qso.lotwConfirmed {
                entry.confirmed += 1
            }
            entry.last = max(entry.last, Int(qso.timestamp.timeIntervalSince1970))
            entry.callsigns.insert(qso.callsign)
            entry.bands.insert(qso.band)
            entry.modes.insert(qso.mode)
            groups[tile] = entry
        }
        return groups
            .map { tile, value in
                GridTileRow(
                    tile: tile,
                    count: value.count,
                    confirmed: value.confirmed,
                    lastQSO: value.last,
                    callsigns: value.callsigns.sorted(),
                    bands: value.bands.sorted(),
                    modes: value.modes.sorted()
                )
            }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tile < $1.tile }
    }

    public static func wasSummary(over qsos: [QSO]) -> WASSummary {
        var allStates = Set<String>()
        var perFamily: [String: Set<String>] = [:]
        for qso in visibleOnly(qsos) {
            guard let raw = qso.state else {
                continue
            }
            let state = normalizeStateAbbreviation(raw)
            guard validUSStates.contains(state) else {
                continue
            }
            allStates.insert(state)
            perFamily[modeFamilyLabel(qso.mode), default: []].insert(state)
        }
        let perMode = perFamily
            .map { WASModeStates(modeFamily: $0.key, states: $0.value.sorted()) }
            .sorted { $0.modeFamily < $1.modeFamily }
        return WASSummary(allStates: allStates.sorted(), perMode: perMode)
    }

    /// DXCC-worked rollup. The oracle supplies only `dxccID` + `count` (the math it
    /// can compute); `name`/`latitude`/`longitude` come from cw-domain on the Rust
    /// path, so parity tests compare id+count and assert location separately — the
    /// same split used for `countBy(.dxcc)` labels.
    public static func dxccWorked(over qsos: [QSO]) -> [DXCCWorkedRow] {
        var counts: [Int: Int] = [:]
        var bandsByDxcc: [Int: Set<String>] = [:]
        for qso in visibleOnly(qsos) {
            guard let dxcc = qso.dxcc, dxcc > 0 else {
                continue
            }
            counts[dxcc, default: 0] += 1
            bandsByDxcc[dxcc, default: []].insert(qso.band)
        }
        return counts
            .map {
                DXCCWorkedRow(
                    dxccID: $0.key,
                    name: String($0.key),
                    latitude: 0,
                    longitude: 0,
                    count: $0.value,
                    bands: (bandsByDxcc[$0.key] ?? []).sorted()
                )
            }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.dxccID < $1.dxccID }
    }

    /// Per-service uploaded/pending unique-QSO counts (mirrors the SQL): over presences
    /// whose QSO is not hidden, `uploaded` dedupes present rows by QSO; `pending` dedupes
    /// `needs_upload` rows for configured services, restricted (when `primaryCallsign` is
    /// set) to QSOs whose callsign is empty or matches. One row per service that has any
    /// non-hidden presence, sorted by service.
    public static func servicePresenceCounts(
        over presences: [PresenceInput],
        primaryCallsign: String?,
        configuredServices: Set<String>
    ) -> [ServicePresenceCountRow] {
        let upperPrimary = primaryCallsign?.uppercased()
        var services = Set<String>()
        var uploaded: [String: Set<String>] = [:]
        var pending: [String: Set<String>] = [:]
        for presence in presences where !presence.qsoIsHidden {
            services.insert(presence.service)
            if presence.isPresent {
                uploaded[presence.service, default: []].insert(presence.qsoID)
            }
            if presence.needsUpload, configuredServices.contains(presence.service) {
                let callsign = presence.qsoMyCallsign.uppercased()
                let matches = callsign.isEmpty || upperPrimary == nil || callsign == upperPrimary
                if matches {
                    pending[presence.service, default: []].insert(presence.qsoID)
                }
            }
        }
        return services.sorted().map { service in
            ServicePresenceCountRow(
                service: service,
                uploaded: uploaded[service]?.count ?? 0,
                pending: pending[service]?.count ?? 0
            )
        }
    }

    // MARK: Internal

    /// The 50 WAS states. Mirrors `POTAAwardsActor.validStates` (kept here so the
    /// package-level oracle does not depend on the app target). Internal so the
    /// session/park/brag oracle extension can reuse it.
    static let validUSStates: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "ID", "IL", "IN", "IA",
        "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT",
        "VA", "WA", "WV", "WI", "WY",
    ]

    /// Normalize a stored state value to a WAS abbreviation: take the text before
    /// " // " (LoFi comment suffix), uppercase, trim whitespace. Mirrors
    /// `USStates.normalizeAbbreviation` and the SQL `NORMALIZED_STATE`.
    static func normalizeStateAbbreviation(_ raw: String) -> String {
        let trimmed = if let slash = raw.range(of: " // ") {
            String(raw[raw.startIndex ..< slash.lowerBound])
        } else {
            raw
        }
        return trimmed.uppercased().trimmingCharacters(in: .whitespaces)
    }

    static func visibleOnly(_ qsos: [QSO]) -> [QSO] {
        qsos.filter { !$0.isHidden && !QSOMode.isMetadata($0.mode) }
    }

    static func modeFamilyLabel(_ mode: String) -> String {
        switch ModeEquivalence.family(for: mode) {
        case .phone: "Phone"
        case .cw: "CW"
        case .digital: "Digital"
        case .other: "Other"
        }
    }

    static func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    // MARK: Private

    private struct GridAccumulator {
        var count = 0
        var confirmed = 0
        var last = Int.min
        var callsigns: Set<String> = []
        var bands: Set<String> = []
        var modes: Set<String> = []
    }

    private struct ActivationKey: Hashable {
        let park: String
        let operatorCallsign: String
        let day: String
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    /// Group by `keyFor` (skipping nil keys); label == key. `byCountDesc` orders by
    /// count desc then key asc; otherwise key asc (months). Matches the Rust
    /// `ORDER BY COUNT(*) DESC, k ASC` / `ORDER BY k ASC`.
    private static func buckets(
        _ visible: [QSO],
        byCountDesc: Bool,
        keyFor: (QSO) -> String?
    ) -> [AnalyticsBucket] {
        var groups: [String: (count: Int, calls: Set<String>)] = [:]
        for qso in visible {
            guard let key = keyFor(qso) else {
                continue
            }
            var entry = groups[key] ?? (0, [])
            entry.count += 1
            entry.calls.insert(qso.callsign)
            groups[key] = entry
        }
        let rows = groups.map { key, value in
            AnalyticsBucket(key: key, label: key, count: value.count, distinctCalls: value.calls.count)
        }
        if byCountDesc {
            return rows.sorted { $0.count != $1.count ? $0.count > $1.count : $0.key < $1.key }
        }
        return rows.sorted { $0.key < $1.key }
    }

    private static func monthKey(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }
}

// A SwiftData-backed `AnalyticsReadSource` (the `off`-mode fallback) is intentionally
// not provided here: aggregating over SwiftData must batch (≤1000 rows/fetch, per
// PERFORMANCE.md) rather than load the whole table, and that batched fallback is
// added when an app-target actor is actually routed to `AnalyticsReadSource`. Until
// then `RustAnalyticsReadSource` is the only conformer, and `AnalyticsAggregator` is
// the pure oracle used for cross-impl parity.
