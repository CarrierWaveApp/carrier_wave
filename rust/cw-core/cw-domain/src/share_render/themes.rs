//! Color themes for the flat share-map rasterizer.
//!
//! Port of `FlatMapRenderer.ColorTheme` (swift/ios/CarrierWave/Views/BragSheet/
//! FlatMapRenderer.swift:24-87). Each palette is captured EXACTLY from the
//! Swift `UIColor(red:green:blue:alpha:)` literals; provenance line numbers are
//! noted per field group. The Swift side names these fields
//! `ocean/landFill/landStroke/landHatch/gridLine/accent`; we rename to
//! snake_case (`land_fill`, etc.) plus add `background` for Task 2/4's use
//! (the flat renderer paints `ocean` as the full-canvas background, so
//! `background` defaults to `ocean` here — the two are the same pixel on the
//! flat path).

/// Straight sRGB color with alpha, components in `0.0..=1.0`.
///
/// Mirrors the Swift `UIColor(red:green:blue:alpha:)` device-RGB literals used
/// throughout `FlatMapRenderer`. No color-management: these are consumed as
/// non-premultiplied sRGB and handed to tiny-skia directly.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Rgba {
    pub r: f32,
    pub g: f32,
    pub b: f32,
    pub a: f32,
}

impl Rgba {
    pub const fn new(r: f32, g: f32, b: f32, a: f32) -> Self {
        Self { r, g, b, a }
    }

    /// Return this color with alpha multiplied by `factor`.
    ///
    /// Mirrors Swift `UIColor.withAlphaComponent(_:)` used at the pin/trace/
    /// center-marker draw sites (e.g. FlatMapRenderer+Drawing.swift:125,132,
    /// 154,162 and the trace `accent.withAlphaComponent(0.5)` at
    /// FlatMapRenderer.swift:171).
    pub fn with_alpha(self, factor: f32) -> Self {
        Self { a: self.a * factor, ..self }
    }
}

/// Named flat-map palette. Field semantics documented at
/// FlatMapRenderer.swift:75-86.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ShareTheme {
    /// Ocean / full-canvas background color.
    pub ocean: Rgba,
    /// Solid fill for land polygons.
    pub land_fill: Rgba,
    /// Stroke color for land polygon edges.
    pub land_stroke: Rgba,
    /// Subtle crosshatch lines drawn over land for texture.
    pub land_hatch: Rgba,
    /// Lat/lon grid line color.
    pub grid_line: Rgba,
    /// Accent color for trace lines, center marker, and labels.
    pub accent: Rgba,
    /// Background color. On the flat path this equals `ocean`; kept separate
    /// so the azimuthal path (Task 2) can differ.
    pub background: Rgba,
}

/// Selectable theme style. Mirrors the custom-flat cases of the Swift
/// `ShareMapStyle` enum routed through `FlatMapRenderer.theme(for:)`
/// (FlatMapRenderer.swift:245-254), plus `Azimuthal` (the single hardcoded
/// palette from `AzimuthalMapRenderer.swift:89-95`, added Task 2).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThemeStyle {
    Midnight,
    Warm,
    Ocean,
    Arctic,
    Ember,
    Azimuthal,
}

impl ShareTheme {
    /// Deep indigo/purple — night sky feel.
    /// Provenance: FlatMapRenderer.swift:26-33.
    pub const MIDNIGHT: ShareTheme = ShareTheme {
        ocean: Rgba::new(0.020, 0.012, 0.055, 1.0),
        land_fill: Rgba::new(0.110, 0.085, 0.210, 1.0),
        land_stroke: Rgba::new(0.170, 0.140, 0.300, 1.0),
        land_hatch: Rgba::new(0.135, 0.108, 0.250, 1.0),
        grid_line: Rgba::new(0.040, 0.032, 0.090, 1.0),
        accent: Rgba::new(0.627, 0.471, 1.0, 1.0),
        background: Rgba::new(0.020, 0.012, 0.055, 1.0),
    };

    /// Warm amber/brown — vintage radio feel.
    /// Provenance: FlatMapRenderer.swift:36-43.
    pub const WARM: ShareTheme = ShareTheme {
        ocean: Rgba::new(0.055, 0.038, 0.025, 1.0),
        land_fill: Rgba::new(0.210, 0.155, 0.100, 1.0),
        land_stroke: Rgba::new(0.290, 0.215, 0.145, 1.0),
        land_hatch: Rgba::new(0.245, 0.180, 0.120, 1.0),
        grid_line: Rgba::new(0.090, 0.065, 0.042, 1.0),
        accent: Rgba::new(1.0, 0.706, 0.235, 1.0),
        background: Rgba::new(0.055, 0.038, 0.025, 1.0),
    };

    /// Deep blue — ocean chart feel.
    /// Provenance: FlatMapRenderer.swift:46-53.
    pub const OCEAN: ShareTheme = ShareTheme {
        ocean: Rgba::new(0.020, 0.040, 0.085, 1.0),
        land_fill: Rgba::new(0.110, 0.155, 0.210, 1.0),
        land_stroke: Rgba::new(0.165, 0.215, 0.280, 1.0),
        land_hatch: Rgba::new(0.135, 0.180, 0.240, 1.0),
        grid_line: Rgba::new(0.040, 0.065, 0.115, 1.0),
        accent: Rgba::new(0.30, 0.80, 0.55, 1.0),
        background: Rgba::new(0.020, 0.040, 0.085, 1.0),
    };

