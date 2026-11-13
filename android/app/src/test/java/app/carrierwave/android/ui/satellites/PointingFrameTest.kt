package app.carrierwave.android.ui.satellites

import app.carrierwave.android.sensors.AntennaMotionService
import app.carrierwave.android.sensors.RotationMatrices
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.cw_ffi.FfiSatTransmitter
import uniffi.cw_ffi.FfiSatModeCategory
import uniffi.cw_ffi.FfiSatellitePass
import uniffi.cw_ffi.FfiSatellitePosition

/**
 * Canned-frame checks of the pointing-screen state machine: lock inside
 * 5°, wrap-180 azimuth error, below-horizon steering to the rise point,
 * and the Doppler tuning sign (approaching bird = higher downlink).
 */
class PointingFrameTest {

    /** Phone flat on its back, top edge north: boom horizontal due north. */
    private val flatMatrix = RotationMatrices.referenceToDevice(
        DoubleArray(9) { i -> if (i % 4 == 0) 1.0 else 0.0 },
        declinationDeg = 0.0,
    )

    private fun position(
        azimuth: Double?,
        elevation: Double?,
        rangeRate: Double = 0.0,
    ) = FfiSatellitePosition(
        noradId = 25544u,
        name = "ISS",
        detailName = "ZARYA",
        latDeg = 0.0,
        lonDeg = 0.0,
        altKm = 420.0,
        latRateDegPerSec = 0.0,
        lonRateDegPerSec = 0.0,
        azimuthDeg = azimuth,
        elevationDeg = elevation,
        rangeKm = 500.0,
        azRateDegPerSec = 0.0,
        elRateDegPerSec = 0.0,
        rangeRateKmPerSec = rangeRate,
        footprintRadiusM = 2_000_000.0,
    )

    private fun transmitter(downlinkHz: Long?, uplinkHz: Long?) = FfiSatTransmitter(
        description = "FM transponder",
        transmitterType = "Transceiver",
        alive = true,
        isActive = true,
        mode = "FM",
        modeCategory = FfiSatModeCategory.VOICE_FM,
        uplinkLowHz = uplinkHz,
        downlinkLowHz = downlinkHz,
        amsatTracked = false,
        amsatLastHeardEpoch = null,
    )

    private fun pass(aosEpoch: Long, losEpoch: Long, aosAz: Double) = FfiSatellitePass(
        aosEpoch = aosEpoch,
        aosAzimuthDeg = aosAz,
        peakEpoch = (aosEpoch + losEpoch) / 2,
        peakAzimuthDeg = 90.0,
        peakElevationDeg = 45.0,
        peakRangeKm = 800.0,
        losEpoch = losEpoch,
        losAzimuthDeg = 180.0,
    )

    @Test
    fun boomOnTargetLocks() {
        // 1° up: exactly 0° elevation counts as below the horizon.
        val frame = PointingFrame.compute(
            position = position(azimuth = 0.0, elevation = 1.0),
            transmitters = emptyList(),
            matrix = flatMatrix,
            boomAxis = AntennaMotionService.NOMINAL_BOOM_AXIS,
            elapsedSecs = 0.0,
            passes = emptyList(),
            nowEpochSecs = 1_000,
        )
        assertTrue(frame.isLocked)
        assertEquals(0.0, frame.azErrorDeg!!, 1e-6)
        assertEquals(1.0, frame.elErrorDeg!!, 1e-6)
    }

    @Test
    fun azimuthErrorWrapsThe180Seam() {
        // Boom north, bird at az 350° → swing 10° LEFT, not 350° right.
        val frame = PointingFrame.compute(
            position = position(azimuth = 350.0, elevation = 30.0),
            transmitters = emptyList(),
            matrix = flatMatrix,
            boomAxis = AntennaMotionService.NOMINAL_BOOM_AXIS,
            elapsedSecs = 0.0,
            passes = emptyList(),
            nowEpochSecs = 1_000,
        )
        assertEquals(-10.0, frame.azErrorDeg!!, 1e-6)
        assertEquals(30.0, frame.elErrorDeg!!, 1e-6)
        assertTrue(frame.phase is PointingFrame.Phase.Tracking)
        assertTrue(!frame.isLocked)
    }

    @Test
    fun belowHorizonSteersToTheRisePoint() {
        val next = pass(aosEpoch = 2_000, losEpoch = 3_000, aosAz = 120.0)
        val frame = PointingFrame.compute(
            position = position(azimuth = 40.0, elevation = -5.0),
            transmitters = emptyList(),
            matrix = flatMatrix,
            boomAxis = AntennaMotionService.NOMINAL_BOOM_AXIS,
            elapsedSecs = 0.0,
            passes = listOf(next),
            nowEpochSecs = 1_000,
        )
        val phase = frame.phase as PointingFrame.Phase.BelowHorizon
        assertEquals(next, phase.nextPass)
        assertEquals(120.0, frame.guidanceAzDeg!!, 1e-9)
        // Boom points north → swing 120° right, tilt to the horizon.
        assertEquals(120.0, frame.azErrorDeg!!, 1e-6)
        assertEquals(0.0, frame.elErrorDeg!!, 1e-6)
    }

    @Test
    fun dopplerRaisesDownlinkAndLowersUplinkWhenApproaching() {
        // Approaching: range rate negative → factor positive.
        val frame = PointingFrame.compute(
            position = position(azimuth = 0.0, elevation = 45.0, rangeRate = -7.0),
            transmitters = listOf(transmitter(downlinkHz = 145_800_000, uplinkHz = 437_800_000)),
            matrix = flatMatrix,
            boomAxis = AntennaMotionService.NOMINAL_BOOM_AXIS,
            elapsedSecs = 0.0,
            passes = emptyList(),
            nowEpochSecs = 1_000,
        )
        assertTrue(frame.downlinkMHz!! > 145.8)
        assertTrue(frame.uplinkMHz!! < 437.8)
        assertTrue(frame.dopplerShiftKHz!! > 0)
        assertEquals("FM", frame.mode)
    }

    @Test
    fun deadReckoningAdvancesTheTarget() {
        val moving = position(azimuth = 10.0, elevation = 20.0).copy(
            azRateDegPerSec = 0.5,
            elRateDegPerSec = 0.2,
        )
        val frame = PointingFrame.compute(
            position = moving,
            transmitters = emptyList(),
            matrix = flatMatrix,
            boomAxis = AntennaMotionService.NOMINAL_BOOM_AXIS,
            elapsedSecs = 10.0,
            passes = emptyList(),
            nowEpochSecs = 1_000,
        )
        assertEquals(15.0, frame.targetAzDeg!!, 1e-9)
        assertEquals(22.0, frame.targetElDeg!!, 1e-9)
    }
}
