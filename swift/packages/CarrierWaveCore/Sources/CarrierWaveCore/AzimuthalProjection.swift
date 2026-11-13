// Azimuthal Equidistant Projection
//
// Pure math for projecting lat/lon onto a plane centered on the operator's QTH.
// Distances and bearings from center are preserved — ideal for ham radio maps.
// No UIKit/MapKit dependencies so it can be used from both iOS and macOS.

import Foundation

// MARK: - AzimuthalPoint

/// A point in azimuthal projection space (bearing + distance from center)
public struct AzimuthalPoint: Sendable, Equatable {
    // MARK: Lifecycle

    public init(bearing: Double, distanceKm: Double, normalizedRadius: Double) {
        self.bearing = bearing
        self.distanceKm = distanceKm
        self.normalizedRadius = normalizedRadius
    }

    // MARK: Public

    public let bearing: Double // degrees, 0 = North
    public let distanceKm: Double
    public let normalizedRadius: Double // 0.0–1.0, clamped to max distance
}

// MARK: - BearingSector

/// Aggregated data for one angular sector of the azimuthal view
public struct BearingSector: Sendable, Equatable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: Int,
        startBearing: Double,
        endBearing: Double,
        centerBearing: Double,
        spotCount: Int,
        qsoCount: Int,
        density: Double
    ) {
        self.id = id
        self.startBearing = startBearing
        self.endBearing = endBearing
        self.centerBearing = centerBearing
        self.spotCount = spotCount
        self.qsoCount = qsoCount
        self.density = density
    }

    // MARK: Public

    public let id: Int // sector index
    public let startBearing: Double
    public let endBearing: Double
    public let centerBearing: Double
    public let spotCount: Int
    public let qsoCount: Int
    public let density: Double // 0.0–1.0, relative to densest sector
}

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

    /// Maximum distance in km for default view (half of Earth's circumference)
    public static let earthHalfCircumferenceKm = 20_020.0

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

    /// Project a target grid square relative to a center grid, returning an AzimuthalPoint
    public static func project(
        from centerGrid: String,
        to targetGrid: String,
        maxDistanceKm: Double = earthHalfCircumferenceKm
    ) -> AzimuthalPoint? {
        guard let bearing = MaidenheadConverter.bearing(from: centerGrid, to: targetGrid),
              let distanceKm = MaidenheadConverter.distanceKm(from: centerGrid, to: targetGrid)
        else {
            return nil
        }
        let normalizedRadius = min(distanceKm / maxDistanceKm, 1.0)
        return AzimuthalPoint(
            bearing: bearing,
            distanceKm: distanceKm,
            normalizedRadius: normalizedRadius
        )
    }

    /// Project a target with known bearing and distance
    public static func project(
        bearing: Double,
        distanceKm: Double,
        maxDistanceKm: Double = earthHalfCircumferenceKm
    ) -> AzimuthalPoint {
        let normalizedRadius = min(distanceKm / maxDistanceKm, 1.0)
        return AzimuthalPoint(
            bearing: bearing,
            distanceKm: distanceKm,
            normalizedRadius: normalizedRadius
        )
    }

    /// Convert an azimuthal point to Cartesian coordinates for Canvas rendering.
    /// Origin at (centerX, centerY), north = up (-Y), east = right (+X).
    public static func cartesian(
        from point: AzimuthalPoint,
        centerX: Double,
        centerY: Double,
        viewRadius: Double
    ) -> (x: Double, y: Double) {
        let radians = point.bearing * .pi / 180.0
        let radius = point.normalizedRadius * viewRadius
        let x = centerX + radius * sin(radians)
        let y = centerY - radius * cos(radians)
        return (x, y)
    }

    /// Bin a collection of bearing values into angular sectors.
    /// - Parameters:
    ///   - items: Array of (bearing, isSpot) tuples. `isSpot` = true for spots, false for QSOs.
    ///   - sectorCount: Number of equal-width sectors (default 36 = 10° each)
    /// - Returns: Array of BearingSector with normalized density values
    public static func binIntoSectors(
        items: [(bearing: Double, isSpot: Bool)],
        sectorCount: Int = 36
    ) -> [BearingSector] {
        guard sectorCount > 0 else {
            return []
        }
        let sectorWidth = 360.0 / Double(sectorCount)

        // Count spots and QSOs per sector
        var spotCounts = [Int](repeating: 0, count: sectorCount)
        var qsoCounts = [Int](repeating: 0, count: sectorCount)

        for item in items {
            var bearing = item.bearing.truncatingRemainder(dividingBy: 360.0)
            if bearing < 0 {
                bearing += 360.0
            }
            let sectorIndex = min(Int(bearing / sectorWidth), sectorCount - 1)
            if item.isSpot {
                spotCounts[sectorIndex] += 1
            } else {
                qsoCounts[sectorIndex] += 1
            }
        }

        // Normalize density relative to the densest sector
        let maxCount = spotCounts.max() ?? 0
        let normalizer = maxCount > 0 ? Double(maxCount) : 1.0

        return (0 ..< sectorCount).map { i in
            let start = Double(i) * sectorWidth
            let end = start + sectorWidth
            return BearingSector(
                id: i,
                startBearing: start,
                endBearing: end,
                centerBearing: start + sectorWidth / 2.0,
                spotCount: spotCounts[i],
                qsoCount: qsoCounts[i],
                density: Double(spotCounts[i]) / normalizer
            )
        }
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

    /// Inverse-project a normalized (x, y) back to (latDeg, lonDeg).
    ///
    /// Takes normalized coordinates in approximately [-1, 1] where ±1
    /// represents π radians (antipodal distance). Returns nil for points
    /// beyond the antipode (outside the unit circle).
    ///
    /// Uses Snyder equations 24-16/24-17 for inverse azimuthal equidistant.
    public func inverseProject(nx: Double, ny: Double) -> (latDeg: Double, lonDeg: Double)? {
        // Scale from normalized [-1,1] back to angular distance
        let x = nx * .pi
        let y = ny * .pi
        let rho = sqrt(x * x + y * y)

        // Outside the projection circle (beyond antipode)
        if rho > .pi {
            return nil
        }

        // Center point
        if rho < 1e-10 {
            return (centerLat * 180 / .pi, centerLon * 180 / .pi)
        }

        let angularDist = rho // For azimuthal equidistant, c = rho
        let sinC = sin(angularDist)
        let cosC = cos(angularDist)

        // Snyder eq 24-16: lat = arcsin(cos(c)*sin(centerLat) + y*sin(c)*cos(centerLat)/rho)
        let lat = asin(cosC * sinCenterLat + y * sinC * cosCenterLat / rho)

        // Snyder eq 24-17: lon = centerLon + atan2(x*sin(c), rho*cos(centerLat)*cos(c) - y*sin(centerLat)*sin(c))
        var lon = centerLon + atan2(
            x * sinC,
            rho * cosCenterLat * cosC - y * sinCenterLat * sinC
        )

        // Normalize longitude to [-π, π]
        while lon > .pi {
            lon -= 2 * .pi
        }
        while lon < -.pi {
            lon += 2 * .pi
        }

        return (lat * 180 / .pi, lon * 180 / .pi)
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