    /// Cool grey-blue — arctic/steel feel.
    /// Provenance: FlatMapRenderer.swift:56-63.
    pub const ARCTIC: ShareTheme = ShareTheme {
        ocean: Rgba::new(0.045, 0.050, 0.065, 1.0),
        land_fill: Rgba::new(0.155, 0.165, 0.195, 1.0),
        land_stroke: Rgba::new(0.220, 0.230, 0.265, 1.0),
        land_hatch: Rgba::new(0.185, 0.195, 0.225, 1.0),
        grid_line: Rgba::new(0.070, 0.075, 0.095, 1.0),
        accent: Rgba::new(0.45, 0.78, 1.0, 1.0),
        background: Rgba::new(0.045, 0.050, 0.065, 1.0),
    };

    /// Ember red-orange — signal strength / heat map feel.
    /// Provenance: FlatMapRenderer.swift:66-73.
    pub const EMBER: ShareTheme = ShareTheme {
        ocean: Rgba::new(0.050, 0.020, 0.020, 1.0),
        land_fill: Rgba::new(0.190, 0.095, 0.075, 1.0),
        land_stroke: Rgba::new(0.265, 0.140, 0.110, 1.0),
        land_hatch: Rgba::new(0.225, 0.115, 0.090, 1.0),
        grid_line: Rgba::new(0.080, 0.038, 0.035, 1.0),
        accent: Rgba::new(1.0, 0.45, 0.20, 1.0),
        background: Rgba::new(0.050, 0.020, 0.020, 1.0),
    };

    /// Azimuthal projection palette — the single hardcoded scheme used by
    /// `AzimuthalMapRenderer` (no per-style variants on the Swift side).
    /// Provenance: AzimuthalMapRenderer.swift:89-95 (`bgColor` #0F0F1E,
    /// `oceanColor`). `land_fill`/`land_hatch` are unused by the azimuthal
    /// renderer (it only strokes coastlines, no fill/crosshatch — Swift
    /// `drawCoastlines` :151-199) and are set equal to `ocean` as a neutral
    /// placeholder. `land_stroke`/`grid_line`/`accent` mirror the renderer's
    /// hardcoded white-alpha constants (coastline stroke alpha 0.15, range-ring
    /// alpha 0.08, trace alpha 0.5 respectively — see `azimuthal.rs` constants,
    /// which apply these alphas directly rather than reading theme fields, since
    /// the Swift source does not route them through a theme struct).
    pub const AZIMUTHAL: ShareTheme = ShareTheme {
        ocean: Rgba::new(0.07, 0.08, 0.16, 1.0),
        land_fill: Rgba::new(0.07, 0.08, 0.16, 1.0),
        land_stroke: Rgba::new(1.0, 1.0, 1.0, 0.15),
        land_hatch: Rgba::new(0.07, 0.08, 0.16, 1.0),
        grid_line: Rgba::new(1.0, 1.0, 1.0, 0.08),
        accent: Rgba::new(1.0, 1.0, 1.0, 0.5),
        background: Rgba::new(0.059, 0.059, 0.118, 1.0),
    };
}

/// Return the theme for a given style. Mirrors `FlatMapRenderer.theme(for:)`
/// (FlatMapRenderer.swift:245-254).
pub fn theme(style: ThemeStyle) -> ShareTheme {
    match style {
        ThemeStyle::Midnight => ShareTheme::MIDNIGHT,
        ThemeStyle::Warm => ShareTheme::WARM,
        ThemeStyle::Ocean => ShareTheme::OCEAN,
        ThemeStyle::Arctic => ShareTheme::ARCTIC,
        ThemeStyle::Ember => ShareTheme::EMBER,
        ThemeStyle::Azimuthal => ShareTheme::AZIMUTHAL,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn theme_lookup_matches_constants() {
        assert_eq!(theme(ThemeStyle::Midnight), ShareTheme::MIDNIGHT);
        assert_eq!(theme(ThemeStyle::Warm), ShareTheme::WARM);
        assert_eq!(theme(ThemeStyle::Ocean), ShareTheme::OCEAN);
        assert_eq!(theme(ThemeStyle::Arctic), ShareTheme::ARCTIC);
        assert_eq!(theme(ThemeStyle::Ember), ShareTheme::EMBER);
        assert_eq!(theme(ThemeStyle::Azimuthal), ShareTheme::AZIMUTHAL);
    }

    // On the flat path `background` is the same pixel as `ocean`
    // (renderBase fills the canvas with theme.ocean — FlatMapRenderer.swift:337).
    #[test]
    fn background_equals_ocean_on_flat_themes() {
        for style in [
            ThemeStyle::Midnight,
            ThemeStyle::Warm,
            ThemeStyle::Ocean,
            ThemeStyle::Arctic,
            ThemeStyle::Ember,
        ] {
            let t = theme(style);
            assert_eq!(t.background, t.ocean);
        }
    }

    #[test]
    fn with_alpha_scales_only_alpha() {
        let c = Rgba::new(0.2, 0.4, 0.6, 1.0).with_alpha(0.5);
        assert_eq!(c, Rgba::new(0.2, 0.4, 0.6, 0.5));
    }
}
