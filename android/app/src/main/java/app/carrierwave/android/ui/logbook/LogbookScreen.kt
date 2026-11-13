package app.carrierwave.android.ui.logbook

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.carrierwave.android.ui.callsign.CallsignMapSection
import app.carrierwave.android.ui.common.QsoEditSheet
import app.carrierwave.android.ui.common.QsoSections
import app.carrierwave.android.ui.common.QueryBar
import app.carrierwave.android.ui.map.QsoDetailMapCard

/**
 * Logbook tab — every QSO, searchable. Mirrors the iOS Logbook (`logs`) tab:
 * a filter bar over the shared Rust query DSL plus the date-grouped QSO list,
 * with the Logs-toolbar ADIF import behind the overflow menu.
 */
@Composable
fun LogbookScreen(vm: LogbookViewModel, modifier: Modifier = Modifier) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    val qsos by vm.qsos.collectAsStateWithLifecycle()
    val loading by vm.loading.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var menuOpen by remember { mutableStateOf(false) }

    // The iOS `fileImporter` equivalent. `.adi`/`.adif` have no registered MIME
    // type (providers report text/plain or application/octet-stream), so accept
    // any document and let the Rust parser decide what it can read.
    val adifPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) vm.importAdif(context, uri)
    }

    Column(modifier.fillMaxSize()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) {
                QueryBar(
                    analysis = ui.queryAnalysis,
                    error = ui.queryError,
                    onChanged = vm::onQueryChange,
                    placeholder = "search: band:20m mode:CW call:W1 …",
                )
            }
            Box {
                IconButton(onClick = { menuOpen = true }) {
                    Icon(Icons.Filled.MoreVert, contentDescription = "Logbook menu")
                }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    DropdownMenuItem(
                        text = { Text(if (ui.importing) "Importing…" else "Import ADIF…") },
                        enabled = !ui.importing,
                        onClick = {
                            menuOpen = false
                            adifPicker.launch(arrayOf("*/*"))
                        },
                    )
                }
            }
        }
        if (ui.importing) {
            LinearProgressIndicator(Modifier.fillMaxWidth())
        } else {
            HorizontalDivider(
                thickness = 0.5.dp,
                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
            )
        }
        Box(Modifier.weight(1f)) {
            QsoSections(
                qsos = qsos,
                homeGrid = vm.homeGrid,
                loading = loading,
                emptyText = if (ui.filtered) {
                    "No QSOs match this filter."
                } else {
                    "No QSOs yet — log one from the Sessions tab or import an ADIF file."
                },
                onQsoClick = vm::editQso,
            )
        }
    }

    // Import outcome — the iOS "Import Complete" / "Import Failed" alerts.
    ui.importResult?.let { message ->
        AlertDialog(
            onDismissRequest = vm::dismissImportMessage,
            title = { Text("Import Complete") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = vm::dismissImportMessage) { Text("OK") } },
        )
    }
    ui.importError?.let { message ->
        AlertDialog(
            onDismissRequest = vm::dismissImportMessage,
            title = { Text("Import Failed") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = vm::dismissImportMessage) { Text("OK") } },
        )
    }

    // Tap a QSO card to edit it — the iOS QSODetailView → QSOEditSheet flow.
    ui.editingQso?.let { qso ->
        QsoEditSheet(
            qso = qso,
            onSave = vm::updateQso,
            onDelete = vm::deleteQso,
            onDismiss = vm::dismissEditor,
            mapContent = { current ->
                Column(Modifier.fillMaxWidth().padding(top = 4.dp)) {
                    current.theirGrid?.takeIf { it.isNotBlank() }?.let { grid ->
                        CallsignMapSection(
                            grid = grid,
                            callsign = current.callsign,
                            homeGrid = vm.homeGrid,
                            modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp),
                        )
                    }
                    QsoDetailMapCard(mapApi = vm.mapApi, qsoId = current.id)
                }
            },
        )
    }
}
