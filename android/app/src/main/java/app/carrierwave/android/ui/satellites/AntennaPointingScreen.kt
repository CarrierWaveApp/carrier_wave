package app.carrierwave.android.ui.satellites

import android.Manifest
import android.app.Activity
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.carrierwave.android.data.SatellitePassRecorder
import app.carrierwave.android.sensors.AntennaMotionService
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import uniffi.cw_ffi.FfiSatellitePass

/**
 * Antenna-mount pointing mode (port of the iOS `AntennaPointingView`,
 * no camera in v1): lay the phone flat on the boom — screen up, top edge
 * toward the antenna tip — and read the screen from afar. Boresight =
 * device +Y (trim-calibrated). G1000 conventions: compass tape with a
 * fly-to bug, glideslope elevation deviation scale, giant chevron
 * corrections tinted by the semantic status color that also frames the
 * screen edge; locked shows the Doppler-corrected tuning + polarization
 * hint; below the horizon it counts down and steers to the rise point.
 * Portrait-pinned (polarization twists roll through landscape) with the
 * screen kept awake.
 */
@Composable
fun AntennaPointingScreen(
    vm: SatelliteViewModel,
    motion: AntennaMotionService,
    noradId: UInt,
    onQuickLog: () -> Unit,
    onDismiss: () -> Unit,
) {
    val ui by vm.state.collectAsStateWithLifecycle()
    val motionState by motion.state.collectAsStateWithLifecycle()
    val view = LocalView.current
    val activity = LocalContext.current as? Activity

    DisposableEffect(Unit) {
        motion.start()
        view.keepScreenOn = true
        val previousOrientation = activity?.requestedOrientation
        activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        onDispose {
            motion.stop()
            view.keepScreenOn = false
            previousOrientation?.let { activity?.requestedOrientation = it }
        }
    }

    // 15 fps render clock (iOS TimelineView cadence).
    var frameMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (isActive) {
            frameMs = System.currentTimeMillis()
            delay(66)
        }
    }

    var passes by remember { mutableStateOf<List<FfiSatellitePass>>(emptyList()) }
    LaunchedEffect(noradId) {
        passes = vm.passForecast(noradId)?.passes ?: emptyList()
    }

    val position = ui.positions.firstOrNull { it.noradId == noradId }
    val elapsed = (frameMs - ui.positionsSyncedAtMs) / 1_000.0
    val frame = PointingFrame.compute(
        position = position,
        transmitters = vm.transmitters(noradId),
        matrix = motionState.rotationMatrix,
        boomAxis = motionState.boomAxis,
        elapsedSecs = elapsed,
        passes = passes,
        nowEpochSecs = frameMs / 1_000,
    )
    val statusColor = statusColor(frame)

    // Calibration outcome flashes for 4 s.
    var outcomeShownUntil by remember { mutableLongStateOf(0L) }
    LaunchedEffect(motionState.calibrationOutcome) {
        if (motionState.calibrationOutcome != null) {
            outcomeShownUntil = System.currentTimeMillis() + 4_000
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .border(width = 12.dp, color = statusColor),
    ) {
        BoresightMarker(frame, motionState.rotationMatrix, motionState.boomAxis)

        Column(modifier = Modifier.fillMaxSize().padding(20.dp)) {
            PointingHeader(frame, motionState.isCalibratingBoom, motion, onDismiss)
            val pointing = frame.pointingAzDeg
            val guidance = frame.guidanceAzDeg
            if (pointing != null && guidance != null) {
                PointingCompassTape(pointingAzDeg = pointing, targetAzDeg = guidance)
            }
            Spacer(modifier = Modifier.weight(1f))
            when {
                motionState.isCalibratingBoom -> CalibrationContent(motionState.calibrationProgress)
                motionState.calibrationOutcome != null && frameMs < outcomeShownUntil ->
                    CalibrationOutcome(motionState.calibrationOutcome!!, motion)
                else -> PhaseContent(frame, frameMs, vm, ui.selectedNoradId, motionState, onQuickLog)
            }
            Spacer(modifier = Modifier.weight(1f))
            PointingRecordControls(noradId, frame.name)
            PointingFooter(frame, motion)
        }

        val elError = frame.elErrorDeg
        if (elError != null) {
            Box(
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .padding(end = 20.dp),
            ) {
                PointingElevationScale(elErrorDeg = elError)
            }
        }
    }
}

