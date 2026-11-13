package app.carrierwave.android.ui.propagation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import app.carrierwave.android.ui.common.cwMessage
import app.carrierwave.android.util.AppLog
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
import uniffi.cw_ffi.FfiPropagationConfig
import uniffi.cw_ffi.FfiPropagationResults
import uniffi.cw_ffi.FfiPropagationSolar
import uniffi.cw_ffi.FfiPropagationState
import uniffi.cw_ffi.FfiPropagationStopReason
import uniffi.cw_ffi.PropagationApi
import uniffi.cw_ffi.QrzApi
import uniffi.cw_ffi.propagationPollCadence

/** Screen the [PropagationCheckViewModel] is currently showing. */
enum class PropagationCheckScreen { START, LIVE, RESULTS }

/** Config captured from the start sheet, frozen for the session. */
data class PropagationCheckConfig(
    val callsign: String,
    val bands: List<String>,
    val userGrid: String,
    val durationCapSeconds: Long?,
)

data class PropagationCheckUiState(
    val screen: PropagationCheckScreen = PropagationCheckScreen.START,
    val defaultCallsign: String = "",
    val defaultGrid: String = "",
    // Live session state, mirrored from the latest FfiPropagationState poll.
    val config: PropagationCheckConfig? = null,
    val startedAtEpoch: Double = 0.0,
    val elapsedSeconds: Long = 0,
    val state: FfiPropagationState? = null,
    val rbnConnected: Boolean = true,
    val pskrConnected: Boolean = true,
    val lastError: String? = null,
    // Finalized results, once stopped.
    val results: FfiPropagationResults? = null,
    val stopReason: FfiPropagationStopReason = FfiPropagationStopReason.USER,
    val error: String? = null,
)

/**
 * Drives a propagation check session end to end on the shared Rust
 * [PropagationApi]: start sheet config -> live polling -> finalized results.
 * The Android analog of iOS `PropagationCheckSession` + `PropagationCheckRootView`,
 * collapsed into one ViewModel since Android has no SwiftData artifact store for
 * these yet (results are shown for the current session only, not persisted —
 * see the class doc on [PropagationCheckScreen] for the parity note).
 *
 * All FFI calls run on [Dispatchers.IO] — `poll()` does blocking network I/O
 * (RBN + PSK Reporter fetch) and must never run on Main.
 */
