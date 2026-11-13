//
//  MaidenheadConverter.swift
//  CarrierWaveCore
//

import Foundation

// MARK: - Coordinate

/// A simple latitude/longitude coordinate (platform-agnostic alternative to CLLocationCoordinate2D)
public struct Coordinate: Sendable, Codable, Equatable {
    // MARK: Lifecycle

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    // MARK: Public

    public let latitude: Double
    public let longitude: Double
}

// MARK: - MaidenheadConverter

/// Converts Maidenhead grid locators to coordinates
public enum MaidenheadConverter: Sendable {
    // MARK: Public

    /// Maidenhead locator precision. 4 = field+square (e.g. `FN31`),
    /// 6 = + subsquare (e.g. `FN31pr`), 8 = + extended subsquare (e.g. `FN31pr12`).
    /// 6 is the conventional default for HF logging; 8 is useful for VHF/UHF
    /// and grid-square contests where ~5×2.5 km isn't precise enough.
    public enum Precision: Int, Sendable, CaseIterable {
        case four = 4
        case six = 6
        case eight = 8
    }

    /// Convert a Maidenhead grid locator to coordinates (center of grid square)
    /// Supports 4-char (e.g., `FN31`), 6-char (e.g., `FN31pr`), and 8-char
    /// extended-subsquare (e.g., `FN31pr12`) formats.
    /// - Parameter grid: The grid locator string (case insensitive)
    /// - Returns: The center coordinate of the grid square, or nil if invalid
    public static func coordinate(from grid: String) -> Coordinate? {
        let grid = grid.uppercased()
        guard let base = parseFieldSquare(grid) else {
            return nil
        }
        var longitude = Double(base.lonField * 20 - 180 + base.lonSquare * 2)
        var latitude = Double(base.latField * 10 - 90 + base.latSquare)

        let chars = Array(grid)
        guard grid.count >= 6,
              let sub = parseSubsquare(chars: chars)
        else {
            // 4-char grid (or invalid subsquare): center of 2°×1° square
            longitude += 1.0
            latitude += 0.5
            return Coordinate(latitude: latitude, longitude: longitude)
        }

        let subsquareLonStep = 2.0 / 24.0
        let subsquareLatStep = 1.0 / 24.0
        longitude += Double(sub.lon) * subsquareLonStep
        latitude += Double(sub.lat) * subsquareLatStep

        guard grid.count >= 8,
              let ext = parseExtendedSubsquare(chars: chars)
        else {
            // 6-char grid: center of subsquare
            longitude += subsquareLonStep / 2.0
            latitude += subsquareLatStep / 2.0
            return Coordinate(latitude: latitude, longitude: longitude)
        }

        // 8-char extended subsquare: 1/10×1/10 of a subsquare; report center.
        let extLonStep = subsquareLonStep / 10.0
        let extLatStep = subsquareLatStep / 10.0
        longitude += Double(ext.lon) * extLonStep + extLonStep / 2.0
        latitude += Double(ext.lat) * extLatStep + extLatStep / 2.0
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    /// Convert a coordinate to a Maidenhead grid locator at the requested precision.
    /// - Parameters:
    ///   - coordinate: The latitude/longitude coordinate
    ///   - precision: 4-, 6-, or 8-character output. Defaults to 6 for back-compat.
    /// - Returns: Grid locator string at the requested length
    public static func grid(
        from coordinate: Coordinate, precision: Precision = .six
    ) -> String {
        // Normalize: longitude to 0..360, latitude to 0..180
        let lon = coordinate.longitude + 180.0
        let lat = coordinate.latitude + 90.0

        // Field (A-R): 20° longitude, 10° latitude
        let lonField = Int(lon / 20.0)
        let latField = Int(lat / 10.0)

        // Square (0-9): 2° longitude, 1° latitude
        let lonSquare = Int((lon - Double(lonField) * 20.0) / 2.0)
        let latSquare = Int((lat - Double(latField) * 10.0) / 1.0)

        let field1 = Character(UnicodeScalar(65 + min(lonField, 17))!)
        let field2 = Character(UnicodeScalar(65 + min(latField, 17))!)
        let square1 = Character(UnicodeScalar(48 + min(lonSquare, 9))!)
        let square2 = Character(UnicodeScalar(48 + min(latSquare, 9))!)

        if precision == .four {
            return String([field1, field2, square1, square2])
        }

        // Subsquare (a-x): 5' longitude, 2.5' latitude
        let lonRemainder = lon - Double(lonField) * 20.0 - Double(lonSquare) * 2.0
        let latRemainder = lat - Double(latField) * 10.0 - Double(latSquare) * 1.0
        let subsquareLonStep = 2.0 / 24.0
        let subsquareLatStep = 1.0 / 24.0
        let lonSubsquare = Int(lonRemainder / subsquareLonStep)
        let latSubsquare = Int(latRemainder / subsquareLatStep)
        let sub1 = Character(UnicodeScalar(97 + min(lonSubsquare, 23))!)
        let sub2 = Character(UnicodeScalar(97 + min(latSubsquare, 23))!)

        if precision == .six {
            return String([field1, field2, square1, square2, sub1, sub2])
        }

        // Extended subsquare (0-9): 1/10th of a subsquare on each axis
        let lonExtRemainder = lonRemainder - Double(lonSubsquare) * subsquareLonStep
        let latExtRemainder = latRemainder - Double(latSubsquare) * subsquareLatStep
        let lonExt = Int(lonExtRemainder / (subsquareLonStep / 10.0))
        let latExt = Int(latExtRemainder / (subsquareLatStep / 10.0))
        let ext1 = Character(UnicodeScalar(48 + min(lonExt, 9))!)
        let ext2 = Character(UnicodeScalar(48 + min(latExt, 9))!)

        return String([field1, field2, square1, square2, sub1, sub2, ext1, ext2])
    }

    /// Check if a grid locator string is valid
    public static func isValid(_ grid: String) -> Bool {
        coordinate(from: grid) != nil
    }

    /// Returns the southwest and northeast corners of a 4-char grid square.
    /// - Parameter grid: A 4-character Maidenhead locator (e.g., "FN31")
    /// - Returns: Tuple of (southwest, northeast) corners, or nil if invalid
    public static func gridBounds(
        for grid: String
    ) -> (sw: Coordinate, ne: Coordinate)? {
        let grid = grid.uppercased()
        guard grid.count >= 4 else {
            return nil
        }
        let chars = Array(grid)

        guard let lonField = chars[0].asciiValue.map({ Int($0) - 65 }),
              let latField = chars[1].asciiValue.map({ Int($0) - 65 }),
              lonField >= 0, lonField < 18,
              latField >= 0, latField < 18,
              let lonSquare = chars[2].wholeNumberValue,
              let latSquare = chars[3].wholeNumberValue
        else {
            return nil
        }

        let swLon = Double(lonField * 20 - 180 + lonSquare * 2)
        let swLat = Double(latField * 10 - 90 + latSquare)
        let neLon = swLon + 2.0
        let neLat = swLat + 1.0

        return (
            sw: Coordinate(latitude: swLat, longitude: swLon),
            ne: Coordinate(latitude: neLat, longitude: neLon)
        )
    }

    /// Returns the southwest and northeast corners of a 6-char Maidenhead tile.
    /// - Parameter tile: A 6-character locator (e.g., "EM73uu").
    /// - Returns: Tuple of (southwest, northeast) corners, or nil if invalid.
    public static func tileBounds(
        for tile: String
    ) -> (sw: Coordinate, ne: Coordinate)? {
        let upper = tile.uppercased()
        guard upper.count >= 6 else {
            return nil
        }
        let chars = Array(upper)

        guard let lonField = chars[0].asciiValue.map({ Int($0) - 65 }),
              let latField = chars[1].asciiValue.map({ Int($0) - 65 }),
              lonField >= 0, lonField < 18,
              latField >= 0, latField < 18,
              let lonSquare = chars[2].wholeNumberValue,
              let latSquare = chars[3].wholeNumberValue,
              let lonSubsquare = chars[4].asciiValue.map({ Int($0) - 65 }),
              let latSubsquare = chars[5].asciiValue.map({ Int($0) - 65 }),
              lonSubsquare >= 0, lonSubsquare < 24,
              latSubsquare >= 0, latSubsquare < 24
        else {
            return nil
        }

        let swLon = Double(lonField * 20 - 180 + lonSquare * 2)
            + Double(lonSubsquare) * (2.0 / 24.0)
        let swLat = Double(latField * 10 - 90 + latSquare)
            + Double(latSubsquare) * (1.0 / 24.0)
        let neLon = swLon + (2.0 / 24.0)
        let neLat = swLat + (1.0 / 24.0)

        return (
            sw: Coordinate(latitude: swLat, longitude: swLon),
            ne: Coordinate(latitude: neLat, longitude: neLon)
        )
    }

    /// Enumerate all 4-char grid locators visible within a coordinate region.
    /// - Parameters:
    ///   - sw: Southwest corner of the visible region
    ///   - ne: Northeast corner of the visible region
    /// - Returns: Array of 4-char grid locator strings
    public static func gridsInRegion(
        sw: Coordinate, ne: Coordinate
    ) -> [String] {
        // Clamp to valid Maidenhead field ranges
        let minLat = max(sw.latitude, -90)
        let maxLat = min(ne.latitude, 90)
        let minLon = max(sw.longitude, -180)
        let maxLon = min(ne.longitude, 180)

        // Each 4-char grid is 2° lon × 1° lat
        let startLon = Int(floor((minLon + 180) / 2.0))
        let endLon = Int(floor((maxLon + 180) / 2.0))
        let startLat = Int(floor((minLat + 90) / 1.0))
        let endLat = Int(floor((maxLat + 90) / 1.0))

        // Safety: don't generate more than ~2000 grids
        let count = (endLon - startLon + 1) * (endLat - startLat + 1)
        guard count > 0, count <= 2_000 else {
            return []
        }

        var grids: [String] = []
        grids.reserveCapacity(count)

        for lonIdx in startLon ... endLon {
            let field1 = lonIdx / 10
            let square1 = lonIdx % 10
            guard field1 >= 0, field1 < 18 else {
                continue
            }

            for latIdx in startLat ... endLat {
                let field2 = latIdx / 10
                let square2 = latIdx % 10
                guard field2 >= 0, field2 < 18 else {
                    continue
                }

                let ch1 = Character(UnicodeScalar(65 + field1)!)
                let ch2 = Character(UnicodeScalar(65 + field2)!)
                grids.append("\(ch1)\(ch2)\(square1)\(square2)")
            }
        }
        return grids
    }

    // MARK: Private

    /// Field+square decomposition of a Maidenhead string (first 4 chars).
    private struct FieldSquare {
        let lonField: Int
        let latField: Int
        let lonSquare: Int
        let latSquare: Int
    }

    /// Parse the field+square (first 4 chars) of a Maidenhead grid string.
    /// Returns nil if the field letters or square digits are out of range.
    private static func parseFieldSquare(_ grid: String) -> FieldSquare? {
        guard grid.count >= 4 else {
            return nil
        }
        let chars = Array(grid)
        guard let lonField = chars[0].asciiValue.map({ Int($0) - 65 }),
              let latField = chars[1].asciiValue.map({ Int($0) - 65 }),
              lonField >= 0, lonField < 18,
              latField >= 0, latField < 18,
              let lonSquare = chars[2].wholeNumberValue,
              let latSquare = chars[3].wholeNumberValue
        else {
            return nil
        }
        return FieldSquare(
            lonField: lonField, latField: latField,
            lonSquare: lonSquare, latSquare: latSquare
        )
    }

    /// Parse subsquare letters (chars 5–6, A–X). Returns nil if out of range.
    private static func parseSubsquare(
        chars: [Character]
    ) -> (lon: Int, lat: Int)? {
        guard chars.count >= 6,
              let lon = chars[4].asciiValue.map({ Int($0) - 65 }),
              let lat = chars[5].asciiValue.map({ Int($0) - 65 }),
              lon >= 0, lon < 24, lat >= 0, lat < 24
        else {
            return nil
        }
        return (lon, lat)
    }

    /// Parse extended subsquare digits (chars 7–8, 0–9). Returns nil if out of range.
    private static func parseExtendedSubsquare(
        chars: [Character]
    ) -> (lon: Int, lat: Int)? {
        guard chars.count >= 8,
              let lon = chars[6].wholeNumberValue,
              let lat = chars[7].wholeNumberValue,
              lon >= 0, lon < 10, lat >= 0, lat < 10
        else {
            return nil
        }
        return (lon, lat)
    }
}

// MARK: - Distance & Bearing

public extension MaidenheadConverter {
    /// Haversine distance in kilometers between two Maidenhead grid squares
    /// - Returns: Distance in km, or nil if either grid is invalid
    static func distanceKm(from grid1: String, to grid2: String) -> Double? {
        guard let c1 = coordinate(from: grid1),
              let c2 = coordinate(from: grid2)
        else {
            return nil
        }
        return haversineKm(c1, c2)
    }