/** Semantic status: green = locked, orange = close, red = far off,
 * blue = below horizon, gray = no data. */
private fun statusColor(frame: PointingFrame): Color = when (val phase = frame.phase) {
    is PointingFrame.Phase.NoData -> Color(0xFF616161)
    is PointingFrame.Phase.BelowHorizon -> Color(0xFF1E88E5)
    is PointingFrame.Phase.Tracking ->
        if (phase.isLocked) {
            Color(0xFF43A047)
        } else if ((frame.offAxisDeg ?: 180.0) < PointingFrame.NEAR_DEG) {
            Color(0xFFFB8C00)
        } else {
            Color(0xFFE53935)
        }
}

/** Satellite marker projected along the boom axis + fixed crosshair. */
@Composable
private fun BoresightMarker(frame: PointingFrame, matrix: DoubleArray?, boomAxis: DoubleArray) {
    Canvas(modifier = Modifier.fillMaxSize()) {
        drawCircle(
            Color.White.copy(alpha = 0.5f),
            radius = 26.dp.toPx(),
            center = Offset(size.width / 2, size.height / 2),
            style = Stroke(width = 1.5.dp.toPx()),
        )
        val azimuth = frame.targetAzDeg ?: return@Canvas
        val elevation = frame.targetElDeg ?: return@Canvas
        if (matrix == null) return@Canvas
        val projector = SkyProjector(matrix, size.width, size.height, boomAxis)
        val point = projector.boomProject(azimuth, elevation) ?: return@Canvas
        val color = if (frame.isLocked) Color(0xFF4CAF50) else Color(0xFFFF9800)
        drawCircle(color, radius = 10.dp.toPx(), center = Offset(point.first, point.second))
    }
}

@Composable
private fun PointingHeader(
    frame: PointingFrame,
    isCalibrating: Boolean,
    motion: AntennaMotionService,
    onDismiss: () -> Unit,
) {
    Row(verticalAlignment = Alignment.Top, modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                frame.name,
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace,
                color = Color.White,
                maxLines = 1,
            )
            frame.detailName?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White.copy(alpha = 0.6f),
                    maxLines = 1,
                )
            }
        }
        IconButton(onClick = {
            if (isCalibrating) motion.cancelBoomCalibration() else motion.startBoomCalibration()
        }) {
            Icon(
                Icons.Filled.Sync,
                contentDescription =
                    if (isCalibrating) "Cancel boom calibration" else "Calibrate boom axis",
                tint = if (isCalibrating) Color(0xFFFF9800) else Color.White,
            )
        }
        IconButton(onClick = onDismiss) {
            Icon(Icons.Filled.Close, contentDescription = "Exit pointing mode", tint = Color.White)
        }
    }
}

@Composable
private fun CalibrationContent(progress: Double) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(
            "TWIST THE ANTENNA",
            fontSize = 24.sp,
            fontWeight = FontWeight.Black,
            color = Color(0xFFFF9800),
        )
        Text(
            "Roll it back and forth around the boom",
            style = MaterialTheme.typography.titleMedium,
            color = Color.White.copy(alpha = 0.9f),
        )
        LinearProgressIndicator(
            progress = { progress.coerceAtMost(1.0).toFloat() },
            color = Color(0xFFFF9800),
        )
    }
}

