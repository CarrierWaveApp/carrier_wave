//! Activation-multiplier ("rosette") detection — purely geometric, run off
//! the map's boundary overlays. Port of `MultiplierFinder.swift`
//! (`swift/ios/CarrierWave/Views/Map/MultiplierFinder.swift`):
//!
//! - POTA+SOTA: a summit point inside a POTA park polygon (outer ring
//!   contains the point, and the point is not inside any hole).
//! - POTA+WWFF: a WWFF reference that borrowed a POTA park polygon — this is
//!   a 1:1 passthrough of the caller's WWFF-with-boundary list, no geometry.
//! - County line: a park centroid / summit within 1,500 m of a county
//!   boundary ring, using the same local equirectangular projection as the
//!   Swift `pointToSegmentMeters`.
//!
//! Point-in-polygon reuses [`crate::park_geometry::point_in_ring`] (Task 3),
//! which is byte-for-byte the same ray-cast Swift's `ParkBoundary.isPointInRing`
//! uses — `containingPark` in the Swift source calls that same helper.

use crate::park_geometry::point_in_ring;

/// Coordinate in `(lat, lon)` degrees — matches [`crate::park_geometry`]'s
/// tuple convention used throughout this module's ring/point math.
pub type LatLon = (f64, f64);

/// County-line proximity threshold in meters. Swift:
/// `MultiplierFinder.countyLineThresholdMeters`. Pinned exactly — do not
/// "round" to 1,500.0 differently or change to `<=`; the Swift comparison is
/// strict `<`.
pub const COUNTY_LINE_THRESHOLD_METERS: f64 = 1_500.0;

/// The reason a location was flagged as a multiplier opportunity. Swift:
/// `MultiplierKind` (`potaSota` / `potaWwff` / `countyLine`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MultiplierKind {
    PotaSota,
    PotaWwff,
    CountyLine,
}

/// A location flagged as having one or more activation multipliers. Swift:
/// `MultiplierCandidate` (`swift/ios/CarrierWave/Models/MultiplierCandidate.swift`).
#[derive(Debug, Clone, PartialEq)]
pub struct MultiplierCandidate {
    pub kind: MultiplierKind,
    pub latitude: f64,
    pub longitude: f64,
    pub refs: Vec<String>,
    pub distance_m: Option<f64>,
}

/// A summit (or any point-like multiplier source): id/name plus coordinate.
/// Swift: the `summit.code`/`summit.name`/`summit.latitude`/`summit.longitude`
/// fields off `SOTASummit` consumed by `MultiplierFinder.summitCandidates`.
#[derive(Debug, Clone, PartialEq)]
pub struct SummitPoint {
    pub reference: String,
    pub latitude: f64,
    pub longitude: f64,
}

/// A park polygon: reference id plus one or more `(exterior, holes)` rings —
/// mirrors `ParkBoundary.mergedPolygons` (`[MergedPolygon]`, each with an
/// `exterior` ring and `holes: [[Coordinate]]`).
#[derive(Debug, Clone, PartialEq)]
pub struct ParkPolygon {
    pub reference: String,
    pub polygons: Vec<(Vec<LatLon>, Vec<Vec<LatLon>>)>,
}

/// A WWFF reference that already borrowed a POTA park boundary — Swift's
/// `WWFFRenderItem` (code/name/center). No geometry test is performed on
/// these; every entry the caller passes is by definition a POTA+WWFF 2-fer
/// (that's what "borrowed a POTA park polygon" means upstream).
#[derive(Debug, Clone, PartialEq)]
pub struct WwffBorrowed {
    pub reference: String,
    pub latitude: f64,
    pub longitude: f64,
}

/// An admin (county) boundary: reference id plus all rings (exteriors +
/// holes, undifferentiated) — mirrors `AdminBoundary.rings`.
#[derive(Debug, Clone, PartialEq)]
pub struct CountyRings {
    pub reference: String,
    pub rings: Vec<Vec<LatLon>>,
}

/// First park whose polygon (excluding holes) contains `point`. Port of
/// `MultiplierFinder.containingPark` (:95-110) minus the Swift bbox
/// prefilter, which is a pure rendering-perf optimization with no behavioral
/// effect on the geometry test itself.
pub fn containing_park(point: LatLon, parks: &[ParkPolygon]) -> Option<&ParkPolygon> {
    parks.iter().find(|park| {
        park.polygons.iter().any(|(exterior, holes)| {
            point_in_ring(point, exterior) && !holes.iter().any(|hole| point_in_ring(point, hole))
        })
    })
}

