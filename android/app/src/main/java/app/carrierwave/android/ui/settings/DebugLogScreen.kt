package app.carrierwave.android.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import app.carrierwave.android.util.AppLog
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Debug Log settings screen — Android's analog to iOS's in-app log surfaces.
 * Shows [AppLog]'s ring buffer in reverse-chronological order with copy/clear
 * actions. No persistence, no filtering — the log is meant for pasting into a
 * bug report, not long-term browsing.
 */
@Composable
fun DebugLogScreen(onBack: () -> Unit) {
    val entries by AppLog.entries.collectAsState()
    val clipboard = LocalClipboardManager.current

    Column(Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.padding(start = 4.dp, end = 20.dp, top = 20.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
            }
            Text(
                "Debug Log",
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.weight(1f),
            )
            TextButton(
                onClick = { clipboard.setText(AnnotatedString(entries.toLogText())) },
                enabled = entries.isNotEmpty(),
            ) {
                Text("Copy")
            }
            TextButton(onClick = { AppLog.clear() }, enabled = entries.isNotEmpty()) {
                Text("Clear")
            }
        }

        if (entries.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    "No log entries yet.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 20.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                items(entries.asReversed()) { entry -> LogEntryRow(entry) }
            }
        }
    }
}

@Composable
private fun LogEntryRow(entry: AppLog.Entry) {
    Row(
        modifier = Modifier
            .fillMaxSize()
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            entry.formattedTime(),
            style = MaterialTheme.typography.bodySmall,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            entry.message,
            style = MaterialTheme.typography.bodySmall,
            fontFamily = FontFamily.Monospace,
            color = if (entry.level == AppLog.Level.ERROR) {
                MaterialTheme.colorScheme.error
            } else {
                MaterialTheme.colorScheme.onSurface
            },
        )
    }
}

private val timeFormat = SimpleDateFormat("HH:mm:ss", Locale.US)

private fun AppLog.Entry.formattedTime(): String = timeFormat.format(Date(timestampMs))

private fun List<AppLog.Entry>.toLogText(): String =
    asReversed().joinToString("\n") { entry ->
        "${entry.formattedTime()} [${entry.level}] ${entry.message}"
    }
