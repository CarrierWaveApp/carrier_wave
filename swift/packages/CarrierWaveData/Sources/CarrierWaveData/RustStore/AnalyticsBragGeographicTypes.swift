import Foundation

// MARK: - BragGeographicResult

/// Geographic-reach brag-sheet stats (mirrors cw-store `BragGeographic` /
/// `BragSheetComputationActor`'s `computeGeoStat` set). All counts are over the period except
/// `newDXCCEntities`, which also consults the all-time log. `continents` is shown as
/// `current/6` and `wasStates` as `current/50`; a `continents`/`mostContinentsDay` of 0 maps
/// to the `.noData` case view-side.
public struct BragGeographicResult: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        dxccEntities: Int,
        newDXCCEntities: Int,
        statesProvinces: Int,
        gridSquares: Int,
        continents: Int,
        mostContinentsDay: Int,
        wasStates: Int
    ) {
        self.dxccEntities = dxccEntities
        self.newDXCCEntities = newDXCCEntities
        self.statesProvinces = statesProvinces
        self.gridSquares = gridSquares
        self.continents = continents
        self.mostContinentsDay = mostContinentsDay
        self.wasStates = wasStates
    }

    // MARK: Public

    public let dxccEntities: Int
    public let newDXCCEntities: Int
    public let statesProvinces: Int
    public let gridSquares: Int
    public let continents: Int
    public let mostContinentsDay: Int
    public let wasStates: Int
}
