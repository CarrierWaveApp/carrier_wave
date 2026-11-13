//! SOTA activation-zone computation from open DEM data.
//!
//! Recreates the technique used by activation.zone (N6ARA) without depending on
//! its API: fetch AWS Terrain Tiles (Terrarium PNG-encoded elevation — free,
//! global, with USGS 3DEP 10 m detail in the US), then apply the official SOTA
//! rule — the activation zone is the connected terrain within 25 vertical
//! metres of the summit. Concretely we flood-fill the DEM from the summit pixel
//! including every connected pixel with `elevation >= summit_elevation - 25 m`,
//! trace the boundary of that region, and emit a lon/lat polygon.
//!
//! Pure helpers (tile math, elevation decode, flood fill, contour, simplify)
//! are unit-tested; only tile fetching is async/network.

use std::collections::{HashMap, VecDeque};
use std::error::Error;
use std::f64::consts::PI;

type BoxError = Box<dyn Error + Send + Sync>;

/// Default Terrarium tile endpoint (AWS Open Data, no auth).
pub const DEFAULT_TILE_URL: &str = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium";

/// Zoom level: 13 ≈ 19 m/px at the equator — enough detail for the small
/// terrain features that bound an activation zone, while keeping the working
/// window to a 3×3 tile block.
const ZOOM: u32 = 13;
const TILE_PX: usize = 256;
/// The "25 vertical metres below the summit" rule.
const DROP_METRES: f32 = 25.0;
/// Abort if the fill balloons past this (DEM void / flat plateau) — the result
/// would be meaningless as an activation zone.
const MAX_FILL_PIXELS: usize = 120_000;
/// Sentinel for pixels with no DEM coverage (acts as a hard fill barrier).
const NODATA: f32 = f32::MIN;

// MARK: - Public API

/// Compute the activation-zone polygon rings (`[[lon, lat], ...]` per ring,
/// largest ring first) for a summit, or `None` if no usable zone was found.
pub async fn compute_activation_zone(
    client: &reqwest::Client,
    lat: f64,
    lon: f64,
    tile_base_url: &str,
) -> Result<Option<Vec<Vec<[f64; 2]>>>, BoxError> {
    let (gx, gy) = lonlat_to_px(lon, lat, ZOOM);
    let center_tx = (gx / TILE_PX as f64).floor() as i64;
    let center_ty = (gy / TILE_PX as f64).floor() as i64;

    // Assemble a 3×3 tile block so the summit is never against an edge.
    let width = TILE_PX * 3;
    let height = TILE_PX * 3;
    let origin_gx = (center_tx - 1) * TILE_PX as i64;
    let origin_gy = (center_ty - 1) * TILE_PX as i64;
    let mut grid = vec![NODATA; width * height];
    let max_tile = (1i64 << ZOOM) - 1;

    for dy in -1..=1i64 {
        for dx in -1..=1i64 {
            let tx = center_tx + dx;
            let ty = center_ty + dy;
            if tx < 0 || ty < 0 || tx > max_tile || ty > max_tile {
                continue; // out of range — leave as NODATA barrier
            }
            let url = format!("{}/{}/{}/{}.png", tile_base_url, ZOOM, tx, ty);
            let bytes = match fetch_tile(client, &url).await {
                Ok(bytes) => bytes,
                Err(err) => {
                    if dx == 0 && dy == 0 {
                        return Err(err); // center tile is required
                    }
                    continue;
                }
            };
            let tile = decode_terrarium(&bytes)?;
            blit(&mut grid, width, &tile, (dx + 1) as usize * TILE_PX, (dy + 1) as usize * TILE_PX);
        }
    }

    let sx = (gx - origin_gx as f64).round() as i64;
    let sy = (gy - origin_gy as f64).round() as i64;
    Ok(zone_rings_from_grid(&grid, width, height, sx, sy, origin_gx, origin_gy))
}

// MARK: - Tile fetching

async fn fetch_tile(client: &reqwest::Client, url: &str) -> Result<Vec<u8>, BoxError> {
    let resp = client.get(url).send().await?.error_for_status()?;
    Ok(resp.bytes().await?.to_vec())
}

// MARK: - DEM decode

/// Terrarium decode: `elevation_m = R*256 + G + B/256 - 32768`.
fn terrarium_elev(red: u8, green: u8, blue: u8) -> f32 {
    red as f32 * 256.0 + green as f32 + blue as f32 / 256.0 - 32768.0
}

