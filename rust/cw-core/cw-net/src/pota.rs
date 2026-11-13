//! POTA spot model + helpers. Port of `POTASpot.swift` (parsing half) and
//! `POTAClient+Spot.swift`'s `POTASpotRequest` (the respot POST body).

use chrono::{DateTime, NaiveDateTime};
use serde::Deserialize;

/// A spot from the POTA spotting system. Field names mirror the Swift
/// `Decodable` property names (which are the JSON keys).
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct PotaSpot {
    #[serde(rename = "spotId")]
    pub spot_id: i64,
    pub activator: String,
    pub frequency: String,
    pub mode: String,
    pub reference: String,
    #[serde(rename = "parkName", default)]
    pub park_name: Option<String>,
    #[serde(rename = "spotTime")]
    pub spot_time: String,
    pub spotter: String,
    #[serde(default)]
    pub comments: Option<String>,
    #[serde(default)]
    pub source: Option<String>,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(rename = "locationDesc", default)]
    pub location_desc: Option<String>,
}

impl PotaSpot {
    /// Frequency string parsed to kHz.
    pub fn frequency_khz(&self) -> Option<f64> {
        self.frequency.trim().parse::<f64>().ok()
    }

    /// RBN-sourced spots are automated.
    /// Park name for display. The rebuilt POTA API (October 2026) leaves
    /// `parkName` null and carries the park name in `name`; older responses
    /// filled `parkName`. Prefer `parkName`, fall back to `name`.
    pub fn park_display_name(&self) -> Option<&str> {
        self.park_name
            .as_deref()
            .filter(|s| !s.trim().is_empty())
            .or_else(|| self.name.as_deref().filter(|s| !s.trim().is_empty()))
    }

    pub fn is_automated_spot(&self) -> bool {
        self.source.as_deref().map(|s| s.to_uppercase() == "RBN").unwrap_or(false)
    }

    pub fn is_human_spot(&self) -> bool {
        !self.is_automated_spot()
    }

    /// US state abbreviation from a POTA `locationDesc` (e.g. "US-WY" → "WY").
    pub fn parse_state(location_desc: Option<&str>) -> Option<String> {
        let desc = location_desc?;
        let parts: Vec<&str> = desc.split('-').collect();
        if parts.len() >= 2 && parts[0] == "US" {
            Some(parts[1].to_string())
        } else {
            None
        }
    }

    /// Normalize a callsign: uppercase and drop any `/`-suffix.
    pub fn normalize_callsign(callsign: &str) -> String {
        let upper = callsign.to_uppercase();
        match upper.find('/') {
            Some(idx) => upper[..idx].to_string(),
            None => upper,
        }
    }

    /// Whether this spot is a self-spot for `user_callsign`.
    pub fn is_self_spot(&self, user_callsign: &str) -> bool {
        Self::normalize_callsign(user_callsign) == Self::normalize_callsign(&self.activator)
    }

    /// Unix epoch seconds parsed from `spot_time`. POTA timestamps are UTC
    /// without a timezone suffix (e.g. "2026-02-03T20:43:36").
    pub fn timestamp_epoch_seconds(&self) -> Option<f64> {
        if let Ok(dt) = DateTime::parse_from_rfc3339(&self.spot_time) {
            return Some(dt.timestamp() as f64);
        }
        for fmt in ["%Y-%m-%dT%H:%M:%S%.f", "%Y-%m-%dT%H:%M:%S"] {
            if let Ok(naive) = NaiveDateTime::parse_from_str(&self.spot_time, fmt) {
                return Some(naive.and_utc().timestamp() as f64);
            }
        }
        None
    }

    /// Parse a POTA spots response (bare JSON array `[PotaSpot]`).
    /// Returns `None` if the body is not valid JSON or not a spot array.
    pub fn parse_response(json: &str) -> Option<Vec<PotaSpot>> {
        serde_json::from_str::<Vec<PotaSpot>>(json).ok()
    }
}

/// Request body for `POST /spot` — a hunter respot (or activator self-spot).
/// Field names mirror the Swift `POTASpotRequest`; the endpoint accepts
/// unauthenticated posts (the spotter callsign rides in the body).
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct PotaSpotPost {
    pub activator: String,
    pub spotter: String,
    pub frequency: String,
    pub reference: String,
    pub mode: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub comments: Option<String>,
}

