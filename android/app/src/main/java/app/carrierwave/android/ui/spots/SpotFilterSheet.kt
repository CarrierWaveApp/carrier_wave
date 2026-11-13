package app.carrierwave.android.ui.spots

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** Common bands offered as filter chips (superset of what the pool usually carries). */
private val FILTER_BANDS =
    listOf("160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m", "2m", "70cm")

/** Common modes offered as filter chips. */
private val FILTER_MODES = listOf("CW", "SSB", "FT8", "FT4", "RTTY", "PSK31", "AM", "FM")

/**
 * Band/mode/worked/needs filter sheet for the spot feed — the Android analog of
 * iOS `SpotFilterSheet`. Edits apply live to the feed behind the sheet via
 * [onChange]; source selection stays on the quick-chip bar.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SpotFilterSheet(
    filters: SpotsViewModel.WidgetFilters,
    onChange: (SpotsViewModel.WidgetFilters) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        SpotFilterContent(filters, onChange)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SpotFilterContent(
    filters: SpotsViewModel.WidgetFilters,
    onChange: (SpotsViewModel.WidgetFilters) -> Unit,
) {
    // Local working copy; each edit commits live so the feed updates behind the sheet.
    var working by remember { mutableStateOf(filters) }
    fun update(next: SpotsViewModel.WidgetFilters) {
        working = next
        onChange(next)
    }

    Column(
        Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Filter spots", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            TextButton(
                onClick = { update(SpotsViewModel.WidgetFilters()) },
                enabled = working != SpotsViewModel.WidgetFilters(),
            ) { Text("Clear all") }
        }

        SectionLabel("Band")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FILTER_BANDS.forEach { band ->
                ToggleChip(band, working.bands.contains(band)) {
                    update(working.copy(bands = working.bands.toggle(band)))
                }
            }
        }

        SectionLabel("Mode")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FILTER_MODES.forEach { mode ->
                ToggleChip(mode, working.modes.contains(mode)) {
                    update(working.copy(modes = working.modes.toggle(mode)))
                }
            }
        }

        SwitchRow("Needs only", working.needsOnly) { update(working.copy(needsOnly = it)) }
    }
}

private fun Set<String>.toggle(value: String): Set<String> =
    if (contains(value)) this - value else this + value

@Composable
private fun SectionLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.primary,
    )
}

@Composable
private fun ToggleChip(label: String, selected: Boolean, onClick: () -> Unit) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Medium) },
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
            selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
        ),
    )
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge)
        Switch(checked = checked, onCheckedChange = onChange)
    }
}
