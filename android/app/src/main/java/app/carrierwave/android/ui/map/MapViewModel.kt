package app.carrierwave.android.ui.map

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.FfiGridBounds
import uniffi.cw_ffi.FfiMapFilter
import uniffi.cw_ffi.FfiQsoMapData
import uniffi.cw_ffi.FieldStore
import uniffi.cw_ffi.MapApi
import uniffi.cw_ffi.maidenheadGridBounds

/** Which overlay the map is showing. */
enum class MapLayer { QSOS, DXCC }

/** UI filter state mirrored into FfiMapFilter on each reload. */
data class MapFilter(
    val band: String? = null,
    val mode: String? = null,
    val park: String? = null,
    val startDate: Long? = null,
    val endDate: Long? = null,
    val confirmedOnly: Boolean = false,
    val showIndividual: Boolean = false,
    val showPaths: Boolean = false,
    val showAll: Boolean = false,
    val showGridOverlay: Boolean = false,
) {
    val hasActiveFilters: Boolean
        get() = band != null || mode != null || park != null ||
            startDate != null || endDate != null || confirmedOnly
}

/** One worked-grid overlay tile with its corner bounds and status. */
data class GridOverlayTile(
    val bounds: FfiGridBounds,
    val confirmed: Boolean,
)

data class MapUiState(
    val layer: MapLayer = MapLayer.QSOS,
    val filter: MapFilter = MapFilter(),
    val data: FfiQsoMapData? = null,
    val gridTiles: List<GridOverlayTile> = emptyList(),
    val dxccPins: List<MapPinUi> = emptyList(),
    val loading: Boolean = true,
    val error: String? = null,
)

data class MapPinUi(val latitude: Double, val longitude: Double, val title: String)

/**
 * Map tab — Rust MapApi view-model. All clustering/arc/stat math is shared
 * with iOS via cw-ffi; this class only shuttles state.
 */
class MapViewModel(
    private val mapApi: MapApi,
    private val store: FieldStore,
    val homeGrid: String,
) : ViewModel() {

    private val _state = MutableStateFlow(MapUiState())
    val state: StateFlow<MapUiState> = _state.asStateFlow()

    /** In-flight qsoMap load; cancelled on each reload so a stale slow response can't land after a newer one. */
    private var reloadJob: Job? = null

    init {
        reload()
        viewModelScope.launch { loadDxcc() }
    }

    fun setLayer(layer: MapLayer) = _state.update { it.copy(layer = layer) }

    fun updateFilter(transform: (MapFilter) -> MapFilter) {
        val newFilter = transform(_state.value.filter)
        _state.update { it.copy(filter = newFilter) }
        reload()
        if (newFilter.showGridOverlay && _state.value.gridTiles.isEmpty()) {
            viewModelScope.launch { loadGridTiles() }
        }
    }

    fun reload() {
        reloadJob?.cancel()
        reloadJob = viewModelScope.launch {
            _state.update { it.copy(loading = it.data == null) }
            val filter = _state.value.filter
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    mapApi.qsoMap(
                        FfiMapFilter(
                            band = filter.band,
                            mode = filter.mode,
                            park = filter.park,
                            startDate = filter.startDate,
                            endDate = filter.endDate,
                            confirmedOnly = filter.confirmedOnly,
                            showIndividual = filter.showIndividual,
                            showPaths = filter.showPaths,
                            maxQsos = if (filter.showAll) null else 500u,
                        ),
                    )
                }
            }
            result.fold(
                onSuccess = { data -> _state.update { it.copy(data = data, loading = false, error = null) } },
                onFailure = { e -> _state.update { it.copy(loading = false, error = e.message) } },
            )
        }
    }

    private suspend fun loadGridTiles() {
        val tiles = withContext(Dispatchers.IO) {
            runCatching {
                store.qsoGridTiles("", 4).mapNotNull { tile ->
                    maidenheadGridBounds(tile.tile)?.let { bounds ->
                        GridOverlayTile(bounds, tile.confirmed > 0)
                    }
                }
            }.getOrDefault(emptyList())
        }
        _state.update { it.copy(gridTiles = tiles) }
    }

    private suspend fun loadDxcc() {
        val pins = withContext(Dispatchers.IO) {
            runCatching {
                store.dxccWorked("").map {
                    MapPinUi(it.latitude, it.longitude, "${it.name} · ${it.count}")
                }
            }.getOrDefault(emptyList())
        }
        _state.update { it.copy(dxccPins = pins) }
    }

    companion object {
        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                MapViewModel(app.mapApi, app.store, app.repository.homeGrid)
            }
        }
    }
}
