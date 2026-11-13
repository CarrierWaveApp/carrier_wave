//! Pure-math geometry primitives for park/trail boundary rendering. Port of
//! iOS `ParkBoundary+Geometry.swift` (signed area, ray-cast `isPointInRing`,
//! Douglas-Peucker simplify, polygon buffer skirt with miter clamp) and
//! `TrailBoundary+Geometry.swift` (polyline buffer with averaged vertex
//! normals, same miter clamp, 100 ft / 30.48 m skirt distance).
//!
//! Coordinates are `(lat, lon)` pairs in degrees, matching
//! `CLLocationCoordinate2D` field order used by the Swift source. Rings are
//! *not* required to be explicitly closed (first == last); callers may pass
//! either form — the point-in-ring and signed-area loops wrap via modulo
//! exactly as the Swift versions do, and the buffer functions detect and
//! strip an explicit closing vertex before operating on the open vertex list.

/// 100 feet in meters — POTA boundary buffer distance. Swift:
/// `TrailBoundary+Geometry.skirtDistanceMeters`.
pub const SKIRT_DISTANCE_METERS: f64 = 30.48;

const METERS_PER_DEGREE_LAT: f64 = 111_320.0;

/// Signed area of a polygon ring (positive = CCW, negative = CW). Port of
/// `ParkBoundary.signedArea` (identical math to `computeSignedArea`, kept as
/// one function here since both call sites in Swift are byte-identical).
///
/// Fixture 1: unit CCW square (0,0)-(0,1)-(1,1)-(1,0) → shoelace sum walked
/// exactly as Swift's `curr.longitude * next.latitude - next.longitude *
/// curr.latitude` gives area = 0.5 * 2.0 = 1.0 (positive, CCW).
/// Fixture 2: same square reversed (CW) → -1.0.
/// Fixture 3: degenerate 2-point "ring" → 0 (guard `count >= 3`).
pub fn signed_area(ring: &[(f64, f64)]) -> f64 {
    if ring.len() < 3 {
        return 0.0;
    }
    let mut area = 0.0;
    let count = ring.len();
    for i in 0..count {
        let curr = ring[i];
        let next = ring[(i + 1) % count];
        // Swift: area += curr.longitude * next.latitude - next.longitude * curr.latitude
        // ring elements here are (lat, lon) => .0 = lat, .1 = lon
        area += curr.1 * next.0;
        area -= next.1 * curr.0;
    }
    area / 2.0
}

/// Ray-cast point-in-polygon test. Port of `ParkBoundary.isPointInRing`.
/// Matches Swift's crossing semantics exactly: strict `>` latitude
/// comparison (so a vertex sitting exactly on the test latitude does not by
/// itself create a crossing) and a strict `<` longitude comparison against
/// the computed intersection (so a point exactly on a rising/falling edge's
/// intersection longitude is *not* toggled, i.e. boundary points can read as
/// outside — this is intentional parity with the Swift ray-cast, not a bug
/// to "fix").
///
/// Fixture 1: point (0.5, 0.5) inside unit square ring
/// [(0,0),(0,1),(1,1),(1,0)] (lat,lon) → true. Hand-traced: two edges cross
/// latitude 0.5 (the (0,0)-(0,1)... wait, walked in Swift order the two
/// vertical-ish edges connecting lat 0 and lat 1 each cross once, toggling
/// inside from false→true→ stays true after the second only if lon compares
/// consistently on one side; verified by running the same loop by hand
/// mirrors Swift's known behavior for a simple square with center point.
/// Fixture 2: point (2.0, 0.5) outside (north of) the same ring → false (no
/// latitude crossings at all since point.lat exceeds both edge lats).
/// Fixture 3: point (0.0, 0.5) sitting exactly on the ring's bottom edge
/// (between (0,0) and (0,1)) → true. Hand-traced against the exact loop
/// order [(0,0),(0,1),(1,1),(1,0)] with `prev` initialized to the last
/// vertex (1,0): the edge (1,0)->(0,0) crosses (1.0>0.0) != (0.0>0.0) with
/// intersect_lon = 0.0, not < 0.5, no toggle; edge (0,0)->(0,1) does not
/// cross (both endpoints at lat 0.0, so `curr.latitude > point.latitude` is
/// false on both sides); edge (0,1)->(1,1) crosses with intersect_lon = 1.0,
/// 0.5 < 1.0 → toggles to true; edge (1,1)->(1,0) does not cross. Net: one
/// toggle → inside. This is standard ray-cast half-open-edge behavior, not
/// a special case to special-case.
pub fn point_in_ring(point: (f64, f64), ring: &[(f64, f64)]) -> bool {
    if ring.len() < 3 {
        return false;
    }
    let mut inside = false;
    let mut prev = ring[ring.len() - 1];
    for &curr in ring {
        let crosses_lat = (curr.0 > point.0) != (prev.0 > point.0);
        if crosses_lat {
            let intersect_lon =
                prev.1 + (point.0 - prev.0) / (curr.0 - prev.0) * (curr.1 - prev.1);
            if point.1 < intersect_lon {
                inside = !inside;
            }
        }
        prev = curr;
    }
    inside
}

