package app.carrierwave.android.ui.clubs

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import uniffi.cw_ffi.FfiCallsignLocation
import uniffi.cw_ffi.FfiClubMember
import uniffi.cw_ffi.maidenheadCoordinate

/**
 * OpenStreetMap view of club members. Pins start from each member's last grid
 * square (resolved by the shared Rust Maidenhead code — the same conversion
 * the iOS map uses) for an instant render, then are refined once
 * [refinedLocations] is populated by an async `QrzApi.locate` call: matched
 * members get their precise coordinate (replacing the centroid, or gaining a
 * pin if they had no grid at all); unmatched members keep their grid pin.
 * Mirrors iOS `ClubMapView.loadMemberLocations`.
 */
@Composable
fun ClubMapView(
    members: List<FfiClubMember>,
    homeGrid: String,
    refinedLocations: Map<String, FfiCallsignLocation> = emptyMap(),
    modifier: Modifier = Modifier,
) {
    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            // osmdroid needs a user agent + cache config before the first tile load.
            Configuration.getInstance().load(ctx, ctx.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
            Configuration.getInstance().userAgentValue = ctx.packageName
            MapView(ctx).apply {
                setTileSource(TileSourceFactory.MAPNIK)
                setMultiTouchControls(true)
                controller.setZoom(3.5)
                maidenheadCoordinate(homeGrid)?.let {
                    controller.setCenter(GeoPoint(it.latitude, it.longitude))
                }
            }
        },
        update = { map ->
            // Drop any prior markers and re-place from the current member list.
            map.overlays.clear()
            var first: GeoPoint? = null
            members.forEach { member ->
                val point = memberPoint(member, refinedLocations) ?: return@forEach
                if (first == null) first = point
                map.overlays.add(
                    Marker(map).apply {
                        position = point
                        title = member.callsign
                        setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                    },
                )
            }
            first?.let { map.controller.setCenter(it) }
            map.invalidate()
        },
    )
}

/**
 * Precise `QrzApi.locate` coordinate when available (case-insensitive match on
 * callsign), else the member's grid centroid, else `null` (no pin — matches
 * the case where a member has neither a resolved location nor a grid).
 */
private fun memberPoint(member: FfiClubMember, refinedLocations: Map<String, FfiCallsignLocation>): GeoPoint? {
    refinedLocations[member.callsign.uppercase()]?.let {
        return GeoPoint(it.latitude, it.longitude)
    }
    val grid = member.lastGrid ?: return null
    val coord = maidenheadCoordinate(grid) ?: return null
    return GeoPoint(coord.latitude, coord.longitude)
}
