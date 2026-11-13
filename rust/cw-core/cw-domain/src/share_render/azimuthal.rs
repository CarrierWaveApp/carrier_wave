//! Azimuthal equidistant share-map rasterizer (tiny-skia).
//!
//! Port of `AzimuthalMapRenderer` (swift/ios/CarrierWave/Views/BragSheet/
//! AzimuthalMapRenderer.swift), replacing iOS CoreGraphics with tiny-skia CPU
//! rasterization. Projection math comes from [`crate::azimuthal::AzimuthalProjection`];
//! coastlines from [`crate::coastline::continents`]. Pin marker + center marker
//! geometry is shared with the flat renderer via [`super::primitives`] (identical
//! constants on both Swift sides).
//!
//! ## Ring labels are NOT rasterized
//!
//! Swift's `drawRingLabel` (AzimuthalMapRenderer.swift:247-279) draws "5k mi"
//! captions directly into the CoreGraphics context using `UIFont.systemFont`.
//! The Phase D plan explicitly keeps text out of the Rust raster (no font
//! dependency in cw-domain) — instead [`render_azimuthal`] returns each ring's
//! formatted text plus an anchor point as a [`RingLabel`], and each platform
//! overlays the text natively at that point. See "Judgment calls" below for how
//! the anchor coordinate is derived without Swift's `NSString` font metrics.
//!
//! ## Coordinate convention
//!
//! Input coordinates are `(lat, lon)` in degrees. Screen space is y-down (row 0
//! at the top), matching CoreGraphics/tiny-skia and the flat renderer.

use tiny_skia::{LineCap, LineJoin, PathBuilder, Pixmap, Stroke, StrokeDash, Transform};

use crate::azimuthal::AzimuthalProjection;
use crate::coastline;
use crate::share_render::primitives::{
    color, draw_center_marker, draw_pin, fill_circle, pin_color_for_count, solid_paint, stroke_polyline,
};
use crate::share_render::themes::{Rgba, ShareTheme};

// ---------------------------------------------------------------------------
// Tunable constants (all captured EXACTLY from AzimuthalMapRenderer.swift)
// ---------------------------------------------------------------------------

/// Padding between the canvas edge and the map circle. Provenance: `mapPadding` (:95).
const MAP_PADDING: f32 = 8.0;

/// Coastline stroke width. Provenance: :158 (`ctx.setLineWidth(0.5)` in `drawCoastlines`).
const COASTLINE_STROKE_WIDTH: f32 = 0.5;
/// Coastline stroke alpha (applied to white). Provenance: :155-157
/// (`UIColor.white.withAlphaComponent(0.15)`).
const COASTLINE_ALPHA: f32 = 0.15;

/// Range ring stroke width. Provenance: :210 (`ctx.setLineWidth(0.5)` in `drawRangeRings`).
const RING_STROKE_WIDTH: f32 = 0.5;
/// Range ring stroke alpha (applied to white). Provenance: :207-209
/// (`UIColor.white.withAlphaComponent(0.08)`).
const RING_ALPHA: f32 = 0.08;
/// Range ring dash pattern (on, off) in points. Provenance: :219 (`dashLengths = [4, 4]`).
const RING_DASH: [f32; 2] = [4.0, 4.0];
/// Distance between successive range rings, in km. Provenance: :215 (`ringDistanceKm = 5_000`).
const RING_DISTANCE_KM: f64 = 5_000.0;
/// Earth half-circumference in km used for the ring-radius fraction. Provenance:
/// :216 (`earthHalfCircumKm: Double = 20_037`) — a LOCAL constant in
/// `drawRangeRings`, distinct from [`crate::azimuthal::EARTH_HALF_CIRCUMFERENCE_KM`]
/// (20_020, used elsewhere for `max_distance_km` defaults). Kept separate here to
/// match the Swift ring-radius math exactly.
const RING_EARTH_HALF_CIRCUM_KM: f64 = 20_037.0;
/// km → statute-mile conversion factor used by `drawRingLabel`. Provenance: :252.
const KM_TO_MILES: f64 = 0.621_371;

/// Trace (geodesic) line stroke width. Provenance: :292 (`ctx.setLineWidth(2.5)`).
const TRACE_LINE_WIDTH: f32 = 2.5;
/// Trace stroke alpha (applied to white). Provenance: :289-291
/// (`UIColor.white.withAlphaComponent(0.5)`).
const TRACE_ALPHA: f32 = 0.5;
/// Number of interpolated segments per geodesic trace. Provenance: :301 (`segments: 40`).
const TRACE_SEGMENTS: usize = 40;

