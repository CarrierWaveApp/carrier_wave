package app.carrierwave.android.ui.spots

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import app.carrierwave.android.data.SpotEngineProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.FfiSpotFilter
import uniffi.cw_ffi.FfiSpotModeFilter

/**
 * Live spots from the shared Rust spot engine. The engine polls all enabled
 * sources on its own cadence, merges/enriches the pool (grids, distance,
 * DXCC), and bumps [SpotEngineProvider.generation] after every publish; this
 * re-reads a filtered snapshot on each bump and maps it for the UI.
 */
class SpotsViewModel(private val provider: SpotEngineProvider) : ViewModel() {

    /** How to order the spot list — the Android analog of iOS `SpotSortOrder`. */
    enum class SortOrder(val label: String) {
        RECENT("Recent"),
        FREQUENCY("Frequency"),
        NEEDS("Needs"),
    }

    /**
     * User-selectable "widget" filters layered on top of the source chip and the
     * HUNT mode-family seed — the Android analog of iOS `SpotFilters`. Empty set /
     * false = no constraint on that dimension.
     */
    data class WidgetFilters(
        val bands: Set<String> = emptySet(),
        val modes: Set<String> = emptySet(),
        val needsOnly: Boolean = false,
    ) {
        // NOTE: iOS's "hide worked" isn't offered here yet — the engine's
        // `hide_worked` needs a worked-callsign FilterContext that this
        // server-side `snapshot(filter, null)` path doesn't supply, so it would
        // be a no-op. Deferred until the context is plumbed through.

        /** Count of active dimensions, for the filter button's badge. */
        val activeCount: Int
            get() = (if (bands.isNotEmpty()) 1 else 0) +
                (if (modes.isNotEmpty()) 1 else 0) +
                (if (needsOnly) 1 else 0)
    }

    data class State(
        /** Source filter chip; null = all enabled sources merged. */
        val source: SpotSource? = null,
        /** Band/mode/worked/needs filters set via the filter sheet. */
        val filters: WidgetFilters = WidgetFilters(),
        /** Active list ordering (segmented control above the list). */
        val sortOrder: SortOrder = SortOrder.RECENT,
        val spots: List<Spot> = emptyList(),
        /** Pool-wide per-source counts (unfiltered), for the chip labels. */
        val counts: Map<SpotSource, Int> = emptyMap(),
        val loading: Boolean = true,
        /** A pull-to-refresh poll is in flight (distinct from first load). */
        val refreshing: Boolean = false,
        val error: String? = null,
        /** Unix epoch seconds of the engine's last completed poll (0 = never). */
        val lastRefresh: Long = 0L,
        /** Pending "Spot on POTA?" confirmation; null when no dialog is up. */
        val respotPrompt: RespotPrompt? = null,
        /** Transient status line (respot result), auto-cleared after a few seconds. */
        val notice: String? = null,
    )

