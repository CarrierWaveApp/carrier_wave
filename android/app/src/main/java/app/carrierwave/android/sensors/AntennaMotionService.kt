package app.carrierwave.android.sensors

import android.content.Context
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.acos
import kotlin.math.sqrt

/**
 * Publishes device attitude for the satellite sky dome and pointing
 * screens (port of the iOS `AntennaMotionService`). TYPE_ROTATION_VECTOR
 * at ~30 Hz, quaternion-slerp smoothed (α = 0.3), converted to the iOS
 * reference→device convention by [RotationMatrices.referenceToDevice]
 * with the declination from the operator's home grid (true north when a
 * grid is set; magnetic otherwise, surfaced via [usesTrueNorth]).
 *
 * Two boresights, same as iOS: the sky dome points along the back camera
 * (device −Z); the antenna boom defaults to +Y (out the top edge, phone
 * flat on the boom) and can be trimmed via the gyro twist calibration
 * ([BoomCalibrator], gyro registered only while calibrating).
 */
class AntennaMotionService(
    context: Context,
    observerLatDeg: Double?,
    observerLonDeg: Double?,
) : SensorEventListener {

    data class State(
        /** Reference→device, row-major; null until the first sample. */
        val rotationMatrix: DoubleArray? = null,
        /** Nominal +Y or the twist-calibrated axis, device frame. */
        val boomAxis: DoubleArray = NOMINAL_BOOM_AXIS,
        val isCalibratingBoom: Boolean = false,
        /** 0…1 while calibrating. */
        val calibrationProgress: Double = 0.0,
        val calibrationOutcome: CalibrationOutcome? = null,
        /** SensorManager accuracy — LOW/UNRELIABLE drives a figure-8 banner. */
        val accuracyLow: Boolean = false,
    )

    enum class CalibrationOutcome { CALIBRATED, FAILED }

    private val appContext = context.applicationContext
    private val sensorManager =
        appContext.getSystemService(SensorManager::class.java)
    private val rotationSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    private val gyroSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

    /** Declination at the QTH; 0 (magnetic) without a home grid. */
    private val declinationDeg: Double = if (observerLatDeg != null && observerLonDeg != null) {
        GeomagneticField(
            observerLatDeg.toFloat(),
            observerLonDeg.toFloat(),
            0f,
            System.currentTimeMillis(),
        ).declination.toDouble()
    } else {
        0.0
    }

    val usesTrueNorth: Boolean = observerLatDeg != null && observerLonDeg != null
    val isAvailable: Boolean = rotationSensor != null

    private val _state = MutableStateFlow(State(boomAxis = loadBoomAxis()))
    val state: StateFlow<State> = _state.asStateFlow()

    private var smoothedQuaternion: DoubleArray? = null
    private var calibrator: BoomCalibrator? = null
    private var running = false

    fun start() {
        val manager = sensorManager ?: return
        val sensor = rotationSensor ?: return
        if (running) return
        manager.registerListener(this, sensor, SAMPLE_PERIOD_US)
        running = true
    }

    fun stop() {
        sensorManager?.unregisterListener(this)
        running = false
        smoothedQuaternion = null
        calibrator = null
        _state.value = _state.value.copy(
            rotationMatrix = null,
            isCalibratingBoom = false,
            calibrationProgress = 0.0,
        )
    }

    /** Begin the boom twist calibration (registers the gyro). */
    fun startBoomCalibration() {
        val manager = sensorManager ?: return
        val gyro = gyroSensor ?: return
        calibrator = BoomCalibrator()
        manager.registerListener(this, gyro, SAMPLE_PERIOD_US)
        _state.value = _state.value.copy(
            isCalibratingBoom = true,
            calibrationProgress = 0.0,
            calibrationOutcome = null,
        )
    }

    fun cancelBoomCalibration() {
        gyroSensor?.let { sensorManager?.unregisterListener(this, it) }
        calibrator = null
        _state.value = _state.value.copy(isCalibratingBoom = false, calibrationProgress = 0.0)
    }

    /** Drop any calibration and return to the nominal +Y boresight. */
    fun resetBoomAxis() {
        prefs().edit().remove(BOOM_AXIS_KEY).apply()
        _state.value = _state.value.copy(
            boomAxis = NOMINAL_BOOM_AXIS,
            calibrationOutcome = null,
        )
    }

    /** Angle between the calibrated boom axis and nominal +Y, degrees. */
    fun boomTrimDeg(): Double =
        acos(_state.value.boomAxis[1].coerceIn(-1.0, 1.0)) * 180.0 / Math.PI

    // MARK: SensorEventListener

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR -> ingestRotation(event)
            Sensor.TYPE_GYROSCOPE -> ingestGyro(event)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {
        if (sensor.type != Sensor.TYPE_ROTATION_VECTOR) return
        _state.value = _state.value.copy(
            accuracyLow = accuracy <= SensorManager.SENSOR_STATUS_ACCURACY_LOW,
        )
    }

    // MARK: private

    private fun ingestRotation(event: SensorEvent) {
        val values = event.values
        // values[3] (w) may be absent on old sensors; reconstruct it.
        val w = if (values.size >= 4) {
            values[3].toDouble()
        } else {
            val sumSq = values[0] * values[0] + values[1] * values[1] + values[2] * values[2]
            sqrt((1.0 - sumSq).coerceAtLeast(0.0))
        }
        val target = doubleArrayOf(
            values[0].toDouble(),
            values[1].toDouble(),
            values[2].toDouble(),
            w,
        )
        val smoothed = smoothedQuaternion
            ?.let { RotationMatrices.slerp(it, target, SMOOTHING_ALPHA) }
            ?: target
        smoothedQuaternion = smoothed
        val deviceToEnu = RotationMatrices.quaternionToMatrix(smoothed)
        _state.value = _state.value.copy(
            rotationMatrix = RotationMatrices.referenceToDevice(deviceToEnu, declinationDeg),
        )
    }

    private fun ingestGyro(event: SensorEvent) {
        val active = calibrator ?: return
        val outcome = active.ingest(
            event.values[0].toDouble(),
            event.values[1].toDouble(),
            event.values[2].toDouble(),
        ) ?: run {
            _state.value = _state.value.copy(calibrationProgress = active.progress)
            return
        }
        gyroSensor?.let { sensorManager?.unregisterListener(this, it) }
        calibrator = null
        when (outcome) {
            is BoomCalibrator.Outcome.Calibrated -> {
                prefs().edit()
                    .putString(
                        BOOM_AXIS_KEY,
                        "${outcome.axis[0]},${outcome.axis[1]},${outcome.axis[2]}",
                    )
                    .apply()
                _state.value = _state.value.copy(
                    boomAxis = outcome.axis,
                    isCalibratingBoom = false,
                    calibrationProgress = 0.0,
                    calibrationOutcome = CalibrationOutcome.CALIBRATED,
                )
            }
            BoomCalibrator.Outcome.Failed -> _state.value = _state.value.copy(
                isCalibratingBoom = false,
                calibrationProgress = 0.0,
                calibrationOutcome = CalibrationOutcome.FAILED,
            )
        }
    }

    private fun loadBoomAxis(): DoubleArray {
        val stored = prefs().getString(BOOM_AXIS_KEY, null) ?: return NOMINAL_BOOM_AXIS
        val parts = stored.split(",").mapNotNull { it.toDoubleOrNull() }
        if (parts.size != 3) return NOMINAL_BOOM_AXIS
        val magnitude = sqrt(parts[0] * parts[0] + parts[1] * parts[1] + parts[2] * parts[2])
        if (magnitude < 1e-6) return NOMINAL_BOOM_AXIS
        val axis = doubleArrayOf(parts[0] / magnitude, parts[1] / magnitude, parts[2] / magnitude)
        val trim = acos(axis[1].coerceIn(-1.0, 1.0)) * 180.0 / Math.PI
        return if (trim < BoomCalibrator.MAX_TRIM_DEG) axis else NOMINAL_BOOM_AXIS
    }

    private fun prefs() = appContext.getSharedPreferences("cw", Context.MODE_PRIVATE)

    companion object {
        val NOMINAL_BOOM_AXIS = doubleArrayOf(0.0, 1.0, 0.0)

        /** Prefs key for the persisted twist-calibrated axis ("x,y,z"). */
        private const val BOOM_AXIS_KEY = "satellite_boom_axis"

        /** ~30 Hz, matching the iOS deviceMotionUpdateInterval. */
        private const val SAMPLE_PERIOD_US = 33_333

        /** Quaternion low-pass weight toward the newest sample. */
        private const val SMOOTHING_ALPHA = 0.3
    }
}
