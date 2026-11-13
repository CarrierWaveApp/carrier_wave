//! Flat equirectangular share-map rasterizer (tiny-skia).
//!
//! Port of `FlatMapRenderer` (swift/ios/CarrierWave/Views/BragSheet/
//! FlatMapRenderer.swift) + its drawing half (`FlatMapRenderer+Drawing.swift`),
//! replacing iOS CoreGraphics with tiny-skia CPU rasterization. Coastlines come
//! from [`crate::coastline::continents`]; geodesic traces from
//! [`crate::great_circle`].
//!
//! ## Deviation from Swift: antimeridian coastline handling
//!
//! The Swift renderer draws each continent THREE times at longitude shifts
//! `{-360, 0, +360}` (FlatMapRenderer+Drawing.swift:65-89) and lets Core
//! Graphics clip the two off-screen copies. The Phase D plan forbids that
//! trick. Instead we pick, per polygon, the SINGLE shift whose shifted
//! centroid-longitude lies nearest the viewport's longitude center, then split
//! that shifted ring at the antimeridian threshold (raw lon jump > 90°,
//! `ANTIMERIDIAN_THRESHOLD`, FlatMapRenderer+Drawing.swift:16) exactly as the
//! Swift `splitAtAntimeridian` does (FlatMapRenderer+Drawing.swift:180-222).
//! This is behaviorally equivalent for the in-view copy while drawing each
//! polygon once.
//!
//! ## Coordinate convention
//!
//! All input coordinates are `(lat, lon)` in degrees, matching the rest of the
//! domain crate (coastline, great_circle, map_bounds). Screen space is
//! y-down (row 0 at the top) as in CoreGraphics/tiny-skia.

use tiny_skia::{FillRule, LineCap, Mask, PathBuilder, Pixmap, Transform};

use crate::coastline;
use crate::great_circle;
use crate::share_render::primitives::{
    color, draw_center_marker, draw_pin, pin_color_for_count, solid_paint, stroke_line, stroke_polyline,
};
use crate::share_render::themes::{Rgba, ShareTheme};

// ---------------------------------------------------------------------------
// Tunable constants (all captured EXACTLY from the Swift sources)
// ---------------------------------------------------------------------------

/// Max longitude jump between consecutive polygon points before we treat it as
/// an antimeridian crossing and break the segment.
/// Provenance: `FlatMapRenderer.antimeridianThreshold` (FlatMapRenderer+Drawing.swift:16).
const ANTIMERIDIAN_THRESHOLD: f64 = 90.0;

/// Grid line stroke width. Provenance: FlatMapRenderer+Drawing.swift:26.
const GRID_LINE_WIDTH: f32 = 0.5;
/// Coastline edge stroke width. Provenance: FlatMapRenderer+Drawing.swift:250,278.
const COASTLINE_STROKE_WIDTH: f32 = 0.5;
/// Crosshatch line width. Provenance: FlatMapRenderer+Drawing.swift:278.
const HATCH_LINE_WIDTH: f32 = 0.5;
/// Crosshatch diagonal spacing in points. Provenance: FlatMapRenderer+Drawing.swift:276.
const HATCH_SPACING: f32 = 4.0;

/// Trace (geodesic) line stroke width. Provenance: FlatMapRenderer+Drawing.swift:101.
const TRACE_LINE_WIDTH: f32 = 2.0;
/// Trace alpha applied to the theme accent. Provenance: FlatMapRenderer.swift:171,219
/// (`accent.withAlphaComponent(0.5)`).
const TRACE_ALPHA: f32 = 0.5;
/// Number of interpolated segments per geodesic trace.
/// Provenance: FlatMapRenderer+Drawing.swift:305 (`segments: 30`).
const TRACE_SEGMENTS: usize = 30;

// Pin marker + center marker geometry constants and drawing functions live in
// `share_render::primitives` — shared verbatim with the azimuthal renderer.

// ---------------------------------------------------------------------------
// Public interface
// ---------------------------------------------------------------------------