/// Decode a Terrarium PNG tile into a row-major elevation grid.
fn decode_terrarium(bytes: &[u8]) -> Result<Vec<f32>, BoxError> {
    let decoder = png::Decoder::new(bytes);
    let mut reader = decoder.read_info()?;
    let mut buf = vec![0u8; reader.output_buffer_size()];
    let info = reader.next_frame(&mut buf)?;
    if info.bit_depth != png::BitDepth::Eight {
        return Err("unexpected Terrarium bit depth".into());
    }
    // CAR-337 / CAR-340: `blit` indexes the decoded tile as a fixed TILE_PX×TILE_PX
    // grid. A tile that isn't exactly that size (truncated/hostile/misrouted
    // response) would panic out of bounds, killing the compute task and orphaning
    // the summit's 'pending' sentinel. Reject wrong dimensions as a normal error.
    if info.width as usize != TILE_PX || info.height as usize != TILE_PX {
        return Err("unexpected Terrarium tile dimensions".into());
    }
    let channels = info.color_type.samples();
    if channels < 3 {
        return Err("unexpected Terrarium channel count".into());
    }
    let data = &buf[..info.buffer_size()];
    Ok(data
        .chunks_exact(channels)
        .map(|px| terrarium_elev(px[0], px[1], px[2]))
        .collect())
}

fn blit(grid: &mut [f32], grid_width: usize, tile: &[f32], col0: usize, row0: usize) {
    for row in 0..TILE_PX {
        for col in 0..TILE_PX {
            let value = tile[row * TILE_PX + col];
            grid[(row0 + row) * grid_width + (col0 + col)] = value;
        }
    }
}

// MARK: - Zone extraction

