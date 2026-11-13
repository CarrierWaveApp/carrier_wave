package app.carrierwave.android.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import uniffi.cw_ffi.FfiSatModeCategory
import uniffi.cw_ffi.FfiSatTransmitter

/**
 * Work-type buckets for the chart/pass-list filter (mirror of the iOS
 * `SatelliteFilterBucket`). Unlike the engine's mode categories, this
 * splits **telemetry** — downlink-only transmitters you can receive but
 * never work through — out of digital, so beacon-only cubesats can be
 * hidden without losing real digital birds. Raw values match iOS.
 */
enum class SatelliteFilterBucket(val raw: String, val label: String) {
    FM("FM", "FM"),
    LINEAR("LINEAR", "Linear"),
    DIGITAL("DIGI", "Digital"),
    TELEMETRY("TLM", "Telemetry"),
    ;

    companion object {
        /** No uplink = telemetry; otherwise the mode decides, with CW
         * folded into linear (it rides the transponder). */
        fun of(transmitter: FfiSatTransmitter): SatelliteFilterBucket {
            if (transmitter.uplinkLowHz == null) return TELEMETRY
            return when (transmitter.modeCategory) {
                FfiSatModeCategory.VOICE_FM -> FM
                FfiSatModeCategory.LINEAR, FfiSatModeCategory.MORSE -> LINEAR
                FfiSatModeCategory.DIGITAL -> DIGITAL
            }
        }
    }
}

/**
 * Amateur-satellite band letters for the uplink/downlink filters
 * (mirror of the iOS `SatBand`).
 */
enum class SatBand(val raw: String, val label: String) {
    HF("H", "H (HF)"),
    VHF("V", "V (2 m)"),
    UHF("U", "U (70 cm)"),
    L_BAND("L", "L (23 cm)"),
    S_BAND("S", "S (13 cm)"),
    C_BAND("C", "C (6 cm)"),
    X_BAND("X", "X (3 cm)"),
    ;

    companion object {
        fun of(hz: Long): SatBand {
            val mhz = hz / 1_000_000.0
            return when {
                mhz < 100 -> HF
                mhz < 225 -> VHF
                mhz < 1_000 -> UHF
                mhz < 2_000 -> L_BAND
                mhz < 3_500 -> S_BAND
                mhz < 8_000 -> C_BAND
                else -> X_BAND
            }
        }
    }
}

/**
 * Eight compass sectors for the clear-sky (horizon mask) filter (mirror
 * of the iOS `SkySector`): disable blocked directions and passes peaking
 * there drop out.
 */
enum class SkySector(val raw: String) {
    N("N"), NE("NE"), E("E"), SE("SE"), S("S"), SW("SW"), W("W"), NW("NW"),
    ;

    companion object {
        /** The 45° sector containing an azimuth (N spans 337.5°–22.5°). */
        fun of(azimuthDeg: Double): SkySector {
            val normalized = ((azimuthDeg % 360.0) + 360.0) % 360.0
            return entries[(((normalized + 22.5) / 45.0).toInt()) % 8]
        }
    }
}

/**
 * Shared persisted work-type + band filters for the satellite chart and
 * pass lists (mirror of the iOS `SatelliteModeFilter`): one selection
 * across surfaces, empty storage = all, toggling never drops below one
 * enabled.
 */
object SatelliteModeFilter {
    private const val PREFS = "cw"
    private const val KEY = "satellite_mode_filter"
    private const val KEY_UPLINK = "satellite_uplink_band_filter"
    private const val KEY_DOWNLINK = "satellite_downlink_band_filter"
    private const val KEY_MIN_PEAK = "satellite_min_peak_elevation"
    private const val KEY_HEARD = "satellite_heard_recently_only"
    private const val KEY_FAVORITES = "satellite_favorites_only"
    private const val KEY_HORIZON = "satellite_horizon_mask"

    /** The heard-recently window (matches the FM workability rule). */
    private const val HEARD_WINDOW_SECS = 7L * 24 * 3_600

