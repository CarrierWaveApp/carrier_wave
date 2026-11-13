//! Flat share-map viewport framing.
//!
//! Verbatim port of the deleted Swift `FlatMapRenderer.computeViewport`
//! (swift/ios/CarrierWave/Views/BragSheet/FlatMapRenderer.swift, ~:261-323 at
//! commit b80b6ce6) plus its `ActivationMapHelpers.tightestLongitudeBounds`
//! dependency. Recovered here so the Rust flat rasterizer and Android reuse
//! the exact same framing as the old CoreGraphics renderer.
//!
//! The old renderer framed all coordinates (the operator QTH folded into the
//! set) by:
//! 1. taking the raw lat bounds + the *tightest* longitude bounds (largest
//!    empty-gap arc, antimeridian-aware);
//! 2. padding lat by `max(range * 0.25, 8)` and lon by `max(range * 0.2, 8)`
//!    on each side;
//! 3. aspect-fitting the padded box to the image ratio by expanding whichever
//!    axis is too short, keeping the box centered on its bounds midpoint;
//! 4. clamping to at most one full globe of longitude and to ±85° latitude.
//!
//! The result is expressed as a center + spans (not min/max) because the FFI /
//! Swift boundary and the [`super::flat::FlatMapSpec`] both consume
//! `center` + `lat_span`/`lon_span`.

/// A framed flat viewport: projection center + total spans, in degrees.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ShareViewport {
    pub center_lat: f64,
    pub center_lon: f64,
    pub lat_span: f64,
    pub lon_span: f64,
}

/// Tightest enclosing longitude bounds for a set of longitudes, accounting for
/// antimeridian wrap. Verbatim port of
/// `ActivationMapHelpers.tightestLongitudeBounds`
/// (swift/ios/CarrierWave/Views/POTAActivations/ActivationMapHelpers.swift:118-151).
///
/// Returns `(min_lon, max_lon)` where `max_lon - min_lon` is the minimal
/// angular span containing every input. The returned values may exceed
/// `[-180, 180]` when the minimal enclosing arc wraps the antimeridian (e.g.
/// `(170, 370)`), matching the Swift contract. `None` for an empty input.
///
/// The algorithm finds the largest empty gap between consecutive sorted
/// longitudes (including the wrap gap from last to first + 360); the
/// complementary arc is the minimal enclosing span.
///
/// NOTE: `crate::map_bounds::bounds_for` is a sibling two-arc (min/max)
/// calculation used for QSO-map camera bounds. The two are intentionally
/// separate: this one matches the deleted Swift share-card framing exactly;
/// `bounds_for` matches `ActivationMapHelpers.coordinateBounds`. Do NOT
/// unify them — see the note on `bounds_for`.
pub fn tightest_longitude_bounds(longitudes: &[f64]) -> Option<(f64, f64)> {
    let first = *longitudes.first()?;
    if longitudes.len() < 2 {
        return Some((first, first));
    }

    let mut sorted = longitudes.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

    let mut max_interior_gap = 0.0;
    let mut gap_end_index = 0;
    for idx in 1..sorted.len() {
        let gap = sorted[idx] - sorted[idx - 1];
        if gap > max_interior_gap {
            max_interior_gap = gap;
            gap_end_index = idx;
        }
    }

    // The wrap-around gap from last back to first + 360.
    let wrap_gap = (sorted[0] + 360.0) - sorted[sorted.len() - 1];
    if wrap_gap >= max_interior_gap {
        // Wrap is the biggest empty arc — no shifting needed.
        return Some((sorted[0], sorted[sorted.len() - 1]));
    }

    // Interior gap is biggest. Shift points before the gap by +360 so they
    // become contiguous with points after the gap.
    let shifted_min = sorted[gap_end_index];
    let shifted_max = sorted[gap_end_index - 1] + 360.0;
    Some((shifted_min, shifted_max))
}

