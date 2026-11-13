import CarrierWaveCore
import CoreLocation
import Foundation
import MapKit

// MARK: - ParkBoundary

/// A park boundary polygon materialized from an `FfiGeoBoundary` handed back by
/// `ParkMapApi`. The server pre-merges overlapping park units, so the client no
/// longer runs a CGPath union — it just decodes the GeoJSON rings and precomputes
/// the render-time skirt / zoomed-out variants.
struct ParkBoundary: Identifiable {
    let reference: String
    let name: String
    let mergedPolygons: [MergedPolygon]
    /// Bounding box covering all polygons, for viewport culling.
    let bbox: RingBBox
    // Callout-only metadata, decoded from `FfiGeoBoundary.propertiesJson` (the
    // park's GeoJSON Feature properties, carried through the GIS cache). Nil when
    // absent (legacy cache rows / boundaries with no properties); the callout
    // hides each field when nil.
    let designation: String?
    let manager: String?
    let acreage: Double?
    let matchQuality: String?

    nonisolated var id: String {
        reference
    }

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

// MARK: - MergedPolygon

/// A polygon with an exterior ring, optional interior holes, and a precomputed skirt.
struct MergedPolygon {
    /// Full-detail exterior preserving narrow corridors and trail easements.
    let exterior: [CLLocationCoordinate2D]
    /// Simplified exterior with narrow spikes removed for zoomed-out display.
    let zoomedOutExterior: [CLLocationCoordinate2D]
    let holes: [[CLLocationCoordinate2D]]
    /// Precomputed 100-foot (30.48m) buffer ring for the skirt layer.
    let skirt: [CLLocationCoordinate2D]
}

// MARK: - GeoJSONGeometry

/// Handles Polygon, MultiPolygon, and GeometryCollection GeoJSON types.
/// Each polygon is an array of rings: [exterior, hole1, hole2, ...].
///
/// The `ParkMapApi` cache stores one row per reference: either a single
/// pre-merged geometry (Polygon/MultiPolygon) or, when a reference still carries
/// multiple features, a GeometryCollection wrapping them. This decode handles
/// all three so both cached shapes round-trip (Task 7 decode contract).
enum GeoJSONGeometry {
    /// A single polygon: [[exterior], [hole1], [hole2], ...]
    case polygon([[[Double]]])
    /// Multiple polygons, each with exterior + optional holes
    case multiPolygon([[[[Double]]]])
    /// A collection of geometries (only polygon members are extracted)
    case geometryCollection([GeoJSONGeometry])

    // MARK: Internal

    /// All polygons as arrays of ring groups (exterior + holes each).
    nonisolated var polygonRingGroups: [[[[Double]]]] {
        switch self {
        case let .polygon(rings):
            [rings]
        case let .multiPolygon(polygons):
            polygons
        case let .geometryCollection(geometries):
            geometries.flatMap(\.polygonRingGroups)
        }
    }

    /// Decode a bare GeoJSON geometry string (no Feature wrapper), returning nil
    /// when the payload is `"null"`, malformed, or an unsupported geometry type.
    nonisolated static func decode(from geojson: String) -> GeoJSONGeometry? {
        guard let data = geojson.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(GeoJSONGeometry.self, from: data)
    }

    nonisolated static func toCoordinates(
        _ ring: [[Double]]
    ) -> [CLLocationCoordinate2D] {
        ring.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count >= 2 else {
                return nil
            }
            return CLLocationCoordinate2D(
                latitude: pair[1], longitude: pair[0]
            )
        }
    }

    /// Decode this geometry into exterior+hole polygons in `(lat, lon)` order.
    nonisolated func decodedPolygons() -> [DecodedPolygonRings] {
        polygonRingGroups.compactMap { ringGroup in
            guard let exteriorRaw = ringGroup.first else {
                return nil
            }
            let exterior = Self.toCoordinates(exteriorRaw)
            guard exterior.count >= 3 else {
                return nil
            }
            let holes = ringGroup.dropFirst().map { Self.toCoordinates($0) }
                .filter { $0.count >= 3 }
            return DecodedPolygonRings(exterior: exterior, holes: holes)
        }
    }
}

// MARK: Codable

extension GeoJSONGeometry: Codable {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let geometryType = try container.decode(String.self, forKey: .type)

        switch geometryType {
        case "Polygon":
            let coords = try container.decode(
                [[[Double]]].self, forKey: .coordinates
            )
            self = .polygon(coords)

        case "MultiPolygon":
            let coords = try container.decode(
                [[[[Double]]]].self, forKey: .coordinates
            )
            self = .multiPolygon(coords)

        case "GeometryCollection":
            let members = try container.decode(
                [SafeGeometry].self, forKey: .geometries
            )
            let geometries = members.compactMap(\.geometry)
            self = .geometryCollection(geometries)

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported geometry type: \(geometryType)"
            )
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .polygon(rings):
            try container.encode("Polygon", forKey: .type)
            try container.encode(rings, forKey: .coordinates)
        case let .multiPolygon(polygons):
            try container.encode("MultiPolygon", forKey: .type)
            try container.encode(polygons, forKey: .coordinates)
        case let .geometryCollection(geometries):
            try container.encode("GeometryCollection", forKey: .type)
            try container.encode(geometries, forKey: .geometries)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case coordinates
        case geometries
    }
}

// MARK: - SafeGeometry

/// Wrapper that silently skips non-polygon geometry members in a GeometryCollection.
/// Point, LineString, etc. are irrelevant for boundary rendering.
private struct SafeGeometry: Codable {
    // MARK: Lifecycle