// ---------------------------------------------------------------------------
// Public interface
// ---------------------------------------------------------------------------

/// Re-exported so callers only need `share_render::{azimuthal, flat}` symbols,
/// not cross-module imports for an identical enum.
pub use crate::share_render::flat::PinColor;

/// A pin to draw on the azimuthal map, in the same two color modes as
/// [`super::flat::SharePin`] (kept as a separate type since the azimuthal spec
/// carries no antimeridian/viewport fields).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AzimuthalPin {
    pub lat: f64,
    pub lon: f64,
    pub color: PinColor,
}

/// A ring-label text anchor. Mirrors what Swift's `drawRingLabel`
/// (AzimuthalMapRenderer.swift:247-279) would have drawn, minus rasterized
/// text — `x`/`y` are a screen-space anchor point in the same coordinate
/// system as the PNG; `text` is the exact "5k mi"/"250 mi" caption string.
///
/// Anchor-edge semantics (so platforms overlay text identically to Swift's
/// `nsText.draw(at:)`, AzimuthalMapRenderer.swift:268-278): `x` is the
/// horizontal CENTER of the label; the text renders ABOVE `y` — `y` is the
/// ring's TOP point (`center.y - ringRadius`). Platforms center the text
/// horizontally on `x` and place the text's BOTTOM edge just above `y` (Swift
/// leaves a 1pt gap: `labelPoint.y = center.y - ringRadius - textHeight - 1`).
#[derive(Debug, Clone, PartialEq)]
pub struct RingLabel {
    pub x: f32,
    pub y: f32,
    pub text: String,
}

/// Everything needed to rasterize an azimuthal share map.
#[derive(Debug, Clone, PartialEq)]
pub struct AzimuthalMapSpec {
    pub width: u32,
    pub height: u32,
    /// Projection center (operator QTH) as `(lat, lon)` in degrees.
    pub center: (f64, f64),
    pub pins: Vec<AzimuthalPin>,
    /// Geodesic traces, each `((from_lat, from_lon), (to_lat, to_lon))`.
    pub traces: Vec<((f64, f64), (f64, f64))>,
    /// Optional operator-QTH center marker as `(lat, lon)`. Swift always draws
    /// this at the projection center (:142 `drawCenterMarker(ctx:center:)`);
    /// modeled as optional here for spec symmetry with the flat renderer, but
    /// callers should normally pass `Some(spec.center)`.
    pub center_marker: Option<(f64, f64)>,
}

/// Render the azimuthal equidistant share map. Returns PNG bytes plus ring
/// label anchors (see module docs — no text is rasterized).
///
/// Draw order mirrors `renderBase` (AzimuthalMapRenderer.swift:99-147):
/// background → ocean circle → coastlines → range rings (+ labels) → traces →
/// pins → center marker.
pub fn render_azimuthal(spec: &AzimuthalMapSpec, theme: &ShareTheme) -> (Vec<u8>, Vec<RingLabel>) {
    let width = spec.width.max(1);
    let height = spec.height.max(1);
    let mut pixmap = Pixmap::new(width, height).expect("non-zero pixmap dimensions");

    let proj = AzimuthalProjection::new(spec.center.0, spec.center.1);
    let map_radius = (width.min(height) as f32) / 2.0 - MAP_PADDING;
    let center = (width as f32 / 2.0, height as f32 / 2.0);

    // Background fill (renderBase :116-117).
    pixmap.fill(color(theme.background));

    // Ocean circle (renderBase :122-128).
    fill_circle(&mut pixmap, center, map_radius, color(theme.ocean));

    draw_coastlines(&mut pixmap, &proj, center, map_radius);
    let labels = draw_range_rings(&mut pixmap, center, map_radius);

    let trace_color = Rgba::new(1.0, 1.0, 1.0, 1.0).with_alpha(TRACE_ALPHA);
    for &(from, to) in &spec.traces {
        draw_trace_line(&mut pixmap, &proj, center, map_radius, from, to, trace_color);
    }

    for pin in &spec.pins {
        let c = match pin.color {
            PinColor::Count(n) => pin_color_for_count(n),
            PinColor::Rgba(c) => c,
        };
        if let Some(pt) = screen_point(&proj, center, map_radius, pin.lat, pin.lon) {
            draw_pin(&mut pixmap, pt, c);
        }
    }

    // Swift always draws the center marker unconditionally at the projection
    // center (`drawCenterMarker(ctx:center:)`, :142) — it never re-projects a
    // coordinate for it. `spec.center_marker` is normally `Some(spec.center)`,
    // which trivially projects to the origin; `screen_point` only returns
    // `None` for the exact antipode of `spec.center`, so the fallback to the
    // geometric `center` below only matters for that degenerate case (or a
    // caller passing an unrelated marker coordinate).
    if let Some((lat, lon)) = spec.center_marker {
        let pt = screen_point(&proj, center, map_radius, lat, lon).unwrap_or(center);
        draw_center_marker(&mut pixmap, pt, theme.accent);
    }

    let png = pixmap.encode_png().expect("tiny-skia PNG encode is infallible for valid pixmaps");
    (png, labels)
}

