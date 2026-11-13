import CoreLocation
import MapKit

// MARK: - WWFFRenderItem

/// A WWFF reference prepared for map rendering. WWFF publishes no boundaries, so
/// where a `KFF-####` reference cross-maps to a POTA `US-####` park we borrow
/// that park's polygon (`polygons` non-empty); otherwise we fall back to a point
/// marker at the reference coordinate.
struct WWFFRenderItem: Identifiable {
    let code: String
    let name: String
    let center: CLLocationCoordinate2D
    /// Borrowed POTA polygon rings (exterior + holes). Empty → render a marker.
    let polygons: [ZonePolygon]
    /// Bounding box covering the polygons (or a small box around the marker).
    let bbox: RingBBox

    var id: String {
        code
    }

    nonisolated var hasBoundary: Bool {
        !polygons.isEmpty
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
