package app.carrierwave.android.ui.sessions

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.carrierwave.android.ui.common.QsoEditSheet
import app.carrierwave.android.ui.common.QsoSections
import uniffi.cw_ffi.FfiLoggingSession
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

private val DetailDateFmt: DateTimeFormatter =
    DateTimeFormatter.ofPattern("MMM d, yyyy HH:mm").withZone(ZoneOffset.UTC)
private val ChipBlue = Color(0xFF3B82F6)
private val PotaGreen = Color(0xFF22C55E)

/**
 * Post-session detail — the Android analog of iOS `SessionDetailView`. Shows
 * the session summary + its QSO list; QSOs open in the shared [QsoEditSheet];
 * the `⋮` menu carries the iOS detail-menu verbs implemented on Android so
 * far: Edit Info, Reopen Session, Delete Session.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SessionDetailScreen(
    vm: SessionDetailViewModel,
    onBack: () -> Unit,
    onReopened: () -> Unit,
    onReplay: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    var menuOpen by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    val session = ui.session
    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                // This Scaffold is nested inside the app's main Scaffold, whose
                // content padding already clears the status bar. Zero the bar's
                // own insets so it doesn't re-add a status-bar-height gap above
                // the title (CAR-294).
                windowInsets = WindowInsets(0, 0, 0, 0),
                title = {
                    Text(
                        session?.displayTitle() ?: "Session",
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(Icons.Filled.MoreVert, contentDescription = "Session actions")
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text("Edit Info") },
                            onClick = {
                                menuOpen = false
                                vm.openMetadataEdit()
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Reopen Session") },
                            onClick = {
                                menuOpen = false
                                vm.reopenSession(onReopened)
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Delete Session", color = MaterialTheme.colorScheme.error) },
                            onClick = {
                                menuOpen = false
                                confirmDelete = true
                            },
                        )
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            session?.let { SessionSummaryCard(it) }
            SessionMapCard(
                mapApi = vm.mapApi,
                sessionId = vm.sessionId,
                onReplay = { onReplay(vm.sessionId) },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
            )
            Box(Modifier.fillMaxSize()) {
                QsoSections(
                    qsos = ui.qsos,
                    homeGrid = vm.homeGrid,
                    loading = !ui.loaded,
                    emptyText = "No QSOs in this session.",
                    onQsoClick = vm::editQso,
                )
            }
        }
    }

    ui.editingQso?.let { qso ->
        QsoEditSheet(
            qso = qso,
            onSave = vm::updateQso,
            onDelete = vm::deleteQso,
            onDismiss = vm::dismissEditor,
        )
    }

    if (ui.showMetadataEdit && session != null) {
        SessionMetadataEditSheet(
            session = session,
            onSave = vm::saveMetadata,
            onDismiss = vm::dismissMetadataEdit,
        )
    }

    if (confirmDelete && session != null) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete Session") },
            text = {
                Text(
                    "Delete this session and hide its ${session.qsoCount} QSOs? " +
                        "Hidden QSOs no longer appear in the logbook.",
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    vm.deleteSession(onBack)
                }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun SessionSummaryCard(session: FfiLoggingSession) {
    Card(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
        shape = RoundedCornerShape(12.dp),
    ) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
            Text(
                buildString {
                    append(DetailDateFmt.format(Instant.ofEpochSecond(session.startedAt)))
                    session.endedAt?.let { append(" – ${DetailDateFmt.format(Instant.ofEpochSecond(it))}") }
                    append(" UTC")
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                DetailPill(session.myCallsign, ChipBlue, mono = true)
                Spacer(Modifier.padding(3.dp))
                DetailPill("${session.qsoCount} Q", PotaGreen)
                session.reference()?.let {
                    Spacer(Modifier.padding(3.dp))
                    DetailPill(it, PotaGreen, mono = true)
                }
                Spacer(Modifier.padding(3.dp))
                DetailPill(session.mode, ChipBlue)
                session.power?.let {
                    Spacer(Modifier.padding(3.dp))
                    DetailPill("${it}W", ChipBlue, mono = true)
                }
            }
        }
    }
}

@Composable
private fun DetailPill(text: String, tint: Color, mono: Boolean = false) {
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

/** Custom title > primary reference > my callsign — the iOS row-title fallback. */
fun FfiLoggingSession.displayTitle(): String =
    customTitle?.takeIf { it.isNotBlank() }
        ?: reference()
        ?: myCallsign

/** The activation's primary reference (park > summit > mission). */
fun FfiLoggingSession.reference(): String? =
    parkReference?.takeIf { it.isNotBlank() }
        ?: sotaReference?.takeIf { it.isNotBlank() }
        ?: missionReference?.takeIf { it.isNotBlank() }
