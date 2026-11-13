package app.carrierwave.android.ui.parks

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.carrierwave.android.CwApp
import app.carrierwave.android.util.AppLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.cw_ffi.FfiBoundingBox
import uniffi.cw_ffi.FfiGeoBoundary
import uniffi.cw_ffi.FfiMultiplierCandidate
import uniffi.cw_ffi.FfiParkPin
import uniffi.cw_ffi.FfiRefSearchHit
import uniffi.cw_ffi.ParkMapApi

/** Rows-per-kind cap passed through to `pinsInBox`; Rust applies this value
 * as-is rather than enforcing its own separate limit, so this constant is the
 * operative cap on how many park/summit pins load per viewport. */
private const val PINS_LIMIT_PER_KIND = 500L
private const val SEARCH_LIMIT_PER_KIND = 10L
private const val REGION_DEBOUNCE_MS = 500L

/** Fetch limits — same defaults `ParkMapApi` documents for parks/trails/admin. */
private const val BOUNDARY_FETCH_LIMIT = 50L
private const val TRAIL_FETCH_LIMIT = 50L
private const val ADMIN_FETCH_LIMIT = 500L

/** Zoom gates (viewport lat span, degrees) — iOS parity, see
 * `ParkSearchMapView+AdminBoundaries.swift`/`+SotaZones.swift`/`+WWFF.swift`. */
private const val BOUNDARY_TRAIL_MAX_SPAN = 5.0
private const val ADMIN_COUNTY_SPAN_GATE = 6.0
private const val ADMIN_MAX_SPAN = 60.0
private const val SOTA_ZONE_SPAN_GATE = 0.5
private const val WWFF_SPAN_GATE = 1.0

private const val MAX_ZONE_SUMMITS_PER_REQUEST = 250
private const val MAX_WWFF_PER_FETCH = 40
private const val MAX_CACHED_BOUNDARIES = 150
private const val MAX_CACHED_TRAILS = 100
private const val MAX_CACHED_ADMIN = 800
private const val MAX_CACHED_ZONES = 400
private const val MAX_CACHED_WWFF = 300

/** Max summits scanned for multiplier overlaps (viewport-bounded) — iOS parity,
 * see `ParkSearchMapView+Multipliers.swift` `maxMultiplierSummits`. */
private const val MAX_MULTIPLIER_SUMMITS = 800

/** Which optional overlay layers are currently toggled on. Boundaries/pins
 * default on (parity with the pre-Task-12 screen); every activity-layer
 * extra (zones/admin/WWFF/grids/tiles) defaults off, same as iOS's
 * `.activityLayers`-gated toggles. */
data class ParkMapLayers(
    val boundaries: Boolean = true,
    val trails: Boolean = false,
    val sotaZones: Boolean = false,
    val wwff: Boolean = false,
    val states: Boolean = false,
    val counties: Boolean = false,
    val gridSquares: Boolean = false,
    val totaTiles: Boolean = false,
)

data class ParkSearchUiState(
    val pins: List<FfiParkPin> = emptyList(),
    val loadingPins: Boolean = false,
    val pinsError: String? = null,
    val query: String = "",
    val searchResults: List<FfiRefSearchHit> = emptyList(),
    val searching: Boolean = false,
    val searchError: String? = null,
    val selectedPin: FfiParkPin? = null,
    val selectedBoundary: FfiGeoBoundary? = null,
    val layers: ParkMapLayers = ParkMapLayers(),
    // Keyed by `FfiGeoBoundary.reference` — merge-and-evict caches, same shape
    // as iOS's `boundariesByRef`/`trailsByRef`/`sotaZonesByCode`/`wwffByCode`.
    val boundaries: Map<String, FfiGeoBoundary> = emptyMap(),
    val trails: Map<String, FfiGeoBoundary> = emptyMap(),
    val sotaZones: Map<String, FfiGeoBoundary> = emptyMap(),
    val adminBoundaries: Map<String, FfiGeoBoundary> = emptyMap(),
    val wwffBoundaries: Map<String, FfiGeoBoundary> = emptyMap(),
    // Raw WWFF (`kind == "wwff"`) reference pins for the viewport — fetched
    // only while the WWFF layer is on (`pinsInBox` supports a `"wwff"` kind
    // separate from park/summit; mixing it into the main pins fetch would
    // dump WWFF dots onto the clustered park/summit pin layer).
    val wwffPins: List<FfiParkPin> = emptyList(),
    val lastRegion: FfiBoundingBox? = null,
    // Rosette multiplier-finder sheet state.
    val showMultipliersSheet: Boolean = false,
    val multiplierCandidates: List<FfiMultiplierCandidate> = emptyList(),
    val findingMultipliers: Boolean = false,
)