/// Perpendicular point-to-segment distance in meters, using the same local
/// equirectangular projection as Swift's `pointToSegmentMeters` (:154-176):
/// longitude scaled by `cos(point.latitude)`, both axes scaled by
/// 111,320 m/deg. Degenerate (zero-length) segments fall back to the
/// point-to-endpoint distance.
fn point_to_segment_meters(point: LatLon, start: LatLon, end: LatLon) -> f64 {
    let meters_per_deg_lat = 111_320.0;
    let meters_per_deg_lon = 111_320.0 * (point.0 * std::f64::consts::PI / 180.0).cos();

    let px = point.1 * meters_per_deg_lon;
    let py = point.0 * meters_per_deg_lat;
    let ax = start.1 * meters_per_deg_lon;
    let ay = start.0 * meters_per_deg_lat;
    let bx = end.1 * meters_per_deg_lon;
    let by = end.0 * meters_per_deg_lat;

    let dx = bx - ax;
    let dy = by - ay;
    let len_sq = dx * dx + dy * dy;
    if len_sq == 0.0 {
        return px.hypot_diff(ax, py, ay);
    }
    let proj = ((px - ax) * dx + (py - ay) * dy) / len_sq;
    let proj = proj.clamp(0.0, 1.0);
    px.hypot_diff(ax + proj * dx, py, ay + proj * dy)
}

/// Small local helper trait to keep `point_to_segment_meters` readable:
/// `a.hypot_diff(b, c, d) == hypot(a - b, c - d)`.
trait HypotDiff {
    fn hypot_diff(self, other_x: f64, y: f64, other_y: f64) -> f64;
}

impl HypotDiff for f64 {
    fn hypot_diff(self, other_x: f64, y: f64, other_y: f64) -> f64 {
        (self - other_x).hypot(y - other_y)
    }
}

/// Minimum distance in meters from `point` to any segment of `ring`. Port of
/// `MultiplierFinder.minDistanceToRingMeters` (:131-152), including the
/// early-exit once a segment is found under the county-line threshold.
fn min_distance_to_ring_meters(point: LatLon, ring: &[LatLon]) -> f64 {
    if ring.len() < 2 {
        return f64::INFINITY;
    }
    let mut min_dist = f64::INFINITY;
    let mut prev = ring[0];
    for &curr in &ring[1..] {
        let dist = point_to_segment_meters(point, prev, curr);
        if dist < min_dist {
            min_dist = dist;
            if min_dist < COUNTY_LINE_THRESHOLD_METERS {
                return min_dist;
            }
        }
        prev = curr;
    }
    min_dist
}

/// `true` iff `point` is within [`COUNTY_LINE_THRESHOLD_METERS`] of any ring
/// of any county in `counties`. Port of `MultiplierFinder.nearCountyLine`
/// (:112-129) minus the Swift bbox prefilter (same rationale as
/// [`containing_park`] — pure perf, no behavioral effect).
fn near_county_line(point: LatLon, counties: &[CountyRings]) -> bool {
    counties.iter().any(|county| {
        county
            .rings
            .iter()
            .any(|ring| min_distance_to_ring_meters(point, ring) < COUNTY_LINE_THRESHOLD_METERS)
    })
}

/// Find all activation-multiplier candidates from the boundary overlays
/// currently loaded on the map. Port of `MultiplierFinder.find` /
/// `summitCandidates` / `wwffCandidates` / `parkCountyCandidates`
/// (:21-92), flattened to the interface the brief specifies: plain slices
/// in, `Vec<MultiplierCandidate>` out, no sort/dedup (that's a display
/// concern the caller — Task 7 — owns).
///
/// - `summits`: point sources tested against `park_polygons` (POTA+SOTA) and
///   `county_rings` (county-line).
/// - `park_polygons`: also tested for county-line proximity via each park's
///   *first* polygon's exterior ring centroid-free — matches Swift's
///   `parkCountyCandidates`, which tests the park's precomputed bbox center,
///   not a ring vertex; callers pass that same bbox-center point per park
///   alongside its geometry (see [`ParkPolygon`] doc — the park's `polygons`
///   field is reused for the POTA+SOTA test only; county-line testing here
///   uses the caller-supplied `park_centers` parallel slice).
/// - `wwff_borrowed`: passthrough POTA+WWFF candidates (no geometry test).
/// - `county_rings`: the county boundaries to test proximity against.
pub fn find_multipliers(
    summits: &[SummitPoint],
    park_polygons: &[ParkPolygon],
    park_centers: &[(String, LatLon)],
    wwff_borrowed: &[WwffBorrowed],
    county_rings: &[CountyRings],
) -> Vec<MultiplierCandidate> {
    let mut candidates = Vec::new();

    for summit in summits {
        let point = (summit.latitude, summit.longitude);
        if let Some(park) = containing_park(point, park_polygons) {
            candidates.push(MultiplierCandidate {
                kind: MultiplierKind::PotaSota,
                latitude: summit.latitude,
                longitude: summit.longitude,
                refs: vec![summit.reference.clone(), park.reference.clone()],
                distance_m: None,
            });
        }
        if !county_rings.is_empty() && near_county_line(point, county_rings) {
            candidates.push(MultiplierCandidate {
                kind: MultiplierKind::CountyLine,
                latitude: summit.latitude,
                longitude: summit.longitude,
                refs: vec![summit.reference.clone()],
                distance_m: None,
            });
        }
    }

    for item in wwff_borrowed {
        candidates.push(MultiplierCandidate {
            kind: MultiplierKind::PotaWwff,
            latitude: item.latitude,
            longitude: item.longitude,
            refs: vec![item.reference.clone()],
            distance_m: None,
        });
    }

    if !county_rings.is_empty() {
        for (reference, center) in park_centers {
            if near_county_line(*center, county_rings) {
                candidates.push(MultiplierCandidate {
                    kind: MultiplierKind::CountyLine,
                    latitude: center.0,
                    longitude: center.1,
                    refs: vec![reference.clone()],
                    distance_m: None,
                });
            }
        }
    }

    candidates
}