fn zone_rings_from_grid(
    grid: &[f32],
    width: usize,
    height: usize,
    sx: i64,
    sy: i64,
    origin_gx: i64,
    origin_gy: i64,
) -> Option<Vec<Vec<[f64; 2]>>> {
    let (peak_idx, peak_elev) = local_peak(grid, width, height, sx, sy)?;
    let threshold = peak_elev - DROP_METRES;
    let mask = flood_fill(grid, width, height, peak_idx, threshold)?;

    let mut rings = extract_rings(&mask, width, height);
    if rings.is_empty() {
        return None;
    }
    // Largest-area ring is the exterior; smaller ones are holes.
    // CAR-337 / CAR-340: use a total order — a NaN area (degenerate geometry) would
    // make partial_cmp().unwrap() panic and orphan the summit's 'pending' sentinel.
    rings.sort_by(|lhs, rhs| {
        ring_area(rhs)
            .partial_cmp(&ring_area(lhs))
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let geo: Vec<Vec<[f64; 2]>> = rings
        .iter()
        .map(|ring| {
            simplify(ring, 1.2)
                .iter()
                .map(|&(cx, cy)| {
                    let (lon, lat) =
                        px_to_lonlat(origin_gx as f64 + cx, origin_gy as f64 + cy, ZOOM);
                    [lon, lat]
                })
                .collect()
        })
        .filter(|ring: &Vec<[f64; 2]>| ring.len() >= 4)
        .collect();

    if geo.is_empty() {
        None
    } else {
        Some(geo)
    }
}

/// Find the highest DEM pixel within a small radius of the nominal summit pixel
/// (corrects minor coordinate offset). Returns its index and elevation.
fn local_peak(grid: &[f32], width: usize, height: usize, sx: i64, sy: i64) -> Option<(usize, f32)> {
    let radius = 3i64;
    let mut best: Option<(usize, f32)> = None;
    for dy in -radius..=radius {
        for dx in -radius..=radius {
            let col = sx + dx;
            let row = sy + dy;
            if col < 0 || row < 0 || col >= width as i64 || row >= height as i64 {
                continue;
            }
            let idx = row as usize * width + col as usize;
            let elev = grid[idx];
            if elev <= NODATA {
                continue;
            }
            if best.map_or(true, |(_, best_elev)| elev > best_elev) {
                best = Some((idx, elev));
            }
        }
    }
    best
}

/// 8-connected flood fill of pixels with `elevation >= threshold`, seeded at the
/// summit. Returns the filled mask, or `None` if the fill exceeds the cap.
fn flood_fill(
    grid: &[f32],
    width: usize,
    height: usize,
    seed: usize,
    threshold: f32,
) -> Option<Vec<bool>> {
    let mut mask = vec![false; width * height];
    let mut queue = VecDeque::new();
    mask[seed] = true;
    queue.push_back(seed);
    let mut count = 1usize;

    while let Some(idx) = queue.pop_front() {
        let col = (idx % width) as i64;
        let row = (idx / width) as i64;
        for dy in -1..=1i64 {
            for dx in -1..=1i64 {
                if dx == 0 && dy == 0 {
                    continue;
                }
                let ncol = col + dx;
                let nrow = row + dy;
                if ncol < 0 || nrow < 0 || ncol >= width as i64 || nrow >= height as i64 {
                    continue;
                }
                let nidx = nrow as usize * width + ncol as usize;
                if mask[nidx] {
                    continue;
                }
                let elev = grid[nidx];
                if elev <= NODATA || elev < threshold {
                    continue;
                }
                mask[nidx] = true;
                count += 1;
                if count > MAX_FILL_PIXELS {
                    return None;
                }
                queue.push_back(nidx);
            }
        }
    }
    Some(mask)
}

// MARK: - Contour extraction (edge stitching, interior-on-left)

/// Trace the boundary of a filled mask into one or more closed rings of lattice
/// corner points. Each boundary cell-edge facing an empty neighbour is emitted
/// as a directed segment (filled cell on the left), then segments are stitched
/// into rings.
fn extract_rings(mask: &[bool], width: usize, height: usize) -> Vec<Vec<(f64, f64)>> {
    let filled = |col: i64, row: i64| -> bool {
        col >= 0 && row >= 0 && col < width as i64 && row < height as i64 && mask[row as usize * width + col as usize]
    };

    // from-corner -> list of to-corners (multimap handles diagonal pinches).
    let mut edges: HashMap<(i64, i64), Vec<(i64, i64)>> = HashMap::new();
    let mut push = |from: (i64, i64), to: (i64, i64)| edges.entry(from).or_default().push(to);

    for row in 0..height as i64 {
        for col in 0..width as i64 {
            if !filled(col, row) {
                continue;
            }
            // Directed so the filled cell stays on the left (image coords, y down).
            if !filled(col, row - 1) {
                push((col + 1, row), (col, row)); // top
            }
            if !filled(col - 1, row) {
                push((col, row), (col, row + 1)); // left
            }
            if !filled(col, row + 1) {
                push((col, row + 1), (col + 1, row + 1)); // bottom
            }
            if !filled(col + 1, row) {
                push((col + 1, row + 1), (col + 1, row)); // right
            }
        }
    }

    let mut rings = Vec::new();
    let mut starts: Vec<(i64, i64)> = edges.keys().copied().collect();
    starts.sort();

    for start in starts {
        while edges.get(&start).map_or(false, |tos| !tos.is_empty()) {
            let mut ring = Vec::new();
            let mut current = start;
            loop {
                let Some(tos) = edges.get_mut(&current) else {
                    break;
                };
                let Some(next) = tos.pop() else {
                    break;
                };
                ring.push((current.0 as f64, current.1 as f64));
                current = next;
                if current == start {
                    ring.push((current.0 as f64, current.1 as f64));
                    break;
                }
            }
            if ring.len() >= 4 {
                rings.push(ring);
            }
        }
    }
    rings
}

/// Shoelace area (absolute) of a closed ring.
fn ring_area(ring: &[(f64, f64)]) -> f64 {
    if ring.len() < 3 {
        return 0.0;
    }
    let mut sum = 0.0;
    for window in ring.windows(2) {
        let (x0, y0) = window[0];
        let (x1, y1) = window[1];
        sum += x0 * y1 - x1 * y0;
    }
    (sum / 2.0).abs()
}

// MARK: - Douglas–Peucker simplification (iterative)

fn simplify(points: &[(f64, f64)], tolerance: f64) -> Vec<(f64, f64)> {
    if points.len() <= 2 {
        return points.to_vec();
    }
    let count = points.len();
    let mut keep = vec![false; count];
    keep[0] = true;
    keep[count - 1] = true;
    let mut stack = vec![(0usize, count - 1)];

    while let Some((start, end)) = stack.pop() {
        let mut max_dist = 0.0;
        let mut index = start;
        for i in (start + 1)..end {
            let dist = perpendicular_distance(points[i], points[start], points[end]);
            if dist > max_dist {
                max_dist = dist;
                index = i;
            }
        }
        if max_dist > tolerance {
            keep[index] = true;
            stack.push((start, index));
            stack.push((index, end));
        }
    }

    points
        .iter()
        .enumerate()
        .filter_map(|(i, &pt)| if keep[i] { Some(pt) } else { None })
        .collect()
}

fn perpendicular_distance(pt: (f64, f64), line_a: (f64, f64), line_b: (f64, f64)) -> f64 {
    let (px, py) = pt;
    let (ax, ay) = line_a;
    let (bx, by) = line_b;
    let dx = bx - ax;
    let dy = by - ay;
    let denom = (dx * dx + dy * dy).sqrt();
    if denom == 0.0 {
        return ((px - ax).powi(2) + (py - ay).powi(2)).sqrt();
    }
    ((dy * px - dx * py + bx * ay - by * ax).abs()) / denom
}

// MARK: - Web-Mercator slippy-tile math

fn world_size(zoom: u32) -> f64 {
    TILE_PX as f64 * (1u64 << zoom) as f64
}

/// Lon/lat (degrees) → global pixel coordinates at `zoom`.
fn lonlat_to_px(lon: f64, lat: f64, zoom: u32) -> (f64, f64) {
    let size = world_size(zoom);
    let x = (lon + 180.0) / 360.0 * size;
    let siny = (lat * PI / 180.0).sin().clamp(-0.9999, 0.9999);
    let y = (0.5 - ((1.0 + siny) / (1.0 - siny)).ln() / (4.0 * PI)) * size;
    (x, y)
}

/// Global pixel coordinates → lon/lat (degrees) at `zoom`.
fn px_to_lonlat(x: f64, y: f64, zoom: u32) -> (f64, f64) {
    let size = world_size(zoom);
    let lon = x / size * 360.0 - 180.0;
    let n = PI - 2.0 * PI * y / size;
    let lat = n.sinh().atan() * 180.0 / PI;
    (lon, lat)
}

/// Build a GeoJSON `Polygon` value from rings (`[[lon,lat],...]`), or `null`.
pub fn rings_to_geojson(rings: &[Vec<[f64; 2]>]) -> serde_json::Value {
    serde_json::json!({
        "type": "Polygon",
        "coordinates": rings,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mercator_round_trip() {
        for &(lon, lat) in &[(-120.5, 38.7), (-71.1, 44.27), (10.0, 60.0)] {
            let (px, py) = lonlat_to_px(lon, lat, ZOOM);
            let (rlon, rlat) = px_to_lonlat(px, py, ZOOM);
            assert!((lon - rlon).abs() < 1e-6, "lon {} vs {}", lon, rlon);
            assert!((lat - rlat).abs() < 1e-6, "lat {} vs {}", lat, rlat);
        }
    }

    #[test]
    fn terrarium_decode_formula() {
        // 32768 offset → 0 m at (128,0,0).
        assert!((terrarium_elev(128, 0, 0) - 0.0).abs() < 1e-3);
        // Sea level region.
        assert!((terrarium_elev(127, 255, 0) - (-1.0)).abs() < 1e-3);
    }

    #[test]
    fn flood_fill_respects_threshold() {
        // 5×5 grid: a central plateau at 100, surroundings at 0.
        let width = 5;
        let height = 5;
        let mut grid = vec![0.0f32; width * height];
        for row in 1..4 {
            for col in 1..4 {
                grid[row * width + col] = 100.0;
            }
        }
        let seed = 2 * width + 2;
        let mask = flood_fill(&grid, width, height, seed, 100.0 - DROP_METRES).unwrap();
        let count = mask.iter().filter(|&&on| on).count();
        assert_eq!(count, 9, "only the 3×3 plateau should fill");
    }

    #[test]
    fn contour_of_rectangle_closes() {
        // 4×4 grid with a 2×2 filled block at (1,1)-(2,2).
        let width = 4;
        let height = 4;
        let mut mask = vec![false; width * height];
        for &(col, row) in &[(1, 1), (2, 1), (1, 2), (2, 2)] {
            mask[row * width + col] = true;
        }
        let rings = extract_rings(&mask, width, height);
        assert_eq!(rings.len(), 1);
        let ring = &rings[0];
        // Closed ring (first == last).
        assert_eq!(ring.first(), ring.last());
        // A 2×2 block has a perimeter enclosing area 4 in lattice units.
        assert!((ring_area(ring) - 4.0).abs() < 1e-6, "area = {}", ring_area(ring));
    }

    #[test]
    fn simplify_collinear_points() {
        let line = vec![(0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (3.0, 0.0)];
        let out = simplify(&line, 0.5);
        assert_eq!(out, vec![(0.0, 0.0), (3.0, 0.0)]);
    }
}
