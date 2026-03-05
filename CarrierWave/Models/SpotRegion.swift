import CarrierWaveData
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
    /// - Parameter grid: Maidenhead grid locator (e.g., "FN31", "JO22")
    /// - Returns: The geographic region for this grid
    static func from(grid: String?) -> SpotRegion {
        guard let grid = grid?.uppercased(), grid.count >= 2 else {
            return .other
        }

        let prefix = String(grid.prefix(2))
        let firstChar = grid.first!
        let secondChar = grid.dropFirst().first!

        // Use coordinate-based classification for accuracy
        if let coord = MaidenheadConverter.coordinate(from: grid) {
            return from(coordinate: coord)
        }

        // Fallback to prefix-based classification
        return classifyByPrefix(prefix, firstChar: firstChar, secondChar: secondChar)
    }

    /// Classify a coordinate into a region
    static func from(coordinate: CLLocationCoordinate2D) -> SpotRegion {
        let lat = coordinate.latitude
        let lon = coordinate.longitude

        // North America
        if lat >= 24, lat <= 72, lon >= -170, lon <= -50 {
            // USA regions
            if lat >= 24, lat <= 49, lon >= -125, lon <= -66 {
                return classifyUSRegion(lat: lat, lon: lon)
            }
            // Canada
            if lat > 49, lon >= -141, lon <= -52 {
                return .canada
            }
            // Mexico
            if lat >= 14, lat <= 33, lon >= -118, lon <= -86 {
                return .mexico
            }
        }

        // Caribbean
        if lat >= 10, lat <= 27, lon >= -85, lon <= -59 {
            return .caribbean
        }

        // Europe
        if lat >= 35, lat <= 72, lon >= -25, lon <= 45 {
            return .europe
        }

        // Asia
        if lat >= 0, lat <= 80, lon >= 45, lon <= 180 {
            return .asia
        }
        if lat >= 0, lat <= 80, lon >= -180, lon <= -140 {
            return .asia // Eastern Russia/Japan wrap
        }

        // Oceania
        if lat >= -50, lat <= 0, lon >= 110, lon <= 180 {
            return .oceania
        }
        if lat >= -50, lat <= 0, lon >= -180, lon <= -130 {
            return .oceania // Pacific islands
        }

        // Africa
        if lat >= -35, lat <= 37, lon >= -20, lon <= 55 {
            return .africa
        }

        // South America
        if lat >= -56, lat <= 15, lon >= -82, lon <= -34 {
            return .southAmerica
        }

        return .other
    }

    // MARK: Private

    /// Grid prefix to region mapping
    private static let prefixRegionMap: [String: SpotRegion] = [
        // Central/Mountain US
        "DN": .mwUS, "DM": .mwUS, "CN": .mwUS, "CM": .mwUS,
        // Canada
        "FO": .canada, "EO": .canada, "DO": .canada, "CO": .canada, "BO": .canada,
        // Mexico
        "DK": .mexico, "EK": .mexico,
        // Caribbean
        "FK": .caribbean, "FL": .caribbean,
        // Europe
        "IO": .europe, "JO": .europe, "JN": .europe, "IN": .europe,
        "KO": .europe, "KN": .europe, "LO": .europe, "LN": .europe,
        // Asia
        "PM": .asia, "OM": .asia, "PL": .asia, "OL": .asia, "QL": .asia, "QM": .asia,
        // Oceania
        "QF": .oceania, "QG": .oceania, "RF": .oceania, "RG": .oceania, "PF": .oceania,
        "PG": .oceania,
        // Africa
        "KH": .africa, "JH": .africa, "IH": .africa, "KG": .africa, "JG": .africa, "IG": .africa,
        // South America
        "FH": .southAmerica, "GH": .southAmerica, "GG": .southAmerica,
        "FG": .southAmerica, "FF": .southAmerica, "GF": .southAmerica,
    ]

    // Prefixes that need secondary character check
    private static let easternUSPrefixes: Set<String> = ["FN", "FM", "EN", "EM", "EL"]
    private static let westernUSPrefixes: Set<String> = ["DL", "CL", "BL", "BM", "BN"]

    private static func classifyUSRegion(lat: Double, lon: Double) -> SpotRegion {
        // Divide US into regions
        // East/West split around -100 longitude
        // North/South split around 37 latitude

        if lon >= -100 {
            // Eastern US
            if lat >= 37 {
                .neUS
            } else {
                .seUS
            }
        } else {
            // Western US
            if lat >= 42 {
                if lon >= -115 {
                    .mwUS // Mountain states
                } else {
                    .nwUS // Pacific Northwest
                }
            } else {
                .swUS
            }
        }
    }

    private static func classifyByPrefix(
        _ prefix: String,
        firstChar: Character,
        secondChar: Character
    ) -> SpotRegion {
        // Check direct mappings first
        if let region = prefixRegionMap[prefix] {
            return region
        }

        // Eastern US (needs secondary check)
        if easternUSPrefixes.contains(prefix) {
            return secondChar >= "L" ? .neUS : .seUS
        }

        // Western US (needs secondary check)
        if westernUSPrefixes.contains(prefix) {
            return secondChar <= "M" ? .swUS : .nwUS
        }

        return .other
    }
}

// MARK: - SpotRegionGroup

/// Coarser geographic region groups for spot filtering.
/// Combines the 5 US sub-regions into a single "US" group.
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

    /// All region groups as a set (for "show all" default)
    static var allSet: Set<SpotRegionGroup> {
        Set(allCases)
    }

    /// Encode a set of region groups to a comma-separated string for AppStorage
    static func encode(_ regions: Set<SpotRegionGroup>) -> String {
        regions.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// Decode a comma-separated string to a set of region groups
    static func decode(_ string: String) -> Set<SpotRegionGroup> {
        guard !string.isEmpty else {
            return allSet
        }
        let values = string.components(separatedBy: ",")
        return Set(values.compactMap { SpotRegionGroup(rawValue: $0) })
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
struct EnrichedSpot: Identifiable, Sendable {
    let spot: UnifiedSpot
    let distanceMeters: Double?
    let bearingDegrees: Double?
    let region: SpotRegion

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

    /// Formatted distance string based on user preference
    func formattedDistance(useMetric: Bool) -> String? {
        guard let km = distanceKm else {
            return nil
        }
        return UnitFormatter.distance(km)
    }
}

// MARK: - SpotSummary

/// Aggregated summary of spots by region
struct SpotSummary: Sendable {
    /// Empty summary
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

    /// Formatted distance range
    func distanceRange(useMetric: Bool) -> String? {
        guard let minMeters = minDistanceMeters,
              let maxMeters = maxDistanceMeters
        else {
            return nil
        }
        return UnitFormatter.distanceRange(minMeters: minMeters, maxMeters: maxMeters)
    }
}
