package app.carrierwave.android.ui.spots

import android.content.Context
import android.graphics.Color as AndroidColor
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import app.carrierwave.android.ui.map.addPolylines
import app.carrierwave.android.ui.map.dotMarker
import app.carrierwave.android.ui.map.snrColor
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import uniffi.cw_ffi.FfiCoordinate
import uniffi.cw_ffi.greatCircleArc
import uniffi.cw_ffi.maidenheadCoordinate
import uniffi.cw_ffi.timelineSnrColorBand
import uniffi.cw_ffi.timelineSnrMarkerSize

/**
 * Collapsible spotter-location map above the spots list — port of iOS
 * `SpotsMiniMapView` (used inside `RBNPanelView`). Shows one dot per spot
 * with a resolvable grid, colored/sized by source (RBN uses SNR-based color
 * bands + marker sizes from the shared Rust timeline helpers; other sources
 * currently modeled on Android — POTA/SOTA/WWFF — use fixed colors). PSKR
 * and cluster spot sources aren't represented in the Android `Spot` model
 * yet, so they never reach this map. Renders nothing if the target/home
 * grid doesn't resolve to a coordinate.
 */
@Composable
fun SpotsMiniMap(spots: List<Spot>, targetCallsign: String, targetGrid: String?, modifier: Modifier = Modifier) {
    val homeCoord = targetGrid?.let { maidenheadCoordinate(it) } ?: return
    val lastRendered = remember { LastRenderedHolder() }

    AndroidView(
        modifier = modifier
            .fillMaxWidth()
            .height(200.dp)
            .clip(RoundedCornerShape(12.dp)),
        factory = { ctx -> buildSpotsMiniMapView(ctx, homeCoord) },
        update = { map ->
            val key = renderKey(spots, targetCallsign, homeCoord)
            if (lastRendered.key == key) return@AndroidView
            lastRendered.key = key
            renderSpotsMiniMap(map, spots, targetCallsign, homeCoord)
        },
    )
}

/** Plain holder for the last-rendered input key, used to skip redundant overlay rebuilds. */
private class LastRenderedHolder {
    var key: List<Any?>? = null
}

/** Cheap identity for "did the map need to change" — spot callsign+grid pairs plus home. */
private fun renderKey(spots: List<Spot>, targetCallsign: String, homeCoord: FfiCoordinate): List<Any?> =
    listOf(
        targetCallsign,
        homeCoord.latitude,
        homeCoord.longitude,
        spots.map { spot -> "${spot.callsign}|${spot.grid}|${spot.spotter}|${spot.snr}|${spot.source}" },
    )

private fun buildSpotsMiniMapView(ctx: Context, homeCoord: FfiCoordinate): MapView {
    Configuration.getInstance().load(ctx, ctx.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
    Configuration.getInstance().userAgentValue = ctx.packageName
    return MapView(ctx).apply {
        setTileSource(TileSourceFactory.MAPNIK)
        setMultiTouchControls(false)
        // Non-interactive: parity with iOS `.allowsHitTesting(false)` — this card lives
        // above a scrolling list and must not steal single-finger pan/scroll gestures.
        isClickable = false
        setOnTouchListener { _, _ -> true }
        controller.setZoom(2.0)
        controller.setCenter(GeoPoint(homeCoord.latitude, homeCoord.longitude))
    }
}

private fun renderSpotsMiniMap(map: MapView, spots: List<Spot>, targetCallsign: String, homeCoord: FfiCoordinate) {
    map.overlays.clear()

    val homePoint = GeoPoint(homeCoord.latitude, homeCoord.longitude)

    val spotterPoints = spots.mapNotNull { spot ->
        val grid = spot.grid ?: return@mapNotNull null
        val coord = maidenheadCoordinate(grid) ?: return@mapNotNull null
        Triple(spot, coord, GeoPoint(coord.latitude, coord.longitude))
    }

    // Arcs from home to each spotter — drawn under the markers, same styling as
    // the other map cards' `addPolylines` (translucent white, 3pt).
    spotterPoints.forEach { (_, coord, _) ->
        addPolylines(map, greatCircleArc(homeCoord, coord, ARC_SEGMENTS))
    }

    spotterPoints.forEach { (spot, _, point) ->
        val (color, sizeDp) = markerStyle(spot)
        map.overlays.add(
            dotMarker(
                map = map,
                center = point,
                radiusDegrees = radiusDegrees(sizeDp),
                fillColor = color,
                title = spot.spotter ?: spot.callsign,
            ),
        )
    }

    // Home/target pin — red, drawn last so it renders above the spotter dots.
    map.overlays.add(
        dotMarker(
            map = map,
            center = homePoint,
            radiusDegrees = radiusDegrees(HOME_MARKER_SIZE_DP),
            fillColor = AndroidColor.RED,
            title = targetCallsign,
        ),
    )

    map.invalidate()
}

/** Converts a dp marker size into a degrees-based radius, scaled relative to [BASE_MARKER_SIZE_DP]. */
private fun radiusDegrees(sizeDp: Double): Double =
    MIN_DOT_RADIUS_DEGREES * (sizeDp / BASE_MARKER_SIZE_DP).coerceIn(0.5, 3.0)

/**
 * Marker color + diameter (dp) for one spot, mirroring iOS
 * `SpotsMiniMapView.spotAnnotations`: RBN spots use the shared SNR color-band
 * (green/blue/orange/red) and SNR-scaled size; other sources use fixed colors.
 */
private fun markerStyle(spot: Spot): Pair<Int, Double> {
    return when (spot.source) {
        SpotSource.RBN -> {
            val snr = spot.snr
            if (snr != null) {
                snrColor(timelineSnrColorBand(snr.toLong())) to timelineSnrMarkerSize(snr.toLong())
            } else {
                AndroidColor.BLUE to 10.0
            }
        }
        SpotSource.POTA -> AndroidColor.rgb(52, 199, 89) to 12.0 // iOS .green
        SpotSource.SOTA -> AndroidColor.rgb(255, 149, 0) to 12.0 // iOS .orange
        SpotSource.WWFF -> AndroidColor.rgb(0, 199, 190) to 12.0 // iOS .mint
    }
}

private const val ARC_SEGMENTS: UInt = 32u
private const val BASE_MARKER_SIZE_DP = 12.0
private const val HOME_MARKER_SIZE_DP = 14.0
private const val MIN_DOT_RADIUS_DEGREES = 0.35

