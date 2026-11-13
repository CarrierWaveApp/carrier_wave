package app.carrierwave.android.ui.hunter

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import app.carrierwave.android.ui.common.cwMessage
import app.carrierwave.android.ui.common.scpSuggestions
import app.carrierwave.android.ui.spots.Spot
import app.carrierwave.android.ui.spots.SpotSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.ActivityLogApi
import uniffi.cw_ffi.CwException
import uniffi.cw_ffi.FfiActivityLog
import uniffi.cw_ffi.FfiDuplicateStatus
import uniffi.cw_ffi.FfiLogQsoInput
import uniffi.cw_ffi.FfiQso
import uniffi.cw_ffi.FfiQuickEntry
import uniffi.cw_ffi.FfiQuickToken
import uniffi.cw_ffi.FfiQuickTokenType
import uniffi.cw_ffi.FfiRstOrder
import uniffi.cw_ffi.FfiSessionMetadataEntry
import uniffi.cw_ffi.FfiTodayStats
import uniffi.cw_ffi.FieldStore
import uniffi.cw_ffi.ScpApi
import uniffi.cw_ffi.bandDerive
import uniffi.cw_ffi.hunterExtractPrimary
import uniffi.cw_ffi.parseQuickEntry
import uniffi.cw_ffi.parseQuickEntrySessionMetadata
import uniffi.cw_ffi.parseQuickEntryTokens
import uniffi.cw_ffi.quickEntryIsCallsign
import java.time.LocalDate
import java.time.ZoneOffset

/** UI state for the hunter ("chaser") log — the single-active-log workflow. */
data class HunterUiState(
    val loaded: Boolean = false,
    val activeLog: FfiActivityLog? = null,
    val today: FfiTodayStats = FfiTodayStats(0L, emptyList(), emptyList()),
    val recent: List<FfiQso> = emptyList(),
    // Quick-entry command bar (shared Rust grammar via UniFFI, identical to iOS).
    val tokens: List<FfiQuickToken> = emptyList(),
    val parsed: FfiQuickEntry? = null,
    val callsign: String? = null,
    /** Day-scoped duplicate status for the parsed contact (null while unknown). */
    val dupeStatus: FfiDuplicateStatus? = null,
    /** SCP (MASTER.SCP) suggestions for a lone partial callsign fragment. */
    val suggestions: List<String> = emptyList(),
    val isLogging: Boolean = false,
    val error: String? = null,
    /** Set once when a logged QSO makes today's count hit the daily goal. */
    val goalReached: Boolean = false,
    /** Callsign-less field line ("14.046 CW") — the send button applies it as defaults. */
    val sessionMeta: FfiSessionMetadataEntry? = null,
    /** Defaults for QSOs logged from now on, when the entry omits freq/mode. */
    val defaultFrequency: Double? = null,
    val defaultMode: String? = null,
    /** One-shot confirmation after applying session metadata (shown as a toast). */
    val notice: String? = null,
    /** QSO currently open in the inline editor sheet (null = sheet closed). */
    val editingQso: FfiQso? = null,
    /** Spot open in the log-from-spot sheet (null = closed) — iOS `SpotLogSheet`. */
    val spotSheet: Spot? = null,
    /** Spot awaiting the "Duplicate QSO — log anyway?" confirmation. */
    val spotDupePrompt: Spot? = null,
)

/**
 * Drives the hunter log entirely through the shared Rust [ActivityLogApi] — the
 * same logic the iOS `ActivityLogManager` runs. The active log, today stats, and
 * recent QSOs come from Rust; duplicate status is the shared
 * [FieldStore.duplicateStatus] port of iOS `classifyDuplicateStatus`. This view
 * model only parses the command bar and marshals calls onto [Dispatchers.IO].
 */
