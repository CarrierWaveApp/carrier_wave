// WWFF overlays for the Parks & Summits reference map. WWFF has no boundary
// data, so we borrow the cross-mapped POTA park polygon (tinted magenta) where
// one exists, and drop a small diamond marker otherwise. Both are MKPolygon
// subclasses (reusing the proven overlay path) so no annotation/clustering
// machinery is touched.
//
// Gated by the `.activityLayers` experiment; toggled via the overlay menu.

import CoreLocation
import MapKit

// MARK: - WWFFFillOverlay

/// Borrowed POTA polygon rendered as a WWFF boundary (carries the WWFF code).
nonisolated final class WWFFFillOverlay: MKPolygon {
    var wwffCode: String?
}

// MARK: - WWFFMarkerOverlay

/// Small diamond marking a WWFF reference with no borrowable boundary.
nonisolated final class WWFFMarkerOverlay: MKPolygon {
    var wwffCode: String?
}

// MARK: - Coordinator sync

extension ParkSearchMapKit.Coordinator {
    /// Diff WWFF overlays against what's drawn, keyed by WWFF code.
    func syncWWFF(on map: MKMapView, items: [WWFFRenderItem]) {
        let desired = Set(items.map(\.code))

        for code in wwffOverlays.keys where !desired.contains(code) {
            if let overlays = wwffOverlays[code] {
                map.removeOverlays(overlays)
                wwffOverlays[code] = nil
            }
        }

        for item in items where wwffOverlays[item.code] == nil {
            let overlays = buildWWFFOverlays(for: item)
            map.addOverlays(overlays, level: .aboveRoads)
            wwffOverlays[item.code] = overlays
        }
    }

    /// Renderers for WWFF overlays, split out to keep `rendererFor` short.
    func wwffRenderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        switch overlay {
        case let fill as WWFFFillOverlay:
            let renderer = MKPolygonRenderer(polygon: fill)
            renderer.fillColor = UIColor.systemPink.withAlphaComponent(0.2)
            renderer.strokeColor = UIColor.systemPink.withAlphaComponent(0.85)
            renderer.lineWidth = 2
            return renderer
        case let marker as WWFFMarkerOverlay:
            let renderer = MKPolygonRenderer(polygon: marker)
            renderer.fillColor = UIColor.systemPink.withAlphaComponent(0.85)
            renderer.strokeColor = .white
            renderer.lineWidth = 1
            return renderer
        default:
            return nil
        }
    }

    private func buildWWFFOverlays(for item: WWFFRenderItem) -> [MKPolygon] {
        guard item.hasBoundary else {
            let marker = markerDiamond(at: item.center)
            marker.wwffCode = item.code
            return [marker]
        }
        return item.polygons.map { polygon in
            let fill = fillOverlay(exterior: polygon.exterior, holes: polygon.holes)
            fill.wwffCode = item.code
            return fill
        }
    }

    private func fillOverlay(
        exterior: [CLLocationCoordinate2D],
        holes: [[CLLocationCoordinate2D]]
    ) -> WWFFFillOverlay {
        let coords = exterior
        if holes.isEmpty {
            return coords.withUnsafeBufferPointer { buf in
                WWFFFillOverlay(coordinates: buf.baseAddress!, count: buf.count)
            }
        }
        let interiors = holes.map { hole -> MKPolygon in
            let holeCoords = hole
            return holeCoords.withUnsafeBufferPointer { buf in
                MKPolygon(coordinates: buf.baseAddress!, count: buf.count)
            }
        }
        return coords.withUnsafeBufferPointer { buf in
            WWFFFillOverlay(coordinates: buf.baseAddress!, count: buf.count, interiorPolygons: interiors)
        }
    }

    private func markerDiamond(at center: CLLocationCoordinate2D) -> WWFFMarkerOverlay {
        let half = 0.0035
        let corners = [
            CLLocationCoordinate2D(latitude: center.latitude + half, longitude: center.longitude),
            CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude + half),
            CLLocationCoordinate2D(latitude: center.latitude - half, longitude: center.longitude),
            CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude - half),
        ]
        return corners.withUnsafeBufferPointer { buf in
            WWFFMarkerOverlay(coordinates: buf.baseAddress!, count: buf.count)
        }
    }
}
