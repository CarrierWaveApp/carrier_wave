import Foundation

// Additional analytics-surface DTOs (the headline/count/WAS/DXCC/presence DTOs live in
// AnalyticsReadSource.swift). Each mirrors a cw-store result struct 1:1.

// MARK: - ParkRollupRow

/// One park's activity rollup (mirrors cw-store `ParkRollup`). `activationDays` = distinct
/// UTC days activated; `huntQSOs` = raw hunt count; `lastWorked` = unix seconds (UTC).
public struct ParkRollupRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(park: String, activationDays: Int, huntQSOs: Int, lastWorked: Int) {
        self.park = park
        self.activationDays = activationDays
        self.huntQSOs = huntQSOs
        self.lastWorked = lastWorked
    }

    // MARK: Public

    public let park: String
    public let activationDays: Int
    public let huntQSOs: Int
    public let lastWorked: Int
}

// MARK: - StateCountRow

/// One worked US state with its QSO count (mirrors cw-store `StateCount`). `state` is a
/// normalized, valid (50-state) abbreviation.
public struct StateCountRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(state: String, count: Int) {
        self.state = state
        self.count = count
    }

    // MARK: Public

    public let state: String
    public let count: Int
}

// MARK: - SessionEquipmentRow

/// One equipment item's session rollup (mirrors cw-store `SessionEquipmentRollup`).
/// `kind` is the category ("radio"/"antenna"/"key"/"mic"); times are unix seconds (UTC).
public struct SessionEquipmentRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(kind: String, name: String, sessionCount: Int, totalQSOs: Int, firstUsed: Int, lastUsed: Int) {
        self.kind = kind
        self.name = name
        self.sessionCount = sessionCount
        self.totalQSOs = totalQSOs
        self.firstUsed = firstUsed
        self.lastUsed = lastUsed
    }

    // MARK: Public

    public let kind: String
    public let name: String
    public let sessionCount: Int
    public let totalQSOs: Int
    public let firstUsed: Int
    public let lastUsed: Int
}

// MARK: - SessionComboRow

/// One rig+antenna combo's session rollup (mirrors cw-store `SessionComboRollup`).
public struct SessionComboRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(rig: String, antenna: String, sessionCount: Int, totalQSOs: Int) {
        self.rig = rig
        self.antenna = antenna
        self.sessionCount = sessionCount
        self.totalQSOs = totalQSOs
    }

    // MARK: Public

    public let rig: String
    public let antenna: String
    public let sessionCount: Int
    public let totalQSOs: Int
}

// MARK: - BragPeriodMetrics

/// SQL-trivial brag-sheet period metrics (mirrors cw-store `BragPeriodMetrics`). Distance
/// / streak / per-session-window / new-this-period / activation-grouping metrics are not
/// included — they stay SwiftData-side (see the analytics design doc).
public struct BragPeriodMetrics: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        totalQSOs: Int,
        cwQSOs: Int,
        phoneQSOs: Int,
        digitalQSOs: Int,
        operatingDays: Int,
        activeBands: Int,
        uniqueCallsigns: Int,
        dxccEntities: Int,
        qrpQSOs: Int,
        milliwattQSOs: Int,
        parksHunted: Int,
        parkToPark: Int,
        perfectReports: Int
    ) {
        self.totalQSOs = totalQSOs
        self.cwQSOs = cwQSOs
        self.phoneQSOs = phoneQSOs
        self.digitalQSOs = digitalQSOs
        self.operatingDays = operatingDays
        self.activeBands = activeBands
        self.uniqueCallsigns = uniqueCallsigns
        self.dxccEntities = dxccEntities
        self.qrpQSOs = qrpQSOs
        self.milliwattQSOs = milliwattQSOs
        self.parksHunted = parksHunted
        self.parkToPark = parkToPark
        self.perfectReports = perfectReports
    }

    // MARK: Public

    public let totalQSOs: Int
    public let cwQSOs: Int
    public let phoneQSOs: Int
    public let digitalQSOs: Int
    public let operatingDays: Int
    public let activeBands: Int
    public let uniqueCallsigns: Int
    public let dxccEntities: Int
    public let qrpQSOs: Int
    public let milliwattQSOs: Int
    public let parksHunted: Int
    public let parkToPark: Int
    public let perfectReports: Int
}

