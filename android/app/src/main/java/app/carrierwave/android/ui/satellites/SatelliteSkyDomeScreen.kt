package app.carrierwave.android.ui.satellites

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.carrierwave.android.sensors.AntennaMotionService
import app.carrierwave.android.sensors.RotationMatrices
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import uniffi.cw_ffi.FfiSatellitePosition
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.sin

/**
 * Attitude-driven sky view (port of the iOS `SatelliteSkyDomeView`, minus
 * the AR camera passthrough — cut on iOS's own advice): raise the phone
 * and pan it to see the ham satellites at their true az/el. The crosshair
 * hovers the nearest bird within 7°; tapping selects it; aiming within 5°
 * of the selected bird locks (green crosshair + haptic). Tilting below
 * −10° exits back to the chart.
 */
private const val LOCK_DEG = 5.0
private const val HOVER_DEG = 7.0
private const val EXIT_TILT_DEG = -10.0

@Composable
fun SatelliteSkyDomeScreen(
    vm: SatelliteViewModel,
    motion: AntennaMotionService,
    onClose: () -> Unit,
) {
    val ui by vm.state.collectAsStateWithLifecycle()
    val motionState by motion.state.collectAsStateWithLifecycle()
    val haptics = LocalHapticFeedback.current
    val textMeasurer = rememberTextMeasurer()

    DisposableEffect(Unit) {
        motion.start()
        onDispose { motion.stop() }
    }

    // Clock-driven redraw (~20 fps): dead-reckoned satellite motion must
    // continue even when the attitude is perfectly still.
    var frameMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (isActive) {
            frameMs = System.currentTimeMillis()
            delay(50)
        }
    }

    val matrix = motionState.rotationMatrix
    val elapsed = (frameMs - ui.positionsSyncedAtMs) / 1_000.0
    val sightings = remember(frameMs, ui.positions) {
        ui.positions.mapNotNull { position -> sighting(position, elapsed) }
    }
    val hovered = matrix?.let { m ->
        val projector = SkyProjector(m, 1f, 1f)
        sightings
            .filter { it.elDeg > -2 }
            .minByOrNull { projector.offAxisDeg(it.azDeg, it.elDeg) }
            ?.takeIf { projector.offAxisDeg(it.azDeg, it.elDeg) < HOVER_DEG }
    }
    val selectedSighting = sightings.firstOrNull { it.position.noradId == ui.selectedNoradId }
    val isOnTarget = matrix != null && selectedSighting != null && selectedSighting.elDeg > 0 &&
        SkyProjector(matrix, 1f, 1f)
            .offAxisDeg(selectedSighting.azDeg, selectedSighting.elDeg) < LOCK_DEG

    // Lock haptic on the off→on transition.
    var wasOnTarget by remember { mutableStateOf(false) }
    LaunchedEffect(isOnTarget) {
        if (isOnTarget && !wasOnTarget) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        wasOnTarget = isOnTarget
    }

    // Tilt-down exit, armed after a grace period so the raise itself
    // doesn't bounce straight back out.
    val openedAt = remember { System.currentTimeMillis() }
    LaunchedEffect(frameMs) {
        val elevation = matrix?.let { RotationMatrices.pointingElevationDeg(it) } ?: return@LaunchedEffect
        if (elevation < EXIT_TILT_DEG && frameMs - openedAt > 2_000) onClose()
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(Color(0xFF05081A), Color(0xFF0D1738)),
                ),
            )
            .pointerInput(hovered?.position?.noradId) {
                detectTapGestures {
                    hovered?.let { vm.select(it.position.noradId) }
                }
            },
    ) {
        if (matrix != null) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val projector = SkyProjector(matrix, size.width, size.height)
                drawSkyLine(projector, elevationDeg = 0.0, opacity = 0.5f)
                drawSkyLine(projector, elevationDeg = 30.0, opacity = 0.15f)
                drawSkyLine(projector, elevationDeg = 60.0, opacity = 0.15f)
                drawCardinals(projector, textMeasurer)
                drawSkyTrack(projector, vm, ui.selectedTrack, elapsedIgnored = elapsed)
                drawSatelliteDots(
                    projector,
                    sightings,
                    selectedNorad = ui.selectedNoradId,
                    hoveredNorad = hovered?.position?.noradId,
                    textMeasurer = textMeasurer,
                )
                drawCrosshair(isOnTarget)
                drawOffscreenArrow(projector, selectedSighting)
            }
        } else {
            Text(
                "Waiting for motion sensors…",
                color = Color.White.copy(alpha = 0.7f),
                modifier = Modifier.align(Alignment.Center),
            )
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
        ) {
            Surface(
                shape = RoundedCornerShape(50),
                color = Color.White.copy(alpha = 0.12f),
            ) {
                Text(
                    "Sky view — move the phone around",
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White.copy(alpha = 0.8f),
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                )
            }
            androidx.compose.foundation.layout.Spacer(modifier = Modifier.weight(1f))
            IconButton(onClick = onClose) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = "Close sky view",
                    tint = Color.White.copy(alpha = 0.8f),
                )
            }
        }
        if (motionState.accuracyLow) {
            Text(
                "Compass accuracy low — wave the phone in a figure-8",
                style = MaterialTheme.typography.labelSmall,
                color = Color(0xFFFFB74D),
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 64.dp),
            )
        }
        SkyDomeFooter(
            vm = vm,
            hovered = hovered,
            selected = selectedSighting,
            selectedNoradId = ui.selectedNoradId,
            isOnTarget = isOnTarget,
            elementTiltDeg = matrix?.let { RotationMatrices.elementTiltDeg(it) },
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 16.dp),
        )
    }
}

