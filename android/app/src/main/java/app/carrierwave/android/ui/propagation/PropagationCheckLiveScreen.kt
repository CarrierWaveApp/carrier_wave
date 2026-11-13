package app.carrierwave.android.ui.propagation

import android.content.Context
import android.graphics.BitmapFactory
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.carrierwave.android.ui.common.bandColor
import app.carrierwave.android.ui.share.ShareMapBox
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Polygon
import uniffi.cw_ffi.FfiPropagationEnrichedSpot
import uniffi.cw_ffi.FfiPropagationStopReason

private enum class LiveMapMode { MAP, AZIMUTHAL }

/**
 * Live "watching" screen: map card + azimuthal card over the current
 * [uniffi.cw_ffi.FfiPropagationState], header stats strip, live spot feed, and
 * Stop. The Android analog of iOS `PropagationCheckLiveView`, minus the
 * MapKit world map (osmdroid stands in — [MAP] mode) and the Auto-CQ banner
 * (iOS-only; drives the CAT/radio bridge Android doesn't have).
 *
 * Map mode uses a plain interactive osmdroid `MapView` with band-colored
 * skimmer pins re-rendered natively per poll (cheap — a handful of markers,
 * the same pattern [app.carrierwave.android.ui.map.QsoDetailMapCard] uses).
 * Azimuthal mode calls [PropagationAzimuthalRenderer], which re-rasterizes via
 * the shared Rust `render_share_map` each time the spot list changes — see the
 * task report for why that's the cheaper faithful choice over a native
 * re-derivation of the projection math.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PropagationCheckLiveScreen(
    vm: PropagationCheckViewModel,
    modifier: Modifier = Modifier,
) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    var mapMode by rememberSaveable { mutableStateOf(LiveMapMode.MAP) }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(title = { Text("Propagation Check") })
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            HeaderStrip(ui)

            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = mapMode == LiveMapMode.MAP,
                    onClick = { mapMode = LiveMapMode.MAP },
                    shape = SegmentedButtonDefaults.itemShape(0, 2),
                ) { Text("Map") }
                SegmentedButton(
                    selected = mapMode == LiveMapMode.AZIMUTHAL,
                    onClick = { mapMode = LiveMapMode.AZIMUTHAL },
                    shape = SegmentedButtonDefaults.itemShape(1, 2),
                ) { Text("Azimuthal") }
            }

            val spots = ui.state?.enrichedSpots.orEmpty()
            when (mapMode) {
                LiveMapMode.MAP -> LiveMapCard(userGrid = ui.config?.userGrid.orEmpty(), spots = spots)
                LiveMapMode.AZIMUTHAL -> LiveAzimuthalCard(userGrid = ui.config?.userGrid.orEmpty(), spots = spots)
            }

            ConnectivityRow(ui)

            SpotFeed(spots = spots, modifier = Modifier.weight(1f))

            Button(
                onClick = { vm.stop(FfiPropagationStopReason.USER) },
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Filled.Stop, contentDescription = null, modifier = Modifier.padding(end = 8.dp))
                Text("Stop")
            }
        }
    }
}

@Composable
private fun HeaderStrip(ui: PropagationCheckUiState) {
    val state = ui.state
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            Metric("Elapsed", formatElapsed(ui.elapsedSeconds))
            Metric("Spots", "${state?.totalSpots ?: 0}")
            Metric("Skimmers", "${state?.uniqueSkimmers ?: 0}")
            Metric("Bands", "${state?.bandsWithActivity?.size ?: 0}")
        }
    }
}

@Composable
private fun Metric(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleMedium, fontFamily = FontFamily.Monospace)
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ConnectivityRow(ui: PropagationCheckUiState) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        SourceDot("RBN", ui.rbnConnected)
        SourceDot("PSKR", ui.pskrConnected)
        ui.lastError?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
    }
}

@Composable
private fun SourceDot(label: String, connected: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(
            Modifier
                .width(8.dp)
                .height(8.dp)
                .clip(CircleShape)
                .background(if (connected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error),
        )
        Text(label, style = MaterialTheme.typography.labelSmall)
    }
}

@Composable
private fun LiveMapCard(userGrid: String, spots: List<FfiPropagationEnrichedSpot>) {
    // The parent recomposes every 1s (elapsed-time tick), but new spots only
    // land every ~30s (RBN cadence) or ~5min (PSK Reporter). `AndroidView.update`
    // otherwise re-runs on every recomposition, and `renderLiveMap` does a full
    // overlays.clear() + marker rebuild + invalidate() — wasted work 29 out of
    // 30 seconds. Gate on a spots-identity key (size + userGrid), the same
    // cheap-enough-at-this-cadence signal `LiveAzimuthalCard` keys its
    // `LaunchedEffect` on below.
    val spotsKey = remember(userGrid, spots.size) { userGrid to spots.size }
    val lastRenderedKey = remember { mutableStateOf<Pair<String, Int>?>(null) }
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp)),
    ) {
        AndroidView(
            modifier = Modifier.fillMaxWidth().height(240.dp),
            factory = { ctx -> buildLiveMapView(ctx) },
            update = { map ->
                if (lastRenderedKey.value != spotsKey) {
                    renderLiveMap(map, userGrid, spots)
                    lastRenderedKey.value = spotsKey
                }
            },
        )
    }
}

private fun buildLiveMapView(ctx: Context): MapView {
    Configuration.getInstance().load(ctx, ctx.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
    Configuration.getInstance().userAgentValue = ctx.packageName
    return MapView(ctx).apply {
        setTileSource(TileSourceFactory.MAPNIK)
        setMultiTouchControls(true)
        controller.setZoom(2.0)
        controller.setCenter(GeoPoint(30.0, -40.0))
    }
}

private fun renderLiveMap(map: MapView, userGrid: String, spots: List<FfiPropagationEnrichedSpot>) {
    map.overlays.clear()
    val home = uniffi.cw_ffi.maidenheadCoordinate(userGrid)
    home?.let { coord ->
        map.overlays.add(
            dotMarkerFor(map, GeoPoint(coord.latitude, coord.longitude), android.graphics.Color.WHITE, "You"),
        )
    }
    spots.forEach { spot ->
        val lat = spot.latitude ?: return@forEach
        val lon = spot.longitude ?: return@forEach
        val color = bandColor(spot.spot.band)
        val argb = android.graphics.Color.argb(
            255,
            (color.red * 255).toInt(),
            (color.green * 255).toInt(),
            (color.blue * 255).toInt(),
        )
        map.overlays.add(
            dotMarkerFor(map, GeoPoint(lat, lon), argb, spot.spot.skimmerCall),
        )
    }
    map.invalidate()
}

/** Small filled-dot marker, screen-size-independent (degrees-based radius). */
private fun dotMarkerFor(map: MapView, center: GeoPoint, fillColor: Int, title: String): Polygon {
    val sides = 12
    val radiusDegrees = 1.2
    val points = (0 until sides).map { i ->
        val angle = 2.0 * Math.PI * i / sides
        GeoPoint(center.latitude + radiusDegrees * Math.cos(angle), center.longitude + radiusDegrees * Math.sin(angle))
    }
    return Polygon(map).apply {
        this.points = points
        fillPaint.color = fillColor
        outlinePaint.color = android.graphics.Color.WHITE
        outlinePaint.strokeWidth = 2f
        this.title = title
    }
}

