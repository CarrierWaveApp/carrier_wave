//! SOTA spot model + helpers. Port of `SOTASpot.swift` (parsing half) and the
//! deterministic, non-HTTP pieces of `SOTAClient.swift`.

use chrono::{DateTime, NaiveDateTime, Utc};
use serde::Deserialize;

/// A spot from the SOTAwatch API representing an active SOTA activator.
/// JSON keys mirror the Swift `Decodable` property names.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct SotaSpot {
    pub id: i64,
    /// Nullable in the wild — the API's injected deprecation-notice entry
    /// ships `"userID": null`.
    #[serde(rename = "userID", default)]
    pub user_id: Option<i64>,
    #[serde(rename = "activatorCallsign")]
    pub activator_callsign: String,
    /// Nullable in the wild (see `user_id`).
    #[serde(rename = "activatorName", default)]
    pub activator_name: Option<String>,
    /// Swift remaps `callsign` → `spotterCallsign` via `CodingKeys`.
    #[serde(rename = "callsign")]
    pub spotter_callsign: String,
    #[serde(rename = "associationCode")]
    pub association_code: String,
    #[serde(rename = "summitCode")]
    pub summit_code: String,
    #[serde(rename = "summitDetails")]
    pub summit_details: String,
    /// MHz as a string, e.g. "14.062".
    pub frequency: String,
    pub mode: String,
    #[serde(default)]
    pub comments: Option<String>,
    #[serde(rename = "highlightColor", default)]
    pub highlight_color: Option<String>,
    /// ISO-8601 without timezone (UTC), e.g. "2026-02-26T17:51:41".
    #[serde(rename = "timeStamp")]
    pub time_stamp: String,
}

impl SotaSpot {
    /// Frequency in MHz, parsed from the API string.
    pub fn frequency_mhz(&self) -> Option<f64> {
        self.frequency.trim().parse::<f64>().ok()
    }

    /// Frequency in kHz, useful for band derivation.
    pub fn frequency_khz(&self) -> Option<f64> {
        self.frequency_mhz().map(|mhz| mhz * 1_000.0)
    }

    /// Parsed UTC timestamp. SOTAwatch returns ISO-8601 without a `Z` suffix.
    pub fn parsed_timestamp(&self) -> Option<DateTime<Utc>> {
        parse_sota_timestamp(&self.time_stamp)
    }

    /// Full summit reference combining association and summit codes
    /// (e.g. "W4C/CM-001").
    pub fn full_summit_reference(&self) -> String {
        format!("{}/{}", self.association_code, self.summit_code)
    }

    /// Points value extracted from `summitDetails` (e.g.
    /// "Mount Mitchell, 2037m, 10 points" -> 10).
    pub fn points(&self) -> u32 {
        for part in self.summit_details.split(',') {
            let trimmed = part.trim().to_lowercase();
            if trimmed.ends_with("points") || trimmed.ends_with("point") {
                if let Some(first) = trimmed.split_whitespace().next() {
                    if let Ok(value) = first.parse::<u32>() {
                        return value;
                    }
                }
            }
        }
        0
    }

    /// Summit name extracted from `summitDetails` (text before first comma).
    pub fn summit_name(&self) -> &str {
        match self.summit_details.split_once(',') {
            Some((head, _)) => head.trim(),
            None => self.summit_details.trim(),
        }
    }

    /// Normalize a callsign: uppercase and drop any `/`-suffix. Mirrors
    /// `POTASpot::normalize_callsign` so S2S/P2P matching stays consistent.
    pub fn normalize_callsign(callsign: &str) -> String {
        let upper = callsign.to_uppercase();
        match upper.find('/') {
            Some(idx) => upper[..idx].to_string(),
            None => upper,
        }
    }

    /// Unix epoch seconds from `parsed_timestamp()`, for FFI consumers.
    pub fn timestamp_epoch_seconds(&self) -> Option<f64> {
        self.parsed_timestamp().map(|dt| dt.timestamp() as f64)
    }

    /// Whether this is the synthetic entry SOTAwatch injects at the head of
    /// the deprecated `/spots` response to announce the API shutdown. It is
    /// not a real spot and must never surface in the UI.
    pub fn is_deprecation_notice(&self) -> bool {
        self.activator_callsign == "DEPRECATED" && self.association_code == "DEPRECATED"
    }

    /// Parse a SOTAwatch spots response (bare JSON array `[SotaSpot]`).
    /// Returns `None` if the body is not valid JSON or not an array.
    /// Individual elements are decoded tolerantly — see [`Self::from_values`].
    pub fn parse_response(json: &str) -> Option<Vec<SotaSpot>> {
        let values = serde_json::from_str::<Vec<serde_json::Value>>(json).ok()?;
        Some(Self::from_values(values))
    }

