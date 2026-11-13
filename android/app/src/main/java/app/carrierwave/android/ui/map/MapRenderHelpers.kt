package app.carrierwave.android.ui.map

import android.graphics.Color as AndroidColor
import org.json.JSONArray
import org.json.JSONObject
import org.osmdroid.util.BoundingBox
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Polygon
import org.osmdroid.views.overlay.Polyline
import uniffi.cw_ffi.FfiMapArc
import uniffi.cw_ffi.FfiMapBounds
import uniffi.cw_ffi.FfiMapPolyline

/**
 * Shared osmdroid rendering helpers for the QSO map surfaces: the full-screen
 * `MapScreen` and the compact per-QSO/callsign map cards. Extracted so the
 * arc/camera-framing logic isn't duplicated across call sites.
 */

/**
 * Small filled-dot marker (a [DOT_MARKER_SIDES]-gon approximating a circle),
 * shared by [app.carrierwave.android.ui.sessions.SessionMapCard]'s rove-stop
 * dots and [app.carrierwave.android.ui.spots.SpotsMiniMap]'s spotter/home
 * dots. Screen-size-independent: degrees-based radius scaled by zoom would
 * drift, so callers pass a fixed [radiusDegrees].
 */
internal fun dotMarker(
    map: MapView,
    center: GeoPoint,
    radiusDegrees: Double,
    fillColor: Int,
    title: String? = null,
): Polygon {
    val points = (0 until DOT_MARKER_SIDES).map { i ->
        val angle = 2.0 * Math.PI * i / DOT_MARKER_SIDES
        GeoPoint(
            center.latitude + radiusDegrees * Math.cos(angle),
            center.longitude + radiusDegrees * Math.sin(angle),
        )
    }
    return Polygon(map).apply {
        this.points = points
        fillPaint.color = AndroidColor.argb(220, AndroidColor.red(fillColor), AndroidColor.green(fillColor), AndroidColor.blue(fillColor))
        outlinePaint.color = AndroidColor.WHITE
        outlinePaint.strokeWidth = 2f
        if (title != null) {
            this.title = title
        }
    }
}

private const val DOT_MARKER_SIDES = 12

/** Draw one translucent white polyline per arc segment (great-circle paths that cross the antimeridian split into segments). */
internal fun addArcs(map: MapView, arcs: List<FfiMapArc>) {
    arcs.forEach { arc ->
        arc.segments.forEach { segment ->
            map.overlays.add(
                Polyline(map).apply {
                    setPoints(segment.points.map { GeoPoint(it.latitude, it.longitude) })
                    outlinePaint.color = AndroidColor.argb(128, 255, 255, 255)
                    outlinePaint.strokeWidth = 3f
                },
            )
        }
    }
}

/** Draw a single arc's polylines (already-segmented great-circle path), same styling as [addArcs]. */
internal fun addPolylines(map: MapView, polylines: List<FfiMapPolyline>) {
    polylines.forEach { polyline ->
        map.overlays.add(
            Polyline(map).apply {
                setPoints(polyline.points.map { GeoPoint(it.latitude, it.longitude) })
                outlinePaint.color = AndroidColor.argb(128, 255, 255, 255)
                outlinePaint.strokeWidth = 3f
            },
        )
    }
}

/**
 * Fit the camera to the Rust-computed QSO bounds (iOS parity: first-load
 * framing from `FfiMapBounds` camera spans). Near-global spans skip the
 * bounding-box math — a wrapped box degenerates when the span approaches 360°.
 */
