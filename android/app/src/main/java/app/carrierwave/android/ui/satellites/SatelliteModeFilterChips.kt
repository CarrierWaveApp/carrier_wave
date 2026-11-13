package app.carrierwave.android.ui.satellites

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.carrierwave.android.data.SatBand
import app.carrierwave.android.data.SatelliteFilterBucket
import app.carrierwave.android.data.SatelliteModeFilter
import app.carrierwave.android.data.SkySector

/**
 * FM/Linear/Digital/Telemetry multi-select chips over the shared
 * chart+passes work-type filter (pass-list surfaces; the chart exposes
 * the same filter through a toolbar dropdown instead of chips).
 */
@Composable
fun SatelliteModeFilterChips(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val selection by SatelliteModeFilter.selection.collectAsStateWithLifecycle()
    val uplink by SatelliteModeFilter.uplinkBands.collectAsStateWithLifecycle()
    val downlink by SatelliteModeFilter.downlinkBands.collectAsStateWithLifecycle()
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = modifier) {
        for (bucket in SatelliteFilterBucket.entries) {
            FilterChip(
                selected = bucket in selection,
                onClick = { SatelliteModeFilter.toggle(context, bucket) },
                label = { Text(bucket.label) },
            )
        }
        BandFilterChip(arrow = "↑", bands = uplink) {
            SatelliteModeFilter.toggleUplinkBand(context, it)
        }
        BandFilterChip(arrow = "↓", bands = downlink) {
            SatelliteModeFilter.toggleDownlinkBand(context, it)
        }
        ElevationFilterChip()
        HorizonFilterChip()
        val heardOnly by SatelliteModeFilter.heardRecentlyOnly.collectAsStateWithLifecycle()
        FilterChip(
            selected = heardOnly,
            onClick = { SatelliteModeFilter.setHeardRecentlyOnly(context, !heardOnly) },
            label = { Text("Heard") },
        )
        val favoritesOnly by SatelliteModeFilter.favoritesOnly.collectAsStateWithLifecycle()
        FilterChip(
            selected = favoritesOnly,
            onClick = { SatelliteModeFilter.setFavoritesOnly(context, !favoritesOnly) },
            label = { Text("★") },
        )
    }
}

/** Per-sector minimum-elevation label for the horizon mask. */
private fun horizonLabel(sector: SkySector, minimum: Int): String = when (minimum) {
    0 -> sector.raw
    SatelliteModeFilter.BLOCKED_ELEVATION -> "${sector.raw} ✕"
    else -> "${sector.raw} ≥$minimum°"
}

/** Horizon-mask chip ("Horizon" / "Horizon N30,W✕") with a dropdown of
 * tap-to-cycle sector rows (stays open across taps). */
@Composable
private fun HorizonFilterChip() {
    val context = LocalContext.current
    val mask by SatelliteModeFilter.horizonMask.collectAsStateWithLifecycle()
    var expanded by remember { mutableStateOf(false) }
    val active = SatelliteModeFilter.horizonActive(mask)
    val summary = SkySector.entries.mapNotNull { sector ->
        val minimum = mask[sector] ?: 0
        when {
            minimum == 0 -> null
            minimum == SatelliteModeFilter.BLOCKED_ELEVATION -> "${sector.raw}✕"
            else -> "${sector.raw}$minimum"
        }
    }
    FilterChip(
        selected = active,
        onClick = { expanded = true },
        label = { Text(if (active) "Horizon ${summary.joinToString(",")}" else "Horizon") },
    )
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
        for (sector in SkySector.entries) {
            DropdownMenuItem(
                text = { Text(horizonLabel(sector, mask[sector] ?: 0)) },
                onClick = { SatelliteModeFilter.cycleHorizon(context, sector) },
            )
        }
    }
}

/** "El ≥ Any/20°" single-select threshold chip with a dropdown. */
@Composable
private fun ElevationFilterChip() {
    val context = LocalContext.current
    val minPeak by SatelliteModeFilter.minPeakElevation.collectAsStateWithLifecycle()
    var expanded by remember { mutableStateOf(false) }
    FilterChip(
        selected = minPeak > 0,
        onClick = { expanded = true },
        label = { Text("El ≥ ${SatelliteModeFilter.peakElevationLabel(minPeak)}") },
    )
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
        for (option in SatelliteModeFilter.PEAK_ELEVATION_OPTIONS) {
            DropdownMenuItem(
                text = { Text(SatelliteModeFilter.peakElevationLabel(option)) },
                trailingIcon = {
                    if (option == minPeak) Icon(Icons.Filled.Check, contentDescription = null)
                },
                onClick = {
                    SatelliteModeFilter.setMinPeakElevation(context, option)
                    expanded = false
                },
            )
        }
    }
}

