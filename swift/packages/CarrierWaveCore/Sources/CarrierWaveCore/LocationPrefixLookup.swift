// Location-Based Call Sign Prefix Lookup
//
// Maps DXCC entities to their primary amateur radio prefix and representative
// coordinates. Provides nearest-entity lookup from GPS position so the app can
// suggest the correct portable prefix when operating from a foreign country.

import Foundation

// MARK: - PrefixCountry

/// A DXCC entity with its primary amateur radio prefix and representative coordinate.
public struct PrefixCountry: Sendable, Identifiable, Hashable {
    public let id: Int // DXCC entity number
    public let name: String
    public let prefix: String
    public let latitude: Double
    public let longitude: Double
}

// MARK: - LocationPrefixLookup

/// Looks up the appropriate amateur radio prefix for a geographic location.
///
/// Uses representative coordinates for each DXCC entity and nearest-match
/// to suggest which prefix an operator should use when transmitting from
/// a given position. Results are suggestions — users should always verify
/// and can override.
public enum LocationPrefixLookup {
    // MARK: Public

    /// All countries, sorted alphabetically by name.
    public static let sortedCountries: [PrefixCountry] = countries
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    /// Find the nearest DXCC entity to a given coordinate.
    /// Returns nil only if the country list is empty (should never happen).
    public static func nearest(
        latitude: Double,
        longitude: Double
    ) -> PrefixCountry? {
        var bestMatch: PrefixCountry?
        var bestDistance = Double.greatestFiniteMagnitude

        for country in countries {
            let dist = haversineDistance(
                lat1: latitude, lon1: longitude,
                lat2: country.latitude, lon2: country.longitude
            )
            if dist < bestDistance {
                bestDistance = dist
                bestMatch = country
            }
        }
        return bestMatch
    }

    /// Find the nearest DXCC entity to the center of a Maidenhead grid square.
    /// Returns nil if the grid is invalid or the country list is empty.
    public static func nearest(grid: String) -> PrefixCountry? {
        guard let coord = MaidenheadConverter.coordinate(from: grid) else {
            return nil
        }
        return nearest(latitude: coord.latitude, longitude: coord.longitude)
    }

    /// Find the DXCC entity for the user's home callsign prefix.
    /// Uses longest-prefix matching against the country list.
    public static func entity(forCallsign callsign: String) -> PrefixCountry? {
        let upper = callsign.uppercased()
        // Strip any existing portable prefix (take the base call)
        let base: String
        let parts = upper.components(separatedBy: "/")
        if parts.count >= 2 {
            // Use the longest part as the base callsign
            base = parts.max(by: { $0.count < $1.count }) ?? upper
        } else {
            base = upper
        }

        // Try progressively shorter prefixes against the country list
        var bestMatch: PrefixCountry?
        var bestLength = 0

        for country in countries {
            if base.hasPrefix(country.prefix), country.prefix.count > bestLength {
                bestMatch = country
                bestLength = country.prefix.count
            }
            // Also check all known prefixes for this DXCC number
            if let prefixes = prefixesByEntity[country.id] {
                for pfx in prefixes {
                    if base.hasPrefix(pfx), pfx.count > bestLength {
                        bestMatch = country
                        bestLength = pfx.count
                    }
                }
            }
        }
        return bestMatch
    }

    /// Search countries by name or prefix.
    public static func search(_ query: String) -> [PrefixCountry] {
        guard !query.isEmpty else {
            return sortedCountries
        }
        let upper = query.uppercased()
        let lower = query.lowercased()
        return sortedCountries.filter { country in
            country.name.lowercased().contains(lower)
                || country.prefix.uppercased().hasPrefix(upper)
        }
    }

    // MARK: Private

    /// Extended prefix list per entity for callsign matching.
    /// Maps DXCC number to all known prefixes (beyond the primary).
    private static let prefixesByEntity: [Int: [String]] = {
        var result: [Int: [String]] = [:]
        for (prefixes, entity) in DescriptionLookup.dxccEntities {
            result[entity.number] = prefixes
        }
        return result
    }()

    /// Haversine distance in kilometers between two coordinates.
    private static func haversineDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let earthRadius = 6_371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let radLat1 = lat1 * .pi / 180
        let radLat2 = lat2 * .pi / 180

        let sinDLat = sin(dLat / 2)
        let sinDLon = sin(dLon / 2)
        let aa = sinDLat * sinDLat + cos(radLat1) * cos(radLat2) * sinDLon * sinDLon
        let cc = 2 * atan2(sqrt(aa), sqrt(1 - aa))
        return earthRadius * cc
    }
}
