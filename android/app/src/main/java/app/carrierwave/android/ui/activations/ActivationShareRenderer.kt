package app.carrierwave.android.ui.activations

import androidx.compose.ui.graphics.Color
import app.carrierwave.android.ui.share.RstColor
import uniffi.cw_ffi.FfiCoordinate
import uniffi.cw_ffi.FfiQso
import uniffi.cw_ffi.FfiRingLabel
import uniffi.cw_ffi.FfiShareMapInput
import uniffi.cw_ffi.FfiShareMapStyle
import uniffi.cw_ffi.FfiSharePin
import uniffi.cw_ffi.FfiSharePinColorKind
import uniffi.cw_ffi.FfiShareTrace
import uniffi.cw_ffi.computeFlatShareViewport
import uniffi.cw_ffi.maidenheadCoordinate
import uniffi.cw_ffi.renderShareMap

/** A resolved QSO marker for the activation share map — coordinate + RST-derived pin color. */
private data class ActivationMarker(val coordinate: FfiCoordinate, val color: Color)

/** Rendered map PNG bytes + azimuthal ring-label overlay anchors (empty for flat styles). */
data class ActivationShareMapResult(
    val pngBytes: ByteArray,
    val ringLabels: List<FfiRingLabel>,
)

/**
 * Map-data prep for the activation share card, on the shared Rust rasterizer.
 *
 * Port of the iOS `ActivationShareRenderer` pin construction
 * (`swift/ios/CarrierWave/Views/POTAActivations/ActivationShareRenderer.swift`):
 * one RST-colored pin per mappable QSO (their-grid resolvable), traces from the
 * operator's home coordinate to each pin, flat framing via
 * [computeFlatShareViewport], azimuthal gated on a resolvable home grid.
 *
 * Unlike the brag-sheet renderer (which count-clusters by grid), the activation
 * card shows every individual contact colored by how well it was heard — so no
 * clustering, `FfiSharePinColorKind.RGBA` pins, mirroring iOS one-marker-per-QSO.
 */
object ActivationShareRenderer {

    const val MAP_WIDTH = 736
    const val MAP_HEIGHT = 400

    /**
     * Most common 4-char operator grid across `qsos`, falling back to
     * `homeGrid`. Used as the trace origin / azimuthal center (iOS's `myGrid`).
     */
    fun resolveHomeCoordinate(qsos: List<FfiQso>, homeGrid: String): FfiCoordinate? {
        val counts = mutableMapOf<String, Int>()
        for (qso in qsos) {
            val grid = qso.myGrid ?: continue
            if (grid.length < 4) continue
            val prefix = grid.substring(0, 4).uppercase()
            counts[prefix] = (counts[prefix] ?: 0) + 1
        }
        val best = counts.maxByOrNull { it.value }?.key
            ?: homeGrid.takeIf { it.length >= 4 }?.substring(0, 4)?.uppercase()
        return best?.let { maidenheadCoordinate(it) }
    }

    /** True when at least one QSO has a resolvable their-grid (i.e. the map has any pins). */
    fun hasMappableQsos(qsos: List<FfiQso>): Boolean = markers(qsos).isNotEmpty()

    /**
     * Renders the themed activation share-map PNG (+ ring labels for azimuthal)
     * for `qsos` traced from `homeCoordinate`. Returns null if there are no
     * mappable QSOs, or if `style` is azimuthal with an unresolvable home
     * coordinate. Runs the FFI render synchronously — callers must dispatch on
     * [kotlinx.coroutines.Dispatchers.IO].
     */
    fun renderMap(
        style: FfiShareMapStyle,
        qsos: List<FfiQso>,
        homeCoordinate: FfiCoordinate?,
    ): ActivationShareMapResult? {
        val markers = markers(qsos)
        if (markers.isEmpty()) return null
        if (style == FfiShareMapStyle.AZIMUTHAL && homeCoordinate == null) return null

        val pins = markers.map { marker ->
            FfiSharePin(
                lat = marker.coordinate.latitude,
                lon = marker.coordinate.longitude,
                kind = FfiSharePinColorKind.RGBA,
                count = 0u,
                red = marker.color.red,
                green = marker.color.green,
                blue = marker.color.blue,
                alpha = 1f,
            )
        }
        val traces = homeCoordinate?.let { home ->
            markers.map { marker ->
                FfiShareTrace(
                    fromLat = home.latitude,
                    fromLon = home.longitude,
                    toLat = marker.coordinate.latitude,
                    toLon = marker.coordinate.longitude,
                )
            }
        }.orEmpty()

        val input: FfiShareMapInput = if (style == FfiShareMapStyle.AZIMUTHAL) {
            FfiShareMapInput(
                width = MAP_WIDTH.toUInt(),
                height = MAP_HEIGHT.toUInt(),
                centerLat = homeCoordinate!!.latitude,
                centerLon = homeCoordinate.longitude,
                centerGrid = null,
                latSpan = 0.0,
                lonSpan = 0.0,
                pins = pins,
                traces = traces,
                showCenterMarker = true,
            )
        } else {
            val coords = markers.map { FfiCoordinate(it.coordinate.latitude, it.coordinate.longitude) } +
                listOfNotNull(homeCoordinate)
            val viewport = computeFlatShareViewport(coords, MAP_WIDTH.toUInt(), MAP_HEIGHT.toUInt())
            FfiShareMapInput(
                width = MAP_WIDTH.toUInt(),
                height = MAP_HEIGHT.toUInt(),
                centerLat = viewport.centerLat,
                centerLon = viewport.centerLon,
                centerGrid = null,
                latSpan = viewport.latSpan,
                lonSpan = viewport.lonSpan,
                pins = pins,
                traces = traces,
                showCenterMarker = homeCoordinate != null,
            )
        }

        val image = renderShareMap(style, input)
        return ActivationShareMapResult(pngBytes = image.pngBytes, ringLabels = image.ringLabels)
    }

    /** Resolve one RST-colored marker per QSO with a resolvable their-grid (iOS `mappableQSOs`). */
    private fun markers(qsos: List<FfiQso>): List<ActivationMarker> =
        qsos.mapNotNull { qso ->
            val grid = qso.theirGrid?.takeIf { it.length >= 4 } ?: return@mapNotNull null
            val coord = maidenheadCoordinate(grid.substring(0, minOf(grid.length, 6))) ?: return@mapNotNull null
            ActivationMarker(coord, RstColor.color(qso.rstSent, qso.rstRcvd))
        }
}