/// Color derivation for a pin. Mirrors the two Swift pin paths:
///
/// - `Count(n)` reproduces the brag-sheet count → color ramp
///   (`BragSheetShareRenderer.pinColor(for:)`,
///   BragSheetShareRenderer+Drawing.swift:148-155) with the traditional pin
///   marker geometry (`drawPinMarker`, :115-146).
/// - `Rgba(color)` reproduces the activation path where the caller supplies an
///   arbitrary color (band/RST color) drawn by `drawRSTPin`
///   (FlatMapRenderer+Drawing.swift:116-138). The geometry is identical; only
///   the color source differs.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum PinColor {
    /// Count-based ramp color.
    Count(u32),
    /// Caller-supplied color.
    Rgba(Rgba),
}

/// A pin to draw on the share map.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SharePin {
    pub lat: f64,
    pub lon: f64,
    pub color: PinColor,
}

/// Everything needed to rasterize a flat share map. The viewport is supplied
/// pre-computed as `center` + spans (Tasks 2/4 derive it via
/// [`crate::map_bounds`]); this keeps the renderer a pure function of its
/// inputs and the theme.
#[derive(Debug, Clone, PartialEq)]
pub struct FlatMapSpec {
    pub width: u32,
    pub height: u32,
    /// Viewport center as `(lat, lon)` in degrees.
    pub center: (f64, f64),
    /// Total latitude span of the viewport in degrees.
    pub lat_span: f64,
    /// Total longitude span of the viewport in degrees.
    pub lon_span: f64,
    pub pins: Vec<SharePin>,
    /// Geodesic traces, each `((from_lat, from_lon), (to_lat, to_lon))`.
    pub traces: Vec<((f64, f64), (f64, f64))>,
    /// Optional operator-QTH center marker as `(lat, lon)`.
    pub center_marker: Option<(f64, f64)>,
}

/// Render the flat equirectangular share map and return PNG bytes.
///
/// Draw order mirrors `renderBase` (FlatMapRenderer.swift:326-350):
/// background → grid → coastlines → traces → pins → center marker.
pub fn render_flat(spec: &FlatMapSpec, theme: &ShareTheme) -> Vec<u8> {
    let width = spec.width.max(1);
    let height = spec.height.max(1);
    let mut pixmap = Pixmap::new(width, height).expect("non-zero pixmap dimensions");

    let vp = Viewport::from_spec(spec);
    let size = (width as f64, height as f64);

    // Background (renderBase fills the whole canvas with theme.ocean).
    pixmap.fill(color(theme.background));

    draw_grid_lines(&mut pixmap, &vp, size, theme);
    draw_coastlines(&mut pixmap, &vp, size, theme);

    // Traces use the accent color at 0.5 alpha (FlatMapRenderer.swift:171).
    let trace_color = theme.accent.with_alpha(TRACE_ALPHA);
    for &(from, to) in &spec.traces {
        draw_geodesic_line(&mut pixmap, &vp, size, from, to, trace_color);
    }

    for pin in &spec.pins {
        let c = match pin.color {
            PinColor::Count(n) => pin_color_for_count(n),
            PinColor::Rgba(c) => c,
        };
        let pt = vp.project(pin.lat, pin.lon, size);
        draw_pin(&mut pixmap, pt, c);
    }

    if let Some((lat, lon)) = spec.center_marker {
        let pt = vp.project(lat, lon, size);
        draw_center_marker(&mut pixmap, pt, theme.accent);
    }

    pixmap.encode_png().expect("tiny-skia PNG encode is infallible for valid pixmaps")
}

// ---------------------------------------------------------------------------
// Viewport
// ---------------------------------------------------------------------------

/// Projects `(lat, lon)` to screen space. Port of `FlatMapRenderer.Viewport`
/// (FlatMapRenderer.swift:107-150). `min/max` bounds are derived from the
/// spec's center + spans so `project`/`project_raw` match the Swift math
/// verbatim.
struct Viewport {
    min_lat: f64,
    max_lat: f64,
    min_lon: f64,
    max_lon: f64,
}

