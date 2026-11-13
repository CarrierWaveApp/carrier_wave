package app.carrierwave.android.ui.propagation

import app.carrierwave.android.ui.common.bandColor
import uniffi.cw_ffi.FfiCoordinate
import uniffi.cw_ffi.FfiPropagationEnrichedSpot
import uniffi.cw_ffi.FfiRingLabel
import uniffi.cw_ffi.FfiShareMapInput
import uniffi.cw_ffi.FfiShareMapStyle
import uniffi.cw_ffi.FfiSharePin
import uniffi.cw_ffi.FfiSharePinColorKind
import uniffi.cw_ffi.FfiShareTrace
import uniffi.cw_ffi.maidenheadCoordinate
import uniffi.cw_ffi.renderShareMap

/** Rendered map PNG bytes + azimuthal ring-label overlay anchors. */
data class PropagationMapResult(
    val pngBytes: ByteArray,
    val ringLabels: List<FfiRingLabel>,
)

/**
 * Azimuthal-equidistant map for a propagation check, on the shared Rust
 * rasterizer — the Android analog of iOS `PropagationCheckAzimuthalCard`
 * (which uses the native `AzimuthalMapView` + `AzimuthalProjection`). Android
 * has no equivalent native azimuthal Canvas renderer, so this reuses
 * `render_share_map(FfiShareMapStyle.AZIMUTHAL, ...)` — the same path the
 * brag-sheet ([app.carrierwave.android.ui.brag.BragSheetShareRenderer]) and
 * activation ([app.carrierwave.android.ui.activations.ActivationShareRenderer])
 * share cards use — one band-colored pin per enriched spot, traced from the
 * operator's grid.
 *
 * Runs the FFI render call synchronously; callers must dispatch on
 * [kotlinx.coroutines.Dispatchers.IO].
 */
object PropagationAzimuthalRenderer {

    const val MAP_WIDTH = 736
    const val MAP_HEIGHT = 400

    /**
     * Renders the azimuthal PNG (+ ring labels) for `spots` centered on
     * `userGrid`. Returns null when `userGrid` doesn't resolve to a coordinate
     * (mirrors iOS, which only renders once the operator grid is valid) or
     * there are no spots with a resolvable position yet.
     */
    fun render(userGrid: String, spots: List<FfiPropagationEnrichedSpot>): PropagationMapResult? {
        val home = maidenheadCoordinate(userGrid) ?: return null
        val resolved = spots.filter { it.latitude != null && it.longitude != null }
        if (resolved.isEmpty()) return null

        val pins = resolved.map { spot ->
            val color = bandColor(spot.spot.band)
            FfiSharePin(
                lat = spot.latitude!!,
                lon = spot.longitude!!,
                kind = FfiSharePinColorKind.RGBA,
                count = 0u,
                red = color.red,
                green = color.green,
                blue = color.blue,
                alpha = 1f,
            )
        }
        val traces = resolved.map { spot ->
            FfiShareTrace(
                fromLat = home.latitude,
                fromLon = home.longitude,
                toLat = spot.latitude!!,
                toLon = spot.longitude!!,
            )
        }

        val input = FfiShareMapInput(
            width = MAP_WIDTH.toUInt(),
            height = MAP_HEIGHT.toUInt(),
            centerLat = home.latitude,
            centerLon = home.longitude,
            centerGrid = null,
            latSpan = 0.0,
            lonSpan = 0.0,
            pins = pins,
            traces = traces,
            showCenterMarker = true,
        )
        val image = renderShareMap(FfiShareMapStyle.AZIMUTHAL, input)
        return PropagationMapResult(pngBytes = image.pngBytes, ringLabels = image.ringLabels)
    }

    /** Home coordinate for [userGrid], or null if unresolvable. */
    fun homeCoordinate(userGrid: String): FfiCoordinate? = maidenheadCoordinate(userGrid)
}

/**
 * Flat (non-azimuthal) map for the results screen's "Map" mode — same
 * band-colored pins + home traces as [PropagationAzimuthalRenderer], but
 * framed with [computeFlatShareViewport] and rendered in
 * [FfiShareMapStyle.MIDNIGHT] instead of a polar projection. This is the
 * Android analog of iOS `PropagationCheckMapCard`'s `interactiveMap`
 * (MapKit) — Android has no MapKit equivalent for a *static results* card,
 * so it reuses the same shared Rust rasterizer the azimuthal card uses
 * rather than standing up a second rendering path.
 */
object PropagationFlatMapRenderer {
    fun render(userGrid: String, spots: List<FfiPropagationEnrichedSpot>): PropagationMapResult? {
        val home = maidenheadCoordinate(userGrid)
        val resolved = spots.filter { it.latitude != null && it.longitude != null }
        if (resolved.isEmpty()) return null

        val pins = resolved.map { spot ->
            val color = bandColor(spot.spot.band)
            FfiSharePin(
                lat = spot.latitude!!,
                lon = spot.longitude!!,
                kind = FfiSharePinColorKind.RGBA,
                count = 0u,
                red = color.red,
                green = color.green,
                blue = color.blue,
                alpha = 1f,
            )
        }
        val traces = home?.let { origin ->
            resolved.map { spot ->
                FfiShareTrace(
                    fromLat = origin.latitude,
                    fromLon = origin.longitude,
                    toLat = spot.latitude!!,
                    toLon = spot.longitude!!,
                )
            }
        }.orEmpty()

        val coords = resolved.map { FfiCoordinate(it.latitude!!, it.longitude!!) } + listOfNotNull(home)
        val viewport = uniffi.cw_ffi.computeFlatShareViewport(
            coords,
            PropagationAzimuthalRenderer.MAP_WIDTH.toUInt(),
            PropagationAzimuthalRenderer.MAP_HEIGHT.toUInt(),
        )
        val input = FfiShareMapInput(
            width = PropagationAzimuthalRenderer.MAP_WIDTH.toUInt(),
            height = PropagationAzimuthalRenderer.MAP_HEIGHT.toUInt(),
            centerLat = viewport.centerLat,
            centerLon = viewport.centerLon,
            centerGrid = null,
            latSpan = viewport.latSpan,
            lonSpan = viewport.lonSpan,
            pins = pins,
            traces = traces,
            showCenterMarker = home != null,
        )
        val image = renderShareMap(FfiShareMapStyle.MIDNIGHT, input)
        return PropagationMapResult(pngBytes = image.pngBytes, ringLabels = image.ringLabels)
    }
}
