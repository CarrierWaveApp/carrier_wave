//! Golden-PNG pinning tests for the flat + azimuthal share-map rasterizers.
//!
//! These goldens pin THIS implementation's byte output, not visual parity with
//! the Swift `FlatMapRenderer`/`AzimuthalMapRenderer` — visual parity is a
//! separate spot-check. The fixtures were generated once from
//! `render_flat`/`render_azimuthal` and committed; any change to a renderer
//! that alters output must regenerate them intentionally:
//!
//! ```text
//! CW_REGEN_GOLDENS=1 cargo test -p cw-domain --test share_render_goldens
//! ```
//!
//! Rendering is deterministic (tiny-skia CPU raster, no time/threads/random),
//! so the byte comparison is stable across runs on the same target.

use std::path::PathBuf;

use cw_domain::share_render::{
    render_azimuthal, render_flat, theme, AzimuthalMapSpec, AzimuthalPin, FlatMapSpec, PinColor, Rgba,
    SharePin, ThemeStyle,
};

/// The pinned fixture spec: a few pins (count-ramp + arbitrary RGBA), one
/// dateline-crossing geodesic trace (SF → Tokyo), a center marker, and a wide
/// enough viewport that coastlines are visible. Small canvas keeps fixtures
/// tiny.
fn fixture_spec() -> FlatMapSpec {
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
        traces: vec![((37.4, -122.3), (35.5, 139.4))],
        center_marker: Some((37.4, -122.3)),
    }
}

fn fixtures_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/share_render")
}

fn all_styles() -> [(&'static str, ThemeStyle); 5] {
    [
        ("midnight", ThemeStyle::Midnight),
        ("warm", ThemeStyle::Warm),
        ("ocean", ThemeStyle::Ocean),
        ("arctic", ThemeStyle::Arctic),
        ("ember", ThemeStyle::Ember),
    ]
}

#[test]
fn golden_pngs_match() {
    let regen = std::env::var("CW_REGEN_GOLDENS").is_ok();
    let dir = fixtures_dir();
    if regen {
        std::fs::create_dir_all(&dir).expect("create fixtures dir");
    }

    for (name, style) in all_styles() {
        let png = render_flat(&fixture_spec(), &theme(style));
        let path = dir.join(format!("flat_{name}.png"));

        if regen {
            std::fs::write(&path, &png).expect("write golden");
            continue;
        }

        let expected = std::fs::read(&path).unwrap_or_else(|_| {
            panic!(
                "missing golden {}; regenerate with CW_REGEN_GOLDENS=1",
                path.display()
            )
        });
        assert_eq!(
            png,
            expected,
            "golden mismatch for theme '{name}' — if intended, regenerate with CW_REGEN_GOLDENS=1"
        );
    }
}

/// The pinned azimuthal fixture spec: QTH in San Francisco, pins in Tokyo
/// (count-ramp) and Sydney (arbitrary RGBA), one great-circle trace to Tokyo,
/// a center marker at the QTH. Small square canvas keeps fixtures tiny while
/// still exercising coastlines + several range rings.
fn azimuthal_fixture_spec() -> AzimuthalMapSpec {
    AzimuthalMapSpec {
        width: 200,
        height: 200,
        center: (37.4, -122.3),
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
fn golden_azimuthal_png_matches() {
    let regen = std::env::var("CW_REGEN_GOLDENS").is_ok();
    let dir = fixtures_dir();
    if regen {
        std::fs::create_dir_all(&dir).expect("create fixtures dir");
    }

    let (png, _labels) = render_azimuthal(&azimuthal_fixture_spec(), &theme(ThemeStyle::Azimuthal));
    let path = dir.join("azimuthal.png");

    if regen {
        std::fs::write(&path, &png).expect("write golden");
        return;
    }

    let expected = std::fs::read(&path).unwrap_or_else(|_| {
        panic!("missing golden {}; regenerate with CW_REGEN_GOLDENS=1", path.display())
    });
    assert_eq!(
        png,
        expected,
        "golden mismatch for azimuthal renderer — if intended, regenerate with CW_REGEN_GOLDENS=1"
    );
}

#[test]
fn golden_azimuthal_ring_labels_match() {
    // Ring-label anchors aren't PNG bytes, so pin them as a plain text fixture
    // alongside the PNG rather than embedding expectations in this file (they
    // regenerate under the same CW_REGEN_GOLDENS switch as the PNG goldens).
    let regen = std::env::var("CW_REGEN_GOLDENS").is_ok();
    let dir = fixtures_dir();
    if regen {
        std::fs::create_dir_all(&dir).expect("create fixtures dir");
    }

    let (_png, labels) = render_azimuthal(&azimuthal_fixture_spec(), &theme(ThemeStyle::Azimuthal));
    let rendered: String = labels
        .iter()
        .map(|l| format!("{:.4},{:.4},{}\n", l.x, l.y, l.text))
        .collect();
    let path = dir.join("azimuthal_ring_labels.txt");

    if regen {
        std::fs::write(&path, &rendered).expect("write golden");
        return;
    }

    let expected = std::fs::read_to_string(&path).unwrap_or_else(|_| {
        panic!("missing golden {}; regenerate with CW_REGEN_GOLDENS=1", path.display())
    });
    assert_eq!(
        rendered, expected,
        "golden mismatch for azimuthal ring labels — if intended, regenerate with CW_REGEN_GOLDENS=1"
    );
}
