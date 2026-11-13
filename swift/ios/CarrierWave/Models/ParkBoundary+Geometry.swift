import CoreLocation

// MARK: - Skirt Buffer (with Miter Clamping)

//
// Render-only geometry. The server pre-merges park units, so the client no
// longer runs a CGPath union; it only precomputes the skirt (buffered outline)
// and the zoomed-out spike-removed variant that the MKMapView renderer consumes.

extension ParkBoundary {
    /// Expand a polygon ring outward by a given distance in meters.
    /// Uses miter-limited vertex offset to prevent spikes at sharp corners.
    nonisolated static func bufferedRing(
        _ ring: [CLLocationCoordinate2D],
        byMeters meters: Double
    ) -> [CLLocationCoordinate2D] {
        guard ring.count >= 3 else {
            return ring
        }

        let signedArea = computeSignedArea(ring)
        let normalSign: Double = signedArea > 0 ? -1.0 : 1.0

        let isClosed = ring.last?.latitude == ring.first?.latitude
            && ring.last?.longitude == ring.first?.longitude
        let open = isClosed ? Array(ring.dropLast()) : ring
        let vertexCount = open.count

        // Precompute cos(lat) for longitude scaling
        let avgLat = open.reduce(0.0) { $0 + $1.latitude }
            / Double(vertexCount)
        let cosLat = cos(avgLat * .pi / 180)
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * max(cosLat, 0.01)

        let params = BufferParams(
            normalSign: normalSign, cosLat: cosLat,
            meters: meters,
            metersPerDegreeLat: metersPerDegreeLat,
            metersPerDegreeLon: metersPerDegreeLon
        )

        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(vertexCount + 1)

        for idx in 0 ..< vertexCount {
            let prev = open[(idx - 1 + vertexCount) % vertexCount]
            let curr = open[idx]
            let next = open[(idx + 1) % vertexCount]
            result.append(miterOffset(prev: prev, curr: curr, next: next, params: params))
        }

        if let first = result.first {
            result.append(first)
        }
        return result
    }

    /// Miter-clamped offset for a single vertex given its neighbors.
    nonisolated static func miterOffset(
        prev: CLLocationCoordinate2D,
        curr: CLLocationCoordinate2D,
        next: CLLocationCoordinate2D,
        params: BufferParams
    ) -> CLLocationCoordinate2D {
        let n1 = edgeNormalScaled(from: prev, to: curr, sign: params.normalSign, cosLat: params.cosLat)
        let n2 = edgeNormalScaled(from: curr, to: next, sign: params.normalSign, cosLat: params.cosLat)

        var nx = n1.0 + n2.0
        var ny = n1.1 + n2.1
        let length = sqrt(nx * nx + ny * ny)
        guard length > 1e-12 else {
            return curr
        }
        nx /= length
        ny /= length

        // Miter scale with 2x clamp to prevent spikes
        let dot = n1.0 * n2.0 + n1.1 * n2.1
        let halfAngleSin = sqrt(max(0, (1.0 - dot) / 2.0))
        let miterScale = halfAngleSin < 0.01 ? 1.0 : min(1.0 / halfAngleSin, 2.0)

        let offsetMeters = params.meters * miterScale
        return CLLocationCoordinate2D(
            latitude: curr.latitude + offsetMeters * ny / params.metersPerDegreeLat,
            longitude: curr.longitude + offsetMeters * nx / params.metersPerDegreeLon
        )
    }

    /// Parameters for the buffer ring calculation.
    struct BufferParams {
        let normalSign: Double
        let cosLat: Double
        let meters: Double
        let metersPerDegreeLat: Double
        let metersPerDegreeLon: Double
    }

    /// Signed area of a polygon ring (positive = CCW, negative = CW).
    nonisolated static func computeSignedArea(
        _ ring: [CLLocationCoordinate2D]
    ) -> Double {
        guard ring.count >= 3 else {
            return 0
        }
        var area = 0.0
        let count = ring.count
        for idx in 0 ..< count {
            let curr = ring[idx]
            let next = ring[(idx + 1) % count]
            area += curr.longitude * next.latitude
            area -= next.longitude * curr.latitude
        }
        return area / 2.0
    }

