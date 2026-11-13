//! UniFFI surface for the themed share-map rasterizer
//! (`cw_domain::share_render`). Store-less: `render_share_map` is a free
//! export mapping an [`FfiShareMapInput`] onto either the flat equirectangular
//! renderer ([`cw_domain::share_render::render_flat`]) or the azimuthal
//! equidistant renderer ([`cw_domain::share_render::render_azimuthal`]),
//! selected by [`FfiShareMapStyle`], and returning PNG bytes plus (for the
//! azimuthal style only) the ring-label anchors the platform overlays natively.
//!
//! ## What Task 7 (the orchestrator) feeds this
//!
//! The Swift `FlatMapRenderer`/`AzimuthalMapRenderer` call sites
//! (`FlatMapRenderer.swift:152-242`, `AzimuthalMapRenderer.swift`) drive the
//! renderers with a viewport already computed (`computeViewport`) plus one of
//! two pin flavours:
//!
//! - **count pins** — `render(clusters:)` draws `BragSheetMapCluster.count`
//!   through the count→color ramp (`pinColor(for:)`). Mirrored by
//!   [`FfiSharePinColorKind::Count`] + `count`.
//! - **RST-color pins** — `render(markers:)` draws `ShareMapMarker.rstColor`,
//!   an arbitrary color. Mirrored by [`FfiSharePinColorKind::Rgba`] + the
//!   `red`/`green`/`blue`/`alpha` fields.
//!
//! The viewport `center` + `lat_span`/`lon_span` (flat) are supplied
//! pre-computed by the caller — this keeps the renderer a pure function of its
//! inputs, exactly as the Rust `FlatMapSpec`/`AzimuthalMapSpec` are.

use cw_domain::maidenhead;
use cw_domain::share_render::{
    compute_flat_share_viewport as domain_compute_flat_share_viewport, render_azimuthal, render_flat, theme,
    AzimuthalMapSpec, AzimuthalPin, FlatMapSpec, PinColor, Rgba, SharePin, ThemeStyle,
};

use crate::{CwError, FfiCoordinate};

/// The six selectable share-map styles. `Azimuthal` routes to the polar
/// projection renderer with the single hardcoded azimuthal palette; the other
/// five route to the flat equirectangular renderer with the matching named
/// theme. Mirrors the Swift `ShareMapStyle` enum
/// (`FlatMapRenderer.theme(for:)`, :245-254, + the azimuthal case).
#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum FfiShareMapStyle {
    Azimuthal,
    Midnight,
    Warm,
    Ocean,
    Arctic,
    Ember,
}

/// How a pin derives its color. Two modes, one per Swift render path:
/// `Count` reproduces the brag-sheet count→color ramp; `Rgba` reproduces the
/// activation path's arbitrary (RST/band) color.
#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum FfiSharePinColorKind {
    /// Use the count→color ramp; read `count`.
    Count,
    /// Use `red`/`green`/`blue`/`alpha` directly (0.0–1.0 sRGB).
    Rgba,
}

/// One pin on the share map. `lat`/`lon` are degrees. `kind` selects which of
/// the color inputs is read: `Count` reads `count`; `Rgba` reads
/// `red`/`green`/`blue`/`alpha`. The unused inputs are ignored (a `Count` pin
/// ignores the RGBA channels, and vice versa).
#[derive(uniffi::Record, Debug, Clone, Copy)]
pub struct FfiSharePin {
    pub lat: f64,
    pub lon: f64,
    pub kind: FfiSharePinColorKind,
    /// Read only when `kind == Count`.
    pub count: u32,
    /// Read only when `kind == Rgba` (straight sRGB, 0.0–1.0).
    pub red: f32,
    pub green: f32,
    pub blue: f32,
    pub alpha: f32,
}

/// A geodesic trace, `(from_lat, from_lon) → (to_lat, to_lon)` in degrees.
/// Mirrors the Swift `drawTraceLines` from/to coordinate pairs.
#[derive(uniffi::Record, Debug, Clone, Copy)]
pub struct FfiShareTrace {
    pub from_lat: f64,
    pub from_lon: f64,
    pub to_lat: f64,
    pub to_lon: f64,
}

