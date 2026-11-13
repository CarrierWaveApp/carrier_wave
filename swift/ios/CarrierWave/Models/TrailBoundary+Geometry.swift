import CoreLocation

// MARK: - Trail Skirt (100ft Buffer Polygon)

extension TrailBoundary {
    /// 100 feet in meters — POTA boundary buffer distance.
    private static let skirtDistanceMeters = 30.48

    /// Generate a polygon for each line segment by buffering 100ft on each side.
    /// Creates a closed polygon: left side forward, cap, right side backward, cap.
    var skirtPolygons: [[CLLocationCoordinate2D]] {
        lines.compactMap { line in
            Self.polylineSkirt(line, meters: Self.skirtDistanceMeters)
        }
    }

    /// Build a closed polygon around an open polyline at the given buffer distance.
    static func polylineSkirt(
        _ line: [CLLocationCoordinate2D],
        meters: Double
    ) -> [CLLocationCoordinate2D]? {
        guard line.count >= 2 else {
            return nil
        }

        let avgLat = line.reduce(into: 0.0) { $0 += $1.latitude }
            / Double(line.count)
        let cosLat = cos(avgLat * .pi / 180)
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * max(cosLat, 0.01)

        // Compute offset normals for each vertex
        var leftSide: [CLLocationCoordinate2D] = []
        var rightSide: [CLLocationCoordinate2D] = []
        leftSide.reserveCapacity(line.count)
        rightSide.reserveCapacity(line.count)

        for idx in 0 ..< line.count {
            let normal = vertexNormal(
                line: line, index: idx, cosLat: cosLat
            )
            let dlat = meters * normal.dy / metersPerDegreeLat
            let dlon = meters * normal.dx / metersPerDegreeLon

            leftSide.append(CLLocationCoordinate2D(
                latitude: line[idx].latitude + dlat,
                longitude: line[idx].longitude + dlon
            ))
            rightSide.append(CLLocationCoordinate2D(
                latitude: line[idx].latitude - dlat,
                longitude: line[idx].longitude - dlon
            ))
        }

        // Build closed polygon: left forward, then right reversed
        var polygon = leftSide
        polygon.append(contentsOf: rightSide.reversed())
        if let first = polygon.first {
            polygon.append(first)
        }
        return polygon
    }

    /// Averaged perpendicular normal at a vertex along the polyline.
    /// For interior vertices, averages the normals of the two adjacent segments.
    /// For endpoints, uses the single adjacent segment normal.
    private static func vertexNormal(
        line: [CLLocationCoordinate2D],
        index: Int,
        cosLat: Double
    ) -> (dx: Double, dy: Double) {
        let count = line.count

        if index == 0 {
            return segmentNormal(
                from: line[0], to: line[1], cosLat: cosLat
            )
        } else if index == count - 1 {
            return segmentNormal(
                from: line[count - 2], to: line[count - 1], cosLat: cosLat
            )
        }

        let n1 = segmentNormal(
            from: line[index - 1], to: line[index], cosLat: cosLat
        )
        let n2 = segmentNormal(
            from: line[index], to: line[index + 1], cosLat: cosLat
        )

        var nx = n1.dx + n2.dx
        var ny = n1.dy + n2.dy
        let length = sqrt(nx * nx + ny * ny)
        guard length > 1e-12 else {
            return n1
        }
        nx /= length
        ny /= length

        // Miter scale with 2x clamp to prevent spikes at sharp bends
        let dot = n1.dx * n2.dx + n1.dy * n2.dy
        let halfAngleSin = sqrt(max(0, (1.0 - dot) / 2.0))
        let miterScale = halfAngleSin < 0.01
            ? 1.0
            : min(1.0 / halfAngleSin, 2.0)

        return (dx: nx * miterScale, dy: ny * miterScale)
    }

    /// Unit perpendicular normal for a single segment (pointing left).
    private static func segmentNormal(
        from ptA: CLLocationCoordinate2D,
        to ptB: CLLocationCoordinate2D,
        cosLat: Double
    ) -> (dx: Double, dy: Double) {
        let dx = (ptB.longitude - ptA.longitude) * cosLat
        let dy = ptB.latitude - ptA.latitude
        let length = sqrt(dx * dx + dy * dy)
        guard length > 1e-12 else {
            return (dx: 0, dy: 0)
        }
        // Perpendicular: rotate 90° CCW → (-dy, dx)
        return (dx: -dy / length, dy: dx / length)
    }
}