    /// Distance in miles between two Maidenhead grid squares
    /// - Returns: Distance in miles, or nil if either grid is invalid
    static func distanceMiles(from grid1: String, to grid2: String) -> Double? {
        guard let km = distanceKm(from: grid1, to: grid2) else {
            return nil
        }
        return km * 0.621371
    }

    /// Initial bearing (forward azimuth) in degrees from one grid to another
    /// - Returns: Bearing in degrees (0-360), or nil if either grid is invalid
    static func bearing(from grid1: String, to grid2: String) -> Double? {
        guard let c1 = coordinate(from: grid1),
              let c2 = coordinate(from: grid2)
        else {
            return nil
        }
        return initialBearing(c1, c2)
    }
}

// MARK: - Private Helpers

private extension MaidenheadConverter {
    static let earthRadiusKm = 6_371.0

    /// Haversine formula for great-circle distance between two coordinates
    static func haversineKm(_ c1: Coordinate, _ c2: Coordinate) -> Double {
        let lat1 = c1.latitude * .pi / 180.0
        let lat2 = c2.latitude * .pi / 180.0
        let dLat = (c2.latitude - c1.latitude) * .pi / 180.0
        let dLon = (c2.longitude - c1.longitude) * .pi / 180.0

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let angularDistance = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadiusKm * angularDistance
    }

    /// Initial bearing (forward azimuth) from c1 to c2, in degrees 0-360
    static func initialBearing(_ c1: Coordinate, _ c2: Coordinate) -> Double {
        let lat1 = c1.latitude * .pi / 180.0
        let lat2 = c2.latitude * .pi / 180.0
        let dLon = (c2.longitude - c1.longitude) * .pi / 180.0

        let x = sin(dLon) * cos(lat2)
        let y = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)

        let bearing = atan2(x, y) * 180.0 / .pi
        return (bearing + 360.0).truncatingRemainder(dividingBy: 360.0)
    }
}