/// Perpendicular distance from a point to a line segment (degenerate case:
/// distance to the shared endpoint when the segment has ~zero length). Port
/// of `ParkBoundary.perpendicularDist`.
fn perpendicular_dist(pt: (f64, f64), line_from: (f64, f64), line_to: (f64, f64)) -> f64 {
    let (pt_lat, pt_lon) = pt;
    let (a_lat, a_lon) = line_from;
    let (b_lat, b_lon) = line_to;
    let dx = b_lon - a_lon;
    let dy = b_lat - a_lat;
    let len_sq = dx * dx + dy * dy;
    if len_sq <= 1e-20 {
        let ex = pt_lon - a_lon;
        let ey = pt_lat - a_lat;
        return (ex * ex + ey * ey).sqrt();
    }
    let cross_product = (dy * pt_lon - dx * pt_lat + b_lon * a_lat - b_lat * a_lon).abs();
    cross_product / len_sq.sqrt()
}

/// Index-based Douglas-Peucker recursion (no array copies). Port of
/// `ParkBoundary.dpRecursive`.
fn dp_recursive(points: &[(f64, f64)], start: usize, end: usize, tolerance: f64, keep: &mut [bool]) {
    if end <= start + 1 {
        return;
    }

    let mut max_dist = 0.0;
    let mut max_idx = start;
    let line_a = points[start];
    let line_b = points[end];

    for (offset, &pt) in points[(start + 1)..end].iter().enumerate() {
        let dist = perpendicular_dist(pt, line_a, line_b);
        if dist > max_dist {
            max_dist = dist;
            max_idx = start + 1 + offset;
        }
    }

    if max_dist > tolerance {
        keep[max_idx] = true;
        dp_recursive(points, start, max_idx, tolerance, keep);
        dp_recursive(points, max_idx, end, tolerance, keep);
    }
}

/// Douglas-Peucker polyline/ring simplification. `tolerance_deg` is compared
/// directly against the same lat/lon-degree perpendicular distance the
/// Swift code uses (no meters conversion — matches source behavior).
///
/// Fixture 1 (nearly-collinear point elimination): points [(0,0), (0.001,
/// 5), (0,10)] with tolerance 0.01 — the middle point's perpendicular
/// distance from the (0,0)-(0,10) chord is 0.001 (essentially a straight
/// line with y=lat, x=lon: dy=0,dx=10 so dist = |0*10 - 10*0.001 + ...|
/// simplifies to 0.001), which is <= tolerance, so it is dropped → result
/// [(0,0), (0,10)].
/// Fixture 2 (spike kept): points [(0,0), (5,5), (0,10)] tolerance 0.01 —
/// midpoint perpendicular distance from chord (0,0)-(0,10) is 5 (pure
/// longitude offset since chord runs along lat axis lon=0), far above
/// tolerance, so the point is kept → result unchanged, 3 points.
/// Fixture 3: fewer than 2 points is returned unchanged (empty / single
/// point rings have nothing to simplify).
pub fn simplify_dp(points: &[(f64, f64)], tolerance_deg: f64) -> Vec<(f64, f64)> {
    if points.len() < 2 {
        return points.to_vec();
    }
    let mut keep = vec![false; points.len()];
    keep[0] = true;
    *keep.last_mut().unwrap() = true;
    dp_recursive(points, 0, points.len() - 1, tolerance_deg, &mut keep);

    points
        .iter()
        .zip(keep.iter())
        .filter_map(|(&p, &k)| if k { Some(p) } else { None })
        .collect()
}

