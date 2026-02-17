import Foundation

// MARK: - SidebarTab

/// Tab selection for the iPad spots sidebar
enum SidebarTab: String, CaseIterable, Identifiable {
    case pota = "POTA"
    case mySpots = "My Spots"
    case p2p = "P2P"

    // MARK: Internal

    var id: String {
        rawValue
    }
}

// MARK: - SpotSelection

/// A spot selected from the sidebar, carrying the data needed to fill the logger form
enum SpotSelection: Equatable {
    case pota(POTASpot)
    case rbn(UnifiedSpot)
    case p2p(P2POpportunity)

    // MARK: Internal

    static func == (lhs: SpotSelection, rhs: SpotSelection) -> Bool {
        switch (lhs, rhs) {
        case let (.pota(lhsSpot), .pota(rhsSpot)):
            lhsSpot.spotId == rhsSpot.spotId
        case let (.rbn(lhsSpot), .rbn(rhsSpot)):
            lhsSpot.id == rhsSpot.id
        case let (.p2p(lhsOpp), .p2p(rhsOpp)):
            lhsOpp.id == rhsOpp.id
        default:
            false
        }
    }
}

// MARK: - SpotCommandAction

/// Actions from LoggerView commands that the container intercepts on iPad
/// to switch sidebar tabs instead of opening overlay panels
enum SpotCommandAction {
    case showPOTA
    case showRBN(callsign: String?)
    case showP2P
}
