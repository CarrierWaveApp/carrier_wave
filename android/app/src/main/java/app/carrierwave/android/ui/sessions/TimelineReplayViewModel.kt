package app.carrierwave.android.ui.sessions

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.FfiTimelineData
import uniffi.cw_ffi.MapApi
import uniffi.cw_ffi.QrzApi

/** UI state for the session timeline replay — the Android analog of iOS `TimelineMapView`. */
data class TimelineReplayUiState(
    val loading: Boolean = true,
    val data: FfiTimelineData? = null,
    /** Seconds since [FfiTimelineData.startedAt]; drives which events are visible. */
    val currentTime: Double = 0.0,
    val isPlaying: Boolean = false,
    val speed: Double = 1.0,
)

/**
 * Loads one session's replay timeline from the shared Rust `MapApi.sessionTimeline`
 * and drives playback — the Android analog of iOS `TimelineMapView`'s `loadData()` +
 * scrubber/play-pause state. Mirrors the iOS spotter-refinement flow: if the
 * timeline reports `unresolvedSpotters`, warms the `callbook_location` cache via
 * a store-backed `QrzApi.locate` pass (best-effort, failure swallowed) and
 * re-fetches the timeline exactly once to pick up the newly cached locations —
 * no retry loop.
 */
class TimelineReplayViewModel(
    val sessionId: String,
    private val mapApi: MapApi,
    private val qrzApi: QrzApi,
) : ViewModel() {

    private val _ui = MutableStateFlow(TimelineReplayUiState())
    val ui: StateFlow<TimelineReplayUiState> = _ui.asStateFlow()

    private var tickJob: Job? = null

    init {
        load()
    }

    private fun load() = viewModelScope.launch {
        var timeline = fetchTimeline() ?: return@launch

        if (timeline.unresolvedSpotters.isNotEmpty()) {
            refineUnresolvedSpotters(timeline.unresolvedSpotters)
            timeline = fetchTimeline() ?: timeline
        }

        _ui.update { it.copy(loading = false, data = timeline, currentTime = 0.0) }
    }

    private suspend fun fetchTimeline(): FfiTimelineData? =
        runCatching {
            withContext(Dispatchers.IO) { mapApi.sessionTimeline(sessionId.lowercase()) }
        }.getOrNull()

    /**
     * Best-effort spotter-grid warm-up (mirror of iOS `refineUnresolvedSpotters`).
     * Failures are swallowed — the timeline still renders with unresolved spots
     * simply lacking a location.
     */
    private suspend fun refineUnresolvedSpotters(spotters: List<String>) {
        runCatching {
            withContext(Dispatchers.IO) { qrzApi.locate(spotters) }
        }
    }

    // ── Playback ─────────────────────────────────────────────────

    fun togglePlayback() {
        if (_ui.value.isPlaying) stopPlayback() else startPlayback()
    }

    private fun startPlayback() {
        val duration = sessionDuration() ?: return
        if (_ui.value.currentTime >= duration) {
            _ui.update { it.copy(currentTime = 0.0) }
        }
        _ui.update { it.copy(isPlaying = true) }
        scheduleTick(duration)
    }

    private fun stopPlayback() {
        _ui.update { it.copy(isPlaying = false) }
        tickJob?.cancel()
        tickJob = null
    }

    private fun scheduleTick(duration: Double) {
        tickJob?.cancel()
        tickJob = viewModelScope.launch {
            while (_ui.value.isPlaying) {
                delay((TICK_INTERVAL_SECS * 1000).toLong())
                if (!_ui.value.isPlaying) break
                val next = _ui.value.currentTime + TICK_INTERVAL_SECS * _ui.value.speed
                if (next >= duration) {
                    _ui.update { it.copy(currentTime = duration, isPlaying = false) }
                    break
                } else {
                    _ui.update { it.copy(currentTime = next) }
                }
            }
        }
    }

    /** Scrubber drag — pauses nothing, just seeks. */
    fun seek(time: Double) {
        val duration = sessionDuration() ?: return
        _ui.update { it.copy(currentTime = time.coerceIn(0.0, duration)) }
    }

    /** Cycle 1x → 2x → 4x → 8x → 1x — matches iOS `TimelineMapView.cycleSpeed()`. */
    fun cycleSpeed() {
        val idx = SPEEDS.indexOf(_ui.value.speed).let { if (it < 0) 0 else it }
        _ui.update { it.copy(speed = SPEEDS[(idx + 1) % SPEEDS.size]) }
    }

    fun sessionDuration(): Double? {
        val data = _ui.value.data ?: return null
        return (data.endedAt - data.startedAt).toDouble()
    }

    override fun onCleared() {
        super.onCleared()
        tickJob?.cancel()
    }

    companion object {
        private const val TICK_INTERVAL_SECS = 1.0 / 30.0
        private val SPEEDS = listOf(1.0, 2.0, 4.0, 8.0)

        fun factory(sessionId: String) = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                TimelineReplayViewModel(sessionId, app.mapApi, app.qrzApi)
            }
        }
    }
}
