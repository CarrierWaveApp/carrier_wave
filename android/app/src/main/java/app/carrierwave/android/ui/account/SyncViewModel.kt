package app.carrierwave.android.ui.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import app.carrierwave.android.data.SyncConfig
import app.carrierwave.android.ui.common.cwMessage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.SyncKeyEnvelope
import uniffi.cw_ffi.createSyncEscrow
import uniffi.cw_ffi.openSyncEscrow
import uniffi.cw_ffi.syncGetKey
import uniffi.cw_ffi.syncPutKey
import uniffi.cw_ffi.syncRunPull
import uniffi.cw_ffi.syncRunPush

data class SyncUiState(
    val signedIn: Boolean = false,
    val enabled: Boolean = false,
    val busy: Boolean = false,
    /** Live step label while busy, mirroring the iOS phase readout. */
    val phase: String? = null,
    /** Unix millis when the in-flight operation started, for the elapsed readout. */
    val operationStart: Long? = null,
    /** "Pushed 12 · pulled 3 in 8.2s" style status from the last run. */
    val message: String? = null,
    val error: String? = null,
    /** Unix seconds of the last successful run. */
    val lastSyncAt: Long? = null,
)

/**
 * Carrier Wave Sync (E2E sync server) — enrollment + manual runs.
 *
 * Enrollment is passphrase-escrow based: if the account already has an escrow
 * envelope on the server we recover the data key from the passphrase
 * (`open_sync_escrow`); otherwise we mint a fresh one (`create_sync_escrow`),
 * upload the envelope, and mark the whole logbook dirty so the first push
 * uploads everything. The data key never leaves the Keystore-backed store;
 * every FFI call hops to [Dispatchers.IO] (SQLCipher + network).
 */
class SyncViewModel(private val app: CwApp) : ViewModel() {

    private val _state = MutableStateFlow(SyncUiState())
    val state: StateFlow<SyncUiState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        _state.update {
            it.copy(
                signedIn = app.authApi.hasSession(),
                enabled = SyncConfig.dataKey(app, app.baseUrl) != null,
                lastSyncAt = SyncConfig.lastSyncAt(app),
            )
        }
    }

    /** Enroll (fresh escrow) or recover (existing escrow) from [passphrase]. */
    fun enable(passphrase: String) = viewModelScope.launch {
        beginOperation()
        try {
            withContext(Dispatchers.IO) {
                setPhase("Contacting server…")
                val bearer = app.authApi.validAccessToken()
                val existing = syncGetKey(app.baseUrl, bearer)
                val dataKey = if (existing != null) {
                    setPhase("Deriving encryption key…")
                    try {
                        openSyncEscrow(passphrase, existing.wrappedKeyB64, existing.kdfParamsJson)
                    } catch (_: Exception) {
                        // The only recoverable cause is a KEK mismatch — say so
                        // instead of surfacing the raw "aead error".
                        error("This account already has a sync key — enter its original passphrase.")
                    }
                } else {
                    setPhase("Deriving encryption key…")
                    val created = createSyncEscrow(passphrase)
                    setPhase("Contacting server…")
                    syncPutKey(
                        app.baseUrl,
                        bearer,
                        SyncKeyEnvelope(created.wrappedKeyB64, created.kdfParamsJson),
                    )
                    // First device on this account: everything local is new to
                    // the server, so queue the full logbook for the first push.
                    app.store.markAllDirty("qso")
                    created.dataKey
                }
                setPhase("Saving…")
                SyncConfig.storeDataKey(app, app.baseUrl, dataKey)
            }
            _state.update {
                it.copy(busy = false, phase = null, operationStart = null, enabled = true, message = "Sync enabled.")
            }
        } catch (e: Exception) {
            _state.update { it.copy(busy = false, phase = null, operationStart = null, error = e.cwMessage()) }
        }
    }

    /** Per-step timings + counts from one pass, for the summary readout. */
    private data class PassSummary(
        val pushed: UInt,
        val pulled: UInt,
        val cursor: Long,
        val prepareMs: Long,
        val downloadMs: Long,
        val uploadMs: Long,
    )

    /** One pull→push pass; persists the returned cursor on success. */
    fun syncNow() = viewModelScope.launch {
        val dataKey = SyncConfig.dataKey(app, app.baseUrl) ?: return@launch
        beginOperation()
        val started = System.currentTimeMillis()
        try {
            val pass = withContext(Dispatchers.IO) { runPass(dataKey) }
            val now = System.currentTimeMillis() / 1_000L
            SyncConfig.storeCursor(app, app.baseUrl, pass.cursor, now)
            SyncConfig.markSeeded(app, app.baseUrl)
            if (pass.pulled > 0u) app.repository.refresh()
            val total = System.currentTimeMillis() - started
            val steps = buildList {
                if (pass.prepareMs > 0) add("prep ${sec(pass.prepareMs)}")
                add("down ${sec(pass.downloadMs)}")
                add("up ${sec(pass.uploadMs)}")
            }.joinToString(" · ")
            _state.update {
                it.copy(
                    busy = false,
                    phase = null,
                    operationStart = null,
                    lastSyncAt = now,
                    message = "Pushed ${pass.pushed} · pulled ${pass.pulled} in ${sec(total)} ($steps)",
                )
            }
        } catch (e: Exception) {
            _state.update { it.copy(busy = false, phase = null, operationStart = null, error = e.cwMessage()) }
        }
    }

    /**
     * The pull→push core, mirroring the iOS driver: seed on the first pass
     * against this server (dirty flags are cleared by pushes to *any* server,
     * so a server switch or an existing-escrow enroll would otherwise upload
     * nothing), pull from the persisted cursor so we never re-download what
     * we're about to push, then push and return the merged cursor.
     */
    private suspend fun runPass(dataKey: ByteArray): PassSummary {
        var prepareMs = 0L
        if (!SyncConfig.isSeeded(app, app.baseUrl)) {
            setPhase("Preparing your log…")
            val mark = System.currentTimeMillis()
            app.store.markAllDirty("qso")
            prepareMs = System.currentTimeMillis() - mark
        }
        val bearer = app.authApi.validAccessToken()
        var cursor = SyncConfig.lastSeq(app, app.baseUrl)
        setPhase("Downloading…")
        val downloadStart = System.currentTimeMillis()
        val pull = syncRunPull(app.store, app.baseUrl, bearer, dataKey, cursor)
        val downloadMs = System.currentTimeMillis() - downloadStart
        cursor = maxOf(cursor, pull.highWater)
        setPhase("Uploading…")
        val uploadStart = System.currentTimeMillis()
        val push = syncRunPush(app.store, app.baseUrl, bearer, dataKey)
        val uploadMs = System.currentTimeMillis() - uploadStart
        cursor = maxOf(cursor, push.highWater)
        return PassSummary(push.pushed, pull.pulled, cursor, prepareMs, downloadMs, uploadMs)
    }

    private fun beginOperation() {
        _state.update {
            it.copy(
                busy = true,
                error = null,
                message = null,
                phase = null,
                operationStart = System.currentTimeMillis(),
            )
        }
    }

    private fun setPhase(label: String) {
        _state.update { it.copy(phase = label) }
    }

    private fun sec(ms: Long) = "%.1fs".format(ms / 1000.0)

    /** Forget the local key + cursor. The server escrow stays for re-enable. */
    fun disable() {
        SyncConfig.clearDataKey(app, app.baseUrl)
        _state.update { it.copy(enabled = false, message = null, error = null, lastSyncAt = null) }
    }

    companion object {
        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                SyncViewModel(app)
            }
        }
    }
}