/** A satellite with its dead-reckoned az/el at render time. */
data class SkySighting(
    val position: FfiSatellitePosition,
    val azDeg: Double,
    val elDeg: Double,
)

private fun sighting(position: FfiSatellitePosition, elapsedSecs: Double): SkySighting? {
    val az = position.azimuthDeg ?: return null
    val el = position.elevationDeg ?: return null
    return SkySighting(
        position = position,
        azDeg = wrapAzimuth(az + position.azRateDegPerSec * elapsedSecs),
        elDeg = el + position.elRateDegPerSec * elapsedSecs,
    )
}

private fun wrapAzimuth(degrees: Double): Double {
    var value = degrees % 360.0
    if (value < 0) value += 360.0
    return value
}

// MARK: drawing

private fun DrawScope.drawSkyLine(
    projector: SkyProjector,
    elevationDeg: Double,
    opacity: Float,
) {
    val path = Path()
    var previous: Pair<Float, Float>? = null
    var azimuth = 0.0
    while (azimuth <= 360.0) {
        val point = projector.project(azimuth, elevationDeg)
        val last = previous
        if (point != null && last != null &&
            kotlin.math.abs(point.first - last.first) < 200 &&
            kotlin.math.abs(point.second - last.second) < 200
        ) {
            path.lineTo(point.first, point.second)
        } else if (point != null) {
            path.moveTo(point.first, point.second)
        }
        previous = point
        azimuth += 3.0
    }
    drawPath(
        path,
        color = Color.White.copy(alpha = opacity),
        style = Stroke(
            width = if (elevationDeg == 0.0) 1.5.dp.toPx() else 1.dp.toPx(),
            pathEffect = if (elevationDeg == 0.0) {
                null
            } else {
                PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 6.dp.toPx()))
            },
        ),
    )
}

private fun DrawScope.drawCardinals(projector: SkyProjector, textMeasurer: TextMeasurer) {
    for ((label, azimuth) in listOf("N" to 0.0, "E" to 90.0, "S" to 180.0, "W" to 270.0)) {
        val point = projector.project(azimuth, 2.0) ?: continue
        val layout = textMeasurer.measure(
            label,
            style = TextStyle(
                color = Color.White.copy(alpha = 0.7f),
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp,
            ),
        )
        drawText(
            layout,
            topLeft = Offset(
                point.first - layout.size.width / 2f,
                point.second - layout.size.height / 2f,
            ),
        )
    }
}