// ---------------------------------------------------------------------------
// Projection helper
// ---------------------------------------------------------------------------

/// Project `(lat, lon)` to a screen point, or `None` if the point falls
/// outside the projectable range (the exact antipode — see
/// `AzimuthalProjection::project`). Port of `MapContext.screenPoint`
/// (AzimuthalMapRenderer.swift:78-86).
fn screen_point(
    proj: &AzimuthalProjection,
    center: (f32, f32),
    radius: f32,
    lat: f64,
    lon: f64,
) -> Option<(f32, f32)> {
    let (x, y) = proj.project(lat, lon)?;
    let sx = center.0 + (x as f32) * radius;
    // Flip y: projection has y-up, screen has y-down.
    let sy = center.1 - (y as f32) * radius;
    Some((sx, sy))
}

// ---------------------------------------------------------------------------
// Coastlines
// ---------------------------------------------------------------------------

/// Port of `drawCoastlines` (AzimuthalMapRenderer.swift:151-199). Unlike the
/// flat renderer, azimuthal coastlines are stroked only (no fill/crosshatch —
/// the Swift source doesn't fill land on this projection) and points beyond
/// the projectable range simply break the current polyline, exactly mirroring
/// Swift's `guard let sp = map.screenPoint(...) else { if started { strokePath() } }`.
fn draw_coastlines(pixmap: &mut Pixmap, proj: &AzimuthalProjection, center: (f32, f32), radius: f32) {
    let stroke_color = color(Rgba::new(1.0, 1.0, 1.0, 1.0).with_alpha(COASTLINE_ALPHA));

    for continent in coastline::continents() {
        if continent.len() < 3 {
            continue;
        }

        let mut current: Vec<(f32, f32)> = Vec::new();
        for &(lat, lon) in continent {
            match screen_point(proj, center, radius, lat, lon) {
                Some(pt) => current.push(pt),
                None => {
                    // Point off the projection — break the path (:171-177).
                    flush_polyline(pixmap, &mut current, stroke_color);
                }
            }
        }

        // Close the polygon back to first point (:188-194).
        if !current.is_empty() {
            if let Some(&(first_lat, first_lon)) = continent.first() {
                if let Some(first_pt) = screen_point(proj, center, radius, first_lat, first_lon) {
                    current.push(first_pt);
                }
            }
        }
        flush_polyline(pixmap, &mut current, stroke_color);
    }
}

/// Stroke and clear an accumulated polyline buffer (mirrors the repeated
/// Swift `ctx.strokePath(); started = false` pattern).
fn flush_polyline(pixmap: &mut Pixmap, current: &mut Vec<(f32, f32)>, stroke_color: tiny_skia::Color) {
    if current.len() >= 2 {
        stroke_polyline(pixmap, current, stroke_color, COASTLINE_STROKE_WIDTH, LineCap::Butt, None);
    }
    current.clear();
}

// ---------------------------------------------------------------------------
// Range rings + labels
// ---------------------------------------------------------------------------

/// Port of `drawRangeRings` (AzimuthalMapRenderer.swift:203-245). Draws
/// dashed concentric rings every `RING_DISTANCE_KM`, plus one [`RingLabel`]
/// anchor per ring (in place of Swift's rasterized `drawRingLabel`).
fn draw_range_rings(pixmap: &mut Pixmap, center: (f32, f32), radius: f32) -> Vec<RingLabel> {
    let stroke_color = color(Rgba::new(1.0, 1.0, 1.0, 1.0).with_alpha(RING_ALPHA));
    let ring_fraction = (RING_DISTANCE_KM / RING_EARTH_HALF_CIRCUM_KM) as f32;

    let mut labels = Vec::new();
    let mut ring_radius = ring_fraction * radius;
    let mut distance_km = RING_DISTANCE_KM;

    while ring_radius < radius {
        stroke_dashed_circle(pixmap, center, ring_radius, stroke_color);
        if let Some(label) = ring_label(center, ring_radius, distance_km) {
            labels.push(label);
        }
        ring_radius += ring_fraction * radius;
        distance_km += RING_DISTANCE_KM;
    }

    labels
}

