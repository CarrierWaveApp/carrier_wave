package app.carrierwave.android.ui.activations

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.carrierwave.android.ui.common.QsoSections
import app.carrierwave.android.ui.common.formatDuration

private val ChipBlue = Color(0xFF3B82F6)
private val PotaGreen = Color(0xFF22C55E)

/**
 * Post-activation detail — the Android analog of the iOS activation detail
 * (`ActivationStatsSummaryView` header + activation map + `QSOTimelineView`).
 * A header stats card (QSO count, duration, bands, modes), a compact map card
 * over the park+UTC-day QSO window, and the shared date-grouped QSO timeline.
 *
 * Part 1 (map port Phase D Task 10) is view-only. Upload/awards/conditions/
 * export verbs arrive in Task 11.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivationDetailScreen(
    vm: ActivationDetailViewModel,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    val context = LocalContext.current

    // Share flow lives "above" the detail as a keyed overlay (same pattern the
    // list uses for detail), dismissed by the system back gesture.
    var showShare by remember { mutableStateOf(false) }
    var showConditions by remember { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }

    if (showShare) {
        BackHandler { showShare = false }
        ActivationShareScreen(
            park = vm.park,
            parkName = ui.parkName,
            callsign = vm.callsign,
            utcDate = vm.utcDate,
            onBack = { showShare = false },
            modifier = modifier,
        )
        return
    }

    if (showConditions) {
        ui.conditions?.let { meta ->
            ActivationConditionsSheet(meta = meta, onDismiss = { showConditions = false })
        }
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(
                            vm.park,
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                        )
                        Text(
                            "${vm.callsign} · ${vm.utcDate}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = "Activation actions")
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text("Share activation") },
                            onClick = { menuOpen = false; showShare = true },
                        )
                        DropdownMenuItem(
                            text = { Text(if (ui.exporting) "Exporting…" else "Export ADIF") },
                            enabled = !ui.exporting && ui.qsos.isNotEmpty(),
                            onClick = { menuOpen = false; vm.exportAdif(context) },
                        )
                        if (ui.conditions != null) {
                            DropdownMenuItem(
                                text = { Text("Conditions") },
                                onClick = { menuOpen = false; showConditions = true },
                            )
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            ActivationStatsCard(ui.stats)
            ui.mapData?.let { data ->
                ActivationMapCard(
                    data = data,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
                )
            }
            Box(Modifier.fillMaxSize()) {
                QsoSections(
                    qsos = ui.qsos,
                    homeGrid = vm.homeGrid,
                    loading = !ui.loaded,
                    emptyText = "No QSOs in this activation.",
                )
            }
        }
    }
}

/** Header stats mirroring iOS `ActivationStatsSummaryView`: count, duration, bands, modes. */
@Composable
private fun ActivationStatsCard(stats: ActivationStats) {
    Card(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
        shape = RoundedCornerShape(12.dp),
    ) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                StatPill("${stats.qsoCount} Q", PotaGreen)
                Spacer(Modifier.padding(3.dp))
                StatPill(formatDuration(stats.durationSeconds * 1_000L), ChipBlue)
                if (stats.bands.isNotEmpty()) {
                    Spacer(Modifier.padding(3.dp))
                    StatPill("${stats.bands.size} band${if (stats.bands.size == 1) "" else "s"}", ChipBlue)
                }
                if (stats.modes.isNotEmpty()) {
                    Spacer(Modifier.padding(3.dp))
                    StatPill("${stats.modes.size} mode${if (stats.modes.size == 1) "" else "s"}", ChipBlue)
                }
            }
            if (stats.bands.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                Text(
                    "Bands: ${stats.bands.joinToString(" · ")}",
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (stats.modes.isNotEmpty()) {
                Spacer(Modifier.height(2.dp))
                Text(
                    "Modes: ${stats.modes.joinToString(" · ")}",
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun StatPill(text: String, tint: Color) {
    Surface(shape = RoundedCornerShape(50), color = tint.copy(alpha = 0.16f)) {
        Text(
            text,
            Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Medium,
            color = tint,
        )
    }
}
