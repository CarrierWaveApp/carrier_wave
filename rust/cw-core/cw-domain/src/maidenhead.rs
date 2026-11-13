//! Maidenhead grid locator ↔ coordinate conversion, distance, and bearing.
//!
//! Faithful port of `MaidenheadConverter.swift`
//! (`swift/packages/CarrierWaveCore/Sources/CarrierWaveCore/MaidenheadConverter.swift`).
//! Preserves observable behavior: same precision rules (4/6/8), same haversine
//! constant, same bearing range (0–360, half-open at 360).

use std::f64::consts::PI;

/// A simple latitude/longitude coordinate. The Swift side has the same name
/// and shape (`Coordinate.swift`); kept that way for cross-language parity.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Coordinate {
    pub latitude: f64,
    pub longitude: f64,
}

impl Coordinate {
    pub fn new(latitude: f64, longitude: f64) -> Self {
        Self { latitude, longitude }
    }
}

/// Output precision when encoding a grid locator. The Swift enum is
/// `Precision { four = 4, six = 6, eight = 8 }`; same numeric values.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Precision {
    Four,
    Six,
    Eight,
}

const EARTH_RADIUS_KM: f64 = 6_371.0;
const SUBSQUARE_LON_STEP: f64 = 2.0 / 24.0;
const SUBSQUARE_LAT_STEP: f64 = 1.0 / 24.0;
const MAX_REGION_GRID_COUNT: i64 = 2_000;

/// Center coordinate of a Maidenhead grid. Returns `None` for invalid input.
/// 4-char → center of 2°×1° square. 6-char → center of subsquare. 8-char →
/// center of extended subsquare (1/10 of a subsquare per axis).
pub fn coordinate_from_grid(grid: &str) -> Option<Coordinate> {
    let upper = grid.to_uppercase();
    let chars: Vec<char> = upper.chars().collect();
    let base = parse_field_square(&chars)?;
    let mut lon = (base.lon_field * 20 - 180 + base.lon_square * 2) as f64;
    let mut lat = (base.lat_field * 10 - 90 + base.lat_square) as f64;

    let Some(sub) = parse_subsquare(&chars) else {
        // 4-char: center of 2°×1° square
        lon += 1.0;
        lat += 0.5;
        return Some(Coordinate::new(lat, lon));
    };
    lon += sub.lon as f64 * SUBSQUARE_LON_STEP;
    lat += sub.lat as f64 * SUBSQUARE_LAT_STEP;

    let Some(ext) = parse_extended_subsquare(&chars) else {
        // 6-char: center of subsquare
        lon += SUBSQUARE_LON_STEP / 2.0;
        lat += SUBSQUARE_LAT_STEP / 2.0;
        return Some(Coordinate::new(lat, lon));
    };
    let ext_lon_step = SUBSQUARE_LON_STEP / 10.0;
    let ext_lat_step = SUBSQUARE_LAT_STEP / 10.0;
    lon += ext.lon as f64 * ext_lon_step + ext_lon_step / 2.0;
    lat += ext.lat as f64 * ext_lat_step + ext_lat_step / 2.0;
    Some(Coordinate::new(lat, lon))
}

/// Encode a coordinate as a Maidenhead grid at the requested precision.
pub fn grid_from_coordinate(coord: Coordinate, precision: Precision) -> String {
    // Normalize: longitude to 0..360, latitude to 0..180. Matches the Swift impl.
    let lon = coord.longitude + 180.0;
    let lat = coord.latitude + 90.0;

    let lon_field = (lon / 20.0) as i64;
    let lat_field = (lat / 10.0) as i64;
    let lon_square = ((lon - lon_field as f64 * 20.0) / 2.0) as i64;
    let lat_square = ((lat - lat_field as f64 * 10.0) / 1.0) as i64;

    let mut out = String::with_capacity(8);
    out.push((b'A' + lon_field.min(17) as u8) as char);
    out.push((b'A' + lat_field.min(17) as u8) as char);
    out.push((b'0' + lon_square.min(9) as u8) as char);
    out.push((b'0' + lat_square.min(9) as u8) as char);

    if precision == Precision::Four {
        return out;
    }

    let lon_remainder = lon - lon_field as f64 * 20.0 - lon_square as f64 * 2.0;
    let lat_remainder = lat - lat_field as f64 * 10.0 - lat_square as f64 * 1.0;
    let lon_subsquare = (lon_remainder / SUBSQUARE_LON_STEP) as i64;
    let lat_subsquare = (lat_remainder / SUBSQUARE_LAT_STEP) as i64;
    out.push((b'a' + lon_subsquare.min(23) as u8) as char);
    out.push((b'a' + lat_subsquare.min(23) as u8) as char);

    if precision == Precision::Six {
        return out;
    }

    let lon_ext_remainder = lon_remainder - lon_subsquare as f64 * SUBSQUARE_LON_STEP;
    let lat_ext_remainder = lat_remainder - lat_subsquare as f64 * SUBSQUARE_LAT_STEP;
    let lon_ext = (lon_ext_remainder / (SUBSQUARE_LON_STEP / 10.0)) as i64;
    let lat_ext = (lat_ext_remainder / (SUBSQUARE_LAT_STEP / 10.0)) as i64;
    out.push((b'0' + lon_ext.min(9) as u8) as char);
    out.push((b'0' + lat_ext.min(9) as u8) as char);
    out
}

