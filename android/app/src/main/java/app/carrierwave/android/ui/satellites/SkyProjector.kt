package app.carrierwave.android.ui.satellites

import kotlin.math.acos
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * Pinhole projection from sky coordinates (az/el) into screen points,
 * looking along the device's back camera (−Z), screen up = device +Y —
 * line-for-line port of the iOS `SkyProjector` (pure math, no Compose
 * types). The matrix is reference→device, reference X = north, Y = west,
 * Z = up ([app.carrierwave.android.sensors.RotationMatrices] semantics).
 */
class SkyProjector(
    private val matrix: DoubleArray,
    private val widthPx: Float,
    private val heightPx: Float,
    private val boomAxis: DoubleArray = doubleArrayOf(0.0, 1.0, 0.0),
) {
    /** ~70° vertical field of view. */
    private val focal: Double = (heightPx / 2.0) / tan(35.0 * Math.PI / 180.0)

    /** Sky direction in the device frame. */
    fun deviceVector(azDeg: Double, elDeg: Double): DoubleArray {
        val ref = referenceVector(azDeg, elDeg)
        return doubleArrayOf(
            matrix[0] * ref[0] + matrix[1] * ref[1] + matrix[2] * ref[2],
            matrix[3] * ref[0] + matrix[4] * ref[1] + matrix[5] * ref[2],
            matrix[6] * ref[0] + matrix[7] * ref[1] + matrix[8] * ref[2],
        )
    }

    /** Screen point (x, y) for a sky direction, null when behind the viewer. */
    fun project(azDeg: Double, elDeg: Double): Pair<Float, Float>? {
        val vector = deviceVector(azDeg, elDeg)
        if (vector[2] >= -0.05) return null
        return Pair(
            (widthPx / 2 + focal * (vector[0] / -vector[2])).toFloat(),
            (heightPx / 2 - focal * (vector[1] / -vector[2])).toFloat(),
        )
    }

    /** Angular separation (degrees) between the pointing axis (−Z) and a
     * sky direction. */
    fun offAxisDeg(azDeg: Double, elDeg: Double): Double {
        val vector = deviceVector(azDeg, elDeg)
        return acos((-vector[2]).coerceIn(-1.0, 1.0)) * 180.0 / Math.PI
    }

    /** Angular separation (degrees) between the boom axis and a sky
     * direction — the pointing screen's boresight. */
    fun boomOffAxisDeg(azDeg: Double, elDeg: Double): Double {
        val vector = deviceVector(azDeg, elDeg)
        return acos(dot(vector, boomAxis).coerceIn(-1.0, 1.0)) * 180.0 / Math.PI
    }

    /**
     * Screen point for a sky direction on the boom-boresight targeting
     * display (forward = device +Y). Null behind the antenna; centered
     * when the boom is on target. The transverse basis is world-stabilized
     * so twisting the phone about the boom (polarization peaking) doesn't
     * spin the display.
     */
    fun boomProject(azDeg: Double, elDeg: Double): Pair<Float, Float>? {
        val target = referenceVector(azDeg, elDeg)
        // Boom axis in the reference frame: device-frame components
        // weighted over the matrix rows (rows = device axes in ref).
        val forward = doubleArrayOf(
            boomAxis[0] * matrix[0] + boomAxis[1] * matrix[3] + boomAxis[2] * matrix[6],
            boomAxis[0] * matrix[1] + boomAxis[1] * matrix[4] + boomAxis[2] * matrix[7],
            boomAxis[0] * matrix[2] + boomAxis[1] * matrix[5] + boomAxis[2] * matrix[8],
        )
        val depth = dot(target, forward)
        if (depth <= 0.05) return null
        var right = cross(forward, doubleArrayOf(0.0, 0.0, 1.0))
        val rightLength = sqrt(dot(right, right))
        if (rightLength <= 1e-3) {
            // Boom at the zenith: world roll is undefined; fall back to
            // the device's own transverse axes.
            val vector = deviceVector(azDeg, elDeg)
            return Pair(
                (widthPx / 2 + focal * (vector[0] / vector[1])).toFloat(),
                (heightPx / 2 - focal * (vector[2] / vector[1])).toFloat(),
            )
        }
        right = doubleArrayOf(right[0] / rightLength, right[1] / rightLength, right[2] / rightLength)
        val up = cross(right, forward)
        return Pair(
            (widthPx / 2 + focal * (dot(target, right) / depth)).toFloat(),
            (heightPx / 2 - focal * (dot(target, up) / depth)).toFloat(),
        )
    }

    /** Screen-space unit direction from center toward a sky point, for
     * the off-screen guidance arrow: (dx, dy). */
    fun screenDirection(azDeg: Double, elDeg: Double): Pair<Float, Float> {
        val vector = deviceVector(azDeg, elDeg)
        val length = max(1e-4, sqrt(vector[0] * vector[0] + vector[1] * vector[1]))
        return Pair((vector[0] / length).toFloat(), (-vector[1] / length).toFloat())
    }

    companion object {
        /** Sky direction in the reference frame (X=north, Y=west, Z=up). */
        fun referenceVector(azDeg: Double, elDeg: Double): DoubleArray {
            val azRad = azDeg * Math.PI / 180.0
            val elRad = elDeg * Math.PI / 180.0
            val north = cos(elRad) * cos(azRad)
            val east = cos(elRad) * sin(azRad)
            return doubleArrayOf(north, -east, sin(elRad))
        }

        private fun dot(a: DoubleArray, b: DoubleArray): Double =
            a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

        private fun cross(a: DoubleArray, b: DoubleArray): DoubleArray = doubleArrayOf(
            a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0],
        )
    }
}
