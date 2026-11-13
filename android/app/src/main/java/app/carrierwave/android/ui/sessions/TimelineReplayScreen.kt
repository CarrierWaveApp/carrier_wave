package app.carrierwave.android.ui.sessions

import android.content.Context
import android.graphics.Color as AndroidColor
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.carrierwave.android.ui.map.dotMarker
import app.carrierwave.android.ui.map.frameBoundingBox
import app.carrierwave.android.ui.map.snrColor
import java.util.Locale
import kotlin.math.floor
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import uniffi.cw_ffi.FfiTimelineData
import uniffi.cw_ffi.FfiTimelineEvent
import uniffi.cw_ffi.timelineSnrColorBand
import uniffi.cw_ffi.timelineSnrMarkerSize
import uniffi.cw_ffi.timelineSpotDecay
import uniffi.cw_ffi.timelineSpotOpacity

/** RBN spots older than this (seconds) stop being drawn — iOS `TimelineMapView.visibleSpots` decayLimit. */
private const val SPOT_DECAY_LIMIT_SECS = 600.0

/**
 * Whole-second playback cutoff — event timestamps are whole seconds, so
 * flooring [currentTime] once (rather than truncating via `.toLong()` at
 * each call site) gives a single consistent key for both render throttling
 * and visibility filtering. Matches iOS, which compares against a `Date`
 * derived from `sessionStartedAt.addingTimeInterval(currentTime)` — no
 * separate truncation step, but since events are second-granular the
 * effective comparison is the same whole-second boundary.
 */
private fun cutoffEpochSecs(data: FfiTimelineData, currentTime: Double): Long =
    data.startedAt + floor(currentTime).toLong()

/** QSO events visible (persisted) at [cutoff] — shared by map rendering and the count label. */
private fun visibleQsos(data: FfiTimelineData, cutoff: Long): List<FfiTimelineEvent> =
    data.events.filter { it.isQso && it.timestamp <= cutoff }

/** RBN spot events visible (not yet decayed) at [cutoff] — shared by map rendering and the count label. */
private fun visibleSpots(data: FfiTimelineData, cutoff: Long): List<FfiTimelineEvent> =
    data.events.filter { event ->
        !event.isQso && event.timestamp <= cutoff && (cutoff - event.timestamp) < SPOT_DECAY_LIMIT_SECS.toLong()
    }

/** "Unknown" fallback for a missing spot band — parity with iOS `TimelineMapEvent.init(ffi:)`. */
private val FfiTimelineEvent.displayBand: String
    get() = band ?: "Unknown"

/**
 * Session replay — full-screen interactive map that plays a session's QSOs
 * and RBN spots back over time, driven by the shared Rust
 * `MapApi.sessionTimeline` and timeline curve functions. Android analog of
 * iOS `TimelineMapView`: a scrubber + play/pause/speed transport at the
 * bottom, QSO pins that persist once their timestamp passes, and RBN spot
 * dots that fade per [timelineSpotOpacity]/[timelineSpotDecay] and disappear
 * past [SPOT_DECAY_LIMIT_SECS].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimelineReplayScreen(vm: TimelineReplayViewModel, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val ui by vm.ui.collectAsStateWithLifecycle()

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                // Nested inside the app's main Scaffold, which already clears the
                // status bar — zero this bar's insets so it doesn't re-add a
                // status-bar-height gap above the title (CAR-294).
                windowInsets = WindowInsets(0, 0, 0, 0),
                title = { Text("Session Replay") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            val data = ui.data
            if (ui.loading || data == null) {
                Box(Modifier.weight(1f).fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            } else {
                Box(Modifier.weight(1f)) {
                    TimelineMap(data = data, currentTime = ui.currentTime, modifier = Modifier.fillMaxSize())
                }
                TimelineControls(vm = vm, data = data, ui = ui)
            }
        }
    }
}

/** Identity of the last render pass — guards [TimelineMap]'s `update` against redundant rebuilds. */
private data class RenderKey(val cutoff: Long, val dataIdentity: FfiTimelineData?)