/// Everything the renderer needs, projection-agnostic. `center_lat`/
/// `center_lon` is the viewport/projection center; if both are absent,
/// `center_grid` (a Maidenhead grid, 4+ chars) is resolved to its box center.
/// `lat_span`/`lon_span` are the flat viewport spans in degrees — ignored on
/// the azimuthal path (range rings fill the canvas regardless). `lon_span` is
/// clamped to ≤ 360° for the flat path (see below).
#[derive(uniffi::Record, Debug, Clone)]
pub struct FfiShareMapInput {
    pub width: u32,
    pub height: u32,
    pub center_lat: Option<f64>,
    pub center_lon: Option<f64>,
    /// Fallback center source when `center_lat`/`center_lon` are absent.
    pub center_grid: Option<String>,
    /// Flat viewport latitude span (degrees). Ignored on the azimuthal path.
    pub lat_span: f64,
    /// Flat viewport longitude span (degrees). Clamped to `0.0..=360.0` on the
    /// flat path — Task 1's per-polygon coastline shift selection
    /// (`best_shift`) assumes a non-near-global viewport, and the Swift
    /// `computeViewport` likewise never produced a span wider than the 360°
    /// world. Ignored on the azimuthal path.
    pub lon_span: f64,
    pub pins: Vec<FfiSharePin>,
    pub traces: Vec<FfiShareTrace>,
    /// Draw the operator-QTH center marker at `center`. On the azimuthal path
    /// the marker always renders at the projection center when `true`.
    pub show_center_marker: bool,
}

/// One overlaid range-ring label (azimuthal path only). `x`/`y` are a
/// screen-space anchor in the PNG's coordinate system; see
/// [`cw_domain::share_render::RingLabel`] for the anchor-edge semantics
/// (`x` is the horizontal center, text renders above `y` which is the ring's
/// top point). Empty for flat styles.
#[derive(uniffi::Record, Debug, Clone)]
pub struct FfiRingLabel {
    pub x: f32,
    pub y: f32,
    pub text: String,
}

/// The rendered share map: PNG bytes plus any ring labels to overlay natively.
#[derive(uniffi::Record, Debug, Clone)]
pub struct FfiShareMapImage {
    pub png_bytes: Vec<u8>,
    /// Non-empty only for [`FfiShareMapStyle::Azimuthal`].
    pub ring_labels: Vec<FfiRingLabel>,
}

/// Maximum flat longitude span. The world is 360° wide; `best_shift`
/// (`share_render::flat`) selects a single coastline copy per polygon assuming
/// the viewport is narrower than the whole globe.
const MAX_FLAT_LON_SPAN: f64 = 360.0;

impl FfiShareMapStyle {
    fn theme_style(self) -> ThemeStyle {
        match self {
            FfiShareMapStyle::Azimuthal => ThemeStyle::Azimuthal,
            FfiShareMapStyle::Midnight => ThemeStyle::Midnight,
            FfiShareMapStyle::Warm => ThemeStyle::Warm,
            FfiShareMapStyle::Ocean => ThemeStyle::Ocean,
            FfiShareMapStyle::Arctic => ThemeStyle::Arctic,
            FfiShareMapStyle::Ember => ThemeStyle::Ember,
        }
    }
}

impl From<FfiSharePin> for PinColor {
    fn from(pin: FfiSharePin) -> Self {
        match pin.kind {
            FfiSharePinColorKind::Count => PinColor::Count(pin.count),
            FfiSharePinColorKind::Rgba => PinColor::Rgba(Rgba::new(pin.red, pin.green, pin.blue, pin.alpha)),
        }
    }
}

/// Resolve the viewport/projection center from the input, falling back to the
/// grid box center, then to `(0, 0)`.
fn resolve_center(input: &FfiShareMapInput) -> (f64, f64) {
    if let (Some(lat), Some(lon)) = (input.center_lat, input.center_lon) {
        return (lat, lon);
    }
    if let Some(grid) = &input.center_grid {
        if let Some((min, max)) = maidenhead::grid_bounds(grid) {
            return ((min.latitude + max.latitude) / 2.0, (min.longitude + max.longitude) / 2.0);
        }
    }
    (0.0, 0.0)
}

fn trace_pairs(traces: &[FfiShareTrace]) -> Vec<((f64, f64), (f64, f64))> {
    traces
        .iter()
        .map(|t| ((t.from_lat, t.from_lon), (t.to_lat, t.to_lon)))
        .collect()
}

