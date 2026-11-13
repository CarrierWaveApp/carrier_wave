package app.carrierwave.android.data

import app.carrierwave.android.ui.common.utcDayKey
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.CwException
import uniffi.cw_ffi.FfiQso
import uniffi.cw_ffi.FfiQsoFilter
import uniffi.cw_ffi.FfiQueryAnalysis
import uniffi.cw_ffi.FfiStoreChange
import uniffi.cw_ffi.FfiStoreTable
import uniffi.cw_ffi.FieldStore
import uniffi.cw_ffi.StoreObserver
import uniffi.cw_ffi.analyzeQuery
import uniffi.cw_ffi.validateQuery

/**
 * Single source of truth for QSO data across Home / Logger / Sessions.
 *
 * Wraps the encrypted Rust [FieldStore] (the same `cw-store` the iOS app uses)
 * and publishes a shared, observable snapshot of the logbook so every tab stays
 * in sync after an edit. Reads/writes hop to [Dispatchers.IO] — the FFI calls
 * cross into SQLCipher and must never touch the main thread.
 *
 * The snapshot stays fresh via a Rust [StoreObserver] (the UniFFI callback that
 * replaces iOS SwiftData `@Query` reactivity): any committed QSO mutation —
 * including QSOs logged through a session via `SessionApi.logQso`, which never
 * pass through [upsert] — re-fetches the snapshot. Without this, session-logged
 * QSOs are written to the store but invisible in Home/Logbook until relaunch,
 * because the tab ViewModels are app-lifetime singletons that only refresh once
 * at launch (CAR-291).
 */
@OptIn(FlowPreview::class)
class LogbookRepository(
    private val store: FieldStore,
    homeGrid: String,
    private val scope: CoroutineScope,
) {
    /** Operator home grid — used for live distance/bearing. Updated on profile edits. */
    @Volatile
    var homeGrid: String = homeGrid
    private val _qsos = MutableStateFlow<List<FfiQso>>(emptyList())

    // Coalesces QSO-table change notifications into snapshot refreshes. Conflated
    // (capacity 1, drop-oldest) so a burst — a sync pull committing thousands of
    // rows, or a fast run of logged QSOs — collapses to a single trailing refresh
    // instead of one fetch per row.
    private val storeChanges =
        MutableSharedFlow<Unit>(extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)

    // Fires on every committed store mutation, on the mutating thread; we only
    // care about the QSO table (the snapshot's sole source). Held for the app's
    // lifetime — the repository is an Application-scoped singleton, so the
    // observer never needs removing.
    private val observer = object : StoreObserver {
        override fun onChange(change: FfiStoreChange) {
            if (change.table == FfiStoreTable.QSO) storeChanges.tryEmit(Unit)
        }
    }

    init {
        store.addObserver(observer)
        scope.launch { storeChanges.debounce(DEBOUNCE_MS).collect { refresh() } }
    }

    /** Newest-first snapshot of the whole logbook (capped at [PAGE]). */
    val qsos: StateFlow<List<FfiQso>> = _qsos.asStateFlow()

    private val _loading = MutableStateFlow(false)
    val loading: StateFlow<Boolean> = _loading.asStateFlow()

    suspend fun refresh() {
        _loading.update { true }
        try {
            val rows = withContext(Dispatchers.IO) {
                store.fetchQsos(FfiQsoFilter(callsignPrefix = null, band = null, mode = null, since = null, dirtyOnly = false), PAGE, 0L)
                    // The raw fetch includes soft-deleted rows (the sync push
                    // needs them); the visible logbook must not.
                    .filterNot { it.isHidden }
                    .sortedByDescending { it.qsoDate }
            }
            _qsos.update { rows }
        } finally {
            _loading.update { false }
        }
    }

    suspend fun count(): Long = withContext(Dispatchers.IO) { store.qsoCount() }

    /**
     * QSO count per UTC day over the trailing [days] — the Home activity
     * heatmap. The FFI has no per-day aggregate (coarsest is MONTH), so this
     * pages the raw rows with a `since` bound and groups client-side. Bypasses
     * the [PAGE]-capped shared snapshot on purpose: a busy year exceeds it.
     */
    suspend fun dayCounts(days: Long = 371L): Map<String, Int> = withContext(Dispatchers.IO) {
        val since = System.currentTimeMillis() / 1_000L - days * 86_400L
        val counts = mutableMapOf<String, Int>()
        var offset = 0L
        while (true) {
            val page = store.fetchQsos(FfiQsoFilter(callsignPrefix = null, band = null, mode = null, since = since, dirtyOnly = false), PAGE, offset)
            for (qso in page) {
                if (qso.isHidden) continue
                val key = utcDayKey(qso.qsoDate)
                counts[key] = (counts[key] ?: 0) + 1
            }
            if (page.size < PAGE) break
            offset += PAGE
        }
        counts
    }

    /** Persist a QSO, then refresh the shared snapshot. */
    suspend fun upsert(qso: FfiQso): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            store.upsertQso(qso)
            Result.success(Unit)
        } catch (e: CwException) {
            Result.failure(e)
        }
    }.also { if (it.isSuccess) refresh() }

    /** Persist a manual edit: stamps `modifiedAt` + `dirty` so sync pushes it. */
    suspend fun update(qso: FfiQso): Result<Unit> =
        upsert(qso.copy(modifiedAt = nowSecs(), dirty = true))

    /**
     * Sync-safe soft delete: `isHidden = true` + `dirty = true` via upsert so
     * the journal propagates it (`FieldStore.deleteQso` is a local-only hard
     * delete). Mirrors the iOS Logbook `softDeleteQSOs`.
     */
    suspend fun softDelete(qso: FfiQso): Result<Unit> =
        upsert(qso.copy(isHidden = true, modifiedAt = nowSecs(), dirty = true))

    /** Validate + cost-analyze a raw filter expression for the query bar. */
    suspend fun analyze(raw: String): Result<FfiQueryAnalysis> = withContext(Dispatchers.IO) {
        try {
            val canonical = validateQuery(raw)
            Result.success(analyzeQuery(canonical, store.qsoCount()))
        } catch (e: CwException) {
            Result.failure(e)
        }
    }

    /**
     * Run a filter expression against the whole logbook and return the matching
     * QSOs (newest-first). Unlike [qsos] this does NOT touch the shared snapshot,
     * so the Logbook tab can filter without disturbing Home/Logger. Uses the DSL
     * path ([FieldStore.fetchQsosQuery]) which also populates service-presence
     * badges on each row.
     */
    suspend fun queryQsos(raw: String, limit: Long = PAGE): Result<List<FfiQso>> =
        withContext(Dispatchers.IO) {
            try {
                val canonical = validateQuery(raw)
                val rows = store.fetchQsosQuery(canonical, limit, 0L)
                    .sortedByDescending { it.qsoDate }
                Result.success(rows)
            } catch (e: CwException) {
                Result.failure(e)
            }
        }

    companion object {
        private const val PAGE = 1000L

        /** Debounce window for observer-driven refreshes — long enough to
         *  collapse a burst of writes, short enough to feel instant. */
        private const val DEBOUNCE_MS = 150L

        /** Current Unix seconds — the cw-store contract for modified_at. */
        private fun nowSecs(): Long = System.currentTimeMillis() / 1_000L
    }
}
