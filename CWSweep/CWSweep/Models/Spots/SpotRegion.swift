import CarrierWaveCore
import CoreLocation
import Foundation

// MARK: - SpotRegion

/// Geographic region classification for spot locations
enum SpotRegion: String, CaseIterable, Sendable {
    case neUS = "NE US"
    case seUS = "SE US"
    case mwUS = "MW US"
    case swUS = "SW US"
    case nwUS = "NW US"
    case canada = "Canada"
    case mexico = "Mexico"
    case caribbean = "Caribbean"
    case europe = "Europe"
    case asia = "Asia"
    case oceania = "Oceania"
    case africa = "Africa"
    case southAmerica = "S. America"
    case other = "Other"

    // MARK: Internal

    /// Short display name for compact views
    var shortName: String {
        switch self {
        case .neUS: "NE"
        case .seUS: "SE"
        case .mwUS: "MW"
        case .swUS: "SW"
        case .nwUS: "NW"
        case .canada: "CA"
        case .mexico: "MX"
        case .caribbean: "Carib"
        case .europe: "EU"
        case .asia: "AS"
        case .oceania: "OC"
        case .africa: "AF"
        case .southAmerica: "SA"
        case .other: "Other"
        }
    }

    /// Classify a grid square into a region
    static func from(grid: String?) -> SpotRegion {
        guard let grid = grid?.uppercased(), grid.count >= 2 else {
            return .other
        }

        if let coord = MaidenheadConverter.coordinate(from: grid) {
            return from(coordinate: CLLocationCoordinate2D(
                latitude: coord.latitude,
                longitude: coord.longitude
            ))
        }

        let prefix = String(grid.prefix(2))
        let firstChar = grid.first!
        let secondChar = grid.dropFirst().first!
        return classifyByPrefix(prefix, firstChar: firstChar, secondChar: secondChar)
    }

    /// Classify a coordinate into a region
    static func from(coordinate: CLLocationCoordinate2D) -> SpotRegion {
        let lat = coordinate.latitude
        let lon = coordinate.longitude

        // North America
        if lat >= 24, lat <= 72, lon >= -170, lon <= -50 {
            if lat >= 24, lat <= 49, lon >= -125, lon <= -66 {
                return classifyUSRegion(lat: lat, lon: lon)
            }
            if lat > 49, lon >= -141, lon <= -52 {
                return .canada
            }
            if lat >= 14, lat <= 33, lon >= -118, lon <= -86 {
                return .mexico
            }
        }

        if lat >= 10, lat <= 27, lon >= -85, lon <= -59 {
            return .caribbean
        }
        if lat >= 35, lat <= 72, lon >= -25, lon <= 45 {
            return .europe
        }
        if (lat >= 0 && lat <= 80 && lon >= 45 && lon <= 180)
            || (lat >= 0 && lat <= 80 && lon >= -180 && lon <= -140)
        {
            return .asia
        }
        if (lat >= -50 && lat <= 0 && lon >= 110 && lon <= 180)
            || (lat >= -50 && lat <= 0 && lon >= -180 && lon <= -130)
        {
            return .oceania
        }
        if lat >= -35, lat <= 37, lon >= -20, lon <= 55 {
            return .africa
        }
        if lat >= -56, lat <= 15, lon >= -82, lon <= -34 {
            return .southAmerica
        }

        return .other
    }

    // MARK: Private

    private static let prefixRegionMap: [String: SpotRegion] = [
        "DN": .mwUS, "DM": .mwUS, "CN": .mwUS, "CM": .mwUS,
        "FO": .canada, "EO": .canada, "DO": .canada, "CO": .canada, "BO": .canada,
        "DK": .mexico, "EK": .mexico,
        "FK": .caribbean, "FL": .caribbean,
        "IO": .europe, "JO": .europe, "JN": .europe, "IN": .europe,
        "KO": .europe, "KN": .europe, "LO": .europe, "LN": .europe,
        "PM": .asia, "OM": .asia, "PL": .asia, "OL": .asia, "QL": .asia, "QM": .asia,
        "QF": .oceania, "QG": .oceania, "RF": .oceania, "RG": .oceania, "PF": .oceania,
        "PG": .oceania,
        "KH": .africa, "JH": .africa, "IH": .africa, "KG": .africa, "JG": .africa, "IG": .africa,
        "FH": .southAmerica, "GH": .southAmerica, "GG": .southAmerica,
        "FG": .southAmerica, "FF": .southAmerica, "GF": .southAmerica,
    ]

