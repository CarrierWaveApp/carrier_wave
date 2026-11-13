package app.carrierwave.android.ui.parks

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color as AndroidColor
import android.graphics.Paint
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.GradientDrawable
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.Park
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Terrain
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.SuggestionChipDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.carrierwave.android.ui.map.GridRectGeometry
import app.carrierwave.android.ui.map.addBoundaryOutlines
import app.carrierwave.android.ui.map.addBoundaryPolygons
import app.carrierwave.android.ui.map.addGridRectOverlays
import app.carrierwave.android.ui.map.geojsonToPolygonRings
import kotlin.math.floor
import org.json.JSONObject
import org.osmdroid.config.Configuration
import org.osmdroid.events.MapListener
import org.osmdroid.events.ScrollEvent
import org.osmdroid.events.ZoomEvent
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.BoundingBox
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import uniffi.cw_ffi.FfiBoundingBox
import uniffi.cw_ffi.FfiGeoBoundary
import uniffi.cw_ffi.FfiParkPin
import uniffi.cw_ffi.FfiRefSearchHit
import uniffi.cw_ffi.maidenheadCoordinate

/**
 * Park/summit search screen — osmdroid map with clustered park/summit pins
 * backed by the shared Rust `ParkMapApi`, plus a name search that centers and
 * zooms the map on the tapped result. Entry point: a "Parks" chip on the Map
 * tab (see [app.carrierwave.android.ui.map.MapScreen]).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ParkSearchScreen(vm: ParkSearchViewModel, homeGrid: String, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val state by vm.state.collectAsStateWithLifecycle()
    // Bumped whenever a search result should re-center the map; the AndroidView
    // reads it inside `update` without needing to recreate the MapView.
    var centerOn by remember { mutableStateOf<GeoPoint?>(null) }

    Column(modifier.fillMaxSize()) {
        TopAppBar(
            title = { Text("Parks & Summits") },
            navigationIcon = {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
            },
            actions = {
                val multipliersEnabled = state.boundaries.isNotEmpty() ||
                    state.wwffBoundaries.isNotEmpty() ||
                    state.adminBoundaries.values.any { it.kind == "admin_county" }
                IconButton(onClick = { vm.presentMultipliers() }, enabled = multipliersEnabled) {
                    Icon(Icons.Filled.WorkspacePremium, contentDescription = "Find Multipliers")
                }
                LayersMenuButton(layers = state.layers, onUpdate = vm::setLayer)
            },
        )

        OutlinedTextField(
            value = state.query,
            onValueChange = vm::onQueryChange,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
            placeholder = { Text("Search parks and summits") },
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            trailingIcon = {
                if (state.query.isNotEmpty()) {
                    IconButton(onClick = { vm.clearSearch() }) {
                        Icon(Icons.Filled.Clear, contentDescription = "Clear")
                    }
                } else if (state.searching) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                }
            },
            singleLine = true,
            colors = TextFieldDefaults.colors(),
        )

        if (state.searchResults.isNotEmpty()) {
            SearchResultsRow(
                results = state.searchResults,
                onSelect = { hit ->
                    val lat = hit.latitude
                    val lon = hit.longitude
                    if (lat != null && lon != null) {
                        centerOn = GeoPoint(lat, lon)
                    }
                    vm.clearSearch()
                },
            )
        }
        state.searchError?.let {
            Text(
                it,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }

        Box(Modifier.weight(1f).clipToBounds()) {
            ParkOsmMap(
                pins = state.pins,
                homeGrid = homeGrid,
                centerOn = centerOn,
                onCentered = { centerOn = null },
                onRegionChanged = vm::onRegionChanged,
                onPinTap = { vm.selectPin(it) },
                layers = state.layers,
                boundaries = state.boundaries,
                trails = state.trails,
                sotaZones = state.sotaZones,
                adminBoundaries = state.adminBoundaries,
                wwffBoundaries = state.wwffBoundaries,
                wwffPins = state.wwffPins,
                onBoundaryTap = { vm.selectBoundary(it) },
            )

            if (state.pinsError != null && state.pins.isEmpty()) {
                Text(
                    state.pinsError.toString(),
                    modifier = Modifier.padding(16.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            state.selectedBoundary?.let { boundary ->
                BoundaryCalloutCard(
                    boundary = boundary,
                    onDismiss = { vm.selectBoundary(null) },
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(16.dp),
                )
            }

            state.selectedPin?.let { pin ->
                ParkCalloutCard(
                    pin = pin,
                    onDismiss = { vm.selectPin(null) },
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(16.dp),
                )
            }
        }

        if (state.showMultipliersSheet) {
            MultipliersSheet(
                candidates = state.multiplierCandidates,
                isFinding = state.findingMultipliers,
                onSelect = { candidate ->
                    centerOn = GeoPoint(candidate.latitude, candidate.longitude)
                    vm.dismissMultipliers()
                },
                onDismiss = { vm.dismissMultipliers() },
            )
        }
    }
}

@Composable
private fun SearchResultsRow(results: List<FfiRefSearchHit>, onSelect: (FfiRefSearchHit) -> Unit) {
    LazyRow(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(vertical = 4.dp),
    ) {
        items(results) { hit ->
            SuggestionChip(
                onClick = { onSelect(hit) },
                label = { Text("${hit.reference} · ${hit.name}") },
                icon = {
                    Icon(
                        if (hit.kind == "summit") Icons.Filled.Terrain else Icons.Filled.Park,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                },
                colors = SuggestionChipDefaults.suggestionChipColors(),
            )
        }
    }
}

@Composable
private fun ParkCalloutCard(pin: FfiParkPin, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.fillMaxWidth().clickable(onClick = onDismiss),
        shape = RoundedCornerShape(8.dp),
        tonalElevation = 4.dp,
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(
                    if (pin.kind == "summit") Icons.Filled.Terrain else Icons.Filled.Park,
                    contentDescription = null,
                    tint = pinTint(pin.kind),
                )
                Text(pin.reference, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            Text(pin.name, style = MaterialTheme.typography.bodyMedium)
            pin.activationCount?.let {
                Text(
                    "$it activation${if (it == 1L) "" else "s"}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            pin.altitudeM?.let {
                Text(
                    "$it m elevation",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private fun pinTint(kind: String): Color =
    if (kind == "summit") Color(0xFF8D6E63) else Color(0xFF43A047)

/**
 * Overflow menu of overlay-layer toggles — Android analog of iOS's
 * `ParkSearchMapView` toolbar `Menu` (Show Boundaries/Trails, Programs
 * section for SOTA Zones/WWFF, Administrative section for States/Counties,
 * Grids section for Grid Squares/TOTA tiles).
 */