impl PotaSpotPost {
    /// Build a normalized respot body. Mirrors iOS `POTAClient.postRespot`:
    /// callsigns/mode/reference uppercased, frequency rendered as a kHz
    /// string. Returns `None` when the park reference doesn't look like
    /// `K-1234`/`US-1234` or the frequency is not positive.
    pub fn respot(
        activator: &str,
        spotter: &str,
        reference: &str,
        frequency_khz: f64,
        mode: &str,
        comments: Option<String>,
    ) -> Option<Self> {
        if !Self::is_valid_reference(reference) || frequency_khz <= 0.0 {
            return None;
        }
        Some(Self {
            activator: activator.trim().to_uppercase(),
            spotter: spotter.trim().to_uppercase(),
            frequency: Self::format_frequency_khz(frequency_khz),
            reference: reference.trim().to_uppercase(),
            mode: mode.trim().to_uppercase(),
            comments: comments.filter(|c| !c.trim().is_empty()),
        })
    }

    /// Park reference format check; the Swift pattern
    /// `^[A-Za-z]{1,4}-\d{1,6}$` without pulling in a regex crate.
    pub fn is_valid_reference(reference: &str) -> bool {
        let Some((prefix, digits)) = reference.trim().split_once('-') else {
            return false;
        };
        (1..=4).contains(&prefix.len())
            && prefix.chars().all(|c| c.is_ascii_alphabetic())
            && (1..=6).contains(&digits.len())
            && digits.chars().all(|c| c.is_ascii_digit())
    }

    /// kHz string for the POTA API — one decimal when whole ("14060.0"),
    /// three otherwise ("14060.250"). Mirrors iOS `formatFrequency`.
    pub fn format_frequency_khz(khz: f64) -> String {
        if khz == khz.round() {
            format!("{khz:.1}")
        } else {
            format!("{khz:.3}")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r#"{
        "spotId": 12345,
        "activator": "W1AW/P",
        "frequency": "14074",
        "mode": "FT8",
        "reference": "K-1234",
        "parkName": "Some Park",
        "spotTime": "2026-02-03T20:43:36",
        "spotter": "K2ABC",
        "comments": "QRT soon",
        "source": "RBN",
        "locationDesc": "US-WY"
    }"#;

    #[test]
    fn decodes_and_derives() {
        let spot: PotaSpot = serde_json::from_str(SAMPLE).unwrap();
        assert_eq!(spot.spot_id, 12345);
        assert_eq!(spot.frequency_khz(), Some(14_074.0));
        assert!(spot.is_automated_spot());
        assert!(!spot.is_human_spot());
        assert_eq!(PotaSpot::parse_state(spot.location_desc.as_deref()), Some("WY".to_string()));
    }

    #[test]
    fn missing_optionals_default_to_none() {
        let json = r#"{
            "spotId": 1, "activator": "N0CALL", "frequency": "7040",
            "mode": "CW", "reference": "K-1", "spotTime": "t", "spotter": "X"
        }"#;
        let spot: PotaSpot = serde_json::from_str(json).unwrap();
        assert!(spot.comments.is_none());
        assert!(spot.source.is_none());
        assert!(spot.is_human_spot());
    }

    #[test]
    fn park_display_name_prefers_park_name_then_name() {
        let spot: PotaSpot = serde_json::from_str(SAMPLE).unwrap();
        assert_eq!(spot.park_display_name(), Some("Some Park"));

        // Shape served by the rebuilt pota.app (2026-10): parkName null, name set.
        let json = r#"{
            "spotId": 59348762, "activator": "EA2CYT", "frequency": "14056", "mode": "CW",
            "reference": "ES-1329", "parkName": null, "spotTime": "2026-10-23T18:01:20",
            "spotter": "EA2CYT", "comments": "QRT", "source": "Ham2K Portable Logger",
            "name": "Zadorra ibaia / Rio Zadorra Natura 2000", "locationDesc": "ES-PV"
        }"#;
        let spot: PotaSpot = serde_json::from_str(json).unwrap();
        assert!(spot.park_name.is_none());
        assert_eq!(spot.park_display_name(), Some("Zadorra ibaia / Rio Zadorra Natura 2000"));

