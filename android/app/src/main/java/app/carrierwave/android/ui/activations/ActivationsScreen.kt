package app.carrierwave.android.ui.activations

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.BottomAppBar
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel

/**
 * The POTA activation browser — the Android analog of iOS `POTAActivationsView`.
 * Lists every activation (park + operator + UTC-day group with a QSO count) from
 * the shared Rust rollup, newest first; tapping one opens
 * [ActivationDetailScreen] as a keyed `rememberSaveable` overlay (the same
 * navigation pattern the Sessions tab uses for session detail).
 *
 * Reached from the More/Account tab. Part 1 (map port Phase D Task 10) is the
 * list + detail + timeline; Task 11 layers on upload status, awards, conditions,
 * and export.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivationsScreen(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    vm: ActivationsViewModel = viewModel(factory = ActivationsViewModel.factory()),
) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    val context = LocalContext.current

    // Detail overlay keyed by the activation's stable key. Sits "above" the list
    // in the back stack, dismissed by the system back gesture.
    var openKey by rememberSaveable { mutableStateOf<String?>(null) }
    var showAwards by rememberSaveable { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }

    if (showAwards) {
        BackHandler { showAwards = false }
        ActivationAwardsScreen(onBack = { showAwards = false }, modifier = modifier)
        return
    }

    val openRow = openKey?.let { key -> ui.activations.firstOrNull { it.key == key } }
    if (openRow != null) {
        BackHandler { openKey = null }
        val detailVm: ActivationDetailViewModel = viewModel(
            key = "activation-detail-${openRow.key}",
            factory = ActivationDetailViewModel.factory(openRow.park, openRow.callsign, openRow.utcDate),
        )
        ActivationDetailScreen(vm = detailVm, onBack = { openKey = null }, modifier = modifier)
        return
    }

    if (ui.selectionMode) BackHandler { vm.setSelectionMode(false) }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        if (ui.selectionMode) "${ui.selectedKeys.size} selected" else "POTA Activations",
                        fontWeight = FontWeight.SemiBold,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = { if (ui.selectionMode) vm.setSelectionMode(false) else onBack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (!ui.selectionMode) {
                        IconButton(onClick = { menuOpen = true }) {
                            Icon(Icons.Filled.MoreVert, contentDescription = "Activation menu")
                        }
                        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                            DropdownMenuItem(
                                text = { Text("Awards & Certificates") },
                                onClick = { menuOpen = false; showAwards = true },
                            )
                            DropdownMenuItem(
                                text = { Text("Export ADIF…") },
                                enabled = ui.activations.isNotEmpty(),
                                onClick = { menuOpen = false; vm.setSelectionMode(true) },
                            )
                        }
                    } else {
                        TextButton(onClick = { vm.setSelectionMode(false) }) { Text("Cancel") }
                    }
                },
            )
        },
        bottomBar = {
            if (ui.selectionMode) {
                BottomAppBar {
                    Button(
                        onClick = { vm.exportSelected(context) },
                        enabled = !ui.exporting && ui.selectedKeys.isNotEmpty(),
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp),
                    ) {
                        Text(
                            if (ui.exporting) {
                                "Exporting…"
                            } else {
                                "Export ${ui.selectedKeys.size} activation${if (ui.selectedKeys.size == 1) "" else "s"}"
                            },
                        )
                    }
                }
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when {
                !ui.loaded -> CircularProgressIndicator(
                    Modifier.align(Alignment.Center),
                    color = MaterialTheme.colorScheme.primary,
                )
                ui.activations.isEmpty() -> Text(
                    ui.error ?: "No POTA activations yet. Log QSOs at a park to see them here.",
                    Modifier.align(Alignment.Center).padding(32.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center,
                )
                else -> LazyColumn(
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(ui.activations, key = { it.key }) { row ->
                        ActivationRowCard(
                            row = row,
                            selectionMode = ui.selectionMode,
                            selected = row.key in ui.selectedKeys,
                            onClick = {
                                if (ui.selectionMode) vm.toggleSelection(row.key) else openKey = row.key
                            },
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ActivationRowCard(
    row: ActivationRow,
    selectionMode: Boolean,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
        ),
        shape = RoundedCornerShape(12.dp),
    ) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (selectionMode) {
                Checkbox(checked = selected, onCheckedChange = { onClick() })
                Spacer(Modifier.padding(2.dp))
            }
            Column(Modifier.weight(1f)) {
                Text(
                    row.park,
                    style = MaterialTheme.typography.titleSmall,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    "${row.callsign} · ${row.utcDate}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Surface(
                shape = RoundedCornerShape(50),
                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.14f),
            ) {
                Text(
                    "${row.qsoCount} Q",
                    Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}