@Composable
private fun LayersMenuButton(layers: ParkMapLayers, onUpdate: ((ParkMapLayers) -> ParkMapLayers) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    IconButton(onClick = { expanded = true }) {
        Icon(Icons.Filled.Layers, contentDescription = "Map Layers")
    }
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
        LayerToggleItem("Park/Trail Boundaries", layers.boundaries) { on -> onUpdate { it.copy(boundaries = on) } }
        LayerToggleItem("Trails", layers.trails) { on -> onUpdate { it.copy(trails = on) } }
        HorizontalDivider()
        LayerToggleItem("SOTA Zones", layers.sotaZones) { on -> onUpdate { it.copy(sotaZones = on) } }
        LayerToggleItem("WWFF", layers.wwff) { on -> onUpdate { it.copy(wwff = on) } }
        HorizontalDivider()
        LayerToggleItem("States", layers.states) { on -> onUpdate { it.copy(states = on) } }
        LayerToggleItem("Counties", layers.counties) { on -> onUpdate { it.copy(counties = on) } }
        HorizontalDivider()
        LayerToggleItem("Grid Squares", layers.gridSquares) { on -> onUpdate { it.copy(gridSquares = on) } }
        LayerToggleItem("Tiles on the Air", layers.totaTiles) { on -> onUpdate { it.copy(totaTiles = on) } }
    }
}

@Composable
private fun LayerToggleItem(label: String, checked: Boolean, onToggle: (Boolean) -> Unit) {
    DropdownMenuItem(
        text = { Text(label) },
        onClick = { onToggle(!checked) },
        trailingIcon = { Switch(checked = checked, onCheckedChange = onToggle) },
    )
}