/**
 * Azimuthal card: re-renders via the shared Rust rasterizer whenever the spot
 * list identity changes (keyed on size + userGrid — new spots arrive appended,
 * so size is a cheap-enough change signal at a several-second poll cadence).
 */
@Composable
private fun LiveAzimuthalCard(userGrid: String, spots: List<FfiPropagationEnrichedSpot>) {
    var result by remember { mutableStateOf<PropagationMapResult?>(null) }

    LaunchedEffect(userGrid, spots.size) {
        result = withContext(Dispatchers.IO) {
            runCatching { PropagationAzimuthalRenderer.render(userGrid, spots) }.getOrNull()
        }
    }

    val current = result
    if (current == null) {
        Box(
            Modifier
                .fillMaxWidth()
                .height((AZIMUTHAL_WIDTH_DP / AZIMUTHAL_ASPECT_RATIO).dp),
            contentAlignment = Alignment.Center,
        ) {
            CircularProgressIndicator()
        }
        return
    }
    val bitmap = remember(current) {
        BitmapFactory.decodeByteArray(current.pngBytes, 0, current.pngBytes.size).asImageBitmap()
    }
    ShareMapBox(
        mapImage = bitmap,
        ringLabels = current.ringLabels,
        boxWidthDp = AZIMUTHAL_WIDTH_DP,
        aspectRatio = AZIMUTHAL_ASPECT_RATIO,
    )
}

@Composable
private fun SpotFeed(spots: List<FfiPropagationEnrichedSpot>, modifier: Modifier = Modifier) {
    if (spots.isEmpty()) {
        Column(
            modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(24.dp))
            CircularProgressIndicator()
            Spacer(Modifier.height(8.dp))
            Text("Waiting for spots…", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                "RBN spots within seconds of TX. PSK Reporter polls every 5 min.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }
    LazyColumn(modifier.fillMaxWidth()) {
        items(spots.asReversed(), key = { it.id }) { spot ->
            SpotRow(spot)
        }
    }
}

@Composable
private fun SpotRow(spot: FfiPropagationEnrichedSpot) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            Modifier
                .width(10.dp)
                .height(10.dp)
                .clip(CircleShape)
                .background(bandColor(spot.spot.band)),
        )
        Column(Modifier.weight(1f)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(spot.spot.skimmerCall, fontFamily = FontFamily.Monospace)
                Text(spot.spot.band ?: "", style = MaterialTheme.typography.labelSmall)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(spot.spot.mode, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                spot.spot.snrDb?.let {
                    Text("${it.toInt()} dB", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(
                    if (spot.spot.source == "rbn") "RBN" else "PSKR",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.outline,
                )
            }
        }
    }
}

private fun formatElapsed(seconds: Long): String {
    val mins = seconds / 60
    val secs = seconds % 60
    return String.format(java.util.Locale.US, "%02d:%02d", mins, secs)
}

private const val AZIMUTHAL_WIDTH_DP = 340
private val AZIMUTHAL_ASPECT_RATIO =
    PropagationAzimuthalRenderer.MAP_WIDTH.toFloat() / PropagationAzimuthalRenderer.MAP_HEIGHT.toFloat()
