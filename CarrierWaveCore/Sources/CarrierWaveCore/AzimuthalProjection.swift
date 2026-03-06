//
//  AzimuthalProjection.swift
//  CarrierWaveCore
//

import Foundation

// MARK: - AzimuthalPoint

/// A point in azimuthal projection space (bearing + distance from center)
public struct AzimuthalPoint: Sendable, Equatable {
    public let bearing: Double // degrees, 0 = North
    public let distanceKm: Double
    public let normalizedRadius: Double // 0.0–1.0, clamped to max distance

    public init(bearing: Double, distanceKm: Double, normalizedRadius: Double) {
        self.bearing = bearing
        self.distanceKm = distanceKm
        self.normalizedRadius = normalizedRadius
    }
}

// MARK: - BearingSector

/// Aggregated data for one angular sector of the azimuthal view
public struct BearingSector: Sendable, Equatable, Identifiable {
    public let id: Int // sector index
    public let startBearing: Double
    public let endBearing: Double
    public let centerBearing: Double
    public let spotCount: Int
    public let qsoCount: Int
    public let density: Double // 0.0–1.0, relative to densest sector

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
}

// MARK: - AzimuthalProjection

/// Utility for projecting geographic points onto an azimuthal equidistant projection
/// centered on the operator's location.
public enum AzimuthalProjection {
    /// Maximum distance in km for default view (half of Earth's circumference)
    public static let earthHalfCircumferenceKm = 20_020.0

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
        let r = point.normalizedRadius * viewRadius
        let x = centerX + r * sin(radians)
        let y = centerY - r * cos(radians)
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
        guard sectorCount > 0 else { return [] }
        let sectorWidth = 360.0 / Double(sectorCount)

        // Count spots and QSOs per sector
        var spotCounts = [Int](repeating: 0, count: sectorCount)
        var qsoCounts = [Int](repeating: 0, count: sectorCount)

        for item in items {
            var bearing = item.bearing.truncatingRemainder(dividingBy: 360.0)
            if bearing < 0 { bearing += 360.0 }
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
            BearingSector(
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
}