/**
 * Park/summit search screen — Rust `ParkMapApi` view-model. Pins are fetched
 * per viewport (bbox-scoped, all zoom levels, no zoom-span guard — a capped
 * subset clusters fine when zoomed out, matching the iOS parity decision).
 * Search issues two calls (park + summit) with a per-kind floor so one kind
 * can't starve the other in a combined limit.
 *
 * Overlay layers (park/trail boundaries, admin state/county, SOTA zones, WWFF
 * borrowed polygons) are additional cache-through fetchers on the same
 * `ParkMapApi`, gated behind the same zoom-span thresholds iOS uses
 * (`ParkSearchMapView+AdminBoundaries.swift` / `+SotaZones.swift` /
 * `+WWFF.swift`) and debounced the same 500ms as the pins fetch. Every FFI
 * call runs on `Dispatchers.IO` — the shared store is SQLCipher-backed and
 * some of these calls hit the network, so keeping them off Main avoids ANRs.
 * Grid-square / TOTA tile geometry is computed by the renderer directly from
 * the viewport (no server round trip; see `ParkSearchScreen`'s grid overlay).
 */
@OptIn(FlowPreview::class)
class ParkSearchViewModel(private val parkMapApi: ParkMapApi) : ViewModel() {

    private val _state = MutableStateFlow(ParkSearchUiState())
    val state: StateFlow<ParkSearchUiState> = _state.asStateFlow()

    private val regionChannel = MutableSharedFlow<FfiBoundingBox>(extraBufferCapacity = 1)

    private var searchJob: Job? = null
    private var boundaryJob: Job? = null
    private var trailJob: Job? = null
    private var adminJob: Job? = null
    private var sotaZoneJob: Job? = null
    private var wwffJob: Job? = null
    private var multiplierJob: Job? = null

    init {
        viewModelScope.launch {
            regionChannel.debounce(REGION_DEBOUNCE_MS).collectLatest { bbox -> loadPins(bbox) }
        }
    }

    /** Called on every osmdroid `MapListener` region change; debounced internally.
     * Drives pins plus every enabled overlay layer fetch for the new viewport. */
    fun onRegionChanged(bbox: FfiBoundingBox) {
        _state.update { it.copy(lastRegion = bbox) }
        regionChannel.tryEmit(bbox)
        val layers = _state.value.layers
        if (layers.boundaries) fetchBoundaries(bbox)
        if (layers.trails) fetchTrails(bbox)
        if (layers.states || layers.counties) fetchAdmin(bbox)
        if (layers.sotaZones) fetchSotaZones(bbox)
        if (layers.wwff) fetchWwff(bbox)
    }

    private suspend fun loadPins(bbox: FfiBoundingBox) {
        _state.update { it.copy(loadingPins = true) }
        val result = withContext(Dispatchers.IO) {
            runCatching {
                parkMapApi.pinsInBox(bbox, listOf("park", "summit"), PINS_LIMIT_PER_KIND)
            }
        }
        result.fold(
            onSuccess = { pins -> _state.update { it.copy(pins = pins, loadingPins = false, pinsError = null) } },
            onFailure = { e ->
                AppLog.add(AppLog.Level.ERROR, "ParkSearch pinsInBox failed: ${e.message}")
                _state.update { it.copy(loadingPins = false, pinsError = e.message) }
            },
        )
    }

