package app.carrierwave.android.ui.hunter

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.carrierwave.android.ui.spots.Spot

/** Values the user can adjust before logging a spot from the sheet. */
data class SpotLogForm(
    val rstSent: String,
    val rstReceived: String,
    val theirGrid: String?,
    val state: String?,
    val notes: String?,
)

/**
 * Half-sheet for logging a QSO from a tapped hunter-log spot — the Android
 * analog of iOS `SpotLogSheet`. Callsign, frequency, mode, and the activity
 * reference come from the spot; the user only touches RST (defaulted by mode)
 * and optional extras behind a "More fields" disclosure.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SpotLogSheet(
    spot: Spot,
    myCallsign: String,
    logName: String,
    isLogging: Boolean,
    error: String?,
    onLog: (SpotLogForm) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        SpotLogFormContent(spot, myCallsign, logName, isLogging, error, onLog)
    }
}

@Composable
private fun SpotLogFormContent(
    spot: Spot,
    myCallsign: String,
    logName: String,
    isLogging: Boolean,
    error: String?,
    onLog: (SpotLogForm) -> Unit,
) {
    // Phone modes exchange 59; everything else 599 (matches iOS defaultRST).
    val defaultRst = when (spot.mode.uppercase()) {
        "SSB", "USB", "LSB", "FM", "AM" -> "59"
        else -> "599"
    }
    var rstSent by rememberSaveable { mutableStateOf("") }
    var rstReceived by rememberSaveable { mutableStateOf("") }
    var showMore by rememberSaveable { mutableStateOf(false) }
    var theirGrid by rememberSaveable { mutableStateOf("") }
    var state by rememberSaveable { mutableStateOf("") }
    var notes by rememberSaveable { mutableStateOf("") }

    Column(
        Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .imePadding()
            .padding(horizontal = 20.dp)
            .padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // ── Spot info ────────────────────────────────────────────
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                spot.callsign,
                style = MaterialTheme.typography.titleLarge,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                spot.freqKhz?.let {
                    Text(
                        "%.3f MHz".format(it / 1_000.0),
                        style = MaterialTheme.typography.bodyMedium,
                        fontFamily = FontFamily.Monospace,
                    )
                }
                Text(
                    listOfNotNull(spot.band, spot.mode.ifBlank { null }).joinToString(" "),
                    style = MaterialTheme.typography.bodyMedium,
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
        }

        // ── RST ──────────────────────────────────────────────────
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedTextField(
                value = rstSent,
                onValueChange = { rstSent = it },
                modifier = Modifier.weight(1f),
                label = { Text("RST Sent") },
                placeholder = { Text(defaultRst) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            )
            OutlinedTextField(
                value = rstReceived,
                onValueChange = { rstReceived = it },
                modifier = Modifier.weight(1f),
                label = { Text("RST Rcvd") },
                placeholder = { Text(defaultRst) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            )
        }

        // ── More fields (grid / state / notes) ───────────────────
        Row(
            Modifier
                .fillMaxWidth()
                .clickable { showMore = !showMore },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("More fields", style = MaterialTheme.typography.titleSmall)
            Spacer(Modifier.width(4.dp))
            Icon(
                if (showMore) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        AnimatedVisibility(showMore) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = theirGrid,
                    onValueChange = { theirGrid = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Their Grid") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                )
                OutlinedTextField(
                    value = state,
                    onValueChange = { state = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("State/Province") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                )
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Notes") },
                    singleLine = true,
                )
            }
        }

        error?.let {
            Text(
                "⚠ $it",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.labelSmall,
            )
        }

        // ── Log button + footer ──────────────────────────────────
        Button(
            onClick = {
                onLog(
                    SpotLogForm(
                        rstSent = rstSent.ifBlank { defaultRst },
                        rstReceived = rstReceived.ifBlank { defaultRst },
                        theirGrid = theirGrid.trim().ifBlank { null },
                        state = state.trim().ifBlank { null },
                        notes = notes.trim().ifBlank { null },
                    ),
                )
            },
            enabled = !isLogging,
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (isLogging) {
                CircularProgressIndicator(
                    Modifier.height(20.dp).width(20.dp),
                    color = MaterialTheme.colorScheme.onPrimary,
                )
            } else {
                Text("Log QSO")
            }
        }
        Text(
            "Logging as $myCallsign · $logName",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(4.dp))
    }
}
