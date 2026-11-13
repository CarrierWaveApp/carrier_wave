package app.carrierwave.android.ui.spots

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CellTower
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import kotlinx.coroutines.delay
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.carrierwave.android.data.UserProfile
import app.carrierwave.android.ui.common.BandPill
import app.carrierwave.android.ui.common.EnrichmentBadges
import app.carrierwave.android.ui.common.ListPadding
import app.carrierwave.android.ui.common.ModePill
import app.carrierwave.android.ui.common.bandColor
import app.carrierwave.android.ui.common.formatFreq
import uniffi.cw_ffi.FfiNeededStatus

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SpotsScreen(
    vm: SpotsViewModel,
    onLogSpot: (Spot) -> Unit,
    onTuneIn: (Spot) -> Unit,
    modifier: Modifier = Modifier,
) {
    val state by vm.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var showFilterSheet by remember { mutableStateOf(false) }
    // Collapsed by default — matches iOS `RBNPanelView`'s non-panel (full tab) default.
    var showMap by remember { mutableStateOf(false) }

    // Hoisted so the filter menu can hide when the user scrolls down through the
    // spot list and reappear when they scroll back up (CAR-297).
    val listState = rememberLazyListState()
    val filtersVisible = listState.isScrollingUp()

    Column(modifier.fillMaxSize()) {
        // Source chips, map/filter toggles, last-refresh pill, and sort picker
        // collapse together on scroll-down; loading/error/notice below stay
        // pinned so status is never hidden.
        AnimatedVisibility(visible = filtersVisible) {
            Column {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    SourceSelector(
                        state.source,
                        state.counts,
                        onSelect = vm::selectSource,
                        modifier = Modifier.weight(1f),
                    )
                    MapToggleButton(showMap) { showMap = !showMap }
                    FilterButton(state.filters.activeCount) { showFilterSheet = true }
                }
                if (showMap) {
                    SpotsMiniMap(
                        spots = state.spots,
                        targetCallsign = UserProfile.callsign(context).ifBlank { "Home" },
                        targetGrid = UserProfile.homeGrid(context).ifBlank { null },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp)
                            .padding(bottom = 6.dp),
                    )
                }
                if (state.lastRefresh > 0L) {
                    LastRefreshPill(
                        epochSeconds = state.lastRefresh,
                        modifier = Modifier
                            .align(Alignment.End)
                            .padding(horizontal = 16.dp)
                            .padding(bottom = 4.dp),
                    )
                }
                SortSelector(
                    selected = state.sortOrder,
                    onSelect = vm::selectSort,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp)
                        .padding(bottom = 4.dp),
                )
            }
        }
        if (state.loading) {
            LinearProgressIndicator(
                Modifier.fillMaxWidth(),
                color = MaterialTheme.colorScheme.primary,
            )
        }
        state.error?.let {
            Text(
                "⚠ $it",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.labelMedium,
                maxLines = 2,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
            )
        }
        state.notice?.let {
            Text(
                it,
                color = MaterialTheme.colorScheme.primary,
                style = MaterialTheme.typography.labelMedium,
                maxLines = 2,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
            )
        }
        PullToRefreshBox(
            isRefreshing = state.refreshing,
            onRefresh = vm::refresh,
            modifier = Modifier.fillMaxSize(),
        ) {
            when {
                state.spots.isEmpty() && state.loading ->
                    CenterText("Loading spots…")
                state.spots.isEmpty() ->
                    CenterText("No ${state.source?.label ?: ""} spots right now.".replace("  ", " "))
                else -> LazyColumn(
                    state = listState,
                    contentPadding = ListPadding,
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    items(state.spots, key = { it.key }) { spot ->
                        val canRespot = spot.source == SpotSource.POTA &&
                            spot.reference != null && spot.freqKhz != null
                        SpotRow(
                            spot,
                            onLog = { onLogSpot(spot) },
                            onTuneIn = { onTuneIn(spot) },
                            onRespot = if (canRespot) {
                                { vm.requestRespot(spot, UserProfile.callsign(context)) }
                            } else {
                                null
                            },
                        )
                    }
                }
            }
        }
    }

    state.respotPrompt?.let { prompt ->
        RespotConfirmDialog(
            prompt = prompt,
            onConfirm = vm::confirmRespot,
            onDismiss = vm::dismissRespot,
        )
    }

    if (showFilterSheet) {
        SpotFilterSheet(
            filters = state.filters,
            onChange = vm::applyFilters,
            onDismiss = { showFilterSheet = false },
        )
    }
}

/**
 * True while the list is at rest or being scrolled *up* (toward the top), false
 * while scrolling down. Drives the collapse of the filter menu on scroll-down
 * (CAR-297). Adapted from the AOSP Compose samples `isScrollingUp()`.
 */