class PropagationCheckViewModel(
    private val store: uniffi.cw_ffi.FieldStore,
    private val qrz: QrzApi,
    private val baseUrl: String,
    defaultCallsign: String,
    defaultGrid: String,
) : ViewModel() {

    private val _ui = MutableStateFlow(
        PropagationCheckUiState(defaultCallsign = defaultCallsign, defaultGrid = defaultGrid),
    )
    val ui: StateFlow<PropagationCheckUiState> = _ui.asStateFlow()

    private var api: PropagationApi? = null
    private var pollJob: Job? = null
    private var timerJob: Job? = null

    /** Guards [stop] against re-entrant/duplicate finalize: the duration-cap
     * timer polls every 1s and re-checks `screen == LIVE`, which is still true
     * while an in-flight finalize coroutine is doing its IO round-trip (stop +
     * results) and hasn't yet flipped the screen to RESULTS. Without this flag
     * a second timer tick (or a user Stop tap racing the timer) would call
     * `stop()` again and launch a redundant finalize. First caller wins;
     * cleared on both success and failure so a failed finalize can be retried. */
    private var isStopping = false

    /** Poll cadence: the Rust engine enforces the PSK Reporter 5-min floor
     * internally, so the host just needs to re-poll at the RBN cadence (the
     * tighter of the two, 30s) per [propagationPollCadence]. */
    fun start(config: PropagationCheckConfig) {
        if (_ui.value.screen == PropagationCheckScreen.LIVE) return
        val startedAt = System.currentTimeMillis() / 1_000.0
        _ui.update {
            it.copy(
                screen = PropagationCheckScreen.LIVE,
                config = config,
                startedAtEpoch = startedAt,
                elapsedSeconds = 0,
                state = null,
                rbnConnected = true,
                pskrConnected = true,
                lastError = null,
                results = null,
                error = null,
            )
        }
        AppLog.add(AppLog.Level.INFO, "Propagation check started for ${config.callsign}, bands: ${config.bands.joinToString(",")}")

        pollJob = viewModelScope.launch {
            val created = runCatching {
                withContext(Dispatchers.IO) {
                    val newApi = PropagationApi(store, qrz, baseUrl)
                    // Android has no NOAA/HamQSL client yet; solar stays null
                    // (host-side omission, tracked as a follow-up — see the
                    // FfiPropagationSolar doc: None means the host skipped the
                    // fetch, exactly this case).
                    val solar: FfiPropagationSolar? = null
                    val ffiConfig = FfiPropagationConfig(
                        callsign = config.callsign,
                        bands = config.bands,
                        userGrid = config.userGrid,
                        startedAtEpoch = startedAt,
                        solar = solar,
                    )
                    newApi.startSession(ffiConfig)
                    newApi
                }
            }
            created.onFailure { err ->
                AppLog.add(AppLog.Level.ERROR, "Propagation session start failed: ${err.cwMessage()}")
                _ui.update { it.copy(screen = PropagationCheckScreen.START, error = err.cwMessage()) }
            }
            val newApi = created.getOrNull() ?: return@launch
            api = newApi
            pollLoop(newApi, config)
        }

        timerJob = viewModelScope.launch {
            while (isActive && _ui.value.screen == PropagationCheckScreen.LIVE) {
                delay(1_000)
                val snapshot = _ui.value
                val elapsed = (System.currentTimeMillis() / 1_000.0 - snapshot.startedAtEpoch).toLong()
                _ui.update { it.copy(elapsedSeconds = elapsed) }
                val cap = snapshot.config?.durationCapSeconds
                if (cap != null && elapsed >= cap) {
                    stop(FfiPropagationStopReason.DURATION)
                }
            }
        }
    }

    private suspend fun pollLoop(session: PropagationApi, config: PropagationCheckConfig) {
        val cadence = propagationPollCadence()
        val pollIntervalMs = (maxOf(1.0, cadence.rbnIntervalSecs) * 1_000).toLong()
        while (pollJob?.isActive == true && _ui.value.screen == PropagationCheckScreen.LIVE) {
            runCatching { session.poll() }
                .onSuccess { state ->
                    _ui.update {
                        it.copy(
                            state = state,
                            rbnConnected = state.rbnConnected,
                            pskrConnected = state.pskrConnected,
                            lastError = state.lastError,
                        )
                    }
                }
                .onFailure { err ->
                    AppLog.add(AppLog.Level.ERROR, "Propagation poll failed: ${err.cwMessage()}")
                    _ui.update { it.copy(lastError = err.cwMessage()) }
                }
            delay(pollIntervalMs)
        }
    }

    /**
     * Stop the session, finalize results, and move to the results screen.
     *
     * Idempotent and non-re-entrant: the duration-cap timer (see [start]) can
     * observe `screen == LIVE` and call this a second time while the first
     * call's async finalize is still in flight (the screen only flips to
     * RESULTS once that finalize completes). [isStopping] makes the second
     * call — from the timer, or a user Stop tap racing it — a no-op; the
     * first caller's finalize is the one that lands the transition.
     */
    fun stop(reason: FfiPropagationStopReason = FfiPropagationStopReason.USER) {
        if (_ui.value.screen != PropagationCheckScreen.LIVE) return
        if (isStopping) return
        isStopping = true
        pollJob?.cancel()
        pollJob = null
        timerJob?.cancel()
        timerJob = null
        val session = api
        if (session == null) {
            isStopping = false
            _ui.update { it.copy(screen = PropagationCheckScreen.START) }
            return
        }
        viewModelScope.launch {
            val finalized = runCatching {
                withContext(Dispatchers.IO) {
                    session.stop(reason)
                    session.results()
                }
            }
            finalized.onSuccess { results ->
                AppLog.add(
                    AppLog.Level.INFO,
                    "Propagation check stopped (${reason.name}); ${results.totalSpots} spots, ${results.uniqueSkimmers} skimmers",
                )
                _ui.update {
                    it.copy(
                        screen = PropagationCheckScreen.RESULTS,
                        results = results,
                        stopReason = reason,
                    )
                }
            }.onFailure { err ->
                AppLog.add(AppLog.Level.ERROR, "Propagation stop/results failed: ${err.cwMessage()}")
                _ui.update { it.copy(screen = PropagationCheckScreen.START, error = err.cwMessage()) }
            }
            isStopping = false
        }
    }

    /** Discard the current results and return to the start sheet for a new check. */
    fun reset() {
        pollJob?.cancel()
        pollJob = null
        timerJob?.cancel()
        timerJob = null
        isStopping = false
        api = null
        _ui.update {
            it.copy(
                screen = PropagationCheckScreen.START,
                config = null,
                state = null,
                results = null,
                error = null,
            )
        }
    }

    override fun onCleared() {
        pollJob?.cancel()
        timerJob?.cancel()
        super.onCleared()
    }

    companion object {
        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                PropagationCheckViewModel(app.store, app.qrzApi, app.baseUrl, app.userCallsign, app.userHomeGrid)
            }
        }
    }
}
