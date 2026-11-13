package app.carrierwave.android.ui.satellites

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.hypot
import kotlin.math.roundToInt
import uniffi.cw_ffi.FfiCoordinate

/**
 * QTH-centered azimuthal-equidistant sky chart: range rings, coastlines,
 * live satellite dots, selected footprint + ground track, compass letters.
 * Port of the iOS `SatelliteAzimuthalMapView` draw plan (north-up on this
 * surface; the sensor screens reuse [AzimuthalChartFrame] with a heading).
 * Tap selects the nearest dot; drag pans (inverse-projection recenter);
 * pinch zooms. Coastline paths are cached per (center, zoom, size) — with
 * a north-up chart they only change on pan/zoom, never per tick.
 */
@Composable
fun SatelliteAzimuthalChart(
    vm: SatelliteViewModel,
    ui: SatelliteViewModel.UiState,
    modifier: Modifier = Modifier,
) {
    val observer = vm.observer ?: return
    var centerLat by remember { mutableStateOf(observer.latDeg) }
    var centerLon by remember { mutableStateOf(observer.lonDeg) }
    var zoom by remember { mutableStateOf(1f) }
    var coastlines by remember { mutableStateOf<List<List<FfiCoordinate>>>(emptyList()) }
    LaunchedEffect(Unit) { coastlines = vm.coastlines() }

    val textMeasurer = rememberTextMeasurer()
    val ringColor = MaterialTheme.colorScheme.outlineVariant
    val coastColor = MaterialTheme.colorScheme.outline
    val dotColor = MaterialTheme.colorScheme.primary
    val selectedColor = MaterialTheme.colorScheme.tertiary
    val labelColor = MaterialTheme.colorScheme.onSurfaceVariant

    Canvas(
        modifier = modifier
            .pointerInput(ui.positions, zoom, centerLat, centerLon) {
                detectTapGestures { tap ->
                    val frame = AzimuthalChartFrame(
                        size.width.toFloat(), size.height.toFloat(),
                        centerLat, centerLon, 0.0, zoom,
                    )
                    val hit = ui.positions.minByOrNull { pos ->
                        val (x, y) = frame.point(pos.latDeg, pos.lonDeg)
                        hypot(x - tap.x, y - tap.y)
                    } ?: return@detectTapGestures
                    val (x, y) = frame.point(hit.latDeg, hit.lonDeg)
                    if (hypot(x - tap.x, y - tap.y) <= 24.dp.toPx()) {
                        vm.select(hit.noradId)
                    } else {
                        vm.select(null)
                    }
                }
            }
            .pointerInput(Unit) {
                detectTransformGestures { centroid, pan, gestureZoom, _ ->
                    zoom = (zoom * gestureZoom).coerceIn(0.5f, 8f)
                    if (pan != Offset.Zero) {
                        val frame = AzimuthalChartFrame(
                            size.width.toFloat(), size.height.toFloat(),
                            centerLat, centerLon, 0.0, zoom,
                        )
                        // Commit the drag: the coordinate that was under the
                        // centroid before the pan becomes the new center's
                        // offset (iOS inverse-projection trick).
                        val (lat, lon) = frame.coordinateAt(
                            frame.screenCenterX - pan.x,
                            frame.screenCenterY - pan.y,
                        )
                        centerLat = lat
                        centerLon = lon
                    }
                    // centroid unused — projection center stays on screen center.
                    @Suppress("UNUSED_EXPRESSION")
                    centroid
                }
            },
    ) {
        val frame = AzimuthalChartFrame(
            size.width, size.height, centerLat, centerLon, 0.0, zoom,
        )
        // Range rings at 25/50/75/100% of the disk.
        for (fraction in listOf(0.25f, 0.5f, 0.75f, 1f)) {
            drawCircle(
                color = ringColor,
                radius = frame.diskRadius * fraction,
                center = Offset(frame.screenCenterX, frame.screenCenterY),
                style = Stroke(width = 1f),
            )
        }
        // Coastlines with antipode-tear breaks.
        val breakDistance = frame.diskRadius / 2f
        for (polyline in coastlines) {
            val path = Path()
            var lastX = Float.NaN
            var lastY = Float.NaN
            for (vertex in polyline) {
                val (x, y) = frame.point(vertex.latitude, vertex.longitude)
                if (lastX.isNaN() || hypot(x - lastX, y - lastY) > breakDistance) {
                    path.moveTo(x, y)
                } else {
                    path.lineTo(x, y)
                }
                lastX = x
                lastY = y
            }
            drawPath(path, color = coastColor, style = Stroke(width = 1f))
        }
        // Selected footprint + ground track.
        val selected = ui.selectedNoradId
        val selectedPos = ui.positions.firstOrNull { it.noradId == selected }
        if (selectedPos != null) {
            val footprintPath = Path()
            val radiusRad = selectedPos.footprintRadiusM / 6_371_000.0
            for (step in 0..90) {
                val bearing = step * 4.0
                val (lat, lon) = destination(
                    selectedPos.latDeg, selectedPos.lonDeg, bearing, radiusRad,
                )
                val (x, y) = frame.point(lat, lon)
                if (step == 0) footprintPath.moveTo(x, y) else footprintPath.lineTo(x, y)
            }
            footprintPath.close()
            drawPath(footprintPath, color = selectedColor.copy(alpha = 0.15f))
            drawPath(footprintPath, color = selectedColor, style = Stroke(width = 1.5f))

            val trackPath = Path()
            var lastX = Float.NaN
            var lastY = Float.NaN
            for (sample in ui.selectedTrack) {
                val (x, y) = frame.point(sample.latDeg, sample.lonDeg)
                if (lastX.isNaN() || hypot(x - lastX, y - lastY) > breakDistance) {
                    trackPath.moveTo(x, y)
                } else {
                    trackPath.lineTo(x, y)
                }
                lastX = x
                lastY = y
            }
            drawPath(trackPath, color = selectedColor, style = Stroke(width = 2f))
        }
        // Satellite dots.
        for (pos in ui.positions) {
            val (x, y) = frame.point(pos.latDeg, pos.lonDeg)
            val isSelected = pos.noradId == selected
            drawCircle(
                color = if (isSelected) selectedColor else dotColor,
                radius = if (isSelected) 7.dp.toPx() else 4.dp.toPx(),
                center = Offset(x, y),
            )
        }
        // Selected name label. Pre-measured overload: the dot can sit far
        // off-canvas at high zoom, and drawText(text, topLeft) builds its
        // constraints from size - topLeft — negative past the edge → crash.
        if (selectedPos != null) {
            val (x, y) = frame.point(selectedPos.latDeg, selectedPos.lonDeg)
            val layout = textMeasurer.measure(
                selectedPos.name,
                style = TextStyle(color = selectedColor, fontSize = 12.sp),
            )
            drawText(layout, topLeft = Offset(x + 10f, y - 8f))
        }
        // Compass letters.
        for ((bearing, letter) in listOf(0.0 to "N", 90.0 to "E", 180.0 to "S", 270.0 to "W")) {
            val (x, y) = frame.compassPoint(bearing)
            drawText(
                textMeasurer = textMeasurer,
                text = letter,
                topLeft = Offset(x - 6f, y - 8f),
                style = TextStyle(color = labelColor, fontSize = 11.sp),
            )
        }
    }
}

/** Great-circle destination point (spherical Earth) for the footprint ring. */
private fun destination(
    latDeg: Double,
    lonDeg: Double,
    bearingDeg: Double,
    angularRad: Double,
): Pair<Double, Double> {
    val lat = Math.toRadians(latDeg)
    val lon = Math.toRadians(lonDeg)
    val bearing = Math.toRadians(bearingDeg)
    val destLat = kotlin.math.asin(
        kotlin.math.sin(lat) * kotlin.math.cos(angularRad) +
            kotlin.math.cos(lat) * kotlin.math.sin(angularRad) * kotlin.math.cos(bearing),
    )
    val destLon = lon + kotlin.math.atan2(
        kotlin.math.sin(bearing) * kotlin.math.sin(angularRad) * kotlin.math.cos(lat),
        kotlin.math.cos(angularRad) - kotlin.math.sin(lat) * kotlin.math.sin(destLat),
    )
    var lonOut = Math.toDegrees(destLon)
    if (lonOut > 180) lonOut -= 360
    if (lonOut < -180) lonOut += 360
    return Pair(Math.toDegrees(destLat), lonOut)
}
