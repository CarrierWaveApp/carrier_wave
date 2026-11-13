import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - AnalyticsCounts

/// Headline distinct counts for the stats dashboard (mirrors cw-store
/// `DistinctCounts`). Distinctness is case-sensitive on the raw stored value.
public struct AnalyticsCounts: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        qsos: Int,
        bands: Int,
        grids: Int,
        entities: Int,
        parks: Int,
        confirmed: Int,
        qrzConfirmed: Int = 0,
        lotwConfirmed: Int = 0,
        withGrid: Int = 0,
        withPark: Int = 0,
        withDXCC: Int = 0,
        uniqueCallsigns: Int = 0
    ) {
        self.qsos = qsos
        self.bands = bands
        self.grids = grids
        self.entities = entities
        self.parks = parks
        self.confirmed = confirmed
        self.qrzConfirmed = qrzConfirmed
        self.lotwConfirmed = lotwConfirmed
        self.withGrid = withGrid
        self.withPark = withPark
        self.withDXCC = withDXCC
        self.uniqueCallsigns = uniqueCallsigns
    }

    // MARK: Public

    public let qsos: Int
    public let bands: Int
    public let grids: Int
    public let entities: Int
    public let parks: Int
    public let confirmed: Int
    /// QSOs confirmed on QRZ (`StatsComputationActor.qrzConfirmedCount`).
    public let qrzConfirmed: Int
    /// QSOs confirmed on LoTW (`lotwConfirmedCount`).
    public let lotwConfirmed: Int
    /// QSOs with a non-empty their-grid (`qsosWithGrid`).
    public let withGrid: Int
    /// QSOs with a non-empty park (`qsosWithParkRef`).
    public let withPark: Int
    /// QSOs with a valid dxcc > 0 (`qsosWithDXCC`).
    public let withDXCC: Int
    /// Distinct raw callsigns worked (`uniqueCallsignCount`).
    public let uniqueCallsigns: Int
}

// MARK: - AnalyticsBucket

/// A grouped count row (mirrors cw-store `DimensionCount`).
public struct AnalyticsBucket: Equatable, Sendable {
    // MARK: Lifecycle

    public init(key: String, label: String, count: Int, distinctCalls: Int) {
        self.key = key
        self.label = label
        self.count = count
        self.distinctCalls = distinctCalls
    }

    // MARK: Public

    public let key: String
    public let label: String
    public let count: Int
    public let distinctCalls: Int
}

// MARK: - ActivationRollupRow

/// One POTA activation: a (park, operator, UTC-date) group with unique/total QSO
/// counts (mirrors cw-store `ActivationRollup`). `park`/`operatorCallsign` are
/// uppercased to match `POTAAwardsActor`'s group key.
public struct ActivationRollupRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        park: String,
        operatorCallsign: String,
        utcDate: String,
        uniqueQSOs: Int,
        totalQSOs: Int,
        successful: Bool
    ) {
        self.park = park
        self.operatorCallsign = operatorCallsign
        self.utcDate = utcDate
        self.uniqueQSOs = uniqueQSOs
        self.totalQSOs = totalQSOs
        self.successful = successful
    }

    // MARK: Public

    public let park: String
    public let operatorCallsign: String
    public let utcDate: String
    public let uniqueQSOs: Int
    public let totalQSOs: Int
    public let successful: Bool
}

// MARK: - GridTileRow

/// One worked Maidenhead grid tile (mirrors cw-store `GridTile`). `lastQSO` is unix
/// seconds (UTC) of the most recent QSO in the tile.
public struct GridTileRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        tile: String,
        count: Int,
        confirmed: Int,
        lastQSO: Int,
        callsigns: [String] = [],
        bands: [String] = [],
        modes: [String] = []
    ) {
        self.tile = tile
        self.count = count
        self.confirmed = confirmed
        self.lastQSO = lastQSO
        self.callsigns = callsigns
        self.bands = bands
        self.modes = modes
    }

    // MARK: Public

    public let tile: String
    public let count: Int
    public let confirmed: Int
    public let lastQSO: Int
    /// Distinct raw callsigns in the tile, sorted ascending.
    public let callsigns: [String]
    /// Distinct raw bands in the tile, sorted ascending.
    public let bands: [String]
    /// Distinct raw modes in the tile, sorted ascending.
    public let modes: [String]
}

