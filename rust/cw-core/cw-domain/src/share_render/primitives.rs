//! Shared tiny-skia drawing primitives + pin/center-marker geometry used by
//! both [`super::flat`] and [`super::azimuthal`].
//!
//! Extracted out of `flat.rs` when the azimuthal renderer was added (map port
//! Phase D, Task 2) — the pin marker (needle + head) and center marker
//! (halo + inner dot) are drawn with IDENTICAL geometry/alpha constants in
//! both Swift renderers (`FlatMapRenderer+Drawing.swift` /
//! `BragSheetShareRenderer+Drawing.swift` vs `AzimuthalMapRenderer.swift:334-391`),
//! so they live here once instead of being copied.

use tiny_skia::{FillRule, LineCap, LineJoin, Mask, Paint, PathBuilder, Pixmap, Shader, Stroke, Transform};

use crate::share_render::themes::Rgba;

/// Pin head radius. Provenance: FlatMapRenderer+Drawing.swift:119 (RST),
/// BragSheetShareRenderer+Drawing.swift:120 (count),
/// AzimuthalMapRenderer.swift:339 (`headRadius`).
pub(crate) const PIN_HEAD_RADIUS: f32 = 4.5;
/// Pin total height (tip to top). Provenance: FlatMapRenderer+Drawing.swift:120,
/// AzimuthalMapRenderer.swift:340 (`pinHeight`).
pub(crate) const PIN_HEIGHT: f32 = 14.0;
/// Pin needle stroke width. Provenance: FlatMapRenderer+Drawing.swift:126,
/// AzimuthalMapRenderer.swift:346.
pub(crate) const PIN_NEEDLE_WIDTH: f32 = 1.5;
/// Pin needle alpha. Provenance: FlatMapRenderer+Drawing.swift:125,
/// AzimuthalMapRenderer.swift:345.
pub(crate) const PIN_NEEDLE_ALPHA: f32 = 0.7;
/// Pin head fill alpha. Provenance: FlatMapRenderer+Drawing.swift:132,
/// AzimuthalMapRenderer.swift:352.
pub(crate) const PIN_HEAD_ALPHA: f32 = 0.8;

/// Center (QTH) marker inner dot radius. Provenance: FlatMapRenderer+Drawing.swift:150,
/// AzimuthalMapRenderer.swift:365 (`dotRadius`).
pub(crate) const CENTER_DOT_RADIUS: f32 = 5.0;
/// Center marker halo radius multiplier. Provenance: FlatMapRenderer+Drawing.swift:157-159,
/// AzimuthalMapRenderer.swift:373-376 (`dotRadius * 1.8`, box `* 3.6`).
pub(crate) const CENTER_HALO_SCALE: f32 = 1.8;
/// Center marker halo alpha. Provenance: FlatMapRenderer+Drawing.swift:154,
/// AzimuthalMapRenderer.swift:370 (`alpha: 0.3`).
pub(crate) const CENTER_HALO_ALPHA: f32 = 0.3;
/// Center marker inner-dot alpha. Provenance: FlatMapRenderer+Drawing.swift:162,
/// AzimuthalMapRenderer.swift:381 (`alpha: 0.9`).
pub(crate) const CENTER_DOT_ALPHA: f32 = 0.9;

/// Count → color ramp. Port of `BragSheetShareRenderer.pinColor(for:)`
/// (BragSheetShareRenderer+Drawing.swift:148-155).
pub(crate) fn pin_color_for_count(count: u32) -> Rgba {
    match count {
        1..=5 => Rgba::new(0.55, 0.85, 0.55, 1.0),
        6..=20 => Rgba::new(0.90, 0.85, 0.45, 1.0),
        21..=50 => Rgba::new(0.90, 0.65, 0.35, 1.0),
        _ => Rgba::new(0.90, 0.45, 0.40, 1.0),
    }
}

