package app.carrierwave.android.ui.sessions

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import app.carrierwave.android.data.SpotEngineProvider
import app.carrierwave.android.ui.common.cwMessage
import app.carrierwave.android.ui.common.scpSuggestions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.CwException
import uniffi.cw_ffi.FfiCommandContext
import uniffi.cw_ffi.FfiCommandOutcome
import uniffi.cw_ffi.FfiCommandPanel
import uniffi.cw_ffi.FfiDuplicateStatus
import uniffi.cw_ffi.FfiLoggerCommand
import uniffi.cw_ffi.FfiLoggerFormConfig
import uniffi.cw_ffi.FfiLoggingSession
import uniffi.cw_ffi.FfiLoggingSessionFilter
import uniffi.cw_ffi.FfiQso
import uniffi.cw_ffi.FfiQuickEntry
import uniffi.cw_ffi.FfiQuickToken
import uniffi.cw_ffi.FfiQuickTokenType
import uniffi.cw_ffi.FfiRstOrder
import uniffi.cw_ffi.FfiSessionLogInput
import uniffi.cw_ffi.FfiSessionMetadataEntry
import uniffi.cw_ffi.FieldStore
import uniffi.cw_ffi.LoggerCommandApi
import uniffi.cw_ffi.ScpApi
import uniffi.cw_ffi.SessionApi
import uniffi.cw_ffi.bandDerive
import uniffi.cw_ffi.hunterExtractPrimary
import uniffi.cw_ffi.parseLoggerCommand
import uniffi.cw_ffi.parseQuickEntry
import uniffi.cw_ffi.parseQuickEntryTokens
import uniffi.cw_ffi.quickEntryIsCallsign
import java.time.LocalDate
import java.time.ZoneOffset

/** UI state for the activation logger — the live QSO-entry surface shown while a
 * session is active. Entry is the shared quick-entry command bar (parsed by the
 * Rust grammar), matching the hunter log. */
data class LoggerUiState(
    val loaded: Boolean = false,
    val session: FfiLoggingSession? = null,
    val config: FfiLoggerFormConfig? = null,
    val recent: List<FfiQso> = emptyList(),
    /** Paused, resumable sessions (newest first) — shown on the idle prompt when
     *  no session is active, so a paused session isn't stranded. */
    val resumable: List<FfiLoggingSession> = emptyList(),
    /** Completed sessions (newest first, bounded) — the idle prompt's history
     *  list; tapping one opens the session detail for post-session editing. */
    val completed: List<FfiLoggingSession> = emptyList(),
    /** QSO currently open in the inline editor sheet (null = sheet closed). */
    val editingQso: FfiQso? = null,
    // Quick-entry command bar (shared Rust grammar via UniFFI, identical to iOS).
    val tokens: List<FfiQuickToken> = emptyList(),
    val parsed: FfiQuickEntry? = null,
    /** The current input parsed as a logger command (FREQ/MODE/SPOT/…), if any. */
    val command: FfiLoggerCommand? = null,
    val callsign: String? = null,
    /** Day-scoped duplicate status for the parsed contact (null while unknown). */
    val dupeStatus: FfiDuplicateStatus? = null,
    /** SCP (MASTER.SCP) suggestions for a lone partial callsign fragment. */
    val suggestions: List<String> = emptyList(),
    val isLogging: Boolean = false,
    val error: String? = null,
    /** Callsign-less field line ("14.046 CW") — the send button applies it as defaults. */
    val sessionMeta: FfiSessionMetadataEntry? = null,
    /** Defaults for QSOs logged from now on, when the entry omits freq/mode. */
    val defaultFrequency: Double? = null,
    val defaultMode: String? = null,
    /** One-shot confirmation after applying session metadata (shown as a toast). */
    val notice: String? = null,
    /** True while the HUNT command's activator-spots browser is presented. */
    val showHunt: Boolean = false,
    /** True while a repeating self-spot timer (SPOT REPEAT) is running. */
    val repeatingSpot: Boolean = false,
    /** Flipped true once the session ends, so the container can leave the logger. */
    val ended: Boolean = false,
)