internal fun frameBounds(map: MapView, bounds: FfiMapBounds) {
    if (bounds.cameraLonSpan >= 300.0 || bounds.cameraLatSpan >= 170.0) {
        map.controller.setZoom(2.0)
        map.controller.setCenter(GeoPoint(bounds.centerLat.coerceIn(-85.0, 85.0), wrapLongitude(bounds.centerLon)))
        return
    }
    // Web-mercator tiles clip at ±85°; BoundingBox rejects latitudes beyond that.
    val north = (bounds.centerLat + bounds.cameraLatSpan / 2).coerceIn(-85.0, 85.0)
    val south = (bounds.centerLat - bounds.cameraLatSpan / 2).coerceIn(-85.0, 85.0)
    // east < west after wrapping is fine: osmdroid treats it as spanning the antimeridian.
    val east = wrapLongitude(bounds.centerLon + bounds.cameraLonSpan / 2)
    val west = wrapLongitude(bounds.centerLon - bounds.cameraLonSpan / 2)
    val box = BoundingBox(north, east, south, west)
    if (map.width > 0 && map.height > 0) {
        map.zoomToBoundingBox(box, false)
    } else {
        map.addOnFirstLayoutListener { _, _, _, _, _ -> map.zoomToBoundingBox(box, false) }
    }
}

/**
 * Fit the camera to a simple two-point bounding box (QSO detail / callsign
 * cards, which don't have a Rust-computed [FfiMapBounds]). Adds a small
 * padding factor so the pins aren't flush against the card edges.
 */
internal fun frameBoundingBox(map: MapView, points: List<GeoPoint>) {
    if (points.isEmpty()) return
    if (points.size == 1) {
        map.controller.setZoom(6.0)
        map.controller.setCenter(points.first())
        return
    }
    val north = points.maxOf { it.latitude }.coerceIn(-85.0, 85.0)
    val south = points.minOf { it.latitude }.coerceIn(-85.0, 85.0)
    val east = points.maxOf { it.longitude }
    val west = points.minOf { it.longitude }
    val box = BoundingBox(north, east, south, west).increaseByScale(1.4f)
    if (map.width > 0 && map.height > 0) {
        map.zoomToBoundingBox(box, false)
    } else {
        map.addOnFirstLayoutListener { _, _, _, _, _ -> map.zoomToBoundingBox(box, false) }
    }
}

internal fun wrapLongitude(lon: Double): Double = ((lon + 180.0).mod(360.0)) - 180.0

/**
 * Marker color for an RBN `timelineSnrColorBand` result (3 green / 2 blue /
 * 1 orange / 0 red). Shared by [app.carrierwave.android.ui.spots.SpotsMiniMap]
 * and [app.carrierwave.android.ui.sessions.TimelineReplayScreen].
 */
internal fun snrColor(band: UByte): Int = when (band.toInt()) {
    3 -> AndroidColor.rgb(52, 199, 89) // green
    2 -> AndroidColor.BLUE
    1 -> AndroidColor.rgb(255, 149, 0) // orange
    else -> AndroidColor.RED
}

// MARK: - GeoJSON → osmdroid conversion (park map overlays, phase C)

/**
 * One decoded polygon: an exterior ring plus any interior holes, in
 * `GeoPoint` order. Mirrors iOS `MergedPolygon`/`DecodedPolygonRings` (minus
 * the skirt buffer / zoomed-out variant, which the Android renderer doesn't
 * need — osmdroid draws the exact ring at every zoom).
 */
internal data class DecodedPolygonRing(val exterior: List<GeoPoint>, val holes: List<List<GeoPoint>>)

/**
 * Shared GeoJSON geometry decoder for every park-map overlay layer (park/trail
 * boundaries, admin boundaries, SOTA zones, WWFF-borrowed boundaries). Per the
 * Task 7/10 decode contract, `FfiGeoBoundary.geojson` is GEOMETRY-ONLY — a bare
 * `Polygon`, `MultiPolygon`, or a `GeometryCollection` of those (one cache row
 * can hold several pre-merged features). Non-polygon `GeometryCollection`
 * members (Point, LineString, ...) are skipped resiliently rather than
 * throwing, matching iOS's `SafeGeometry`. Returns an empty list for
 * unparseable / unsupported input.
 */
internal fun geojsonToPolygonRings(geojson: String): List<DecodedPolygonRing> {
    val root = runCatching { JSONObject(geojson) }.getOrNull() ?: return emptyList()
    return decodeGeometry(root)
}