// MARK: - WASModeStates

/// The valid US states worked on one mode family (mirrors cw-store `WasModeStates`).
public struct WASModeStates: Equatable, Sendable {
    // MARK: Lifecycle

    public init(modeFamily: String, states: [String]) {
        self.modeFamily = modeFamily
        self.states = states
    }

    // MARK: Public

    public let modeFamily: String
    public let states: [String]
}

// MARK: - WASSummary

/// WAS (Worked All States) rollup (mirrors cw-store `WasSummary`): valid US states
/// worked overall and per mode family. Sorted ascending; per-mode family-sorted.
public struct WASSummary: Equatable, Sendable {
    // MARK: Lifecycle

    public init(allStates: [String], perMode: [WASModeStates]) {
        self.allStates = allStates
        self.perMode = perMode
    }

    // MARK: Public

    public let allStates: [String]
    public let perMode: [WASModeStates]
}

// MARK: - DXCCWorkedRow

/// One worked DXCC entity with location and QSO count (mirrors cw-store
/// `DxccWorked`). `name`/`latitude`/`longitude` come from cw-domain's country table.
public struct DXCCWorkedRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        dxccID: Int,
        name: String,
        latitude: Double,
        longitude: Double,
        count: Int,
        bands: [String] = []
    ) {
        self.dxccID = dxccID
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.count = count
        self.bands = bands
    }

    // MARK: Public

    public let dxccID: Int
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let count: Int
    /// Distinct raw bands worked for this entity, sorted ascending.
    public let bands: [String]
}

// MARK: - ServicePresenceCountRow

/// Per-service uploaded/pending unique-QSO counts (mirrors cw-store
/// `ServicePresenceCount`). `service` is the `ServiceType` raw value.
public struct ServicePresenceCountRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(service: String, uploaded: Int, pending: Int) {
        self.service = service
        self.uploaded = uploaded
        self.pending = pending
    }

    // MARK: Public

    public let service: String
    public let uploaded: Int
    public let pending: Int
}

// MARK: - AnalyticsDimension

/// Dimension to group `countBy` on (mirrors cw-store `AggregateDimension`).
public enum AnalyticsDimension: Sendable {
    case band
    case modeFamily
    case dxcc
    case month
}

// MARK: - AnalyticsReadSource

