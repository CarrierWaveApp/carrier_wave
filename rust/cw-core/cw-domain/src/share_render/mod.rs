//! Themed share-map rasterizer (Phase D of the map Rust port).
//!
//! Renders the share card maps as PNG bytes via tiny-skia, replacing the iOS
//! CoreGraphics `FlatMapRenderer`/`AzimuthalMapRenderer`. `flat.rs` is the
//! equirectangular renderer + five named themes; `azimuthal.rs` is the polar
//! projection renderer (Task 2) + ring-label anchors; `primitives.rs` holds
//! drawing helpers shared by both (pin marker, center marker, tiny-skia
//! plumbing).
//!
//! Port sources: `swift/ios/CarrierWave/Views/BragSheet/FlatMapRenderer.swift`
//! + `FlatMapRenderer+Drawing.swift` + `AzimuthalMapRenderer.swift`.

pub mod azimuthal;
pub mod flat;
mod primitives;
pub mod themes;
pub mod viewport;

pub use azimuthal::{render_azimuthal, AzimuthalMapSpec, AzimuthalPin, RingLabel};
pub use flat::{render_flat, FlatMapSpec, PinColor, SharePin};
pub use themes::{theme, Rgba, ShareTheme, ThemeStyle};
pub use viewport::{compute_flat_share_viewport, tightest_longitude_bounds, ShareViewport};

#[cfg(test)]
mod geometry_tests {
    use super::flat::{FlatMapSpec, PinColor, SharePin};
    use super::themes::{theme, ThemeStyle};
    use super::*;

    // A small world-ish spec: a couple of pins, one dateline-crossing trace,
    // a center marker, wide enough to show coastlines. Reused by the golden
    // tests too.
    fn sample_spec() -> FlatMapSpec {
        FlatMapSpec {
            width: 200,
            height: 120,
            center: (20.0, 150.0),
            lat_span: 120.0,
            lon_span: 200.0,
            pins: vec![
                SharePin { lat: 37.4, lon: -122.3, color: PinColor::Count(3) },
                SharePin { lat: 35.5, lon: 139.4, color: PinColor::Count(30) },
                SharePin {
                    lat: -33.9,
                    lon: 151.2,
                    color: PinColor::Rgba(Rgba::new(0.2, 0.6, 1.0, 1.0)),
                },
            ],
            // San Francisco → Tokyo: crosses the antimeridian.
            traces: vec![((37.4, -122.3), (35.5, 139.4))],
            center_marker: Some((37.4, -122.3)),
        }
    }

    #[test]
    fn renders_a_valid_png_for_every_theme() {
        for style in [
            ThemeStyle::Midnight,
            ThemeStyle::Warm,
            ThemeStyle::Ocean,
            ThemeStyle::Arctic,
            ThemeStyle::Ember,
        ] {
            let png = render_flat(&sample_spec(), &theme(style));
            // PNG magic number.
            assert_eq!(&png[..8], &[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]);
        }
    }

    #[test]
    fn render_is_deterministic() {
        let a = render_flat(&sample_spec(), &theme(ThemeStyle::Midnight));
        let b = render_flat(&sample_spec(), &theme(ThemeStyle::Midnight));
        assert_eq!(a, b, "identical inputs must produce byte-identical PNGs");
    }

    #[test]
    fn empty_spec_still_renders_background() {
        let spec = FlatMapSpec {
            width: 40,
            height: 24,
            center: (0.0, 0.0),
            lat_span: 60.0,
            lon_span: 100.0,
            pins: vec![],
            traces: vec![],
            center_marker: None,
        };
        let png = render_flat(&spec, &theme(ThemeStyle::Ocean));
        assert_eq!(&png[..8], &[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]);
    }
}
