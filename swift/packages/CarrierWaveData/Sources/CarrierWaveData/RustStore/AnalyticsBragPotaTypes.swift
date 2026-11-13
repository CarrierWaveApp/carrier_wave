import Foundation

// MARK: - BragBestActivationRow

/// One park activation extreme (mirrors cw-store `BragBestActivation` /
/// `BragSheetComputationActor.computeBestActivation`'s `.parkDetail`). `day` is a `YYYY-MM-DD`
/// UTC calendar day; the routing layer maps it back to a `Date`.
public struct BragBestActivationRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(park: String, day: String, count: Int) {
        self.park = park
        self.day = day
        self.count = count
    }

    // MARK: Public

    public let park: String
    public let day: String
    public let count: Int
}

// MARK: - BragPotaResult

/// POTA-category brag-sheet stats (mirrors cw-store `BragPota` / `BragSheetComputationActor+POTA`).
/// All counts are over the period except `newParks`, which also consults the all-time log.
/// `bestActivation` is `nil` when there are no parked QSOs.
public struct BragPotaResult: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        parksActivated: Int,
        parksHunted: Int,
        parkToPark: Int,
        bestActivation: BragBestActivationRow?,
        newParks: Int
    ) {
        self.parksActivated = parksActivated
        self.parksHunted = parksHunted
        self.parkToPark = parkToPark
        self.bestActivation = bestActivation
        self.newParks = newParks
    }

    // MARK: Public

    /// Distinct parks with a (park, UTC-day) group of ≥ 10 unique QSOs (`computeParksActivated`).
    public let parksActivated: Int
    /// Distinct non-empty raw their-park references hunted (`computeParksHunted`).
    public let parksHunted: Int
    /// QSOs with both a non-empty park and their-park (`computeP2P`).
    public let parkToPark: Int
    /// The (park, UTC-day) activation group with the most raw QSOs (`computeBestActivation`).
    public let bestActivation: BragBestActivationRow?
    /// Parks (activated ∪ hunted) in the period first ever worked within it (`computeNewParks`).
    public let newParks: Int
}