    /** Threshold choices in the steps operators actually use (N9HO: "15°
     * is usually about the hard minimum, I set mine to 20/25"). */
    val PEAK_ELEVATION_OPTIONS = listOf(0, 10, 15, 20, 25, 30, 45)

    /** A sector marked fully blocked. */
    const val BLOCKED_ELEVATION = 90

    /** The per-sector minimums a horizon control cycles through. */
    val HORIZON_STEPS = listOf(0, 10, 20, 30, 45, BLOCKED_ELEVATION)

    fun peakElevationLabel(degrees: Int): String = if (degrees == 0) "Any" else "$degrees°"

    val ALL: Set<SatelliteFilterBucket> = SatelliteFilterBucket.entries.toSet()
    val ALL_BANDS: Set<SatBand> = SatBand.entries.toSet()

    private val _selection = MutableStateFlow(ALL)
    val selection: StateFlow<Set<SatelliteFilterBucket>> = _selection.asStateFlow()

    private val _uplinkBands = MutableStateFlow(ALL_BANDS)
    val uplinkBands: StateFlow<Set<SatBand>> = _uplinkBands.asStateFlow()

    private val _downlinkBands = MutableStateFlow(ALL_BANDS)
    val downlinkBands: StateFlow<Set<SatBand>> = _downlinkBands.asStateFlow()

    /** Minimum next-pass peak elevation, degrees (0 = any). */
    private val _minPeakElevation = MutableStateFlow(0)
    val minPeakElevation: StateFlow<Int> = _minPeakElevation.asStateFlow()

    /** Only birds AMSAT heard in the last 7 days (untracked birds keep
     * the benefit of the doubt). */
    private val _heardRecentlyOnly = MutableStateFlow(false)
    val heardRecentlyOnly: StateFlow<Boolean> = _heardRecentlyOnly.asStateFlow()

    /** Only favorited birds. */
    private val _favoritesOnly = MutableStateFlow(false)
    val favoritesOnly: StateFlow<Boolean> = _favoritesOnly.asStateFlow()

    /** Horizon mask: per-sector minimum elevation, degrees (absent = 0 =
     * clear to the horizon); passes peaking below it drop out. */
    private val _horizonMask = MutableStateFlow<Map<SkySector, Int>>(emptyMap())
    val horizonMask: StateFlow<Map<SkySector, Int>> = _horizonMask.asStateFlow()

    fun load(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.getString(KEY, null)?.let { raw ->
            val decoded = raw.split(",")
                .mapNotNull { part -> SatelliteFilterBucket.entries.firstOrNull { it.raw == part.trim() } }
                .toSet()
            if (decoded.isNotEmpty()) _selection.value = decoded
        }
        prefs.getString(KEY_UPLINK, null)?.let { raw ->
            decodeBands(raw)?.let { _uplinkBands.value = it }
        }
        prefs.getString(KEY_DOWNLINK, null)?.let { raw ->
            decodeBands(raw)?.let { _downlinkBands.value = it }
        }
        _minPeakElevation.value = prefs.getInt(KEY_MIN_PEAK, 0)
        _heardRecentlyOnly.value = prefs.getBoolean(KEY_HEARD, false)
        _favoritesOnly.value = prefs.getBoolean(KEY_FAVORITES, false)
        prefs.getString(KEY_HORIZON, null)?.let { raw ->
            _horizonMask.value = raw.split(",").mapNotNull { entry ->
                val parts = entry.split(":")
                val sector = SkySector.entries.firstOrNull { it.raw == parts.getOrNull(0)?.trim() }
                val degrees = parts.getOrNull(1)?.trim()?.toIntOrNull()
                if (sector != null && degrees != null) sector to degrees else null
            }.toMap()
        }
    }

    fun setMinPeakElevation(context: Context, degrees: Int) {
        _minPeakElevation.value = degrees
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putInt(KEY_MIN_PEAK, degrees)
            .apply()
    }