// MARK: - WASDrilldownRow

/// One WAS drilldown row (mirrors cw-store `WasDrilldownRow`): for a (source × mode ×
/// state), the QSO count and the distinct uppercased callsigns. `source` is `"all"` or
/// `"qth"` (QSOs not at a park); `mode` is `nil` for the all-modes rollup. Backs
/// `StatsComputationActor.wasData`.
public struct WASDrilldownRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(source: String, mode: String?, state: String, count: Int, callsigns: [String]) {
        self.source = source
        self.mode = mode
        self.state = state
        self.count = count
        self.callsigns = callsigns
    }

    // MARK: Public

    public let source: String
    public let mode: String?
    public let state: String
    public let count: Int
    public let callsigns: [String]
}

// MARK: - NearKiloParkRow

/// A park approaching the 1,000-QSO kilo threshold (mirrors cw-store `NearKiloPark`).
public struct NearKiloParkRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(reference: String, qsoCount: Int) {
        self.reference = reference
        self.qsoCount = qsoCount
    }

    // MARK: Public

    public let reference: String
    public let qsoCount: Int
}

// MARK: - POTAAwardsResult

/// POTA activator awards progress (mirrors cw-store `PotaAwards` / iOS
/// `POTAAwardsProgress`). `statesActivated` is sorted; `kiloParks` ascending;
/// `nearKiloParks` by count descending (ties by reference ascending).
public struct POTAAwardsResult: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        uniqueParksCount: Int,
        dxEntitiesCount: Int,
        statesActivated: [String],
        roverMaxParks: Int,
        repeatOffenderMaxCount: Int,
        parkToParkCount: Int,
        kiloParks: [String],
        nearKiloParks: [NearKiloParkRow],
        laPortaEarned: Bool,
        laPortaQualifyingParks: Int,
        sixPackEarned: Bool,
        bestSingleParkTotal: Int,
        totalParkQSOs: Int,
        metadataExcluded: Int,
        totalActivationGroups: Int,
        validActivationGroups: Int
    ) {
        self.uniqueParksCount = uniqueParksCount
        self.dxEntitiesCount = dxEntitiesCount
        self.statesActivated = statesActivated
        self.roverMaxParks = roverMaxParks
        self.repeatOffenderMaxCount = repeatOffenderMaxCount
        self.parkToParkCount = parkToParkCount
        self.kiloParks = kiloParks
        self.nearKiloParks = nearKiloParks
        self.laPortaEarned = laPortaEarned
        self.laPortaQualifyingParks = laPortaQualifyingParks
        self.sixPackEarned = sixPackEarned
        self.bestSingleParkTotal = bestSingleParkTotal
        self.totalParkQSOs = totalParkQSOs
        self.metadataExcluded = metadataExcluded
        self.totalActivationGroups = totalActivationGroups
        self.validActivationGroups = validActivationGroups
    }

    // MARK: Public

    public let uniqueParksCount: Int
    public let dxEntitiesCount: Int
    public let statesActivated: [String]
    public let roverMaxParks: Int
    public let repeatOffenderMaxCount: Int
    public let parkToParkCount: Int
    public let kiloParks: [String]
    public let nearKiloParks: [NearKiloParkRow]
    public let laPortaEarned: Bool
    public let laPortaQualifyingParks: Int
    public let sixPackEarned: Bool
    public let bestSingleParkTotal: Int
    public let totalParkQSOs: Int
    public let metadataExcluded: Int
    public let totalActivationGroups: Int
    public let validActivationGroups: Int
}

// MARK: - WAS250Result