    /// Decode raw JSON array elements, skipping entries that fail to decode
    /// (one malformed spot must not take down the whole feed) and the API's
    /// injected deprecation notice.
    pub fn from_values(values: Vec<serde_json::Value>) -> Vec<SotaSpot> {
        values
            .into_iter()
            .filter_map(|value| serde_json::from_value::<SotaSpot>(value).ok())
            .filter(|spot| !spot.is_deprecation_notice())
            .collect()
    }
}

/// Validation error from the deterministic half of `SOTAClient.postSpot`.
#[derive(Debug, PartialEq, Eq, thiserror::Error)]
pub enum SotaSpotPostError {
    #[error("Invalid SOTA summit code (expected ASSOC/REGION-NUM, e.g. W6/CT-021)")]
    InvalidSummitCode,
    #[error("Invalid frequency for SOTA spot")]
    InvalidFrequency,
}

/// Body the SOTAwatch POST endpoint expects. Built deterministically — the
/// transport just serializes this to JSON. Matches the Swift `body` dictionary.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct SotaSpotPost {
    #[serde(rename = "activatorCallsign")]
    pub activator_callsign: String,
    #[serde(rename = "spotterCallsign")]
    pub spotter_callsign: String,
    #[serde(rename = "summitCode")]
    pub summit_code: String,
    pub frequency: String,
    pub mode: String,
    pub comments: String,
}

impl SotaSpotPost {
    /// Build (and validate) a POST body. Mirrors `SOTAClient.postSpot`.
    pub fn build(
        activator_callsign: &str,
        spotter_callsign: &str,
        summit_code: &str,
        frequency_mhz: f64,
        mode: &str,
        comments: Option<&str>,
    ) -> Result<Self, SotaSpotPostError> {
        let trimmed_summit = summit_code.trim().to_uppercase();
        if !(trimmed_summit.contains('/') && trimmed_summit.contains('-')) {
            return Err(SotaSpotPostError::InvalidSummitCode);
        }
        if frequency_mhz <= 0.0 || frequency_mhz.is_nan() {
            return Err(SotaSpotPostError::InvalidFrequency);
        }
        Ok(Self {
            activator_callsign: activator_callsign.to_uppercase(),
            spotter_callsign: spotter_callsign.to_uppercase(),
            summit_code: trimmed_summit,
            frequency: format_frequency(frequency_mhz),
            mode: mode.to_uppercase(),
            comments: comments.unwrap_or("").to_string(),
        })
    }
}

/// Format a frequency for the SOTA spot endpoint. SOTAwatch expects MHz as a
/// decimal string with trailing zeros trimmed (e.g. 14.062 stays "14.062",
/// not "14.06200").
pub fn format_frequency(mhz: f64) -> String {
    let mut formatted = format!("{:.5}", mhz);
    while formatted.ends_with('0') {
        formatted.pop();
    }
    if formatted.ends_with('.') {
        formatted.pop();
    }
    formatted
}