@Composable
private fun LazyListState.isScrollingUp(): Boolean {
    var previousIndex by remember(this) { mutableIntStateOf(firstVisibleItemIndex) }
    var previousOffset by remember(this) { mutableIntStateOf(firstVisibleItemScrollOffset) }
    return remember(this) {
        derivedStateOf {
            if (previousIndex != firstVisibleItemIndex) {
                previousIndex > firstVisibleItemIndex
            } else {
                previousOffset >= firstVisibleItemScrollOffset
            }.also {
                previousIndex = firstVisibleItemIndex
                previousOffset = firstVisibleItemScrollOffset
            }
        }
    }.value
}

/** Recent / Frequency / Needs ordering — the iOS segmented sort picker. */
@Composable
private fun SortSelector(
    selected: SpotsViewModel.SortOrder,
    onSelect: (SpotsViewModel.SortOrder) -> Unit,
    modifier: Modifier = Modifier,
) {
    val orders = SpotsViewModel.SortOrder.entries
    SingleChoiceSegmentedButtonRow(modifier) {
        orders.forEachIndexed { index, order ->
            SegmentedButton(
                selected = selected == order,
                onClick = { onSelect(order) },
                shape = SegmentedButtonDefaults.itemShape(index = index, count = orders.size),
                label = { Text(order.label, style = MaterialTheme.typography.labelMedium) },
            )
        }
    }
}

/** Toggles the collapsible spotter-location mini-map above the list. */
@Composable
private fun MapToggleButton(showMap: Boolean, onClick: () -> Unit) {
    IconButton(onClick = onClick) {
        Icon(
            Icons.Filled.Map,
            contentDescription = if (showMap) "Hide map" else "Show map",
            tint = if (showMap) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
        )
    }
}

/** Funnel button opening the band/mode/worked/needs sheet; badged when active. */
@Composable
private fun FilterButton(activeCount: Int, onClick: () -> Unit) {
    IconButton(onClick = onClick) {
        BadgedBox(badge = {
            if (activeCount > 0) {
                Badge { Text("$activeCount") }
            }
        }) {
            Icon(
                Icons.Filled.Tune,
                contentDescription = "Filter spots",
                tint = if (activeCount > 0) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
            )
        }
    }
}

/**
 * Explicit "Spot on POTA?" confirmation — respotting publishes to POTA under
 * the user's callsign, so it's never one-tap. Mirrors the iOS hunter-log
 * spot confirm, including the anti-spam warning inside the cooldown window.
 */
@Composable
private fun RespotConfirmDialog(
    prompt: SpotsViewModel.RespotPrompt,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    val spot = prompt.spot
    val details = buildString {
        append("Posts a spot for ${spot.callsign} at ${spot.reference} on ")
        append(formatFreq(spot.freqKhz) ?: "unknown frequency")
        if (spot.mode.isNotBlank()) append(" ${spot.mode}")
        append(" as ${prompt.myCallsign}.")
        if (prompt.recentlySpotted) {
            append(
                "\n\nYou spotted ${spot.callsign} less than 5 minutes ago — posting " +
                    "again may be considered spam. Only repost if the frequency or " +
                    "mode has changed.",
            )
        }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Spot on POTA?") },
        text = { Text(details) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(if (prompt.recentlySpotted) "Spot Anyway" else "Spot")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

/**
 * "Updated 3m ago" pill for the engine's last completed poll. Ticks every
 * 30 s so the age stays honest between generation bumps.
 */
@Composable
private fun LastRefreshPill(epochSeconds: Long, modifier: Modifier = Modifier) {
    var now by remember { mutableStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(30_000)
            now = System.currentTimeMillis()
        }
    }
    val ageSec = (now / 1_000 - epochSeconds).coerceAtLeast(0)
    val text = when {
        ageSec < 60 -> "Updated just now"
        ageSec < 3_600 -> "Updated ${ageSec / 60}m ago"
        else -> "Updated ${ageSec / 3_600}h ago"
    }
    Surface(
        modifier,
        shape = RoundedCornerShape(50),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Text(
            text,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
        )
    }
}

@Composable
private fun SourceSelector(
    selected: SpotSource?,
    counts: Map<SpotSource, Int>,
    onSelect: (SpotSource?) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        SourceChip("All", selected == null) { onSelect(null) }
        SpotSource.entries.forEach { source ->
            val count = counts[source] ?: 0
            SourceChip(
                label = if (count > 0) "${source.label} $count" else source.label,
                selected = selected == source,
            ) { onSelect(source) }
        }
    }
}

@Composable
private fun SourceChip(label: String, selected: Boolean, onClick: () -> Unit) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = {
            Text(label, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Medium)
        },
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
            selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
        ),
    )
}