/// America 250 WAS progress (mirrors cw-store `Was250` / iOS `WAS250Progress`).
/// State arrays are sorted ascending; the pipeline counts are diagnostic.
public struct WAS250Result: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        statesWorked: [String],
        cwStates: [String],
        phoneStates: [String],
        digitalStates: [String],
        totalQSOs: Int,
        metadataExcluded: Int,
        withStateField: Int,
        withValidState: Int
    ) {
        self.statesWorked = statesWorked
        self.cwStates = cwStates
        self.phoneStates = phoneStates
        self.digitalStates = digitalStates
        self.totalQSOs = totalQSOs
        self.metadataExcluded = metadataExcluded
        self.withStateField = withStateField
        self.withValidState = withValidState
    }

    // MARK: Public

    public let statesWorked: [String]
    public let cwStates: [String]
    public let phoneStates: [String]
    public let digitalStates: [String]
    public let totalQSOs: Int
    public let metadataExcluded: Int
    public let withStateField: Int
    public let withValidState: Int
}

// MARK: - SessionInput

/// Flattened `LoggingSession` equipment fields — the oracle input for
/// `AnalyticsAggregator.sessionEquipmentRollup` / `sessionComboRollup` (the SQL has the
/// same columns). Keeps the oracle free of SwiftData models.
public struct SessionInput: Sendable {
    // MARK: Lifecycle

    public init(myRig: String?, myAntenna: String?, myKey: String?, myMic: String?, qsoCount: Int, startedAt: Int) {
        self.myRig = myRig
        self.myAntenna = myAntenna
        self.myKey = myKey
        self.myMic = myMic
        self.qsoCount = qsoCount
        self.startedAt = startedAt
    }

    // MARK: Public

    public let myRig: String?
    public let myAntenna: String?
    public let myKey: String?
    public let myMic: String?
    public let qsoCount: Int
    public let startedAt: Int
}

// MARK: - SessionItemInput

/// A `LoggingSession`'s identity + equipment slots — the oracle input for
/// `AnalyticsAggregator.sessionItemDetail`. Adds `id` over `SessionInput` so the oracle can
/// link QSOs (`loggingSessionId`) to the sessions that use a given item, exactly as the SQL
/// `qso` ↔ `logging_session` join does.
public struct SessionItemInput: Sendable {
    // MARK: Lifecycle

    public init(id: UUID, myRig: String?, myAntenna: String?, myKey: String?, myMic: String?, qsoCount: Int) {
        self.id = id
        self.myRig = myRig
        self.myAntenna = myAntenna
        self.myKey = myKey
        self.myMic = myMic
        self.qsoCount = qsoCount
    }

    // MARK: Public

    public let id: UUID
    public let myRig: String?
    public let myAntenna: String?
    public let myKey: String?
    public let myMic: String?
    public let qsoCount: Int
}

// MARK: - ItemTallyRow

/// One (name, count) tally row in a `SessionItemDetailResult` breakdown (mirrors cw-store
/// `ItemTally`). `name` is the raw band or mode string (empty for NULL/empty).
public struct ItemTallyRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }

    // MARK: Public

    public let name: String
    public let count: Int
}

// MARK: - SessionItemDetailResult

/// Per-equipment-item QSO breakdown (mirrors cw-store `SessionItemDetail` / the QSO-derived
/// half of `EquipmentItemDetailActor.ComputedEquipmentItemDetail`): totals, distinct DXCC
/// entities, distance extremes, and per-band / per-mode tallies over the item's QSOs.
/// Distance values are `nil` when no QSO has a positive, computable distance. The session
/// list and paired-equipment counts are computed session-side, not here.
public struct SessionItemDetailResult: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        totalQSOs: Int,
        uniqueEntities: Int,
        farthestKm: Double?,
        shortestKm: Double?,
        averageKm: Double?,
        bandBreakdown: [ItemTallyRow],
        modeBreakdown: [ItemTallyRow]
    ) {
        self.totalQSOs = totalQSOs
        self.uniqueEntities = uniqueEntities
        self.farthestKm = farthestKm
        self.shortestKm = shortestKm
        self.averageKm = averageKm
        self.bandBreakdown = bandBreakdown
        self.modeBreakdown = modeBreakdown
    }

    // MARK: Public

    public let totalQSOs: Int
    public let uniqueEntities: Int
    public let farthestKm: Double?
    public let shortestKm: Double?
    public let averageKm: Double?
    public let bandBreakdown: [ItemTallyRow]
    public let modeBreakdown: [ItemTallyRow]
}