/// `true` iff `grid` parses to a valid coordinate.
pub fn is_valid(grid: &str) -> bool {
    coordinate_from_grid(grid).is_some()
}

/// SW and NE corners of a 4-char grid square (2° × 1°). `None` for invalid.
pub fn grid_bounds(grid: &str) -> Option<(Coordinate, Coordinate)> {
    let upper = grid.to_uppercase();
    let chars: Vec<char> = upper.chars().collect();
    if chars.len() < 4 {
        return None;
    }
    let fs = parse_field_square(&chars)?;
    let sw_lon = (fs.lon_field * 20 - 180 + fs.lon_square * 2) as f64;
    let sw_lat = (fs.lat_field * 10 - 90 + fs.lat_square) as f64;
    Some((
        Coordinate::new(sw_lat, sw_lon),
        Coordinate::new(sw_lat + 1.0, sw_lon + 2.0),
    ))
}

/// SW and NE corners of a 6-char Maidenhead tile (~5′ × 2.5′). `None` for invalid.
pub fn tile_bounds(tile: &str) -> Option<(Coordinate, Coordinate)> {
    let upper = tile.to_uppercase();
    let chars: Vec<char> = upper.chars().collect();
    if chars.len() < 6 {
        return None;
    }
    let fs = parse_field_square(&chars)?;
    let sub = parse_subsquare(&chars)?;
    let sw_lon = (fs.lon_field * 20 - 180 + fs.lon_square * 2) as f64
        + sub.lon as f64 * SUBSQUARE_LON_STEP;
    let sw_lat = (fs.lat_field * 10 - 90 + fs.lat_square) as f64
        + sub.lat as f64 * SUBSQUARE_LAT_STEP;
    Some((
        Coordinate::new(sw_lat, sw_lon),
        Coordinate::new(sw_lat + SUBSQUARE_LAT_STEP, sw_lon + SUBSQUARE_LON_STEP),
    ))
}

/// All 4-char grid locators within a region. Empty if the region is invalid or
/// would produce more than `MAX_REGION_GRID_COUNT` grids (matches Swift's 2000
/// guard against accidental world-spanning queries).
pub fn grids_in_region(sw: Coordinate, ne: Coordinate) -> Vec<String> {
    let min_lat = sw.latitude.max(-90.0);
    let max_lat = ne.latitude.min(90.0);
    let min_lon = sw.longitude.max(-180.0);
    let max_lon = ne.longitude.min(180.0);

    let start_lon = ((min_lon + 180.0) / 2.0).floor() as i64;
    let end_lon = ((max_lon + 180.0) / 2.0).floor() as i64;
    let start_lat = (min_lat + 90.0).floor() as i64;
    let end_lat = (max_lat + 90.0).floor() as i64;

    let count = (end_lon - start_lon + 1) * (end_lat - start_lat + 1);
    if count <= 0 || count > MAX_REGION_GRID_COUNT {
        return Vec::new();
    }

    let mut grids = Vec::with_capacity(count as usize);
    for lon_idx in start_lon..=end_lon {
        let field1 = lon_idx / 10;
        let square1 = lon_idx % 10;
        if !(0..18).contains(&field1) {
            continue;
        }
        for lat_idx in start_lat..=end_lat {
            let field2 = lat_idx / 10;
            let square2 = lat_idx % 10;
            if !(0..18).contains(&field2) {
                continue;
            }
            let mut s = String::with_capacity(4);
            s.push((b'A' + field1 as u8) as char);
            s.push((b'A' + field2 as u8) as char);
            s.push((b'0' + square1 as u8) as char);
            s.push((b'0' + square2 as u8) as char);
            grids.push(s);
        }
    }
    grids
}

