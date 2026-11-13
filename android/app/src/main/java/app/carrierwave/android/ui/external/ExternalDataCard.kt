package app.carrierwave.android.ui.external

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel

/**
 * External Data — cached reference databases with per-dataset refresh, the
 * Android counterpart of iOS `ExternalDataView`. Downloads and storage run
 * in the shared Rust core.
 */
@Composable
fun ExternalDataCard() {
    val vm: ExternalDataViewModel = viewModel(factory = ExternalDataViewModel.factory())
    val state by vm.state.collectAsStateWithLifecycle()

    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
        Column(Modifier.padding(16.dp)) {
            Text(
                "External Data",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                "Cached reference databases: parks, summits, callsigns, gear, contests.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = vm::downloadAll,
                enabled = !state.downloadingAll,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (state.downloadingAll) {
                    CircularProgressIndicator(
                        Modifier.size(18.dp),
                        color = MaterialTheme.colorScheme.onPrimary,
                        strokeWidth = 2.dp,
                    )
                    Spacer(Modifier.size(8.dp))
                    Text("Downloading All Sources…")
                } else {
                    Text("Download All Sources")
                }
            }
            Spacer(Modifier.height(8.dp))
            ExternalDataset.entries.forEachIndexed { index, dataset ->
                if (index > 0) {
                    HorizontalDivider(
                        thickness = 0.5.dp,
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.25f),
                    )
                }
                DatasetRow(
                    dataset = dataset,
                    row = state.rows[dataset] ?: DatasetUi(),
                    onRefresh = { vm.refresh(dataset) },
                )
            }
        }
    }
}

@Composable
private fun DatasetRow(dataset: ExternalDataset, row: DatasetUi, onRefresh: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(dataset.label, style = MaterialTheme.typography.bodyLarge)
            Text(
                statusLine(dataset, row),
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            row.note?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.tertiary,
                )
            }
            row.error?.let {
                Text(
                    "⚠ $it",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
        if (row.busy) {
            CircularProgressIndicator(
                Modifier.size(20.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.primary,
            )
        } else {
            IconButton(onClick = onRefresh) {
                Icon(
                    Icons.Filled.Refresh,
                    contentDescription = "Refresh ${dataset.label}",
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

/** "52,381 parks · updated 3d ago" / "Not downloaded". */
private fun statusLine(dataset: ExternalDataset, row: DatasetUi): String {
    if (row.count <= 0 && row.fetchedAt == null) return "Not downloaded"
    val count = "%,d ${dataset.unit}".format(row.count)
    val age = row.fetchedAt?.let { "updated ${agoText(it)}" }
    return listOfNotNull(count, age).joinToString(" · ")
}

/** "just now" / "5m ago" / "3h ago" / "12d ago" from Unix seconds. */
private fun agoText(epochSeconds: Long): String {
    val ageSec = System.currentTimeMillis() / 1_000 - epochSeconds
    return when {
        ageSec < 60 -> "just now"
        ageSec < 3_600 -> "${ageSec / 60}m ago"
        ageSec < 86_400 -> "${ageSec / 3_600}h ago"
        else -> "${ageSec / 86_400}d ago"
    }
}
