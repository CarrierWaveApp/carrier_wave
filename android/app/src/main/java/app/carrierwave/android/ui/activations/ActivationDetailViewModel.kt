package app.carrierwave.android.ui.activations

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import android.content.Context
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
import uniffi.cw_ffi.FfiActivationMetadata
import uniffi.cw_ffi.FfiMapFilter
import uniffi.cw_ffi.FfiQso
import uniffi.cw_ffi.FfiQsoMapData
import uniffi.cw_ffi.FieldStore
import uniffi.cw_ffi.MapApi
import java.time.LocalDate
import java.time.ZoneOffset

/** Header stats for one activation, mirroring iOS `ActivationStatsSummaryView`. */
data class ActivationStats(
    val qsoCount: Int = 0,
    /** Wall-clock span first→last QSO in the day, in seconds (iOS's duration). */
    val durationSeconds: Long = 0,
    /** Distinct bands worked, in band order (iOS `uniqueBands`). */
    val bands: List<String> = emptyList(),
    /** Distinct modes worked (iOS `uniqueModes`). */
    val modes: List<String> = emptyList(),
)

/** UI state for the activation detail. */
data class ActivationDetailUiState(
    val loaded: Boolean = false,
    val qsos: List<FfiQso> = emptyList(),
    val stats: ActivationStats = ActivationStats(),
    val mapData: FfiQsoMapData? = null,
    /** Resolved park name from the reference table (null if unknown). */
    val parkName: String? = null,
    /** Recorded solar/weather metadata for this activation, if any (drives the Conditions sheet). */
    val conditions: FfiActivationMetadata? = null,
    /** True while a single-activation ADIF export is running. */
    val exporting: Boolean = false,
    val error: String? = null,
)

/**
 * Post-activation detail — the Android analog of the iOS activation detail
 * (header stats + map + QSO timeline). An activation is a `(park, callsign,
 * UTC-day)` group; there is no session-id to key off. The timeline + header
 * stats pull the QSOs via [FieldStore.fetchActivationQsos], which scopes on the
 * operator's own callsign too (matching iOS's activation key), so two of the
 * user's own callsigns at the same park on the same day stay separate; it also
 * guarantees hidden/metadata rows are excluded.
 *
 * The map card is built from the park+day window over [MapApi.qsoMap] (the Phase
 * A/B QSO-map surface — session maps key on a session id, which activations
 * lack). [FfiMapFilter] has no callsign field, so on a shared day the map blends
 * the user's own callsigns while the list/stats stay callsign-scoped — cosmetic,
 * tracked as a Phase D follow-up.
 *
 * Part 1 shows stats + map + timeline. Awards / conditions / export attach in
 * Phase D Task 11.
 */