/// A 6-char TOTA tile rectangle: the tile locator plus its SW/NE corner
/// bounds, expanded into the four fields used by callers that don't want to
/// re-derive south/west/north/east from a `(Coordinate, Coordinate)` pair.
#[derive(Clone, Debug, PartialEq)]
pub struct TotaTile {
    pub tile: String,
    pub south: f64,
    pub west: f64,
    pub north: f64,
    pub east: f64,
}

/// TOTA tile longitude/latitude step — a 6-char tile spans 2°/24 longitude ×
/// 1°/24 latitude, same as [`SUBSQUARE_LON_STEP`]/[`SUBSQUARE_LAT_STEP`].
/// Kept as separate constants (rather than reusing the subsquare ones
/// directly) to mirror Swift's `MapGridGeometry.tileLonStep`/`tileLatStep`
/// naming 1:1 for anyone diffing the two sources side by side.
const TOTA_TILE_LON_STEP: f64 = SUBSQUARE_LON_STEP;
const TOTA_TILE_LAT_STEP: f64 = SUBSQUARE_LAT_STEP;

/// All 6-char TOTA tile rectangles within `lat_span`×`lon_span` degrees of
/// `center`, capped at `cap` tiles. Port of `MapGridGeometry.tileRects` +
/// `indexBounds` (`swift/ios/CarrierWave/Views/Map/ParkSearchMapKit+Grids.swift`
/// :41-73, :92-109). Swift additionally gates on a fixed `tileSpanGate` (0.6°)
/// before calling this at all and hard-codes `maxVisibleTiles = 1_500`; both
/// are caller concerns here — `lat_span`/`lon_span`/`cap` are passed in so the
/// UI layer (Task 7) owns those thresholds, matching the brief's signature
/// `tota_tiles_in_region(center, lat_span, lon_span, cap)`.
///
/// Index bounds are computed exactly like Swift's `indexBounds`: clamp the
/// region to the globe, then `floor((coord + offset) / step)` per axis — NOT
/// the `grids_in_region` convention of clamping min/max separately post-hoc,
/// though the effect is equivalent since both clamp before flooring.
/// Returns an empty `Vec` if the resulting tile count is 0 or exceeds `cap`
/// (mirrors Swift's `guard count > 0, count <= maxVisibleTiles`).
pub fn tota_tiles_in_region(center: Coordinate, lat_span: f64, lon_span: f64, cap: i64) -> Vec<TotaTile> {
    let sw_lat = (center.latitude - lat_span / 2.0).max(-90.0);
    let ne_lat = (center.latitude + lat_span / 2.0).min(90.0);
    let sw_lon = (center.longitude - lon_span / 2.0).max(-180.0);
    let ne_lon = (center.longitude + lon_span / 2.0).min(180.0);

    let start_lon = ((sw_lon + 180.0) / TOTA_TILE_LON_STEP).floor() as i64;
    let end_lon = ((ne_lon + 180.0) / TOTA_TILE_LON_STEP).floor() as i64;
    let start_lat = ((sw_lat + 90.0) / TOTA_TILE_LAT_STEP).floor() as i64;
    let end_lat = ((ne_lat + 90.0) / TOTA_TILE_LAT_STEP).floor() as i64;

    let count = (end_lon - start_lon + 1) * (end_lat - start_lat + 1);
    if count <= 0 || count > cap {
        return Vec::new();
    }

    let mut tiles = Vec::with_capacity(count as usize);
    for lon_idx in start_lon..=end_lon {
        let tile_sw_lon = -180.0 + lon_idx as f64 * TOTA_TILE_LON_STEP;
        let tile_ne_lon = tile_sw_lon + TOTA_TILE_LON_STEP;
        for lat_idx in start_lat..=end_lat {
            let tile_sw_lat = -90.0 + lat_idx as f64 * TOTA_TILE_LAT_STEP;
            let tile_ne_lat = tile_sw_lat + TOTA_TILE_LAT_STEP;
            let center_coord = Coordinate::new(
                (tile_sw_lat + tile_ne_lat) / 2.0,
                (tile_sw_lon + tile_ne_lon) / 2.0,
            );
            let tile = grid_from_coordinate(center_coord, Precision::Six);
            tiles.push(TotaTile {
                tile,
                south: tile_sw_lat,
                west: tile_sw_lon,
                north: tile_ne_lat,
                east: tile_ne_lon,
            });
        }
    }
    tiles
}

