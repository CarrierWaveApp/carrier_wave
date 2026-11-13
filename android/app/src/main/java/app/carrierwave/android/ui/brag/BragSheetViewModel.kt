package app.carrierwave.android.ui.brag

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.BragSheetApi
import uniffi.cw_ffi.FfiBragCategoryMeta
import uniffi.cw_ffi.FfiBragConfiguration
import uniffi.cw_ffi.FfiBragPeriod
import uniffi.cw_ffi.FfiBragPreset
import uniffi.cw_ffi.FfiBragPresetInfo
import uniffi.cw_ffi.FfiBragStatMeta
import uniffi.cw_ffi.FfiBragStatResult
import uniffi.cw_ffi.FfiBragStatType

data class BragSheetUiState(
    val loading: Boolean = true,
    val catalog: List<FfiBragStatMeta> = emptyList(),
    val categories: List<FfiBragCategoryMeta> = emptyList(),
    val presets: List<FfiBragPresetInfo> = emptyList(),
    val configuration: FfiBragConfiguration? = null,
    val period: FfiBragPeriod = FfiBragPeriod.ALL_TIME,
    val results: List<FfiBragStatResult> = emptyList(),
    val error: String? = null,
)

/**
 * Drives the Android brag sheet + customize screens over the shared Rust
 * [BragSheetApi]. All FFI calls run on [Dispatchers.IO] — the API touches the
 * SQLCipher-backed store (kv reads/writes + QSO aggregates), which blocks and
 * would ANR on the main thread.
 */