/// Serves dashboard / award / map aggregations. `RustAnalyticsReadSource` runs SQL
/// `GROUP BY` in cw-store; `AnalyticsAggregator` is the pure-Swift oracle (and the
/// math a future batched SwiftData fallback would reuse). Selected by `CwStoreQSOMode`
/// like the list reads. `query` is an optional `.cwquery` DSL filter; the cross-impl
/// parity harness uses an empty query, which both paths treat as "all visible".
public protocol AnalyticsReadSource: Sendable {
    func distinctCounts(query: String) async throws -> AnalyticsCounts
    func countBy(query: String, dimension: AnalyticsDimension) async throws -> [AnalyticsBucket]
    func activationRollup(query: String, minQSOs: Int) async throws -> [ActivationRollupRow]
    func gridTiles(query: String, precision: Int) async throws -> [GridTileRow]
    func wasSummary(query: String) async throws -> WASSummary
    func potaAwards(query: String) async throws -> POTAAwardsResult
    func was250(query: String) async throws -> WAS250Result
    func wasDrilldown(query: String) async throws -> [WASDrilldownRow]
    func dxccWorked(query: String) async throws -> [DXCCWorkedRow]
    func servicePresenceCounts(
        query: String,
        primaryCallsign: String?,
        configuredServices: [String]
    ) async throws -> [ServicePresenceCountRow]
    func parkRollup(query: String) async throws -> [ParkRollupRow]
    func stateCounts(query: String) async throws -> [StateCountRow]
    func sessionEquipmentRollup() async throws -> [SessionEquipmentRow]
    func sessionComboRollup() async throws -> [SessionComboRow]
    func sessionItemDetail(name: String) async throws -> SessionItemDetailResult
    // The brag-sheet aggregates take an inclusive `[start, end]` unix-second window (the period;
    // `nil`/`nil` = all-time). The concrete `RustAnalyticsReadSource` defaults them to `nil` so
    // existing call sites (parity tests) need no change.
    func bragPeriodMetrics(query: String, start: Int?, end: Int?) async throws -> BragPeriodMetrics
    func bragDistanceStats(query: String, start: Int?, end: Int?) async throws -> BragDistanceStatsResult
    func bragStreaks(query: String, today: String, start: Int?, end: Int?) async throws -> BragStreaksResult
    func bragGeographic(query: String, start: Int?, end: Int?) async throws -> BragGeographicResult
    func bragPota(query: String, start: Int?, end: Int?) async throws -> BragPotaResult
    func bragRecords(query: String, start: Int?, end: Int?) async throws -> BragRecordsResult
    func bragSessionStats(query: String, start: Int?, end: Int?) async throws -> BragSessionStatsResult
    func bragAverageRST(query: String, start: Int?, end: Int?) async throws -> Double?
    func workedMemberCallsigns(
        query: String,
        members: [String],
        start: Int?,
        end: Int?
    ) async throws -> [String]
}

// MARK: - RustAnalyticsReadSource