private fun decodeGeometry(geometry: JSONObject): List<DecodedPolygonRing> {
    return when (geometry.optString("type")) {
        "Polygon" -> {
            val rings = geometry.optJSONArray("coordinates") ?: return emptyList()
            listOfNotNull(ringsToPolygon(rings))
        }
        "MultiPolygon" -> {
            val polygons = geometry.optJSONArray("coordinates") ?: return emptyList()
            (0 until polygons.length()).mapNotNull { i ->
                polygons.optJSONArray(i)?.let { ringsToPolygon(it) }
            }
        }
        "GeometryCollection" -> {
            val members = geometry.optJSONArray("geometries") ?: return emptyList()
            (0 until members.length()).flatMap { i ->
                members.optJSONObject(i)?.let { decodeGeometry(it) } ?: emptyList()
            }
        }
        else -> emptyList()
    }
}

/** One polygon's ring group: `[exterior, hole1, hole2, ...]`, each ring `[[lon, lat], ...]`. */
private fun ringsToPolygon(rings: JSONArray): DecodedPolygonRing? {
    if (rings.length() == 0) return null
    val exterior = rings.optJSONArray(0)?.let(::coordinatesToPoints) ?: return null
    if (exterior.size < 3) return null
    val holes = (1 until rings.length()).mapNotNull { i ->
        rings.optJSONArray(i)?.let(::coordinatesToPoints)?.takeIf { it.size >= 3 }
    }
    return DecodedPolygonRing(exterior, holes)
}

/** A ring's raw `[[lon, lat], ...]` coordinate array → `GeoPoint`s (GeoJSON is lon-first). */
private fun coordinatesToPoints(ring: JSONArray): List<GeoPoint> =
    (0 until ring.length()).mapNotNull { i ->
        val pair = ring.optJSONArray(i) ?: return@mapNotNull null
        if (pair.length() < 2) return@mapNotNull null
        GeoPoint(pair.optDouble(1), pair.optDouble(0))
    }

/**
 * Add one filled+outlined [Polygon] overlay per decoded ring group (exterior +
 * holes rendered as osmdroid's polygon `holes` list). Shared by every boundary
 * layer (park/trail/admin/zone/WWFF) so the fill/stroke styling only lives
 * here.
 */
internal fun addBoundaryPolygons(
    map: MapView,
    rings: List<DecodedPolygonRing>,
    fillColor: Int,
    strokeColor: Int,
    strokeWidth: Float = 2f,
    title: String? = null,
    onTap: (() -> Boolean)? = null,
) {
    rings.forEach { ring ->
        map.overlays.add(
            Polygon(map).apply {
                points = ring.exterior
                if (ring.holes.isNotEmpty()) {
                    this.holes = ring.holes
                }
                fillPaint.color = fillColor
                outlinePaint.color = strokeColor
                outlinePaint.strokeWidth = strokeWidth
                if (title != null) {
                    this.title = title
                }
                if (onTap != null) {
                    setOnClickListener { _, _, _ -> onTap() }
                }
            },
        )
    }
}

/** Add one outline-only [Polyline] per decoded ring's exterior — used for admin boundaries (no fill). */
internal fun addBoundaryOutlines(
    map: MapView,
    rings: List<DecodedPolygonRing>,
    strokeColor: Int,
    strokeWidth: Float = 2f,
) {
    rings.forEach { ring ->
        map.overlays.add(
            Polyline(map).apply {
                setPoints(ring.exterior + ring.exterior.first())
                outlinePaint.color = strokeColor
                outlinePaint.strokeWidth = strokeWidth
            },
        )
    }
}

// MARK: - Grid-square / TOTA tile rectangles (client-side geometry, no FFI round trip)

/**
 * Closed-rectangle boundary paths for Maidenhead grid squares (4-char, 2°lon
 * × 1°lat) or TOTA tiles (6-char, 2/24°lon × 1/24°lat) visible in a
 * [BoundingBox]. Pure index math — mirrors iOS `MapGridGeometry.gridRects`/
 * `tileRects` (`ParkSearchMapKit+Grids.swift`), which likewise computes these
 * client-side rather than round-tripping through `maidenheadGridBounds`/
 * `maidenheadTileBounds` (those FFI exports resolve a *named* grid/tile, not
 * "every cell visible in a viewport" — no batch equivalent exists).
 */