/**
 * Drives the activation logger through the shared Rust [SessionApi] — the same
 * kernel iOS runs. The active session is [SessionApi.currentSession]; form config
 * (band/mode/POTA flags) [SessionApi.loggerFormConfig]; duplicate status the
 * activator-scoped [FieldStore.activationDuplicateStatus]; QSOs are logged with
 * [SessionApi.logQso], which owns band derivation, session-field stamping, RST
 * defaults, and the notes merge. This view model only parses the command bar and
 * marshals store-touching calls onto [Dispatchers.IO].
 */
class LoggerViewModel(
    private val api: SessionApi,
    private val commandApi: LoggerCommandApi,
    private val store: FieldStore,
    private val scpApi: ScpApi,
    private val spotEngine: SpotEngineProvider,
) : ViewModel() {

    private val _ui = MutableStateFlow(LoggerUiState())
    val ui: StateFlow<LoggerUiState> = _ui.asStateFlow()

    /** The active repeating-spot loop (SPOT REPEAT), cancelled by SPOT STOP. */
    private var repeatSpotJob: Job? = null

    init {
        refresh()
    }

    /** Reload the current session, its form config, and the running QSO list. */
    fun refresh() = viewModelScope.launch { reload() }

    /** Resume a paused session (reactivates it, pausing any other active one),
     * then reload so [SessionsContainerScreen] swaps back to the live logger. */
    fun resumeSession(id: String) = viewModelScope.launch {
        withContext(Dispatchers.IO) { runCatching { api.resumeSession(id) } }
        reload()
    }

    private suspend fun reload() {
        val snapshot = withContext(Dispatchers.IO) {
            val session = api.currentSession()
            val config = session?.let { api.loggerFormConfig(it.id) }
            val recent = session?.let { api.sessionQsos(it.id, RECENT_LIMIT) } ?: emptyList()
            // Only needed for the idle prompt, so skip the scan when a session is live.
            val idle = if (session == null) idleSessions() else IdleSessions(emptyList(), emptyList())
            Snapshot(session, config, recent, idle.paused, idle.completed)
        }
        _ui.update {
            it.copy(
                loaded = true,
                session = snapshot.session,
                config = snapshot.config,
                recent = snapshot.recent,
                resumable = snapshot.resumable,
                completed = snapshot.completed,
            )
        }
    }

    /** Paused + completed sessions (newest first, bounded) for the idle prompt. */
    private fun idleSessions(): IdleSessions =
        runCatching {
            val all = store.fetchLoggingSessions(FfiLoggingSessionFilter(null, null, null), SESSION_LIST_LIMIT, 0L)
                .sortedByDescending { it.startedAt }
            IdleSessions(
                paused = all.filter { it.statusRawValue == "paused" },
                completed = all.filter { it.statusRawValue == "completed" },
            )
        }.getOrDefault(IdleSessions(emptyList(), emptyList()))

    // ── Quick-entry command bar ─────────────────────────────────
    fun onCommandChange(text: String) {
        // A command (FREQ/MODE/SPOT/RBN/NOTE/… + the callsign-less field line)
        // short-circuits the QSO parse — the shared Rust grammar decides, and the
        // shared handler runs it on send. iOS parity.
        val command = parseLoggerCommand(text)
        if (command != null) {
            _ui.update {
                it.copy(
                    command = command,
                    tokens = parseQuickEntryTokens(text, FfiRstOrder.RECEIVED_FIRST),
                    parsed = null,
                    callsign = null,
                    dupeStatus = null,
                    suggestions = emptyList(),
                    sessionMeta = null,
                    error = null,
                )
            }
            return
        }
        var tokens = parseQuickEntryTokens(text, FfiRstOrder.RECEIVED_FIRST)
        var parsed = parseQuickEntry(text, FfiRstOrder.RECEIVED_FIRST)
        if (parsed == null) {
            val lone = text.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
                .singleOrNull()?.uppercase()?.takeIf { quickEntryIsCallsign(it) }
            if (lone != null) {
                parsed = callsignOnlyEntry(lone)
                tokens = listOf(FfiQuickToken(0u, lone, FfiQuickTokenType.CALLSIGN))
            }
        }
        val entry = parsed
        _ui.update {
            it.copy(
                command = null,
                tokens = tokens,
                parsed = parsed,
                callsign = parsed?.callsign,
                dupeStatus = null,
                suggestions = scpSuggestions(text, scpApi),
                error = null,
                sessionMeta = null,
            )
        }
        if (entry != null) computeDupeStatus(entry)
    }

    /** Apply the pending callsign-less field line as defaults for future QSOs. */
    fun applySessionMetadata() {
        val meta = _ui.value.sessionMeta ?: return
        val applied = buildList {
            meta.frequency?.let { add("%.3f MHz".format(it) + (meta.band?.let { band -> " ($band)" } ?: "")) }
            meta.mode?.let { add(it) }
        }
        val notice = if (applied.isEmpty()) null else "Set for future QSOs: ${applied.joinToString(" · ")}"
        _ui.update {
            it.copy(
                defaultFrequency = meta.frequency ?: it.defaultFrequency,
                defaultMode = meta.mode ?: it.defaultMode,
                sessionMeta = null,
                tokens = emptyList(),
                notice = notice,
            )
        }
    }

    fun consumeNotice() = _ui.update { it.copy(notice = null) }

    /** Classify whether logging [entry] now would dupe a contact already worked
     * today at this activation's park/band/mode — the activator-scoped dupe. */
    private fun computeDupeStatus(entry: FfiQuickEntry) = viewModelScope.launch {
        val session = _ui.value.session ?: return@launch
        val status = withContext(Dispatchers.IO) {
            runCatching {
                store.activationDuplicateStatus(
                    callsign = hunterExtractPrimary(entry.callsign),
                    band = bandOf(entry),
                    mode = modeOf(entry),
                    myPark = session.parkReference,
                    isPota = _ui.value.config?.isPota ?: false,
                    dayStart = utcDayStartSecs(),
                )
            }.getOrNull()
        }
        // Drop a stale result if the parse changed while we were off-thread.
        _ui.update { if (it.parsed === entry) it.copy(dupeStatus = status) else it }
    }

    /** Log the parsed contact — or, when the input is a command, run it through
     * the shared Rust handler. */
    fun onLog(onSuccess: () -> Unit) = viewModelScope.launch {
        _ui.value.command?.let { command ->
            handleCommand(command, onSuccess)
            return@launch
        }
        val parsed = _ui.value.parsed ?: return@launch
        val session = _ui.value.session ?: return@launch
        _ui.update { it.copy(isLogging = true, error = null) }
        val result = withContext(Dispatchers.IO) {
            try {
                Result.success(api.logQso(inputFor(parsed, session.id)))
            } catch (e: CwException) {
                Result.failure(e)
            }
        }
        result
            .onSuccess {
                _ui.update {
                    it.copy(
                        isLogging = false,
                        tokens = emptyList(),
                        parsed = null,
                        callsign = null,
                        dupeStatus = null,
                        suggestions = emptyList(),
                    )
                }
                onSuccess()
                refresh()
            }
            .onFailure { err -> _ui.update { it.copy(isLogging = false, error = err.cwMessage()) } }
    }

    /** Run a logger command through the shared Rust [LoggerCommandApi]. State
     * commands (FREQ/MODE/NOTE/MYCALL/session-metadata) and the one-off HUNT log
     * execute here; spot + panel commands come back as intents the host runs:
     * SPOT posts a self-spot through the shared spot engine, and HUNT opens the
     * activator-spots browser. */
    private suspend fun handleCommand(command: FfiLoggerCommand, onSuccess: () -> Unit) {
        val session = _ui.value.session ?: return
        _ui.update { it.copy(isLogging = true, error = null) }
        // Android doesn't drive live radio spotting yet, so those prompts are off.
        val ctx = FfiCommandContext(potaQsySpotEnabled = false, potaAutoSpotEnabled = false)
        val outcome = withContext(Dispatchers.IO) {
            runCatching { commandApi.handle(session.id, command, ctx) }.getOrNull()
        }
        val notice: String? = when (outcome) {
            is FfiCommandOutcome.SessionUpdated -> outcome.notice
            is FfiCommandOutcome.LogQso -> {
                withContext(Dispatchers.IO) { runCatching { api.logQso(outcome.input) } }
                "Logged ${outcome.input.callsign}"
            }
            is FfiCommandOutcome.Message -> outcome.text
            is FfiCommandOutcome.Present -> presentPanel(outcome.panel)
            is FfiCommandOutcome.PostSpot -> postSelfSpot(outcome.comment)
            is FfiCommandOutcome.StartRepeatSpot -> {
                startRepeatSpot(outcome.comment, outcome.intervalMinutes)
                "Repeating spot every ${outcome.intervalMinutes} min"
            }
            is FfiCommandOutcome.StopRepeatSpot -> {
                stopRepeatSpot()
                "Stopped repeating spot"
            }
            null -> "Command failed"
        }
        _ui.update { it.copy(isLogging = false, command = null, tokens = emptyList(), notice = notice) }
        onSuccess()
        refresh()
    }

    /** Map a command panel to a host action. HUNT opens the activator-spots
     * browser (its own bottom sheet); the rest have no Android surface yet. */
    private fun presentPanel(panel: FfiCommandPanel): String? = when (panel) {
        is FfiCommandPanel.Hunt -> {
            _ui.update { it.copy(showHunt = true) }
            null
        }
        else -> "${panelLabel(panel)} isn't available on Android yet"
    }

    /** Dismiss the HUNT activator-spots browser. */
    fun dismissHunt() = _ui.update { it.copy(showHunt = false) }

    /** Post a POTA self-spot for the active session through the shared spot
     * engine (activator = station callsign). Fans out across every park in an
     * n-fer reference. The Rust handler already validated freq/park/callsign;
     * this only carries out the network post. Returns the toast text.
     *
     * SOTA sessions reach here too (the handler allows them), but the Android
     * spot engine only exposes POTA posting — those get a "not supported" note. */
    private suspend fun postSelfSpot(comment: String?): String {
        val session = _ui.value.session ?: return "Start a session first"
        if (_ui.value.config?.isPota != true) {
            return "SOTA spotting isn't supported on Android yet"
        }
        val parkRef = session.parkReference?.takeIf { it.isNotBlank() }
            ?: return "POTA spot needs a park reference"
        val freqKhz = (session.frequency ?: return "SPOT requires a frequency") * 1_000.0
        val activator = session.stationCallsign?.takeIf { it.isNotBlank() } ?: session.myCallsign
        if (activator.isBlank()) return "No callsign configured"
        val engine = spotEngine.engine() ?: return "Spot engine unavailable"
        // Park references are comma-separated for n-fers (matches Rust park_reference::split).
        val parks = parkRef.split(',').map { it.trim().uppercase() }.filter { it.isNotEmpty() }
        val posted = mutableListOf<String>()
        val failed = mutableListOf<String>()
        withContext(Dispatchers.IO) {
            for (park in parks) {
                runCatching { engine.potaRespot(activator, park, freqKhz, session.mode, comment) }
                    .onSuccess { posted.add(park) }
                    .onFailure { failed.add(park) }
            }
        }
        return when {
            posted.isEmpty() -> "Spot failed"
            failed.isEmpty() -> "Spotted ${posted.joinToString(", ")}"
            else -> "Spotted ${posted.joinToString(", ")} (failed: ${failed.joinToString(", ")})"
        }
    }

    /** Start the repeating self-spot loop: post immediately, then every
     * [intervalMinutes]. Replaces any prior loop. Cancelled by SPOT STOP. */
    private fun startRepeatSpot(comment: String?, intervalMinutes: Int) {
        repeatSpotJob?.cancel()
        _ui.update { it.copy(repeatingSpot = true) }
        repeatSpotJob = viewModelScope.launch {
            while (isActive) {
                val notice = postSelfSpot(comment)
                _ui.update { it.copy(notice = notice) }
                delay(intervalMinutes.toLong() * 60_000L)
            }
        }
    }

    /** Stop the repeating self-spot loop. */
    private fun stopRepeatSpot() {
        repeatSpotJob?.cancel()
        repeatSpotJob = null
        _ui.update { it.copy(repeatingSpot = false) }
    }

    override fun onCleared() {
        repeatSpotJob?.cancel()
        super.onCleared()
    }

    private fun panelLabel(panel: FfiCommandPanel): String = when (panel) {
        is FfiCommandPanel.Rbn -> "RBN"
        is FfiCommandPanel.Hunt -> "Hunt"
        is FfiCommandPanel.P2p -> "P2P"
        is FfiCommandPanel.S2s -> "S2S"
        is FfiCommandPanel.Solar -> "Solar"
        is FfiCommandPanel.Weather -> "Weather"
        is FfiCommandPanel.Map -> "Map"
        is FfiCommandPanel.Hidden -> "Hidden QSOs"
        is FfiCommandPanel.Help -> "Help"
        is FfiCommandPanel.Manual -> "Manual"
        is FfiCommandPanel.Checklist -> "Checklist"
        is FfiCommandPanel.Radio -> "Radio"
        is FfiCommandPanel.Websdr -> "WebSDR"
        is FfiCommandPanel.Band -> "Band picker"
        is FfiCommandPanel.Rig -> "Rig"
        is FfiCommandPanel.Replay -> "Replay"
    }

    /** Pause the active session (leaves it resumable); the container leaves the logger. */
    fun pauseSession(onDone: () -> Unit) = viewModelScope.launch {
        val session = _ui.value.session ?: return@launch
        stopRepeatSpot()
        withContext(Dispatchers.IO) { runCatching { api.pauseSession(session.id) } }
        onDone()
    }

    /** End the active session (marks it completed); the container leaves the logger. */
    fun endSession(onDone: () -> Unit) = viewModelScope.launch {
        val session = _ui.value.session ?: return@launch
        stopRepeatSpot()
        withContext(Dispatchers.IO) { runCatching { api.endSession(session.id) } }
        _ui.update { it.copy(ended = true) }
        onDone()
    }

    private fun inputFor(entry: FfiQuickEntry, sessionId: String) = FfiSessionLogInput(
        sessionId = sessionId,
        callsign = entry.callsign,
        // Blank -> Rust fills the mode default (default_rst).
        rstSent = entry.rstSent ?: "",
        rstReceived = entry.rstReceived ?: "",
        theirGrid = entry.theirGrid,
        theirPark = entry.theirPark,
        notes = entry.notes,
        name = null,
        qth = null,
        state = entry.state,
        country = null,
        theirLicenseClass = null,
        aoaCode = null,
        callsignChangeNote = null,
        frequencyOverrideMhz = entry.frequency ?: _ui.value.defaultFrequency,
        modeOverride = entry.mode ?: _ui.value.defaultMode,
        timestampOverride = null,
        contestName = null,
        contestSerialSent = null,
        contestSerialReceived = null,
        contestExchangeSent = null,
        contestExchangeReceived = null,
        // Android has no upload pipeline wired yet; the QSO still logs + enriches.
        uploadQrz = false,
        uploadPota = false,
        uploadLofi = false,
        uploadClublog = false,
    )

    private fun bandOf(entry: FfiQuickEntry): String =
        entry.band
            ?: (entry.frequency ?: _ui.value.defaultFrequency)?.let { bandDerive(it * 1_000.0) }
            ?: _ui.value.config?.band
            ?: "Unknown"

    private fun modeOf(entry: FfiQuickEntry): String =
        entry.mode ?: _ui.value.defaultMode ?: _ui.value.config?.mode ?: "SSB"

    private fun callsignOnlyEntry(callsign: String): FfiQuickEntry = FfiQuickEntry(
        callsign = callsign,
        rstSent = null,
        rstReceived = null,
        state = null,
        theirPark = null,
        theirGrid = null,
        frequency = null,
        band = null,
        mode = null,
        notes = null,
        rstConflicts = emptyList(),
        zuluTime = null,
    )

    // ── Inline QSO editing (iOS LoggerQSOEditSheet parity) ──────
    /** Open a logged QSO in the editor sheet. */
    fun editQso(qso: FfiQso) = _ui.update { it.copy(editingQso = qso, error = null) }

    /** Dismiss the editor sheet without saving. */
    fun dismissEditor() = _ui.update { it.copy(editingQso = null) }

    /** Persist edits to a session QSO via the shared store, then reload. */
    fun updateQso(qso: FfiQso) = viewModelScope.launch {
        val result = withContext(Dispatchers.IO) {
            try {
                store.upsertQso(qso.copy(modifiedAt = nowSecs(), dirty = true))
                Result.success(Unit)
            } catch (e: CwException) {
                Result.failure(e)
            }
        }
        result
            .onSuccess {
                _ui.update { it.copy(editingQso = null) }
                reload()
            }
            .onFailure { err -> _ui.update { it.copy(error = err.cwMessage()) } }
    }

    /**
     * Delete a session QSO. Sync-safe soft delete (`isHidden` + `dirty` upsert,
     * never the hard `deleteQso`), and decrements the session's QSO count —
     * mirrors iOS `LoggingSessionManager.hideQSO`.
     */
    fun deleteQso(qso: FfiQso) = viewModelScope.launch {
        val result = withContext(Dispatchers.IO) {
            try {
                store.upsertQso(qso.copy(isHidden = true, modifiedAt = nowSecs(), dirty = true))
                qso.loggingSessionId?.let { sessionId ->
                    store.fetchLoggingSession(sessionId)?.let { session ->
                        store.upsertLoggingSession(
                            session.copy(
                                qsoCount = (session.qsoCount - 1).coerceAtLeast(0L),
                                cloudDirtyFlag = true,
                            ),
                        )
                    }
                }
                Result.success(Unit)
            } catch (e: CwException) {
                Result.failure(e)
            }
        }
        result
            .onSuccess {
                _ui.update { it.copy(editingQso = null) }
                reload()
            }
            .onFailure { err -> _ui.update { it.copy(error = err.cwMessage()) } }
    }

    private data class IdleSessions(
        val paused: List<FfiLoggingSession>,
        val completed: List<FfiLoggingSession>,
    )

    private data class Snapshot(
        val session: FfiLoggingSession?,
        val config: FfiLoggerFormConfig?,
        val recent: List<FfiQso>,
        val resumable: List<FfiLoggingSession>,
        val completed: List<FfiLoggingSession>,
    )

    companion object {
        private const val RECENT_LIMIT = 50L
        private const val SESSION_LIST_LIMIT = 50L

        /** UTC start-of-day epoch seconds — the dupe-status "today" window. */
        private fun utcDayStartSecs(): Long =
            LocalDate.now(ZoneOffset.UTC).atStartOfDay(ZoneOffset.UTC).toEpochSecond()

        /** Current Unix seconds — the cw-store contract for modified_at. */
        private fun nowSecs(): Long = System.currentTimeMillis() / 1_000L

        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                LoggerViewModel(app.sessionApi, app.loggerCommandApi, app.store, app.scpApi, app.spotEngine)
            }
        }
    }
}
