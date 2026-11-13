package app.carrierwave.android.ui.satellites

import app.carrierwave.android.sensors.RotationMatrices
import uniffi.cw_ffi.FfiSatTransmitter
import uniffi.cw_ffi.FfiSatellitePass
import uniffi.cw_ffi.FfiSatellitePosition

/**
 * Everything one render frame of the pointing screen needs, computed from
 * the dead-reckoned satellite position and the device attitude (pure port
 * of the iOS `PointingFrame` + `makeFrame`/`applyTuning` — no Compose or
 * sensor types, JVM-testable).
 */
data class PointingFrame(
    val phase: Phase,
    val name: String = "",
    val detailName: String? = null,
    val targetAzDeg: Double? = null,
    val targetElDeg: Double? = null,
    /** Boresight azimuth from the attitude, for the compass tape. */
    val pointingAzDeg: Double? = null,
    /** Azimuth the guidance steers toward: the satellite, or its rise
     * point when it's below the horizon. */
    val guidanceAzDeg: Double? = null,
    /** Guidance errors: how far to swing (+ = right) and tilt (+ = up). */
    val azErrorDeg: Double? = null,
    val elErrorDeg: Double? = null,
    val offAxisDeg: Double? = null,
    val downlinkMHz: Double? = null,
    val uplinkMHz: Double? = null,
    val dopplerShiftKHz: Double? = null,
    val mode: String? = null,
) {
    sealed class Phase {
        data class NoData(val reason: String) : Phase()
        data class BelowHorizon(val nextPass: FfiSatellitePass?) : Phase()
        data class Tracking(val isLocked: Boolean) : Phase()
    }

    val isLocked: Boolean
        get() = (phase as? Phase.Tracking)?.isLocked == true

    companion object {
        /** Lock threshold matches the sky dome's lock-on cone. */
        const val LOCK_DEG = 5.0
        const val NEAR_DEG = 20.0
        private const val LIGHT_SPEED_KM_PER_SEC = 299_792.458

        fun compute(
            position: FfiSatellitePosition?,
            transmitters: List<FfiSatTransmitter>,
            matrix: DoubleArray?,
            boomAxis: DoubleArray,
            elapsedSecs: Double,
            passes: List<FfiSatellitePass>,
            nowEpochSecs: Long,
        ): PointingFrame {
            if (position == null) {
                return PointingFrame(Phase.NoData("No satellite selected"))
            }
            var frame = PointingFrame(
                phase = Phase.NoData("Waiting for motion + location…"),
                name = position.name,
                detailName = position.detailName,
            )
            frame = applyTuning(frame, position, transmitters)
            val azimuth = position.azimuthDeg ?: return frame
            val elevation = position.elevationDeg ?: return frame
            if (matrix == null) return frame
            val pointingAz = RotationMatrices.boomAzimuthDeg(matrix, boomAxis) ?: return frame
            val pointingEl = RotationMatrices.boomElevationDeg(matrix, boomAxis)

            val azNow = wrapAzimuth(azimuth + position.azRateDegPerSec * elapsedSecs)
            val elNow = elevation + position.elRateDegPerSec * elapsedSecs
            val projector = SkyProjector(matrix, 1f, 1f, boomAxis)

            val guidanceAz: Double
            val guidanceEl: Double
            val phase: Phase
            var offAxis: Double? = null
            if (elNow <= 0) {
                val nextPass = passes.firstOrNull { it.losEpoch > nowEpochSecs }
                guidanceAz = nextPass?.aosAzimuthDeg ?: azNow
                guidanceEl = 0.0
                phase = Phase.BelowHorizon(nextPass)
            } else {
                guidanceAz = azNow
                guidanceEl = elNow
                offAxis = projector.boomOffAxisDeg(azNow, elNow)
                phase = Phase.Tracking(isLocked = offAxis < LOCK_DEG)
            }
            return frame.copy(
                phase = phase,
                targetAzDeg = azNow,
                targetElDeg = elNow,
                pointingAzDeg = pointingAz,
                guidanceAzDeg = guidanceAz,
                azErrorDeg = wrap180(guidanceAz - pointingAz),
                elErrorDeg = guidanceEl - pointingEl,
                offAxisDeg = offAxis,
            )
        }

        /** Doppler-corrected tuning from the primary (active,
         * downlink-bearing) transmitter: `f · (1 ± ṙ/c)`. */
        private fun applyTuning(
            frame: PointingFrame,
            position: FfiSatellitePosition,
            transmitters: List<FfiSatTransmitter>,
        ): PointingFrame {
            val primary = transmitters.firstOrNull { it.isActive && it.downlinkLowHz != null }
                ?: transmitters.firstOrNull { it.downlinkLowHz != null }
                ?: return frame
            val factor = -position.rangeRateKmPerSec / LIGHT_SPEED_KM_PER_SEC
            return frame.copy(
                mode = primary.mode,
                downlinkMHz = primary.downlinkLowHz?.let { it * (1 + factor) / 1_000_000.0 },
                dopplerShiftKHz = primary.downlinkLowHz?.let { it * factor / 1_000.0 },
                uplinkMHz = primary.uplinkLowHz?.let { it * (1 - factor) / 1_000_000.0 },
            )
        }

        fun wrapAzimuth(degrees: Double): Double {
            var value = degrees % 360.0
            if (value < 0) value += 360.0
            return value
        }

        fun wrap180(degrees: Double): Double {
            var value = degrees % 360.0
            if (value > 180) value -= 360.0
            if (value < -180) value += 360.0
            return value
        }
    }
}