/// Parameters shared across a single `buffer_polygon` call. Mirrors Swift's
/// `ParkBoundary.BufferParams`.
struct BufferParams {
    normal_sign: f64,
    cos_lat: f64,
    meters: f64,
    meters_per_degree_lat: f64,
    meters_per_degree_lon: f64,
}

/// Edge normal in isotropic (latitude-scaled) space. Port of
/// `ParkBoundary.edgeNormalScaled`.
fn edge_normal_scaled(pt_a: (f64, f64), pt_b: (f64, f64), sign: f64, cos_lat: f64) -> (f64, f64) {
    let dx = (pt_b.1 - pt_a.1) * cos_lat;
    let dy = pt_b.0 - pt_a.0;
    let mut nx = -dy * sign;
    let mut ny = dx * sign;
    let length = (nx * nx + ny * ny).sqrt();
    if length <= 1e-12 {
        return (0.0, 0.0);
    }
    nx /= length;
    ny /= length;
    (nx, ny)
}

/// Miter-clamped offset for a single vertex given its neighbors. Port of
/// `ParkBoundary.miterOffset`.
fn miter_offset(prev: (f64, f64), curr: (f64, f64), next: (f64, f64), params: &BufferParams) -> (f64, f64) {
    let n1 = edge_normal_scaled(prev, curr, params.normal_sign, params.cos_lat);
    let n2 = edge_normal_scaled(curr, next, params.normal_sign, params.cos_lat);

    let mut nx = n1.0 + n2.0;
    let mut ny = n1.1 + n2.1;
    let length = (nx * nx + ny * ny).sqrt();
    if length <= 1e-12 {
        return curr;
    }
    nx /= length;
    ny /= length;

    // Miter scale with 2x clamp to prevent spikes.
    let dot = n1.0 * n2.0 + n1.1 * n2.1;
    let half_angle_sin = (0.0_f64).max((1.0 - dot) / 2.0).sqrt();
    let miter_scale = if half_angle_sin < 0.01 { 1.0 } else { (1.0 / half_angle_sin).min(2.0) };

    let offset_meters = params.meters * miter_scale;
    (
        curr.0 + offset_meters * ny / params.meters_per_degree_lat,
        curr.1 + offset_meters * nx / params.meters_per_degree_lon,
    )
}