#[cfg(test)]
mod tests {
    use super::*;

    fn unit_square_ring() -> Vec<LatLon> {
        vec![(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)]
    }

    // --- containing_park / point-in-polygon ---

    #[test]
    fn containing_park_finds_park_with_point_inside_exterior() {
        let park = ParkPolygon {
            reference: "US-0001".to_string(),
            polygons: vec![(unit_square_ring(), vec![])],
        };
        let found = containing_park((0.5, 0.5), std::slice::from_ref(&park));
        assert_eq!(found.map(|p| p.reference.as_str()), Some("US-0001"));
    }

    #[test]
    fn containing_park_returns_none_for_point_outside_all_parks() {
        let park = ParkPolygon {
            reference: "US-0001".to_string(),
            polygons: vec![(unit_square_ring(), vec![])],
        };
        let found = containing_park((5.0, 5.0), std::slice::from_ref(&park));
        assert!(found.is_none());
    }

    #[test]
    fn containing_park_excludes_point_inside_a_hole() {
        // A donut park: outer unit square minus a small inner hole centered
        // at (0.5, 0.5). A point inside the hole must NOT count as
        // "containing", matching Swift's `!polygon.holes.contains { ... }`.
        let hole = vec![(0.4, 0.4), (0.4, 0.6), (0.6, 0.6), (0.6, 0.4)];
        let park = ParkPolygon {
            reference: "US-0002".to_string(),
            polygons: vec![(unit_square_ring(), vec![hole])],
        };
        let inside_hole = containing_park((0.5, 0.5), std::slice::from_ref(&park));
        assert!(inside_hole.is_none(), "point inside hole should not match");

        let inside_ring_outside_hole =
            containing_park((0.1, 0.1), std::slice::from_ref(&park));
        assert!(inside_ring_outside_hole.is_some());
    }

    #[test]
    fn containing_park_returns_first_match_when_multiple_overlap() {
        let park_a = ParkPolygon {
            reference: "US-0001".to_string(),
            polygons: vec![(unit_square_ring(), vec![])],
        };
        let park_b = ParkPolygon {
            reference: "US-0002".to_string(),
            polygons: vec![(unit_square_ring(), vec![])],
        };
        let parks = [park_a, park_b];
        let found = containing_park((0.5, 0.5), &parks);
        assert_eq!(found.map(|p| p.reference.as_str()), Some("US-0001"));
    }

    // --- county-line distance pinning ---

    #[test]
    fn point_at_1499_meters_from_segment_is_near_county_line() {
        // A north-south segment along longitude 0, from lat 0 to lat 1. At
        // the equator, 1 degree of longitude ~= 111,320 m. Offset the test
        // point east by exactly 1,499 m worth of longitude so its
        // perpendicular distance to the segment is 1,499 m.
        let meters_per_deg_lon = 111_320.0; // cos(0) == 1 at the equator
        let offset_deg = 1_499.0 / meters_per_deg_lon;
        let point = (0.5, offset_deg);
        let ring = vec![(0.0, 0.0), (1.0, 0.0)];
        let dist = min_distance_to_ring_meters(point, &ring);
        assert!(
            (dist - 1_499.0).abs() < 0.5,
            "expected ~1499m, got {dist}"
        );
        assert!(dist < COUNTY_LINE_THRESHOLD_METERS);

        let county = CountyRings {
            reference: "test-county".to_string(),
            rings: vec![ring],
        };
        assert!(near_county_line(point, std::slice::from_ref(&county)));
    }

