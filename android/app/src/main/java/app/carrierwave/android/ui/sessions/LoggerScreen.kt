package app.carrierwave.android.ui.sessions

import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.carrierwave.android.CwApp
import app.carrierwave.android.data.TuneInPhase
import app.carrierwave.android.ui.common.QsoEditSheet
import app.carrierwave.android.ui.common.QuickEntryCommandBar
import app.carrierwave.android.ui.spots.SpotsScreen
import app.carrierwave.android.ui.spots.SpotsViewModel
import app.carrierwave.android.ui.tunein.TuneInBar
import app.carrierwave.android.ui.tunein.TuneInErrorRow
import app.carrierwave.android.ui.tunein.TuneInStrategyDialog
import uniffi.cw_ffi.FfiLoggerFormConfig
import uniffi.cw_ffi.FfiLoggingSession
import uniffi.cw_ffi.FfiModeFamily
import uniffi.cw_ffi.FfiQso
import uniffi.cw_ffi.FfiSpotModeFilter
import uniffi.cw_ffi.modeFamily
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

// iOS uses opacity-tinted semantic colors (blue for radio chips, green for POTA);
// alpha fills read correctly in both light and dark themes.
private val ChipBlue = Color(0xFF3B82F6)
private val PotaGreen = Color(0xFF22C55E)
private val TimeFmt: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm").withZone(ZoneOffset.UTC)

/**
 * The live activation logger — shown by [SessionsContainerScreen] while a session
 * is active. Matches the iOS `LoggerView`: a card session header (monospace title,
 * chip row of my-call/QSO-count/park/band/mode, End·Pause), the running QSO list,
 * and — the only entry surface — the shared quick-entry command bar pinned at the
 * bottom. All logic runs in the shared Rust `SessionApi` via [LoggerViewModel].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoggerScreen(
    vm: LoggerViewModel,
    spotsVm: SpotsViewModel,
    onLeaveLogger: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    val session = ui.session
    if (!ui.loaded || session == null) {
        return
    }

    val context = LocalContext.current
    LaunchedEffect(ui.notice) {
        ui.notice?.let {
            Toast.makeText(context, it, Toast.LENGTH_LONG).show()
            vm.consumeNotice()
        }
    }

    // A spot tapped in the HUNT browser seeds the command bar (cleared once the
    // bar consumes it, so re-tapping the same spot re-fires). Matches the hunter log.
    var spotSeed by rememberSaveable { mutableStateOf<String?>(null) }

    Column(modifier.fillMaxSize()) {
        SessionHeader(
            session = session,
            config = ui.config,
            onPause = { vm.pauseSession(onLeaveLogger) },
            onEnd = { vm.endSession(onLeaveLogger) },
        )
        HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))

        // Running QSO list (session log), newest first — the body between the
        // header and the command bar.
        Column(Modifier.weight(1f).fillMaxWidth()) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    "Session Log",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    "${ui.recent.size} QSOs",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (ui.recent.isEmpty()) {
                Text(
                    "No entries yet",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                    modifier = Modifier.fillMaxWidth().padding(vertical = 20.dp),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
            } else {
                LazyColumn(Modifier.fillMaxSize()) {
                    items(ui.recent, key = { it.id }) { qso ->
                        SessionQsoRow(qso, onClick = { vm.editQso(qso) })
                        HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
                    }
                }
            }
        }

        // The one and only entry surface.
        QuickEntryCommandBar(
            tokens = ui.tokens,
            callsign = ui.callsign,
            dupeStatus = ui.dupeStatus,
            suggestions = ui.suggestions,
            canLog = ui.parsed != null || ui.command != null,
            isLogging = ui.isLogging,
            error = ui.error,
            sessionMeta = ui.sessionMeta,
            onChanged = vm::onCommandChange,
            onLog = vm::onLog,
            onApplyMeta = vm::applySessionMetadata,
            seedText = spotSeed,
            onSeedConsumed = { spotSeed = null },
        )
    }

    // Tap a session-log row to edit it inline — the iOS LoggerQSOEditSheet flow.
    ui.editingQso?.let { qso ->
        QsoEditSheet(
            qso = qso,
            onSave = vm::updateQso,
            onDelete = vm::deleteQso,
            onDismiss = vm::dismissEditor,
        )
    }

    // HUNT command: the live activator-spots browser as a bottom sheet over the
    // logger (iOS presents the equivalent swipe-to-dismiss POTA spots panel).
    // Tapping a spot seeds the command bar and closes the sheet.
    if (ui.showHunt) {
        val tuneIn = (context.applicationContext as CwApp).tuneIn
        val tuneState by tuneIn.state.collectAsStateWithLifecycle()
        // Default the browser to the session's mode family (CW/Phone/Digital);
        // cleared back to ALL when the sheet closes so the Hunter tab is unfiltered.
        DisposableEffect(session.mode) {
            spotsVm.applyModeFilter(spotModeFilterFor(session.mode))
            onDispose { spotsVm.applyModeFilter(FfiSpotModeFilter.ALL) }
        }
        ModalBottomSheet(onDismissRequest = vm::dismissHunt) {
            Column(Modifier.fillMaxHeight(0.92f)) {
                Box(Modifier.weight(1f)) {
                    SpotsScreen(
                        spotsVm,
                        onLogSpot = { spot ->
                            spotSeed = spot.toLoggerCommand()
                            vm.dismissHunt()
                        },
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
            }
        }
    }
}

// ── Session header ──────────────────────────────────────────────

@Composable
private fun SessionHeader(
    session: FfiLoggingSession,
    config: FfiLoggerFormConfig?,
    onPause: () -> Unit,
    onEnd: () -> Unit,
) {
    Card(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
        shape = RoundedCornerShape(12.dp),
    ) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    session.reference() ?: session.myCallsign,
                    style = MaterialTheme.typography.titleMedium,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = onPause) { Text("Pause") }
                Spacer(Modifier.width(4.dp))
                OutlinedButton(
                    onClick = onEnd,
                    colors = androidx.compose.material3.ButtonDefaults.outlinedButtonColors(
                        contentColor = MaterialTheme.colorScheme.error,
                    ),
                ) { Text("End") }
            }
            Spacer(Modifier.height(8.dp))
            // Horizontally scrolling chip row (iOS session-controls bar).
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Pill(session.myCallsign, ChipBlue, mono = true)
                Pill("${session.qsoCount} Q", PotaGreen)
                session.reference()?.takeIf { session.parkReference != null }?.let { Pill(it, PotaGreen, mono = true) }
                config?.band?.let { Pill(it, ChipBlue) }
                Pill(config?.mode ?: session.mode, ChipBlue)
                config?.frequencyMhz?.let { Pill("%.3f".format(it), ChipBlue, mono = true) }
            }
        }
    }
}

/** A capsule chip in the iOS style: a subtle tinted fill with tinted text. */
@Composable
private fun Pill(text: String, tint: Color, mono: Boolean = false) {
    Surface(shape = RoundedCornerShape(50), color = tint.copy(alpha = 0.16f)) {
        Text(
            text,
            Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Medium,
            fontFamily = if (mono) FontFamily.Monospace else FontFamily.Default,
            color = tint,
        )
    }
}