@Composable
private fun TimelineMap(data: FfiTimelineData, currentTime: Double, modifier: Modifier = Modifier) {
    // Plain holder, not MutableState — framing runs once per map lifetime,
    // matching iOS's first-load-only camera fit (see MapScreen's OsmMap).
    val framedInitialBounds = remember { booleanArrayOf(false) }

    // Event timestamps are whole seconds, so during playback (~30 ticks/sec)
    // most `update` invocations would rebuild an overlay list identical to the
    // last one. Track the last cutoff second + data identity we actually
    // rendered and skip rebuilding when neither changed — this cuts rebuilds
    // from ~30/s to roughly speed-multiplier/s while scrubbing still
    // re-renders on every new second crossed.
    val lastRendered = remember { arrayOfNulls<RenderKey>(1) }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            Configuration.getInstance().load(ctx, ctx.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
            Configuration.getInstance().userAgentValue = ctx.packageName
            MapView(ctx).apply {
                setTileSource(TileSourceFactory.MAPNIK)
                setMultiTouchControls(true)
                controller.setZoom(3.0)
            }
        },
        update = { map ->
            val cutoff = cutoffEpochSecs(data, currentTime)
            val key = RenderKey(cutoff, data)
            if (lastRendered[0] != key) {
                lastRendered[0] = key
                renderTimeline(map, data, cutoff)
            }
            if (!framedInitialBounds[0]) {
                val points = buildList {
                    val myLat = data.myLatitude
                    val myLon = data.myLongitude
                    if (myLat != null && myLon != null) {
                        add(GeoPoint(myLat, myLon))
                    }
                    data.events.forEach { event ->
                        val lat = event.latitude
                        val lon = event.longitude
                        if (lat != null && lon != null) {
                            add(GeoPoint(lat, lon))
                        }
                    }
                }
                if (points.isNotEmpty()) {
                    framedInitialBounds[0] = true
                    frameBoundingBox(map, points)
                }
            }
            map.invalidate()
        },
    )
}

private fun renderTimeline(map: MapView, data: FfiTimelineData, cutoff: Long) {
    map.overlays.clear()

    val myLat = data.myLatitude
    val myLon = data.myLongitude
    if (myLat != null && myLon != null) {
        map.overlays.add(
            dotMarker(
                map = map,
                center = GeoPoint(myLat, myLon),
                radiusDegrees = HOME_DOT_RADIUS_DEGREES,
                fillColor = AndroidColor.RED,
                title = "Home",
            ),
        )
    }

    // QSOs: once their timestamp passes, they persist for the rest of playback
    // (iOS `visibleQSOs`).
    visibleQsos(data, cutoff).forEach { event ->
        val lat = event.latitude
        val lon = event.longitude
        if (lat != null && lon != null) {
            map.overlays.add(
                Marker(map).apply {
                    position = GeoPoint(lat, lon)
                    title = event.callsign
                    setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                },
            )
        }
    }

    // RBN spots: fade in per timelineSpotOpacity/timelineSpotDecay, gone past
    // the decay limit (iOS `visibleSpots`).
    visibleSpots(data, cutoff).forEach { event ->
        val lat = event.latitude
        val lon = event.longitude
        if (lat == null || lon == null) return@forEach
        val age = (cutoff - event.timestamp).toDouble()

        val opacity = timelineSpotOpacity(age)
        val decay = timelineSpotDecay(age)
        val snr = event.snr
        val baseSize = timelineSnrMarkerSize(snr)
        val color = if (snr != null) snrColor(timelineSnrColorBand(snr)) else AndroidColor.rgb(0, 200, 0)
        val alphaColor = AndroidColor.argb(
            (opacity.coerceIn(0.0, 1.0) * 255).toInt(),
            AndroidColor.red(color),
            AndroidColor.green(color),
            AndroidColor.blue(color),
        )
        map.overlays.add(
            dotMarker(
                map = map,
                center = GeoPoint(lat, lon),
                radiusDegrees = SPOT_BASE_RADIUS_DEGREES * (baseSize / BASE_MARKER_SIZE_DP).coerceIn(0.3, 3.0) * decay,
                fillColor = alphaColor,
                title = spotLabel(event),
            ),
        )
    }
}

/**
 * "SPOTTER SNRdB" — port of iOS `TimelineMapView.spotLabel`. Band isn't
 * displayed here, but callers that add it should read [FfiTimelineEvent.displayBand]
 * (never the raw nullable `band`) so a future label addition can't regress to
 * a blank/null band — see [displayBand] for the "Unknown" fallback, parity
 * with iOS `TimelineMapEvent.init(ffi:)`.
 */
private fun spotLabel(event: FfiTimelineEvent): String {
    val snr = event.snr
    return if (snr != null) "${event.spotter ?: "RBN"} ${snr}dB" else (event.spotter ?: "RBN")
}

