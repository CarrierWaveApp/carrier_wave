import CarrierWaveCore
import CoreLocation
import MapKit

// MARK: - AdminBoundary

/// A US administrative boundary (state or county) materialized from an
/// `FfiGeoBoundary` handed back by `ParkMapApi.adminBoundariesInBox`. Rendered as
/// outline polylines on the reference map — no fill, no skirt, no selection.
struct AdminBoundary: Identifiable {
    enum Kind: String {
        case state
        case county
    }

    let id: String
    let kind: Kind
    let name: String
    /// All rings (polygon exteriors + holes) as closed coordinate paths.
    let rings: [[CLLocationCoordinate2D]]
    /// Bounding box covering all rings, for viewport culling.
    let bbox: RingBBox

    /// Whether this boundary intersects the given map region.
    nonisolated func intersects(region: MKCoordinateRegion) -> Bool {
        let west = region.center.longitude - region.span.longitudeDelta / 2
        let east = region.center.longitude + region.span.longitudeDelta / 2
        let south = region.center.latitude - region.span.latitudeDelta / 2
        let north = region.center.latitude + region.span.latitudeDelta / 2
        return bbox.minLat <= north && bbox.maxLat >= south
            && bbox.minLon <= east && bbox.maxLon >= west
    }
}

// MARK: - FfiGeoBoundary → AdminBoundary

extension AdminBoundary {
    /// Build an `AdminBoundary` from an `FfiGeoBoundary`. The kind (state vs
    /// county) comes from `FfiGeoBoundary.kind` (`"admin_state"` /
    /// `"admin_county"`, tagged Rust-side from the feature's own kind); when that
    /// is absent (legacy cache rows), it falls back to the FIPS-id-length
    /// heuristic — a ≤2-char id is a state, else a county. Returns nil when the
    /// payload yields no ring. Nonisolated so it can run off the main thread.
    nonisolated static func from(ffi boundary: FfiGeoBoundary) -> AdminBoundary? {
        guard let geometry = GeoJSONGeometry.decode(from: boundary.geojson) else {
            return nil
        }
        let rings = geometry.polygonRingGroups
            .flatMap { $0 }
            .map { GeoJSONGeometry.toCoordinates($0) }
            .filter { $0.count >= 2 }
        guard !rings.isEmpty else {
            return nil
        }
        let kind = kind(for: boundary)
        let bbox = ringBoundingBox(rings.flatMap { $0 })
        return AdminBoundary(
            id: boundary.reference,
            kind: kind,
            name: boundary.name ?? boundary.reference,
            rings: rings,
            bbox: bbox
        )
    }

    /// Resolve the boundary kind from the FFI `kind` tag, falling back to the
    /// FIPS-id-length heuristic (≤2 chars = state) when the tag is absent.
    nonisolated private static func kind(for boundary: FfiGeoBoundary) -> Kind {
        switch boundary.kind {
        case "admin_state":
            .state
        case "admin_county":
            .county
        default:
            boundary.reference.count <= 2 ? .state : .county
        }
    }
}
