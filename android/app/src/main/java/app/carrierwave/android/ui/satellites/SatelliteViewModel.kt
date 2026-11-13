package app.carrierwave.android.ui.satellites

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import app.carrierwave.android.CwApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.CwException
import uniffi.cw_ffi.FfiCoordinate
import uniffi.cw_ffi.FfiObserver
import uniffi.cw_ffi.FfiPassForecast
import uniffi.cw_ffi.FfiSatTransmitter
import uniffi.cw_ffi.FfiSatelliteLook
import uniffi.cw_ffi.FfiSatellitePosition
import uniffi.cw_ffi.FfiSatelliteRefreshSummary
import uniffi.cw_ffi.FfiSatelliteSearchItem
import uniffi.cw_ffi.FfiSatelliteSummary
import uniffi.cw_ffi.FfiUpcomingPass
import uniffi.cw_ffi.SatelliteApi
import uniffi.cw_ffi.maidenheadCoordinate

/**
 * Satellite tab state over the shared Rust [SatelliteApi]: cache-through
 * refresh, a host-driven 5 s position tick (the API is stateless — time
 * scrubbing just shifts the epoch we ask for), selection + ground track,
 * search, pass forecasts. Mirror of the iOS `SatelliteTrackerModel`'s
 * view-model half; every FFI call is IO-dispatched (blocking FFI on Main
 * is an ANR).
 */
