package app.carrierwave.android.ui.spots

import uniffi.cw_ffi.FfiEnrichedSpot
import uniffi.cw_ffi.FfiNeededStatus
import uniffi.cw_ffi.FfiSpotSource
import uniffi.cw_ffi.FfiTuneInSpot

/** The live-spot source the user can filter to. */
enum class SpotSource(val label: String) {
    POTA("POTA"),
    RBN("RBN"),
    SOTA("SOTA"),
    WWFF("WWFF"),
    ;

    fun toFfi(): FfiSpotSource = when (this) {
        POTA -> FfiSpotSource.POTA
        RBN -> FfiSpotSource.RBN
        SOTA -> FfiSpotSource.SOTA
        WWFF -> FfiSpotSource.WWFF
    }
}

/** Engine source → UI source; null for sources Android doesn't enable yet. */
fun FfiSpotSource.toUi(): SpotSource? = when (this) {
    FfiSpotSource.POTA -> SpotSource.POTA
    FfiSpotSource.RBN -> SpotSource.RBN
    FfiSpotSource.SOTA -> SpotSource.SOTA
    FfiSpotSource.WWFF -> SpotSource.WWFF
    else -> null
}

/**
 * A spot for the UI, flattened from the engine's [FfiEnrichedSpot] so one row
 * renderer handles every source.
 */
data class Spot(
    val key: String,
    val source: SpotSource,
    val callsign: String,
    val freqKhz: Double?,
    val band: String?,
    val mode: String,
    /** POTA/SOTA/WWFF reference, or null for RBN. */
    val reference: String?,
    val spotter: String?,
    val comments: String?,
    val epochSeconds: Double?,
    /** Activator's Maidenhead grid, when the source carries one. */
    val grid: String? = null,
    // Engine enrichment
    val country: String? = null,
    val state: String? = null,
    val distanceKm: Double? = null,
    val wpm: Int? = null,
    val snr: Int? = null,
    val needed: FfiNeededStatus = FfiNeededStatus.UNKNOWN,
    /** Highest matched-need priority ordinal (HIGH=2 … LOW=0), null when no
     *  needs matched — the iOS `EnrichedSpot.highestNeedPriority` analog. */
    val needPriority: Int? = null,
) {
    /**
     * A quick-entry command that prefills the Logger from this spot, e.g.
     * "W1AW 14.074 FT8". The POTA park reference is appended (the quick-entry
     * grammar recognizes POTA park tokens); other refs are left off.
     */
    fun toLoggerCommand(): String = buildString {
        append(callsign)
        freqKhz?.let {
            append(' ')
            append("%.3f".format(it / 1000.0).trimEnd('0').trimEnd('.'))
        }
        if (mode.isNotBlank()) {
            append(' ')
            append(mode)
        }
        if (source == SpotSource.POTA && !reference.isNullOrBlank()) {
            append(' ')
            append(reference)
        }
    }

    /**
     * The Rust Tune-In snapshot for this spot, or null without a frequency.
     * Park/summit coordinates stay null — iOS resolves them from local POTA/
     * SOTA caches Android doesn't keep; the near-activator strategy falls
     * back to HamDB/RBN inside the shared core.
     */
    fun toTuneInSpot(): FfiTuneInSpot? {
        val khz = freqKhz ?: return null
        return FfiTuneInSpot(
            callsign = callsign,
            frequencyMhz = khz / 1_000.0,
            mode = mode.ifBlank { "SSB" },
            band = band.orEmpty(),
            parkRef = reference.takeIf { source == SpotSource.POTA },
            summitCode = reference.takeIf { source == SpotSource.SOTA },
            latitude = null,
            longitude = null,
            grid = grid,
            parkLatitude = null,
            parkLongitude = null,
            summitLatitude = null,
            summitLongitude = null,
        )
    }
}

/** Engine spot → UI spot; null when the source isn't one Android shows. */
fun FfiEnrichedSpot.toSpot(): Spot? {
    val uiSource = source.toUi() ?: return null
    return Spot(
        key = id,
        source = uiSource,
        callsign = callsign,
        freqKhz = frequencyKhz,
        band = band.ifBlank { null },
        mode = mode,
        reference = parkRef ?: summitCode ?: wwffRef,
        spotter = spotter,
        comments = comments,
        epochSeconds = timestamp.toDouble(),
        grid = dxGrid,
        country = country,
        state = state,
        distanceKm = distanceMeters?.div(1_000.0),
        wpm = wpm,
        snr = snr,
        needed = neededStatus,
        needPriority = matchedNeeds.maxOfOrNull { it.priority.ordinal },
    )
}
