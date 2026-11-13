import CarrierWaveData
import Foundation

// MARK: - DaySummarySnapshot

/// Sendable projection of a single UTC day for `DaySummaryView`.
///
/// Built on `DaySummaryDataActor`; consumed on `@MainActor`.
struct DaySummarySnapshot {
    let date: Date
    let dayQSOs: [DaySummaryQSO]
    let sessions: [SessionCardData]
    let hunterCard: SessionCardData?
    let looseCard: SessionCardData?
    let bandCounts: [DayBandCount]
    let modeCounts: [DayModeCount]
    let dxccCount: Int
    let stateAbbreviations: Set<String>
}

// MARK: - SessionCardData

struct SessionCardData: Identifiable, Equatable {
    enum Kind: Equatable {
        case session(UUID)
        case hunter
        case loose
    }

    let id: String
    let kind: Kind
    let title: String
    let typeIcon: SessionTypeIcon
    let timeRange: ClosedRange<Date>?
    let isLive: Bool
    let continuationBadge: ContinuationBadge?
    let slicedQSOs: [DaySummaryQSO]
    let bandPills: [DayBandCount]
    let modePills: [DayModeCount]
}

// MARK: - DaySummaryQSO

nonisolated struct DaySummaryQSO: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let callsign: String
    let band: String
    let mode: String
    let frequency: Double?
    let loggingSessionId: UUID?
    let dxcc: Int?
    let state: String?
    let myGrid: String?
    let theirGrid: String?
    let stationProfileName: String?
}

// MARK: - DayBandCount

struct DayBandCount: Equatable, Hashable {
    let band: String
    let count: Int
}

// MARK: - DayModeCount

struct DayModeCount: Equatable, Hashable {
    let mode: String
    let count: Int
}

// MARK: - ContinuationBadge

enum ContinuationBadge: Equatable {
    case continues
    case continued
    case both
}

// MARK: - SessionTypeIcon

enum SessionTypeIcon: Equatable {
    case pota
    case sota
    case wwff
    case aoa
    case tota
    case ft8
    case contest
    case casual
    case hunter
    case loose
}

// MARK: - DaySummaryQSO bridge from SwiftData QSO

extension DaySummaryQSO {
    nonisolated init(qso: QSO) {
        self.init(
            id: qso.id,
            timestamp: qso.timestamp,
            callsign: qso.callsign,
            band: qso.band,
            mode: qso.mode,
            frequency: qso.frequency,
            loggingSessionId: qso.loggingSessionId,
            dxcc: qso.dxcc,
            state: qso.state,
            myGrid: qso.myGrid,
            theirGrid: qso.theirGrid,
            stationProfileName: qso.stationProfileName
        )
    }
}

// MARK: - SessionFacts

/// `Sendable` projection of the `LoggingSession` fields the snapshot needs.
/// SwiftData models are tied to their context; copying out everything we
/// touch lets us hand the result back to the main actor safely.
nonisolated struct SessionFacts: Equatable {
    // MARK: Lifecycle

    nonisolated init(session: LoggingSession) {
        id = session.id
        startedAt = session.startedAt
        endedAt = session.endedAt
        mode = session.mode
        programs = session.programs
        parkReference = session.parkReference
        sotaReference = session.sotaReference
        wwffReference = session.wwffReference
        customTitle = session.customTitle
        activationTypeDisplay = session.activationType.displayName
    }

    nonisolated init(
        id: UUID,
        startedAt: Date,
        endedAt: Date?,
        mode: String,
        programs: Set<String>,
        parkReference: String? = nil,
        sotaReference: String? = nil,
        wwffReference: String? = nil,
        customTitle: String? = nil,
        activationTypeDisplay: String = "Casual"
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.mode = mode
        self.programs = programs
        self.parkReference = parkReference
        self.sotaReference = sotaReference
        self.wwffReference = wwffReference
        self.customTitle = customTitle
        self.activationTypeDisplay = activationTypeDisplay
    }

    // MARK: Internal

    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let mode: String
    let programs: Set<String>
    let parkReference: String?
    let sotaReference: String?
    let wwffReference: String?
    let customTitle: String?
    let activationTypeDisplay: String
}