    private static let easternUSPrefixes: Set<String> = ["FN", "FM", "EN", "EM", "EL"]
    private static let westernUSPrefixes: Set<String> = ["DL", "CL", "BL", "BM", "BN"]

    private static func classifyUSRegion(lat: Double, lon: Double) -> SpotRegion {
        if lon >= -100 {
            if lat >= 37 {
                .neUS
            } else {
                .seUS
            }
        } else {
            if lat >= 42 {
                if lon >= -115 {
                    .mwUS
                } else {
                    .nwUS
                }
            } else {
                .swUS
            }
        }
    }

    private static func classifyByPrefix(
        _ prefix: String,
        firstChar _: Character,
        secondChar: Character
    ) -> SpotRegion {
        if let region = prefixRegionMap[prefix] {
            return region
        }
        if easternUSPrefixes.contains(prefix) {
            return secondChar >= "L" ? .neUS : .seUS
        }
        if westernUSPrefixes.contains(prefix) {
            return secondChar <= "M" ? .swUS : .nwUS
        }
        return .other
    }
}

// MARK: - SpotRegionGroup

/// Coarser geographic region groups for spot filtering.
enum SpotRegionGroup: String, CaseIterable, Codable, Sendable {
    case us = "US"
    case canada = "Canada"
    case mexico = "Mexico"
    case caribbean = "Caribbean"
    case europe = "Europe"
    case asia = "Asia"
    case oceania = "Oceania"
    case africa = "Africa"
    case southAmerica = "S. America"
    case other = "Other"

    // MARK: Internal

    static var allSet: Set<SpotRegionGroup> {
        Set(allCases)
    }
}

extension SpotRegion {
    /// Map this fine-grained region to its coarser group
    var group: SpotRegionGroup {
        switch self {
        case .neUS,
             .seUS,
             .mwUS,
             .swUS,
             .nwUS: .us
        case .canada: .canada
        case .mexico: .mexico
        case .caribbean: .caribbean
        case .europe: .europe
        case .asia: .asia
        case .oceania: .oceania
        case .africa: .africa
        case .southAmerica: .southAmerica
        case .other: .other
        }
    }
}

// MARK: - EnrichedSpot

/// A spot enriched with distance and region information
struct EnrichedSpot: Identifiable, Sendable, Equatable {
    let spot: UnifiedSpot
    let distanceMeters: Double?
    let bearingDegrees: Double?
    let region: SpotRegion
    var state: String?
    var country: String?

    var id: String {
        spot.id
    }

    /// Distance in miles
    var distanceMiles: Double? {
        guard let meters = distanceMeters else {
            return nil
        }
        return meters / 1_609.344
    }

    /// Distance in kilometers
    var distanceKm: Double? {
        guard let meters = distanceMeters else {
            return nil
        }
        return meters / 1_000.0
    }

    /// Best available location string: state (for US) or country, falling back to region
    var locationDisplay: String? {
        if let state, !state.isEmpty {
            return state
        }
        if let country, !country.isEmpty {
            return country
        }
        return nil
    }

    /// Formatted distance string using user's unit preference
    func formattedDistance() -> String? {
        guard let meters = distanceMeters else {
            return nil
        }
        return UnitFormatter.distanceFromMeters(meters)
    }

    /// Formatted bearing string, e.g. "275°"
    func formattedBearing() -> String? {
        guard let bearing = bearingDegrees else {
            return nil
        }
        return String(format: "%.0f°", bearing)
    }

    /// Combined distance and bearing, e.g. "450 mi 275°"
    func formattedDistanceAndBearing() -> String? {
        guard let dist = formattedDistance() else {
            return nil
        }
        if let brg = formattedBearing() {
            return "\(dist) \(brg)"
        }
        return dist
    }
}

// MARK: - SpotSummary

/// Aggregated summary of spots by region
struct SpotSummary: Sendable {
    static let empty = SpotSummary(
        spots: [],
        byRegion: [:],
        minDistanceMeters: nil,
        maxDistanceMeters: nil,
        timestamp: Date()
    )

    let spots: [EnrichedSpot]
    let byRegion: [SpotRegion: [EnrichedSpot]]
    let minDistanceMeters: Double?
    let maxDistanceMeters: Double?
    let timestamp: Date

    /// Regions with spots, sorted by count (descending)
    var regionsWithSpots: [(region: SpotRegion, count: Int)] {
        byRegion
            .map { (region: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    /// Total spot count
    var totalCount: Int {
        spots.count
    }
}