    nonisolated init(from decoder: Decoder) throws {
        geometry = try? GeoJSONGeometry(from: decoder)
    }

    // MARK: Internal

    let geometry: GeoJSONGeometry?

    nonisolated func encode(to encoder: Encoder) throws {
        try geometry?.encode(to: encoder)
    }
}

// MARK: - RingBBox

struct RingBBox {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double

    nonisolated var centerLat: Double {
        (minLat + maxLat) / 2
    }

    nonisolated var centerLon: Double {
        (minLon + maxLon) / 2
    }
}

nonisolated func ringBoundingBox(
    _ ring: [CLLocationCoordinate2D]
) -> RingBBox {
    var minLat = Double.infinity
    var maxLat = -Double.infinity
    var minLon = Double.infinity
    var maxLon = -Double.infinity
    for coord in ring {
        minLat = min(minLat, coord.latitude)
        maxLat = max(maxLat, coord.latitude)
        minLon = min(minLon, coord.longitude)
        maxLon = max(maxLon, coord.longitude)
    }
    return RingBBox(
        minLat: minLat, maxLat: maxLat,
        minLon: minLon, maxLon: maxLon
    )
}

// MARK: - DecodedPolygonRings

/// A decoded polygon with its exterior ring and any interior holes.
struct DecodedPolygonRings {
    let exterior: [CLLocationCoordinate2D]
    let holes: [[CLLocationCoordinate2D]]
}

// MARK: - BoundaryFeatureProperties

/// The GeoJSON Feature `properties` object carried alongside a boundary geometry
/// through the GIS cache (`FfiGeoBoundary.propertiesJson`). One struct covers
/// park, trail, and admin callout fields — each `from(ffi:)` reads the subset it
/// needs. All fields optional so a partial / legacy payload decodes cleanly.
struct BoundaryFeatureProperties: Decodable {
    // MARK: Lifecycle

    /// Explicit nonisolated decode so the conformance is usable from the
    /// nonisolated `from(ffi:)` builders (the target defaults to @MainActor
    /// isolation). Every key is `decodeIfPresent` — a partial / legacy payload
    /// decodes cleanly.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        designation = try container.decodeIfPresent(String.self, forKey: .designation)
        manager = try container.decodeIfPresent(String.self, forKey: .manager)
        acreage = try container.decodeIfPresent(Double.self, forKey: .acreage)
        matchQuality = try container.decodeIfPresent(String.self, forKey: .matchQuality)
        managingAgency = try container.decodeIfPresent(String.self, forKey: .managingAgency)
        lengthMiles = try container.decodeIfPresent(Double.self, forKey: .lengthMiles)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        stateName = try container.decodeIfPresent(String.self, forKey: .stateName)
        fips = try container.decodeIfPresent(String.self, forKey: .fips)
    }

    // MARK: Internal

    // Park
    let designation: String?
    let manager: String?
    let acreage: Double?
    let matchQuality: String?
    // Trail
    let managingAgency: String?
    let lengthMiles: Double?
    let state: String?
    // Admin
    let kind: String?
    let stateName: String?
    let fips: String?

    /// Decode from an optional raw JSON string; nil (no properties, e.g. a
    /// legacy cache row) or malformed JSON yields nil.
    nonisolated static func decode(from json: String?) -> BoundaryFeatureProperties? {
        guard let json, let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(BoundaryFeatureProperties.self, from: data)
    }

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case designation
        case manager
        case acreage
        case matchQuality
        case managingAgency
        case lengthMiles
        case state
        case kind
        case stateName
        case fips
    }
}

// MARK: - FfiGeoBoundary → ParkBoundary

extension ParkBoundary {
    /// Build a `ParkBoundary` from an `FfiGeoBoundary`. The GeoJSON is already
    /// pre-merged server-side, so each decoded polygon becomes one
    /// `MergedPolygon` directly (skirt + zoomed-out variant precomputed for the
    /// renderer). Returns nil when the payload yields no valid polygon.
    /// Nonisolated so it can run on background threads for performance.
    nonisolated static func from(ffi boundary: FfiGeoBoundary) -> ParkBoundary? {
        guard let geometry = GeoJSONGeometry.decode(from: boundary.geojson) else {
            return nil
        }
        let merged = geometry.decodedPolygons().map { rings in
            buildMergedPolygon(exterior: rings.exterior, holes: rings.holes)
        }
        guard !merged.isEmpty else {
            return nil
        }
        let allCoords = merged.flatMap(\.skirt)
        let bbox = allCoords.isEmpty
            ? RingBBox(minLat: 0, maxLat: 0, minLon: 0, maxLon: 0)
            : ringBoundingBox(allCoords)
        let properties = BoundaryFeatureProperties.decode(from: boundary.propertiesJson)
        return ParkBoundary(
            reference: boundary.reference,
            name: boundary.name ?? boundary.reference,
            mergedPolygons: merged,
            bbox: bbox,
            designation: properties?.designation,
            manager: properties?.manager,
            acreage: properties?.acreage,
            matchQuality: properties?.matchQuality
        )
    }

    /// Build a `MergedPolygon` with precomputed skirt and zoomed-out variant from
    /// a single pre-merged exterior + holes.
    nonisolated static func buildMergedPolygon(
        exterior: [CLLocationCoordinate2D],
        holes: [[CLLocationCoordinate2D]]
    ) -> MergedPolygon {
        let skirt = bufferedRing(exterior, byMeters: 30.48)
        let simplified = removeNarrowSpikes(exterior)
        return MergedPolygon(
            exterior: exterior,
            zoomedOutExterior: simplified,
            holes: holes,
            skirt: skirt
        )
    }
}
