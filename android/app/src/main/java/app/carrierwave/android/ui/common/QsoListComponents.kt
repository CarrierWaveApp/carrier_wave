package app.carrierwave.android.ui.common

import androidx.compose.foundation.BorderStroke
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.FilterAlt
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.SuggestionChipDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import uniffi.cw_ffi.FfiQso
import uniffi.cw_ffi.FfiQueryAnalysis
import uniffi.cw_ffi.FfiQueryCost
import uniffi.cw_ffi.FfiQueryWarning
import uniffi.cw_ffi.FfiSeverity

/**
 * Shared filter/query bar used by the Logger and Logbook tabs. Surfaces the
 * validated query cost (uses-index / bounded / full-scan) and any warnings from
 * the shared Rust analyzer, or an error if the expression doesn't parse.
 */
@Composable
fun QueryBar(
    analysis: FfiQueryAnalysis?,
    error: String?,
    onChanged: (String) -> Unit,
    placeholder: String = "filter: band:20m mode:FT8 …",
) {
    var text by rememberSaveable { mutableStateOf("") }
    Column(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        OutlinedTextField(
            value = text,
            onValueChange = { value ->
                text = value
                onChanged(value)
            },
            modifier = Modifier.fillMaxWidth(),
            placeholder = {
                Text(placeholder, fontFamily = FontFamily.Monospace)
            },
            leadingIcon = { Icon(Icons.Default.Search, null) },
            isError = error != null,
            singleLine = true,
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = MaterialTheme.colorScheme.primary,
                unfocusedBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f),
            ),
        )
        Spacer(Modifier.height(4.dp))
        when {
            error != null -> Text(
                text = "⚠ $error",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.labelSmall,
                fontFamily = FontFamily.Monospace,
            )
            analysis != null -> Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CostChip(analysis.cost)
                analysis.warnings.forEach { WarningChip(it) }
            }
        }
    }
}

@Composable
private fun CostChip(cost: FfiQueryCost) {
    val (label, icon, tint) = when (cost) {
        FfiQueryCost.INDEXED -> Triple("uses-index", Icons.Default.Bolt, Color(0xFF4CAF83))
        FfiQueryCost.BOUNDED -> Triple("bounded-scan", Icons.Default.FilterAlt, Color(0xFFFFB74D))
        FfiQueryCost.FULL_SCAN -> Triple("full-scan", Icons.Default.Warning, Color(0xFFCF6679))
    }
    SuggestionChip(
        onClick = {},
        label = {
            Text(label, style = MaterialTheme.typography.labelSmall, fontFamily = FontFamily.Monospace)
        },
        icon = { Icon(icon, null, Modifier.size(14.dp), tint = tint) },
        border = BorderStroke(0.5.dp, tint.copy(alpha = 0.5f)),
        colors = SuggestionChipDefaults.suggestionChipColors(containerColor = tint.copy(alpha = 0.08f)),
    )
}

@Composable
private fun WarningChip(warning: FfiQueryWarning) {
    val tint = when (warning.severity) {
        FfiSeverity.HINT -> Color(0xFF90CAF9)
        FfiSeverity.MEDIUM -> Color(0xFFFFB74D)
        FfiSeverity.HIGH -> Color(0xFFCF6679)
    }
    SuggestionChip(
        onClick = {},
        label = { Text(warning.message, style = MaterialTheme.typography.labelSmall, maxLines = 1) },
        icon = { Icon(Icons.Default.Info, null, Modifier.size(14.dp), tint = tint) },
        border = BorderStroke(0.5.dp, tint.copy(alpha = 0.4f)),
        colors = SuggestionChipDefaults.suggestionChipColors(containerColor = tint.copy(alpha = 0.07f)),
    )
}

/**
 * Shared date-grouped QSO list. Groups by UTC day with a per-day header + count,
 * shows a spinner while the first page loads, and [emptyText] when there are none.
 */
@Composable
fun QsoSections(
    qsos: List<FfiQso>,
    homeGrid: String,
    loading: Boolean,
    emptyText: String,
    onQsoClick: ((FfiQso) -> Unit)? = null,
) {
    if (loading && qsos.isEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
        }
        return
    }
    if (qsos.isEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                emptyText,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
        return
    }
    val sections = qsos.groupBy { utcDayKey(it.qsoDate) }.entries.toList()
    LazyColumn(
        contentPadding = ListPadding,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        sections.forEach { (_, rows) ->
            item(key = "hdr-${rows.first().id}") {
                DateHeader(formatDay(rows.first().qsoDate), rows.size)
            }
            items(rows, key = { it.id }) { qso ->
                QsoCard(qso, homeGrid, onClick = onQsoClick?.let { click -> { click(qso) } })
            }
        }
    }
}

@Composable
private fun DateHeader(day: String, count: Int) {
    Row(
        Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 2.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            day,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            "$count QSO${if (count == 1) "" else "s"}",
            style = MaterialTheme.typography.labelSmall,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