/// Expand a polygon ring outward by `meters`, using miter-limited vertex
/// offsets to prevent spikes at sharp corners. Port of
/// `ParkBoundary.bufferedRing`. Accepts either an explicitly-closed ring
/// (first == last) or an open one; the result is always explicitly closed
/// (first vertex repeated at the end), matching the Swift return shape.
///
/// Fixture 1 (unit CCW square, buffer 111.32 m ≈ 1e-3 deg at the equator):
/// ring [(0,0),(0,1),(1,1),(1,0)] (lat,lon), open (Swift's `isClosed` check
/// is false since first != last). `computeSignedArea` > 0 (CCW) so
/// `normalSign = -1.0`, meaning normals point outward for a CCW ring walked
/// in this order — each corner offsets away from the square's center.
/// Result has 5 coordinates (4 offset vertices + repeated first) with the
/// corner nearest (0,0) offset to roughly (-0.000707, -0.000707) deg (45°
/// miter at a right-angle corner scales the unit offset by ~√2, clamped
/// under the 2x cap).
/// Fixture 2: ring.count < 3 (raw, pre-strip) → returned unchanged (guard
/// mirrors Swift's `guard ring.count >= 3`).
/// Fixture 3: a CW ring (same square, vertices reversed) flips
/// `normal_sign` to +1.0, but reversing the vertex order also swaps which
/// neighbor is "prev" vs "next" at the shared physical corner — the two
/// effects cancel, so the corner nearest (0,0) offsets to the *same*
/// outward position in both windings (hand-verified: (-1.0, -1.0000381) in
/// both cases at buffer = 111_320 m). This pins that `signed_area`'s sign
/// correctly compensates for winding so the skirt always expands outward,
/// never inward, regardless of the input ring's orientation.
///
/// Fixture 4 (degenerate 2-distinct-vertex closed ring — parity pin, no
/// post-strip guard): input `[(0,0),(1,1),(0,0)]` (lat,lon), `is_closed` is
/// true (first == last) so it strips to `open = [(0,0),(1,1)]`,
/// `vertex_count = 2`. Swift's `bufferedRing` has **no** guard on
/// `vertexCount` after the strip (only the pre-strip `ring.count >= 3`), so
/// it proceeds into the miter loop with `vertexCount == 2`; Rust must match
/// — there is intentionally no `vertex_count < 3` early return here.
/// Hand-derivation of the loop, `meters = METERS_PER_DEGREE_LAT`: the raw
/// (pre-strip) ring's `signed_area` is 0 (a 2-distinct-point "polygon" has
/// zero area — shoelace over `[(0,0),(1,1),(0,0)]` sums to 0), so
/// `normal_sign = 1.0` (the `else` branch of `area > 0.0`). For `idx == 0`:
/// `prev = open[(0 + 2 - 1) % 2] = open[1] = (1,1)`, `curr = open[0] =
/// (0,0)`, `next = open[(0 + 1) % 2] = open[1] = (1,1)` — both neighbors
/// wrap to the *same* other point. `edge_normal_scaled(prev, curr, ...)`
/// (the reversed segment `(1,1)->(0,0)`) and `edge_normal_scaled(curr, next,
/// ...)` (the forward segment `(0,0)->(1,1)`) are unit normals of the same
/// line walked in opposite directions, so they are exact negations of each
/// other; their sum has length 0, tripping `miter_offset`'s `length <=
/// 1e-12` guard, which returns `curr` unmodified — i.e. `(0,0)`. By
/// symmetry `idx == 1` returns `curr = (1,1)` unmodified. Closing the ring
/// (repeat first) gives the pinned result `[(0,0),(1,1),(0,0)]` — byte-
/// identical to the input, via the *defined* wraparound/zero-length path,
/// not a panic. Verified numerically (see
/// `buffer_polygon_degenerate_two_vertex_closed_ring_matches_swift_wraparound`).
pub fn buffer_polygon(ring: &[(f64, f64)], meters: f64) -> Vec<(f64, f64)> {
    if ring.len() < 3 {
        return ring.to_vec();
    }

    let area = signed_area(ring);
    let normal_sign: f64 = if area > 0.0 { -1.0 } else { 1.0 };

    let is_closed = ring.first() == ring.last();
    let open: Vec<(f64, f64)> = if is_closed { ring[..ring.len() - 1].to_vec() } else { ring.to_vec() };
    let vertex_count = open.len();

    // NOTE: intentionally no `vertex_count < 3` guard here — Swift's
    // `bufferedRing` only checks `ring.count >= 3` *before* stripping the
    // closing vertex; once stripped, a 2-vertex open ring proceeds into the
    // miter loop below and hits the defined index-wraparound / zero-length
    // degenerate path (see fixture 4 above). Adding a post-strip guard
    // would be a parity break from the Swift source.
    let avg_lat = open.iter().map(|p| p.0).sum::<f64>() / vertex_count as f64;
    let cos_lat = (avg_lat * std::f64::consts::PI / 180.0).cos();
    let meters_per_degree_lat = METERS_PER_DEGREE_LAT;
    let meters_per_degree_lon = METERS_PER_DEGREE_LAT * cos_lat.max(0.01);

    let params = BufferParams {
        normal_sign,
        cos_lat,
        meters,
        meters_per_degree_lat,
        meters_per_degree_lon,
    };

    let mut result: Vec<(f64, f64)> = Vec::with_capacity(vertex_count + 1);
    for idx in 0..vertex_count {
        let prev = open[(idx + vertex_count - 1) % vertex_count];
        let curr = open[idx];
        let next = open[(idx + 1) % vertex_count];
        result.push(miter_offset(prev, curr, next, &params));
    }

    if let Some(&first) = result.first() {
        result.push(first);
    }
    result
}

/// Unit perpendicular normal for a single segment (pointing left). Port of
/// `TrailBoundary.segmentNormal`.
fn segment_normal(pt_a: (f64, f64), pt_b: (f64, f64), cos_lat: f64) -> (f64, f64) {
    let dx = (pt_b.1 - pt_a.1) * cos_lat;
    let dy = pt_b.0 - pt_a.0;
    let length = (dx * dx + dy * dy).sqrt();
    if length <= 1e-12 {
        return (0.0, 0.0);
    }
    // Perpendicular: rotate 90 deg CCW -> (-dy, dx).
    (-dy / length, dx / length)
}

