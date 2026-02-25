import Foundation

// MARK: - BragSheetStatType

/// All available statistics for brag sheet cards.
/// Each stat belongs to a category and can be independently toggled per period.
enum BragSheetStatType: String, Codable, CaseIterable, Identifiable, Sendable {
    var id: String { rawValue }

    // MARK: - Totals

    case totalQSOs
    case totalCWQSOs
    case totalPhoneQSOs
    case totalDigitalQSOs
    case totalDistance
    case operatingDays
    case operatingHours
    case activeBands
    case activeModes
    case uniqueCallsigns
    case qrpQSOCount
    case milliwattQSOCount

    // MARK: - Speed & Rate

    case fastest10QSOs
    case peak15MinRate
    case bestSessionRate
    case fastestActivation

    // MARK: - Distance

    case furthestContact
    case furthestContactPerBand
    case furthestQRPContact
    case averageContactDistance

    // MARK: - Power & Efficiency

    case lowestPowerContact
    case bestWattsPerMile

    // MARK: - Geographic Reach

    case dxccEntities
    case newDXCCEntities
    case statesAndProvinces
    case gridSquares
    case continents
    case mostContinentsInADay
    case workedAllStatesProgress

    // MARK: - Volume Records

    case mostQSOsInADay
    case mostQSOsInASession
    case mostCountriesInADay
    case mostBandsInADay

    // MARK: - Streaks

    case currentOnAirStreak
    case bestOnAirStreak
    case currentActivationStreak
    case modeStreaks

    // MARK: - POTA

    case parksActivated
    case parksHunted
    case parkToParkContacts
    case largestNfer
    case bestActivation
    case newParks

    // MARK: - CW

    case fastestCWSpeed
    case cwDistanceRecord
    case cwQRPRecord

    // MARK: - Signal Quality

    case perfectReports
    case averageRSTReceived
    case bestRSTAtDistance

    // MARK: - Fun & Unique

    case earliestQSOOfTheDay
    case latestQSOOfTheDay
    case longestSession
    case mostActiveDayOfWeek
    case busiestBand
    case busiestMode
    case repeatCustomers
}

// MARK: - Display Metadata

extension BragSheetStatType {
    var displayName: String {
        switch self {
        case .totalQSOs: "Total QSOs"
        case .totalCWQSOs: "Total CW QSOs"
        case .totalPhoneQSOs: "Total Phone QSOs"
        case .totalDigitalQSOs: "Total Digital QSOs"
        case .totalDistance: "Total Distance"
        case .operatingDays: "Operating Days"
        case .operatingHours: "Operating Hours"
        case .activeBands: "Active Bands"
        case .activeModes: "Active Modes"
        case .uniqueCallsigns: "Unique Callsigns"
        case .qrpQSOCount: "QRP QSO Count"
        case .milliwattQSOCount: "Milliwatt QSO Count"
        case .fastest10QSOs: "Fastest 10 QSOs"
        case .peak15MinRate: "Peak 15-Min Rate"
        case .bestSessionRate: "Best Session Rate"
        case .fastestActivation: "Fastest Activation"
        case .furthestContact: "Furthest Contact"
        case .furthestContactPerBand: "Furthest per Band"
        case .furthestQRPContact: "Furthest QRP Contact"
        case .averageContactDistance: "Avg Contact Distance"
        case .lowestPowerContact: "Lowest Power Contact"
        case .bestWattsPerMile: "Best Watts-per-Mile"
        case .dxccEntities: "DXCC Entities"
        case .newDXCCEntities: "New DXCC Entities"
        case .statesAndProvinces: "States & Provinces"
        case .gridSquares: "Grid Squares"
        case .continents: "Continents"
        case .mostContinentsInADay: "Most Continents/Day"
        case .workedAllStatesProgress: "WAS Progress"
        case .mostQSOsInADay: "Most QSOs in a Day"
        case .mostQSOsInASession: "Most QSOs/Session"
        case .mostCountriesInADay: "Most Countries/Day"
        case .mostBandsInADay: "Most Bands in a Day"
        case .currentOnAirStreak: "On-Air Streak"
        case .bestOnAirStreak: "Best On-Air Streak"
        case .currentActivationStreak: "Activation Streak"
        case .modeStreaks: "Mode Streaks"
        case .parksActivated: "Parks Activated"
        case .parksHunted: "Parks Hunted"
        case .parkToParkContacts: "P2P Contacts"
        case .largestNfer: "Largest N-fer"
        case .bestActivation: "Best Activation"
        case .newParks: "New Parks"
        case .fastestCWSpeed: "Fastest CW Speed"
        case .cwDistanceRecord: "CW Distance Record"
        case .cwQRPRecord: "CW QRP Record"
        case .perfectReports: "Perfect Reports"
        case .averageRSTReceived: "Avg RST Received"
        case .bestRSTAtDistance: "Best RST at Distance"
        case .earliestQSOOfTheDay: "Earliest QSO"
        case .latestQSOOfTheDay: "Latest QSO"
        case .longestSession: "Longest Session"
        case .mostActiveDayOfWeek: "Most Active Day"
        case .busiestBand: "Busiest Band"
        case .busiestMode: "Busiest Mode"
        case .repeatCustomers: "Repeat Customers"
        }
    }

    var category: BragSheetCategory {
        switch self {
        case .totalQSOs, .totalCWQSOs, .totalPhoneQSOs, .totalDigitalQSOs,
             .totalDistance, .operatingDays, .operatingHours, .activeBands,
             .activeModes, .uniqueCallsigns, .qrpQSOCount, .milliwattQSOCount:
            .totals
        case .fastest10QSOs, .peak15MinRate, .bestSessionRate, .fastestActivation:
            .speedAndRate
        case .furthestContact, .furthestContactPerBand, .furthestQRPContact,
             .averageContactDistance:
            .distance
        case .lowestPowerContact, .bestWattsPerMile:
            .powerAndEfficiency
        case .dxccEntities, .newDXCCEntities, .statesAndProvinces, .gridSquares,
             .continents, .mostContinentsInADay, .workedAllStatesProgress:
            .geographicReach
        case .mostQSOsInADay, .mostQSOsInASession, .mostCountriesInADay,
             .mostBandsInADay:
            .volumeRecords
        case .currentOnAirStreak, .bestOnAirStreak, .currentActivationStreak,
             .modeStreaks:
            .streaks
        case .parksActivated, .parksHunted, .parkToParkContacts, .largestNfer,
             .bestActivation, .newParks:
            .pota
        case .fastestCWSpeed, .cwDistanceRecord, .cwQRPRecord:
            .cw
        case .perfectReports, .averageRSTReceived, .bestRSTAtDistance:
            .signalQuality
        case .earliestQSOOfTheDay, .latestQSOOfTheDay, .longestSession,
             .mostActiveDayOfWeek, .busiestBand, .busiestMode, .repeatCustomers:
            .funAndUnique
        }
    }

    var systemImage: String {
        switch category {
        case .totals: "number"
        case .speedAndRate: "gauge.with.needle"
        case .distance: "location.north.line"
        case .powerAndEfficiency: "bolt"
        case .geographicReach: "globe"
        case .volumeRecords: "trophy"
        case .streaks: "flame"
        case .pota: "tree"
        case .cw: "waveform"
        case .signalQuality: "antenna.radiowaves.left.and.right"
        case .funAndUnique: "sparkles"
        }
    }
}