/// Great-circle distance in km between two grids, or `None` if either is invalid.
pub fn distance_km(grid1: &str, grid2: &str) -> Option<f64> {
    let c1 = coordinate_from_grid(grid1)?;
    let c2 = coordinate_from_grid(grid2)?;
    Some(haversine_km(c1, c2))
}

/// Great-circle distance in statute miles, or `None` if either grid is invalid.
pub fn distance_miles(grid1: &str, grid2: &str) -> Option<f64> {
    distance_km(grid1, grid2).map(|km| km * 0.621_371)
}

/// Initial bearing (forward azimuth, degrees) from `grid1` to `grid2`, in
/// `[0, 360)`. `None` if either grid is invalid.
pub fn bearing(grid1: &str, grid2: &str) -> Option<f64> {
    let c1 = coordinate_from_grid(grid1)?;
    let c2 = coordinate_from_grid(grid2)?;
    Some(initial_bearing(c1, c2))
}

/// Great-circle distance in km between two coordinates. The coordinate-based
/// counterpart of [`distance_km`], for callers (e.g. the QSO-detail map's POTA
/// park fallback) that already hold lat/lon and have no grid to resolve.
pub fn distance_km_between(c1: Coordinate, c2: Coordinate) -> f64 {
    haversine_km(c1, c2)
}

/// Initial bearing (forward azimuth, degrees, `[0, 360)`) between two
/// coordinates. Coordinate-based counterpart of [`bearing`].
pub fn bearing_between(c1: Coordinate, c2: Coordinate) -> f64 {
    initial_bearing(c1, c2)
}

// ---------- internals ----------

struct FieldSquare {
    lon_field: i64,
    lat_field: i64,
    lon_square: i64,
    lat_square: i64,
}

struct SubOrExt {
    lon: i64,
    lat: i64,
}

fn parse_field_square(chars: &[char]) -> Option<FieldSquare> {
    if chars.len() < 4 {
        return None;
    }
    let lon_field = letter_index(chars[0])?;
    let lat_field = letter_index(chars[1])?;
    if !(0..18).contains(&lon_field) || !(0..18).contains(&lat_field) {
        return None;
    }
    let lon_square = digit(chars[2])?;
    let lat_square = digit(chars[3])?;
    Some(FieldSquare {
        lon_field,
        lat_field,
        lon_square,
        lat_square,
    })
}

fn parse_subsquare(chars: &[char]) -> Option<SubOrExt> {
    if chars.len() < 6 {
        return None;
    }
    // Swift uppercases the input first; subsquare letters A–X (24 wide).
    let lon = letter_index(chars[4])?;
    let lat = letter_index(chars[5])?;
    if !(0..24).contains(&lon) || !(0..24).contains(&lat) {
        return None;
    }
    Some(SubOrExt { lon, lat })
}

fn parse_extended_subsquare(chars: &[char]) -> Option<SubOrExt> {
    if chars.len() < 8 {
        return None;
    }
    let lon = digit(chars[6])?;
    let lat = digit(chars[7])?;
    if !(0..10).contains(&lon) || !(0..10).contains(&lat) {
        return None;
    }
    Some(SubOrExt { lon, lat })
}

fn letter_index(ch: char) -> Option<i64> {
    let byte = ch as u32;
    if (b'A' as u32..=b'Z' as u32).contains(&byte) {
        Some((byte - b'A' as u32) as i64)
    } else {
        None
    }
}

fn digit(ch: char) -> Option<i64> {
    ch.to_digit(10).map(|d| d as i64)
}