fn parse_sota_timestamp(value: &str) -> Option<DateTime<Utc>> {
    // RFC 3339 with `Z` or offset.
    if let Ok(dt) = DateTime::parse_from_rfc3339(value) {
        return Some(dt.with_timezone(&Utc));
    }
    // Bare "YYYY-MM-DDTHH:MM:SS" (the common SOTAwatch shape) — assume UTC.
    if let Ok(naive) = NaiveDateTime::parse_from_str(value, "%Y-%m-%dT%H:%M:%S") {
        return Some(naive.and_utc());
    }
    if let Ok(naive) = NaiveDateTime::parse_from_str(value, "%Y-%m-%dT%H:%M:%S%.f") {
        return Some(naive.and_utc());
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r#"{
        "id": 123,
        "userID": 5,
        "activatorCallsign": "W6JY/P",
        "activatorName": "Jay",
        "callsign": "K2ABC",
        "associationCode": "W4C",
        "summitCode": "CM-001",
        "summitDetails": "Mount Mitchell, 2037m, 10 points",
        "frequency": "14.062",
        "mode": "CW",
        "comments": "QRT soon",
        "highlightColor": "yellow",
        "timeStamp": "2026-02-26T17:51:41"
    }"#;

    #[test]
    fn decodes_codable_keys() {
        let spot: SotaSpot = serde_json::from_str(SAMPLE).unwrap();
        assert_eq!(spot.spotter_callsign, "K2ABC");
        assert_eq!(spot.frequency_mhz(), Some(14.062));
        assert_eq!(spot.frequency_khz(), Some(14_062.0));
        assert_eq!(spot.full_summit_reference(), "W4C/CM-001");
        assert_eq!(spot.points(), 10);
        assert_eq!(spot.summit_name(), "Mount Mitchell");
    }

    #[test]
    fn timestamp_without_z_is_treated_as_utc() {
        let spot: SotaSpot = serde_json::from_str(SAMPLE).unwrap();
        let ts = spot.parsed_timestamp().unwrap();
        assert_eq!(ts.to_rfc3339(), "2026-02-26T17:51:41+00:00");
    }

    #[test]
    fn timestamp_with_z_is_parsed_too() {
        let mut spot: SotaSpot = serde_json::from_str(SAMPLE).unwrap();
        spot.time_stamp = "2026-02-26T17:51:41Z".to_string();
        assert!(spot.parsed_timestamp().is_some());
    }

    #[test]
    fn normalize_callsign_drops_portable_suffix() {
        assert_eq!(SotaSpot::normalize_callsign("w6jy/p"), "W6JY");
        assert_eq!(SotaSpot::normalize_callsign("K2ABC"), "K2ABC");
    }

    #[test]
    fn format_frequency_strips_trailing_zeros() {
        assert_eq!(format_frequency(14.062), "14.062");
        assert_eq!(format_frequency(7.0), "7");
        assert_eq!(format_frequency(14.06200), "14.062");
    }

    #[test]
    fn build_post_uppercases_and_validates() {
        let post = SotaSpotPost::build("w6jy", "k2abc", "w6/ct-021", 14.062, "cw", Some("hi"))
            .unwrap();
        assert_eq!(post.activator_callsign, "W6JY");
        assert_eq!(post.spotter_callsign, "K2ABC");
        assert_eq!(post.summit_code, "W6/CT-021");
        assert_eq!(post.frequency, "14.062");
        assert_eq!(post.mode, "CW");
        assert_eq!(post.comments, "hi");
    }

    #[test]
    fn build_post_rejects_bad_summit() {
        assert_eq!(
            SotaSpotPost::build("W6JY", "W6JY", "W6CT021", 14.062, "CW", None),
            Err(SotaSpotPostError::InvalidSummitCode)
        );
    }

    #[test]
    fn build_post_rejects_zero_frequency() {
        assert_eq!(
            SotaSpotPost::build("W6JY", "W6JY", "W6/CT-021", 0.0, "CW", None),
            Err(SotaSpotPostError::InvalidFrequency)
        );
    }

    #[test]
    fn timestamp_epoch_seconds_from_naive_utc() {
        let spot: SotaSpot = serde_json::from_str(SAMPLE).unwrap();
        // "2026-02-26T17:51:41" UTC → 1_772_128_301
        // Verified: 2026-01-01T00Z=1_767_225_600 + 56d*86400 + 64301s
        let epoch = spot.timestamp_epoch_seconds().unwrap();
        assert!((epoch - 1_772_128_301.0).abs() < 1.0);
    }

    #[test]
    fn parse_response_bare_array() {
        let json = format!("[{SAMPLE}]");
        let spots = SotaSpot::parse_response(&json).unwrap();
        assert_eq!(spots.len(), 1);
        assert_eq!(spots[0].id, 123);
        assert_eq!(spots[0].activator_callsign, "W6JY/P");
    }

    #[test]
    fn parse_response_rejects_non_array() {
        assert!(SotaSpot::parse_response(r#"{"not":"an-array"}"#).is_none());
    }

    /// Verbatim shape of the entry the deprecated SOTAwatch endpoint injects
    /// at the head of every response (null userID/activatorName, sentinel id).
    const DEPRECATION_NOTICE: &str = r#"{
        "id": 9999999999999999,
        "userID": null,
        "timeStamp": "2026-08-28T00:35:51",
        "comments": "This API endpoint is deprecated…",
        "callsign": "DEPRECATED",
        "associationCode": "DEPRECATED",
        "summitCode": "DEPRECATED",
        "activatorCallsign": "DEPRECATED",
        "activatorName": null,
        "frequency": "",
        "mode": "",
        "summitDetails": "DEPRECATED",
        "highlightColor": null
    }"#;

    #[test]
    fn parse_response_skips_deprecation_notice_and_keeps_real_spots() {
        let json = format!("[{DEPRECATION_NOTICE},{SAMPLE}]");
        let spots = SotaSpot::parse_response(&json).unwrap();
        assert_eq!(spots.len(), 1);
        assert_eq!(spots[0].id, 123);
        assert_eq!(spots[0].user_id, Some(5));
    }

    #[test]
    fn parse_response_skips_malformed_elements() {
        let json = format!(r#"[{{"id":"not-a-number"}},{SAMPLE}]"#);
        let spots = SotaSpot::parse_response(&json).unwrap();
        assert_eq!(spots.len(), 1);
        assert_eq!(spots[0].id, 123);
    }

    #[test]
    fn null_user_id_and_activator_name_decode() {
        let spot: SotaSpot = serde_json::from_str(DEPRECATION_NOTICE).unwrap();
        assert_eq!(spot.user_id, None);
        assert_eq!(spot.activator_name, None);
        assert!(spot.is_deprecation_notice());
    }
}
