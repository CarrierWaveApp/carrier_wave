// Azimuthal Equidistant Projection
//
// Pure math for projecting lat/lon onto a plane centered on the operator's QTH.
// Distances and bearings from center are preserved — ideal for ham radio maps.
// No UIKit/MapKit dependencies so it can be used from both iOS and macOS.

import Foundation

// MARK: - AzimuthalProjection

/// Projects lat/lon coordinates onto an azimuthal equidistant plane.
///
/// Center point is preserved exactly; all other points are placed at
/// their correct bearing and great-circle distance from center.
/// Coordinates are returned in normalized [-1, 1] range where ±1
/// represents the antipodal distance (π radians ≈ 20,000 km).
public struct AzimuthalProjection {
    // MARK: Lifecycle

    /// Create a projection centered on the given coordinates (in degrees).
    public init(centerLatDeg: Double, centerLonDeg: Double) {
        centerLat = centerLatDeg * .pi / 180
        centerLon = centerLonDeg * .pi / 180
        cosCenterLat = cos(centerLat)
        sinCenterLat = sin(centerLat)
    }

    // MARK: Public

    // MARK: - Great Circle Path

    /// Generate a geodesic path between two points (degrees).
    /// Returns an array of (lat, lon) pairs in degrees.
    public static func greatCirclePath(
        fromLat lat1Deg: Double, fromLon lon1Deg: Double,
        toLat lat2Deg: Double, toLon lon2Deg: Double,
        segments: Int = 50
    ) -> [(lat: Double, lon: Double)] {
        let lat1 = lat1Deg * .pi / 180
        let lon1 = lon1Deg * .pi / 180
        let lat2 = lat2Deg * .pi / 180
        let lon2 = lon2Deg * .pi / 180

        let dist = angularDistance(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2)
        guard dist > 1e-10 else {
            return [(lat1Deg, lon1Deg), (lat2Deg, lon2Deg)]
        }

        let sinDist = sin(dist)
        var path: [(lat: Double, lon: Double)] = []
        path.reserveCapacity(segments + 1)

        for i in 0 ... segments {
            let frac = Double(i) / Double(segments)
            let a = sin((1 - frac) * dist) / sinDist
            let b = sin(frac * dist) / sinDist

            let x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
            let y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
            let z = a * sin(lat1) + b * sin(lat2)

            let lat = atan2(z, sqrt(x * x + y * y)) * 180 / .pi
            let lon = atan2(y, x) * 180 / .pi
            path.append((lat, lon))
        }

        return path
    }

    /// Project a point (degrees) onto the plane.
    /// Returns normalized (x, y) in approximately [-1, 1].
    /// Returns nil only for the exact antipodal point (undefined azimuth).
    public func project(latDeg: Double, lonDeg: Double) -> (x: Double, y: Double)? {
        let lat = latDeg * .pi / 180
        let lon = lonDeg * .pi / 180
        let dLon = lon - centerLon

        let cosLat = cos(lat)
        let sinLat = sin(lat)
        let cosDLon = cos(dLon)
        let sinDLon = sin(dLon)

        // Angular distance from center
        let cosAng = sinCenterLat * sinLat + cosCenterLat * cosLat * cosDLon
        let angDist = acos(min(1, max(-1, cosAng)))

        // Antipodal point — azimuth is undefined
        if angDist > .pi - 1e-10 {
            return nil
        }

        // Center point
        if angDist < 1e-10 {
            return (0, 0)
        }

        let sinAng = sin(angDist)
        // k scales the angular distance to the projected radius
        let kScale = angDist / sinAng

        let x = kScale * cosLat * sinDLon
        // y positive = north
        let y = kScale * (cosCenterLat * sinLat - sinCenterLat * cosLat * cosDLon)

        // Normalize so that π (half the earth) maps to 1.0
        return (x / .pi, y / .pi)
    }

    // MARK: Private

    private let centerLat: Double
    private let centerLon: Double
    private let cosCenterLat: Double
    private let sinCenterLat: Double

    private static func angularDistance(
        lat1: Double, lon1: Double, lat2: Double, lon2: Double
    ) -> Double {
        2 * asin(sqrt(
            pow(sin((lat2 - lat1) / 2), 2)
                + cos(lat1) * cos(lat2) * pow(sin((lon2 - lon1) / 2), 2)
        ))
    }
}
