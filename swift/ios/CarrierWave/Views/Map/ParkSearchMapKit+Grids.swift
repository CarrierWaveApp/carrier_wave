// Maidenhead grid-square and Tiles-on-the-Air (TOTA) tile boundary overlays for
// the Parks & Summits reference map. Both are fixed lat/lon grids computed
// client-side (no data sourcing), rendered as boundary polylines on the shared
// MKMapView so they pan in lockstep with park boundaries, trails, and radar.
//
// Gated by the `.activityLayers` experiment; toggled individually from the
// reference map's overlay menu in `ParkSearchMapView`.

import CarrierWaveCore
import CoreLocation
import MapKit
import SwiftUI

// MARK: - GridLineOverlay

/// Boundary polyline for a 4-char Maidenhead grid square (2° lon × 1° lat).
nonisolated final class GridLineOverlay: MKPolyline {}

// MARK: - TileLineOverlay

/// Boundary polyline for a 6-char TOTA tile / subsquare (≈5' lon × 2.5' lat).
nonisolated final class TileLineOverlay: MKPolyline {}

// MARK: - MapGridGeometry

/// Builds closed-rectangle boundary paths for the grid/tile overlays, with
/// zoom gates and hard caps so the map is never over-populated. Each result
/// carries a cheap signature (integer index bounds) so the coordinator can skip
/// rebuilding overlays while the visible cells haven't changed.
enum MapGridGeometry {
    // MARK: Internal

    /// Closed rectangles for the 4-char grid squares visible in `region`.
    /// Reuses `GridSquareComputation` (400-grid cap + 30°×60° span gate).
    static func gridRects(in region: MKCoordinateRegion) -> (rects: [[CLLocationCoordinate2D]], signature: String) {
        let rects = GridSquareComputation.visibleGrids(in: region).map(\.boundaryPath)
        return (rects, signature(in: region, lonStep: 2.0, latStep: 1.0, prefix: "g"))
    }

    /// Closed rectangles for the 6-char TOTA tiles visible in `region`.
    static func tileRects(in region: MKCoordinateRegion) -> (rects: [[CLLocationCoordinate2D]], signature: String) {
        let span = region.span
        // Tiles are tiny (~5 km); only draw them once zoomed in tightly so we
        // don't carpet the map with thousands of rectangles.
        guard span.latitudeDelta < tileSpanGate, span.longitudeDelta < tileSpanGate else {
            return ([], "t:off")
        }

        let bounds = indexBounds(in: region, lonStep: tileLonStep, latStep: tileLatStep)
        let count = (bounds.endLon - bounds.startLon + 1) * (bounds.endLat - bounds.startLat + 1)
        guard count > 0, count <= maxVisibleTiles else {
            return ([], "t:over")
        }

        var rects: [[CLLocationCoordinate2D]] = []
        rects.reserveCapacity(count)
        for lonIdx in bounds.startLon ... bounds.endLon {
            let swLon = -180.0 + Double(lonIdx) * tileLonStep
            let neLon = swLon + tileLonStep
            for latIdx in bounds.startLat ... bounds.endLat {
                let swLat = -90.0 + Double(latIdx) * tileLatStep
                let neLat = swLat + tileLatStep
                rects.append([
                    CLLocationCoordinate2D(latitude: swLat, longitude: swLon),
                    CLLocationCoordinate2D(latitude: neLat, longitude: swLon),
                    CLLocationCoordinate2D(latitude: neLat, longitude: neLon),
                    CLLocationCoordinate2D(latitude: swLat, longitude: neLon),
                    CLLocationCoordinate2D(latitude: swLat, longitude: swLon),
                ])
            }
        }
        return (rects, signature(in: region, lonStep: tileLonStep, latStep: tileLatStep, prefix: "t"))
    }

    // MARK: Private

    private struct IndexBounds {
        let startLon: Int
        let endLon: Int
        let startLat: Int
        let endLat: Int
    }

    /// Maximum tile rectangles to render before bailing out (perf guard).
    private static let maxVisibleTiles = 1_500
    /// A 6-char tile spans 2°/24 longitude × 1°/24 latitude.
    private static let tileLonStep = 2.0 / 24.0
    private static let tileLatStep = 1.0 / 24.0
    /// Show tiles only when both span deltas are below this (degrees).
    private static let tileSpanGate = 0.6

    private static func indexBounds(
        in region: MKCoordinateRegion,
        lonStep: Double,
        latStep: Double
    ) -> IndexBounds {
        let center = region.center
        let span = region.span
        let swLat = max(center.latitude - span.latitudeDelta / 2, -90)
        let neLat = min(center.latitude + span.latitudeDelta / 2, 90)
        let swLon = max(center.longitude - span.longitudeDelta / 2, -180)
        let neLon = min(center.longitude + span.longitudeDelta / 2, 180)
        return IndexBounds(
            startLon: Int(floor((swLon + 180) / lonStep)),
            endLon: Int(floor((neLon + 180) / lonStep)),
            startLat: Int(floor((swLat + 90) / latStep)),
            endLat: Int(floor((neLat + 90) / latStep))
        )
    }

    private static func signature(
        in region: MKCoordinateRegion,
        lonStep: Double,
        latStep: Double,
        prefix: String
    ) -> String {
        let bounds = indexBounds(in: region, lonStep: lonStep, latStep: latStep)
        return "\(prefix):\(bounds.startLon)-\(bounds.endLon)-\(bounds.startLat)-\(bounds.endLat)"
    }
}

// MARK: - Coordinator sync

extension ParkSearchMapKit.Coordinator {
    /// Diff the visible grid squares against what's drawn; rebuild only when the
    /// set of visible cells changes (cheap signature compare).
    func syncGrids(on map: MKMapView, enabled: Bool) {
        let result: (rects: [[CLLocationCoordinate2D]], signature: String) =
            enabled ? MapGridGeometry.gridRects(in: map.region) : ([], "g:off")
        guard result.1 != lastGridSignature else {
            return
        }
        lastGridSignature = result.1
        map.removeOverlays(gridLineOverlays)
        let overlays = result.0.map { polyline(GridLineOverlay.self, coordinates: $0) }
        gridLineOverlays = overlays
        if !overlays.isEmpty {
            map.addOverlays(overlays, level: .aboveRoads)
        }
    }

    /// Diff the visible TOTA tiles against what's drawn.
    func syncTiles(on map: MKMapView, enabled: Bool) {
        let result: (rects: [[CLLocationCoordinate2D]], signature: String) =
            enabled ? MapGridGeometry.tileRects(in: map.region) : ([], "t:off")
        guard result.1 != lastTileSignature else {
            return
        }
        lastTileSignature = result.1
        map.removeOverlays(tileLineOverlays)
        let overlays = result.0.map { polyline(TileLineOverlay.self, coordinates: $0) }
        tileLineOverlays = overlays
        if !overlays.isEmpty {
            map.addOverlays(overlays, level: .aboveRoads)
        }
    }

    /// Thin stroked renderer shared by the grid/tile/admin boundary lines.
    func lineRenderer(
        _ polyline: MKPolyline,
        color: UIColor,
        width: CGFloat = 1,
        alpha: CGFloat = 0.5
    ) -> MKPolylineRenderer {
        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = color.withAlphaComponent(alpha)
        renderer.lineWidth = width
        return renderer
    }

    private func polyline<T: MKPolyline>(
        _: T.Type,
        coordinates: [CLLocationCoordinate2D]
    ) -> T {
        coordinates.withUnsafeBufferPointer { buf in
            T(coordinates: buf.baseAddress!, count: buf.count)
        }
    }
}