/// Draw a map pin (needle + head) with `point` as the tip. Port of
/// `drawRSTPin`/`drawPinMarker` (identical geometry;
/// FlatMapRenderer+Drawing.swift:116-138, BragSheetShareRenderer+Drawing.swift:115-146,
/// AzimuthalMapRenderer.swift:336-358).
pub(crate) fn draw_pin(pixmap: &mut Pixmap, point: (f32, f32), pin: Rgba) {
    let tip_y = point.1;
    let head_center_y = tip_y - PIN_HEIGHT + PIN_HEAD_RADIUS;

    // Needle: tip → bottom of head.
    stroke_line(
        pixmap,
        (point.0, tip_y),
        (point.0, head_center_y + PIN_HEAD_RADIUS),
        color(pin.with_alpha(PIN_NEEDLE_ALPHA)),
        PIN_NEEDLE_WIDTH,
        LineCap::Round,
    );

    // Head circle.
    fill_circle(
        pixmap,
        (point.0, head_center_y),
        PIN_HEAD_RADIUS,
        color(pin.with_alpha(PIN_HEAD_ALPHA)),
    );
}

/// Draw a center (QTH) marker (halo + inner dot) at a pre-projected screen
/// point. Port of `drawCenterMarker` (FlatMapRenderer+Drawing.swift:142-171,
/// AzimuthalMapRenderer.swift:362-391).
pub(crate) fn draw_center_marker(pixmap: &mut Pixmap, center: (f32, f32), accent: Rgba) {
    fill_circle(
        pixmap,
        center,
        CENTER_DOT_RADIUS * CENTER_HALO_SCALE,
        color(accent.with_alpha(CENTER_HALO_ALPHA)),
    );
    fill_circle(
        pixmap,
        center,
        CENTER_DOT_RADIUS,
        color(accent.with_alpha(CENTER_DOT_ALPHA)),
    );
}

/// Build an anti-aliased solid-color [`Paint`].
pub(crate) fn solid_paint<'a>(c: tiny_skia::Color) -> Paint<'a> {
    Paint {
        shader: Shader::SolidColor(c),
        anti_alias: true,
        ..Paint::default()
    }
}

/// Convert a straight-sRGB [`Rgba`] to a tiny-skia [`tiny_skia::Color`],
/// clamping components into range.
pub(crate) fn color(c: Rgba) -> tiny_skia::Color {
    tiny_skia::Color::from_rgba(
        c.r.clamp(0.0, 1.0),
        c.g.clamp(0.0, 1.0),
        c.b.clamp(0.0, 1.0),
        c.a.clamp(0.0, 1.0),
    )
    .unwrap_or_else(|| tiny_skia::Color::from_rgba8(0, 0, 0, 0))
}

pub(crate) fn stroke_line(
    pixmap: &mut Pixmap,
    a: (f32, f32),
    b: (f32, f32),
    line_color: tiny_skia::Color,
    line_width: f32,
    cap: LineCap,
) {
    let mut pb = PathBuilder::new();
    pb.move_to(a.0, a.1);
    pb.line_to(b.0, b.1);
    let Some(path) = pb.finish() else {
        return;
    };
    let paint = solid_paint(line_color);
    let stroke = Stroke {
        width: line_width,
        line_cap: cap,
        line_join: LineJoin::Round,
        ..Stroke::default()
    };
    pixmap.stroke_path(&path, &paint, &stroke, Transform::identity(), None);
}

pub(crate) fn stroke_polyline(
    pixmap: &mut Pixmap,
    points: &[(f32, f32)],
    line_color: tiny_skia::Color,
    line_width: f32,
    cap: LineCap,
    mask: Option<&Mask>,
) {
    if points.len() < 2 {
        return;
    }
    let mut pb = PathBuilder::new();
    pb.move_to(points[0].0, points[0].1);
    for &(x, y) in &points[1..] {
        pb.line_to(x, y);
    }
    let Some(path) = pb.finish() else {
        return;
    };
    let paint = solid_paint(line_color);
    let stroke = Stroke {
        width: line_width,
        line_cap: cap,
        line_join: LineJoin::Round,
        ..Stroke::default()
    };
    pixmap.stroke_path(&path, &paint, &stroke, Transform::identity(), mask);
}

pub(crate) fn fill_circle(pixmap: &mut Pixmap, center: (f32, f32), radius: f32, fill: tiny_skia::Color) {
    let Some(path) = PathBuilder::from_circle(center.0, center.1, radius) else {
        return;
    };
    let paint = solid_paint(fill);
    pixmap.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), None);
}
