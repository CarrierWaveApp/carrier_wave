package app.carrierwave.android.ui.activations

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
import app.carrierwave.android.ui.common.cwMessage
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
import uniffi.cw_ffi.AdifApi
import uniffi.cw_ffi.FfiCoordinate
import uniffi.cw_ffi.FfiQso
import uniffi.cw_ffi.FfiRingLabel
import uniffi.cw_ffi.FfiShareMapStyle

data class ActivationShareUiState(
    val loading: Boolean = true,
    val style: FfiShareMapStyle = FfiShareMapStyle.MIDNIGHT,
    val availableStyles: List<FfiShareMapStyle> = emptyList(),
    val mapImage: ImageBitmap? = null,
    val ringLabels: List<FfiRingLabel> = emptyList(),
    /** True once loading finished with no mappable QSOs — the card renders a placeholder map but Share stays enabled. */
    val noMappableQsos: Boolean = false,
    val qsoCount: Int = 0,
    val bands: List<String> = emptyList(),
    val sharing: Boolean = false,
    val error: String? = null,
)

/**
 * Drives the activation share-card flow: fetches the activation's QSOs
 * ([AdifApi.fetchActivationQsos] — the same `(park, callsign, UTC-day)` scope
 * the detail screen uses), builds RST-colored pins traced from the operator's
 * home coordinate, and renders the selected [FfiShareMapStyle] via the shared
 * Rust rasterizer ([ActivationShareRenderer]). The composed card is captured
 * from its on-screen [GraphicsLayer] at share time (see
 * [app.carrierwave.android.ui.share.RecordedLayer]).
 *
 * All FFI/store/file work runs on [Dispatchers.IO]; only [_state] updates happen
 * on the caller's dispatcher.
 */
class ActivationShareViewModel(
    private val adifApi: AdifApi,
    private val homeGrid: String,
) : ViewModel() {

    private val _state = MutableStateFlow(ActivationShareUiState())
    val state: StateFlow<ActivationShareUiState> = _state.asStateFlow()

    private var qsos: List<FfiQso> = emptyList()
    private var homeCoordinate: FfiCoordinate? = null

    fun load(park: String, callsign: String, utcDate: String) {
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            runCatching {
                withContext(Dispatchers.IO) {
                    val loaded = adifApi.fetchActivationQsos(park, callsign, utcDate)
                    val home = ActivationShareRenderer.resolveHomeCoordinate(loaded, homeGrid)
                    Triple(loaded, home, ActivationShareRenderer.hasMappableQsos(loaded))
                }
            }.onSuccess { (loaded, home, hasMappable) ->
                qsos = loaded
                homeCoordinate = home
                val bands = loaded.mapNotNull { it.band?.takeIf(String::isNotBlank) }.distinct()
                val available = availableShareStyles(homeGridResolvable = home != null)
                val initialStyle = _state.value.style.takeIf { it in available } ?: available.first()
                _state.update {
                    it.copy(
                        loading = false,
                        availableStyles = available,
                        style = initialStyle,
                        noMappableQsos = !hasMappable,
                        qsoCount = loaded.size,
                        bands = bands,
                    )
                }
                if (hasMappable) renderMap(initialStyle) else _state.update { it.copy(mapImage = null, ringLabels = emptyList()) }
            }.onFailure { err ->
                AppLog.add(AppLog.Level.ERROR, "activation share load failed: ${err.cwMessage()}")
                _state.update { it.copy(loading = false, error = err.cwMessage()) }
            }
        }
    }

    fun selectStyle(style: FfiShareMapStyle) {
        if (style !in _state.value.availableStyles) return
        _state.update { it.copy(style = style, mapImage = null, ringLabels = emptyList()) }
        if (_state.value.noMappableQsos) return
        renderMap(style)
    }

    private fun renderMap(style: FfiShareMapStyle) {
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    ActivationShareRenderer.renderMap(style, qsos, homeCoordinate)
                }
            }.onSuccess { result ->
                val bitmap = result?.pngBytes?.let { bytes -> BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }
                _state.update { it.copy(mapImage = bitmap?.asImageBitmap(), ringLabels = result?.ringLabels.orEmpty()) }
            }.onFailure { err ->
                _state.update { it.copy(error = err.cwMessage()) }
            }
        }
    }

    fun share(context: Context, cardLayer: GraphicsLayer) {
        viewModelScope.launch {
            _state.update { it.copy(sharing = true, error = null) }
            runCatching {
                val bitmap = cardLayer.captureToBitmap()
                writeShareBitmap(context, bitmap, "activation-share.png")
            }.onSuccess { uri ->
                _state.update { it.copy(sharing = false) }
                if (uri != null) {
                    shareBitmapUri(context, uri, "Share Activation")
                } else {
                    _state.update { it.copy(error = "Failed to prepare share image") }
                    AppLog.add(AppLog.Level.ERROR, "ActivationShare: share() got null URI")
                }
            }.onFailure { err ->
                _state.update { it.copy(sharing = false, error = err.cwMessage()) }
                AppLog.add(AppLog.Level.ERROR, "ActivationShare: capture/share failed: ${err.cwMessage()}")
            }
        }
    }

    companion object {
        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                ActivationShareViewModel(app.adifApi, app.userHomeGrid)
            }
        }
    }
}
