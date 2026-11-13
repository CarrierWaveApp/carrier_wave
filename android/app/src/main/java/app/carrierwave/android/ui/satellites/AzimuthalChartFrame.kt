package app.carrierwave.android.ui.satellites

import kotlin.math.PI
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Azimuthal-equidistant projection centered on the observer: bearing from
 * the observer is the screen angle, great-circle distance is the radius.
 * Line-for-line port of the iOS `AzimuthalChartFrame.swift` (pure math, no
 * Compose types — JVM unit-testable). The chart passes `headingDeg = 0`
 * (north-up); the sensor surfaces can reuse the class with a live heading.
 */
class AzimuthalChartFrame(
    widthPx: Float,
    heightPx: Float,
    observerLatDeg: Double,
    observerLonDeg: Double,
    headingDeg: Double,
    val zoom: Float,
) {
    val screenCenterX: Float = widthPx / 2f
    val screenCenterY: Float = heightPx / 2f
    val diskRadius: Float
    val compassRadius: Float
    private val headingRad: Double = headingDeg * PI / 180.0
    private val observerLatRad: Double = observerLatDeg * PI / 180.0
    private val observerLonRad: Double = observerLonDeg * PI / 180.0

    init {
        val baseRadius = max(1f, min(widthPx, heightPx) / 2f - 18f)
        diskRadius = baseRadius * zoom
        compassRadius = min(diskRadius + 11f, baseRadius + 7f)
    }

    /** Inverse projection: the lat/lon under a screen point (drag-to-pan). */
    fun coordinateAt(x: Float, y: Float): Pair<Double, Double> {
        val deltaX = (x - screenCenterX).toDouble()
        val deltaY = (y - screenCenterY).toDouble()
        val radius = hypot(deltaX, deltaY)
        if (radius <= 0.5) {
            return Pair(observerLatRad * 180.0 / PI, observerLonRad * 180.0 / PI)
        }
        val bearing = atan2(deltaX, -deltaY) + headingRad
        val angular = min(radius / diskRadius.toDouble() * PI, PI * 0.999)
        val lat = asin(
            sin(observerLatRad) * cos(angular) + cos(observerLatRad) * sin(angular) * cos(bearing),
        )
        val lon = observerLonRad + atan2(
            sin(bearing) * sin(angular) * cos(observerLatRad),
            cos(angular) - sin(observerLatRad) * sin(lat),
        )
        var lonDeg = lon * 180.0 / PI
        if (lonDeg > 180) lonDeg -= 360
        if (lonDeg < -180) lonDeg += 360
        return Pair(lat * 180.0 / PI, lonDeg)
    }

    /** Compass letters anchor to the screen center. */
    fun compassPoint(bearingDeg: Double): Pair<Float, Float> {
        val angle = bearingDeg * PI / 180.0 - headingRad
        return Pair(
            screenCenterX + compassRadius * sin(angle).toFloat(),
            screenCenterY - compassRadius * cos(angle).toFloat(),
        )
    }

    /** Angular distance (radians) from the observer to a point. */
    fun angularDistance(latDeg: Double, lonDeg: Double): Double {
        val lat = latDeg * PI / 180.0
        val lonDelta = lonDeg * PI / 180.0 - observerLonRad
        val cosine = sin(observerLatRad) * sin(lat) +
            cos(observerLatRad) * cos(lat) * cos(lonDelta)
        return acos(cosine.coerceIn(-1.0, 1.0))
    }

    /** Screen position of a lat/lon under the current rotation. */
    fun point(latDeg: Double, lonDeg: Double): Pair<Float, Float> {
        val lat = latDeg * PI / 180.0
        val lonDelta = lonDeg * PI / 180.0 - observerLonRad
        val bearing = atan2(
            sin(lonDelta) * cos(lat),
            cos(observerLatRad) * sin(lat) - sin(observerLatRad) * cos(lat) * cos(lonDelta),
        )
        val radius = (angularDistance(latDeg, lonDeg) / PI).toFloat() * diskRadius
        val angle = bearing - headingRad
        return Pair(
            screenCenterX + radius * sin(angle).toFloat(),
            screenCenterY - radius * cos(angle).toFloat(),
        )
    }

    /** Screen position at a given distance ring and compass bearing. */
    fun ringPoint(bearingDeg: Double, radius: Float): Pair<Float, Float> {
        val angle = bearingDeg * PI / 180.0 - headingRad
        return Pair(
            screenCenterX + radius * sin(angle).toFloat(),
            screenCenterY - radius * cos(angle).toFloat(),
        )
    }

    companion object {
        /** Half the Earth's circumference — the antipode lands on the rim. */
        const val MAX_DISTANCE_KM = PI * 6_371.0
    }
}
