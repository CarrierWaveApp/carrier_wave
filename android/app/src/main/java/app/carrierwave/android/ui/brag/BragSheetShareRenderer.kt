package app.carrierwave.android.ui.brag

import uniffi.cw_ffi.FfiCoordinate
import uniffi.cw_ffi.FfiQso
import uniffi.cw_ffi.FfiShareMapInput
import uniffi.cw_ffi.FfiShareMapStyle
import uniffi.cw_ffi.FfiSharePin
import uniffi.cw_ffi.FfiSharePinColorKind
import uniffi.cw_ffi.FfiShareTrace
import uniffi.cw_ffi.computeFlatShareViewport
import uniffi.cw_ffi.maidenheadCoordinate
import uniffi.cw_ffi.renderShareMap

/** A cluster of QSOs in the same grid square — count pin + centroid coordinate. */
data class BragSheetMapCluster(val coordinate: FfiCoordinate, val count: Int)

/**
 * Map-data prep for the brag sheet share card, on the shared Rust rasterizer.
 *
 * Port of the iOS `BragSheetShareRenderer.computeClusters` +
 * `drawMap`/`computeViewport` (`swift/ios/CarrierWave/Views/BragSheet/
 * BragSheetShareRenderer.swift`), minus the MapKit adaptive/globe styles
 * Android doesn't have. Clustering stays client-side (mirrors iOS exactly);
 * framing (flat styles) and rasterizing both styles are shared Rust
 * (`compute_flat_share_viewport` / `render_share_map`).
 */
object BragSheetShareRenderer {

    const val MAP_WIDTH = 736
    const val MAP_HEIGHT = 400

    /**
     * Cluster `qsos` by their grid square. Verbatim port of the iOS rule:
     * decide 2-char (field, wide spans) vs 4-char (square, focused) prefix
     * length from the longitude spread of the 4-char-resolved grids, then
     * group-count by that prefix. 2-char prefixes are padded with "55" (grid
     * square center) before coordinate lookup, matching iOS.
     */
    fun computeClusters(qsos: List<FfiQso>): List<BragSheetMapCluster> {
        val theirGrids = qsos.mapNotNull { it.theirGrid }

        val lons = theirGrids
            .filter { it.length >= 4 }
            .mapNotNull { maidenheadCoordinate(it.substring(0, 4))?.longitude }
        val lonSpread = (lons.maxOrNull() ?: 0.0) - (lons.minOrNull() ?: 0.0)
        val prefixLength = if (lonSpread > 50.0) 2 else 4

        val gridCounts = mutableMapOf<String, Int>()
        for (grid in theirGrids) {
            if (grid.length < prefixLength) continue
            val prefix = grid.substring(0, prefixLength).uppercase()
            gridCounts[prefix] = (gridCounts[prefix] ?: 0) + 1
        }

        return gridCounts.mapNotNull { (grid, count) ->
            val lookupGrid = if (grid.length < 4) grid + "55" else grid
            val coord = maidenheadCoordinate(lookupGrid) ?: return@mapNotNull null
            BragSheetMapCluster(coord, count)
        }
    }

    /**
     * Most common 4-char operator grid across `qsos` — used as the home
     * coordinate for trace lines / the azimuthal center. Mirrors iOS
     * `Input.myGrid`.
     */
    fun mostCommonMyGrid(qsos: List<FfiQso>): String? {
        val counts = mutableMapOf<String, Int>()
        for (qso in qsos) {
            val grid = qso.myGrid ?: continue
            if (grid.length < 4) continue
            val prefix = grid.substring(0, 4).uppercase()
            counts[prefix] = (counts[prefix] ?: 0) + 1
        }
        return counts.maxByOrNull { it.value }?.key
    }

    /**
     * Renders the themed share map PNG (+ ring labels for azimuthal) for
     * `clusters` traced from `homeCoordinate`. Returns null if `style` is
     * [FfiShareMapStyle.AZIMUTHAL] and `homeCoordinate` is unresolvable — the
     * caller should have already hidden that style option in that case (see
     * [BragSheetShareStyle.availableStyles]), so this is a defensive no-op.
     *
     * Runs the FFI render call synchronously; callers must dispatch on
     * [kotlinx.coroutines.Dispatchers.IO].
     */
    fun renderMap(
        style: FfiShareMapStyle,
        clusters: List<BragSheetMapCluster>,
        homeCoordinate: FfiCoordinate?,
    ): BragShareMapResult? {
        if (style == FfiShareMapStyle.AZIMUTHAL && homeCoordinate == null) return null

        val pins = clusters.map { cluster ->
            FfiSharePin(
                lat = cluster.coordinate.latitude,
                lon = cluster.coordinate.longitude,
                kind = FfiSharePinColorKind.COUNT,
                count = cluster.count.toUInt(),
                red = 0f,
                green = 0f,
                blue = 0f,
                alpha = 0f,
            )
        }
        val traces = homeCoordinate?.let { home ->
            clusters.map { cluster ->
                FfiShareTrace(
                    fromLat = home.latitude,
                    fromLon = home.longitude,
                    toLat = cluster.coordinate.latitude,
                    toLon = cluster.coordinate.longitude,
                )
            }
        }.orEmpty()

        val input: FfiShareMapInput = if (style == FfiShareMapStyle.AZIMUTHAL) {
            // Azimuthal: centered on home; lat/lon span are ignored by the
            // Rust renderer for this path (range rings fill the canvas).
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
            // Flat styles: bounds-midpoint + aspect-fit viewport over home +
            // all cluster coordinates — the shared framing contract, not a
            // hand-rolled span.
            val coords = clusters.map { FfiCoordinate(it.coordinate.latitude, it.coordinate.longitude) } +
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
        return BragShareMapResult(pngBytes = image.pngBytes, ringLabels = image.ringLabels)
    }
}

/** Rendered map PNG bytes + azimuthal ring-label overlay anchors (empty for flat styles). */
data class BragShareMapResult(
    val pngBytes: ByteArray,
    val ringLabels: List<uniffi.cw_ffi.FfiRingLabel>,
)
