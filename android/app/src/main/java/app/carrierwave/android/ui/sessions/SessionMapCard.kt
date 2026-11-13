package app.carrierwave.android.ui.sessions

import android.content.Context
import android.graphics.Color as AndroidColor
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import app.carrierwave.android.ui.map.addArcs
import app.carrierwave.android.ui.map.dotMarker
import app.carrierwave.android.ui.map.frameBounds
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import uniffi.cw_ffi.FfiSessionMapData
import uniffi.cw_ffi.MapApi

/**
 * Compact session-detail map card over `mapApi.sessionMap(sessionId)`:
 * individual QSO pins (session maps never cluster), rove-stop markers, and
 * home→contact arcs, framed by the Rust-computed bounds. Loads on IO;
 * hidden until data arrives and silently omitted on failure or an empty
 * result — matches [app.carrierwave.android.ui.map.QsoDetailMapCard], which
 * never shows a broken map.
 *
 * Below the map, a "Replay" row opens [TimelineReplayScreen] for this session
 * (Phase B Task 14) — always shown once the card itself has data, since a
 * session with plottable QSOs also has a timeline to replay.
 */
@Composable
fun SessionMapCard(mapApi: MapApi, sessionId: String, onReplay: () -> Unit, modifier: Modifier = Modifier) {
    var data by remember(sessionId) { mutableStateOf<FfiSessionMapData?>(null) }

    LaunchedEffect(sessionId) {
        data = runCatching {
            withContext(Dispatchers.IO) { mapApi.sessionMap(sessionId.lowercase()) }
        }.getOrNull()
    }

    val session = data ?: return
    if (session.annotations.isEmpty() && session.roveStops.isEmpty()) return

    Column(modifier) {
        AndroidView(
            modifier = Modifier
                .fillMaxWidth()
                .height(220.dp)
                .clip(RoundedCornerShape(12.dp)),
            factory = { ctx -> buildSessionMapView(ctx, session) },
            update = { map -> renderSessionMap(map, session) },
        )
        Row(
            Modifier.fillMaxWidth().padding(top = 4.dp),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = onReplay) {
                Icon(
                    Icons.Filled.PlayCircle,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.height(18.dp),
                )
                Text(" Replay")
            }
        }
    }
}

private fun buildSessionMapView(ctx: Context, data: FfiSessionMapData): MapView {
    Configuration.getInstance().load(ctx, ctx.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
    Configuration.getInstance().userAgentValue = ctx.packageName
    return MapView(ctx).apply {
        setTileSource(TileSourceFactory.MAPNIK)
        setMultiTouchControls(false)
        // Non-interactive: parity with iOS `.allowsHitTesting(false)` — this card lives
        // inside a scrolling sheet and must not steal single-finger pan/scroll gestures.
        isClickable = false
        setOnTouchListener { _, _ -> true }
        controller.setZoom(3.0)
        (data.annotations.firstOrNull()?.let { GeoPoint(it.latitude, it.longitude) }
            ?: data.roveStops.firstOrNull()?.let { GeoPoint(it.latitude, it.longitude) })
            ?.let { controller.setCenter(it) }
    }
}

private fun renderSessionMap(map: MapView, data: FfiSessionMapData) {
    map.overlays.clear()

    addArcs(map, data.arcs)

    data.annotations.forEach { annotation ->
        map.overlays.add(
            Marker(map).apply {
                position = GeoPoint(annotation.latitude, annotation.longitude)
                title = if (annotation.qsoCount == 1L) {
                    annotation.callsigns.firstOrNull() ?: annotation.gridSquare
                } else {
                    "${annotation.gridSquare} (${annotation.qsoCount})"
                }
                setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
            },
        )
    }

    data.roveStops.forEach { stop ->
        map.overlays.add(
            dotMarker(
                map = map,
                center = GeoPoint(stop.latitude, stop.longitude),
                radiusDegrees = ROVE_STOP_DOT_RADIUS_DEGREES,
                fillColor = AndroidColor.rgb(255, 165, 0),
                title = "Rove stop",
            ),
        )
    }

    val bounds = data.bounds
    if (bounds != null) {
        frameBounds(map, bounds)
    }
    map.invalidate()
}

private const val ROVE_STOP_DOT_RADIUS_DEGREES = 0.03
