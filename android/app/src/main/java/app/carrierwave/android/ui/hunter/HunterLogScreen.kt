package app.carrierwave.android.ui.hunter

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.carrierwave.android.CwApp
import app.carrierwave.android.data.TuneInPhase
import app.carrierwave.android.data.UserProfile
import app.carrierwave.android.ui.common.DupeBadge
import app.carrierwave.android.ui.common.EnrichmentBadges
import app.carrierwave.android.ui.common.QsoEditSheet
import app.carrierwave.android.ui.common.QuickEntryCommandBar
import app.carrierwave.android.ui.common.formatTime
import app.carrierwave.android.ui.common.ScpSuggestionRow
import app.carrierwave.android.ui.spots.SpotsScreen
import app.carrierwave.android.ui.spots.SpotsViewModel
import app.carrierwave.android.ui.tunein.TuneInBar
import app.carrierwave.android.ui.tunein.TuneInErrorRow
import app.carrierwave.android.ui.tunein.TuneInStrategyDialog
import android.widget.Toast
import uniffi.cw_ffi.FfiDuplicateStatus
import uniffi.cw_ffi.FfiQso
import uniffi.cw_ffi.FfiQuickToken
import uniffi.cw_ffi.FfiSessionMetadataEntry
import uniffi.cw_ffi.FfiTodayStats

@Composable
fun HunterLogScreen(
    vm: HunterLogViewModel,
    spotsVm: SpotsViewModel,
    modifier: Modifier = Modifier,
) {
    val ui by vm.ui.collectAsStateWithLifecycle()

    if (!ui.loaded) {
        Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
        }
        return
    }

    val active = ui.activeLog
    if (active == null) {
        StartLogPrompt(modifier, onStart = vm::createLog)
        return
    }

    // Tapping the "today" summary card expands the list of QSOs logged today,
    // each tappable to edit (CAR-289).
    var recentExpanded by rememberSaveable { mutableStateOf(false) }

    // One-shot confirmation after applying session metadata ("14.046 CW").
    val context = LocalContext.current
    LaunchedEffect(ui.notice) {
        ui.notice?.let {
            Toast.makeText(context, it, Toast.LENGTH_LONG).show()
            vm.consumeNotice()
        }
    }

    Column(modifier.fillMaxSize()) {
        TodayHeader(
            name = active.name,
            today = ui.today,
            recent = ui.recent,
            expanded = recentExpanded,
            onToggleExpanded = { recentExpanded = !recentExpanded },
            onEditQso = vm::editQso,
        )
        HorizontalDivider(
            thickness = 0.5.dp,
            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
        )
        // The live spot feed is the hunter log's body (iOS ActivityLogView
        // shape). Today's logged contacts live in the Logbook tab. Tapping a
        // spot opens the pre-filled log sheet (iOS SpotLogSheet), with a dupe
        // confirmation first when it was already worked today.
        val tuneIn = (LocalContext.current.applicationContext as CwApp).tuneIn
        val tuneState by tuneIn.state.collectAsStateWithLifecycle()
        Box(Modifier.weight(1f)) {
            SpotsScreen(
                spotsVm,
                onLogSpot = vm::onSpotTapped,
                onTuneIn = { spot -> spot.toTuneInSpot()?.let(tuneIn::requestTuneIn) },
            )
        }
        tuneState.error?.let { TuneInErrorRow(it, onDismiss = tuneIn::dismissError) }
        if (tuneState.phase != TuneInPhase.IDLE) {
            TuneInBar(tuneState, onToggleMute = tuneIn::toggleMute, onStop = tuneIn::stop)
        }
        if (tuneState.pendingSpot != null) {
            TuneInStrategyDialog(
                onPick = tuneIn::tuneIn,
                onDismiss = tuneIn::dismissStrategyPicker,
            )
        }
        QuickEntryCommandBar(
            tokens = ui.tokens,
            callsign = ui.callsign,
            dupeStatus = ui.dupeStatus,
            suggestions = ui.suggestions,
            canLog = ui.parsed != null,
            isLogging = ui.isLogging,
            error = ui.error,
            sessionMeta = ui.sessionMeta,
            onChanged = vm::onCommandChange,
            onLog = vm::onLog,
            onApplyMeta = vm::applySessionMetadata,
        )
    }

    ui.editingQso?.let { qso ->
        QsoEditSheet(
            qso = qso,
            onSave = vm::updateQso,
            onDelete = vm::deleteQso,
            onDismiss = vm::dismissEditor,
        )
    }

    // "Already worked today" confirmation before the log sheet (iOS parity).
    ui.spotDupePrompt?.let { spot ->
        AlertDialog(
            onDismissRequest = vm::dismissSpotDupe,
            title = { Text("Duplicate QSO") },
            text = {
                Text("You already worked ${spot.callsign} on ${spot.band ?: "this band"} today.")
            },
            confirmButton = {
                TextButton(onClick = vm::confirmSpotDupe) { Text("Log Anyway") }
            },
            dismissButton = {
                TextButton(onClick = vm::dismissSpotDupe) { Text("Cancel") }
            },
        )
    }

    ui.spotSheet?.let { spot ->
        SpotLogSheet(
            spot = spot,
            myCallsign = active.myCallsign,
            logName = active.name,
            isLogging = ui.isLogging,
            error = ui.error,
            onLog = { form ->
                vm.logSpotQso(form) {
                    // Mirror iOS: after logging a POTA hunt, offer a respot to
                    // help other hunters — through the existing explicit-confirm
                    // respot flow (CAR-288), never an unprompted post.
                    spotsVm.requestRespot(spot, UserProfile.callsign(context))
                }
            },
            onDismiss = vm::dismissSpotSheet,
        )
    }
}

