package app.carrierwave.android.sensors

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.cos
import kotlin.math.sin

/** Scripted gyro streams through the twist calibrator. */
class BoomCalibratorTest {

    @Test
    fun cleanAlternatingTwistCalibratesOnAxis() {
        val calibrator = BoomCalibrator()
        var outcome: BoomCalibrator.Outcome? = null
        repeat(BoomCalibrator.SAMPLE_TARGET) { index ->
            // Alternating-direction twist about +Y at 2 rad/s.
            val sign = if (index % 2 == 0) 1.0 else -1.0
            outcome = calibrator.ingest(0.0, sign * 2.0, 0.0)
        }
        val calibrated = outcome as BoomCalibrator.Outcome.Calibrated
        assertEquals(0.0, calibrated.trimDeg, 1e-9)
        assertEquals(1.0, calibrated.axis[1], 1e-9)
    }

    @Test
    fun offAxisTwistWithinTrimCalibratesWithTrim() {
        val calibrator = BoomCalibrator()
        var outcome: BoomCalibrator.Outcome? = null
        val trimRad = 15.0 * Math.PI / 180.0
        repeat(BoomCalibrator.SAMPLE_TARGET) { index ->
            val sign = if (index % 2 == 0) 1.0 else -1.0
            outcome = calibrator.ingest(sign * 2.0 * sin(trimRad), sign * 2.0 * cos(trimRad), 0.0)
        }
        val calibrated = outcome as BoomCalibrator.Outcome.Calibrated
        assertEquals(15.0, calibrated.trimDeg, 1e-6)
    }

    @Test
    fun rotationAboutTheWrongAxisFails() {
        val calibrator = BoomCalibrator()
        var outcome: BoomCalibrator.Outcome? = null
        repeat(BoomCalibrator.SAMPLE_TARGET) { index ->
            // Twisting about X (90° from the boom) — not a boom twist.
            val sign = if (index % 2 == 0) 1.0 else -1.0
            outcome = calibrator.ingest(sign * 2.0, 0.0, 0.0)
        }
        assertTrue(outcome is BoomCalibrator.Outcome.Failed)
    }

    @Test
    fun incoherentSamplesFail() {
        val calibrator = BoomCalibrator()
        var outcome: BoomCalibrator.Outcome? = null
        // Samples split between two axes 56° apart (coherence cos(28°) ≈
        // 0.88 < 0.9) but each within the 30° trim gate.
        val spread = 28.0 * Math.PI / 180.0
        repeat(BoomCalibrator.SAMPLE_TARGET) { index ->
            val lean = if (index % 2 == 0) spread else -spread
            outcome = calibrator.ingest(2.0 * sin(lean), 2.0 * cos(lean), 0.0)
        }
        assertTrue(outcome is BoomCalibrator.Outcome.Failed)
    }

    @Test
    fun slowSamplesAreIgnored() {
        val calibrator = BoomCalibrator()
        assertNull(calibrator.ingest(0.0, 0.5, 0.0))
        assertEquals(0.0, calibrator.progress, 1e-12)
    }

    @Test
    fun progressTracksSampleCount() {
        val calibrator = BoomCalibrator()
        repeat(BoomCalibrator.SAMPLE_TARGET / 2) {
            calibrator.ingest(0.0, 2.0, 0.0)
        }
        assertEquals(0.5, calibrator.progress, 1e-9)
    }
}