@Composable
private fun CalibrationOutcome(
    outcome: AntennaMotionService.CalibrationOutcome,
    motion: AntennaMotionService,
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
        when (outcome) {
            AntennaMotionService.CalibrationOutcome.CALIBRATED -> Text(
                "BOOM SET — TRIM %.1f°".format(motion.boomTrimDeg()),
                fontSize = 24.sp,
                fontWeight = FontWeight.Black,
                color = Color(0xFF4CAF50),
            )
            AntennaMotionService.CalibrationOutcome.FAILED -> Text(
                "Calibration failed — twist only around the boom",
                style = MaterialTheme.typography.titleMedium,
                color = Color(0xFFFF9800),
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun PhaseContent(
    frame: PointingFrame,
    frameMs: Long,
    vm: SatelliteViewModel,
    selectedNoradId: UInt?,
    motionState: AntennaMotionService.State,
    onQuickLog: () -> Unit,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        when (val phase = frame.phase) {
            is PointingFrame.Phase.NoData -> Text(
                phase.reason,
                style = MaterialTheme.typography.titleLarge,
                color = Color.White,
                textAlign = TextAlign.Center,
            )
            is PointingFrame.Phase.BelowHorizon -> {
                BelowHorizonContent(phase.nextPass, frameMs)
                TextButton(onClick = onQuickLog) {
                    Text("Log the last pass", color = Color.White.copy(alpha = 0.85f))
                }
            }
            is PointingFrame.Phase.Tracking -> TrackingContent(
                frame, phase.isLocked, vm, selectedNoradId, motionState,
            )
        }
    }
}

@Composable
private fun BelowHorizonContent(nextPass: FfiSatellitePass?, frameMs: Long) {
    Text(
        "BELOW HORIZON",
        fontSize = 24.sp,
        fontWeight = FontWeight.Black,
        color = Color.White.copy(alpha = 0.8f),
    )
    if (nextPass == null) {
        Text(
            "No pass in the next 48 hours",
            style = MaterialTheme.typography.titleLarge,
            color = Color.White,
        )
        return
    }
    val secondsToAos = nextPass.aosEpoch - frameMs / 1_000
    val countdown = when {
        secondsToAos <= 0 -> "RISING"
        secondsToAos < 3_600 -> "%d:%02d".format(secondsToAos / 60, secondsToAos % 60)
        else -> "${secondsToAos / 3_600}h %02dm".format((secondsToAos / 60) % 60)
    }
    Text(
        countdown,
        fontSize = 80.sp,
        fontWeight = FontWeight.Black,
        fontFamily = FontFamily.Monospace,
        color = Color.White,
    )
    Text(
        "Rises ${pointingCompassPoint(nextPass.aosAzimuthDeg)} · max %.0f°"
            .format(nextPass.peakElevationDeg),
        fontSize = 22.sp,
        fontWeight = FontWeight.SemiBold,
        color = Color.White.copy(alpha = 0.9f),
    )
}

/** Tracking layout with a stable frame: the correction chevrons' slot and
 * the polarization hint line stay allocated in both states (invisible
 * rather than removed) and the tuning block has one size — so the
 * frequency readout never moves when lock is gained or lost. */
@Composable
private fun TrackingContent(
    frame: PointingFrame,
    isLocked: Boolean,
    vm: SatelliteViewModel,
    selectedNoradId: UInt?,
    motionState: AntennaMotionService.State,
) {
    Box(contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier.alpha(if (isLocked) 0f else 1f),
        ) {
            CorrectionReadout(frame)
        }
        if (isLocked) {
            Text(
                "◎ ON TARGET",
                fontSize = 24.sp,
                fontWeight = FontWeight.Black,
                color = Color(0xFF4CAF50),
            )
        }
    }
    TuningReadout(frame)
    PolarizationHint(vm, selectedNoradId, motionState, visible = isLocked)
}

/** Doppler-corrected tuning block: downlink, uplink, mode, Doppler shift.
 * One size in every tracking state. */
@Composable
private fun TuningReadout(frame: PointingFrame) {
    frame.downlinkMHz?.let {
        Text(
            "↓ %.3f".format(it),
            fontSize = 56.sp,
            fontWeight = FontWeight.Black,
            fontFamily = FontFamily.Monospace,
            color = Color.White,
            maxLines = 1,
        )
    }
    frame.uplinkMHz?.let {
        Text(
            "↑ %.3f".format(it),
            fontSize = 36.sp,
            fontWeight = FontWeight.Black,
            fontFamily = FontFamily.Monospace,
            color = Color.White,
            maxLines = 1,
        )
    }
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        frame.mode?.let {
            Text(
                it,
                fontSize = 20.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White.copy(alpha = 0.9f),
            )
        }
        frame.dopplerShiftKHz?.let {
            Text(
                "Doppler %+.1f kHz".format(it),
                fontSize = 20.sp,
                fontWeight = FontWeight.SemiBold,
                color = Color.White.copy(alpha = 0.9f),
            )
        }
    }
}