class ActivationDetailViewModel(
    val park: String,
    val callsign: String,
    /** "YYYY-MM-DD" UTC day, matching the rollup's `strftime` output. */
    val utcDate: String,
    private val store: FieldStore,
    private val adifApi: AdifApi,
    val mapApi: MapApi,
    val homeGrid: String,
) : ViewModel() {

    private val _ui = MutableStateFlow(ActivationDetailUiState())
    val ui: StateFlow<ActivationDetailUiState> = _ui.asStateFlow()

    /** UTC-day bounds in Unix seconds for the map filter's date window. */
    private val dayStart: Long = LocalDate.parse(utcDate).atStartOfDay(ZoneOffset.UTC).toEpochSecond()
    private val dayEnd: Long = dayStart + SECONDS_PER_DAY

    init {
        refresh()
    }

    fun refresh() = viewModelScope.launch {
        val result = withContext(Dispatchers.IO) {
            runCatching {
                // Callsign-scoped: (park, own callsign, UTC-day), hidden/metadata
                // excluded by the store. Matches iOS's `POTAActivation` grouping
                // key (which bakes in myCallsign) — a bare park:+date: DSL query
                // would blend two of the user's own callsigns on a shared day.
                val qsos = adifApi.fetchActivationQsos(park, callsign, utcDate)
                // The map card silently omits itself on failure — never let a map
                // error blank the whole detail (parity with SessionMapCard). The
                // filter has no callsign field, so on a shared day the map blends
                // the user's own callsigns (cosmetic; tracked). See class doc.
                val map = runCatching {
                    mapApi.qsoMap(
                        FfiMapFilter(
                            band = null,
                            mode = null,
                            park = park,
                            startDate = dayStart,
                            endDate = dayEnd,
                            confirmedOnly = false,
                            showIndividual = true,
                            showPaths = true,
                            maxQsos = null,
                        ),
                    )
                }.getOrNull()
                // Park name (reference table) + recorded conditions metadata,
                // both best-effort — a missing park row or no metadata must not
                // fail the detail load, so each is caught independently. Conditions
                // are keyed by (park, UTC-day-start-epoch), matching the metadata store.
                val parkName = runCatching { store.fetchPotaPark(park)?.name?.takeIf { it.isNotBlank() } }.getOrNull()
                val conditions = runCatching { store.fetchActivationMetadata(park, dayStart) }.getOrNull()
                LoadResult(qsos, map, parkName, conditions)
            }
        }
        result
            .onSuccess { data ->
                _ui.update {
                    it.copy(
                        loaded = true,
                        qsos = data.qsos,
                        stats = computeStats(data.qsos),
                        mapData = data.map,
                        parkName = data.parkName,
                        conditions = data.conditions,
                        error = null,
                    )
                }
            }
            .onFailure { err ->
                AppLog.add(AppLog.Level.ERROR, "activation detail load failed: ${err.cwMessage()}")
                _ui.update { it.copy(loaded = true, error = err.cwMessage()) }
            }
    }

    /**
     * Export this activation to an ADIF `.adi` file and fire a share chooser.
     * The Rust writer ([AdifApi.exportActivation]) resolves the same
     * `(park, callsign, UTC-day)` scope on [Dispatchers.IO]; the file write +
     * chooser are the shared `ui/share` plumbing. [context] is the hosting
     * Activity.
     */
    fun exportAdif(context: Context) = viewModelScope.launch {
        _ui.update { it.copy(exporting = true, error = null) }
        val parkName = _ui.value.parkName
        runCatching {
            withContext(Dispatchers.IO) {
                val adif = adifApi.exportActivation(park, parkName, callsign, utcDate, BuildConfig.VERSION_NAME)
                val fileName = "${park}_${callsign}_$utcDate.adi".replace('/', '-')
                writeShareBytes(context, adif.toByteArray(Charsets.UTF_8), fileName)
            }
        }.onSuccess { uri ->
            _ui.update { it.copy(exporting = false) }
            if (uri != null) {
                shareTextFileUri(context, uri, "Export Activation ADIF")
            } else {
                _ui.update { it.copy(error = "Failed to prepare ADIF file") }
            }
        }.onFailure { err ->
            AppLog.add(AppLog.Level.ERROR, "activation ADIF export failed: ${err.cwMessage()}")
            _ui.update { it.copy(exporting = false, error = err.cwMessage()) }
        }
    }

    /** Snapshot of everything loaded for the detail screen in one IO pass. */
    private data class LoadResult(
        val qsos: List<FfiQso>,
        val map: FfiQsoMapData?,
        val parkName: String?,
        val conditions: FfiActivationMetadata?,
    )

    companion object {
        private const val SECONDS_PER_DAY = 86_400L

        /** iOS band ordering for the bands breakdown (high freq → low). */
        private val BAND_ORDER = listOf(
            "6m", "10m", "12m", "15m", "17m", "20m", "30m", "40m", "60m", "80m", "160m",
        )

        private fun computeStats(qsos: List<FfiQso>): ActivationStats {
            if (qsos.isEmpty()) return ActivationStats()
            val dates = qsos.map { it.qsoDate }
            val duration = (dates.max() - dates.min()).coerceAtLeast(0)
            val bands = qsos.mapNotNull { it.band?.takeIf(String::isNotBlank) }.distinct()
                .sortedBy { band -> BAND_ORDER.indexOf(band.lowercase()).let { if (it < 0) Int.MAX_VALUE else it } }
            val modes = qsos.mapNotNull { it.mode?.takeIf(String::isNotBlank) }.distinct().sorted()
            return ActivationStats(
                qsoCount = qsos.size,
                durationSeconds = duration,
                bands = bands,
                modes = modes,
            )
        }

        fun factory(park: String, callsign: String, utcDate: String) = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                ActivationDetailViewModel(park, callsign, utcDate, app.store, app.adifApi, app.mapApi, app.userHomeGrid)
            }
        }
    }
}