class BragSheetViewModel(
    private val api: BragSheetApi,
    private val appContext: Context,
) : ViewModel() {

    private val _state = MutableStateFlow(BragSheetUiState())
    val state: StateFlow<BragSheetUiState> = _state.asStateFlow()

    init {
        load()
    }

    /** Loads catalog/categories/presets/config once, then computes the current period. */
    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            runCatching {
                withContext(Dispatchers.IO) {
                    val catalog = api.catalog()
                    val categories = api.categories()
                    val presets = api.presets()
                    val config = api.loadConfig()
                    Triple(catalog, categories, presets) to config
                }
            }.onSuccess { (meta, config) ->
                val (catalog, categories, presets) = meta
                _state.update {
                    it.copy(
                        loading = false,
                        catalog = catalog,
                        categories = categories,
                        presets = presets,
                        configuration = config,
                    )
                }
                computeBrag()
            }.onFailure { e ->
                _state.update { it.copy(loading = false, error = e.message ?: "Failed to load brag sheet") }
            }
        }
    }

    /** Switches the displayed period and recomputes its stats. */
    fun selectPeriod(period: FfiBragPeriod) {
        _state.update { it.copy(period = period) }
        computeBrag()
    }

    /** Computes the enabled stats for the currently-selected period. */
    fun computeBrag() {
        val period = _state.value.period
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    api.computeBrag(period, System.currentTimeMillis() / 1_000L, useMetricUnits())
                }
            }.onSuccess { results ->
                _state.update { it.copy(results = results, error = null) }
            }.onFailure { e ->
                _state.update { it.copy(error = e.message ?: "Failed to compute brag sheet") }
            }
        }
    }

    /**
     * Resolves the metric/imperial preference for distance formatting.
     *
     * There is no dedicated units setting in the app yet. This reads a
     * `"useMetricUnits"` boolean from the shared `"cw"` prefs file if present
     * (future-proofing, and mirrors the iOS `UserDefaults` key of the same
     * name), and otherwise falls back to the device locale's country: US,
     * Liberia, and Myanmar default to imperial; everywhere else defaults to
     * metric.
     */
    private fun useMetricUnits(): Boolean {
        val prefs = appContext.getSharedPreferences("cw", Context.MODE_PRIVATE)
        val defaultFromLocale = java.util.Locale.getDefault().country !in IMPERIAL_LOCALE_COUNTRIES
        return prefs.getBoolean("useMetricUnits", defaultFromLocale)
    }

    /**
     * Applies a curated preset to one period's config via the shared Rust
     * `BragSheetApi.applyPreset`, persists, and recomputes. All seven
     * presets now share the exact Rust logic (parity with iOS) rather than
     * the earlier `ShowEverything`-only fallback.
     */
    fun applyPreset(preset: FfiBragPreset, period: FfiBragPeriod) {
        val config = _state.value.configuration ?: return
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) { api.applyPreset(config, preset, period) }
            }.onSuccess { newConfig ->
                mutateConfig(newConfig)
            }.onFailure { e ->
                _state.update { it.copy(error = e.message ?: "Failed to apply preset") }
            }
        }
    }

    /** Copies one period's config onto another via the shared Rust logic. */
    fun copyPeriodConfig(from: FfiBragPeriod, to: FfiBragPeriod) {
        val config = _state.value.configuration ?: return
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) { api.copyPeriodConfig(config, from, to) }
            }.onSuccess { newConfig ->
                mutateConfig(newConfig)
            }.onFailure { e ->
                _state.update { it.copy(error = e.message ?: "Failed to copy config") }
            }
        }
    }

    /** Toggles a stat's enabled state within one period's config. */
    fun toggleStat(stat: FfiBragStatType, period: FfiBragPeriod) {
        val config = _state.value.configuration ?: return
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) { api.toggleStat(config, stat, period) }
            }.onSuccess { newConfig ->
                mutateConfig(newConfig)
            }.onFailure { e ->
                _state.update { it.copy(error = e.message ?: "Failed to toggle stat") }
            }
        }
    }

    /** Toggles a stat's hero status within one period's config; caps at 4 heroes. */
    fun toggleHero(stat: FfiBragStatType, period: FfiBragPeriod) {
        val config = _state.value.configuration ?: return
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) { api.toggleHeroStat(config, stat, period) }
            }.onSuccess { newConfig ->
                mutateConfig(newConfig)
            }.onFailure { e ->
                _state.update { it.copy(error = e.message ?: "Failed to toggle hero stat") }
            }
        }
    }

    /** Moves a stat within one period's enabled-stat order. */
    fun moveStat(period: FfiBragPeriod, from: UInt, to: UInt) {
        val config = _state.value.configuration ?: return
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) { api.moveStat(config, period, from, to) }
            }.onSuccess { newConfig ->
                mutateConfig(newConfig)
            }.onFailure { e ->
                _state.update { it.copy(error = e.message ?: "Failed to reorder stat") }
            }
        }
    }

    /** Flips one of the three top-level configuration switches. */
    fun setIncludeMap(value: Boolean) {
        val config = _state.value.configuration ?: return
        mutateConfig(config.copy(includeMap = value))
    }

    fun setIncludeEquipmentSummary(value: Boolean) {
        val config = _state.value.configuration ?: return
        mutateConfig(config.copy(includeEquipmentSummary = value))
    }

    fun setGoldRecordBadges(value: Boolean) {
        val config = _state.value.configuration ?: return
        mutateConfig(config.copy(goldRecordBadges = value))
    }

    /** Applies an in-memory config change, then persists + recomputes. */
    private fun mutateConfig(newConfig: FfiBragConfiguration) {
        _state.update { it.copy(configuration = newConfig) }
        saveConfig()
    }

    /** Persists the current in-memory configuration to the shared store. */
    fun saveConfig() {
        val config = _state.value.configuration ?: return
        viewModelScope.launch {
            runCatching {
                withContext(Dispatchers.IO) { api.saveConfig(config) }
            }.onFailure { e ->
                _state.update { it.copy(error = e.message ?: "Failed to save brag sheet config") }
            }
            computeBrag()
        }
    }

    companion object {
        /** Locale countries that default to imperial units absent an explicit preference. */
        private val IMPERIAL_LOCALE_COUNTRIES = setOf("US", "LR", "MM")

        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                BragSheetViewModel(BragSheetApi(app.store), app.applicationContext)
            }
        }
    }
}
