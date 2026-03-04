import CarrierWaveData
import Foundation

// MARK: - BragSheetPreset

/// Curated starting-point configurations for brag sheet cards.
/// After applying a preset, users can customize stat selection and ordering.
nonisolated enum BragSheetPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case general
    case dxer
    case qrp
    case activator
    case contester
    case cwEnthusiast
    case showEverything

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .general: "General"
        case .dxer: "DXer"
        case .qrp: "QRP"
        case .activator: "Activator"
        case .contester: "Contester"
        case .cwEnthusiast: "CW Enthusiast"
        case .showEverything: "Show Everything"
        }
    }

    var description: String {
        switch self {
        case .general: "Balanced overview"
        case .dxer: "Distance & entities"
        case .qrp: "Low power"
        case .activator: "POTA activations"
        case .contester: "Speed & volume"
        case .cwEnthusiast: "Morse code"
        case .showEverything: "All stats"
        }
    }

    /// Stats included in this preset, in display order.
    var stats: [BragSheetStatType] {
        switch self {
        case .general:
            [
                .totalQSOs, .furthestContact, .dxccEntities,
                .statesAndProvinces, .activeBands, .activeModes,
                .operatingDays, .bestSessionRate, .clubMembersWorked,
            ]
        case .dxer:
            [
                .furthestContact, .furthestContactPerBand, .dxccEntities,
                .newDXCCEntities, .continents, .mostCountriesInADay,
                .gridSquares, .totalDistance,
            ]
        case .qrp:
            [
                .lowestPowerContact, .bestWattsPerMile, .furthestQRPContact,
                .qrpQSOCount, .milliwattQSOCount, .furthestContact,
                .totalDistance,
            ]
        case .activator:
            [
                .parksActivated, .bestActivation, .fastestActivation,
                .parkToParkContacts, .largestNfer, .newParks,
                .totalQSOs, .bestSessionRate,
            ]
        case .contester:
            [
                .fastest10QSOs, .peak15MinRate, .bestSessionRate,
                .mostQSOsInADay, .totalQSOs, .activeBands,
                .uniqueCallsigns,
            ]
        case .cwEnthusiast:
            [
                .totalCWQSOs, .fastestCWSpeed, .cwDistanceRecord,
                .cwQRPRecord, .peak15MinRate, .perfectReports,
                .currentOnAirStreak,
            ]
        case .showEverything:
            BragSheetStatType.allCases
        }
    }

    /// Default hero stats (first 4) for this preset.
    var defaultHeroStats: [BragSheetStatType] {
        Array(stats.prefix(4))
    }
}