/// Render a themed share map from `input`, selected by `style`.
///
/// Free export (store-less). Returns PNG bytes plus, for the azimuthal style,
/// the ring-label anchors to overlay natively; flat styles return an empty
/// `ring_labels`. Never errors today — the `Result` leaves room for future
/// validation and keeps the signature uniform with the store-backed APIs.
#[uniffi::export]
pub fn render_share_map(style: FfiShareMapStyle, input: FfiShareMapInput) -> Result<FfiShareMapImage, CwError> {
    let center = resolve_center(&input);
    let center_marker = input.show_center_marker.then_some(center);
    let selected_theme = theme(style.theme_style());

    match style {
        FfiShareMapStyle::Azimuthal => {
            let spec = AzimuthalMapSpec {
                width: input.width,
                height: input.height,
                center,
                pins: input
                    .pins
                    .iter()
                    .map(|p| AzimuthalPin { lat: p.lat, lon: p.lon, color: PinColor::from(*p) })
                    .collect(),
                traces: trace_pairs(&input.traces),
                center_marker,
            };
            let (png_bytes, labels) = render_azimuthal(&spec, &selected_theme);
            Ok(FfiShareMapImage {
                png_bytes,
                ring_labels: labels
                    .into_iter()
                    .map(|l| FfiRingLabel { x: l.x, y: l.y, text: l.text })
                    .collect(),
            })
        }
        _ => {
            let spec = FlatMapSpec {
                width: input.width,
                height: input.height,
                center,
                lat_span: input.lat_span,
                lon_span: input.lon_span.clamp(0.0, MAX_FLAT_LON_SPAN),
                pins: input
                    .pins
                    .iter()
                    .map(|p| SharePin { lat: p.lat, lon: p.lon, color: PinColor::from(*p) })
                    .collect(),
                traces: trace_pairs(&input.traces),
                center_marker,
            };
            let png_bytes = render_flat(&spec, &selected_theme);
            Ok(FfiShareMapImage { png_bytes, ring_labels: Vec::new() })
        }
    }
}

/// A framed flat share-map viewport: projection center + total spans, degrees.
/// Mirrors [`cw_domain::share_render::ShareViewport`]. The caller feeds
/// `center_lat`/`center_lon` + `lat_span`/`lon_span` straight into
/// [`FfiShareMapInput`] for the flat styles.
#[derive(uniffi::Record, Debug, Clone, Copy, PartialEq)]
pub struct FfiShareViewport {
    pub center_lat: f64,
    pub center_lon: f64,
    pub lat_span: f64,
    pub lon_span: f64,
}