class HunterLogViewModel(
    private val api: ActivityLogApi,
    private val store: FieldStore,
    private val scpApi: ScpApi,
    private val myCallsign: String,
    val homeGrid: String,
) : ViewModel() {

    private val _ui = MutableStateFlow(HunterUiState())
    val ui: StateFlow<HunterUiState> = _ui.asStateFlow()

    init {
        refresh()
    }

    fun refresh() = viewModelScope.launch {
        val snapshot = withContext(Dispatchers.IO) {
            val log = api.activeLog()
            val today = log?.let { api.todayStats(it.id) } ?: FfiTodayStats(0L, emptyList(), emptyList())
            val recent = log?.let { api.recentQsos(it.id, RECENT_LIMIT) } ?: emptyList()
            Snapshot(log, today, recent)
        }
        _ui.update {
            it.copy(
                loaded = true,
                activeLog = snapshot.log,
                today = snapshot.today,
                recent = snapshot.recent,
            )
        }
    }

    /** Start (and activate) a new hunter log; deactivates any previous one. */
    fun createLog(name: String) = viewModelScope.launch {
        val clean = name.trim().ifEmpty { "Hunter Log" }
        withContext(Dispatchers.IO) {
            api.createLog(clean, myCallsign, null, homeGrid)
        }
        refresh()
    }

    // ── Quick-entry command bar ─────────────────────────────────
    fun onCommandChange(text: String) {
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
        // A callsign-less field line ("14.046 CW") sets defaults for future
        // QSOs instead of logging one — same shared-grammar rule as iOS.
        val sessionMeta = if (parsed == null) parseQuickEntrySessionMetadata(text) else null
        val entry = parsed
        _ui.update {
            it.copy(
                tokens = tokens,
                parsed = parsed,
                callsign = parsed?.callsign,
                dupeStatus = null,
                suggestions = scpSuggestions(text, scpApi),
                error = null,
                sessionMeta = sessionMeta,
            )
        }
        if (entry != null) computeDupeStatus(entry)
    }

    /**
     * Apply the pending callsign-less field line as defaults for QSOs logged
     * from now on. Fields the hunter log can't take (grid, parks, states, …)
     * are called out in the notice instead of silently dropped.
     */
    fun applySessionMetadata() {
        val meta = _ui.value.sessionMeta ?: return
        val applied = buildList {
            meta.frequency?.let { add("%.3f MHz".format(it) + (meta.band?.let { band -> " ($band)" } ?: "")) }
            meta.mode?.let { add(it) }
        }
        val ignored = buildList {
            meta.grid?.let { add(it) }
            addAll(meta.unsupported)
        }
        val notice = buildString {
            if (applied.isNotEmpty()) append("Set for future QSOs: ${applied.joinToString(" · ")}")
            if (ignored.isNotEmpty()) {
                if (isNotEmpty()) append(" — ")
                append("can't set here: ${ignored.joinToString(", ")}")
            }
        }
        _ui.update {
            it.copy(
                defaultFrequency = meta.frequency ?: it.defaultFrequency,
                defaultMode = meta.mode ?: it.defaultMode,
                sessionMeta = null,
                tokens = emptyList(),
                notice = notice.ifEmpty { null },
            )
        }
    }

    fun consumeNotice() = _ui.update { it.copy(notice = null) }

    /** Classify whether logging [entry] now would dupe a contact worked today. */
    private fun computeDupeStatus(entry: FfiQuickEntry) = viewModelScope.launch {
        val status = withContext(Dispatchers.IO) {
            runCatching {
                store.duplicateStatus(
                    callsign = hunterExtractPrimary(entry.callsign),
                    band = bandOf(entry),
                    mode = modeOf(entry),
                    park = entry.theirPark,
                    isPota = entry.theirPark != null,
                    dayStart = utcDayStartSecs(),
                )
            }.getOrNull()
        }
        // Drop a stale result if the parse changed while we were off-thread.
        _ui.update { if (it.parsed === entry) it.copy(dupeStatus = status) else it }
    }

    /** Log the parsed contact into the active log via the Rust API. */
    fun onLog(onSuccess: () -> Unit) = viewModelScope.launch {
        val parsed = _ui.value.parsed ?: return@launch
        val log = _ui.value.activeLog ?: return@launch
        _ui.update { it.copy(isLogging = true, error = null) }
        val result = withContext(Dispatchers.IO) {
            try {
                Result.success(api.logQso(inputFor(parsed, log.id)))
            } catch (e: CwException) {
                Result.failure(e)
            }
        }
        result
            .onSuccess { logged ->
                _ui.update {
                    it.copy(
                        isLogging = false,
                        tokens = emptyList(),
                        parsed = null,
                        callsign = null,
                        dupeStatus = null,
                        suggestions = emptyList(),
                        today = logged?.today ?: it.today,
                        goalReached = logged?.dailyGoalReached ?: false,
                    )
                }
                onSuccess()
                // Pull the refreshed recent-QSO list.
                _ui.value.activeLog?.let { active ->
                    val recent = withContext(Dispatchers.IO) { api.recentQsos(active.id, RECENT_LIMIT) }
                    _ui.update { it.copy(recent = recent) }
                }
            }
            .onFailure { err -> _ui.update { it.copy(isLogging = false, error = err.cwMessage()) } }
    }

    fun consumeGoalReached() = _ui.update { it.copy(goalReached = false) }

    // ── Log-from-spot sheet (iOS SpotLogSheet flow) ─────────────
    /**
     * Spot tapped in the feed: open the pre-filled log sheet, or ask first when
     * logging it now would dupe a contact already worked today (same call +
     * band/mode/park) — mirrors iOS `handleSpotTap`.
     */
    fun onSpotTapped(spot: Spot) = viewModelScope.launch {
        if (_ui.value.activeLog == null) return@launch
        val status = withContext(Dispatchers.IO) {
            runCatching {
                store.duplicateStatus(
                    callsign = hunterExtractPrimary(spot.callsign),
                    band = spotBand(spot),
                    mode = spotMode(spot),
                    park = spot.reference.takeIf { spot.source == SpotSource.POTA },
                    isPota = spot.source == SpotSource.POTA && spot.reference != null,
                    dayStart = utcDayStartSecs(),
                )
            }.getOrNull()
        }
        _ui.update {
            if (status is FfiDuplicateStatus.DuplicateBand) {
                it.copy(spotDupePrompt = spot)
            } else {
                it.copy(spotSheet = spot, error = null)
            }
        }
    }

    /** "Log Anyway" on the dupe prompt — proceed into the sheet. */
    fun confirmSpotDupe() = _ui.update {
        it.copy(spotSheet = it.spotDupePrompt, spotDupePrompt = null, error = null)
    }

    fun dismissSpotDupe() = _ui.update { it.copy(spotDupePrompt = null) }

    fun dismissSpotSheet() = _ui.update { it.copy(spotSheet = null) }

    /** Log the sheet's contact via the Rust API — the iOS `SpotLogSheet.logQSO` analog. */
    fun logSpotQso(form: SpotLogForm, onSuccess: () -> Unit) = viewModelScope.launch {
        val spot = _ui.value.spotSheet ?: return@launch
        val log = _ui.value.activeLog ?: return@launch
        _ui.update { it.copy(isLogging = true, error = null) }
        val input = FfiLogQsoInput(
            logId = log.id,
            callsign = spot.callsign,
            band = spotBand(spot),
            mode = spotMode(spot),
            frequencyMhz = spot.freqKhz?.div(1_000.0),
            rstSent = form.rstSent,
            rstReceived = form.rstReceived,
            theirGrid = form.theirGrid,
            theirPark = spot.reference.takeIf { spot.source == SpotSource.POTA },
            sotaRef = spot.reference.takeIf { spot.source == SpotSource.SOTA },
            notes = form.notes,
            name = null,
            state = form.state,
            country = null,
            power = null,
            myRig = null,
            stationProfileName = null,
            // Android has no upload pipeline wired yet; the QSO still logs + enriches.
            uploadQrz = false,
            uploadLofi = false,
            uploadClublog = false,
            dailyGoal = 0L,
        )
        val result = withContext(Dispatchers.IO) {
            try {
                Result.success(api.logQso(input))
            } catch (e: CwException) {
                Result.failure(e)
            }
        }
        result
            .onSuccess { logged ->
                _ui.update {
                    it.copy(
                        isLogging = false,
                        spotSheet = null,
                        today = logged?.today ?: it.today,
                        goalReached = logged?.dailyGoalReached ?: false,
                    )
                }
                onSuccess()
                _ui.value.activeLog?.let { active ->
                    val recent = withContext(Dispatchers.IO) { api.recentQsos(active.id, RECENT_LIMIT) }
                    _ui.update { it.copy(recent = recent) }
                }
            }
            .onFailure { err -> _ui.update { it.copy(isLogging = false, error = err.cwMessage()) } }
    }

    /** Band for a spot: explicit, derived from kHz, or "Unknown" (matches [bandOf]). */
    private fun spotBand(spot: Spot): String =
        spot.band ?: spot.freqKhz?.let { bandDerive(it) } ?: "Unknown"

    private fun spotMode(spot: Spot): String = spot.mode.ifBlank { "SSB" }

    // ── Inline QSO editing ──────────────────────────────────────
    /** Open a logged QSO in the editor sheet. */
    fun editQso(qso: FfiQso) = _ui.update { it.copy(editingQso = qso, error = null) }

    /** Dismiss the editor sheet without saving. */
    fun dismissEditor() = _ui.update { it.copy(editingQso = null) }

    /**
     * Persist edits to a logged QSO via the shared store, then refresh today's
     * stats + recent list. Store writes fsync, so they run off the main thread.
     */
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
                refresh()
            }
            .onFailure { err -> _ui.update { it.copy(error = err.cwMessage()) } }
    }

    /**
     * Delete a logged QSO, then refresh today's stats + recent list. Sync-safe
     * soft delete: `isHidden = true` + `dirty = true` via upsert so the journal
     * propagates it — `FieldStore.deleteQso` is a local-only hard delete that
     * other devices would never see (mirrors the iOS `hideQSO` path).
     */
    fun deleteQso(qso: FfiQso) = viewModelScope.launch {
        val result = withContext(Dispatchers.IO) {
            try {
                store.upsertQso(qso.copy(isHidden = true, modifiedAt = nowSecs(), dirty = true))
                Result.success(Unit)
            } catch (e: CwException) {
                Result.failure(e)
            }
        }
        result
            .onSuccess {
                _ui.update { it.copy(editingQso = null) }
                refresh()
            }
            .onFailure { err -> _ui.update { it.copy(error = err.cwMessage()) } }
    }

    private fun inputFor(entry: FfiQuickEntry, logId: String) = FfiLogQsoInput(
        logId = logId,
        callsign = entry.callsign,
        band = bandOf(entry),
        mode = modeOf(entry),
        frequencyMhz = entry.frequency ?: _ui.value.defaultFrequency,
        rstSent = entry.rstSent ?: "599",
        rstReceived = entry.rstReceived ?: "599",
        theirGrid = entry.theirGrid,
        theirPark = entry.theirPark,
        sotaRef = null,
        notes = entry.notes,
        name = null,
        state = entry.state,
        country = null,
        power = null,
        myRig = null,
        stationProfileName = null,
        // Android has no upload pipeline wired yet; the QSO still logs + enriches.
        uploadQrz = false,
        uploadLofi = false,
        uploadClublog = false,
        dailyGoal = 0L,
    )

    private fun bandOf(entry: FfiQuickEntry): String =
        entry.band
            ?: (entry.frequency ?: _ui.value.defaultFrequency)?.let { bandDerive(it * 1_000.0) }
            ?: "Unknown"

    private fun modeOf(entry: FfiQuickEntry): String =
        entry.mode ?: _ui.value.defaultMode ?: "SSB"

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

    private data class Snapshot(
        val log: FfiActivityLog?,
        val today: FfiTodayStats,
        val recent: List<FfiQso>,
    )

    companion object {
        private const val RECENT_LIMIT = 20L

        /** UTC start-of-day epoch seconds — the dupe-status "today" window. */
        private fun utcDayStartSecs(): Long =
            LocalDate.now(ZoneOffset.UTC).atStartOfDay(ZoneOffset.UTC).toEpochSecond()

        /** Current Unix seconds — the cw-store contract for modified_at. */
        private fun nowSecs(): Long = System.currentTimeMillis() / 1_000L

        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                HunterLogViewModel(app.activityLogApi, app.store, app.scpApi, app.userCallsign, app.userHomeGrid)
            }
        }
    }
}
