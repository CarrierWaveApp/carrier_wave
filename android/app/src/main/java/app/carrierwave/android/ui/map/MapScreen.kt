package app.carrierwave.android.ui.map

import android.content.Context
import android.graphics.Color as AndroidColor
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FilterAlt
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Park
import androidx.compose.material.icons.filled.Route
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import app.carrierwave.android.ui.parks.ParkSearchScreen
import app.carrierwave.android.ui.parks.ParkSearchViewModel
import java.util.Locale
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polygon
import uniffi.cw_ffi.FfiGridBounds
import uniffi.cw_ffi.FfiQsoMapAnnotation
import uniffi.cw_ffi.FfiQsoMapData
import uniffi.cw_ffi.maidenheadCoordinate

/**
 * Map tab — OpenStreetMap view backed by the shared Rust `MapApi`. QSO layer
 * shows clustered markers, geodesic arcs, and a worked/confirmed grid overlay;
 * DXCC layer keeps the original per-entity pin list.
 */
@Composable
fun MapScreen(vm: MapViewModel, modifier: Modifier = Modifier) {
    val state by vm.state.collectAsStateWithLifecycle()
    var showFilterSheet by remember { mutableStateOf(false) }
    var selectedAnnotation by remember { mutableStateOf<FfiQsoMapAnnotation?>(null) }
    // Full-screen overlay for park/summit search, opened via the "Parks" chip
    // below — mirrors the Sessions tab's rememberSaveable overlay pattern.
    var showParkSearch by rememberSaveable { mutableStateOf(false) }

    if (showParkSearch) {
        BackHandler { showParkSearch = false }
        val parkSearchVm: ParkSearchViewModel = viewModel(factory = ParkSearchViewModel.factory())
        ParkSearchScreen(
            vm = parkSearchVm,
            homeGrid = vm.homeGrid,
            onBack = { showParkSearch = false },
            modifier = modifier,
        )
        return
    }

    Column(modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FilterChip(
                selected = state.layer == MapLayer.QSOS,
                onClick = { vm.setLayer(MapLayer.QSOS) },
                label = { Text("QSOs") },
            )
            FilterChip(
                selected = state.layer == MapLayer.DXCC,
                onClick = { vm.setLayer(MapLayer.DXCC) },
                label = { Text("DXCC") },
            )
            FilterChip(
                selected = false,
                onClick = { showParkSearch = true },
                label = { Text("Parks") },
                leadingIcon = { Icon(Icons.Filled.Park, contentDescription = null) },
            )
            if (state.layer == MapLayer.QSOS) {
                FilterChip(
                    selected = state.filter.showGridOverlay,
                    onClick = { vm.updateFilter { it.copy(showGridOverlay = !it.showGridOverlay) } },
                    label = { Text("Grid") },
                    leadingIcon = { Icon(Icons.Filled.GridView, contentDescription = null) },
                )
                FilterChip(
                    selected = state.filter.showPaths,
                    onClick = { vm.updateFilter { it.copy(showPaths = !it.showPaths) } },
                    label = { Text("Arcs") },
                    leadingIcon = { Icon(Icons.Filled.Route, contentDescription = null) },
                )
                BadgedBox(
                    badge = { if (state.filter.hasActiveFilters) Badge() },
                ) {
                    IconButton(
                        onClick = { showFilterSheet = true },
                        enabled = state.data != null,
                    ) {
                        Icon(Icons.Filled.FilterAlt, contentDescription = "Filter")
                    }
                }
            }
        }

        if (state.layer == MapLayer.QSOS) {
            state.data?.let { data ->
                StatsStrip(data, state.filter.showAll)
            }
        }

        Box(Modifier.weight(1f).clipToBounds()) {
            OsmMap(
                state = state,
                homeGrid = vm.homeGrid,
                onAnnotationTap = { selectedAnnotation = it },
            )
            val hasContent = when (state.layer) {
                MapLayer.QSOS -> (state.data?.annotations?.isNotEmpty() == true)
                MapLayer.DXCC -> state.dxccPins.isNotEmpty()
            }
            when {
                state.error != null && state.data == null -> {
                    Text(
                        state.error.toString(),
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
                !state.loading && !hasContent -> {
                    Text(
                        "No locations to plot yet.",
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            selectedAnnotation?.let { annotation ->
                QsoCalloutCard(
                    annotation = annotation,
                    onDismiss = { selectedAnnotation = null },
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(16.dp),
                )
            }
        }
    }

    if (showFilterSheet) {
        state.data?.let { data ->
            MapFilterSheet(
                data = MapUiStateFilterOptions(data.availableBands, data.availableModes, data.availableParks),
                filter = state.filter,
                onUpdate = { transform -> vm.updateFilter(transform) },
                onDismiss = { showFilterSheet = false },
            )
        }
    }
}

@Composable
private fun StatsStrip(data: FfiQsoMapData, showAll: Boolean) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatItem("${data.displayedCount}/${data.totalCount}", "QSOs")
            StatItem("${data.annotations.size}", "Grids")
            StatItem("${data.stats.uniqueStates}", "States")
            StatItem("${data.stats.uniqueDxcc}", "DXCC")
        }
        val stats = data.stats
        if (stats.durationSeconds != null || stats.qsoRate != null ||
            stats.averageDistanceKm != null || stats.longestDistanceKm != null || stats.wattsPerMile != null
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                stats.durationSeconds?.let { StatItem(formatDuration(it), "Duration") }
                stats.qsoRate?.let { StatItem(String.format(Locale.US, "%.1f", it), "Rate") }
                stats.averageDistanceKm?.let { StatItem("${it.toInt()} km", "Avg") }
                stats.longestDistanceKm?.let { StatItem("${it.toInt()} km", "Max") }
                stats.wattsPerMile?.let { StatItem(String.format(Locale.US, "%.1f", it), "W/mi") }
            }
        }
        if (!showAll && data.isLimited) {
            Text(
                "Limited to 500",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
    }
}

@Composable
private fun StatItem(value: String, label: String) {
    Column {
        Text(value, style = MaterialTheme.typography.labelLarge)
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun formatDuration(seconds: Long): String {
    val hours = seconds / 3600
    val minutes = (seconds % 3600) / 60
    return if (hours > 0) "${hours}h${minutes}m" else "${minutes}m"
}

@Composable
private fun OsmMap(
    state: MapUiState,
    homeGrid: String,
    onAnnotationTap: (FfiQsoMapAnnotation) -> Unit,
) {
    // Plain holder, not MutableState — the flag drives no UI, so flipping it
    // shouldn't trigger a recomposition. Framing runs once per map lifetime,
    // matching iOS's first-load-only camera fit.
    val framedInitialBounds = remember { booleanArrayOf(false) }
    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { ctx ->
            // osmdroid needs a user agent + cache config before the first tile load.
            Configuration.getInstance().load(ctx, ctx.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
            Configuration.getInstance().userAgentValue = ctx.packageName
            MapView(ctx).apply {
                setTileSource(TileSourceFactory.MAPNIK)
                setMultiTouchControls(true)
                // Pinch-to-zoom only — hide osmdroid's built-in +/- buttons.
                zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER)
                controller.setZoom(3.0)
                maidenheadCoordinate(homeGrid)?.let {
                    controller.setCenter(GeoPoint(it.latitude, it.longitude))
                }
            }
        },
        update = { map ->
            map.overlays.clear()

            when (state.layer) {
                MapLayer.QSOS -> {
                    val data = state.data
                    if (data != null) {
                        if (state.filter.showGridOverlay) {
                            addGridOverlays(map, state.gridTiles)
                        }
                        if (state.filter.showPaths) {
                            addArcs(map, data.arcs)
                        }
                        addAnnotationMarkers(map, data.annotations, onAnnotationTap)
                        val bounds = data.bounds
                        if (!framedInitialBounds[0] && bounds != null) {
                            framedInitialBounds[0] = true
                            frameBounds(map, bounds)
                        }
                    }
                }
                MapLayer.DXCC -> {
                    state.dxccPins.forEach { pin ->
                        map.overlays.add(
                            Marker(map).apply {
                                position = GeoPoint(pin.latitude, pin.longitude)
                                title = pin.title
                                setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                            },
                        )
                    }
                }
            }

            map.invalidate()
        },
    )
}

private fun addAnnotationMarkers(
    map: MapView,
    annotations: List<FfiQsoMapAnnotation>,
    onTap: (FfiQsoMapAnnotation) -> Unit,
) {
    annotations.forEach { annotation ->
        map.overlays.add(
            Marker(map).apply {
                position = GeoPoint(annotation.latitude, annotation.longitude)
                title = if (annotation.qsoCount == 1L) {
                    annotation.callsigns.firstOrNull() ?: annotation.gridSquare
                } else {
                    "${annotation.gridSquare} (${annotation.qsoCount})"
                }
                setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_BOTTOM)
                setOnMarkerClickListener { _, _ ->
                    onTap(annotation)
                    true
                }
            },
        )
    }
}

private fun addGridOverlays(map: MapView, tiles: List<GridOverlayTile>) {
    tiles.forEach { tile ->
        val bounds: FfiGridBounds = tile.bounds
        map.overlays.add(
            Polygon(map).apply {
                points = listOf(
                    GeoPoint(bounds.south, bounds.west),
                    GeoPoint(bounds.south, bounds.east),
                    GeoPoint(bounds.north, bounds.east),
                    GeoPoint(bounds.north, bounds.west),
                )
                fillPaint.color = if (tile.confirmed) {
                    AndroidColor.argb(51, 0, 200, 0)
                } else {
                    AndroidColor.argb(38, 0, 0, 255)
                }
                outlinePaint.color = AndroidColor.argb(255, 128, 128, 128)
                outlinePaint.strokeWidth = 1f
            },
        )
    }
}
