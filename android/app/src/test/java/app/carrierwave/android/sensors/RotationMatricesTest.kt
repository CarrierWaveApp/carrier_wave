package app.carrierwave.android.sensors

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Canned-attitude checks of the ENU→reference conversion and the derived
 * angle extractors, including the declination sign (positive declination
 * = magnetic north east of true north must ADD to true azimuths).
 */
class RotationMatricesTest {

    /** Device flat on its back, top edge to magnetic north (R = identity). */
    private val flat = DoubleArray(9) { i -> if (i % 4 == 0) 1.0 else 0.0 }

    /** Device raised vertical, screen to the user, back camera to magnetic
     * north: device X→east, Y→up, Z→south in ENU. */
    private val raised = doubleArrayOf(
        1.0, 0.0, 0.0,
        0.0, 0.0, -1.0,
        0.0, 1.0, 0.0,
    )

    @Test
    fun flatDeviceCameraPointsStraightDown() {
        val m = RotationMatrices.referenceToDevice(flat, declinationDeg = 0.0)
        assertEquals(-90.0, RotationMatrices.pointingElevationDeg(m), 1e-9)
    }

    @Test
    fun flatDeviceHeadingIsNorth() {
        val m = RotationMatrices.referenceToDevice(flat, declinationDeg = 0.0)
        assertEquals(0.0, RotationMatrices.screenHeadingDeg(m)!!, 1e-9)
    }

    @Test
    fun positiveDeclinationShiftsHeadingEast() {
        // Pointing at MAGNETIC north with +10° declination = 10° true.
        val m = RotationMatrices.referenceToDevice(flat, declinationDeg = 10.0)
        assertEquals(10.0, RotationMatrices.screenHeadingDeg(m)!!, 1e-9)
    }

    @Test
    fun raisedDeviceCameraPointsAtTheHorizonDueNorth() {
        val m = RotationMatrices.referenceToDevice(raised, declinationDeg = 0.0)
        assertEquals(0.0, RotationMatrices.pointingElevationDeg(m), 1e-9)
        assertEquals(0.0, RotationMatrices.pointingAzimuthDeg(m)!!, 1e-9)
    }

    @Test
    fun raisedDeviceBoomPointsAtTheZenith() {
        val m = RotationMatrices.referenceToDevice(raised, declinationDeg = 0.0)
        assertEquals(
            90.0,
            RotationMatrices.boomElevationDeg(m, AntennaMotionService.NOMINAL_BOOM_AXIS),
            1e-9,
        )
    }

    @Test
    fun flatDeviceBoomIsHorizontalNorth() {
        val m = RotationMatrices.referenceToDevice(flat, declinationDeg = 0.0)
        val axis = AntennaMotionService.NOMINAL_BOOM_AXIS
        assertEquals(0.0, RotationMatrices.boomElevationDeg(m, axis), 1e-9)
        assertEquals(0.0, RotationMatrices.boomAzimuthDeg(m, axis)!!, 1e-9)
    }

    @Test
    fun flatDeviceElementTiltIsZero() {
        val m = RotationMatrices.referenceToDevice(flat, declinationDeg = 0.0)
        assertEquals(0.0, RotationMatrices.elementTiltDeg(m), 1e-9)
    }

    @Test
    fun quaternionIdentityGivesIdentityMatrix() {
        val m = RotationMatrices.quaternionToMatrix(doubleArrayOf(0.0, 0.0, 0.0, 1.0))
        for (i in 0..8) {
            assertEquals(if (i % 4 == 0) 1.0 else 0.0, m[i], 1e-12)
        }
    }

    @Test
    fun slerpAtZeroAndOneReturnsEndpoints() {
        val identity = doubleArrayOf(0.0, 0.0, 0.0, 1.0)
        // 90° about Z.
        val quarter = doubleArrayOf(0.0, 0.0, kotlin.math.sqrt(0.5), kotlin.math.sqrt(0.5))
        val atZero = RotationMatrices.slerp(identity, quarter, 0.0)
        val atOne = RotationMatrices.slerp(identity, quarter, 1.0)
        for (i in 0..3) {
            assertEquals(identity[i], atZero[i], 1e-9)
            assertEquals(quarter[i], atOne[i], 1e-9)
        }
        // Halfway = 45° about Z: z = sin(22.5°), w = cos(22.5°).
        val half = RotationMatrices.slerp(identity, quarter, 0.5)
        assertEquals(kotlin.math.sin(Math.PI / 8), half[2], 1e-9)
        assertEquals(kotlin.math.cos(Math.PI / 8), half[3], 1e-9)
    }
}