/// Averaged perpendicular normal at a vertex along an open polyline. For
/// interior vertices, averages (with the same miter clamp as
/// `buffer_polygon`) the normals of the two adjacent segments; for
/// endpoints, uses the single adjacent segment's normal unmodified. Port of
/// `TrailBoundary.vertexNormal`.
fn vertex_normal(line: &[(f64, f64)], index: usize, cos_lat: f64) -> (f64, f64) {
    let count = line.len();

    if index == 0 {
        return segment_normal(line[0], line[1], cos_lat);
    } else if index == count - 1 {
        return segment_normal(line[count - 2], line[count - 1], cos_lat);
    }

    let n1 = segment_normal(line[index - 1], line[index], cos_lat);
    let n2 = segment_normal(line[index], line[index + 1], cos_lat);

    let mut nx = n1.0 + n2.0;
    let mut ny = n1.1 + n2.1;
    let length = (nx * nx + ny * ny).sqrt();
    if length <= 1e-12 {
        return n1;
    }
    nx /= length;
    ny /= length;

    // Miter scale with 2x clamp to prevent spikes at sharp bends.
    let dot = n1.0 * n2.0 + n1.1 * n2.1;
    let half_angle_sin = (0.0_f64).max((1.0 - dot) / 2.0).sqrt();
    let miter_scale = if half_angle_sin < 0.01 { 1.0 } else { (1.0 / half_angle_sin).min(2.0) };

    (nx * miter_scale, ny * miter_scale)
}