@Composable
private fun TimelineControls(vm: TimelineReplayViewModel, data: FfiTimelineData, ui: TimelineReplayUiState) {
    val duration = (data.endedAt - data.startedAt).toDouble().coerceAtLeast(0.0)
    val cutoff = cutoffEpochSecs(data, ui.currentTime)

    Surface(tonalElevation = 2.dp) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    formatElapsed(ui.currentTime),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    "-${formatElapsed((duration - ui.currentTime).coerceAtLeast(0.0))}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Box(Modifier.fillMaxWidth()) {
                TimelineTickMarks(
                    data = data,
                    duration = duration,
                    modifier = Modifier.fillMaxWidth().height(TICK_OVERLAY_HEIGHT_DP),
                )
                Slider(
                    value = ui.currentTime.toFloat().coerceIn(0f, duration.toFloat()),
                    onValueChange = { vm.seek(it.toDouble()) },
                    valueRange = 0f..duration.toFloat().coerceAtLeast(0f),
                )
            }
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = vm::togglePlayback) {
                        Icon(
                            if (ui.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            contentDescription = if (ui.isPlaying) "Pause" else "Play",
                        )
                    }
                    Surface(
                        onClick = vm::cycleSpeed,
                        shape = MaterialTheme.shapes.small,
                        color = MaterialTheme.colorScheme.surfaceVariant,
                    ) {
                        Text(
                            "${formatSpeed(ui.speed)}x",
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                            style = MaterialTheme.typography.labelLarge,
                        )
                    }
                }
                val qsoCount = visibleQsos(data, cutoff).size
                val spotCount = visibleSpots(data, cutoff).size
                Text(
                    "$qsoCount QSOs · $spotCount spots",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/**
 * Thin vertical tick per timeline event along the scrubber track — QSOs in
 * blue (taller), RBN spots in green (shorter). Port of iOS
 * `TimelineSliderView.tickMarksOverlay`; drawn behind the [Slider] so the
 * track and thumb remain interactive (`Canvas` here doesn't consume touch
 * input, unlike iOS's `.allowsHitTesting(false)` which achieves the same).
 */
@Composable
private fun TimelineTickMarks(data: FfiTimelineData, duration: Double, modifier: Modifier = Modifier) {
    Canvas(modifier = modifier) {
        if (duration <= 0.0) return@Canvas
        val trackWidth = size.width
        val centerY = size.height / 2f
        data.events.forEach { event ->
            val offsetSecs = (event.timestamp - data.startedAt).toDouble()
            val fraction = (offsetSecs / duration).coerceIn(0.0, 1.0)
            val xPos = (fraction * trackWidth).toFloat()
            val tickHeightDp = if (event.isQso) QSO_TICK_HEIGHT_DP else SPOT_TICK_HEIGHT_DP
            val tickHeightPx = tickHeightDp.toPx()
            val color = if (event.isQso) TICK_COLOR_QSO else TICK_COLOR_SPOT
            drawLine(
                color = color,
                start = Offset(xPos, centerY - tickHeightPx / 2f),
                end = Offset(xPos, centerY + tickHeightPx / 2f),
                strokeWidth = TICK_STROKE_WIDTH_PX,
            )
        }
    }
}

/** mm:ss, or h:mm:ss past one hour — port of iOS `TimelineSliderView.formatElapsed`. */
private fun formatElapsed(seconds: Double): String {
    val totalSeconds = seconds.coerceAtLeast(0.0).toLong()
    val hrs = totalSeconds / 3_600
    val mins = (totalSeconds % 3_600) / 60
    val secs = totalSeconds % 60
    return if (hrs > 0) {
        String.format(Locale.US, "%d:%02d:%02d", hrs, mins, secs)
    } else {
        String.format(Locale.US, "%d:%02d", mins, secs)
    }
}

private fun formatSpeed(speed: Double): String =
    if (speed == speed.toLong().toDouble()) speed.toLong().toString() else String.format(Locale.US, "%.1f", speed)

private const val HOME_DOT_RADIUS_DEGREES = 0.05
private const val SPOT_BASE_RADIUS_DEGREES = 0.35
private const val BASE_MARKER_SIZE_DP = 12.0

/** Tick-mark overlay sizing/coloring — port of iOS `TimelineSliderView` tick constants. */
private val TICK_OVERLAY_HEIGHT_DP = 28.dp
private val QSO_TICK_HEIGHT_DP = 14.dp
private val SPOT_TICK_HEIGHT_DP = 8.dp
private const val TICK_STROKE_WIDTH_PX = 2f
private val TICK_COLOR_QSO = Color(0xFF2196F3).copy(alpha = 0.7f) // iOS `.blue.opacity(0.7)`
private val TICK_COLOR_SPOT = Color(0xFF4CAF50).copy(alpha = 0.7f) // iOS `.green.opacity(0.7)`
