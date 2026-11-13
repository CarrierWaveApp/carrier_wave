// US administrative boundary (state + county) outline overlays for the Parks &
// Summits reference map. Served by the activities server (PostGIS) and rendered
// as plain outline polylines — no fill, no skirt, no selection.
//
// Gated by the `.activityLayers` experiment; toggled individually from the
// reference map's overlay menu in `ParkSearchMapView`.

import CoreLocation
import MapKit

// MARK: - StateLineOverlay

/// Outline polyline for a US state boundary ring.
nonisolated final class StateLineOverlay: MKPolyline {}

// MARK: - CountyLineOverlay

/// Outline polyline for a US county boundary ring.
nonisolated final class CountyLineOverlay: MKPolyline {}

// MARK: - Coordinator sync

extension ParkSearchMapKit.Coordinator {
    /// Diff the supplied admin boundaries against what's drawn, keyed by id, so
    /// we only add/remove overlays as the visible set changes.
    func syncAdmin(on map: MKMapView, boundaries: [AdminBoundary]) {
        let desiredIDs = Set(boundaries.map(\.id))

        for id in adminOverlays.keys where !desiredIDs.contains(id) {
            if let overlays = adminOverlays[id] {
                map.removeOverlays(overlays)
                adminOverlays[id] = nil
            }
        }

        for boundary in boundaries where adminOverlays[boundary.id] == nil {
            let overlays: [MKPolyline] = boundary.rings.map { ring -> MKPolyline in
                switch boundary.kind {
                case .state:
                    adminPolyline(StateLineOverlay.self, coordinates: ring)
                case .county:
                    adminPolyline(CountyLineOverlay.self, coordinates: ring)
                }
            }
            map.addOverlays(overlays, level: .aboveRoads)
            adminOverlays[boundary.id] = overlays
        }
    }

    private func adminPolyline<T: MKPolyline>(
        _: T.Type,
        coordinates: [CLLocationCoordinate2D]
    ) -> T {
        coordinates.withUnsafeBufferPointer { buf in
            T(coordinates: buf.baseAddress!, count: buf.count)
        }
    }
}
