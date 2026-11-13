package app.carrierwave.android.ui.satellites

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.carrierwave.android.data.FavoriteSatellites
import app.carrierwave.android.data.SatelliteModeFilter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import uniffi.cw_ffi.FfiSatellitePass
import uniffi.cw_ffi.FfiSatelliteSearchItem
import uniffi.cw_ffi.FfiUpcomingPass

/** Shared 10°/20° thresholds (mirror of `SatelliteWorkability`). */
private const val MIN_WORKABLE_DEG = 10.0
private const val RECOMMENDED_DEG = 20.0

private fun isMarginal(peak: Double) = peak >= MIN_WORKABLE_DEG && peak < RECOMMENDED_DEG

private val timeFormat = SimpleDateFormat("EEE HH:mm", Locale.getDefault())
private val shortTimeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())

// MARK: - Search

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SatelliteSearchScreen(
    items: List<FfiSatelliteSearchItem>,
    onSelect: (UInt) -> Unit,
    onBack: () -> Unit,
) {
    var query by remember { mutableStateOf("") }
    val context = LocalContext.current
    val favorites by FavoriteSatellites.state.collectAsStateWithLifecycle()
    BackHandler(onBack = onBack)
    val filtered = remember(query, items, favorites) {
        val matching = if (query.isBlank()) {
            items
        } else {
            items.filter { item ->
                item.name.contains(query, ignoreCase = true) ||
                    item.detailName?.contains(query, ignoreCase = true) == true ||
                    item.noradId.toString().startsWith(query)
            }
        }
        // Favorites first (stable partition), original order within groups.
        matching.filter { favorites.contains(it.noradId) } +
            matching.filterNot { favorites.contains(it.noradId) }
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Find Satellite") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(modifier = Modifier.padding(padding).fillMaxSize()) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                label = { Text("Satellite name or NORAD ID") },
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            )
            LazyColumn {
                // Lazy keys must be Bundle-saveable; boxed UInt is not (crash
                // on first row), so key by the Long value.
                items(filtered, key = { it.noradId.toLong() }) { item ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSelect(item.noradId) }
                            .padding(horizontal = 16.dp, vertical = 10.dp),
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(item.name, style = MaterialTheme.typography.bodyLarge)
                            Text(
                                (item.detailName?.let { "$it · " } ?: "") + "NORAD ${item.noradId}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        val isFavorite = favorites.contains(item.noradId)
                        IconButton(onClick = { FavoriteSatellites.toggle(context, item.noradId) }) {
                            Icon(
                                if (isFavorite) Icons.Filled.Star else Icons.Outlined.StarBorder,
                                contentDescription =
                                    if (isFavorite) "Remove from favorites" else "Add to favorites",
                                tint = if (isFavorite) Color(0xFFF9A825) else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Upcoming (all-sky)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SatelliteUpcomingScreen(
    vm: SatelliteViewModel,
    onSelect: (UInt) -> Unit,
    onBack: () -> Unit,
) {
    var passes by remember { mutableStateOf<List<FfiUpcomingPass>?>(null) }
    val favorites by FavoriteSatellites.state.collectAsStateWithLifecycle()
    val modeSelection by SatelliteModeFilter.selection.collectAsStateWithLifecycle()
    val uplinkBands by SatelliteModeFilter.uplinkBands.collectAsStateWithLifecycle()
    val downlinkBands by SatelliteModeFilter.downlinkBands.collectAsStateWithLifecycle()
    val minPeak by SatelliteModeFilter.minPeakElevation.collectAsStateWithLifecycle()
    val heardOnly by SatelliteModeFilter.heardRecentlyOnly.collectAsStateWithLifecycle()
    val favoritesOnly by SatelliteModeFilter.favoritesOnly.collectAsStateWithLifecycle()
    val horizonMask by SatelliteModeFilter.horizonMask.collectAsStateWithLifecycle()
    BackHandler(onBack = onBack)
    LaunchedEffect(Unit) { passes = vm.upcomingPasses(emptyList()) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Upcoming Passes") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        val loaded = passes
        if (loaded == null) {
            Row(
                modifier = Modifier.padding(padding).fillMaxWidth().padding(24.dp),
                horizontalArrangement = Arrangement.Center,
            ) { CircularProgressIndicator() }
        } else {
            val workable = loaded.filter { item ->
                item.pass.peakElevationDeg >= maxOf(MIN_WORKABLE_DEG, minPeak.toDouble()) &&
                    SatelliteModeFilter.horizonAllows(
                        item.pass.peakAzimuthDeg,
                        item.pass.peakElevationDeg,
                        horizonMask,
                    ) &&
                    (!favoritesOnly || item.noradId in favorites) &&
                    SatelliteModeFilter.matches(
                        vm.transmitters(item.noradId),
                        modeSelection,
                        uplinkBands,
                        downlinkBands,
                        heardOnly,
                    )
            }
            val ordered = workable.filter { favorites.contains(it.noradId) } +
                workable.filterNot { favorites.contains(it.noradId) }
            Column(modifier = Modifier.padding(padding)) {
                // Above the list so the chips stay reachable when the
                // filter empties the sky.
                SatelliteModeFilterChips(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                )
                LazyColumn {
                    items(ordered, key = { "${it.noradId}-${it.pass.aosEpoch}" }) { item ->
                        UpcomingPassRow(
                            item = item,
                            isFavorite = favorites.contains(item.noradId),
                            onClick = { onSelect(item.noradId) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun UpcomingPassRow(item: FfiUpcomingPass, isFavorite: Boolean, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (isFavorite) {
                Icon(
                    Icons.Filled.Star,
                    contentDescription = null,
                    tint = Color(0xFFF9A825),
                    modifier = Modifier.padding(end = 4.dp),
                )
            }
            Text(item.name, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
            PassPeakLabel(item.pass)
        }
        PassTimeLine(item.pass)
    }
}

// MARK: - Per-satellite pass list

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SatellitePassListScreen(
    vm: SatelliteViewModel,
    noradId: UInt,
    onBack: () -> Unit,
) {
    var forecast by remember { mutableStateOf<List<FfiSatellitePass>?>(null) }
    var alwaysVisible by remember { mutableStateOf(false) }
    val name = vm.summary(noradId)?.name ?: "Passes"
    BackHandler(onBack = onBack)
    LaunchedEffect(noradId) {
        val result = vm.passForecast(noradId)
        forecast = result?.passes ?: emptyList()
        alwaysVisible = result?.isAlwaysVisible ?: false
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(name) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        val loaded = forecast
        when {
            loaded == null -> Row(
                modifier = Modifier.padding(padding).fillMaxWidth().padding(24.dp),
                horizontalArrangement = Arrangement.Center,
            ) { CircularProgressIndicator() }

            alwaysVisible -> Text(
                "$name stays above your horizon continuously — no discrete passes.",
                modifier = Modifier.padding(padding).padding(16.dp),
            )

            loaded.isEmpty() -> Text(
                "No passes rise above your horizon in the next 48 hours.",
                modifier = Modifier.padding(padding).padding(16.dp),
            )

            else -> LazyColumn(modifier = Modifier.padding(padding)) {
                items(loaded, key = { it.aosEpoch }) { pass ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                timeFormat.format(Date(pass.aosEpoch * 1_000)) +
                                    " – " + shortTimeFormat.format(Date(pass.losEpoch * 1_000)),
                                style = MaterialTheme.typography.bodyLarge,
                                modifier = Modifier.weight(1f),
                            )
                            PassPeakLabel(pass)
                        }
                        PassTimeLine(pass)
                    }
                }
            }
        }
    }
}

// MARK: - Shared row pieces

@Composable
private fun PassPeakLabel(pass: FfiSatellitePass) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        if (isMarginal(pass.peakElevationDeg)) {
            Text(
                "marginal",
                style = MaterialTheme.typography.labelSmall,
                color = Color(0xFFE65100),
            )
        }
        Text(
            "%.0f° max".format(pass.peakElevationDeg),
            style = MaterialTheme.typography.bodyMedium,
            color = when {
                pass.peakElevationDeg >= 45 -> Color(0xFF2E7D32)
                pass.peakElevationDeg >= RECOMMENDED_DEG -> MaterialTheme.colorScheme.onSurface
                else -> MaterialTheme.colorScheme.onSurfaceVariant
            },
        )
    }
}

@Composable
private fun PassTimeLine(pass: FfiSatellitePass) {
    val minutes = ((pass.losEpoch - pass.aosEpoch) / 60).coerceAtLeast(1)
    val remainingMs = pass.aosEpoch * 1_000 - System.currentTimeMillis()
    val countdown = when {
        remainingMs <= 0 -> "now"
        remainingMs < 3_600_000 -> "in ${remainingMs / 60_000}m"
        else -> "in ${remainingMs / 3_600_000}h ${(remainingMs / 60_000) % 60}m"
    }
    Text(
        "$countdown · $minutes min · " +
            "${compassPoint(pass.aosAzimuthDeg)} → ${compassPoint(pass.losAzimuthDeg)}",
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

private fun compassPoint(degrees: Double): String {
    val points = listOf("N", "NE", "E", "SE", "S", "SW", "W", "NW")
    val index = (((degrees + 22.5) / 45.0).toInt()).mod(8)
    return points[index]
}