        let json = r#"{"spotId": 1, "activator": "N0CALL", "frequency": "7040",
            "mode": "CW", "reference": "K-1", "spotTime": "t", "spotter": "X", "parkName": ""}"#;
        let spot: PotaSpot = serde_json::from_str(json).unwrap();
        assert_eq!(spot.park_display_name(), None);
    }

    #[test]
    fn callsign_normalization_and_self_spot() {
        assert_eq!(PotaSpot::normalize_callsign("w1aw/p"), "W1AW");
        let spot: PotaSpot = serde_json::from_str(SAMPLE).unwrap();
        assert!(spot.is_self_spot("W1AW"));
        assert!(!spot.is_self_spot("K2ABC"));
    }

    #[test]
    fn timestamp_epoch_seconds_without_z() {
        let spot: PotaSpot = serde_json::from_str(SAMPLE).unwrap();
        // "2026-02-03T20:43:36" UTC → 1_770_151_416
        assert_eq!(spot.timestamp_epoch_seconds(), Some(1_770_151_416.0));
    }

    #[test]
    fn parse_response_bare_array() {
        let json = format!("[{SAMPLE}]");
        let spots = PotaSpot::parse_response(&json).unwrap();
        assert_eq!(spots.len(), 1);
        assert_eq!(spots[0].spot_id, 12345);
    }

    #[test]
    fn parse_response_rejects_invalid_json() {
        assert!(PotaSpot::parse_response(r#"{"not":"an-array"}"#).is_none());
    }

    #[test]
    fn respot_normalizes_and_serializes() {
        let post = PotaSpotPost::respot("k2g/p", "w6jy", "us-1234", 14_060.0, "cw", None)
            .expect("valid respot");
        assert_eq!(post.activator, "K2G/P");
        assert_eq!(post.spotter, "W6JY");
        assert_eq!(post.reference, "US-1234");
        assert_eq!(post.frequency, "14060.0");
        assert_eq!(post.mode, "CW");
        // `comments: nil` must be absent, matching Swift's encodeIfPresent.
        let json = serde_json::to_string(&post).unwrap();
        assert!(!json.contains("comments"));
        assert!(json.contains(r#""frequency":"14060.0""#));
    }

    #[test]
    fn respot_formats_fractional_khz() {
        let post =
            PotaSpotPost::respot("K2G", "W6JY", "US-1234", 14_060.25, "CW", Some("qsy".into()))
                .expect("valid respot");
        assert_eq!(post.frequency, "14060.250");
        assert_eq!(post.comments.as_deref(), Some("qsy"));
    }

    #[test]
    fn respot_rejects_bad_inputs() {
        assert!(PotaSpotPost::respot("K2G", "W6JY", "US1234", 14_060.0, "CW", None).is_none());
        assert!(PotaSpotPost::respot("K2G", "W6JY", "US-", 14_060.0, "CW", None).is_none());
        assert!(PotaSpotPost::respot("K2G", "W6JY", "TOOBIG-1234", 14_060.0, "CW", None).is_none());
        assert!(PotaSpotPost::respot("K2G", "W6JY", "US-1234567", 14_060.0, "CW", None).is_none());
        assert!(PotaSpotPost::respot("K2G", "W6JY", "US-1234", 0.0, "CW", None).is_none());
    }

    #[test]
    fn respot_reference_validation_matches_swift_pattern() {
        for good in ["K-1234", "VE-1234", "US-1234", "us-0001", "ZLFF-1"] {
            assert!(PotaSpotPost::is_valid_reference(good), "{good} should be valid");
        }
        for bad in ["", "1234", "US_1234", "U5-1234", "-1234", "US-12a4"] {
            assert!(!PotaSpotPost::is_valid_reference(bad), "{bad} should be invalid");
        }
    }

    #[test]
    fn respot_blank_comments_dropped() {
        let post = PotaSpotPost::respot("K2G", "W6JY", "US-1234", 7_040.0, "CW", Some("  ".into()))
            .expect("valid respot");
        assert!(post.comments.is_none());
    }
}