/** Map a session mode (e.g. "CW", "SSB", "FT8") to the spot browser's
 *  mode-family filter via the shared Rust mode taxonomy; other/unknown modes
 *  leave the feed unfiltered (matches iOS `ModeFilter.from(modeName:)`). */
private fun spotModeFilterFor(mode: String): FfiSpotModeFilter = when (modeFamily(mode)) {
    FfiModeFamily.CW -> FfiSpotModeFilter.CW
    FfiModeFamily.PHONE -> FfiSpotModeFilter.PHONE
    FfiModeFamily.DIGITAL -> FfiSpotModeFilter.DIGITAL
    FfiModeFamily.OTHER -> FfiSpotModeFilter.ALL
}

// ── QSO row (iOS LoggerQSORow) ──────────────────────────────────

@Composable
private fun SessionQsoRow(qso: FfiQso, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            TimeFmt.format(Instant.ofEpochSecond(qso.qsoDate)),
            style = MaterialTheme.typography.bodySmall,
            fontFamily = FontFamily.Monospace,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(46.dp),
        )
        Column(Modifier.weight(1f)) {
            Text(
                qso.callsign,
                style = MaterialTheme.typography.bodyLarge,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.SemiBold,
            )
            secondaryLine(qso)?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                )
            }
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(
                buildString {
                    append(qso.freqKhz?.let { "%.3f".format(it / 1_000.0) } ?: qso.band.orEmpty())
                    qso.mode?.let { append("  $it") }
                },
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            val rst = listOfNotNull(qso.rstSent, qso.rstRcvd).joinToString("/")
            if (rst.isNotEmpty()) {
                Text(
                    rst,
                    style = MaterialTheme.typography.labelSmall,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                )
            }
        }
    }
}

/** Name / location / their-park line under the callsign, if any. */
private fun secondaryLine(qso: FfiQso): String? =
    qso.name?.takeIf { it.isNotBlank() }
        ?: qso.theirPark?.takeIf { it.isNotBlank() }?.let { "P2P $it" }
        ?: listOfNotNull(qso.state, qso.country).joinToString(", ").takeIf { it.isNotEmpty() }