class SatelliteViewModel(
    private val api: SatelliteApi,
    homeGrid: String,
) : ViewModel() {

    data class UiState(
        val loading: Boolean = true,
        val error: String? = null,
        val observerGrid: String = "",
        val catalog: List<FfiSatelliteSummary> = emptyList(),
        val searchItems: List<FfiSatelliteSearchItem> = emptyList(),
        val positions: List<FfiSatellitePosition> = emptyList(),
        /** Wall-clock ms when [positions] was propagated (dead-reckoning). */
        val positionsSyncedAtMs: Long = 0,
        val selectedNoradId: UInt? = null,
        val selectedTrack: List<FfiSatellitePosition> = emptyList(),
        /** Time-scrubber offset: seconds ahead (+) / behind (−) real time. */
        val timeOffsetSecs: Long = 0,
        val tlesFetchedAtEpoch: Long = 0,
        val tlesStale: Boolean = false,
    )

    private val _state = MutableStateFlow(UiState(observerGrid = homeGrid))
    val state: StateFlow<UiState> = _state.asStateFlow()

    /** Observer from the profile home grid; null = QTH-not-set empty state. */
    val observer: FfiObserver? = homeGrid
        .takeIf { it.isNotBlank() }
        ?.let { grid -> maidenheadCoordinate(grid.take(6)) }
        ?.let { FfiObserver(latDeg = it.latitude, lonDeg = it.longitude) }

    /** Coalesces scrub-driven re-propagation (iOS `scrubRefreshInFlight`). */
    private var tickInFlight = false

    init {
        // Cached orbital data first (any age, no network) so the screen opens
        // immediately, then the cache-through refresh brings it up to date.
        // Only a cold cache leaves the spinner up while SatNOGS downloads.
        viewModelScope.launch {
            loadCached()
            refresh(force = false)
        }
    }

    private suspend fun loadCached() {
        if (_state.value.catalog.isNotEmpty()) return
        val summary = try {
            withContext(Dispatchers.IO) { api.loadCached() }
        } catch (e: CwException) {
            null
        } ?: return
        applyCatalog(summary)
    }

    suspend fun refresh(force: Boolean) {
        _state.value = _state.value.copy(loading = _state.value.catalog.isEmpty(), error = null)
        try {
            val summary = withContext(Dispatchers.IO) { api.refresh(force) }
            applyCatalog(summary)
        } catch (e: CwException) {
            _state.value = _state.value.copy(
                loading = false,
                error = if (_state.value.catalog.isEmpty()) e.message else null,
            )
        }
    }

    private suspend fun applyCatalog(summary: FfiSatelliteRefreshSummary) {
        val catalog = withContext(Dispatchers.IO) { api.catalog() }
        val search = withContext(Dispatchers.IO) { api.searchItems() }
        _state.value = _state.value.copy(
            loading = false,
            catalog = catalog,
            searchItems = search,
            tlesFetchedAtEpoch = summary.tlesFetchedAtEpoch,
            tlesStale = summary.tlesStale,
        )
        tick()
    }

    /** One propagation sync — the host screen drives this every 5 s. */
    suspend fun tick() {
        if (tickInFlight || _state.value.catalog.isEmpty()) return
        tickInFlight = true
        try {
            val epoch = simulatedEpoch()
            val positions = withContext(Dispatchers.IO) { api.positions(epoch, observer) }
            _state.value = _state.value.copy(
                positions = positions,
                positionsSyncedAtMs = System.currentTimeMillis(),
            )
            val selected = _state.value.selectedNoradId
            if (selected != null && _state.value.selectedTrack.isEmpty()) {
                loadTrack(selected)
            }
        } finally {
            tickInFlight = false
        }
    }

    fun select(noradId: UInt?) {
        _state.value = _state.value.copy(selectedNoradId = noradId, selectedTrack = emptyList())
        if (noradId != null) {
            viewModelScope.launch { loadTrack(noradId) }
        }
    }

    fun setTimeOffset(offsetSecs: Long) {
        _state.value = _state.value.copy(timeOffsetSecs = offsetSecs, selectedTrack = emptyList())
        viewModelScope.launch { tick() }
    }

    fun transmitters(noradId: UInt): List<FfiSatTransmitter> =
        _state.value.catalog.firstOrNull { it.noradId == noradId }?.transmitters ?: emptyList()

    fun summary(noradId: UInt): FfiSatelliteSummary? =
        _state.value.catalog.firstOrNull { it.noradId == noradId }

    fun selectedPosition(): FfiSatellitePosition? {
        val selected = _state.value.selectedNoradId ?: return null
        return _state.value.positions.firstOrNull { it.noradId == selected }
    }

    /** 48 h pass forecast for one bird (pass list sheet). */
    suspend fun passForecast(noradId: UInt): FfiPassForecast? {
        val site = observer ?: return null
        return try {
            withContext(Dispatchers.IO) {
                api.passForecast(noradId, site, simulatedEpoch(), 48.0, 12u)
            }
        } catch (_: CwException) {
            null
        }
    }

    /** All-sky upcoming passes (6 h window like iOS; empty favorites = all). */
    suspend fun upcomingPasses(favorites: List<UInt>): List<FfiUpcomingPass> {
        val site = observer ?: return emptyList()
        return try {
            withContext(Dispatchers.IO) {
                api.upcomingPasses(site, simulatedEpoch(), 6.0, favorites)
            }
        } catch (_: CwException) {
            emptyList()
        }
    }

    /** Doppler-corrected look sample for the pointing/sky-dome surfaces. */
    suspend fun look(noradId: UInt): FfiSatelliteLook? {
        val site = observer ?: return null
        return withContext(Dispatchers.IO) { api.look(noradId, simulatedEpoch(), site) }
    }

    fun simulatedEpoch(): Long =
        System.currentTimeMillis() / 1_000 + _state.value.timeOffsetSecs

    /** Natural Earth coastline polylines, fetched once (chart underlay). */
    suspend fun coastlines(): List<List<FfiCoordinate>> {
        coastlineCache?.let { return it }
        val loaded = withContext(Dispatchers.IO) { api.coastlineContinents() }
        coastlineCache = loaded
        return loaded
    }

    private var coastlineCache: List<List<FfiCoordinate>>? = null

    private suspend fun loadTrack(noradId: UInt) {
        val track = withContext(Dispatchers.IO) {
            api.groundTrack(noradId, simulatedEpoch(), observer)
        }
        if (_state.value.selectedNoradId == noradId) {
            _state.value = _state.value.copy(selectedTrack = track)
        }
    }

    companion object {
        fun factory(): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                SatelliteViewModel(app.satelliteApi, app.userHomeGrid)
            }
        }
    }
}
