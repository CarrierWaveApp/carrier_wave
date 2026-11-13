package app.carrierwave.android.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.cw_ffi.FfiSpotEngineConfig
import uniffi.cw_ffi.FfiSpotSource
import uniffi.cw_ffi.SpotEngineApi
import uniffi.cw_ffi.SpotEngineListener

/**
 * Owns the process-wide Rust [SpotEngineApi]: builds it on first use with the
 * enabled-source configuration, feeds host-side context (operator grid +
 * callsign, cached CTY.dat), and pauses/resumes the poll loop across app
 * lifecycle transitions. Kotlin port of iOS `SpotEngineProvider`.
 *
 * The engine holds ONE listener slot, so this provider owns it and publishes
 * each generation bump through [generation]; collectors re-read
 * [SpotEngineApi.snapshot] rather than receiving pushed arrays.
 */
class SpotEngineProvider(
    private val scope: CoroutineScope,
    private var activitiesBaseUrl: String,
    private var callsign: String,
    private var homeGrid: String,
    /** JSON file persisting the per-callsign enrichment cache across launches. */
    private val enrichmentCachePath: String,
    /** Supplies the cached raw CTY.dat text (EnrichmentApi's kv cache). */
    private val ctySupplier: suspend () -> String?,
) {

    private val generationFlow = MutableStateFlow(0uL)

    /** Bumped after every engine publish (poll cycle / cluster spot). */
    val generation: StateFlow<ULong> = generationFlow.asStateFlow()

    /** Engine construction failure, surfaced in the Spots tab. */
    @Volatile
    var lastError: String? = null
        private set

    @Volatile
    private var built: SpotEngineApi? = null

    @Volatile
    private var started = false

    private val listener = object : SpotEngineListener {
        // Callbacks arrive on Rust worker threads; StateFlow writes are thread-safe.
        override fun onSpotsUpdated(generation: ULong) {
            generationFlow.value = generation
        }

        // Android has no cluster terminal view and no cluster connection yet.
        override fun onClusterLine(line: String) {}

        override fun onClusterState(connected: Boolean) {}
    }

    /** The engine, built on first use. Null only when the Rust core fails to init. */
    @Synchronized
    fun engine(): SpotEngineApi? {
        built?.let { return it }
        return try {
            val engine = SpotEngineApi(currentConfig())
            engine.setUserContext(homeGrid.ifBlank { null }, callsign)
            built = engine
            feedCty()
            // Loads the persisted cache file — off the caller's thread,
            // since engine() can be hit from Main.
            scope.launch(Dispatchers.IO) {
                engine.setEnrichmentCachePath(enrichmentCachePath)
            }
            engine
        } catch (e: Exception) {
            lastError = e.message ?: "spot engine failed to initialize"
            null
        }
    }

    /**
     * Start the poll loop once a screen actually watches spots. Idempotent —
     * the engine keeps running for the process lifetime, paused while the app
     * is backgrounded (matching iOS, where the engine runs while observed).
     */
    fun startIfNeeded() {
        val engine = engine() ?: return
        synchronized(this) {
            if (started) return
            started = true
        }
        scope.launch { engine.start(listener) }
    }

    /** Operator grid + callsign — distance origin + self-spot detection. */
    fun updateUserContext(callsign: String, homeGrid: String) {
        this.callsign = callsign
        this.homeGrid = homeGrid
        built?.setUserContext(homeGrid.ifBlank { null }, callsign)
    }

    /** Re-point the RBN proxy at a new activities server. */
    fun updateBaseUrl(url: String) {
        activitiesBaseUrl = url
        built?.setConfig(currentConfig())
    }

    /**
     * Push the cached CTY.dat into the engine for DXCC resolution. Called on
     * build and again after `EnrichmentApi.refresh()` lands a fresh download
     * (first launch builds the engine before the download finishes).
     */
    fun feedCty() {
        val engine = built ?: return
        scope.launch {
            runCatching { ctySupplier() }.getOrNull()?.let { engine.setCtyDatabase(it) }
        }
    }

    /** App backgrounded: skip poll ticks without tearing anything down. */
    fun pause() {
        built?.pause()
    }

    /** App foregrounded: resume polling and refresh immediately. */
    fun resume() {
        val engine = built ?: return
        engine.resume()
        if (started) scope.launch { engine.refresh() }
    }

    /**
     * Enabled sources = the classic hunter four. The DX-web trio, PSK
     * Reporter, and the telnet cluster stay off until Android grows the
     * filter UI for them. Poll cadence matches iOS (120 s), not Sweep (30 s).
     */
    private fun currentConfig() = FfiSpotEngineConfig(
        activitiesBaseUrl = activitiesBaseUrl,
        enabledSources = listOf(
            FfiSpotSource.RBN,
            FfiSpotSource.POTA,
            FfiSpotSource.SOTA,
            FfiSpotSource.WWFF,
        ),
        pollIntervalSecs = 120u,
        maxSpotAgeSecs = 1_800u,
        rbnLimit = 100u,
        sotaCount = 50u,
        dxWebLimit = 50u,
    )
}
