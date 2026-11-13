//! Reverse Beacon Network spot model + response parsing. Port of
//! `RBNSpot.swift` (the `Decodable` types and derived properties).
//!
//! The carrier_wave activities server proxies RBN and returns one of three
//! JSON shapes, so [`RbnSpot::parse_response`] tries them in the same order as
//! the Swift `RBNClient.fetchSpots`: a callsign-echo response, a total-count
//! response, then a bare array.

use chrono::{DateTime, NaiveDateTime};
use cw_domain::BandUtilities;
use serde::Deserialize;

/// A spot from the Reverse Beacon Network. JSON keys mirror the Swift
/// `RBNSpot` `CodingKeys`.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct RbnSpot {
    pub id: i64,
    pub callsign: String,
    /// Frequency in kHz.
    pub frequency: f64,
    pub mode: String,
    /// ISO-8601 timestamp string, as the server emits it.
    pub timestamp: String,
    pub snr: i64,
    #[serde(default)]
    pub wpm: Option<i64>,
    pub spotter: String,
    #[serde(rename = "spotter_grid", default)]
    pub spotter_grid: Option<String>,
}

impl RbnSpot {
    /// Frequency in MHz.
    pub fn frequency_mhz(&self) -> f64 {
        self.frequency / 1_000.0
    }

    /// Band derived from frequency (empty string when out of any band, matching
    /// the Swift `band` computed property).
    pub fn band(&self) -> String {
        BandUtilities::derive_band(Some(self.frequency)).unwrap_or("").to_string()
    }

    /// Formatted frequency string, e.g. `14025.0 kHz`.
    pub fn formatted_frequency(&self) -> String {
        format!("{:.1} kHz", self.frequency)
    }

    /// Timestamp parsed to Unix epoch seconds, for sorting / age display on the
    /// consumer side. Accepts RFC-3339 (with offset/`Z`) and offset-less
    /// `%Y-%m-%dT%H:%M:%S` forms.
    pub fn timestamp_epoch_seconds(&self) -> Option<f64> {
        if let Ok(dt) = DateTime::parse_from_rfc3339(&self.timestamp) {
            return Some(dt.timestamp() as f64 + f64::from(dt.timestamp_subsec_millis()) / 1_000.0);
        }
        for fmt in ["%Y-%m-%dT%H:%M:%S%.f", "%Y-%m-%dT%H:%M:%S"] {
            if let Ok(naive) = NaiveDateTime::parse_from_str(&self.timestamp, fmt) {
                return Some(naive.and_utc().timestamp() as f64);
            }
        }
        None
    }

    /// Parse the three RBN response shapes in the same priority order as
    /// `RBNClient.fetchSpots`. Returns the contained spots, or `None` if the
    /// payload matches none of the shapes.
    pub fn parse_response(json: &str) -> Option<Vec<RbnSpot>> {
        if let Ok(resp) = serde_json::from_str::<RbnCallsignSpotsResponse>(json) {
            return Some(resp.spots);
        }
        if let Ok(resp) = serde_json::from_str::<RbnSpotsResponse>(json) {
            return Some(resp.spots);
        }
        serde_json::from_str::<Vec<RbnSpot>>(json).ok()
    }
}

/// Response from the `/spots` endpoint (with total count).
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct RbnSpotsResponse {
    pub total: i64,
    pub spots: Vec<RbnSpot>,
}

/// Response from the `/spots/:callsign` endpoint (with callsign echo).
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct RbnCallsignSpotsResponse {
    pub callsign: String,
    pub spots: Vec<RbnSpot>,
}

#[cfg(test)]
mod tests {
    use super::*;

    const SPOT: &str = r#"{
        "id": 42,
        "callsign": "W1AW",
        "frequency": 14025.0,
        "mode": "CW",
        "timestamp": "2026-02-03T20:43:36Z",
        "snr": 19,
        "wpm": 28,
        "spotter": "K2ABC",
        "spotter_grid": "FN20"
    }"#;

    #[test]
    fn decodes_and_derives() {
        let spot: RbnSpot = serde_json::from_str(SPOT).unwrap();
        assert_eq!(spot.id, 42);
        assert_eq!(spot.callsign, "W1AW");
        assert_eq!(spot.snr, 19);
        assert_eq!(spot.wpm, Some(28));
        assert_eq!(spot.spotter_grid.as_deref(), Some("FN20"));
        assert!((spot.frequency_mhz() - 14.025).abs() < 1e-9);
        assert_eq!(spot.band(), "20m");
        assert_eq!(spot.formatted_frequency(), "14025.0 kHz");
        assert_eq!(spot.timestamp_epoch_seconds(), Some(1_770_151_416.0));
    }

    #[test]
    fn optional_fields_default_to_none() {
        let json = r#"{
            "id": 1, "callsign": "N0CALL", "frequency": 7030.0, "mode": "CW",
            "timestamp": "2026-02-03T20:43:36", "snr": 5, "spotter": "X"
        }"#;
        let spot: RbnSpot = serde_json::from_str(json).unwrap();
        assert_eq!(spot.wpm, None);
        assert_eq!(spot.spotter_grid, None);
        assert_eq!(spot.band(), "40m");
        // Offset-less timestamp still parses.
        assert!(spot.timestamp_epoch_seconds().is_some());
    }

    #[test]
    fn parses_callsign_response_shape() {
        let json = format!(r#"{{"callsign":"W1AW","spots":[{SPOT}]}}"#);
        let spots = RbnSpot::parse_response(&json).unwrap();
        assert_eq!(spots.len(), 1);
        assert_eq!(spots[0].callsign, "W1AW");
    }

    #[test]
    fn parses_total_response_shape() {
        let json = format!(r#"{{"total":1,"spots":[{SPOT}]}}"#);
        let spots = RbnSpot::parse_response(&json).unwrap();
        assert_eq!(spots.len(), 1);
    }

    #[test]
    fn parses_bare_array_shape() {
        let json = format!("[{SPOT}]");
        let spots = RbnSpot::parse_response(&json).unwrap();
        assert_eq!(spots.len(), 1);
    }

    #[test]
    fn rejects_unrelated_json() {
        assert!(RbnSpot::parse_response(r#"{"unrelated":true}"#).is_none());
    }
}