    /** Explicit respot confirmation state — respotting publishes to POTA
     *  under the user's callsign, so it is never a one-tap action. */
    data class RespotPrompt(
        val spot: Spot,
        val myCallsign: String,
        /** True when the activator was respotted within the anti-spam cooldown. */
        val recentlySpotted: Boolean,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    private val sourceFilter = MutableStateFlow<SpotSource?>(null)

    /** Mode-family filter (CW/Phone/Digital), `ALL` = no mode filter. Seeded by
     *  the HUNT command from the active session's mode; the tab leaves it `ALL`. */
    private val modeFilter = MutableStateFlow(FfiSpotModeFilter.ALL)

    /** Band/mode/worked/needs filters set via the filter sheet. */
    private val widgetFilters = MutableStateFlow(WidgetFilters())

    /** Active list ordering. */
    private val sortOrder = MutableStateFlow(SortOrder.RECENT)

    init {
        provider.startIfNeeded()
        viewModelScope.launch {
            combine(
                provider.generation,
                sourceFilter,
                modeFilter,
                widgetFilters,
                sortOrder,
            ) { _, source, mode, widgets, sort ->
                Rebuild(source, mode, widgets, sort)
            }.collect { (source, mode, widgets, sort) -> rebuild(source, mode, widgets, sort) }
        }
    }

    /** Switch the source filter chip. No-op if already selected. */
    fun selectSource(source: SpotSource?) {
        if (source == sourceFilter.value) return
        _state.update { it.copy(source = source) }
        sourceFilter.value = source
    }

    /** Constrain the feed to a mode family (or `ALL` to clear). Used by the HUNT
     *  command to default the browser to the operator's current mode. */
    fun applyModeFilter(mode: FfiSpotModeFilter) {
        modeFilter.value = mode
    }

    /** Commit the filter-sheet selection (band/mode/worked/needs). */
    fun applyFilters(filters: WidgetFilters) {
        _state.update { it.copy(filters = filters) }
        widgetFilters.value = filters
    }

    /** Switch the list ordering. No-op if already selected. */
    fun selectSort(order: SortOrder) {
        if (order == sortOrder.value) return
        _state.update { it.copy(sortOrder = order) }
        sortOrder.value = order
    }

    /** One manual refresh outside the engine's timer (pull-to-refresh). */
    fun refresh() {
        if (_state.value.refreshing) return
        val engine = provider.engine() ?: return
        _state.update { it.copy(refreshing = true) }
        viewModelScope.launch {
            withContext(Dispatchers.IO) { runCatching { engine.refresh() } }
            _state.update { it.copy(refreshing = false) }
        }
    }

    /** Raise the explicit respot confirmation for a POTA spot. */
    fun requestRespot(spot: Spot, myCallsign: String) {
        if (spot.source != SpotSource.POTA || spot.reference == null || spot.freqKhz == null) return
        if (myCallsign.isBlank()) {
            showNotice("Set your callsign in Account before spotting")
            return
        }
        val engine = provider.engine() ?: return
        viewModelScope.launch {
            val remaining = withContext(Dispatchers.IO) {
                runCatching { engine.potaRespotCooldownRemaining(spot.callsign) }.getOrNull()
            }
            _state.update {
                it.copy(
                    respotPrompt = RespotPrompt(
                        spot = spot,
                        myCallsign = myCallsign,
                        recentlySpotted = remaining != null,
                    ),
                )
            }
        }
    }

    fun dismissRespot() = _state.update { it.copy(respotPrompt = null) }

    /** Post the confirmed respot through the shared engine. */
    fun confirmRespot() {
        val prompt = _state.value.respotPrompt ?: return
        _state.update { it.copy(respotPrompt = null) }
        val engine = provider.engine() ?: return
        val spot = prompt.spot
        val reference = spot.reference ?: return
        val freqKhz = spot.freqKhz ?: return
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { engine.potaRespot(spot.callsign, reference, freqKhz, spot.mode, null) }
            }
            showNotice(
                result.fold(
                    onSuccess = { "Spotted ${spot.callsign} at $reference" },
                    onFailure = { err -> "Respot failed: ${err.message}" },
                ),
            )
        }
    }

    private fun showNotice(text: String) {
        _state.update { it.copy(notice = text) }
        viewModelScope.launch {
            delay(4_000)
            _state.update { if (it.notice == text) it.copy(notice = null) else it }
        }
    }

    /** Re-read a filtered snapshot off-main (the FFI call locks + copies). */
    private suspend fun rebuild(source: SpotSource?, mode: FfiSpotModeFilter, widgets: WidgetFilters, sort: SortOrder) {
        val engine = provider.engine()
        if (engine == null) {
            _state.update { it.copy(loading = false, error = provider.lastError) }
            return
        }
        val snapshot = withContext(Dispatchers.IO) {
            engine.snapshot(filterFor(source, mode, widgets), null)
        }
        val spots = snapshot.spots
            .mapNotNull { it.toSpot() }
            .sortedWith(comparatorFor(sort))
        val counts = snapshot.counts
            .mapNotNull { entry -> entry.source.toUi()?.let { it to entry.count.toInt() } }
            .toMap()
        val error = snapshot.errors
            .takeIf { it.isNotEmpty() }
            ?.joinToString(" · ") { "${it.source.toUi()?.label ?: it.source.name}: ${it.message}" }
        _state.update {
            it.copy(
                spots = spots,
                counts = counts,
                loading = snapshot.lastRefresh == 0L && spots.isEmpty(),
                error = error,
                lastRefresh = snapshot.lastRefresh,
            )
        }
    }

    /**
     * List ordering for each [SortOrder] — same keys and tiebreaks as the iOS
     * `sortedSpots` primary sort. Spots without a frequency sink to the bottom
     * of the Frequency order; unmatched needs (-1) sink in the Needs order.
     */
    private fun comparatorFor(sort: SortOrder): Comparator<Spot> = when (sort) {
        SortOrder.RECENT ->
            compareByDescending<Spot> { it.epochSeconds ?: 0.0 }
                .thenByDescending { it.callsign }
        SortOrder.FREQUENCY ->
            compareBy<Spot> { it.freqKhz ?: Double.MAX_VALUE }
                .thenBy { it.callsign }
        SortOrder.NEEDS ->
            compareByDescending<Spot> { it.needPriority ?: -1 }
                .thenByDescending { it.epochSeconds ?: 0.0 }
    }

    /** Build the snapshot filter for the active source + mode + widget selection,
     *  or null when nothing is set (the engine then returns the whole pool). */
    private fun filterFor(source: SpotSource?, mode: FfiSpotModeFilter, widgets: WidgetFilters): FfiSpotFilter? {
        if (source == null && mode == FfiSpotModeFilter.ALL && widgets == WidgetFilters()) return null
        return FfiSpotFilter(
            sources = source?.let { listOf(it.toFfi()) } ?: emptyList(),
            bands = widgets.bands.toList(),
            modeFamilies = if (mode == FfiSpotModeFilter.ALL) emptyList() else listOf(mode),
            modes = widgets.modes.toList(),
            continents = emptyList(),
            regionGroups = emptyList(),
            status = null,
            maxAgeMinutes = null,
            text = null,
            hideWorked = false,
            needsOnly = widgets.needsOnly,
        )
    }

    /** Inputs of one [rebuild] pass, combined from the filter + sort flows. */
    private data class Rebuild(
        val source: SpotSource?,
        val mode: FfiSpotModeFilter,
        val widgets: WidgetFilters,
        val sort: SortOrder,
    )

    companion object {
        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                SpotsViewModel(app.spotEngine)
            }
        }
    }
}
