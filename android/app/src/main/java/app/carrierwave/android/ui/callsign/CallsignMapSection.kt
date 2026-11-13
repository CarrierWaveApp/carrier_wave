package app.carrierwave.android.ui.callsign

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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import app.carrierwave.android.ui.map.cardinalDirection
import app.carrierwave.android.ui.map.frameBoundingBox
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import uniffi.cw_ffi.FfiCoordinate
import uniffi.cw_ffi.maidenheadBearing
import uniffi.cw_ffi.maidenheadCoordinate
import uniffi.cw_ffi.maidenheadDistanceKm
import java.util.Locale

/**
 * Compact single-pin map card showing the other station's grid-square
 * location, with a distance/bearing label from the operator's home grid.
 * Android analog of iOS `CallsignMapSection` — Android has no separate
 * callsign-history screen, so this is embedded in the QSO detail surface's
 * callsign header. Renders nothing if the grid doesn't resolve to a
 * coordinate (matches iOS, which only shows the section when the grid is
 * valid).
 */
@Composable
fun CallsignMapSection(grid: String, callsign: String, homeGrid: String, modifier: Modifier = Modifier) {
    val center = remember(grid) { maidenheadCoordinate(grid) } ?: return

    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp)),
    ) {
        AndroidView(
            modifier = Modifier
                .fillMaxWidth()
                .height(150.dp),
            factory = { ctx -> buildCallsignMapView(ctx, center) },
            update = { map -> renderCallsignMap(map, center, callsign) },
        )
        DistanceBearingLabel(grid, homeGrid)
    }
}

private fun buildCallsignMapView(ctx: Context, center: FfiCoordinate): MapView {
    Configuration.getInstance().load(ctx, ctx.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
    Configuration.getInstance().userAgentValue = ctx.packageName
    return MapView(ctx).apply {
        setTileSource(TileSourceFactory.MAPNIK)
        setMultiTouchControls(false)
        // Non-interactive: parity with iOS `.allowsHitTesting(false)` — this card lives
        // inside a scrolling sheet and must not steal single-finger pan/scroll gestures.
        isClickable = false
        setOnTouchListener { _, _ -> true }
        controller.setZoom(5.0)
        controller.setCenter(GeoPoint(center.latitude, center.longitude))
    }
}

private fun renderCallsignMap(map: MapView, center: FfiCoordinate, callsign: String) {
    map.overlays.clear()
    val point = GeoPoint(center.latitude, center.longitude)
    map.overlays.add(
        Marker(map).apply {
            position = point
            title = callsign
            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
        },
    )
    frameBoundingBox(map, listOf(point))
    map.invalidate()
}

@Composable
private fun DistanceBearingLabel(grid: String, homeGrid: String) {
    if (homeGrid.isBlank()) return
    val distanceKm = remember(homeGrid, grid) { maidenheadDistanceKm(homeGrid, grid) } ?: return
    val bearing = remember(homeGrid, grid) { maidenheadBearing(homeGrid, grid) } ?: return

    val distanceMi = distanceKm * 0.621371
    val cardinal = cardinalDirection(bearing)
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
        Text(
            String.format(
                Locale.US,
                "~%d mi · %d° %s from %s",
                distanceMi.toInt(),
                bearing.toInt(),
                cardinal,
                homeGrid,
            ),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