@Suppress("UNUSED_PARAMETER")
private fun DrawScope.drawSkyTrack(
    projector: SkyProjector,
    vm: SatelliteViewModel,
    track: List<FfiSatellitePosition>,
    elapsedIgnored: Double,
) {
    // The track is a fixed pass arc — no dead reckoning, iOS parity.
    val path = Path()
    var previous: Pair<Float, Float>? = null
    for (point in track) {
        val az = point.azimuthDeg
        val el = point.elevationDeg
        val screen = if (az != null && el != null && el > 0) projector.project(az, el) else null
        val last = previous
        if (screen != null && last != null &&
            kotlin.math.abs(screen.first - last.first) < 300 &&
            kotlin.math.abs(screen.second - last.second) < 300
        ) {
            path.lineTo(screen.first, screen.second)
        } else if (screen != null) {
            path.moveTo(screen.first, screen.second)
        }
        previous = screen
    }
    drawPath(
        path,
        color = Color(0xFFFF9800).copy(alpha = 0.55f),
        style = Stroke(
            width = 1.5.dp.toPx(),
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 4.dp.toPx())),
        ),
    )
}

private fun DrawScope.drawSatelliteDots(
    projector: SkyProjector,
    sightings: List<SkySighting>,
    selectedNorad: UInt?,
    hoveredNorad: UInt?,
    textMeasurer: TextMeasurer,
) {
    val centerX = size.width / 2
    val centerY = size.height / 2
    for (sighting in sightings) {
        if (sighting.elDeg <= -2) continue
        val point = projector.project(sighting.azDeg, sighting.elDeg) ?: continue
        val isSelected = sighting.position.noradId == selectedNorad
        val isHovered = sighting.position.noradId == hoveredNorad
        val offset = Offset(point.first, point.second)
        if (isHovered) {
            drawCircle(
                color = Color.White.copy(alpha = 0.8f),
                radius = 15.dp.toPx(),
                center = offset,
                style = Stroke(
                    width = 1.dp.toPx(),
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx())),
                ),
            )
        }
        if (isSelected) {
            drawCircle(
                color = Color(0xFFFF9800),
                radius = 11.dp.toPx(),
                center = offset,
                style = Stroke(width = 1.5.dp.toPx()),
            )
            drawCircle(color = Color(0xFFFF9800), radius = 5.dp.toPx(), center = offset)
        } else {
            drawCircle(
                color = if (isHovered) Color.White else Color(0xFF26A69A).copy(alpha = 0.9f),
                radius = (if (isHovered) 4 else 3).dp.toPx(),
                center = offset,
            )
        }
        val distanceToCenter = hypot(point.first - centerX, point.second - centerY)
        if (isSelected || isHovered || distanceToCenter < 80.dp.toPx()) {
            val layout = textMeasurer.measure(
                sighting.position.name,
                style = TextStyle(
                    color = when {
                        isSelected -> Color(0xFFFF9800)
                        isHovered -> Color.White
                        else -> Color.White.copy(alpha = 0.8f)
                    },
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = if (isHovered) FontWeight.Bold else FontWeight.Normal,
                ),
            )
            drawText(
                layout,
                topLeft = Offset(
                    point.first - layout.size.width / 2f,
                    point.second - 16.dp.toPx() - layout.size.height / 2f,
                ),
            )
        }
    }
}

private fun DrawScope.drawCrosshair(isOnTarget: Boolean) {
    drawCircle(
        color = if (isOnTarget) Color(0xFF4CAF50) else Color.White.copy(alpha = 0.6f),
        radius = 14.dp.toPx(),
        center = Offset(size.width / 2, size.height / 2),
        style = Stroke(width = (if (isOnTarget) 2.5 else 1.5).dp.toPx()),
    )
}

private fun DrawScope.drawOffscreenArrow(projector: SkyProjector, selected: SkySighting?) {
    val sighting = selected ?: return
    if (sighting.elDeg <= 0) return
    val visible = projector.project(sighting.azDeg, sighting.elDeg)
    if (visible != null && projector.offAxisDeg(sighting.azDeg, sighting.elDeg) <= 60) return
    val (dx, dy) = projector.screenDirection(sighting.azDeg, sighting.elDeg)
    val centerX = size.width / 2
    val centerY = size.height / 2
    val radius = min(size.width, size.height) / 2 - 50.dp.toPx()
    val tipX = centerX + dx * radius
    val tipY = centerY + dy * radius
    val angle = atan2(dy, dx)
    val arm = 18.dp.toPx()
    val arrow = Path().apply {
        moveTo(tipX, tipY)
        lineTo(tipX - arm * cos(angle - 0.4f), tipY - arm * sin(angle - 0.4f))
        lineTo(tipX - arm * cos(angle + 0.4f), tipY - arm * sin(angle + 0.4f))
        close()
    }
    drawPath(arrow, color = Color(0xFFFF9800))
}
