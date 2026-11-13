package app.carrierwave.android.ui.map

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import uniffi.cw_ffi.FfiQsoDetailMap
import uniffi.cw_ffi.MapApi
import java.util.Locale

/**
 * Compact per-QSO map card for the shared QSO detail/edit surface (Logbook,
 * Hunter log, Session detail). Loads `mapApi.qsoDetailMap(qsoId)` on IO and
 * renders my/their pins, the connecting arc, and a distance/bearing footer.
 * Hidden while loading; omitted silently on failure or when neither station
 * has a plottable location — matches iOS, which never shows a broken map.
 */
@Composable
fun QsoDetailMapCard(mapApi: MapApi, qsoId: String, modifier: Modifier = Modifier) {
    var detail by remember(qsoId) { mutableStateOf<FfiQsoDetailMap?>(null) }

    LaunchedEffect(qsoId) {
        detail = runCatching {
            withContext(Dispatchers.IO) { mapApi.qsoDetailMap(qsoId.lowercase()) }
        }.getOrNull()
    }

    val data = detail ?: return
    if (data.my == null && data.their == null) return

    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp)),
    ) {
        AndroidView(
            modifier = Modifier
                .fillMaxWidth()
                .height(220.dp),
            factory = { ctx -> buildDetailMapView(ctx, data) },
            update = { map -> renderDetailMap(map, data) },
        )
        DistanceBearingFooter(data)
    }
}

private fun buildDetailMapView(ctx: Context, data: FfiQsoDetailMap): MapView {
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
        (data.my ?: data.their)?.let { controller.setCenter(GeoPoint(it.latitude, it.longitude)) }
    }
}

private fun renderDetailMap(map: MapView, data: FfiQsoDetailMap) {
    map.overlays.clear()

    addPolylines(map, data.arc)

    val points = mutableListOf<GeoPoint>()
    data.my?.let { coord ->
        val point = GeoPoint(coord.latitude, coord.longitude)
        points += point
        map.overlays.add(
            Marker(map).apply {
                position = point
                title = "My station"
                setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
            },
        )
    }
    data.their?.let { coord ->
        val point = GeoPoint(coord.latitude, coord.longitude)
        points += point
        map.overlays.add(
            Marker(map).apply {
                position = point
                title = "Their station"
                setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
            },
        )
    }

    frameBoundingBox(map, points)
    map.invalidate()
}

@Composable
private fun DistanceBearingFooter(data: FfiQsoDetailMap) {
    val distanceKm = data.distanceKm
    val bearing = data.bearing
    if (distanceKm == null && bearing == null) return

    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(
            Icons.Filled.LocationOn,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.height(16.dp),
        )
        val label = buildString {
            if (distanceKm != null) {
                val miles = distanceKm * 0.621371
                append(String.format(Locale.US, "%d km / %d mi", distanceKm.toInt(), miles.toInt()))
            }
            if (bearing != null) {
                if (distanceKm != null) append(" · ")
                append(String.format(Locale.US, "%d° %s", bearing.toInt(), cardinalDirection(bearing)))
            }
        }
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** 8-point compass direction, ported from iOS `CallsignMapSection.cardinalDirection`. */
internal fun cardinalDirection(degrees: Double): String {
    val directions = listOf("N", "NE", "E", "SE", "S", "SW", "W", "NW")
    val index = (((degrees + 22.5) / 45.0).toInt()).mod(8)
    return directions[index]
}