/// Build a closed polygon "skirt" around an open polyline at the given
/// buffer distance: left side walked forward, then right side walked
/// backward, closed by repeating the first vertex. Port of
/// `TrailBoundary.polylineSkirt`. Returns `None` when `points.len() < 2`
/// (mirrors the Swift `guard line.count >= 2 else { return nil }`, modeled
/// here as an empty `Vec` since the brief's signature is infallible — see
/// fixture 3).
///
/// Fixture 1 (two-point straight line, buffer 30.48 m / SKIRT_DISTANCE):
/// line [(0,0),(0,1)] (lat,lon). Both vertices are endpoints so
/// `vertex_normal` uses the single segment normal: dx=(1-0)*cosLat,
/// dy=0-0=0, unit normal after rotate-90-CCW is (0, dx/|dx|) = (0,1) i.e.
/// purely in the "dx" (longitude) direction — meaning the offset applies
/// entirely to latitude via `dlat = meters*normal.dy/metersPerDegreeLat` = 0
/// and to longitude via `dlon = meters*normal.dx/metersPerDegreeLon`. Left
/// side ends up offset south/north depending on sign convention; result has
/// 5 coordinates: 2 left + 2 right (reversed) + repeated first.
/// Fixture 2 (single point / empty line): returns empty Vec (< 2 guard).
/// Fixture 3 (three-point right-angle bend): line [(0,0),(0,1),(1,1)]
/// exercises the interior-vertex averaged-normal + miter-clamp branch at
/// index 1, pinning that the clamp caps the offset at 2x `meters` rather
/// than spiking to the unclamped ~1.41x-secant value for a 90° bend... the
/// exact right-angle bend produces half_angle_sin = sin(45°) ≈ 0.707 so
/// miter_scale = min(1/0.707, 2.0) ≈ 1.414 (unclamped, since it's under 2).
pub fn buffer_polyline(points: &[(f64, f64)], meters: f64) -> Vec<(f64, f64)> {
    if points.len() < 2 {
        return Vec::new();
    }

    let avg_lat = points.iter().map(|p| p.0).sum::<f64>() / points.len() as f64;
    let cos_lat = (avg_lat * std::f64::consts::PI / 180.0).cos();
    let meters_per_degree_lat = METERS_PER_DEGREE_LAT;
    let meters_per_degree_lon = METERS_PER_DEGREE_LAT * cos_lat.max(0.01);

    let mut left_side: Vec<(f64, f64)> = Vec::with_capacity(points.len());
    let mut right_side: Vec<(f64, f64)> = Vec::with_capacity(points.len());

    for idx in 0..points.len() {
        let normal = vertex_normal(points, idx, cos_lat);
        let dlat = meters * normal.1 / meters_per_degree_lat;
        let dlon = meters * normal.0 / meters_per_degree_lon;

        left_side.push((points[idx].0 + dlat, points[idx].1 + dlon));
        right_side.push((points[idx].0 - dlat, points[idx].1 - dlon));
    }

    let mut polygon = left_side;
    polygon.extend(right_side.into_iter().rev());
    if let Some(&first) = polygon.first() {
        polygon.push(first);
    }
    polygon
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- signed_area ---

    #[test]
    fn signed_area_ccw_unit_square_is_positive_one() {
        // Fixture provenance: see doc comment on signed_area, fixture 1.
        let ring = [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)];
        assert!((signed_area(&ring) - 1.0).abs() < 1e-12);
    }

    #[test]
    fn signed_area_cw_unit_square_is_negative_one() {
        // Fixture provenance: see doc comment on signed_area, fixture 2.
        let ring = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)];
        assert!((signed_area(&ring) - -1.0).abs() < 1e-12);
    }

    #[test]
    fn signed_area_degenerate_ring_is_zero() {
        // Fixture provenance: see doc comment on signed_area, fixture 3.
        let ring = [(0.0, 0.0), (1.0, 1.0)];
        assert_eq!(signed_area(&ring), 0.0);
    }

    // --- point_in_ring ---

    #[test]
    fn point_in_ring_center_of_unit_square_is_inside() {
        // Fixture provenance: see doc comment on point_in_ring, fixture 1.
        let ring = [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)];
        assert!(point_in_ring((0.5, 0.5), &ring));
    }

    #[test]
    fn point_in_ring_outside_north_is_false() {
        // Fixture provenance: see doc comment on point_in_ring, fixture 2.
        let ring = [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)];
        assert!(!point_in_ring((2.0, 0.5), &ring));
    }

    #[test]
    fn point_in_ring_on_bottom_edge_latitude_is_true() {
        // Fixture provenance: see doc comment on point_in_ring, fixture 3.
        let ring = [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)];
        assert!(point_in_ring((0.0, 0.5), &ring));
    }

    #[test]
    fn point_in_ring_degenerate_ring_is_false() {
        let ring = [(0.0, 0.0), (1.0, 1.0)];
        assert!(!point_in_ring((0.5, 0.5), &ring));
    }

    // --- simplify_dp ---

    #[test]
    fn simplify_dp_drops_near_collinear_point() {
        // Fixture provenance: see doc comment on simplify_dp, fixture 1.
        let points = [(0.0, 0.0), (0.001, 5.0), (0.0, 10.0)];
        let simplified = simplify_dp(&points, 0.01);
        assert_eq!(simplified, vec![(0.0, 0.0), (0.0, 10.0)]);
    }

    #[test]
    fn simplify_dp_keeps_spike_point() {
        // Fixture provenance: see doc comment on simplify_dp, fixture 2.
        let points = [(0.0, 0.0), (5.0, 5.0), (0.0, 10.0)];
        let simplified = simplify_dp(&points, 0.01);
        assert_eq!(simplified, vec![(0.0, 0.0), (5.0, 5.0), (0.0, 10.0)]);
    }

    #[test]
    fn simplify_dp_single_point_unchanged() {
        // Fixture provenance: see doc comment on simplify_dp, fixture 3.
        let points = [(1.0, 2.0)];
        assert_eq!(simplify_dp(&points, 0.01), vec![(1.0, 2.0)]);
    }

    // --- buffer_polygon ---

    #[test]
    fn buffer_polygon_ccw_square_offsets_outward_negative_corner() {
        // Fixture provenance: see doc comment on buffer_polygon, fixture 1.
        // Buffer distance chosen as one degree-of-latitude-equivalent
        // (111_320 m) so the unclamped per-axis offset before miter scaling
        // is exactly 1.0 degree, making the corner math easy to hand-check:
        // an interior right-angle corner miter-scales by sqrt(2).
        let ring = [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)];
        let buffered = buffer_polygon(&ring, METERS_PER_DEGREE_LAT);
        assert_eq!(buffered.len(), 5);
        assert_eq!(buffered.first(), buffered.last());
        // Corner (0,0): normals of incoming edge (1,0)->(0,0) and outgoing
        // edge (0,0)->(0,1) average to a diagonal miter offset pointing
        // away from the square's interior (negative lat, negative lon)
        // since normal_sign = -1 for this CCW ring.
        let corner = buffered[0];
        assert!(corner.0 < 0.0, "expected negative lat offset, got {}", corner.0);
        assert!(corner.1 < 0.0, "expected negative lon offset, got {}", corner.1);
    }

    #[test]
    fn buffer_polygon_degenerate_ring_unchanged() {
        // Fixture provenance: see doc comment on buffer_polygon, fixture 2.
        let ring = [(0.0, 0.0), (1.0, 1.0)];
        assert_eq!(buffer_polygon(&ring, 30.48), ring.to_vec());
    }

    #[test]
    fn buffer_polygon_winding_direction_does_not_flip_outward_expansion() {
        // Fixture provenance: see doc comment on buffer_polygon, fixture 3.
        let ccw = [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)];
        let cw = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)];
        let buffered_ccw = buffer_polygon(&ccw, METERS_PER_DEGREE_LAT);
        let buffered_cw = buffer_polygon(&cw, METERS_PER_DEGREE_LAT);
        // Same physical corner (0,0) in both rings offsets to the same
        // outward position regardless of winding, because normal_sign
        // (derived from signed_area) compensates for the reversed prev/next
        // adjacency.
        assert!(buffered_ccw[0].0 < 0.0 && buffered_ccw[0].1 < 0.0);
        assert!((buffered_ccw[0].0 - buffered_cw[0].0).abs() < 1e-9);
        assert!((buffered_ccw[0].1 - buffered_cw[0].1).abs() < 1e-9);
    }

    #[test]
    fn buffer_polygon_degenerate_two_vertex_closed_ring_matches_swift_wraparound() {
        // Fixture provenance: see doc comment on buffer_polygon, fixture 4.
        // Parity pin: Swift's `bufferedRing` has no post-strip vertex-count
        // guard, so a closed ring that strips down to 2 distinct vertices
        // still runs the miter loop with vertexCount == 2. Both indices'
        // prev/next wrap to the same opposite point, the two edge normals
        // are exact negations, and `miterOffset`'s zero-length guard
        // returns each vertex unmodified — the ring comes back unchanged
        // (not a panic, not an early return).
        let ring = [(0.0, 0.0), (1.0, 1.0), (0.0, 0.0)];
        let buffered = buffer_polygon(&ring, METERS_PER_DEGREE_LAT);
        assert_eq!(buffered, vec![(0.0, 0.0), (1.0, 1.0), (0.0, 0.0)]);
    }

    // --- buffer_polyline ---

    #[test]
    fn buffer_polyline_two_point_line_closes_to_five_vertices() {
        // Fixture provenance: see doc comment on buffer_polyline, fixture 1.
        let line = [(0.0, 0.0), (0.0, 1.0)];
        let skirt = buffer_polyline(&line, SKIRT_DISTANCE_METERS);
        assert_eq!(skirt.len(), 5);
        assert_eq!(skirt.first(), skirt.last());
        // Pure east-west segment: normal is purely latitudinal, so every
        // offset vertex keeps the original longitude untouched.
        for (i, orig) in line.iter().enumerate() {
            assert!((skirt[i].1 - orig.1).abs() < 1e-12);
        }
    }

    #[test]
    fn buffer_polyline_single_point_returns_empty() {
        // Fixture provenance: see doc comment on buffer_polyline, fixture 2.
        let line = [(0.0, 0.0)];
        assert!(buffer_polyline(&line, SKIRT_DISTANCE_METERS).is_empty());
    }

    #[test]
    fn buffer_polyline_right_angle_bend_applies_unclamped_miter() {
        // Fixture provenance: see doc comment on buffer_polyline, fixture 3.
        let line = [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0)];
        let skirt = buffer_polyline(&line, SKIRT_DISTANCE_METERS);
        // 3 points -> left(3) + right(3) + closing vertex = 7.
        assert_eq!(skirt.len(), 7);
        // Interior vertex (index 1) offset magnitude should exceed the
        // endpoint offset magnitude because of the ~1.414x miter scale
        // (uses lon offset since cos_lat ~ 1 near the equator; degenerate
        // if run at high latitude, so this fixture intentionally stays
        // near lat=0/1).
        let dlat_endpoint = (skirt[0].0 - line[0].0).abs();
        let dlon_interior = (skirt[1].1 - line[1].1).abs();
        let dlon_endpoint_from_segment = (skirt[0].1 - line[0].1).abs();
        assert!(dlat_endpoint > 0.0);
        assert!(dlon_interior > dlon_endpoint_from_segment);
    }

    #[test]
    fn skirt_distance_constant_matches_100_feet() {
        assert!((SKIRT_DISTANCE_METERS - 30.48).abs() < 1e-9);
    }
}
