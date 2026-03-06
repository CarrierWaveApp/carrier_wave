//
//  AntennaPattern.swift
//  CarrierWaveCore
//

import Foundation

// MARK: - AntennaPattern

/// Simplified 2D azimuthal radiation pattern for common portable antenna types.
/// Returns relative gain (0.0–1.0) at a given bearing for pattern overlay visualization.
public enum AntennaPattern: Sendable, Equatable {
    /// Omnidirectional (vertical, mag loop, ground plane)
    case omnidirectional

    /// Figure-8 pattern (dipole, EFHW horizontal, longwire)
    /// `orientation` is the wire direction in degrees — maximum radiation is broadside (±90°)
    case figureEight(orientation: Double)

    /// Cardioid-like pattern (Yagi, Moxon, hex beam)
    /// `heading` is the direction of maximum gain, `beamwidthDeg` is the -3dB full beamwidth
    case cardioid(heading: Double, beamwidthDeg: Double)

    // MARK: Public

    /// Default pattern for a given antenna type
    /// - Parameters:
    ///   - antennaType: The antenna type from the parser
    ///   - orientationDeg: Wire/boom direction in degrees (from compass or user input)
    public static func defaultPattern(
        for antennaType: AntennaType,
        orientationDeg: Double = 0
    ) -> AntennaPattern {
        switch antennaType {
        case .vertical,
             .whip,
             .loop:
            .omnidirectional
        case .dipole,
             .endFed,
             .longwire,
             .beverage:
            .figureEight(orientation: orientationDeg)
        case .yagi:
            .cardioid(heading: orientationDeg, beamwidthDeg: 60)
        case .logPeriodic:
            .cardioid(heading: orientationDeg, beamwidthDeg: 70)
        case .hexBeam:
            .cardioid(heading: orientationDeg, beamwidthDeg: 80)
        case .unknown:
            .omnidirectional
        }
    }

    /// Relative gain at the given bearing (0–360°), normalized to 0.0–1.0
    public func gain(at bearing: Double) -> Double {
        switch self {
        case .omnidirectional:
            return 1.0

        case let .figureEight(orientation):
            // Max broadside to wire (±90° from wire direction)
            let broadsideBearing = normalizedAngle(orientation + 90.0)
            let delta = angleDifference(bearing, broadsideBearing)
            // cos² pattern: max at broadside, nulls along wire
            let cosVal = cos(delta * .pi / 180.0)
            return cosVal * cosVal

        case let .cardioid(heading, beamwidthDeg):
            let delta = angleDifference(bearing, heading)
            let absDelta = abs(delta)
            // Approximate cardioid: strong forward lobe, attenuated rear
            // Use cosine-based model with adjustable beamwidth
            let sigma = beamwidthDeg / 2.35 // FWHM to gaussian sigma approximation
            if sigma <= 0 {
                return 1.0
            }
            let gaussian = exp(-(absDelta * absDelta) / (2.0 * sigma * sigma))
            // Add a small rear lobe (~15% of forward gain, 180° offset)
            let rearDelta = angleDifference(bearing, normalizedAngle(heading + 180.0))
            let rearGaussian = exp(-(rearDelta * rearDelta) / (2.0 * sigma * sigma))
            return min(gaussian + 0.15 * rearGaussian, 1.0)
        }
    }

    /// Generate points for rendering the pattern as a closed polar shape.
    /// Returns an array of (angle, normalizedRadius) pairs at `steps` evenly-spaced bearings.
    public func polarPoints(steps: Int = 72) -> [(angle: Double, radius: Double)] {
        let stepSize = 360.0 / Double(steps)
        return (0 ..< steps).map { i in
            let angle = Double(i) * stepSize
            return (angle: angle, radius: gain(at: angle))
        }
    }

    // MARK: Private

    /// Normalize angle to [0, 360)
    private func normalizedAngle(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 360.0)
        if a < 0 {
            a += 360.0
        }
        return a
    }

    /// Signed angular difference, result in [-180, 180]
    private func angleDifference(_ a: Double, _ b: Double) -> Double {
        var diff = a - b
        diff = diff.truncatingRemainder(dividingBy: 360.0)
        if diff > 180.0 {
            diff -= 360.0
        }
        if diff < -180.0 {
            diff += 360.0
        }
        return diff
    }
}
