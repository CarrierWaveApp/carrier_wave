package app.carrierwave.android.ui.external

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import app.carrierwave.android.ui.common.cwMessage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.AuthApi
import uniffi.cw_ffi.ContestApi
import uniffi.cw_ffi.ReferenceDataApi
import uniffi.cw_ffi.ScpApi

/** The datasets the External Data card manages, in iOS section order. */
enum class ExternalDataset(val label: String, val unit: String) {
    FCC("FCC Callsigns", "callsigns"),
    SCP("Super Check Partial", "callsigns"),
    EQUIPMENT("Equipment Catalog", "entries"),
    POTA("POTA Parks", "parks"),
    SOTA("SOTA Summits", "summits"),
    SOTA_ZONES("SOTA Activation Zones", "zones"),
    WWFF("WWFF Directory", "references"),
    CONTESTS("Contest Definitions", "contests"),
}

/** One dataset row's UI state. */
data class DatasetUi(
    val count: Long = 0,
    /** Unix seconds of the last successful refresh/check. */
    val fetchedAt: Long? = null,
    val busy: Boolean = false,
    val error: String? = null,
    /** Extra status line (SOTA zones "N still computing…"). */
    val note: String? = null,
)

data class ExternalDataUiState(
    val rows: Map<ExternalDataset, DatasetUi> = ExternalDataset.entries.associateWith { DatasetUi() },
    val downloadingAll: Boolean = false,
)

/**
 * Drives the External Data card entirely through the shared Rust APIs —
 * [ReferenceDataApi] for the six new datasets plus the existing [ScpApi]
 * and [ContestApi]. The Android counterpart of iOS `ExternalDataView`.
 */
class ExternalDataViewModel(
    private val referenceData: ReferenceDataApi,
    private val scpApi: ScpApi,
    private val contestApi: ContestApi,
    private val authApi: AuthApi,
) : ViewModel() {

    private val _state = MutableStateFlow(ExternalDataUiState())
    val state: StateFlow<ExternalDataUiState> = _state.asStateFlow()

    init {
        reloadStatuses()
    }

    /** Refresh one dataset (always force — the button is user-intent). */
    fun refresh(dataset: ExternalDataset) {
        viewModelScope.launch { runRefresh(dataset) }
    }

    /** iOS "Download All Sources" — every dataset in parallel. */
    fun downloadAll() {
        viewModelScope.launch {
            _state.update { it.copy(downloadingAll = true) }
            ExternalDataset.entries.map { dataset ->
                launch { runRefresh(dataset) }
            }.joinAll()
            _state.update { it.copy(downloadingAll = false) }
        }
    }

    private suspend fun runRefresh(dataset: ExternalDataset) {
        setRow(dataset) { it.copy(busy = true, error = null) }
        val result = withContext(Dispatchers.IO) {
            runCatching {
                when (dataset) {
                    ExternalDataset.FCC -> referenceData.refreshFcc(force = true)
                    ExternalDataset.SCP -> scpApi.refresh(force = true)
                    ExternalDataset.EQUIPMENT ->
                        referenceData.refreshEquipmentCatalog(bearerToken(), force = true)
                    ExternalDataset.POTA -> referenceData.refreshPotaParks(force = true)
                    ExternalDataset.SOTA -> referenceData.refreshSotaSummits(force = true)
                    ExternalDataset.SOTA_ZONES -> referenceData.refreshSotaZones()
                    ExternalDataset.WWFF -> referenceData.refreshWwffDirectory(force = true)
                    ExternalDataset.CONTESTS -> contestApi.refresh()
                }
            }
        }
        result.onFailure { err ->
            setRow(dataset) { it.copy(busy = false, error = err.cwMessage()) }
        }
        result.onSuccess {
            setRow(dataset) { it.copy(busy = false) }
            reloadStatuses()
        }
    }

    /** OAuth bearer for the equipment catalog when signed in (iOS parity). */
    private suspend fun bearerToken(): String? =
        if (authApi.hasSession()) runCatching { authApi.validAccessToken() }.getOrNull() else null

    /** Pull counts + freshness for every dataset off the Rust APIs. */
    private fun reloadStatuses() = viewModelScope.launch {
        val snapshot = withContext(Dispatchers.IO) {
            runCatching {
                val status = referenceData.status()
                val scpCount = scpApi.database()?.count()?.toLong() ?: 0L
                val scpFetchedAt = scpApi.fetchedAt()
                val contests = contestApi.summaries()
                Snapshot(
                    mapOf(
                        ExternalDataset.FCC to DatasetUi(
                            status.fccCallsigns.count,
                            status.fccCallsigns.fetchedAt,
                        ),
                        ExternalDataset.SCP to DatasetUi(scpCount, scpFetchedAt),
                        ExternalDataset.EQUIPMENT to DatasetUi(
                            status.equipmentEntries.count,
                            status.equipmentEntries.fetchedAt,
                        ),
                        ExternalDataset.POTA to DatasetUi(
                            status.potaParks.count,
                            status.potaParks.fetchedAt,
                        ),
                        ExternalDataset.SOTA to DatasetUi(
                            status.sotaSummits.count,
                            status.sotaSummits.fetchedAt,
                        ),
                        ExternalDataset.SOTA_ZONES to DatasetUi(
                            status.sotaZones.count,
                            status.sotaZones.fetchedAt,
                            note = status.sotaZonesPending.takeIf { it > 0 }?.let {
                                "$it still computing on server — refresh again later"
                            },
                        ),
                        ExternalDataset.WWFF to DatasetUi(
                            status.wwffReferences.count,
                            status.wwffReferences.fetchedAt,
                        ),
                        ExternalDataset.CONTESTS to DatasetUi(
                            contests.size.toLong(),
                            contests.minOfOrNull { it.lastSyncedAt },
                        ),
                    ),
                )
            }.getOrNull()
        } ?: return@launch
        _state.update { current ->
            current.copy(
                rows = current.rows.mapValues { (dataset, row) ->
                    val fresh = snapshot.rows[dataset] ?: return@mapValues row
                    // Keep transient per-row state (busy/error) across reloads.
                    fresh.copy(busy = row.busy, error = row.error)
                },
            )
        }
    }

    private fun setRow(dataset: ExternalDataset, transform: (DatasetUi) -> DatasetUi) {
        _state.update { current ->
            val row = current.rows[dataset] ?: DatasetUi()
            current.copy(rows = current.rows + (dataset to transform(row)))
        }
    }

    private data class Snapshot(val rows: Map<ExternalDataset, DatasetUi>)

    companion object {
        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                ExternalDataViewModel(app.referenceDataApi, app.scpApi, app.contestApi, app.authApi)
            }
        }
    }
}
