package app.carrierwave.android.sensors

import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Pure attitude math for the satellite sensor surfaces. Everything works
 * on 3×3 row-major [DoubleArray]s with the SAME semantics as the iOS
 * `CMAttitude.rotationMatrix` as consumed by `SkyProjector` /
 * `AntennaMotionService`: **reference → device**, reference frame
 * X = north, Y = west, Z = up. Android's
 * `SensorManager.getRotationMatrix*` yields device → ENU (X = east,
 * Y = magnetic north, Z = up); [referenceToDevice] converts — ENU→NWU
 * axis swap, magnetic→true rotation by the declination, then transpose —
 * so every iOS angle formula ports verbatim on top.
 */
object RotationMatrices {

    /** ENU → NWU axis swap: north = ENU.y, west = −ENU.x, up = ENU.z. */
    private val ENU_TO_NWU = doubleArrayOf(
        0.0, 1.0, 0.0,
        -1.0, 0.0, 0.0,
        0.0, 0.0, 1.0,
    )

    /**
     * Build the reference→device matrix from Android's device→ENU rotation
     * matrix and the local magnetic declination (degrees, positive when
     * magnetic north lies east of true north): `M = (Rz(−decl)·T·R)ᵀ`.
     */
    fun referenceToDevice(deviceToEnu: DoubleArray, declinationDeg: Double): DoubleArray {
        val declRad = -declinationDeg * Math.PI / 180.0
        val cosD = cos(declRad)
        val sinD = sin(declRad)
        val rotZ = doubleArrayOf(
            cosD, -sinD, 0.0,
            sinD, cosD, 0.0,
            0.0, 0.0, 1.0,
        )
        return transpose(multiply(rotZ, multiply(ENU_TO_NWU, deviceToEnu)))
    }

    /** Rotation-vector quaternion (x, y, z, w) → device→ENU matrix. */
    fun quaternionToMatrix(quat: DoubleArray): DoubleArray {
        val (x, y, z) = Triple(quat[0], quat[1], quat[2])
        val w = quat[3]
        return doubleArrayOf(
            1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y),
            2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x),
            2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y),
        )
    }

    /**
     * Quaternion slerp low-pass (α toward [target]) — smooths sensor jitter
     * without the gimbal artifacts of per-angle filtering. Both quaternions
     * are (x, y, z, w), unit length; result is normalized.
     */
    fun slerp(current: DoubleArray, target: DoubleArray, alpha: Double): DoubleArray {
        var dot = current[0] * target[0] + current[1] * target[1] +
            current[2] * target[2] + current[3] * target[3]
        // Take the short way around: q and −q are the same rotation.
        val sign = if (dot < 0) -1.0 else 1.0
        dot = abs(dot).coerceAtMost(1.0)
        if (dot > 0.9995) {
            // Nearly parallel — lerp + normalize avoids the 0/0.
            val blended = DoubleArray(4) { i ->
                current[i] + alpha * (sign * target[i] - current[i])
            }
            return normalize(blended)
        }
        val theta = acos(dot)
        val sinTheta = sin(theta)
        val weightCurrent = sin((1 - alpha) * theta) / sinTheta
        val weightTarget = sin(alpha * theta) / sinTheta * sign
        return normalize(
            DoubleArray(4) { i -> weightCurrent * current[i] + weightTarget * target[i] },
        )
    }

    // MARK: derived angles (verbatim ports of the iOS AntennaMotionService)

    /** Elevation of the back camera (device −Z) above the horizon, degrees. */
    fun pointingElevationDeg(m: DoubleArray): Double =
        asin((-m[8]).coerceIn(-1.0, 1.0)) * 180.0 / Math.PI

    /** Compass azimuth of the back camera, degrees CW from north; null at
     * the zenith. */
    fun pointingAzimuthDeg(m: DoubleArray): Double? {
        val north = -m[6]
        val east = m[7]
        if (abs(north) <= 1e-6 && abs(east) <= 1e-6) return null
        val azimuth = atan2(east, north) * 180.0 / Math.PI
        return if (azimuth < 0) azimuth + 360 else azimuth
    }

    /** Boom axis (device frame) expressed in the reference frame. */
    fun boomAxisReference(m: DoubleArray, axis: DoubleArray): DoubleArray = doubleArrayOf(
        axis[0] * m[0] + axis[1] * m[3] + axis[2] * m[6],
        axis[0] * m[1] + axis[1] * m[4] + axis[2] * m[7],
        axis[0] * m[2] + axis[1] * m[5] + axis[2] * m[8],
    )

    /** Elevation of the antenna boom axis above the horizon, degrees. */
    fun boomElevationDeg(m: DoubleArray, axis: DoubleArray): Double =
        asin(boomAxisReference(m, axis)[2].coerceIn(-1.0, 1.0)) * 180.0 / Math.PI

    /** Compass azimuth of the boom axis, degrees CW from north; null at
     * the zenith. */
    fun boomAzimuthDeg(m: DoubleArray, axis: DoubleArray): Double? {
        val ref = boomAxisReference(m, axis)
        val north = ref[0]
        val east = -ref[1]
        if (abs(north) <= 1e-6 && abs(east) <= 1e-6) return null
        val azimuth = atan2(east, north) * 180.0 / Math.PI
        return if (azimuth < 0) azimuth + 360 else azimuth
    }

    /** Tilt of device X away from horizontal, degrees — the polarization
     * roll for elements mounted along X. */
    fun elementTiltDeg(m: DoubleArray): Double =
        asin(m[2].coerceIn(-1.0, 1.0)) * 180.0 / Math.PI

    /** Blended screen heading (see the iOS doc: +Y dominant flat, −Z
     * dominant raised), degrees CW from north; null when degenerate. */
    fun screenHeadingDeg(m: DoubleArray): Double? {
        val north = m[3] - m[6]
        val east = -m[4] + m[7]
        if (abs(north) <= 1e-6 && abs(east) <= 1e-6) return null
        val heading = atan2(east, north) * 180.0 / Math.PI
        return if (heading < 0) heading + 360 else heading
    }

    // MARK: matrix helpers

    fun multiply(a: DoubleArray, b: DoubleArray): DoubleArray {
        val out = DoubleArray(9)
        for (row in 0..2) {
            for (col in 0..2) {
                out[row * 3 + col] = a[row * 3] * b[col] +
                    a[row * 3 + 1] * b[3 + col] +
                    a[row * 3 + 2] * b[6 + col]
            }
        }
        return out
    }

    fun transpose(m: DoubleArray): DoubleArray = doubleArrayOf(
        m[0], m[3], m[6],
        m[1], m[4], m[7],
        m[2], m[5], m[8],
    )

    private fun normalize(quat: DoubleArray): DoubleArray {
        val magnitude = sqrt(
            quat[0] * quat[0] + quat[1] * quat[1] + quat[2] * quat[2] + quat[3] * quat[3],
        )
        if (magnitude < 1e-12) return doubleArrayOf(0.0, 0.0, 0.0, 1.0)
        return DoubleArray(4) { i -> quat[i] / magnitude }
    }
}