    fun onQueryChange(text: String) {
        _state.update { it.copy(query = text) }
        if (text.isBlank()) {
            searchJob?.cancel()
            _state.update { it.copy(searchResults = emptyList(), searching = false, searchError = null) }
            return
        }
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            // Debounce inline (search is user-typing driven, not region-driven);
            // a small delay here avoids firing on every keystroke.
            delay(300)
            runSearch(text)
        }
    }

    private suspend fun runSearch(query: String) {
        _state.update { it.copy(searching = true) }
        val result = withContext(Dispatchers.IO) {
            runCatching {
                // Two calls, one per kind — a combined limit would starve
                // whichever kind sorts second.
                val parks = parkMapApi.search(query, listOf("park"), SEARCH_LIMIT_PER_KIND)
                val summits = parkMapApi.search(query, listOf("summit"), SEARCH_LIMIT_PER_KIND)
                parks + summits
            }
        }
        result.fold(
            onSuccess = { hits -> _state.update { it.copy(searchResults = hits, searching = false, searchError = null) } },
            onFailure = { e ->
                AppLog.add(AppLog.Level.ERROR, "ParkSearch search failed: ${e.message}")
                _state.update { it.copy(searching = false, searchError = e.message) }
            },
        )
    }

    fun selectPin(pin: FfiParkPin?) = _state.update { it.copy(selectedPin = pin, selectedBoundary = null) }

    fun selectBoundary(boundary: FfiGeoBoundary?) = _state.update { it.copy(selectedBoundary = boundary, selectedPin = null) }

    /** Clears the search results/query after a result is tapped and the map centers on it. */
    fun clearSearch() = _state.update { it.copy(query = "", searchResults = emptyList()) }

    // MARK: - Layer toggles

    fun setLayer(update: (ParkMapLayers) -> ParkMapLayers) {
        val previous = _state.value.layers
        val next = update(previous)
        _state.update { it.copy(layers = next) }
        val bbox = _state.value.lastRegion ?: return
        // A toggle flipping on should fetch immediately for the current
        // viewport rather than waiting for the next pan/zoom.
        if (next.boundaries && !previous.boundaries) fetchBoundaries(bbox)
        if (next.trails && !previous.trails) fetchTrails(bbox)
        if ((next.states || next.counties) && !(previous.states || previous.counties)) fetchAdmin(bbox)
        if (next.sotaZones && !previous.sotaZones) fetchSotaZones(bbox)
        if (next.wwff && !previous.wwff) fetchWwff(bbox)
    }

    // MARK: - Park/trail boundaries

    private fun fetchBoundaries(bbox: FfiBoundingBox) {
        if (!withinSpan(bbox, BOUNDARY_TRAIL_MAX_SPAN)) return
        boundaryJob?.cancel()
        boundaryJob = viewModelScope.launch {
            delay(REGION_DEBOUNCE_MS)
            val known = _state.value.boundaries.keys
            val result = withContext(Dispatchers.IO) {
                runCatching { parkMapApi.parkBoundariesInBox(bbox, BOUNDARY_FETCH_LIMIT, simplifyTolerance(bbox)) }
            }
            result.fold(
                onSuccess = { fetched ->
                    val newOnes = fetched.filterNot { known.contains(it.reference) }
                    if (newOnes.isNotEmpty()) {
                        mergeBoundaries(newOnes)
                    }
                },
                onFailure = { e -> AppLog.add(AppLog.Level.ERROR, "Boundary fetch failed: ${e.message}") },
            )
        }
    }

    private fun mergeBoundaries(new: List<FfiGeoBoundary>) {
        _state.update { state ->
            state.copy(boundaries = mergeCache(state.boundaries, new, MAX_CACHED_BOUNDARIES) { it.reference })
        }
    }

    // MARK: - Trails

    private fun fetchTrails(bbox: FfiBoundingBox) {
        if (!withinSpan(bbox, BOUNDARY_TRAIL_MAX_SPAN)) return
        trailJob?.cancel()
        trailJob = viewModelScope.launch {
            delay(REGION_DEBOUNCE_MS)
            val result = withContext(Dispatchers.IO) {
                runCatching { parkMapApi.trailsInBox(bbox, TRAIL_FETCH_LIMIT, simplifyTolerance(bbox)) }
            }
            result.fold(
                onSuccess = { fetched ->
                    if (fetched.isNotEmpty()) {
                        _state.update { state ->
                            state.copy(trails = mergeCache(state.trails, fetched, MAX_CACHED_TRAILS) { it.reference })
                        }
                    }
                },
                onFailure = { e -> AppLog.add(AppLog.Level.ERROR, "Trail fetch failed: ${e.message}") },
            )
        }
    }

    // MARK: - Admin boundaries (state/county)

    private fun fetchAdmin(bbox: FfiBoundingBox) {
        val layers = _state.value.layers
        val wantStates = layers.states
        val wantCounties = layers.counties && withinSpan(bbox, ADMIN_COUNTY_SPAN_GATE)
        if (!wantStates && !wantCounties) return
        if (!withinSpan(bbox, ADMIN_MAX_SPAN)) return
        val kind: String? = if (wantStates && wantCounties) null else if (wantStates) "state" else "county"

        adminJob?.cancel()
        adminJob = viewModelScope.launch {
            delay(REGION_DEBOUNCE_MS)
            val known = _state.value.adminBoundaries.keys
            val result = withContext(Dispatchers.IO) {
                runCatching { parkMapApi.adminBoundariesInBox(bbox, kind, ADMIN_FETCH_LIMIT, simplifyTolerance(bbox)) }
            }
            result.fold(
                onSuccess = { fetched ->
                    val newOnes = fetched.filterNot { known.contains(it.reference) }
                    if (newOnes.isNotEmpty()) {
                        _state.update { state ->
                            state.copy(
                                adminBoundaries = mergeCache(state.adminBoundaries, newOnes, MAX_CACHED_ADMIN) { it.reference },
                            )
                        }
                    }
                },
                onFailure = { e -> AppLog.add(AppLog.Level.ERROR, "Admin boundary fetch failed: ${e.message}") },
            )
        }
    }

    // MARK: - SOTA activation zones

    private fun fetchSotaZones(bbox: FfiBoundingBox) {
        if (!withinSpan(bbox, SOTA_ZONE_SPAN_GATE)) return
        sotaZoneJob?.cancel()
        sotaZoneJob = viewModelScope.launch {
            delay(REGION_DEBOUNCE_MS)
            val known = _state.value.sotaZones.keys
            val codes = _state.value.pins
                .asSequence()
                .filter { it.kind == "summit" }
                .filter { inBox(it.latitude, it.longitude, bbox) }
                .map { nearestFirstKey(it, bbox) }
                .sortedBy { it.first }
                .map { it.second.reference }
                .filterNot { known.contains(it) }
                .take(MAX_ZONE_SUMMITS_PER_REQUEST)
                .toList()
            if (codes.isEmpty()) return@launch
            val result = withContext(Dispatchers.IO) {
                runCatching { parkMapApi.sotaZonesFor(codes) }
            }
            result.fold(
                onSuccess = { fetched ->
                    if (fetched.isNotEmpty()) {
                        _state.update { state ->
                            state.copy(sotaZones = mergeCache(state.sotaZones, fetched, MAX_CACHED_ZONES) { it.reference })
                        }
                    }
                },
                onFailure = { e -> AppLog.add(AppLog.Level.ERROR, "SOTA zone read failed: ${e.message}") },
            )
        }
    }

    // MARK: - WWFF borrowed boundaries

    /**
     * WWFF pins are fetched separately from the park/summit pins (`pinsInBox`
     * supports a `"wwff"` kind, but mixing it into the always-on pins fetch
     * would dump WWFF dots onto the clustered park/summit layer). Only the US
     * program (`KFF-####`) borrows a POTA boundary (iOS's
     * `program.uppercased() == "KFF"` prefilter in `loadWWFFReferences`), so
     * non-KFF refs are dropped client-side before resolving boundaries — the
     * FFI itself further drops refs with a non-numeric tail.
     */
    private fun fetchWwff(bbox: FfiBoundingBox) {
        if (!withinSpan(bbox, WWFF_SPAN_GATE)) return
        wwffJob?.cancel()
        wwffJob = viewModelScope.launch {
            delay(REGION_DEBOUNCE_MS)
            val pinsResult = withContext(Dispatchers.IO) {
                runCatching { parkMapApi.pinsInBox(bbox, listOf("wwff"), PINS_LIMIT_PER_KIND) }
            }
            val wwffPins = pinsResult.getOrElse { e ->
                AppLog.add(AppLog.Level.ERROR, "WWFF pins fetch failed: ${e.message}")
                return@launch
            }
            _state.update { it.copy(wwffPins = wwffPins) }

            val known = _state.value.wwffBoundaries.keys
            val refs = wwffPins
                .asSequence()
                .filter { it.reference.startsWith("KFF-", ignoreCase = true) }
                .map { nearestFirstKey(it, bbox) }
                .sortedBy { it.first }
                .map { it.second.reference }
                .filterNot { known.contains(it) }
                .take(MAX_WWFF_PER_FETCH)
                .toList()
            if (refs.isEmpty()) return@launch
            val result = withContext(Dispatchers.IO) {
                runCatching { parkMapApi.wwffBorrowedBoundaries(refs) }
            }
            result.fold(
                onSuccess = { fetched ->
                    if (fetched.isNotEmpty()) {
                        _state.update { state ->
                            state.copy(wwffBoundaries = mergeCache(state.wwffBoundaries, fetched, MAX_CACHED_WWFF) { it.reference })
                        }
                    }
                },
                onFailure = { e -> AppLog.add(AppLog.Level.ERROR, "WWFF boundary fetch failed: ${e.message}") },
            )
        }
    }

    // MARK: - Rosette multiplier finder

    /** Open the sheet and kick off the (Dispatchers.IO) overlap scan over the
     * current viewport's loaded refs. Re-triggering cancels any prior scan —
     * iOS parity, see `ParkSearchMapView+Multipliers.swift` `presentMultipliers`. */
    fun presentMultipliers() {
        _state.update { it.copy(showMultipliersSheet = true, multiplierCandidates = emptyList(), findingMultipliers = true) }
        multiplierJob?.cancel()
        multiplierJob = viewModelScope.launch { computeMultipliers() }
    }

    fun dismissMultipliers() {
        multiplierJob?.cancel()
        _state.update { it.copy(showMultipliersSheet = false, findingMultipliers = false) }
    }

    private suspend fun computeMultipliers() {
        val snapshot = _state.value
        val bbox = snapshot.lastRegion
        if (bbox == null) {
            _state.update { it.copy(multiplierCandidates = emptyList(), findingMultipliers = false) }
            return
        }
        val summitRefs = snapshot.pins
            .asSequence()
            .filter { it.kind == "summit" }
            .filter { inBox(it.latitude, it.longitude, bbox) }
            .map { nearestFirstKey(it, bbox) }
            .sortedBy { it.first }
            .map { it.second.reference }
            .take(MAX_MULTIPLIER_SUMMITS)
            .toList()
        val parkRefs = snapshot.boundaries.keys.toList()
        val wwffRefs = snapshot.wwffBoundaries.keys.toList()
        val countyRefs = snapshot.adminBoundaries.values
            .filter { it.kind == "admin_county" }
            .map { it.reference }

        val result = withContext(Dispatchers.IO) {
            runCatching {
                parkMapApi.findMultipliers(
                    summitRefs = summitRefs,
                    parkRefs = parkRefs,
                    wwffBorrowedRefs = wwffRefs,
                    countyRefs = countyRefs,
                )
            }
        }
        result.fold(
            onSuccess = { found ->
                _state.update { it.copy(multiplierCandidates = found, findingMultipliers = false) }
            },
            onFailure = { e ->
                AppLog.add(AppLog.Level.ERROR, "Multiplier scan failed: ${e.message}")
                _state.update { it.copy(multiplierCandidates = emptyList(), findingMultipliers = false) }
            },
        )
    }

    // MARK: - Shared helpers

    /** Merge new rows into a reference-keyed cache map, evicting the oldest
     * (by insertion order — `LinkedHashMap`) entries when over the cap. Mirrors
     * iOS's `mergeBoundaries`/`mergeAdminBoundaries`/etc. distance-based eviction
     * closely enough for a bounded viewport cache; simpler ordinal eviction is
     * used here since Android doesn't keep a `centerLat/centerLon` on every
     * cached row (`FfiGeoBoundary` carries no bbox — only geometry). */
    private fun mergeCache(
        existing: Map<String, FfiGeoBoundary>,
        new: List<FfiGeoBoundary>,
        maxCached: Int,
        keyOf: (FfiGeoBoundary) -> String,
    ): Map<String, FfiGeoBoundary> {
        val merged = LinkedHashMap(existing)
        for (item in new) {
            merged[keyOf(item)] = item
        }
        if (merged.size <= maxCached) return merged
        val overflow = merged.size - maxCached
        val toDrop = merged.keys.filterNot { key -> new.any { keyOf(it) == key } }.take(overflow)
        toDrop.forEach { merged.remove(it) }
        return merged
    }

    // iOS gates on BOTH latitudeDelta and longitudeDelta (< maxSpanDegrees
    // each) before fetching boundaries/trails — a wide-but-short viewport
    // shouldn't slip through on latitude alone. Plain subtraction (no
    // antimeridian wraparound) matches these fetch call sites' existing bbox
    // handling.
    private fun withinSpan(bbox: FfiBoundingBox, maxSpanDegrees: Double): Boolean =
        (bbox.north - bbox.south) < maxSpanDegrees && (bbox.east - bbox.west) < maxSpanDegrees

    /** Zoom-scaled polygon simplification tolerance — mirrors iOS `simplifyTolerance(for:)`. */
    private fun simplifyTolerance(bbox: FfiBoundingBox): Double {
        val span = maxOf(bbox.north - bbox.south, bbox.east - bbox.west)
        return when {
            span > 3 -> 0.005
            span > 1 -> 0.002
            span > 0.3 -> 0.001
            else -> 0.0005
        }
    }

    private fun inBox(lat: Double, lon: Double, bbox: FfiBoundingBox): Boolean =
        lat in bbox.south..bbox.north && lon in bbox.west..bbox.east

    /** Distance-from-center key (Manhattan, degrees) paired with the pin, for
     * nearest-first capping — mirrors iOS `zoneSummitCodes`/`visibleWWFF`. */
    private fun nearestFirstKey(pin: FfiParkPin, bbox: FfiBoundingBox): Pair<Double, FfiParkPin> {
        val centerLat = (bbox.north + bbox.south) / 2
        val centerLon = (bbox.east + bbox.west) / 2
        val dist = kotlin.math.abs(pin.latitude - centerLat) + kotlin.math.abs(pin.longitude - centerLon)
        return dist to pin
    }

    companion object {
        fun factory() = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as CwApp
                ParkSearchViewModel(app.parkMapApi)
            }
        }
    }
}