/// Stroke a dashed circle. Port of the dashed `ctx.strokeEllipse`
/// (AzimuthalMapRenderer.swift:219, 225-230 — `setLineDash(phase: 0, lengths:
/// [4, 4])` then `strokeEllipse`), using tiny-skia's native
/// [`StrokeDash`] rather than manual arc tessellation.
fn stroke_dashed_circle(pixmap: &mut Pixmap, center: (f32, f32), radius: f32, stroke_color: tiny_skia::Color) {
    if radius <= 0.0 {
        return;
    }
    let Some(path) = PathBuilder::from_circle(center.0, center.1, radius) else {
        return;
    };
    let paint = solid_paint(stroke_color);
    let stroke = Stroke {
        width: RING_STROKE_WIDTH,
        line_cap: LineCap::Butt,
        line_join: LineJoin::Round,
        dash: StrokeDash::new(RING_DASH.to_vec(), 0.0),
        ..Stroke::default()
    };
    pixmap.stroke_path(&path, &paint, &stroke, Transform::identity(), None);
}

/// Compute the ring label text + anchor for one range ring. Port of
/// `drawRingLabel` (AzimuthalMapRenderer.swift:247-279) MINUS text
/// rasterization.
///
/// ## Judgment call: anchor position without font metrics
///
/// Swift centers the label horizontally and lifts it above the ring using
/// `NSString.size(withAttributes:)` (the exact width/height of "5k mi" set in
/// `UIFont.systemFont(ofSize: 7)`):
/// ```swift
/// let labelPoint = CGPoint(
///     x: center.x - textSize.width / 2,
///     y: center.y - ringRadius - textSize.height - 1
/// )
/// guard labelPoint.y > 0 else { return }
/// ```
/// cw-domain has no font/text-layout dependency (by design — see module docs
/// and the Phase D design doc's "Ring labels: no text in Rust rasters"
/// decision), so `textSize` isn't reproducible here. Since the design doc
/// explicitly accepts "font metrics differ slightly" as each platform
/// overlays natively, this anchor is the ring's TOP-CENTER point (`x =
/// center.x`, `y = center.y - ringRadius`) — the position Swift's box is
/// built outward from — leaving the platform's own text layout to apply
/// centering/ascent exactly as it would for any other native label. The
/// off-canvas guard is applied against this same unadjusted `y` (`y > 0`),
/// the closest faithful equivalent of Swift's `labelPoint.y > 0` check.
fn ring_label(center: (f32, f32), ring_radius: f32, distance_km: f64) -> Option<RingLabel> {
    let y = center.1 - ring_radius;
    if y <= 0.0 {
        return None;
    }
    Some(RingLabel { x: center.0, y, text: format_ring_distance(distance_km) })
}

/// Port of the ring-caption format logic (AzimuthalMapRenderer.swift:251-257):
/// convert km → statute miles, then `"%.0fk mi"` above 1,000 mi or `"%.0f mi"`
/// below.
fn format_ring_distance(distance_km: f64) -> String {
    let distance_mi = distance_km * KM_TO_MILES;
    if distance_mi >= 1_000.0 {
        format!("{:.0}k mi", distance_mi / 1_000.0)
    } else {
        format!("{:.0} mi", distance_mi)
    }
}

// ---------------------------------------------------------------------------
// Trace lines
// ---------------------------------------------------------------------------

/// Draw one great-circle trace directly through the azimuthal projection
/// (NOT antimeridian-split — the projection itself handles wrap; points
/// beyond the projectable range break the path). Port of `drawTraceLines`
/// (AzimuthalMapRenderer.swift:283-332), using
/// [`AzimuthalProjection::great_circle_path`] per the brief rather than the
/// flat renderer's antimeridian-aware [`crate::great_circle`] helper.
fn draw_trace_line(
    pixmap: &mut Pixmap,
    proj: &AzimuthalProjection,
    center: (f32, f32),
    radius: f32,
    from: (f64, f64),
    to: (f64, f64),
    line_color: Rgba,
) {
    let path = AzimuthalProjection::great_circle_path(from.0, from.1, to.0, to.1, TRACE_SEGMENTS);
    if path.len() < 2 {
        return;
    }
    let c = color(line_color);

    let mut current: Vec<(f32, f32)> = Vec::new();
    for &(lat, lon) in &path {
        match screen_point(proj, center, radius, lat, lon) {
            Some(pt) => current.push(pt),
            None => {
                flush_trace(pixmap, &mut current, c);
            }
        }
    }
    flush_trace(pixmap, &mut current, c);
}

