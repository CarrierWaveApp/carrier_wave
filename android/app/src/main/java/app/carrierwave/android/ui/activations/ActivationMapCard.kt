package app.carrierwave.android.ui.activations

import android.content.Context
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import app.carrierwave.android.ui.map.addArcs
import app.carrierwave.android.ui.map.frameBounds
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import uniffi.cw_ffi.FfiQsoMapData

/**
 * Compact activation-detail map card over [FfiQsoMapData] (the park+UTC-day
 * window the detail VM built via `MapApi.qsoMap`). Same non-interactive,
 * silently-omitted-on-empty contract as
 * [app.carrierwave.android.ui.sessions.SessionMapCard] — activations have no
 * session id, so they can't use `sessionMap`; they render the individual QSO
 * pins + home→contact arcs from the filtered QSO map instead. Reuses the shared
 * [addArcs]/[frameBounds] osmdroid helpers.
 */
@Composable
fun ActivationMapCard(data: FfiQsoMapData, modifier: Modifier = Modifier) {
    if (data.annotations.isEmpty()) return

    AndroidView(
        modifier = modifier
            .fillMaxWidth()
            .height(220.dp)
            .clip(RoundedCornerShape(12.dp)),
        factory = { ctx -> buildActivationMapView(ctx, data) },
        update = { map -> renderActivationMap(map, data) },
    )
}

private fun buildActivationMapView(ctx: Context, data: FfiQsoMapData): MapView {
    Configuration.getInstance().load(ctx, ctx.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
    Configuration.getInstance().userAgentValue = ctx.packageName
    return MapView(ctx).apply {
        setTileSource(TileSourceFactory.MAPNIK)
        setMultiTouchControls(false)
        // Non-interactive: this card lives in a scrolling column and must not
        // steal single-finger pan/scroll gestures (iOS `.allowsHitTesting(false)`).
        isClickable = false
        setOnTouchListener { _, _ -> true }
        controller.setZoom(3.0)
        data.annotations.firstOrNull()?.let { controller.setCenter(GeoPoint(it.latitude, it.longitude)) }
    }
}

private fun renderActivationMap(map: MapView, data: FfiQsoMapData) {
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
    data.bounds?.let { frameBounds(map, it) }
    map.invalidate()
}
