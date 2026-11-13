import Foundation

// Distance-shaped brag-sheet DTOs (split from AnalyticsTypes.swift for file length). Each
// mirrors a cw-store result struct 1:1; see AnalyticsReadSource+BragDistance.swift.

// MARK: - BragContactRow

/// A furthest-contact brag record (mirrors cw-store `BragContact` / the `.contact` stat).
public struct BragContactRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(callsign: String, band: String, distanceKm: Double) {
        self.callsign = callsign
        self.band = band
        self.distanceKm = distanceKm
    }

    // MARK: Public

    public let callsign: String
    public let band: String
    public let distanceKm: Double
}

// MARK: - BragBandRecordRow

/// A per-band furthest-contact brag record (mirrors cw-store `BragBandRecord`). `band` is the
/// lowercased band key.
public struct BragBandRecordRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(band: String, callsign: String, distanceKm: Double) {
        self.band = band
        self.callsign = callsign
        self.distanceKm = distanceKm
    }

    // MARK: Public

    public let band: String
    public let callsign: String
    public let distanceKm: Double
}

// MARK: - BragPowerContactRow

/// The lowest-power brag contact (mirrors cw-store `BragPowerContact` / the `.power` stat).
/// `distanceKm` is `nil` when that QSO's grids don't yield a distance.
public struct BragPowerContactRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(watts: Int, callsign: String, band: String, distanceKm: Double?) {
        self.watts = watts
        self.callsign = callsign
        self.band = band
        self.distanceKm = distanceKm
    }

    // MARK: Public

    public let watts: Int
    public let callsign: String
    public let band: String
    public let distanceKm: Double?
}

// MARK: - BragEfficiencyRow

/// The best watts-per-mile brag contact (mirrors cw-store `BragEfficiency`). The `.efficiency`
/// ratio + detail string are formatted view-side from these components.
public struct BragEfficiencyRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(watts: Int, callsign: String, band: String, distanceKm: Double) {
        self.watts = watts
        self.callsign = callsign
        self.band = band
        self.distanceKm = distanceKm
    }

    // MARK: Public

    public let watts: Int
    public let callsign: String
    public let band: String
    public let distanceKm: Double
}

// MARK: - BragDistanceStatsResult

/// Distance-shaped brag-sheet stats (mirrors cw-store `BragDistanceStats` /
/// `BragSheetComputationActor`'s distance records). Each "furthest" is the max-distance
/// contact within a filtered subset; `nil`/empty when no QSO qualifies. Distances are
/// great-circle (haversine), matching the cw-store `cw_grid_distance_km` UDF.
public struct BragDistanceStatsResult: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        furthest: BragContactRow?,
        furthestQRP: BragContactRow?,
        furthestCW: BragContactRow?,
        furthestCWQRP: BragContactRow?,
        furthestPerfectRST: BragContactRow?,
        furthestPerBand: [BragBandRecordRow],
        averageKm: Double?,
        lowestPower: BragPowerContactRow?,
        bestWattsPerMile: BragEfficiencyRow?
    ) {
        self.furthest = furthest
        self.furthestQRP = furthestQRP
        self.furthestCW = furthestCW
        self.furthestCWQRP = furthestCWQRP
        self.furthestPerfectRST = furthestPerfectRST
        self.furthestPerBand = furthestPerBand
        self.averageKm = averageKm
        self.lowestPower = lowestPower
        self.bestWattsPerMile = bestWattsPerMile
    }

    // MARK: Public

    public let furthest: BragContactRow?
    public let furthestQRP: BragContactRow?
    public let furthestCW: BragContactRow?
    public let furthestCWQRP: BragContactRow?
    public let furthestPerfectRST: BragContactRow?
    public let furthestPerBand: [BragBandRecordRow]
    public let averageKm: Double?
    public let lowestPower: BragPowerContactRow?
    public let bestWattsPerMile: BragEfficiencyRow?
}