@Composable
private fun SpotRow(
    spot: Spot,
    onLog: () -> Unit,
    onTuneIn: () -> Unit,
    onRespot: (() -> Unit)?,
) {
    ElevatedCard(
        onClick = onLog,
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
        colors = CardDefaults.elevatedCardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Surface(
                color = bandColor(spot.band),
                modifier = Modifier.width(3.dp).height(78.dp),
            ) {}
            Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp).fillMaxWidth()) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = spot.callsign,
                            style = MaterialTheme.typography.titleMedium,
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        NeededBadge(spot.needed)
                    }
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        spot.band?.let { BandPill(it) }
                        ModePill(spot.mode.ifBlank { "—" })
                        if (onRespot != null) {
                            IconButton(onClick = onRespot, modifier = Modifier.size(28.dp)) {
                                Icon(
                                    Icons.Filled.CellTower,
                                    contentDescription = "Respot on POTA",
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(18.dp),
                                )
                            }
                        }
                        if (spot.freqKhz != null) {
                            IconButton(onClick = onTuneIn, modifier = Modifier.size(28.dp)) {
                                Icon(
                                    Icons.Filled.Headphones,
                                    contentDescription = "Tune in on a web SDR",
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(18.dp),
                                )
                            }
                        }
                    }
                }
                EnrichmentBadges(
                    spot.callsign,
                    modifier = Modifier.padding(top = 2.dp),
                    includeQrz = true,
                )
                Row(
                    Modifier.fillMaxWidth().padding(top = 3.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    formatFreq(spot.freqKhz)?.let {
                        Text(
                            it,
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    spot.reference?.let {
                        Text(
                            "📍 $it",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.tertiary,
                        )
                    }
                    signalMeta(spot)?.let {
                        Text(
                            it,
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.75f),
                        )
                    }
                }
                geoMeta(spot)?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.75f),
                        maxLines = 1,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
                spot.comments?.takeIf { it.isNotBlank() }?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.75f),
                        maxLines = 1,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
                Row(
                    Modifier.fillMaxWidth().padding(top = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    spot.spotter?.let {
                        Text(
                            "de $it",
                            style = MaterialTheme.typography.labelSmall,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                        )
                    }
                    spotAge(spot.epochSeconds)?.let {
                        Text(
                            it,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                        )
                    }
                }
            }
        }
    }
}

/** "New DXCC" / "New band" chip when the engine's needs matching flags the spot. */
@Composable
private fun NeededBadge(status: FfiNeededStatus) {
    val label = when (status) {
        FfiNeededStatus.NEW_ENTITY -> "New DXCC"
        FfiNeededStatus.NEW_BAND_SLOT -> "New band"
        else -> return
    }
    Surface(
        color = MaterialTheme.colorScheme.tertiaryContainer,
        shape = RoundedCornerShape(6.dp),
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onTertiaryContainer,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 1.dp),
        )
    }
}

/** "22 wpm · 18 dB" — RBN skimmer metadata, when present. */
private fun signalMeta(spot: Spot): String? {
    val parts = listOfNotNull(
        spot.wpm?.let { "$it wpm" },
        spot.snr?.let { "$it dB" },
    )
    return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
}

/** "Japan · 8,842 km" — engine DXCC/state enrichment + distance from home grid. */
private fun geoMeta(spot: Spot): String? {
    val place = spot.country?.let { country ->
        spot.state?.let { "$it, $country" } ?: country
    } ?: spot.state
    val distance = spot.distanceKm?.let { "%,d km".format(it.toLong()) }
    val parts = listOfNotNull(place, distance)
    return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
}

@Composable
private fun CenterText(text: String) {
    // A single-item LazyColumn (not a plain Box) so the pull-to-refresh
    // gesture still registers on the empty/loading states — PullToRefreshBox
    // needs nested-scroll events, and fillParentMaxSize keeps the text
    // vertically centered in the viewport.
    LazyColumn(Modifier.fillMaxSize()) {
        item {
            Box(Modifier.fillParentMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    text,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
    }
}

/** "3m" / "2h" / "just now" relative to now, from epoch seconds. */
private fun spotAge(epochSeconds: Double?): String? {
    if (epochSeconds == null) return null
    val ageSec = (System.currentTimeMillis() / 1000.0 - epochSeconds).toLong()
    return when {
        ageSec < 60 -> "just now"
        ageSec < 3_600 -> "${ageSec / 60}m"
        ageSec < 86_400 -> "${ageSec / 3_600}h"
        else -> "${ageSec / 86_400}d"
    }
}