/** Compact band chip ("↑ All" / "↓ U,V") opening a toggle dropdown. */
@Composable
private fun BandFilterChip(
    arrow: String,
    bands: Set<SatBand>,
    onToggle: (SatBand) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val narrowed = bands.size < SatelliteModeFilter.ALL_BANDS.size
    val label = if (narrowed) {
        SatBand.entries.filter { it in bands }.joinToString(",") { it.raw }
    } else {
        "All"
    }
    FilterChip(
        selected = narrowed,
        onClick = { expanded = true },
        label = { Text("$arrow $label") },
    )
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
        for (band in SatBand.entries) {
            DropdownMenuItem(
                text = { Text(band.label) },
                trailingIcon = {
                    if (band in bands) Icon(Icons.Filled.Check, contentDescription = null)
                },
                onClick = { onToggle(band) },
            )
        }
    }
}

/**
 * Toolbar entry for the chart: a filter icon opening checkmark rows —
 * the same shared filter without spending chart real estate on chips
 * (iOS parks it in the map's ⋯ menu). The dropdown stays open across
 * taps, so multi-select is one gesture stream.
 */
@Composable
fun SatelliteModeFilterMenuButton() {
    val context = LocalContext.current
    val selection by SatelliteModeFilter.selection.collectAsStateWithLifecycle()
    val uplink by SatelliteModeFilter.uplinkBands.collectAsStateWithLifecycle()
    val downlink by SatelliteModeFilter.downlinkBands.collectAsStateWithLifecycle()
    var expanded by remember { mutableStateOf(false) }
    IconButton(onClick = { expanded = true }) {
        Icon(Icons.Filled.FilterList, contentDescription = "Filter satellites by mode")
    }
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
        for (bucket in SatelliteFilterBucket.entries) {
            DropdownMenuItem(
                text = { Text(bucket.label) },
                trailingIcon = {
                    if (bucket in selection) {
                        Icon(Icons.Filled.Check, contentDescription = null)
                    }
                },
                onClick = { SatelliteModeFilter.toggle(context, bucket) },
            )
        }
        HorizontalDivider()
        BandSection(title = "Uplink band", bands = uplink) {
            SatelliteModeFilter.toggleUplinkBand(context, it)
        }
        HorizontalDivider()
        BandSection(title = "Downlink band", bands = downlink) {
            SatelliteModeFilter.toggleDownlinkBand(context, it)
        }
        HorizontalDivider()
        Text(
            "Next pass peaks ≥",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
        )
        val minPeak by SatelliteModeFilter.minPeakElevation.collectAsStateWithLifecycle()
        for (option in SatelliteModeFilter.PEAK_ELEVATION_OPTIONS) {
            DropdownMenuItem(
                text = { Text(SatelliteModeFilter.peakElevationLabel(option)) },
                trailingIcon = {
                    if (option == minPeak) Icon(Icons.Filled.Check, contentDescription = null)
                },
                onClick = { SatelliteModeFilter.setMinPeakElevation(context, option) },
            )
        }
        HorizontalDivider()
        Text(
            "Horizon — min elevation by direction (tap to cycle)",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
        )
        val mask by SatelliteModeFilter.horizonMask.collectAsStateWithLifecycle()
        for (sector in SkySector.entries) {
            DropdownMenuItem(
                text = { Text(horizonLabel(sector, mask[sector] ?: 0)) },
                onClick = { SatelliteModeFilter.cycleHorizon(context, sector) },
            )
        }
        HorizontalDivider()
        val heardOnly by SatelliteModeFilter.heardRecentlyOnly.collectAsStateWithLifecycle()
        DropdownMenuItem(
            text = { Text("Heard this week only") },
            trailingIcon = {
                if (heardOnly) Icon(Icons.Filled.Check, contentDescription = null)
            },
            onClick = { SatelliteModeFilter.setHeardRecentlyOnly(context, !heardOnly) },
        )
        val favoritesOnly by SatelliteModeFilter.favoritesOnly.collectAsStateWithLifecycle()
        DropdownMenuItem(
            text = { Text("Favorites only") },
            trailingIcon = {
                if (favoritesOnly) Icon(Icons.Filled.Check, contentDescription = null)
            },
            onClick = { SatelliteModeFilter.setFavoritesOnly(context, !favoritesOnly) },
        )
    }
}

@Composable
private fun BandSection(
    title: String,
    bands: Set<SatBand>,
    onToggle: (SatBand) -> Unit,
) {
    Text(
        title,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
    )
    for (band in SatBand.entries) {
        DropdownMenuItem(
            text = { Text(band.label) },
            trailingIcon = {
                if (band in bands) Icon(Icons.Filled.Check, contentDescription = null)
            },
            onClick = { onToggle(band) },
        )
    }
}