// ── Start prompt (no active log) ────────────────────────────────

@Composable
private fun StartLogPrompt(modifier: Modifier, onStart: (String) -> Unit) {
    var name by rememberSaveable { mutableStateOf("") }
    Column(
        modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            "No active hunter log",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            "Start a chasing session to log spots with worked-before dedup.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(20.dp))
        OutlinedTextField(
            value = name,
            onValueChange = { name = it },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            placeholder = { Text("Log name (e.g. Saturday hunt)") },
        )
        Spacer(Modifier.height(12.dp))
        Button(
            onClick = { onStart(name) },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Start hunter log")
        }
    }
}

// ── Today header ────────────────────────────────────────────────

@Composable
private fun TodayHeader(
    name: String,
    today: FfiTodayStats,
    recent: List<FfiQso>,
    expanded: Boolean,
    onToggleExpanded: () -> Unit,
    onEditQso: (FfiQso) -> Unit,
) {
    Card(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .clickable(onClick = onToggleExpanded),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(Modifier.padding(14.dp)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        "${today.qsoCount} today",
                        style = MaterialTheme.typography.labelLarge,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Icon(
                        Icons.Filled.KeyboardArrowDown,
                        contentDescription = if (expanded) "Hide today's QSOs" else "Show today's QSOs",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(20.dp).rotate(if (expanded) 180f else 0f),
                    )
                }
            }
            if (today.bands.isNotEmpty() || today.modes.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    items(today.bands, key = { "b-$it" }) { MetaChip(it, MaterialTheme.colorScheme.tertiary) }
                    items(today.modes, key = { "m-$it" }) { MetaChip(it, MaterialTheme.colorScheme.secondary) }
                }
            }
            if (expanded) {
                Spacer(Modifier.height(10.dp))
                HorizontalDivider(
                    thickness = 0.5.dp,
                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                )
                if (recent.isEmpty()) {
                    Text(
                        "No QSOs logged today",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                        textAlign = TextAlign.Center,
                    )
                } else {
                    Column {
                        recent.forEach { qso ->
                            RecentQsoRow(qso, onClick = { onEditQso(qso) })
                        }
                    }
                }
            }
        }
    }
}

/** One tappable row in the expanded "today" list: time · call · band/mode · RST. */
@Composable
private fun RecentQsoRow(qso: FfiQso, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            formatTime(qso.qsoDate),
            style = MaterialTheme.typography.bodySmall,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            qso.callsign,
            style = MaterialTheme.typography.bodyMedium,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.weight(1f))
        val bandMode = listOfNotNull(qso.band, qso.mode).joinToString(" ")
        if (bandMode.isNotEmpty()) {
            Surface(
                shape = RoundedCornerShape(6.dp),
                color = MaterialTheme.colorScheme.secondary.copy(alpha = 0.14f),
            ) {
                Text(
                    bandMode,
                    Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                    style = MaterialTheme.typography.labelMedium,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.secondary,
                )
            }
        }
        Text(
            qso.rstSent ?: "599",
            style = MaterialTheme.typography.labelSmall,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
        )
    }
}

@Composable
private fun MetaChip(text: String, color: Color) {
    Surface(
        shape = RoundedCornerShape(6.dp),
        color = color.copy(alpha = 0.14f),
        border = BorderStroke(0.5.dp, color.copy(alpha = 0.4f)),
    ) {
        Text(
            text,
            Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            style = MaterialTheme.typography.labelMedium,
            fontFamily = FontFamily.Monospace,
            color = color,
        )
    }
}