    #[test]
    fn point_at_1501_meters_from_segment_is_not_near_county_line() {
        let meters_per_deg_lon = 111_320.0;
        let offset_deg = 1_501.0 / meters_per_deg_lon;
        let point = (0.5, offset_deg);
        let ring = vec![(0.0, 0.0), (1.0, 0.0)];
        let dist = min_distance_to_ring_meters(point, &ring);
        assert!(
            (dist - 1_501.0).abs() < 0.5,
            "expected ~1501m, got {dist}"
        );
        assert!(dist >= COUNTY_LINE_THRESHOLD_METERS);

        let county = CountyRings {
            reference: "test-county".to_string(),
            rings: vec![ring],
        };
        assert!(!near_county_line(point, std::slice::from_ref(&county)));
    }

    #[test]
    fn threshold_constant_is_pinned_to_1500_meters() {
        assert_eq!(COUNTY_LINE_THRESHOLD_METERS, 1_500.0);
    }

    #[test]
    fn min_distance_to_degenerate_ring_is_infinite() {
        assert_eq!(min_distance_to_ring_meters((0.0, 0.0), &[(0.0, 0.0)]), f64::INFINITY);
        assert_eq!(min_distance_to_ring_meters((0.0, 0.0), &[]), f64::INFINITY);
    }

    // --- find_multipliers integration ---

    #[test]
    fn find_multipliers_flags_summit_inside_park_as_pota_sota() {
        let summits = vec![SummitPoint {
            reference: "W1/AA-001".to_string(),
            latitude: 0.5,
            longitude: 0.5,
        }];
        let parks = vec![ParkPolygon {
            reference: "US-0001".to_string(),
            polygons: vec![(unit_square_ring(), vec![])],
        }];
        let candidates = find_multipliers(&summits, &parks, &[], &[], &[]);
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].kind, MultiplierKind::PotaSota);
        assert_eq!(candidates[0].refs, vec!["W1/AA-001", "US-0001"]);
    }

    #[test]
    fn find_multipliers_ignores_summit_outside_all_parks_and_counties() {
        let summits = vec![SummitPoint {
            reference: "W1/AA-002".to_string(),
            latitude: 50.0,
            longitude: 50.0,
        }];
        let parks = vec![ParkPolygon {
            reference: "US-0001".to_string(),
            polygons: vec![(unit_square_ring(), vec![])],
        }];
        let candidates = find_multipliers(&summits, &parks, &[], &[], &[]);
        assert!(candidates.is_empty());
    }

    #[test]
    fn find_multipliers_passes_through_wwff_borrowed_unconditionally() {
        let wwff = vec![WwffBorrowed {
            reference: "KFF-0001".to_string(),
            latitude: 10.0,
            longitude: 10.0,
        }];
        let candidates = find_multipliers(&[], &[], &[], &wwff, &[]);
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].kind, MultiplierKind::PotaWwff);
        assert_eq!(candidates[0].refs, vec!["KFF-0001"]);
    }

    #[test]
    fn find_multipliers_flags_park_center_near_county_line() {
        let ring = vec![(0.0, 0.0), (1.0, 0.0)];
        let counties = vec![CountyRings {
            reference: "county".to_string(),
            rings: vec![ring],
        }];
        // ~500m east of the boundary segment, well under the 1500m threshold.
        let offset_deg = 500.0 / 111_320.0;
        let park_centers = vec![("US-0003".to_string(), (0.5, offset_deg))];
        let candidates = find_multipliers(&[], &[], &park_centers, &[], &counties);
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].kind, MultiplierKind::CountyLine);
        assert_eq!(candidates[0].refs, vec!["US-0003"]);
    }

    #[test]
    fn find_multipliers_skips_county_line_test_when_no_counties() {
        // Swift's `nearCountyLine` / `parkCountyCandidates` short-circuit
        // when `counties.isEmpty` — pin that an empty county list produces
        // no county-line candidates even for a point that would otherwise
        // match against a nearby ring (there simply isn't one to check).
        let summits = vec![SummitPoint {
            reference: "W1/AA-003".to_string(),
            latitude: 0.0,
            longitude: 0.0,
        }];
        let candidates = find_multipliers(&summits, &[], &[], &[], &[]);
        assert!(candidates.is_empty());
    }
}
