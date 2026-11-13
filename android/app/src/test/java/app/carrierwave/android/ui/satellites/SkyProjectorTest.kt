package app.carrierwave.android.ui.satellites

import app.carrierwave.android.sensors.RotationMatrices
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * SkyProjector against canned attitudes (the raised-phone matrix from
 * `RotationMatricesTest`): on-boresight targets land at screen center,
 * elevation moves points up-screen, behind-the-viewer culls to null.
 */
class SkyProjectorTest {

    /** Back camera at the horizon due north, screen to the user. */
    private val raised = RotationMatrices.referenceToDevice(
        doubleArrayOf(
            1.0, 0.0, 0.0,
            0.0, 0.0, -1.0,
            0.0, 1.0, 0.0,
        ),
        declinationDeg = 0.0,
    )

    private fun projector() = SkyProjector(raised, widthPx = 400f, heightPx = 800f)

    @Test
    fun boresightTargetProjectsToCenter() {
        val (x, y) = projector().project(0.0, 0.0)!!
        assertEquals(200f, x, 0.01f)
        assertEquals(400f, y, 0.01f)
    }

    @Test
    fun higherElevationMovesUpScreen() {
        val (_, y) = projector().project(0.0, 20.0)!!
        assertTrue("elevated target renders above center", y < 400f)
    }

    @Test
    fun eastOfBoresightMovesRightOnScreen() {
        val (x, _) = projector().project(30.0, 0.0)!!
        assertTrue("east target renders right of center", x > 200f)
    }

    @Test
    fun behindTheViewerCullsToNull() {
        assertNull(projector().project(180.0, 0.0))
    }

    @Test
    fun offAxisMatchesGreatCircleSeparation() {
        val projector = projector()
        assertEquals(0.0, projector.offAxisDeg(0.0, 0.0), 1e-9)
        assertEquals(45.0, projector.offAxisDeg(0.0, 45.0), 1e-9)
        assertEquals(90.0, projector.offAxisDeg(90.0, 0.0), 1e-9)
    }

    @Test
    fun boomBoresightIsTheZenithWhenRaised() {
        // Raised phone: boom +Y points at the zenith.
        assertEquals(0.0, projector().boomOffAxisDeg(0.0, 90.0), 1e-9)
        assertEquals(90.0, projector().boomOffAxisDeg(0.0, 0.0), 1e-9)
    }

    @Test
    fun screenDirectionPointsUpForElevatedTarget() {
        val (dx, dy) = projector().screenDirection(0.0, 60.0)
        assertEquals(0f, dx, 1e-6f)
        assertTrue("up-screen is negative dy", dy < 0)
    }
}