internal object GridRectGeometry {
    private const val MAX_VISIBLE_GRIDS = 400
    private const val MAX_VISIBLE_TILES = 1_500
    private const val GRID_LON_STEP = 2.0
    private const val GRID_LAT_STEP = 1.0
    private const val TILE_LON_STEP = 2.0 / 24.0
    private const val TILE_LAT_STEP = 1.0 / 24.0
    /** Don't render tiles until zoomed in tighter than this span (degrees). */
    const val TILE_SPAN_GATE = 0.6
    /** Don't render grid squares past this span (degrees). */
    const val GRID_LAT_SPAN_GATE = 30.0
    const val GRID_LON_SPAN_GATE = 60.0

    /** Closed rectangles for the 4-char grid squares visible in [box]. */
    fun gridRects(box: BoundingBox): List<List<GeoPoint>> {
        if (latSpan(box) >= GRID_LAT_SPAN_GATE || lonSpan(box) >= GRID_LON_SPAN_GATE) return emptyList()
        val rects = rectsFor(box, GRID_LON_STEP, GRID_LAT_STEP)
        return if (rects.size <= MAX_VISIBLE_GRIDS) rects else emptyList()
    }

    /** Closed rectangles for the 6-char TOTA tiles visible in [box]. */
    fun tileRects(box: BoundingBox): List<List<GeoPoint>> {
        if (latSpan(box) >= TILE_SPAN_GATE || lonSpan(box) >= TILE_SPAN_GATE) return emptyList()
        val rects = rectsFor(box, TILE_LON_STEP, TILE_LAT_STEP)
        return if (rects.size <= MAX_VISIBLE_TILES) rects else emptyList()
    }

    // `BoundingBox.getLatitudeSpan`/`getLongitudeSpan` are deprecated in this
    // osmdroid version (superseded by antimeridian-aware variants this call
    // site doesn't need); computing the plain span directly from the box's
    // own corners avoids the deprecation warning without changing behavior.
    private fun latSpan(box: BoundingBox): Double = box.latNorth - box.latSouth
    private fun lonSpan(box: BoundingBox): Double = box.lonEast - box.lonWest

    private fun rectsFor(box: BoundingBox, lonStep: Double, latStep: Double): List<List<GeoPoint>> {
        val swLat = box.latSouth.coerceAtLeast(-90.0)
        val neLat = box.latNorth.coerceAtMost(90.0)
        val swLon = box.lonWest.coerceAtLeast(-180.0)
        val neLon = box.lonEast.coerceAtMost(180.0)
        val startLon = kotlin.math.floor((swLon + 180) / lonStep).toInt()
        val endLon = kotlin.math.floor((neLon + 180) / lonStep).toInt()
        val startLat = kotlin.math.floor((swLat + 90) / latStep).toInt()
        val endLat = kotlin.math.floor((neLat + 90) / latStep).toInt()
        val rects = mutableListOf<List<GeoPoint>>()
        for (lonIdx in startLon..endLon) {
            val cellSwLon = -180.0 + lonIdx * lonStep
            val cellNeLon = cellSwLon + lonStep
            for (latIdx in startLat..endLat) {
                val cellSwLat = -90.0 + latIdx * latStep
                val cellNeLat = cellSwLat + latStep
                rects.add(
                    listOf(
                        GeoPoint(cellSwLat, cellSwLon),
                        GeoPoint(cellNeLat, cellSwLon),
                        GeoPoint(cellNeLat, cellNeLon),
                        GeoPoint(cellSwLat, cellNeLon),
                        GeoPoint(cellSwLat, cellSwLon),
                    ),
                )
            }
        }
        return rects
    }
}

/** Add grid-square / TOTA-tile boundary outlines (thin translucent polylines, no fill). */
internal fun addGridRectOverlays(map: MapView, rects: List<List<GeoPoint>>, strokeColor: Int, strokeWidth: Float = 2f) {
    rects.forEach { rect ->
        map.overlays.add(
            Polyline(map).apply {
                setPoints(rect)
                outlinePaint.color = strokeColor
                outlinePaint.strokeWidth = strokeWidth
            },
        )
    }
}
