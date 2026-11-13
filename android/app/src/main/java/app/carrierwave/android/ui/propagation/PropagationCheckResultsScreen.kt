package app.carrierwave.android.ui.propagation

import android.graphics.BitmapFactory
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
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
import app.carrierwave.android.ui.common.bandColor
import app.carrierwave.android.ui.share.ShareMapBox
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.FfiPropagationResults
import uniffi.cw_ffi.FfiPropagationStopReason

private enum class ResultsMapMode { MAP, AZIMUTHAL }

/**
 * Results screen for a finished propagation check — the Android analog of iOS
 * `PropagationCheckResultsView`, scoped to headline stats + map (both modes) +
 * per-band table + spot list. Android has no SwiftData artifact store for
 * propagation checks yet, so results are shown for the just-finished session
 * only (not persisted/re-browsable) — see [PropagationCheckViewModel]'s class
 * doc.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PropagationCheckResultsScreen(
    results: FfiPropagationResults,
    stopReason: FfiPropagationStopReason,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var mapMode by rememberSaveable { mutableStateOf(ResultsMapMode.MAP) }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Propagation Check Results") },
                navigationIcon = {
                    IconButton(onClick = onDone) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Done")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            HeadlineCard(results)

            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = mapMode == ResultsMapMode.MAP,
                    onClick = { mapMode = ResultsMapMode.MAP },
                    shape = SegmentedButtonDefaults.itemShape(0, 2),
                ) { Text("Map") }
                SegmentedButton(
                    selected = mapMode == ResultsMapMode.AZIMUTHAL,
                    onClick = { mapMode = ResultsMapMode.AZIMUTHAL },
                    shape = SegmentedButtonDefaults.itemShape(1, 2),
                ) { Text("Azimuthal") }
            }

            when (mapMode) {
                ResultsMapMode.MAP -> ResultsFlatMapCard(results)
                ResultsMapMode.AZIMUTHAL -> ResultsAzimuthalCard(results)
            }

            if (results.totalSpots <= 2) {
                SparseHelpCard(results)
            }

            BandBreakdownCard(results)

            MetaCard(results, stopReason)

            Button(onClick = onDone, modifier = Modifier.fillMaxWidth()) {
                Text("Done")
            }
        }
    }
}

@Composable
private fun HeadlineCard(results: FfiPropagationResults) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                StatTile("Spots", "${results.totalSpots}")
                StatTile("Skimmers", "${results.uniqueSkimmers}")
                StatTile("Bands", "${results.bandsWithActivity.size}")
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                StatTile("Max distance", distanceLabel(results.maxDistanceKm))
                StatTile("Peak SNR", "${results.peakSnrDb.toInt()} dB")
                StatTile("Duration", durationLabel(results.endedAtEpoch - results.startedAtEpoch))
            }
        }
    }
}

@Composable
private fun StatTile(title: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleMedium, fontFamily = FontFamily.Monospace)
        Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ResultsAzimuthalCard(results: FfiPropagationResults) {
    var result by remember(results) { mutableStateOf<PropagationMapResult?>(null) }
    LaunchedEffect(results) {
        result = withContext(Dispatchers.IO) {
            runCatching { PropagationAzimuthalRenderer.render(results.userGrid, results.enrichedSpots) }.getOrNull()
        }
    }
    val current = result
    if (current == null) {
        Box(
            Modifier.fillMaxWidth().height((RESULTS_MAP_WIDTH_DP / RESULTS_ASPECT_RATIO).dp),
            contentAlignment = Alignment.Center,
        ) { CircularProgressIndicator() }
        return
    }
    val bitmap = remember(current) {
        BitmapFactory.decodeByteArray(current.pngBytes, 0, current.pngBytes.size).asImageBitmap()
    }
    ShareMapBox(
        mapImage = bitmap,
        ringLabels = current.ringLabels,
        boxWidthDp = RESULTS_MAP_WIDTH_DP,
        aspectRatio = RESULTS_ASPECT_RATIO,
    )
}

/**
 * Flat map for saved results. Reuses the same Rust rasterizer as the
 * azimuthal card (a non-azimuthal [uniffi.cw_ffi.FfiShareMapStyle]) rather
 * than a second osmdroid `MapView` — the results screen is a static review
 * surface (unlike the live screen, which needs pan/zoom while watching spots
 * arrive), so the themed PNG is the simpler, cheaper choice here and mirrors
 * how iOS's `PropagationCheckMapCard` falls back to the same renderer for its
 * non-MapKit themed styles.
 */
@Composable
private fun ResultsFlatMapCard(results: FfiPropagationResults) {
    var result by remember(results) { mutableStateOf<PropagationMapResult?>(null) }
    LaunchedEffect(results) {
        result = withContext(Dispatchers.IO) {
            runCatching { PropagationFlatMapRenderer.render(results.userGrid, results.enrichedSpots) }.getOrNull()
        }
    }
    val current = result
    if (current == null) {
        Box(
            Modifier.fillMaxWidth().height((RESULTS_MAP_WIDTH_DP / RESULTS_ASPECT_RATIO).dp),
            contentAlignment = Alignment.Center,
        ) { CircularProgressIndicator() }
        return
    }
    val bitmap = remember(current) {
        BitmapFactory.decodeByteArray(current.pngBytes, 0, current.pngBytes.size).asImageBitmap()
    }
    ShareMapBox(
        mapImage = bitmap,
        ringLabels = current.ringLabels,
        boxWidthDp = RESULTS_MAP_WIDTH_DP,
        aspectRatio = RESULTS_ASPECT_RATIO,
    )
}