/// Aggregations served from a `FieldStore` (Rust cw-store, SQL `GROUP BY`).
public struct RustAnalyticsReadSource: AnalyticsReadSource {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        self.store = store
    }

    // MARK: Public

    public func distinctCounts(query: String) async throws -> AnalyticsCounts {
        let counts = try store.qsoDistinctCounts(query: query)
        return AnalyticsCounts(
            qsos: Int(counts.qsos),
            bands: Int(counts.bands),
            grids: Int(counts.grids),
            entities: Int(counts.entities),
            parks: Int(counts.parks),
            confirmed: Int(counts.confirmed),
            qrzConfirmed: Int(counts.qrzConfirmed),
            lotwConfirmed: Int(counts.lotwConfirmed),
            withGrid: Int(counts.withGrid),
            withPark: Int(counts.withPark),
            withDXCC: Int(counts.withDxcc),
            uniqueCallsigns: Int(counts.uniqueCallsigns)
        )
    }

    public func countBy(query: String, dimension: AnalyticsDimension) async throws -> [AnalyticsBucket] {
        try store.qsoCountBy(query: query, dimension: dimension.ffi)
            .map {
                AnalyticsBucket(
                    key: $0.key,
                    label: $0.label,
                    count: Int($0.count),
                    distinctCalls: Int($0.distinctCalls)
                )
            }
    }

    public func activationRollup(query: String, minQSOs: Int) async throws -> [ActivationRollupRow] {
        try store.qsoActivationRollup(query: query, minQsos: Int64(minQSOs))
            .map {
                ActivationRollupRow(
                    park: $0.park,
                    operatorCallsign: $0.operatorCallsign,
                    utcDate: $0.utcDate,
                    uniqueQSOs: Int($0.uniqueQsos),
                    totalQSOs: Int($0.totalQsos),
                    successful: $0.successful
                )
            }
    }

    public func gridTiles(query: String, precision: Int) async throws -> [GridTileRow] {
        try store.qsoGridTiles(query: query, precision: Int64(precision))
            .map {
                GridTileRow(
                    tile: $0.tile,
                    count: Int($0.count),
                    confirmed: Int($0.confirmed),
                    lastQSO: Int($0.lastQso),
                    callsigns: $0.callsigns,
                    bands: $0.bands,
                    modes: $0.modes
                )
            }
    }

    public func wasSummary(query: String) async throws -> WASSummary {
        let summary = try store.wasSummary(query: query)
        return WASSummary(
            allStates: summary.allStates,
            perMode: summary.perMode.map { WASModeStates(modeFamily: $0.modeFamily, states: $0.states) }
        )
    }

    public func dxccWorked(query: String) async throws -> [DXCCWorkedRow] {
        try store.dxccWorked(query: query)
            .map {
                DXCCWorkedRow(
                    dxccID: Int($0.dxccId),
                    name: $0.name,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    count: Int($0.count),
                    bands: $0.bands
                )
            }
    }

    public func servicePresenceCounts(
        query: String,
        primaryCallsign: String?,
        configuredServices: [String]
    ) async throws -> [ServicePresenceCountRow] {
        try store.servicePresenceCounts(
            query: query,
            primaryCallsign: primaryCallsign,
            configuredServices: configuredServices
        )
        .map { ServicePresenceCountRow(service: $0.service, uploaded: Int($0.uploaded), pending: Int($0.pending)) }
    }

    public func parkRollup(query: String) async throws -> [ParkRollupRow] {
        try store.qsoParkRollup(query: query)
            .map {
                ParkRollupRow(
                    park: $0.park,
                    activationDays: Int($0.activationDays),
                    huntQSOs: Int($0.huntQsos),
                    lastWorked: Int($0.lastWorked)
                )
            }
    }

    public func stateCounts(query: String) async throws -> [StateCountRow] {
        try store.qsoStateCounts(query: query)
            .map { StateCountRow(state: $0.state, count: Int($0.count)) }
    }

    public func sessionEquipmentRollup() async throws -> [SessionEquipmentRow] {
        try store.sessionEquipmentRollup()
            .map {
                SessionEquipmentRow(
                    kind: $0.kind,
                    name: $0.name,
                    sessionCount: Int($0.sessionCount),
                    totalQSOs: Int($0.totalQsos),
                    firstUsed: Int($0.firstUsed),
                    lastUsed: Int($0.lastUsed)
                )
            }
    }

    public func sessionComboRollup() async throws -> [SessionComboRow] {
        try store.sessionComboRollup()
            .map {
                SessionComboRow(
                    rig: $0.rig,
                    antenna: $0.antenna,
                    sessionCount: Int($0.sessionCount),
                    totalQSOs: Int($0.totalQsos)
                )
            }
    }

    public func bragPeriodMetrics(query: String, start: Int? = nil, end: Int? = nil) async throws -> BragPeriodMetrics {
        let metrics = try store.bragPeriodMetrics(query: query, start: start.map(Int64.init), end: end.map(Int64.init))
        return BragPeriodMetrics(
            totalQSOs: Int(metrics.totalQsos),
            cwQSOs: Int(metrics.cwQsos),
            phoneQSOs: Int(metrics.phoneQsos),
            digitalQSOs: Int(metrics.digitalQsos),
            operatingDays: Int(metrics.operatingDays),
            activeBands: Int(metrics.activeBands),
            uniqueCallsigns: Int(metrics.uniqueCallsigns),
            dxccEntities: Int(metrics.dxccEntities),
            qrpQSOs: Int(metrics.qrpQsos),
            milliwattQSOs: Int(metrics.milliwattQsos),
            parksHunted: Int(metrics.parksHunted),
            parkToPark: Int(metrics.parkToPark),
            perfectReports: Int(metrics.perfectReports)
        )
    }

    // MARK: Internal

    /// Internal (not private) so the `+POTAAwards` extension in another file can reach it.
    let store: FieldStore
}

private extension AnalyticsDimension {
    var ffi: FfiAggregateDimension {
        switch self {
        case .band: .band
        case .modeFamily: .modeFamily
        case .dxcc: .dxcc
        case .month: .month
        }
    }
}