impl Viewport {
    fn from_spec(spec: &FlatMapSpec) -> Self {
        let (center_lat, center_lon) = spec.center;
        let half_lat = spec.lat_span / 2.0;
        let half_lon = spec.lon_span / 2.0;
        Viewport {
            min_lat: center_lat - half_lat,
            max_lat: center_lat + half_lat,
            min_lon: center_lon - half_lon,
            max_lon: center_lon + half_lon,
        }
    }

    /// Center-nearest-wrap projection for single points (trace vertices,
    /// pins, center marker). Port of `Viewport.project` (FlatMapRenderer.swift:113-135).
    fn project(&self, lat: f64, lon: f64, size: (f64, f64)) -> (f32, f32) {
        let center = (self.min_lon + self.max_lon) / 2.0;
        let mut projected_lon = lon;
        let diff = projected_lon - center;
        if diff > 180.0 {
            projected_lon -= 360.0;
        } else if diff < -180.0 {
            projected_lon += 360.0;
        }
        let x_fraction = (projected_lon - self.min_lon) / (self.max_lon - self.min_lon);
        let y_fraction = 1.0 - (lat - self.min_lat) / (self.max_lat - self.min_lat);
        ((x_fraction * size.0) as f32, (y_fraction * size.1) as f32)
    }

    /// Plain linear projection with no longitude wrapping, for polygons.
    /// Port of `Viewport.projectRaw` (FlatMapRenderer.swift:140-149).
    fn project_raw(&self, lat: f64, lon: f64, size: (f64, f64)) -> (f32, f32) {
        let x_fraction = (lon - self.min_lon) / (self.max_lon - self.min_lon);
        let y_fraction = 1.0 - (lat - self.min_lat) / (self.max_lat - self.min_lat);
        ((x_fraction * size.0) as f32, (y_fraction * size.1) as f32)
    }

    fn center_lon(&self) -> f64 {
        (self.min_lon + self.max_lon) / 2.0
    }
}

// ---------------------------------------------------------------------------
// Grid lines
// ---------------------------------------------------------------------------

/// Port of `drawGridLines` (FlatMapRenderer+Drawing.swift:20-54).
fn draw_grid_lines(pixmap: &mut Pixmap, vp: &Viewport, size: (f64, f64), theme: &ShareTheme) {
    let lat_range = vp.max_lat - vp.min_lat;
    let lon_range = vp.max_lon - vp.min_lon;
    // Provenance: FlatMapRenderer+Drawing.swift:30-31.
    let lat_step = if lat_range > 80.0 {
        30.0
    } else if lat_range > 40.0 {
        15.0
    } else {
        10.0
    };
    let lon_step = if lon_range > 120.0 {
        30.0
    } else if lon_range > 60.0 {
        15.0
    } else {
        10.0
    };

    let grid_color = color(theme.grid_line);

    // Horizontal lines at each latitude gridline.
    let first_lat = (vp.min_lat / lat_step).ceil() * lat_step;
    let mut lat = first_lat;
    while lat <= vp.max_lat {
        let pt = vp.project(lat, vp.min_lon, size);
        stroke_line(
            pixmap,
            (0.0, pt.1),
            (size.0 as f32, pt.1),
            grid_color,
            GRID_LINE_WIDTH,
            LineCap::Butt,
        );
        lat += lat_step;
    }

    // Vertical lines at each longitude gridline.
    let first_lon = (vp.min_lon / lon_step).ceil() * lon_step;
    let mut lon = first_lon;
    while lon <= vp.max_lon {
        let pt = vp.project(0.0, lon, size);
        stroke_line(
            pixmap,
            (pt.0, 0.0),
            (pt.0, size.1 as f32),
            grid_color,
            GRID_LINE_WIDTH,
            LineCap::Butt,
        );
        lon += lon_step;
    }
}

// ---------------------------------------------------------------------------
// Coastlines
// ---------------------------------------------------------------------------