    /// Edge normal in isotropic (latitude-scaled) space.
    nonisolated static func edgeNormalScaled(
        from ptA: CLLocationCoordinate2D,
        to ptB: CLLocationCoordinate2D,
        sign: Double,
        cosLat: Double
    ) -> (Double, Double) {
        let dx = (ptB.longitude - ptA.longitude) * cosLat
        let dy = ptB.latitude - ptA.latitude
        var nx = -dy * sign
        var ny = dx * sign
        let length = sqrt(nx * nx + ny * ny)
        guard length > 1e-12 else {
            return (0, 0)
        }
        nx /= length
        ny /= length
        return (nx, ny)
    }
}

// MARK: - Zoomed-Out Spike Removal

extension ParkBoundary {
    /// Aggressively remove narrow spikes for zoomed-out display.
    /// Multiple passes over the pre-merged exterior.
    nonisolated static func removeNarrowSpikes(
        _ ring: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D] {
        guard ring.count > 4 else {
            return ring
        }

        let isClosed = ring.first?.latitude == ring.last?.latitude
            && ring.first?.longitude == ring.last?.longitude
        let open = isClosed ? Array(ring.dropLast()) : ring

        let avgLat = open.reduce(0.0) { $0 + $1.latitude }
            / Double(open.count)
        let lonScale = cos(avgLat * .pi / 180)

        var pts = open
        for _ in 0 ..< 3 {
            let before = pts.count
            pts = spikePass(pts, lonScale: lonScale)
            if pts.count == before {
                break
            }
        }

        guard pts.count >= 3 else {
            return ring
        }
        if let first = pts.first {
            pts.append(first)
        }
        return pts
    }

    /// Single pass of spike removal with zoomed-out thresholds.
    nonisolated private static func spikePass(
        _ pts: [CLLocationCoordinate2D],
        lonScale: Double
    ) -> [CLLocationCoordinate2D] {
        guard pts.count > 3 else {
            return pts
        }
        var result: [CLLocationCoordinate2D] = []
        let count = pts.count

        for i in 0 ..< count {
            let prev = pts[(i - 1 + count) % count]
            let curr = pts[i]
            let next = pts[(i + 1) % count]

            let angle = angleDegrees(prev, curr, next, lonScale: lonScale)
            let edgeA = scaledDistance(prev, curr, lonScale: lonScale)
            let edgeB = scaledDistance(curr, next, lonScale: lonScale)
            let shortEdge = min(edgeA, edgeB)

            // Hairpin (< 10°): remove unconditionally
            let isHairpin = angle < 10
            // Sharp spike (< 30°) with short edge (~100m)
            let isSpike = angle < 30 && shortEdge < 0.001
            if !isHairpin, !isSpike {
                result.append(curr)
            }
        }
        return result.count >= 3 ? result : pts
    }

    /// Angle at vertex B in degrees, with longitude scaled by cos(lat).
    nonisolated static func angleDegrees(
        _ ptA: CLLocationCoordinate2D,
        _ ptB: CLLocationCoordinate2D,
        _ ptC: CLLocationCoordinate2D,
        lonScale: Double
    ) -> Double {
        let v1x = (ptA.longitude - ptB.longitude) * lonScale
        let v1y = ptA.latitude - ptB.latitude
        let v2x = (ptC.longitude - ptB.longitude) * lonScale
        let v2y = ptC.latitude - ptB.latitude
        let dot = v1x * v2x + v1y * v2y
        let cross = v1x * v2y - v1y * v2x
        let angle = atan2(abs(cross), dot)
        return angle * 180.0 / .pi
    }

    /// Euclidean distance with longitude scaled by cos(lat).
    nonisolated static func scaledDistance(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D,
        lonScale: Double
    ) -> Double {
        let dx = (a.longitude - b.longitude) * lonScale
        let dy = a.latitude - b.latitude
        return sqrt(dx * dx + dy * dy)
    }
}
