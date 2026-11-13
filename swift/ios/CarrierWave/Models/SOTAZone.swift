import CarrierWaveCore
import CoreLocation
import MapKit

// MARK: - SOTAZone

/// A SOTA activation-zone polygon (the terrain within 25 vertical metres of the
/// summit), computed server-side from DEM data and cached in the store's
/// `sota_zone` table. Materialized either from the bulk `SOTAZonesCache`
/// (carries altitude) or from `ParkMapApi.sotaZonesFor` (a cached read keyed by
/// summit code).
struct SOTAZone: Identifiable {
    let code: String
    let altitudeM: Double?
    let polygons: [ZonePolygon]
    /// Bounding box covering all polygons, for viewport culling.
    let bbox: RingBBox

    var id: String {
        code
    }

    nonisolated func intersects(region: MKCoordinateRegion) -> Bool {
        let west = region.center.longitude - region.span.longitudeDelta / 2
        let east = region.center.longitude + region.span.longitudeDelta / 2
        let south = region.center.latitude - region.span.latitudeDelta / 2
        let north = region.center.latitude + region.span.latitudeDelta / 2
        return bbox.minLat <= north && bbox.maxLat >= south
            && bbox.minLon <= east && bbox.maxLon >= west
    }
}

// MARK: - ZonePolygon

struct ZonePolygon {
    let exterior: [CLLocationCoordinate2D]
    let holes: [[CLLocationCoordinate2D]]
}

// MARK: - FfiGeoBoundary → SOTAZone

extension SOTAZone {
    /// Build a `SOTAZone` from an `FfiGeoBoundary` (the `sotaZonesFor` shape).
    /// `FfiGeoBoundary` carries no altitude, so `altitudeM` is nil on this path.
    /// Returns nil when the payload yields no polygon.
    nonisolated static func from(ffi boundary: FfiGeoBoundary) -> SOTAZone? {
        guard let geometry = GeoJSONGeometry.decode(from: boundary.geojson) else {
            return nil
        }
        let polygons = geometry.decodedPolygons().map { rings in
            ZonePolygon(exterior: rings.exterior, holes: rings.holes)
        }
        guard !polygons.isEmpty else {
            return nil
        }
        return SOTAZone(
            code: boundary.reference,
            altitudeM: nil,
            polygons: polygons,
            bbox: ringBoundingBox(polygons.flatMap(\.exterior))
        )
    }
}