/// Port of `drawCoastlines` (FlatMapRenderer+Drawing.swift:67-89), but drawing
/// each polygon ONCE at its viewport-nearest ±360 shift (see module docs)
/// instead of triple-drawing at `{-360, 0, +360}`.
fn draw_coastlines(pixmap: &mut Pixmap, vp: &Viewport, size: (f64, f64), theme: &ShareTheme) {
    for continent in coastline::continents() {
        if continent.len() < 3 {
            continue;
        }
        let shift = best_shift(continent, vp.center_lon());
        let shifted: Vec<(f64, f64)> =
            continent.iter().map(|&(lat, lon)| (lat, lon + shift)).collect();
        let segments = split_at_antimeridian(&shifted, vp, size);
        draw_segments(pixmap, &segments, theme);
    }
}

/// Pick the longitude shift from `{-360, 0, +360}` whose shifted centroid
/// longitude lies nearest the viewport's longitude center. Replaces the Swift
/// triple-draw; the chosen copy is the one that would have rendered in-view.
fn best_shift(polygon: &[(f64, f64)], center_lon: f64) -> f64 {
    let mean_lon: f64 = polygon.iter().map(|&(_, lon)| lon).sum::<f64>() / polygon.len() as f64;
    [-360.0_f64, 0.0, 360.0]
        .into_iter()
        .min_by(|&a, &b| {
            let da = (mean_lon + a - center_lon).abs();
            let db = (mean_lon + b - center_lon).abs();
            da.partial_cmp(&db).unwrap_or(std::cmp::Ordering::Equal)
        })
        .unwrap_or(0.0)
}

/// Split a polygon into screen-space segments, breaking at antimeridian
/// crossings using `project_raw`. Port of `splitAtAntimeridian`
/// (FlatMapRenderer+Drawing.swift:180-222).
fn split_at_antimeridian(
    polygon: &[(f64, f64)],
    vp: &Viewport,
    size: (f64, f64),
) -> Vec<Vec<(f32, f32)>> {
    let mut segments: Vec<Vec<(f32, f32)>> = Vec::new();
    let mut current: Vec<(f32, f32)> = Vec::new();

    for idx in 0..polygon.len() {
        let (lat, lon) = polygon[idx];
        let screen_pt = vp.project_raw(lat, lon, size);

        if idx > 0 {
            let (_, prev_lon) = polygon[idx - 1];
            if (lon - prev_lon).abs() > ANTIMERIDIAN_THRESHOLD {
                if current.len() >= 2 {
                    segments.push(std::mem::take(&mut current));
                } else {
                    current.clear();
                }
                current.push(screen_pt);
                continue;
            }
        }
        current.push(screen_pt);
    }

    // Close back to first point if no antimeridian crossing between last/first.
    if let (Some(&(first_lat, first_lon)), Some(&(_, last_lon))) =
        (polygon.first(), polygon.last())
    {
        if (first_lon - last_lon).abs() <= ANTIMERIDIAN_THRESHOLD && !current.is_empty() {
            current.push(vp.project_raw(first_lat, first_lon, size));
        }
    }

    if current.len() >= 2 {
        segments.push(current);
    }
    segments
}

/// Fill + crosshatch + stroke each segment. Port of `drawSegments`
/// (FlatMapRenderer+Drawing.swift:225-259).
fn draw_segments(pixmap: &mut Pixmap, segments: &[Vec<(f32, f32)>], theme: &ShareTheme) {
    let fill_color = color(theme.land_fill);
    let hatch_color = color(theme.land_hatch);

    for segment in segments {
        if segment.len() < 3 {
            continue;
        }
        let Some(path) = build_closed_path(segment) else {
            continue;
        };

        // Fill land.
        let paint = solid_paint(fill_color);
        pixmap.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), None);

        // Crosshatch clipped to the land polygon.
        let bounds = path_bounds(segment);
        let (w, h) = (pixmap.width(), pixmap.height());
        let mut mask = Mask::new(w, h).expect("mask dims match pixmap");
        mask.fill_path(&path, FillRule::Winding, true, Transform::identity());
        draw_hatch_lines(pixmap, bounds, hatch_color, &mask);
    }

    // Stroke coastline edges (segment.count >= 2).
    let stroke_color = color(theme.land_stroke);
    for segment in segments {
        if segment.len() < 2 {
            continue;
        }
        stroke_polyline(pixmap, segment, stroke_color, COASTLINE_STROKE_WIDTH, LineCap::Butt, None);
    }
}

