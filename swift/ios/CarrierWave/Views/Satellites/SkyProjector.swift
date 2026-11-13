import CoreMotion
import SwiftUI

// MARK: - SkySighting

/// A satellite with its interpolated az/el at render time.
nonisolated struct SkySighting {
    let position: SatellitePosition
    let azDeg: Double
    let elDeg: Double
}

// MARK: - SkyProjector

/// Pinhole projection from sky coordinates (az/el) into screen points,
/// looking along the device's back camera (−Z), screen up = device +Y.
nonisolated struct SkyProjector {
    // MARK: Lifecycle

    init(matrix: CMRotationMatrix, size: CGSize, boomAxis: SIMD3<Double> = SIMD3(0, 1, 0)) {
        self.matrix = matrix
        self.size = size
        self.boomAxis = boomAxis
        // ~70° vertical field of view.
        focal = (size.height / 2) / tan(35 * Double.pi / 180)
    }

    // MARK: Internal

    /// Sky direction in the device frame. Reference: X=north, Y=west, Z=up.
    func deviceVector(azDeg: Double, elDeg: Double) -> SIMD3<Double> {
        let ref = Self.referenceVector(azDeg: azDeg, elDeg: elDeg)
        return SIMD3(
            matrix.m11 * ref.x + matrix.m12 * ref.y + matrix.m13 * ref.z,
            matrix.m21 * ref.x + matrix.m22 * ref.y + matrix.m23 * ref.z,
            matrix.m31 * ref.x + matrix.m32 * ref.y + matrix.m33 * ref.z
        )
    }

    /// Screen point for a sky direction, nil when behind the viewer.
    func project(azDeg: Double, elDeg: Double) -> CGPoint? {
        let vector = deviceVector(azDeg: azDeg, elDeg: elDeg)
        guard vector.z < -0.05 else {
            return nil
        }
        return CGPoint(
            x: size.width / 2 + focal * (vector.x / -vector.z),
            y: size.height / 2 - focal * (vector.y / -vector.z)
        )
    }

    /// Angular separation (degrees) between the pointing axis (−Z) and a
    /// sky direction.
    func offAxisDeg(azDeg: Double, elDeg: Double) -> Double {
        let vector = deviceVector(azDeg: azDeg, elDeg: elDeg)
        return acos(max(-1, min(1, -vector.z))) * 180 / .pi
    }

    /// Angular separation (degrees) between the boom axis and a sky
    /// direction — the pointing screen's boresight, with the phone lying
    /// flat on the antenna boom (trim-calibrated axis when available).
    func boomOffAxisDeg(azDeg: Double, elDeg: Double) -> Double {
        let vector = deviceVector(azDeg: azDeg, elDeg: elDeg)
        return acos(max(-1, min(1, Self.dot(vector, boomAxis)))) * 180 / .pi
    }

    /// Screen point for a sky direction on the boom-boresight targeting
    /// display (forward = device +Y). Nil behind the antenna; centered
    /// when the boom is on target. The transverse basis is world-
    /// stabilized — screen right = horizontal right of the boom, screen
    /// up = sky-up — so twisting the phone about the boom (polarization
    /// peaking) doesn't spin the display.
    func boomProject(azDeg: Double, elDeg: Double) -> CGPoint? {
        let target = Self.referenceVector(azDeg: azDeg, elDeg: elDeg)
        // Boom axis in the reference frame: device-frame components
        // weighted over the matrix rows (rows = device axes in ref).
        let forward = SIMD3(
            boomAxis.x * matrix.m11 + boomAxis.y * matrix.m21 + boomAxis.z * matrix.m31,
            boomAxis.x * matrix.m12 + boomAxis.y * matrix.m22 + boomAxis.z * matrix.m32,
            boomAxis.x * matrix.m13 + boomAxis.y * matrix.m23 + boomAxis.z * matrix.m33
        )
        let depth = Self.dot(target, forward)
        guard depth > 0.05 else {
            return nil
        }
        var right = Self.cross(forward, SIMD3(0, 0, 1))
        let rightLength = (Self.dot(right, right)).squareRoot()
        guard rightLength > 1e-3 else {
            // Boom at the zenith: world roll is undefined; fall back to
            // the device's own transverse axes.
            let vector = deviceVector(azDeg: azDeg, elDeg: elDeg)
            return CGPoint(
                x: size.width / 2 + focal * (vector.x / vector.y),
                y: size.height / 2 - focal * (vector.z / vector.y)
            )
        }
        right /= rightLength
        let up = Self.cross(right, forward)
        return CGPoint(
            x: size.width / 2 + focal * (Self.dot(target, right) / depth),
            y: size.height / 2 - focal * (Self.dot(target, up) / depth)
        )
    }

    /// Screen-space direction from center toward a sky point, for the
    /// off-screen guidance arrow.
    func screenDirection(azDeg: Double, elDeg: Double) -> CGVector {
        let vector = deviceVector(azDeg: azDeg, elDeg: elDeg)
        let length = max(0.0001, sqrt(vector.x * vector.x + vector.y * vector.y))
        return CGVector(dx: vector.x / length, dy: -vector.y / length)
    }

    // MARK: Private

    private let matrix: CMRotationMatrix
    private let size: CGSize
    private let focal: Double
    /// Boresight for the boom projections, in the device frame.
    private let boomAxis: SIMD3<Double>

    /// Sky direction in the reference frame (X=north, Y=west, Z=up).
    private static func referenceVector(azDeg: Double, elDeg: Double) -> SIMD3<Double> {
        let azRad = azDeg * .pi / 180
        let elRad = elDeg * .pi / 180
        let north = cos(elRad) * cos(azRad)
        let east = cos(elRad) * sin(azRad)
        let vertical = sin(elRad)
        return SIMD3(north, -east, vertical)
    }

    private static func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    private static func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
    }
}
