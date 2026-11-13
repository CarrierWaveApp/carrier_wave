import CarrierWaveCore
import CoreLocation
import Foundation

// MARK: - TrailBoundary

/// A historic trail line materialized from an `FfiGeoBoundary` handed back by
/// `ParkMapApi.trailsInBox`. Decode + render only — the skirt buffer lives in
/// `TrailBoundary+Geometry.swift`.
struct TrailBoundary: Identifiable {
    let reference: String
    let name: String
    let designation: String?
    let managingAgency: String?
    let lengthMiles: Double?
    let state: String?
    let matchQuality: String?
    let lines: [[CLLocationCoordinate2D]]

    nonisolated var id: String {
        reference
    }
}

// MARK: - TrailGeometry

/// Handles LineString and MultiLineString GeoJSON geometry types (recursing into
/// a GeometryCollection so a multi-feature cache row still decodes).
enum TrailGeometry {
    case lineString([[Double]])
    case multiLineString([[[Double]]])
    case geometryCollection([TrailGeometry])

    // MARK: Internal

    nonisolated var coordinateLines: [[[Double]]] {
        switch self {
        case let .lineString(line):
            [line]
        case let .multiLineString(lines):
            lines
        case let .geometryCollection(geometries):
            geometries.flatMap(\.coordinateLines)
        }
    }

    nonisolated static func decode(from geojson: String) -> TrailGeometry? {
        guard let data = geojson.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(TrailGeometry.self, from: data)
    }
}

// MARK: Codable

extension TrailGeometry: Codable {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let geometryType = try container.decode(String.self, forKey: .type)

        switch geometryType {
        case "LineString":
            let coords = try container.decode([[Double]].self, forKey: .coordinates)
            self = .lineString(coords)

        case "MultiLineString":
            let coords = try container.decode([[[Double]]].self, forKey: .coordinates)
            self = .multiLineString(coords)

        case "GeometryCollection":
            let members = try container.decode([SafeTrailGeometry].self, forKey: .geometries)
            self = .geometryCollection(members.compactMap(\.geometry))

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .coordinates,
                in: container,
                debugDescription: "Unsupported trail geometry type: \(geometryType)"
            )
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .lineString(line):
            try container.encode("LineString", forKey: .type)
            try container.encode(line, forKey: .coordinates)
        case let .multiLineString(lines):
            try container.encode("MultiLineString", forKey: .type)
            try container.encode(lines, forKey: .coordinates)
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

// MARK: - SafeTrailGeometry

/// Wrapper that silently skips non-line geometry members in a GeometryCollection.
private struct SafeTrailGeometry: Codable {
    // MARK: Lifecycle

    nonisolated init(from decoder: Decoder) throws {
        geometry = try? TrailGeometry(from: decoder)
    }

    // MARK: Internal

    let geometry: TrailGeometry?

    nonisolated func encode(to encoder: Encoder) throws {
        try geometry?.encode(to: encoder)
    }
}

// MARK: - FfiGeoBoundary → TrailBoundary

extension TrailBoundary {
    /// Build a `TrailBoundary` from an `FfiGeoBoundary`. The descriptive metadata
    /// (designation, agency, length, state, match quality) is decoded from
    /// `propertiesJson` when present (nil for legacy cache rows).
    /// Returns nil when the payload yields no valid line.
    nonisolated static func from(ffi boundary: FfiGeoBoundary) -> TrailBoundary? {
        guard let geometry = TrailGeometry.decode(from: boundary.geojson) else {
            return nil
        }
        let lines = geometry.coordinateLines.map { line in
            line.compactMap { pair -> CLLocationCoordinate2D? in
                guard pair.count >= 2 else {
                    return nil
                }
                return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            }
        }
        .filter { $0.count >= 2 }
        guard !lines.isEmpty else {
            return nil
        }
        let properties = BoundaryFeatureProperties.decode(from: boundary.propertiesJson)
        return TrailBoundary(
            reference: boundary.reference,
            name: boundary.name ?? boundary.reference,
            designation: properties?.designation,
            managingAgency: properties?.managingAgency,
            lengthMiles: properties?.lengthMiles,
            state: properties?.state,
            matchQuality: properties?.matchQuality,
            lines: lines
        )
    }
}