fn haversine_km(c1: Coordinate, c2: Coordinate) -> f64 {
    let lat1 = c1.latitude * PI / 180.0;
    let lat2 = c2.latitude * PI / 180.0;
    let d_lat = (c2.latitude - c1.latitude) * PI / 180.0;
    let d_lon = (c2.longitude - c1.longitude) * PI / 180.0;
    let a = (d_lat / 2.0).sin().powi(2)
        + lat1.cos() * lat2.cos() * (d_lon / 2.0).sin().powi(2);
    let angular = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());
    EARTH_RADIUS_KM * angular
}

fn initial_bearing(c1: Coordinate, c2: Coordinate) -> f64 {
    let lat1 = c1.latitude * PI / 180.0;
    let lat2 = c2.latitude * PI / 180.0;
    let d_lon = (c2.longitude - c1.longitude) * PI / 180.0;
    let x = d_lon.sin() * lat2.cos();
    let y = lat1.cos() * lat2.sin() - lat1.sin() * lat2.cos() * d_lon.cos();
    let bearing_deg = x.atan2(y) * 180.0 / PI;
    (bearing_deg + 360.0).rem_euclid(360.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn approx_eq(a: f64, b: f64, eps: f64) -> bool {
        (a - b).abs() < eps
    }

    #[test]
    fn round_trip_well_known_grids() {
        // FN31pr is the canonical Newington, CT grid (W1AW). Center is at
        // (~41.75, ~-72.708). Loose tolerance — the parity gate is on the
        // Swift side.
        let coord = coordinate_from_grid("FN31pr").unwrap();
        assert!(
            approx_eq(coord.latitude, 41.75, 0.05),
            "lat: {}",
            coord.latitude
        );
        assert!(
            approx_eq(coord.longitude, -72.708, 0.05),
            "lon: {}",
            coord.longitude
        );

        // Round-trip through grid_from_coordinate at six-char precision
        // returns the same letters (case-insensitive).
        let grid = grid_from_coordinate(coord, Precision::Six);
        assert_eq!(grid.to_uppercase(), "FN31PR");
    }

    #[test]
    fn precision_truncates_correctly() {
        let coord = Coordinate::new(41.7, -72.5);
        assert_eq!(grid_from_coordinate(coord, Precision::Four).len(), 4);
        assert_eq!(grid_from_coordinate(coord, Precision::Six).len(), 6);
        assert_eq!(grid_from_coordinate(coord, Precision::Eight).len(), 8);
    }

    #[test]
    fn invalid_grids_return_none() {
        assert!(coordinate_from_grid("ZZ").is_none());
        assert!(coordinate_from_grid("ZZ99").is_none()); // field out of range
        assert!(coordinate_from_grid("FN3A").is_none()); // non-digit square
        assert!(!is_valid("garbage"));
    }

    #[test]
    fn distance_km_w1aw_to_california() {
        // FN31pr (W1AW, Newington CT) → DM12 (Los Angeles area). The actual
        // grid-center distance is ~4012 km; allow ±200 km for grid centering.
        let km = distance_km("FN31pr", "DM12").unwrap();
        assert!(approx_eq(km, 4012.0, 200.0), "got {km}");
    }

    #[test]
    fn bearing_is_in_zero_three_sixty() {
        let b = bearing("FN31pr", "DM12").unwrap();
        assert!((0.0..360.0).contains(&b), "bearing out of range: {b}");
    }

    #[test]
    fn grid_bounds_size_matches_swift() {
        let (sw, ne) = grid_bounds("FN31").unwrap();
        assert!(approx_eq(ne.longitude - sw.longitude, 2.0, 1e-9));
        assert!(approx_eq(ne.latitude - sw.latitude, 1.0, 1e-9));
    }

    #[test]
    fn tile_bounds_size_matches_swift() {
        let (sw, ne) = tile_bounds("EM73uu").unwrap();
        assert!(approx_eq(ne.longitude - sw.longitude, SUBSQUARE_LON_STEP, 1e-9));
        assert!(approx_eq(ne.latitude - sw.latitude, SUBSQUARE_LAT_STEP, 1e-9));
    }

    #[test]
    fn region_returns_grids_and_respects_cap() {
        // Tiny region: should include at least one grid.
        let grids = grids_in_region(
            Coordinate::new(41.0, -73.0),
            Coordinate::new(42.0, -72.0),
        );
        assert!(!grids.is_empty());

        // Region just under the 2000-grid cap (~1681 grids) — should return.
        let large = grids_in_region(
            Coordinate::new(0.0, 0.0),
            Coordinate::new(40.0, 80.0),
        );
        assert!(!large.is_empty());
        assert!(large.len() as i64 <= MAX_REGION_GRID_COUNT);

        // Whole-world region (181 × 181 = 32 761) blows the cap → empty.
        let world = grids_in_region(
            Coordinate::new(-90.0, -180.0),
            Coordinate::new(90.0, 180.0),
        );
        assert!(world.is_empty(), "world region should hit cap, got {}", world.len());
    }

    #[test]
    fn tota_tiles_in_region_corner_math_matches_known_grid() {
        // A tiny region centered well inside the interior of a single TOTA
        // tile near Kansas (offset off the tile grid lines so a small span
        // doesn't straddle a boundary), so exactly one tile is returned.
        // Assert both the corner rectangle size (5' lon / 2.5' lat, i.e. the
        // same SUBSQUARE_* steps as tile_bounds) and that the derived
        // 6-char locator round-trips through tile_bounds to the same
        // rectangle.
        let center = Coordinate::new(38.02, -97.02);
        let tiles = tota_tiles_in_region(center, 0.01, 0.01, 100);
        assert_eq!(tiles.len(), 1, "expected exactly one tile, got {tiles:?}");

        let tile = &tiles[0];
        assert!(approx_eq(tile.north - tile.south, SUBSQUARE_LAT_STEP, 1e-9));
        assert!(approx_eq(tile.east - tile.west, SUBSQUARE_LON_STEP, 1e-9));
        assert_eq!(tile.tile.len(), 6);

        // Round-trip: tile_bounds(tile.tile) must reproduce the same
        // rectangle the region scan computed independently via index math.
        let (sw, ne) = tile_bounds(&tile.tile).unwrap();
        assert!(approx_eq(sw.latitude, tile.south, 1e-9));
        assert!(approx_eq(sw.longitude, tile.west, 1e-9));
        assert!(approx_eq(ne.latitude, tile.north, 1e-9));
        assert!(approx_eq(ne.longitude, tile.east, 1e-9));
    }

    #[test]
    fn tota_tiles_in_region_respects_cap() {
        // A region spanning many tiles (2 degrees square ~= 24 x 24 = 576
        // tiles) with a cap well under that count should return empty,
        // matching Swift's `guard count > 0, count <= maxVisibleTiles`.
        let center = Coordinate::new(38.0, -97.0);
        let over_cap = tota_tiles_in_region(center, 2.0, 2.0, 10);
        assert!(over_cap.is_empty(), "expected cap to reject, got {} tiles", over_cap.len());

        // Same region with a cap comfortably above the tile count returns
        // results.
        let under_cap = tota_tiles_in_region(center, 2.0, 2.0, 10_000);
        assert!(!under_cap.is_empty());
        assert!(under_cap.len() as i64 <= 10_000);
    }

    #[test]
    fn tota_tiles_in_region_clamps_query_bounds_near_globe_edge() {
        // Center right at the north pole / date line edge: the query
        // bounds (sw/ne of the requested region) must clamp to ±90/±180
        // rather than panic or wrap, exactly like grids_in_region's
        // min/max clamps. The individual tile rectangles returned are
        // *not* truncated to the clamp (same as grids_in_region returns
        // whole grid squares, not clipped ones) — this just pins that the
        // scan terminates sanely instead of blowing up on out-of-range
        // input.
        let center = Coordinate::new(89.99, 179.99);
        let tiles = tota_tiles_in_region(center, 0.05, 0.05, 1_000);
        assert!(!tiles.is_empty());
        for tile in &tiles {
            assert!(tile.south <= 90.0);
            assert!(tile.west <= 180.0);
        }
    }

    #[test]
    fn case_insensitive_input() {
        // "fn31PR" should yield the same coordinate as "FN31PR".
        let lower = coordinate_from_grid("fn31pr").unwrap();
        let upper = coordinate_from_grid("FN31PR").unwrap();
        assert!(approx_eq(lower.latitude, upper.latitude, 1e-12));
        assert!(approx_eq(lower.longitude, upper.longitude, 1e-12));
    }
}