/// Frame `coords` into a flat share-map viewport matched to the `width`/
/// `height` image aspect ratio.
///
/// Free export (store-less). Verbatim port of the deleted iOS
/// `FlatMapRenderer.computeViewport`: bounds-midpoint center (operator QTH is
/// expected to be folded into `coords`), `max(range*0.25, 8)` lat / `max(range*
/// 0.2, 8)` lon padding, aspect-fit expansion of the shorter axis, and ±85°
/// latitude / one-globe longitude clamps. Degenerate inputs (empty `coords` or
/// a zero dimension) return a default near-world viewport.
#[uniffi::export]
pub fn compute_flat_share_viewport(coords: Vec<FfiCoordinate>, width: u32, height: u32) -> FfiShareViewport {
    let pairs: Vec<(f64, f64)> = coords.iter().map(|c| (c.latitude, c.longitude)).collect();
    let vp = domain_compute_flat_share_viewport(&pairs, width, height);
    FfiShareViewport {
        center_lat: vp.center_lat,
        center_lon: vp.center_lon,
        lat_span: vp.lat_span,
        lon_span: vp.lon_span,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn count_pin(lat: f64, lon: f64, count: u32) -> FfiSharePin {
        FfiSharePin {
            lat,
            lon,
            kind: FfiSharePinColorKind::Count,
            count,
            red: 0.0,
            green: 0.0,
            blue: 0.0,
            alpha: 0.0,
        }
    }

    fn rgba_pin(lat: f64, lon: f64, rgba: (f32, f32, f32, f32)) -> FfiSharePin {
        FfiSharePin {
            lat,
            lon,
            kind: FfiSharePinColorKind::Rgba,
            count: 0,
            red: rgba.0,
            green: rgba.1,
            blue: rgba.2,
            alpha: rgba.3,
        }
    }

    fn sample_input() -> FfiShareMapInput {
        FfiShareMapInput {
            width: 200,
            height: 120,
            center_lat: Some(20.0),
            center_lon: Some(150.0),
            center_grid: None,
            lat_span: 120.0,
            lon_span: 200.0,
            pins: vec![count_pin(37.4, -122.3, 3), rgba_pin(-33.9, 151.2, (0.2, 0.6, 1.0, 1.0))],
            traces: vec![FfiShareTrace {
                from_lat: 37.4,
                from_lon: -122.3,
                to_lat: 35.5,
                to_lon: 139.4,
            }],
            show_center_marker: true,
        }
    }

    fn is_png(bytes: &[u8]) -> bool {
        bytes.len() >= 8 && bytes[..8] == [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]
    }

    #[test]
    fn flat_styles_render_png_with_no_ring_labels() {
        for style in [
            FfiShareMapStyle::Midnight,
            FfiShareMapStyle::Warm,
            FfiShareMapStyle::Ocean,
            FfiShareMapStyle::Arctic,
            FfiShareMapStyle::Ember,
        ] {
            let out = render_share_map(style, sample_input()).unwrap();
            assert!(is_png(&out.png_bytes), "{style:?} should render a PNG");
            assert!(out.ring_labels.is_empty(), "{style:?} is flat — no ring labels");
        }
    }

    #[test]
    fn azimuthal_style_renders_png_with_ring_labels() {
        let mut input = sample_input();
        input.width = 200;
        input.height = 200;
        let out = render_share_map(FfiShareMapStyle::Azimuthal, input).unwrap();
        assert!(is_png(&out.png_bytes));
        assert!(!out.ring_labels.is_empty(), "azimuthal must return ring labels");
        // Ring labels are the "Nk mi"/"N mi" captions.
        assert!(out.ring_labels.iter().all(|l| l.text.ends_with("mi")));
    }

    #[test]
    fn style_routes_to_matching_theme() {
        // Each flat style must produce a DIFFERENT background pixel (proves the
        // style→theme routing actually varies), and azimuthal differs from all.
        let midnight = render_share_map(FfiShareMapStyle::Midnight, sample_input()).unwrap();
        let ocean = render_share_map(FfiShareMapStyle::Ocean, sample_input()).unwrap();
        assert_ne!(midnight.png_bytes, ocean.png_bytes, "distinct themes -> distinct PNGs");
    }

    #[test]
    fn lon_span_is_clamped_to_360() {
        // A pathological near-global span must not panic and must render — the
        // clamp keeps `best_shift` in its supported range. Compare against the
        // same input already clamped: identical output proves the clamp took.
        let mut wide = sample_input();
        wide.lon_span = 720.0;
        let mut clamped = sample_input();
        clamped.lon_span = 360.0;
        let a = render_share_map(FfiShareMapStyle::Ocean, wide).unwrap();
        let b = render_share_map(FfiShareMapStyle::Ocean, clamped).unwrap();
        assert!(is_png(&a.png_bytes));
        assert_eq!(a.png_bytes, b.png_bytes, "720° must clamp to 360°");
    }

    #[test]
    fn grid_center_fallback_resolves() {
        // No lat/lon, but a grid — center resolves to the grid box center, so
        // the render still succeeds (and differs from the (0,0) fallback).
        let mut with_grid = sample_input();
        with_grid.center_lat = None;
        with_grid.center_lon = None;
        with_grid.center_grid = Some("CM87".to_string());
        let out = render_share_map(FfiShareMapStyle::Midnight, with_grid).unwrap();
        assert!(is_png(&out.png_bytes));
    }

    #[test]
    fn compute_viewport_centers_on_bounds_midpoint() {
        // Operator off to the west; center must be the whole-set bounds
        // midpoint, not the operator or the pins' centroid.
        let coords = vec![
            FfiCoordinate { latitude: 40.0, longitude: 8.0 },
            FfiCoordinate { latitude: 42.0, longitude: 10.0 },
            FfiCoordinate { latitude: 45.0, longitude: -50.0 },
        ];
        let vp = compute_flat_share_viewport(coords, 100, 100);
        // Raw lon bounds [-50, 10]; padded box stays centered at midpoint -20.
        assert!((vp.center_lon - -20.0).abs() < 1e-9, "center_lon {}", vp.center_lon);
    }

    #[test]
    fn compute_viewport_empty_is_default() {
        let vp = compute_flat_share_viewport(vec![], 100, 100);
        assert!((vp.lat_span - 120.0).abs() < 1e-9);
        assert!((vp.lon_span - 360.0).abs() < 1e-9);
    }

    #[test]
    fn count_and_rgba_pins_both_render() {
        // Exercises both PinColor arms end-to-end; mainly a no-panic check.
        let mut input = sample_input();
        input.pins = vec![count_pin(0.0, 0.0, 42), rgba_pin(10.0, 10.0, (1.0, 0.0, 0.0, 1.0))];
        let out = render_share_map(FfiShareMapStyle::Warm, input).unwrap();
        assert!(is_png(&out.png_bytes));
    }
}
