package app.carrierwave.android.ui.activations

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.BuildConfig
import app.carrierwave.android.CwApp
import app.carrierwave.android.ui.common.cwMessage
import app.carrierwave.android.ui.share.shareTextFileUri
import app.carrierwave.android.ui.share.writeShareBytes
import app.carrierwave.android.util.AppLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.AdifApi
import uniffi.cw_ffi.FfiActivationRollup
import uniffi.cw_ffi.FfiAdifBulkActivationRef
import uniffi.cw_ffi.FieldStore

/**
 * One POTA activation row for the browser list. Wraps the Rust
 * [FfiActivationRollup] — a `(park, operator, UTC-day)` group with QSO counts —
 * and carries the stable detail key the detail screen re-derives its query from.
 */
data class ActivationRow(
    val rollup: FfiActivationRollup,
) {
    val park: String get() = rollup.park
    val callsign: String get() = rollup.operatorCallsign
    /** "YYYY-MM-DD" UTC day, exactly as the Rust rollup's `strftime` emits it. */
    val utcDate: String get() = rollup.utcDate
    val qsoCount: Long get() = rollup.totalQsos
    val uniqueQsos: Long get() = rollup.uniqueQsos

    /** Stable key encoding the activation identity for detail navigation. */
    val key: String get() = "$park|$callsign|$utcDate"
}

/** UI state for the activation browser list. */
data class ActivationsUiState(
    val loaded: Boolean = false,
    val activations: List<ActivationRow> = emptyList(),
    /** Multi-select mode for bulk ADIF export; keys of the selected rows. */
    val selectionMode: Boolean = false,
    val selectedKeys: Set<String> = emptySet(),
    /** True while a bulk ADIF export is running. */
    val exporting: Boolean = false,
    val error: String? = null,
)

/**
 * The Android analog of iOS `POTAActivationsView`: enumerates POTA activations
 * from the shared Rust store via [FieldStore.qsoActivationRollup] — the one
 * "distinct activations with counts" query, which buckets QSOs by
 * `(park, operator, UTC-day)` in SQL (no client-side aggregation over the full
 * QSO table). Sorted newest-first for display.
 *
 * Part 1 (this task) shows the list + detail + timeline; upload status,
 * jobs/awards, conditions, and export are Phase D Task 11.
 */
class ActivationsViewModel(
    private val store: FieldStore,
    private val adifApi: AdifApi,
) : ViewModel() {

    private val _ui = MutableStateFlow(ActivationsUiState())
    val ui: StateFlow<ActivationsUiState> = _ui.asStateFlow()

    init {
        refresh()
    }

    fun refresh() = viewModelScope.launch {
        val result = withContext(Dispatchers.IO) {
            runCatching {
                // Empty query = every activation; min_qsos=1 so every group counts
                // as "successful" (POTA's 10-QSO rule is surfaced in Task 11).
                store.qsoActivationRollup("", MIN_QSOS)
            }
        }
        result
            .onSuccess { rollups ->
                // Newest first: rollup rows arrive sorted by park/day; re-sort by
                // the UTC-day string (lexical sort works for YYYY-MM-DD), then park.
                val rows = rollups
                    .map(::ActivationRow)
                    .sortedWith(compareByDescending<ActivationRow> { it.utcDate }.thenBy { it.park })
                _ui.update { it.copy(loaded = true, activations = rows, error = null) }
            }
            .onFailure { err ->
                AppLog.add(AppLog.Level.ERROR, "activation list load failed: ${err.cwMessage()}")
                _ui.update { it.copy(loaded = true, error = err.cwMessage()) }
            }
    }

    /** Enter/exit multi-select mode. Exiting clears the selection. */
    fun setSelectionMode(on: Boolean) {
        _ui.update { it.copy(selectionMode = on, selectedKeys = if (on) it.selectedKeys else emptySet()) }
    }

    fun toggleSelection(key: String) {
        _ui.update {
            val next = it.selectedKeys.toMutableSet().apply { if (!add(key)) remove(key) }
            it.copy(selectedKeys = next)
        }
    }

    /**
     * Export every selected activation to one combined ADIF `.adi` file and fire
     * a share chooser — the "combined" mode of iOS's `BulkADIFExportSheet`
     * ([AdifApi.exportBulk]). Runs the Rust writer + file write on
     * [Dispatchers.IO]; [context] is the hosting Activity. No-op on an empty
     * selection.
     */
    fun exportSelected(context: Context) = viewModelScope.launch {
        val selected = _ui.value.activations.filter { it.key in _ui.value.selectedKeys }
        if (selected.isEmpty()) return@launch
        _ui.update { it.copy(exporting = true, error = null) }
        runCatching {
            withContext(Dispatchers.IO) {
                val refs = selected.map {
                    FfiAdifBulkActivationRef(
                        parkReference = it.park,
                        // Park name isn't carried on the rollup; the Rust writer
                        // tolerates a null MY_SIG_INFO name (park ref is enough).
                        parkName = null,
                        callsign = it.callsign,
                        date = it.utcDate,
                    )
                }
                val adif = adifApi.exportBulk(refs, BuildConfig.VERSION_NAME)
                writeShareBytes(context, adif.toByteArray(Charsets.UTF_8), "activations-${selected.size}.adi")
            }
        }.onSuccess { uri ->
            _ui.update { it.copy(exporting = false, selectionMode = false, selectedKeys = emptySet()) }
            if (uri != null) {
                shareTextFileUri(context, uri, "Export Activations ADIF")
            } else {
                _ui.update { it.copy(error = "Failed to prepare ADIF file") }
            }
        }.onFailure { err ->
            AppLog.add(AppLog.Level.ERROR, "bulk ADIF export failed: ${err.cwMessage()}")
            _ui.update { it.copy(exporting = false, error = err.cwMessage()) }
        }
    }

    companion object {
        private const val MIN_QSOS = 1L

        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                ActivationsViewModel(app.store, app.adifApi)
            }
        }
    }
}
