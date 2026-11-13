package app.carrierwave.android.sensors

import kotlin.math.acos
import kotlin.math.sqrt

/**
 * Gyro twist calibration for the antenna boom axis (pure port of the iOS
 * `AntennaMotionService` calibration half): while the user twists the
 * antenna back and forth, the gyro's instantaneous rotation axis IS the
 * boom axis in the device frame. Collects fast-twist samples folded into
 * the +Y hemisphere; finishes once enough arrive, requiring the samples
 * to cluster on one axis (coherence > 0.9) within 30° of nominal +Y.
 */
class BoomCalibrator {
    sealed class Outcome {
        data class Calibrated(val axis: DoubleArray, val trimDeg: Double) : Outcome()
        object Failed : Outcome()
    }

    /** 0…1: fraction of the required twist samples collected. */
    var progress: Double = 0.0
        private set

    private val samples = mutableListOf<DoubleArray>()

    /** Feed one gyro sample (rad/s, device frame). Returns the outcome
     * once the sample target is reached, else null. */
    fun ingest(rateX: Double, rateY: Double, rateZ: Double): Outcome? {
        val magnitude = sqrt(rateX * rateX + rateY * rateY + rateZ * rateZ)
        // Slow samples carry more hand-wobble than twist.
        if (magnitude <= MIN_RATE_RAD_PER_SEC) return null
        var sample = doubleArrayOf(rateX / magnitude, rateY / magnitude, rateZ / magnitude)
        // The twist alternates direction; fold both into the +Y hemisphere.
        if (sample[1] < 0) sample = doubleArrayOf(-sample[0], -sample[1], -sample[2])
        samples.add(sample)
        progress = samples.size.toDouble() / SAMPLE_TARGET
        if (samples.size < SAMPLE_TARGET) return null
        return finish()
    }

    fun reset() {
        samples.clear()
        progress = 0.0
    }

    private fun finish(): Outcome {
        var sumX = 0.0
        var sumY = 0.0
        var sumZ = 0.0
        for (sample in samples) {
            sumX += sample[0]
            sumY += sample[1]
            sumZ += sample[2]
        }
        val count = samples.size.toDouble()
        samples.clear()
        val magnitude = sqrt(sumX * sumX + sumY * sumY + sumZ * sumZ)
        val mean = doubleArrayOf(
            sumX / magnitude.coerceAtLeast(1e-9),
            sumY / magnitude.coerceAtLeast(1e-9),
            sumZ / magnitude.coerceAtLeast(1e-9),
        )
        val trim = acos(mean[1].coerceIn(-1.0, 1.0)) * 180.0 / Math.PI
        // Coherent (samples clustered on one axis) and plausibly boom-like.
        if (magnitude <= count * COHERENCE || trim >= MAX_TRIM_DEG) return Outcome.Failed
        return Outcome.Calibrated(axis = mean, trimDeg = trim)
    }

    companion object {
        /** ~2 s of active twisting at 30 Hz. */
        const val SAMPLE_TARGET = 60

        /** Ignore gyro samples slower than this (rad/s). */
        const val MIN_RATE_RAD_PER_SEC = 0.8

        /** Reject an axis further than this from nominal +Y. */
        const val MAX_TRIM_DEG = 30.0

        private const val COHERENCE = 0.9
    }
}
