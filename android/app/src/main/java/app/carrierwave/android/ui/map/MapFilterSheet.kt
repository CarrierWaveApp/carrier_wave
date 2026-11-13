package app.carrierwave.android.ui.map

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * Filter/display options for the Map tab. Mirrors iOS `MapFilterSheet`: band
 * / mode / park single-select chips, a UTC date range, confirmed-only +
 * individual-pin switches, and a reset. Every change funnels through
 * [MapViewModel.updateFilter] so the map reloads from Rust immediately.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun MapFilterSheet(
    data: MapUiStateFilterOptions,
    filter: MapFilter,
    onUpdate: ((MapFilter) -> MapFilter) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState()
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Map Filters", style = MaterialTheme.typography.titleMedium)

            if (data.bands.isNotEmpty()) {
                FilterSection(title = "Band") {
                    ChipRow(data.bands, filter.band) { selected ->
                        onUpdate { it.copy(band = selected) }
                    }
                }
            }

            if (data.modes.isNotEmpty()) {
                FilterSection(title = "Mode") {
                    ChipRow(data.modes, filter.mode) { selected ->
                        onUpdate { it.copy(mode = selected) }
                    }
                }
            }

            if (data.parks.isNotEmpty()) {
                FilterSection(title = "Park") {
                    if (data.parks.size > 8) {
                        ParkDropdown(data.parks, filter.park) { selected ->
                            onUpdate { it.copy(park = selected) }
                        }
                    } else {
                        ChipRow(data.parks, filter.park) { selected ->
                            onUpdate { it.copy(park = selected) }
                        }
                    }
                }
            }

            FilterSection(title = "Date Range") {
                DateRangeRow(
                    startDate = filter.startDate,
                    endDate = filter.endDate,
                    onStartDate = { onUpdate { f -> f.copy(startDate = it) } },
                    onEndDate = { onUpdate { f -> f.copy(endDate = it) } },
                )
            }

            HorizontalDivider()

            SwitchRow(
                label = "Confirmed only",
                checked = filter.confirmedOnly,
                onCheckedChange = { onUpdate { f -> f.copy(confirmedOnly = it) } },
            )
            SwitchRow(
                label = "Show individual QSOs",
                checked = filter.showIndividual,
                onCheckedChange = { onUpdate { f -> f.copy(showIndividual = it) } },
            )

            if (filter.hasActiveFilters) {
                TextButton(onClick = { onUpdate { MapFilter() } }) {
                    Text("Reset")
                }
            }
        }
    }
}

/** Filter-sheet option lists sourced from [FfiQsoMapData]. */
data class MapUiStateFilterOptions(
    val bands: List<String>,
    val modes: List<String>,
    val parks: List<String>,
)

@Composable
private fun FilterSection(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        content()
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ChipRow(options: List<String>, selected: String?, onSelect: (String?) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { option ->
            FilterChip(
                selected = selected == option,
                onClick = { onSelect(if (selected == option) null else option) },
                label = { Text(option) },
            )
        }
    }
}

@Composable
private fun ParkDropdown(options: List<String>, selected: String?, onSelect: (String?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Column {
        OutlinedButton(onClick = { expanded = true }) {
            Text(selected ?: "All Parks")
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text("All Parks") }, onClick = { onSelect(null); expanded = false })
            options.forEach { park ->
                DropdownMenuItem(text = { Text(park) }, onClick = { onSelect(park); expanded = false })
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DateRangeRow(
    startDate: Long?,
    endDate: Long?,
    onStartDate: (Long?) -> Unit,
    onEndDate: (Long?) -> Unit,
) {
    var showStartPicker by remember { mutableStateOf(false) }
    var showEndPicker by remember { mutableStateOf(false) }

    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(onClick = { showStartPicker = true }, modifier = Modifier.weight(1f)) {
            Text("From: ${formatUtcDate(startDate) ?: "Any"}")
        }
        OutlinedButton(onClick = { showEndPicker = true }, modifier = Modifier.weight(1f)) {
            Text("To: ${formatUtcDate(endDate) ?: "Any"}")
        }
    }
    if (startDate != null || endDate != null) {
        TextButton(onClick = { onStartDate(null); onEndDate(null) }) {
            Text("Clear Date Range")
        }
    }

    if (showStartPicker) {
        UtcDatePickerDialog(
            initialMillis = startDate?.let { it * 1000L },
            onDismiss = { showStartPicker = false },
            onConfirm = { onStartDate(it?.let { millis -> millis / 1000L }); showStartPicker = false },
        )
    }
    if (showEndPicker) {
        UtcDatePickerDialog(
            initialMillis = endDate?.let { it * 1000L },
            onDismiss = { showEndPicker = false },
            onConfirm = { onEndDate(it?.let { millis -> millis / 1000L }); showEndPicker = false },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun UtcDatePickerDialog(initialMillis: Long?, onDismiss: () -> Unit, onConfirm: (Long?) -> Unit) {
    val state = rememberDatePickerState(initialSelectedDateMillis = initialMillis)
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            Button(onClick = { onConfirm(state.selectedDateMillis) }) { Text("OK") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    ) {
        DatePicker(state = state)
    }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

private val utcDateFormat = SimpleDateFormat("MMM d, yyyy", Locale.US).apply {
    timeZone = TimeZone.getTimeZone("UTC")
}

private fun formatUtcDate(epochSeconds: Long?): String? =
    epochSeconds?.let { utcDateFormat.format(it * 1000L) }
