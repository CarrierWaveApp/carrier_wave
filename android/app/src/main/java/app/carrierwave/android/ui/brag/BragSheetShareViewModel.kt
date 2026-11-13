package app.carrierwave.android.ui.brag

import android.content.Context
import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import app.carrierwave.android.ui.share.availableShareStyles
import app.carrierwave.android.ui.share.captureToBitmap
import app.carrierwave.android.ui.share.shareBitmapUri
import app.carrierwave.android.ui.share.writeShareBitmap
import app.carrierwave.android.util.AppLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.FfiBragPeriod
import uniffi.cw_ffi.FfiCoordinate
import uniffi.cw_ffi.FfiQso
import uniffi.cw_ffi.FfiQsoFilter
import uniffi.cw_ffi.FfiRingLabel
import uniffi.cw_ffi.FfiShareMapStyle
import uniffi.cw_ffi.FieldStore
import uniffi.cw_ffi.maidenheadCoordinate

data class BragSheetShareUiState(
    val loading: Boolean = true,
    val style: FfiShareMapStyle = FfiShareMapStyle.MIDNIGHT,
    val availableStyles: List<FfiShareMapStyle> = emptyList(),
    val mapImage: ImageBitmap? = null,
    /** Azimuthal-only range-ring captions to overlay on [mapImage]; empty for flat styles. */
    val ringLabels: List<FfiRingLabel> = emptyList(),
    /**
     * True once loading has finished and there were no clusters to map. Mirrors
     * iOS `BragSheetShareRenderer.renderWithMap`, which renders no map at all
     * when `clusters.isEmpty()` (`BragSheetShareRenderer.swift:127-132`) rather
     * than rasterizing an empty near-world map. The card's map section is
     * skipped when this is true, and the Share button stays enabled for the
     * stats-only card (it must not depend on [mapImage] being non-null).
     */
    val noClusters: Boolean = false,
    val sharing: Boolean = false,
    val error: String? = null,
)

/**
 * Drives the brag sheet share flow: fetches the QSO snapshot for the current
 * period, clusters it by grid (Kotlin port of iOS `computeClusters`), and
 * renders the selected [FfiShareMapStyle] via the shared Rust rasterizer. The
 * composed card itself is captured directly from the on-screen
 * [androidx.compose.ui.graphics.layer.GraphicsLayer] at share time (see
 * [share]) rather than held in this state — see [BragSheetShareCapture] for
 * why capture must be click-triggered, not effect-triggered.
 *
 * All FFI/store/file work runs on [Dispatchers.IO]; only [_state] updates
 * happen on the caller's dispatcher (Compose's Main).
 */
class BragSheetShareViewModel(
    private val store: FieldStore,
    private val homeGrid: String,
) : ViewModel() {

    private val _state = MutableStateFlow(BragSheetShareUiState())
    val state: StateFlow<BragSheetShareUiState> = _state.asStateFlow()

    private var clusters: List<BragSheetMapCluster> = emptyList()
    private var homeCoordinate: FfiCoordinate? = null

    /** Loads the period's QSO snapshot, computes clusters, and renders the initial map. */
    fun load(period: FfiBragPeriod) {
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            runCatching {
                withContext(Dispatchers.IO) {
                    val since = period.sinceEpochSeconds()
                    val qsos = fetchAllQsos(since)
                    val clustered = BragSheetShareRenderer.computeClusters(qsos)
                    val myGrid = BragSheetShareRenderer.mostCommonMyGrid(qsos) ?: homeGrid.takeIf { it.isNotBlank() }
                    val home = myGrid?.let { maidenheadCoordinate(it) }
                    Pair(clustered, home)
                }
            }.onSuccess { (clustered, home) ->
                clusters = clustered
                homeCoordinate = home
                val available = availableShareStyles(homeGridResolvable = home != null)
                val initialStyle = _state.value.style.takeIf { it in available } ?: available.first()
                _state.update {
                    it.copy(loading = false, availableStyles = available, style = initialStyle, noClusters = clustered.isEmpty())
                }
                if (clustered.isEmpty()) {
                    // Parity with iOS: skip the map render entirely rather than
                    // rasterizing an empty near-world map (BragSheetShareRenderer.swift:127-132).
                    _state.update { it.copy(mapImage = null, ringLabels = emptyList()) }
                } else {
                    renderMap(initialStyle)
                }
            }.onFailure { e ->
                _state.update { it.copy(loading = false, error = e.message ?: "Failed to load brag sheet map data") }
            }
        }
    }

    /** Pages through the whole logbook (bypassing the capped shared snapshot) since [since], newest-first. */
    private suspend fun fetchAllQsos(since: Long?): List<FfiQso> {
        val out = mutableListOf<FfiQso>()
        var offset = 0L
        while (true) {
            val page = store.fetchQsos(
                FfiQsoFilter(callsignPrefix = null, band = null, mode = null, since = since, dirtyOnly = false),
                PAGE,
                offset,
            )
            out += page.filterNot { it.isHidden }
            if (page.size < PAGE) break
            offset += PAGE
        }
        return out
    }

    fun selectStyle(style: FfiShareMapStyle) {
        if (style !in _state.value.availableStyles) return
        _state.update { it.copy(style = style, mapImage = null, ringLabels = emptyList()) }
        if (_state.value.noClusters) return
        renderMap(style)
    }

    private fun renderMap(style: FfiShareMapStyle) {
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    BragSheetShareRenderer.renderMap(style, clusters, homeCoordinate)
                }
            }.onSuccess { result ->
                val bitmap = result?.pngBytes?.let { bytes -> BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }
                _state.update { it.copy(mapImage = bitmap?.asImageBitmap(), ringLabels = result?.ringLabels.orEmpty()) }
            }.onFailure { e ->
                _state.update { it.copy(error = e.message ?: "Failed to render share map") }
            }
        }
    }

    /**
     * Rasterizes [cardLayer]'s last-drawn frame (the on-screen card preview),
     * writes it to cache, and fires the share intent. [cardLayer] must be the
     * [GraphicsLayer] wrapping the visible [BragSheetShareCard] — calling this
     * from a button click (as [BragSheetShareScreen] does) guarantees it has
     * already drawn at least once.
     */
    fun share(context: Context, cardLayer: GraphicsLayer) {
        viewModelScope.launch {
            _state.update { it.copy(sharing = true, error = null) }
            runCatching {
                val bitmap = cardLayer.captureToBitmap()
                writeShareBitmap(context, bitmap, "brag-sheet-share.png")
            }.onSuccess { uri ->
                _state.update { it.copy(sharing = false) }
                if (uri != null) {
                    shareBitmapUri(context, uri, "Share Brag Sheet")
                } else {
                    _state.update { it.copy(error = "Failed to prepare share image") }
                    AppLog.add(AppLog.Level.ERROR, "BragSheetShare: share() got null URI")
                }
            }.onFailure { e ->
                _state.update { it.copy(sharing = false, error = e.message ?: "Failed to prepare share image") }
                AppLog.add(AppLog.Level.ERROR, "BragSheetShare: capture/share failed: ${e.message}")
            }
        }
    }

    companion object {
        private const val PAGE = 1000L

        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                BragSheetShareViewModel(app.store, app.userHomeGrid)
            }
        }
    }
}
