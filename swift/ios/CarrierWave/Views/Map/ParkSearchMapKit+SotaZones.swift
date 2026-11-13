// SOTA activation-zone fill overlays for the Parks & Summits reference map.
// Zones are computed server-side from DEM data (the "25 m below the summit"
// rule) and rendered as translucent filled polygons, keyed by summit code.
//
// Gated by the `.activityLayers` experiment; toggled via the overlay menu.

import CoreLocation
import MapKit

// MARK: - SotaZoneFillOverlay

/// Filled polygon for a SOTA activation zone (carries the summit code).
nonisolated final class SotaZoneFillOverlay: MKPolygon {
    var zoneCode: String?
}

// MARK: - Coordinator sync

extension ParkSearchMapKit.Coordinator {
    /// Diff activation-zone overlays against what's drawn, keyed by summit code.
    func syncSotaZones(on map: MKMapView, zones: [SOTAZone]) {
        let desired = Set(zones.map(\.code))

        for code in sotaZoneOverlays.keys where !desired.contains(code) {
            if let overlays = sotaZoneOverlays[code] {
                map.removeOverlays(overlays)
                sotaZoneOverlays[code] = nil
            }
        }

        for zone in zones where sotaZoneOverlays[zone.code] == nil {
            let overlays = zone.polygons.map { polygon -> SotaZoneFillOverlay in
                let overlay = zonePolygon(exterior: polygon.exterior, holes: polygon.holes)
                overlay.zoneCode = zone.code
                return overlay
            }
            map.addOverlays(overlays, level: .aboveRoads)
            sotaZoneOverlays[zone.code] = overlays
        }
    }

    /// Translucent renderer for activation-zone fills.
    func zoneFillRenderer(_ polygon: MKPolygon) -> MKPolygonRenderer {
        let renderer = MKPolygonRenderer(polygon: polygon)
        renderer.fillColor = UIColor.systemTeal.withAlphaComponent(0.22)
        renderer.strokeColor = UIColor.systemTeal.withAlphaComponent(0.8)
        renderer.lineWidth = 1.5
        return renderer
    }

    private func zonePolygon(
        exterior: [CLLocationCoordinate2D],
        holes: [[CLLocationCoordinate2D]]
    ) -> SotaZoneFillOverlay {
        let coords = exterior
        if holes.isEmpty {
            return coords.withUnsafeBufferPointer { buf in
                SotaZoneFillOverlay(coordinates: buf.baseAddress!, count: buf.count)
            }
        }
        let interiors = holes.map { hole -> MKPolygon in
            let holeCoords = hole
            return holeCoords.withUnsafeBufferPointer { buf in
                MKPolygon(coordinates: buf.baseAddress!, count: buf.count)
            }
        }
        return coords.withUnsafeBufferPointer { buf in
            SotaZoneFillOverlay(
                coordinates: buf.baseAddress!,
                count: buf.count,
                interiorPolygons: interiors
            )
        }
    }
}