/// Diagonal crosshatch across a bounding box. Port of `drawHatchLines`
/// (FlatMapRenderer+Drawing.swift:272-293). Lines run top-left → bottom-right.
fn draw_hatch_lines(
    pixmap: &mut Pixmap,
    bounds: (f32, f32, f32, f32),
    hatch_color: tiny_skia::Color,
    mask: &Mask,
) {
    let (min_x, min_y, width, height) = bounds;
    let max_dim = width + height;
    let mut offset = 0.0_f32;
    while offset < max_dim {
        let x1 = min_x + offset;
        let y1 = min_y;
        let x2 = min_x;
        let y2 = min_y + offset;
        // Each hatch line is clipped to the land polygon via `mask`, matching
        // the Swift `ctx.clip()` around the hatch pass (FlatMapRenderer+Drawing.swift:242-243).
        stroke_polyline(
            pixmap,
            &[(x1, y1), (x2, y2)],
            hatch_color,
            HATCH_LINE_WIDTH,
            LineCap::Butt,
            Some(mask),
        );
        offset += HATCH_SPACING;
    }
}

// ---------------------------------------------------------------------------
// Traces
// ---------------------------------------------------------------------------

/// Draw one geodesic trace, split at the antimeridian. Port of
/// `drawGeodesicLine` (FlatMapRenderer+Drawing.swift:299-322) using the shared
/// [`crate::great_circle`] path (already antimeridian-split).
fn draw_geodesic_line(
    pixmap: &mut Pixmap,
    vp: &Viewport,
    size: (f64, f64),
    from: (f64, f64),
    to: (f64, f64),
    line_color: Rgba,
) {
    let c = color(line_color);
    let segments = great_circle::great_circle_segments(from, to, TRACE_SEGMENTS);
    for segment in segments {
        if segment.len() < 2 {
            continue;
        }
        let pts: Vec<(f32, f32)> =
            segment.iter().map(|&(lat, lon)| vp.project(lat, lon, size)).collect();
        stroke_polyline(pixmap, &pts, c, TRACE_LINE_WIDTH, LineCap::Round, None);
    }
}

// ---------------------------------------------------------------------------
// Pins + center marker
// ---------------------------------------------------------------------------
//
// Pin/center-marker geometry + shared tiny-skia primitives (solid_paint,
// color, stroke_line, stroke_polyline, fill_circle) live in
// `share_render::primitives` (shared with the azimuthal renderer).

/// Build a closed polygon path from screen points.
fn build_closed_path(points: &[(f32, f32)]) -> Option<tiny_skia::Path> {
    if points.len() < 3 {
        return None;
    }
    let mut pb = PathBuilder::new();
    pb.move_to(points[0].0, points[0].1);
    for &(x, y) in &points[1..] {
        pb.line_to(x, y);
    }
    pb.close();
    pb.finish()
}

/// Bounding box `(min_x, min_y, width, height)` of a screen-point ring.
fn path_bounds(points: &[(f32, f32)]) -> (f32, f32, f32, f32) {
    let mut min_x = f32::INFINITY;
    let mut min_y = f32::INFINITY;
    let mut max_x = f32::NEG_INFINITY;
    let mut max_y = f32::NEG_INFINITY;
    for &(x, y) in points {
        min_x = min_x.min(x);
        min_y = min_y.min(y);
        max_x = max_x.max(x);
        max_y = max_y.max(y);
    }
    (min_x, min_y, max_x - min_x, max_y - min_y)
}
