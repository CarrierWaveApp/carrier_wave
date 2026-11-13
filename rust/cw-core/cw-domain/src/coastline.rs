//! World coastline polygons (Natural Earth 110m, public domain).
//!
//! Embedded from [`data/coastline.json`](../../data/coastline.json) via
//! `include_bytes!`. The JSON is the canonical source for the iOS/macOS apps
//! — the original Swift `CoastlineData.continents` array (6 `+PartN.swift`
//! extension files, ~4,982 (lat, lon) pairs across 103 polygons) was
//! converted one-shot from those Swift sources; the Swift side now
//! regenerates from this JSON instead of the other way around.
//!
//! - Source: <https://www.naturalearthdata.com/downloads/110m-physical-vectors/>
//! - License: Public Domain
//!
//! Each polygon is a closed ring of (lat, lon) pairs in degrees.

use std::sync::OnceLock;

const RAW_JSON: &[u8] = include_bytes!("../data/coastline.json");

/// All land polygon outlines as closed rings of (lat, lon) pairs.
pub fn continents() -> &'static [Vec<(f64, f64)>] {
    static PARSED: OnceLock<Vec<Vec<(f64, f64)>>> = OnceLock::new();
    PARSED
        .get_or_init(|| {
            let arrays: Vec<Vec<[f64; 2]>> =
                serde_json::from_slice(RAW_JSON).expect("coastline.json must be valid JSON");
            arrays
                .into_iter()
                .map(|polygon| {
                    polygon
                        .into_iter()
                        .map(|[lat, lon]| (lat, lon))
                        .collect()
                })
                .collect()
        })
        .as_slice()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn embedded_data_decodes_without_panic() {
        let polygons = continents();
        assert!(!polygons.is_empty(), "should have land polygons");
        // Per `data/coastline.json` extraction: 103 polygons / 4,982 pairs.
        assert_eq!(polygons.len(), 103);
        let total_pairs: usize = polygons.iter().map(|p| p.len()).sum();
        assert_eq!(total_pairs, 4_982);
    }

    #[test]
    fn coordinates_are_in_world_bounds() {
        for polygon in continents() {
            for &(lat, lon) in polygon {
                assert!((-90.0..=90.0).contains(&lat), "lat out of range: {lat}");
                assert!((-180.0..=180.0).contains(&lon), "lon out of range: {lon}");
            }
        }
    }

    #[test]
    fn cached_returns_same_pointer() {
        let a = continents();
        let b = continents();
        assert!(std::ptr::eq(a, b), "OnceLock should cache the slice");
    }
}
