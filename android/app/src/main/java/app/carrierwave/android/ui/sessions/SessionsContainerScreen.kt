package app.carrierwave.android.ui.sessions

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import app.carrierwave.android.ui.spots.SpotsViewModel
import uniffi.cw_ffi.FfiLoggingSession
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

private val HistoryDateFmt: DateTimeFormatter =
    DateTimeFormatter.ofPattern("MMM d, yyyy").withZone(ZoneOffset.UTC)

/**
 * The Sessions tab. Mirrors the iOS `SessionsTabView` swap: when a session is
 * active (Rust `SessionApi.currentSession()` non-null) it shows the live
 * [LoggerScreen]; otherwise it shows a start prompt with paused sessions to
 * resume plus recent completed sessions. Tapping any session opens
 * [SessionDetailScreen] for post-session editing (QSOs, metadata, reopen,
 * delete) — the iOS `SessionsView` → `SessionDetailView` flow.
 */
@Composable
fun SessionsContainerScreen(
    vm: LoggerViewModel,
    spotsVm: SpotsViewModel,
    onStartSession: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    // Re-read the active-session pointer each time the tab is shown (the wizard
    // may have created one while we were elsewhere).
    LaunchedEffect(Unit) { vm.refresh() }

    // Timeline replay overlay, keyed by session id — opened from the session
    // detail's map card, sits "above" the detail screen in the back stack.
    var replaySessionId by rememberSaveable { mutableStateOf<String?>(null) }
    replaySessionId?.let { sessionId ->
        BackHandler { replaySessionId = null }
        val replayVm: TimelineReplayViewModel = viewModel(
            key = "timeline-replay-$sessionId",
            factory = TimelineReplayViewModel.factory(sessionId),
        )
        TimelineReplayScreen(
            vm = replayVm,
            onBack = { replaySessionId = null },
            modifier = modifier,
        )
        return
    }

    // Post-session detail overlay, keyed by session id.
    var detailSessionId by rememberSaveable { mutableStateOf<String?>(null) }
    detailSessionId?.let { sessionId ->
        BackHandler { detailSessionId = null }
        val detailVm: SessionDetailViewModel = viewModel(
            key = "session-detail-$sessionId",
            factory = SessionDetailViewModel.factory(sessionId),
        )
        SessionDetailScreen(
            vm = detailVm,
            onBack = {
                detailSessionId = null
                vm.refresh()
            },
            onReopened = {
                detailSessionId = null
                // The session is active again — refresh flips to the live logger.
                vm.refresh()
            },
            onReplay = { replaySessionId = it },
            modifier = modifier,
        )
        return
    }

    if (ui.loaded && ui.session != null) {
        LoggerScreen(vm, spotsVm, onLeaveLogger = { vm.refresh() }, modifier = modifier)
    } else {
        SessionIdlePrompt(
            resumable = ui.resumable,
            completed = ui.completed,
            onResume = vm::resumeSession,
            onOpenDetail = { detailSessionId = it },
            onStartSession = onStartSession,
            modifier = modifier,
        )
    }
}

@Composable
private fun SessionIdlePrompt(
    resumable: List<FfiLoggingSession>,
    completed: List<FfiLoggingSession>,
    onResume: (String) -> Unit,
    onOpenDetail: (String) -> Unit,
    onStartSession: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            "No active session",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            "Start an activation to log contacts into a session with dupe detection and a running QSO list.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(20.dp))
        Button(
            onClick = onStartSession,
            modifier = Modifier.fillMaxWidth().height(48.dp),
        ) {
            Text("Start Session", fontWeight = FontWeight.SemiBold)
        }

        if (resumable.isNotEmpty()) {
            Spacer(Modifier.height(28.dp))
            SectionHeading("Paused sessions")
            Spacer(Modifier.height(8.dp))
            resumable.forEach { session ->
                SessionHistoryRow(
                    session,
                    onOpen = { onOpenDetail(session.id) },
                    onResume = { onResume(session.id) },
                )
                Spacer(Modifier.height(8.dp))
            }
        }

        if (completed.isNotEmpty()) {
            Spacer(Modifier.height(if (resumable.isEmpty()) 28.dp else 12.dp))
            SectionHeading("Recent sessions")
            Spacer(Modifier.height(8.dp))
            completed.forEach { session ->
                SessionHistoryRow(session, onOpen = { onOpenDetail(session.id) })
                Spacer(Modifier.height(8.dp))
            }
        }
    }
}

@Composable
private fun SectionHeading(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.fillMaxWidth(),
        textAlign = TextAlign.Start,
    )
}

/** One paused/completed session. Tap opens the detail (view + edit); paused
 *  rows also keep their one-tap Resume button. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun SessionHistoryRow(
    session: FfiLoggingSession,
    onOpen: () -> Unit,
    onResume: (() -> Unit)? = null,
) {
    Card(
        onClick = onOpen,
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
            Column(Modifier.weight(1f)) {
                Text(
                    session.displayTitle(),
                    style = MaterialTheme.typography.titleSmall,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    buildString {
                        append(HistoryDateFmt.format(Instant.ofEpochSecond(session.startedAt)))
                        append(" · ${session.qsoCount} QSOs")
                        session.reference()?.let { if (session.displayTitle() != it) append(" · $it") }
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (onResume != null) {
                OutlinedButton(onClick = onResume) { Text("Resume") }
            }
        }
    }
}