/// Compute a viewport that frames all `coords` with padding, matched to the
/// `width`/`height` image aspect ratio. Verbatim port of the deleted
/// `FlatMapRenderer.computeViewport`.
///
/// `coords` should already include the operator QTH folded into the set — the
/// old renderer appended `myCoordinate` to the coordinate list before framing,
/// so the caller does the same. The center is the bounds midpoint of the whole
/// set (operator included), NOT the operator QTH.
///
/// Degenerate inputs (empty `coords`, or a zero image dimension) fall back to
/// the same default whole-ish-world viewport the Swift `guard` produced:
/// lat `[-60, 60]`, lon `[-180, 180]`.
pub fn compute_flat_share_viewport(coords: &[(f64, f64)], width: u32, height: u32) -> ShareViewport {
    let default_viewport = ShareViewport {
        center_lat: 0.0,
        center_lon: 0.0,
        lat_span: 120.0,
        lon_span: 360.0,
    };

    if width == 0 || height == 0 {
        return default_viewport;
    }

    let lats: Vec<f64> = coords.iter().map(|c| c.0).collect();
    let lons: Vec<f64> = coords.iter().map(|c| c.1).collect();

    let raw_min_lat = lats.iter().copied().fold(f64::INFINITY, f64::min);
    let raw_max_lat = lats.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    let lon_bounds = tightest_longitude_bounds(&lons);

    let (Some(raw_min_lat), Some(raw_max_lat), Some((raw_min_lon, raw_max_lon))) = (
        raw_min_lat.is_finite().then_some(raw_min_lat),
        raw_max_lat.is_finite().then_some(raw_max_lat),
        lon_bounds,
    ) else {
        return default_viewport;
    };

    let lat_pad = ((raw_max_lat - raw_min_lat) * 0.25).max(8.0);
    let lon_pad = ((raw_max_lon - raw_min_lon) * 0.2).max(8.0);

    let mut v_min_lat = raw_min_lat - lat_pad;
    let mut v_max_lat = raw_max_lat + lat_pad;
    let mut v_min_lon = raw_min_lon - lon_pad;
    let mut v_max_lon = raw_max_lon + lon_pad;

    // Match image aspect ratio: expand the shorter axis so the box's aspect
    // equals the image's, keeping the box centered on its midpoint.
    let image_aspect = f64::from(width) / f64::from(height);
    let lat_range = v_max_lat - v_min_lat;
    let lon_range = v_max_lon - v_min_lon;

    if lon_range / lat_range > image_aspect {
        let new_lat_range = lon_range / image_aspect;
        let center = (v_min_lat + v_max_lat) / 2.0;
        v_min_lat = center - new_lat_range / 2.0;
        v_max_lat = center + new_lat_range / 2.0;
    } else {
        let new_lon_range = lat_range * image_aspect;
        let center = (v_min_lon + v_max_lon) / 2.0;
        v_min_lon = center - new_lon_range / 2.0;
        v_max_lon = center + new_lon_range / 2.0;
    }

    // Clamp to at most one full globe; leave lon otherwise unclamped so
    // antimeridian-spanning viewports retain their shifted values.
    if v_max_lon - v_min_lon > 360.0 {
        let center_lon = (v_min_lon + v_max_lon) / 2.0;
        v_min_lon = center_lon - 180.0;
        v_max_lon = center_lon + 180.0;
    }

    let min_lat = v_min_lat.max(-85.0);
    let max_lat = v_max_lat.min(85.0);

    ShareViewport {
        center_lat: (min_lat + max_lat) / 2.0,
        center_lon: (v_min_lon + v_max_lon) / 2.0,
        lat_span: max_lat - min_lat,
        lon_span: v_max_lon - v_min_lon,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const EPS: f64 = 1e-9;

    #[test]
    fn tightest_bounds_single() {
        assert_eq!(tightest_longitude_bounds(&[42.0]), Some((42.0, 42.0)));
    }

    #[test]
    fn tightest_bounds_empty() {
        assert_eq!(tightest_longitude_bounds(&[]), None);
    }

    #[test]
    fn tightest_bounds_simple_arc() {
        // No wrap: min/max are the plain extremes.
        let (min, max) = tightest_longitude_bounds(&[-120.0, -100.0, -80.0]).unwrap();
        assert!((min - -120.0).abs() < EPS);
        assert!((max - -80.0).abs() < EPS);
    }

    #[test]
    fn tightest_bounds_wraps_antimeridian() {
        // Points at 170, -179, -120: the big empty gap is the interior one
        // (-120 .. 170), so the enclosing arc wraps: 170 .. (241 -> shifted).
        let (min, max) = tightest_longitude_bounds(&[170.0, -179.0, -120.0]).unwrap();
        // Enclosing arc should be the short one crossing the dateline.
        assert!(max > 180.0, "wrapped max should exceed 180 ({max})");
        assert!((max - min) < 180.0, "should pick the short arc ({}° wide)", max - min);
        // Concretely: sorted [-179, -120, 170]; interior gaps 59 and 290; wrap
        // gap = (-179 + 360) - 170 = 11. Largest gap is interior 290 ending at
        // idx 2, so min = 170, max = -120 + 360 = 240.
        assert!((min - 170.0).abs() < EPS);
        assert!((max - 240.0).abs() < EPS);
    }

    #[test]
    fn center_is_bounds_midpoint_operator_off_centroid() {
        // Three pins clustered near lon 10, operator far west at lon -50. The
        // viewport center must sit at the MIDPOINT of the whole bounds
        // (operator folded in), not at the pins' centroid or the operator.
        let coords = vec![(40.0, 8.0), (42.0, 10.0), (41.0, 12.0), (45.0, -50.0)];
        let vp = compute_flat_share_viewport(&coords, 100, 100);
        // Raw lon bounds: [-50, 12]; padded then aspect-fit keeps center at the
        // padded-box midpoint. Padded midpoint of lon = (-50 - pad + 12 + pad)/2
        // = (-50 + 12)/2 = -19. Aspect-fit may expand lon but stays centered.
        assert!((vp.center_lon - -19.0).abs() < EPS, "center_lon {} != -19", vp.center_lon);
    }

    #[test]
    fn padding_floors_apply_for_a_single_point() {
        // A single coordinate has zero raw range, so padding hits the 8°
        // floors: lat pad 8 each side -> 16° raw, lon pad 8 -> 16° raw, then
        // aspect-fit to square (100x100) expands to the larger, so both 16°.
        let vp = compute_flat_share_viewport(&[(30.0, 20.0)], 100, 100);
        assert!((vp.center_lat - 30.0).abs() < EPS);
        assert!((vp.center_lon - 20.0).abs() < EPS);
        // 16 x 16 already square -> stays 16 on both axes.
        assert!((vp.lat_span - 16.0).abs() < EPS, "lat_span {}", vp.lat_span);
        assert!((vp.lon_span - 16.0).abs() < EPS, "lon_span {}", vp.lon_span);
    }

    #[test]
    fn aspect_fit_expands_latitude_for_wide_image() {
        // A wide, short lon/lat box in a SQUARE image: lon/lat ratio > 1 == the
        // image aspect (1.0), so latitude expands to match.
        // Pins span lat [40,42] (range 2), lon [0,40] (range 40).
        let coords = vec![(40.0, 0.0), (42.0, 40.0)];
        let vp = compute_flat_share_viewport(&coords, 100, 100);
        // Padded: lat range = 2 + 2*max(0.5, 8) = 2 + 16 = 18.
        // lon range = 40 + 2*max(8, 8) = 40 + 16 = 56.
        // lon/lat = 56/18 ≈ 3.11 > 1.0 -> latitude expands to lon/aspect = 56.
        assert!((vp.lon_span - 56.0).abs() < EPS, "lon_span {}", vp.lon_span);
        assert!((vp.lat_span - 56.0).abs() < 1e-6, "lat_span {}", vp.lat_span);
    }

    #[test]
    fn aspect_fit_expands_longitude_for_tall_content() {
        // Tall content (big lat range, small lon range) in a square image:
        // lon/lat < aspect, so LONGITUDE expands.
        // Pins span lat [0,60] (range 60), lon [10,12] (range 2).
        let coords = vec![(0.0, 10.0), (60.0, 12.0)];
        let vp = compute_flat_share_viewport(&coords, 100, 100);
        // Padded lat = 60 + 2*max(15, 8) = 60 + 30 = 90 -> clamped ±85 later.
        // Padded lon = 2 + 2*max(0.4, 8) = 2 + 16 = 18.
        // lon/lat = 18/90 = 0.2 < 1.0 aspect -> lon expands to lat_range * aspect.
        // But lat is later clamped to ±85; check lon expanded past its padded 18.
        assert!(vp.lon_span > 18.0, "lon should expand past padded 18 ({})", vp.lon_span);
    }

    #[test]
    fn latitude_clamped_to_85() {
        // Force a huge lat span; the ±85 clamp caps it at 170° total.
        let coords = vec![(-89.0, 0.0), (89.0, 0.5)];
        let vp = compute_flat_share_viewport(&coords, 100, 100);
        assert!(vp.lat_span <= 170.0 + EPS, "lat_span {} must clamp to <=170", vp.lat_span);
        assert!((vp.center_lat).abs() < EPS, "center should stay at equator");
    }

    #[test]
    fn empty_coords_fall_back_to_default() {
        let vp = compute_flat_share_viewport(&[], 100, 100);
        assert!((vp.lat_span - 120.0).abs() < EPS);
        assert!((vp.lon_span - 360.0).abs() < EPS);
    }

    #[test]
    fn zero_dimension_falls_back_to_default() {
        let vp = compute_flat_share_viewport(&[(30.0, 20.0)], 0, 100);
        assert!((vp.lon_span - 360.0).abs() < EPS);
    }
}