fn flush_trace(pixmap: &mut Pixmap, current: &mut Vec<(f32, f32)>, line_color: tiny_skia::Color) {
    if current.len() >= 2 {
        stroke_polyline(pixmap, current, line_color, TRACE_LINE_WIDTH, LineCap::Round, None);
    }
    current.clear();
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::share_render::themes::{theme, ThemeStyle};

    fn sample_spec() -> AzimuthalMapSpec {
        AzimuthalMapSpec {
            width: 200,
            height: 200,
            center: (37.4, -122.3), // San Francisco-ish QTH.
            pins: vec![
                AzimuthalPin { lat: 35.5, lon: 139.4, color: PinColor::Count(3) },
                AzimuthalPin {
                    lat: -33.9,
                    lon: 151.2,
                    color: PinColor::Rgba(Rgba::new(0.2, 0.6, 1.0, 1.0)),
                },
            ],
            traces: vec![((37.4, -122.3), (35.5, 139.4))],
            center_marker: Some((37.4, -122.3)),
        }
    }

    #[test]
    fn renders_a_valid_png() {
        let (png, _labels) = render_azimuthal(&sample_spec(), &theme(ThemeStyle::Azimuthal));
        assert_eq!(&png[..8], &[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]);
    }

    #[test]
    fn render_is_deterministic() {
        let (a, la) = render_azimuthal(&sample_spec(), &theme(ThemeStyle::Azimuthal));
        let (b, lb) = render_azimuthal(&sample_spec(), &theme(ThemeStyle::Azimuthal));
        assert_eq!(a, b, "identical inputs must produce byte-identical PNGs");
        assert_eq!(la, lb);
    }

    #[test]
    fn ring_labels_use_exact_swift_format() {
        assert_eq!(format_ring_distance(5_000.0), "3k mi"); // 5000*0.621371=3106.855 -> 3k mi
        assert_eq!(format_ring_distance(500.0), "311 mi"); // 500*0.621371=310.6855 -> 311 mi
        assert_eq!(format_ring_distance(20_037.0), "12k mi");
    }

    #[test]
    fn ring_labels_pinned_for_fixed_spec() {
        let (_png, labels) = render_azimuthal(&sample_spec(), &theme(ThemeStyle::Azimuthal));
        // 200x200 canvas, padding 8 -> map_radius = 92. Rings at
        // ring_fraction*radius, ring_fraction = 5000/20037 ≈ 0.249551...
        let radius = 100.0_f32 - MAP_PADDING;
        let ring_fraction = (RING_DISTANCE_KM / RING_EARTH_HALF_CIRCUM_KM) as f32;
        let center = (100.0_f32, 100.0_f32);

        let mut expected = Vec::new();
        let mut ring_radius = ring_fraction * radius;
        let mut distance_km = RING_DISTANCE_KM;
        while ring_radius < radius {
            let y = center.1 - ring_radius;
            if y > 0.0 {
                expected.push(RingLabel { x: center.0, y, text: format_ring_distance(distance_km) });
            }
            ring_radius += ring_fraction * radius;
            distance_km += RING_DISTANCE_KM;
        }

        assert_eq!(labels.len(), expected.len());
        for (got, want) in labels.iter().zip(expected.iter()) {
            assert!((got.x - want.x).abs() < 1e-4, "x mismatch: {got:?} vs {want:?}");
            assert!((got.y - want.y).abs() < 1e-4, "y mismatch: {got:?} vs {want:?}");
            assert_eq!(got.text, want.text);
        }
        // Pin exact values for the fixed 200x200/padding-8 spec.
        assert_eq!(labels[0].text, "3k mi");
        assert!((labels[0].x - 100.0).abs() < 1e-4);
    }

    #[test]
    fn off_canvas_ring_labels_are_dropped() {
        // A tiny canvas whose map radius is smaller than the first ring
        // radius should yield zero labels (and zero rings drawn).
        let spec = AzimuthalMapSpec {
            width: 10,
            height: 10,
            center: (0.0, 0.0),
            pins: vec![],
            traces: vec![],
            center_marker: None,
        };
        let (_png, labels) = render_azimuthal(&spec, &theme(ThemeStyle::Azimuthal));
        assert!(labels.is_empty());
    }

    #[test]
    fn empty_spec_still_renders_background() {
        let spec = AzimuthalMapSpec {
            width: 40,
            height: 24,
            center: (0.0, 0.0),
            pins: vec![],
            traces: vec![],
            center_marker: None,
        };
        let (png, _labels) = render_azimuthal(&spec, &theme(ThemeStyle::Azimuthal));
        assert_eq!(&png[..8], &[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]);
    }
}
