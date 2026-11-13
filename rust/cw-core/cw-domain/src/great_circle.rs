//! Great-circle (geodesic) path generation split at the antimeridian.
//!
//! Port of iOS `ActivationMapHelpers.geodesicSegments` /
//! `splitAtAntimeridian` / `interpolateCrossingLat`, reusing the slerp path
//! from `azimuthal::AzimuthalProjection::great_circle_path` so the repo has
//! exactly one great-circle implementation.

use crate::azimuthal::AzimuthalProjection;

/// Generate a geodesic path from `from` to `to` (both `(lat_deg, lon_deg)`),
/// split into segments at ±180° crossings. Each inner Vec is a continuous
/// polyline that does not cross the antimeridian.
pub fn great_circle_segments(
    from: (f64, f64),
    to: (f64, f64),
    segments: usize,
) -> Vec<Vec<(f64, f64)>> {
    let raw = AzimuthalProjection::great_circle_path(from.0, from.1, to.0, to.1, segments);
    split_at_antimeridian(&raw)
}

/// Split a (lat, lon) path at antimeridian crossings, interpolating the
/// crossing latitude so each segment ends/starts exactly on the ±180° edge.
pub fn split_at_antimeridian(path: &[(f64, f64)]) -> Vec<Vec<(f64, f64)>> {
    if path.len() < 2 {
        return vec![path.to_vec()];
    }
    let mut out = Vec::new();
    let mut current = vec![path[0]];
    for i in 1..path.len() {
        let prev = path[i - 1];
        let curr = path[i];
        // A longitude jump > 180° means we crossed the antimeridian.
        if (curr.1 - prev.1).abs() > 180.0 {
            let cross_lat = interpolate_crossing_lat(prev, curr);
            let edge_lon = if prev.1 > 0.0 { 180.0 } else { -180.0 };
            current.push((cross_lat, edge_lon));
            out.push(current);
            current = vec![(cross_lat, -edge_lon)];
        }
        current.push(curr);
    }
    out.push(current);
    out
}

/// Linearly interpolate the latitude at the antimeridian crossing between
/// two points that straddle it.
fn interpolate_crossing_lat(a: (f64, f64), b: (f64, f64)) -> f64 {
    let (lat_a, lon_a) = a;
    let (lat_b, lon_b) = b;
    // Unwrap lon_b onto lon_a's side for interpolation.
    let unwrapped_b = if lon_b - lon_a > 180.0 {
        lon_b - 360.0
    } else if lon_a - lon_b > 180.0 {
        lon_b + 360.0
    } else {
        lon_b
    };
    let target = if lon_a > 0.0 { 180.0 } else { -180.0 };
    let frac = (target - lon_a) / (unwrapped_b - lon_a);
    lat_a + frac * (lat_b - lat_a)
}

#[cfg(test)]
mod tests {
    use super::*;

    // CM87 (San Francisco ~37.4,-122.3) → PM95 (Tokyo ~35.5,139.4): the great
    // circle goes over the North Pacific and crosses the antimeridian.
    #[test]
    fn splits_pacific_path_at_antimeridian() {
        let segs = great_circle_segments((37.4, -122.3), (35.5, 139.4), 50);
        assert_eq!(segs.len(), 2);
        let first = &segs[0];
        let second = &segs[1];
        // First segment ends exactly on the -180 edge (heading west from -122).
        assert!((first.last().unwrap().1.abs() - 180.0).abs() < 1e-9);
        // Second segment starts on the opposite edge with the same latitude.
        assert!((second[0].1.abs() - 180.0).abs() < 1e-9);
        assert!((first.last().unwrap().0 - second[0].0).abs() < 1e-9);
        assert_ne!(first.last().unwrap().1, second[0].1);
    }

    #[test]
    fn short_path_is_single_segment() {
        let segs = great_circle_segments((32.9, -96.8), (33.9, -96.8), 50);
        assert_eq!(segs.len(), 1);
        assert_eq!(segs[0].len(), 51); // segments + 1 points
    }

    #[test]
    fn zero_distance_returns_two_points() {
        let segs = great_circle_segments((32.9, -96.8), (32.9, -96.8), 50);
        assert_eq!(segs.len(), 1);
        assert_eq!(segs[0].len(), 2);
    }
}