/**
 * Callout for a tapped boundary/trail/zone/WWFF polygon — decodes
 * `FfiGeoBoundary.propertiesJson` (a flat JSON object; see the Task 7/10
 * decode contract) for designation/manager/acreage/matchQuality (parks) or
 * managingAgency/lengthMiles/state (trails) when present.
 */
@Composable
private fun BoundaryCalloutCard(boundary: FfiGeoBoundary, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val properties = remember(boundary.propertiesJson) { decodeBoundaryProperties(boundary.propertiesJson) }
    Surface(
        modifier = modifier.fillMaxWidth().clickable(onClick = onDismiss),
        shape = RoundedCornerShape(8.dp),
        tonalElevation = 4.dp,
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                boundary.name ?: boundary.reference,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
            if (boundary.name != null) {
                Text(boundary.reference, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            properties?.designation?.let { CalloutDetailLine("Designation", it) }
            properties?.manager?.let { CalloutDetailLine("Manager", it) }
            properties?.acreage?.let { CalloutDetailLine("Acreage", "%.1f ac".format(it)) }
            properties?.managingAgency?.let { CalloutDetailLine("Agency", it) }
            properties?.lengthMiles?.let { CalloutDetailLine("Length", "%.1f mi".format(it)) }
            properties?.state?.let { CalloutDetailLine("State", it) }
            properties?.matchQuality?.let { CalloutDetailLine("Match", it) }
        }
    }
}

@Composable
private fun CalloutDetailLine(label: String, value: String) {
    Text(
        "$label: $value",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

/** Flat properties payload carried in `FfiGeoBoundary.propertiesJson` — the
 * park/trail/admin Feature `properties` object (Task 7/10 decode contract:
 * flat JSON object, all keys optional). Mirrors iOS `BoundaryFeatureProperties`. */
private data class BoundaryFeatureProperties(
    val designation: String?,
    val manager: String?,
    val acreage: Double?,
    val matchQuality: String?,
    val managingAgency: String?,
    val lengthMiles: Double?,
    val state: String?,
)

private fun decodeBoundaryProperties(json: String?): BoundaryFeatureProperties? {
    if (json.isNullOrBlank()) return null
    val obj = runCatching { JSONObject(json) }.getOrNull() ?: return null
    return BoundaryFeatureProperties(
        designation = obj.optStringOrNull("designation"),
        manager = obj.optStringOrNull("manager"),
        acreage = obj.optDoubleOrNull("acreage"),
        matchQuality = obj.optStringOrNull("matchQuality"),
        managingAgency = obj.optStringOrNull("managingAgency"),
        lengthMiles = obj.optDoubleOrNull("lengthMiles"),
        state = obj.optStringOrNull("state"),
    )
}

private fun JSONObject.optStringOrNull(key: String): String? = if (has(key) && !isNull(key)) optString(key) else null

private fun JSONObject.optDoubleOrNull(key: String): Double? = if (has(key) && !isNull(key)) optDouble(key) else null

@Composable
private fun ParkOsmMap(
    pins: List<FfiParkPin>,
    homeGrid: String,
    centerOn: GeoPoint?,
    onCentered: () -> Unit,
    onRegionChanged: (FfiBoundingBox) -> Unit,
    onPinTap: (FfiParkPin) -> Unit,
    layers: ParkMapLayers,
    boundaries: Map<String, FfiGeoBoundary>,
    trails: Map<String, FfiGeoBoundary>,
    sotaZones: Map<String, FfiGeoBoundary>,
    adminBoundaries: Map<String, FfiGeoBoundary>,
    wwffBoundaries: Map<String, FfiGeoBoundary>,
    wwffPins: List<FfiParkPin>,
    onBoundaryTap: (FfiGeoBoundary) -> Unit,
) {
    val lastRendered = remember { LastRenderedHolder() }

    androidx.compose.ui.viewinterop.AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { ctx ->
            Configuration.getInstance().load(ctx, ctx.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
            Configuration.getInstance().userAgentValue = ctx.packageName
            MapView(ctx).apply {
                setTileSource(TileSourceFactory.MAPNIK)
                setMultiTouchControls(true)
                // Pinch-to-zoom only — hide osmdroid's built-in +/- buttons.
                zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER)
                controller.setZoom(6.0)
                maidenheadCoordinate(homeGrid)?.let {
                    controller.setCenter(GeoPoint(it.latitude, it.longitude))
                }
                addMapListener(
                    object : MapListener {
                        override fun onScroll(event: ScrollEvent?): Boolean {
                            onRegionChanged(boundingBox.toFfi())
                            return true
                        }

                        override fun onZoom(event: ZoomEvent?): Boolean {
                            onRegionChanged(boundingBox.toFfi())
                            return true
                        }
                    },
                )
                // Fire once for the initial viewport (listener only fires on
                // user-driven scroll/zoom).
                post { onRegionChanged(boundingBox.toFfi()) }
            }
        },
        update = { map ->
            if (centerOn != null) {
                map.controller.animateTo(centerOn)
                map.controller.setZoom(12.0)
                onCentered()
                // A programmatic recenter doesn't fire MapListener, so kick a
                // pin reload for the new viewport directly.
                map.post { onRegionChanged(map.boundingBox.toFfi()) }
            }

            // Grid-square/TOTA-tile overlays are pure viewport geometry (no
            // ViewModel cache backing them), so their key input is the map's
            // own bounding box rather than a fetched-data set.
            val gridBoxKey = if (layers.gridSquares || layers.totaTiles) {
                val box = map.boundingBox
                listOf(box.latNorth, box.latSouth, box.lonEast, box.lonWest)
            } else {
                null
            }
            val key = renderKey(pins, centerOn, layers, boundaries, trails, sotaZones, adminBoundaries, wwffBoundaries, wwffPins) +
                listOf(gridBoxKey)
            if (lastRendered.key == key) return@AndroidView
            lastRendered.key = key

            map.overlays.clear()
            if (layers.states || layers.counties) {
                // iOS distinguishes state vs. county admin boundaries
                // (ParkSearchMapKit.swift StateLineOverlay/CountyLineOverlay
                // renderers) — indigo/2pt/0.7-alpha for states, gray/1pt/
                // 0.6-alpha for counties. A null `kind` (shouldn't happen post
                // `admin_boundary_kind`, but the FFI type is optional) falls
                // back to the county style.
                val (stateBoundaries, countyBoundaries) = adminBoundaries.values.partition {
                    it.kind == "admin_state"
                }
                addBoundaryOutlines(
                    map,
                    stateBoundaries.flatMap { geojsonToPolygonRings(it.geojson) },
                    strokeColor = AndroidColor.argb(179, 63, 81, 181),
                    strokeWidth = 2f,
                )
                addBoundaryOutlines(
                    map,
                    countyBoundaries.flatMap { geojsonToPolygonRings(it.geojson) },
                    strokeColor = AndroidColor.argb(153, 158, 158, 158),
                    strokeWidth = 1f,
                )
            }
            if (layers.gridSquares) {
                addGridRectOverlays(
                    map,
                    GridRectGeometry.gridRects(map.boundingBox),
                    strokeColor = AndroidColor.argb(140, 0, 188, 212),
                )
            }
            if (layers.totaTiles) {
                addGridRectOverlays(
                    map,
                    GridRectGeometry.tileRects(map.boundingBox),
                    strokeColor = AndroidColor.argb(140, 156, 39, 176),
                )
            }
            if (layers.sotaZones) {
                addBoundaryPolygons(
                    map,
                    sotaZones.values.flatMap { geojsonToPolygonRings(it.geojson) },
                    fillColor = AndroidColor.argb(40, 141, 110, 99),
                    strokeColor = AndroidColor.argb(180, 141, 110, 99),
                )
            }
            if (layers.wwff) {
                wwffBoundaries.values.forEach { boundary ->
                    addBoundaryPolygons(
                        map,
                        geojsonToPolygonRings(boundary.geojson),
                        fillColor = AndroidColor.argb(40, 156, 39, 176),
                        strokeColor = AndroidColor.argb(180, 156, 39, 176),
                        title = boundary.name ?: boundary.reference,
                        onTap = { onBoundaryTap(boundary); true },
                    )
                }
                // Diamond marker fallback for WWFF refs with no borrowed POTA
                // boundary (iOS parity: a bare marker at the reference's own
                // coordinate — `ParkSearchMapView+WWFF.swift`'s `markerBBox`).
                wwffPins.filter { it.reference !in wwffBoundaries }.forEach { pin ->
                    map.overlays.add(
                        Marker(map).apply {
                            position = GeoPoint(pin.latitude, pin.longitude)
                            title = "${pin.reference} · ${pin.name}"
                            icon = diamondDrawable(map.context, AndroidColor.rgb(156, 39, 176))
                            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
                        },
                    )
                }
            }
            if (layers.trails) {
                trails.values.forEach { trail ->
                    addBoundaryOutlines(
                        map,
                        geojsonToPolygonRings(trail.geojson),
                        strokeColor = AndroidColor.argb(200, 121, 85, 72),
                        strokeWidth = 2.5f,
                    )
                }
            }
            if (layers.boundaries) {
                boundaries.values.forEach { boundary ->
                    addBoundaryPolygons(
                        map,
                        geojsonToPolygonRings(boundary.geojson),
                        fillColor = AndroidColor.argb(40, 67, 160, 71),
                        strokeColor = AndroidColor.argb(200, 67, 160, 71),
                        title = boundary.name ?: boundary.reference,
                        onTap = { onBoundaryTap(boundary); true },
                    )
                }
            }
            addClusteredPinMarkers(map, pins, onPinTap)
            map.invalidate()
        },
    )
}

/** Plain holder for the last-rendered input key, used to skip redundant overlay rebuilds. */
private class LastRenderedHolder {
    var key: List<Any?>? = null
}

/** Cheap identity for "did the map need to change" — pin reference+kind pairs, the
 * pending recenter target, the layer toggle set, and each overlay cache's reference
 * set (so a newly-fetched boundary/trail/zone/admin/WWFF row forces a rebuild). */
private fun renderKey(
    pins: List<FfiParkPin>,
    centerOn: GeoPoint?,
    layers: ParkMapLayers,
    boundaries: Map<String, FfiGeoBoundary>,
    trails: Map<String, FfiGeoBoundary>,
    sotaZones: Map<String, FfiGeoBoundary>,
    adminBoundaries: Map<String, FfiGeoBoundary>,
    wwffBoundaries: Map<String, FfiGeoBoundary>,
    wwffPins: List<FfiParkPin>,
): List<Any?> =
    listOf(
        pins.map { pin -> "${pin.reference}|${pin.kind}" },
        centerOn?.latitude,
        centerOn?.longitude,
        layers,
        boundaries.keys.toList(),
        trails.keys.toList(),
        sotaZones.keys.toList(),
        adminBoundaries.keys.toList(),
        wwffBoundaries.keys.toList(),
        wwffPins.map { it.reference },
    )

private fun BoundingBox.toFfi(): FfiBoundingBox =
    FfiBoundingBox(west = lonWest, south = latSouth, east = lonEast, north = latNorth)

/**
 * Self-contained grid-bucket clusterer: no osmdroid clustering artifact is
 * pulled into the app (only `osmdroid-android` is a dependency), so pins are
 * bucketed into a coarse lat/lon grid sized relative to the current viewport
 * and rendered as either a single pin marker or a cluster badge marker.
 */
private fun addClusteredPinMarkers(map: MapView, pins: List<FfiParkPin>, onPinTap: (FfiParkPin) -> Unit) {
    if (pins.isEmpty()) return
    val box = map.boundingBox
    // ~40 buckets across the shorter viewport dimension keeps clusters visually
    // distinct without collapsing everything into one blob when zoomed out.
    val spanLat = (box.latNorth - box.latSouth).let { if (it <= 0.0) 1.0 else it }
    val spanLon = (box.lonEast - box.lonWest).let { if (it <= 0.0) 1.0 else it }
    val cellLat = spanLat / 40.0
    val cellLon = spanLon / 40.0

    val buckets = LinkedHashMap<Pair<Long, Long>, MutableList<FfiParkPin>>()
    for (pin in pins) {
        val key = Pair(
            floor(pin.latitude / cellLat).toLong(),
            floor(pin.longitude / cellLon).toLong(),
        )
        buckets.getOrPut(key) { mutableListOf() }.add(pin)
    }

    buckets.values.forEach { group ->
        if (group.size == 1) {
            addSinglePinMarker(map, group[0], onPinTap)
        } else {
            addClusterMarker(map, group, onPinTap)
        }
    }
}

private fun addSinglePinMarker(map: MapView, pin: FfiParkPin, onPinTap: (FfiParkPin) -> Unit) {
    map.overlays.add(
        Marker(map).apply {
            position = GeoPoint(pin.latitude, pin.longitude)
            title = "${pin.reference} · ${pin.name}"
            icon = dotDrawable(map.context, pinTint(pin.kind).toArgb())
            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
            setOnMarkerClickListener { _, _ ->
                onPinTap(pin)
                true
            }
        },
    )
}

private fun addClusterMarker(map: MapView, group: List<FfiParkPin>, onPinTap: (FfiParkPin) -> Unit) {
    val avgLat = group.sumOf { it.latitude } / group.size
    val avgLon = group.sumOf { it.longitude } / group.size
    // Mixed-kind clusters read as parks (green); pure-summit clusters as summits.
    val allSummits = group.all { it.kind == "summit" }
    val tint = if (allSummits) pinTint("summit") else pinTint("park")
    map.overlays.add(
        Marker(map).apply {
            position = GeoPoint(avgLat, avgLon)
            title = "${group.size} locations"
            icon = clusterDrawable(map.context, tint.toArgb(), group.size)
            setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
            setOnMarkerClickListener { _, _ ->
                // Zoom in on tap rather than trying to pick one pin from the cluster.
                map.controller.animateTo(position)
                map.controller.setZoom(map.zoomLevelDouble + 2.0)
                true
            }
        },
    )
}

private fun dotDrawable(ctx: Context, color: Int): android.graphics.drawable.Drawable {
    val sizePx = (16 * ctx.resources.displayMetrics.density).toInt().coerceAtLeast(1)
    return GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(color)
        setStroke((2 * ctx.resources.displayMetrics.density).toInt(), AndroidColor.WHITE)
        setSize(sizePx, sizePx)
    }
}

/** Diamond marker for a WWFF reference with no borrowed POTA boundary — iOS
 * parity ("bare marker" fallback in `ParkSearchMapView+WWFF.swift`). */
private fun diamondDrawable(ctx: Context, color: Int): android.graphics.drawable.Drawable {
    val density = ctx.resources.displayMetrics.density
    val sizePx = (16 * density).toInt().coerceAtLeast(1)
    val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val half = sizePx / 2f
    val path = android.graphics.Path().apply {
        moveTo(half, 0f)
        lineTo(sizePx.toFloat(), half)
        lineTo(half, sizePx.toFloat())
        lineTo(0f, half)
        close()
    }
    val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { setColor(color) }
    val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        setColor(AndroidColor.WHITE)
        style = Paint.Style.STROKE
        strokeWidth = 2 * density
    }
    canvas.drawPath(path, fillPaint)
    canvas.drawPath(path, strokePaint)
    return BitmapDrawable(ctx.resources, bitmap)
}

/** Cluster badge: a filled circle with the pin count drawn in the center —
 * plain [GradientDrawable] can't render text, so this rasterizes to a bitmap. */
private fun clusterDrawable(ctx: Context, color: Int, count: Int): android.graphics.drawable.Drawable {
    val density = ctx.resources.displayMetrics.density
    val sizePx = (32 * density).toInt().coerceAtLeast(1)
    val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val radius = sizePx / 2f
    val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { setColor(color) }
    val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        setColor(AndroidColor.WHITE)
        style = Paint.Style.STROKE
        strokeWidth = 2 * density
    }
    canvas.drawCircle(radius, radius, radius - strokePaint.strokeWidth / 2f, fillPaint)
    canvas.drawCircle(radius, radius, radius - strokePaint.strokeWidth / 2f, strokePaint)
    val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        setColor(AndroidColor.WHITE)
        textSize = 12 * density
        textAlign = Paint.Align.CENTER
        isFakeBoldText = true
    }
    val label = if (count > 99) "99+" else count.toString()
    val textY = radius - (textPaint.descent() + textPaint.ascent()) / 2f
    canvas.drawText(label, radius, textY, textPaint)
    return BitmapDrawable(ctx.resources, bitmap)
}
