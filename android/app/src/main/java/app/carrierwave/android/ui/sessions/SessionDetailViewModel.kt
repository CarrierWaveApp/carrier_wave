package app.carrierwave.android.ui.sessions

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import app.carrierwave.android.ui.common.cwMessage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.CwException
import uniffi.cw_ffi.FfiLoggingSession
import uniffi.cw_ffi.FfiQso
import uniffi.cw_ffi.FieldStore
import uniffi.cw_ffi.MapApi
import uniffi.cw_ffi.SessionApi

/** UI state for the post-session detail — the Android analog of iOS `SessionDetailView`. */
data class SessionDetailUiState(
    val loaded: Boolean = false,
    val session: FfiLoggingSession? = null,
    val qsos: List<FfiQso> = emptyList(),
    /** QSO currently open in the editor sheet (null = sheet closed). */
    val editingQso: FfiQso? = null,
    /** True while the session-metadata editor sheet is presented. */
    val showMetadataEdit: Boolean = false,
    val error: String? = null,
)

/**
 * Post-session viewing + editing for one session: its QSO list (tap to edit,
 * sync-safe soft delete), session-metadata edits (title/equipment/notes/… via
 * `upsertLoggingSession`), and the lifecycle verbs iOS exposes from the detail
 * menu — Reopen (`SessionApi.reopenSession`) and Delete
 * (`SessionApi.deleteSession`, which soft-hides the session's QSOs in Rust).
 */
class SessionDetailViewModel(
    val sessionId: String,
    private val store: FieldStore,
    private val api: SessionApi,
    val mapApi: MapApi,
    val homeGrid: String,
) : ViewModel() {

    private val _ui = MutableStateFlow(SessionDetailUiState())
    val ui: StateFlow<SessionDetailUiState> = _ui.asStateFlow()

    init {
        refresh()
    }

    fun refresh() = viewModelScope.launch {
        val snapshot = withContext(Dispatchers.IO) {
            runCatching {
                val session = store.fetchLoggingSession(sessionId)
                val qsos = session?.let { api.sessionQsos(it.id, QSO_LIMIT) } ?: emptyList()
                session to qsos
            }
        }
        snapshot
            .onSuccess { (session, qsos) ->
                _ui.update { it.copy(loaded = true, session = session, qsos = qsos) }
            }
            .onFailure { err -> _ui.update { it.copy(loaded = true, error = err.cwMessage()) } }
    }

    // ── QSO editing (shared QsoEditSheet) ───────────────────────
    fun editQso(qso: FfiQso) = _ui.update { it.copy(editingQso = qso, error = null) }

    fun dismissEditor() = _ui.update { it.copy(editingQso = null) }

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

    /** Sync-safe soft delete + session QSO-count decrement (iOS `hideQSO`). */
    fun deleteQso(qso: FfiQso) = viewModelScope.launch {
        val result = withContext(Dispatchers.IO) {
            try {
                store.upsertQso(qso.copy(isHidden = true, modifiedAt = nowSecs(), dirty = true))
                store.fetchLoggingSession(sessionId)?.let { session ->
                    store.upsertLoggingSession(
                        session.copy(
                            qsoCount = (session.qsoCount - 1).coerceAtLeast(0L),
                            cloudDirtyFlag = true,
                        ),
                    )
                }
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

    // ── Session metadata editing (iOS SessionMetadataEditSheet) ─
    fun openMetadataEdit() = _ui.update { it.copy(showMetadataEdit = true) }

    fun dismissMetadataEdit() = _ui.update { it.copy(showMetadataEdit = false) }

    /**
     * Persist an edited session record. When the my-callsign or park reference
     * changed, cascade the new value to every QSO in the session — the same
     * cascade the iOS sheet confirms before committing.
     */
    fun saveMetadata(edited: FfiLoggingSession, cascadeCallsign: Boolean, cascadePark: Boolean) =
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) {
                try {
                    store.upsertLoggingSession(edited.copy(cloudDirtyFlag = true))
                    if (cascadeCallsign || cascadePark) {
                        for (qso in api.sessionQsos(edited.id, QSO_LIMIT)) {
                            var updated = qso
                            if (cascadeCallsign) updated = updated.copy(myCallsign = edited.myCallsign)
                            if (cascadePark) updated = updated.copy(park = edited.parkReference)
                            store.upsertQso(updated.copy(modifiedAt = nowSecs(), dirty = true))
                        }
                    }
                    Result.success(Unit)
                } catch (e: CwException) {
                    Result.failure(e)
                }
            }
            result
                .onSuccess {
                    _ui.update { it.copy(showMetadataEdit = false) }
                    refresh()
                }
                .onFailure { err -> _ui.update { it.copy(error = err.cwMessage()) } }
        }

    // ── Lifecycle verbs (detail menu) ───────────────────────────
    /** Reopen the session (clears `endedAt`, makes it active); caller leaves the detail. */
    fun reopenSession(onDone: () -> Unit) = viewModelScope.launch {
        withContext(Dispatchers.IO) { runCatching { api.reopenSession(sessionId) } }
        onDone()
    }

    /** Delete the session — Rust soft-hides its QSOs and drops the session row. */
    fun deleteSession(onDone: () -> Unit) = viewModelScope.launch {
        withContext(Dispatchers.IO) { runCatching { api.deleteSession(sessionId) } }
        onDone()
    }

    companion object {
        // Bounded by the store's MAX_FETCH_LIMIT (1000); a larger value makes
        // fetch_qsos_for_session throw FetchLimitExceeded, which (because refresh
        // fetches the session + its QSOs in one runCatching) would null out the
        // session and break the whole detail screen — including Delete Session.
        private const val QSO_LIMIT = 1000L

        private fun nowSecs(): Long = System.currentTimeMillis() / 1_000L

        fun factory(sessionId: String) = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                SessionDetailViewModel(sessionId, app.store, app.sessionApi, app.mapApi, app.userHomeGrid)
            }
        }
    }
}