    fun setHeardRecentlyOnly(context: Context, on: Boolean) {
        _heardRecentlyOnly.value = on
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_HEARD, on)
            .apply()
    }

    fun setFavoritesOnly(context: Context, on: Boolean) {
        _favoritesOnly.value = on
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_FAVORITES, on)
            .apply()
    }

    /** Tap-cycle one sector through the horizon steps (0 → 10 → … →
     * blocked → 0). */
    fun cycleHorizon(context: Context, sector: SkySector) {
        val current = _horizonMask.value[sector] ?: 0
        val index = HORIZON_STEPS.indexOf(current).coerceAtLeast(0)
        val next = HORIZON_STEPS[(index + 1) % HORIZON_STEPS.size]
        val mask = (_horizonMask.value + (sector to next)).filterValues { it > 0 }
        _horizonMask.value = mask
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(
                KEY_HORIZON,
                mask.entries.map { "${it.key.raw}:${it.value}" }.sorted().joinToString(","),
            )
            .apply()
    }

    /** Any direction raised above the horizon? */
    fun horizonActive(mask: Map<SkySector, Int>): Boolean = mask.values.any { it > 0 }

    /** Does a pass peaking here clear the direction's minimum elevation? */
    fun horizonAllows(
        peakAzimuthDeg: Double,
        peakElevationDeg: Double,
        mask: Map<SkySector, Int>,
    ): Boolean = peakElevationDeg >= (mask[SkySector.of(peakAzimuthDeg)] ?: 0)

    fun toggle(context: Context, bucket: SatelliteFilterBucket) {
        val current = _selection.value
        val next = when {
            bucket in current && current.size > 1 -> current - bucket
            bucket in current -> return
            else -> current + bucket
        }
        _selection.value = next
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY, next.map(SatelliteFilterBucket::raw).sorted().joinToString(","))
            .apply()
    }

    fun toggleUplinkBand(context: Context, band: SatBand) {
        _uplinkBands.value = toggledBands(context, KEY_UPLINK, _uplinkBands.value, band)
    }

    fun toggleDownlinkBand(context: Context, band: SatBand) {
        _downlinkBands.value = toggledBands(context, KEY_DOWNLINK, _downlinkBands.value, band)
    }

    /**
     * Does the bird carry a transmitter satisfying ALL the
     * transmitter-level filters at once? An active uplink-band filter
     * requires an uplink — it means "something I can transmit into on
     * these bands" — likewise downlink; heard-recently only indicts
     * AMSAT-tracked capabilities that have fallen silent.
     */
    fun matches(
        transmitters: List<FfiSatTransmitter>,
        selection: Set<SatelliteFilterBucket>,
        uplink: Set<SatBand> = _uplinkBands.value,
        downlink: Set<SatBand> = _downlinkBands.value,
        heardOnly: Boolean = _heardRecentlyOnly.value,
    ): Boolean {
        val allBuckets = selection.size == ALL.size
        val allUplink = uplink.size == ALL_BANDS.size
        val allDownlink = downlink.size == ALL_BANDS.size
        if (allBuckets && allUplink && allDownlink && !heardOnly) return true
        val heardCutoff = System.currentTimeMillis() / 1_000 - HEARD_WINDOW_SECS
        return transmitters.any { transmitter ->
            (allBuckets || SatelliteFilterBucket.of(transmitter) in selection) &&
                (allUplink || transmitter.uplinkLowHz?.let { SatBand.of(it) in uplink } == true) &&
                (
                    allDownlink ||
                        transmitter.downlinkLowHz?.let { SatBand.of(it) in downlink } == true
                    ) &&
                (
                    !heardOnly || !transmitter.amsatTracked ||
                        (transmitter.amsatLastHeardEpoch ?: 0) > heardCutoff
                    )
        }
    }

    private fun decodeBands(raw: String): Set<SatBand>? = raw.split(",")
        .mapNotNull { part -> SatBand.entries.firstOrNull { it.raw == part.trim() } }
        .toSet()
        .ifEmpty { null }

    private fun toggledBands(
        context: Context,
        key: String,
        current: Set<SatBand>,
        band: SatBand,
    ): Set<SatBand> {
        val next = when {
            band in current && current.size > 1 -> current - band
            band in current -> return current
            else -> current + band
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(key, next.map(SatBand::raw).sorted().joinToString(","))
            .apply()
        return next
    }
}