/** Circular birds get the static hint; linear ones the live roll. Laid out
 * even while steering (alpha 0) so gaining lock doesn't reflow the tuning
 * block above it. */
@Composable
private fun PolarizationHint(
    vm: SatelliteViewModel,
    selectedNoradId: UInt?,
    motionState: AntennaMotionService.State,
    visible: Boolean,
) {
    val polarization = selectedNoradId?.let { vm.summary(it)?.polarization }
    val matrix = motionState.rotationMatrix
    val hint = when {
        polarization != null && polarization.isCircular -> polarization.pointingHint
        matrix != null -> "Roll %.0f° — twist to peak, flip 90° if it fades"
            .format(app.carrierwave.android.sensors.RotationMatrices.elementTiltDeg(matrix))
        else -> null
    }
    hint?.let {
        Text(
            it,
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
            textAlign = TextAlign.Center,
            modifier = Modifier.alpha(if (visible) 1f else 0f),
        )
    }
}

@Composable
private fun CorrectionReadout(frame: PointingFrame) {
    val tint = statusColor(frame)
    val azError = frame.azErrorDeg ?: return
    val elError = frame.elErrorDeg ?: return
    Text(
        (if (azError < 0) "« " else "") + "%.0f°".format(kotlin.math.abs(azError)) +
            (if (azError >= 0) " »" else ""),
        fontSize = 62.sp,
        fontWeight = FontWeight.Black,
        fontFamily = FontFamily.Monospace,
        color = tint,
    )
    Text(
        (if (elError < 0) "▼ " else "▲ ") + "%.0f°".format(kotlin.math.abs(elError)),
        fontSize = 62.sp,
        fontWeight = FontWeight.Black,
        fontFamily = FontFamily.Monospace,
        color = tint,
    )
}

@Composable
private fun PointingFooter(frame: PointingFrame, motion: AntennaMotionService) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        val azimuth = frame.targetAzDeg
        val elevation = frame.targetElDeg
        if (azimuth != null && elevation != null) {
            Text(
                "AZ %03.0f°   EL %+.0f°".format(azimuth, elevation),
                fontSize = 22.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = FontFamily.Monospace,
                color = Color.White.copy(alpha = 0.9f),
            )
        }
        if (motion.boomTrimDeg() > 0.5) {
            Text(
                "Boom trim %.1f°".format(motion.boomTrimDeg()),
                style = MaterialTheme.typography.labelSmall,
                color = Color.White.copy(alpha = 0.5f),
            )
        }
    }
}

private fun pointingCompassPoint(degrees: Double): String {
    val points = listOf("N", "NE", "E", "SE", "S", "SW", "W", "NW")
    return points[(((degrees + 22.5) / 45.0).toInt()).mod(8)]
}

/** Primary record controls: the pointing screen owns capture during a
 * pass (the info card's are the sensor-free secondary). */
@Composable
private fun PointingRecordControls(noradId: UInt, satelliteName: String) {
    val context = LocalContext.current
    val recState by SatellitePassRecorder.state.collectAsStateWithLifecycle()
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) SatellitePassRecorder.start(context, noradId.toInt(), satelliteName)
    }
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 10.dp),
    ) {
        if (recState.isRecording) {
            TextButton(onClick = { SatellitePassRecorder.mark() }) {
                Text("⚑ MARK (${recState.markCount})", color = Color.White)
            }
            TextButton(onClick = { SatellitePassRecorder.stop(context) }) {
                Text("■ STOP", color = Color(0xFFE53935))
            }
        } else {
            TextButton(onClick = {
                val granted = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.RECORD_AUDIO,
                ) == PackageManager.PERMISSION_GRANTED
                if (granted) {
                    SatellitePassRecorder.start(context, noradId.toInt(), satelliteName)
                } else {
                    permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                }
            }) {
                Text("● REC", color = Color.White.copy(alpha = 0.85f))
            }
        }
    }
}