@Composable
private fun SparseHelpCard(results: FfiPropagationResults) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Nobody (or almost nobody) heard you", style = MaterialTheme.typography.titleSmall)
            Text(
                "RBN and PSK Reporter were both reachable. Common causes: band was dead, antenna/feedline" +
                    " issue, wrong band CQ'd, callsign typo (yours: ${results.callsign}), or a short FT8" +
                    " session under PSK Reporter's 15 min window granularity.",
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

/**
 * Per-band stat line, computed to match iOS
 * `PropagationCheckStatistics.bandBreakdown(spots:userGrid:)`: spot/skimmer
 * counts over all spots in the band, max distance + median/peak SNR over the
 * subset that carries that stat (nil distance or nil SNR spots are dropped
 * from their respective metric only, independently — a spot missing SNR can
 * still contribute to distance and vice versa).
 */
private data class BandBreakdownRow(
    val band: String,
    val spotCount: Int,
    val uniqueSkimmers: Int,
    val maxDistanceKm: Double,
    val medianSnrDb: Double,
    val peakSnrDb: Double,
)

/** Same identity the Rust dedup key uses (`source-CALL-freqHz-secondBucket`,
 * see `dedup_key` in propagation_api/mod.rs) — precise enough to join a raw
 * `FfiPropagationSpot` (from `results.spots`) back to its
 * `FfiPropagationEnrichedSpot.distanceKm` (from `results.enrichedSpots`)
 * without colliding on same-band/same-skimmer repeat spots. */
private fun spotIdentity(spot: uniffi.cw_ffi.FfiPropagationSpot) =
    Triple(spot.source, spot.skimmerCall.uppercase(), spot.freqHz) to spot.timestampEpoch.toLong()

private fun bandBreakdown(results: FfiPropagationResults): List<BandBreakdownRow> {
    val distanceBySpot = results.enrichedSpots
        .filter { it.distanceKm != null }
        .associate { spotIdentity(it.spot) to it.distanceKm!! }
    return results.spots
        .groupBy { it.band ?: "?" }
        .map { (band, spots) ->
            val distances = spots.mapNotNull { distanceBySpot[spotIdentity(it)] }
            val snrs = spots.mapNotNull { it.snrDb }.sorted()
            BandBreakdownRow(
                band = band,
                spotCount = spots.size,
                uniqueSkimmers = spots.map { it.skimmerCall.uppercase() }.distinct().size,
                maxDistanceKm = distances.maxOrNull() ?: 0.0,
                medianSnrDb = medianOf(snrs) ?: 0.0,
                peakSnrDb = snrs.maxOrNull() ?: 0.0,
            )
        }
        .sortedBy { it.band }
}

private fun medianOf(sorted: List<Double>): Double? {
    if (sorted.isEmpty()) return null
    val mid = sorted.size / 2
    return if (sorted.size % 2 == 0) (sorted[mid - 1] + sorted[mid]) / 2 else sorted[mid]
}

@Composable
private fun BandBreakdownCard(results: FfiPropagationResults) {
    val rows = bandBreakdown(results)
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Per Band", style = MaterialTheme.typography.titleMedium)
            if (rows.isEmpty()) {
                Text("No band activity captured.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                rows.forEach { row -> BandStatRow(row) }
            }
        }
    }
}

@Composable
private fun BandStatRow(row: BandBreakdownRow) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(
                Modifier.width(12.dp).height(12.dp).clip(CircleShape)
                    .background(bandColor(row.band)),
            )
            Text(row.band, fontFamily = FontFamily.Monospace)
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(
                "${row.spotCount} spots · ${row.uniqueSkimmers} RX",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "${distanceLabel(row.maxDistanceKm)} max · ${row.medianSnrDb.toInt()} dB med · ${row.peakSnrDb.toInt()} dB peak",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun MetaCard(results: FfiPropagationResults, stopReason: FfiPropagationStopReason) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            MetaRow("Callsign", results.callsign)
            MetaRow("Grid", results.userGrid)
            MetaRow("Stop reason", stopReason.name.lowercase().replace("_", " "))
            if (results.connectivityGaps.isNotEmpty()) {
                Text(
                    "Connectivity gaps",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                results.connectivityGaps.forEach { gap ->
                    MetaRow(gap.source.uppercase(), "${(gap.endedAtEpoch - gap.startedAtEpoch).toInt()} s")
                }
            }
        }
    }
}

@Composable
private fun MetaRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace)
    }
}

private fun distanceLabel(km: Double): String {
    if (km <= 0) return "—"
    val miles = km * 0.621371
    return "${miles.toInt()} mi"
}

private fun durationLabel(seconds: Double): String {
    val mins = (seconds / 60).toInt()
    return if (mins == 0) "${seconds.toInt()}s" else "$mins min"
}

private const val RESULTS_MAP_WIDTH_DP = 340
private val RESULTS_ASPECT_RATIO =
    PropagationAzimuthalRenderer.MAP_WIDTH.toFloat() / PropagationAzimuthalRenderer.MAP_HEIGHT.toFloat()
