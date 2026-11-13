package app.carrierwave.android.ui.satellites

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.hypot

/**
 * Geometry invariants of the azimuthal-equidistant chart frame (the pure
 * math the Compose canvas draws from): observer at center, north-up
 * orientation, antipode on the rim, and projection/inverse round-trip.
 */
class AzimuthalChartFrameTest {

    private fun frame(zoom: Float = 1f) = AzimuthalChartFrame(
        widthPx = 400f,
        heightPx = 400f,
        observerLatDeg = 37.7749,
        observerLonDeg = -122.4194,
        headingDeg = 0.0,
        zoom = zoom,
    )

    @Test
    fun observerProjectsToScreenCenter() {
        val chart = frame()
        val (x, y) = chart.point(37.7749, -122.4194)
        assertEquals(chart.screenCenterX, x, 0.01f)
        assertEquals(chart.screenCenterY, y, 0.01f)
    }

    @Test
    fun pointDueNorthIsStraightUp() {
        val chart = frame()
        val (x, y) = chart.point(50.0, -122.4194)
        assertEquals(chart.screenCenterX, x, 0.5f)
        assertTrue("north must be above center", y < chart.screenCenterY)
    }

    @Test
    fun antipodeLandsOnTheRim() {
        val chart = frame()
        assertEquals(PI, chart.angularDistance(-37.7749, 57.5806), 1e-6)
        val (x, y) = chart.point(-37.7749, 57.5806)
        val radius = hypot(x - chart.screenCenterX, y - chart.screenCenterY)
        assertEquals(chart.diskRadius, radius, 0.5f)
    }

    @Test
    fun inverseProjectionRoundTrips() {
        val chart = frame()
        for ((lat, lon) in listOf(
            40.0 to -100.0,
            -10.0 to 140.0,
            60.0 to 5.0,
        )) {
            val (x, y) = chart.point(lat, lon)
            val (latBack, lonBack) = chart.coordinateAt(x, y)
            assertEquals("lat for ($lat,$lon)", lat, latBack, 0.05)
            assertEquals("lon for ($lat,$lon)", lon, lonBack, 0.05)
        }
    }

    @Test
    fun centerInverseIsTheObserver() {
        val chart = frame()
        val (lat, lon) = chart.coordinateAt(chart.screenCenterX, chart.screenCenterY)
        assertEquals(37.7749, lat, 1e-6)
        assertEquals(-122.4194, lon, 1e-6)
    }

    @Test
    fun zoomScalesTheDisk() {
        assertEquals(frame(zoom = 2f).diskRadius, frame(zoom = 1f).diskRadius * 2f, 0.01f)
    }

    @Test
    fun compassNorthSitsAboveCenter() {
        val chart = frame()
        val (x, y) = chart.compassPoint(0.0)
        assertEquals(chart.screenCenterX, x, 0.01f)
        assertEquals(chart.screenCenterY - chart.compassRadius, y, 0.01f)
    }
}
