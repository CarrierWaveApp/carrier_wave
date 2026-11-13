//! DX Summit (dxsummit.fi) spot model + response parsing. Port of the
//! decoding half of Sweep's `DXSummitClient.swift` / `DXWebSpot.swift`.

use chrono::{DateTime, NaiveDateTime};
use serde::Deserialize;

/// A DX Summit API response element.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct DxSummitSpot {
    pub id: i64,
    #[serde(rename = "dx_call")]
    pub dx_call: String,
    #[serde(rename = "de_call")]
    pub de_call: String,
    /// Frequency in kHz.
    pub frequency: f64,
    /// Timestamp string — either RFC 3339 or timezone-less
    /// `2026-03-24T01:49:15` (assumed UTC), matching the Swift dual-format
    /// date decoder.
    pub time: String,
    #[serde(default)]
    pub info: Option<String>,
    #[serde(rename = "dx_country", default)]
    pub dx_country: Option<String>,
    #[serde(rename = "dx_latitude", default)]
    pub dx_latitude: Option<f64>,
    #[serde(rename = "dx_longitude", default)]
    pub dx_longitude: Option<f64>,
    #[serde(rename = "de_latitude", default)]
    pub de_latitude: Option<f64>,
    #[serde(rename = "de_longitude", default)]
    pub de_longitude: Option<f64>,
}

impl DxSummitSpot {
    /// Unix epoch seconds parsed from `time`, or `None` if unparseable.
    pub fn timestamp_epoch_seconds(&self) -> Option<i64> {
        if let Ok(dt) = DateTime::parse_from_rfc3339(&self.time) {
            return Some(dt.timestamp());
        }
        if let Ok(naive) = NaiveDateTime::parse_from_str(&self.time, "%Y-%m-%dT%H:%M:%S") {
            return Some(naive.and_utc().timestamp());
        }
        None
    }

    /// Parse the bare JSON array the API returns.
    pub fn parse_response(json: &str) -> Option<Vec<DxSummitSpot>> {
        serde_json::from_str(json).ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Captured from http://www.dxsummit.fi/api/v1/spots?limit=3 (2026-07-02).
    const FIXTURE: &str = r#"[{"info": "tnx 73", "dx_country": "Spain", "de_latitude": 52.77, "dx_latitude": 38.87, "dx_longitude": 0.97, "de_call": "M7BYF", "frequency": 14259.0, "time": "2026-07-02T15:27:39", "dx_call": "EA5EE", "de_longitude": 1.47, "id": 67354373}, {"info": null, "dx_country": "Switzerland", "de_latitude": 41.15, "dx_latitude": 46.87, "dx_longitude": -8.12, "de_call": "KC2OSR", "frequency": 18150.4, "time": "2026-07-02T15:27:23", "dx_call": "HB9WWA", "de_longitude": 74.53, "id": 67354371}]"#;

    #[test]
    fn parses_live_fixture() {
        let spots = DxSummitSpot::parse_response(FIXTURE).unwrap();
        assert_eq!(spots.len(), 2);
        assert_eq!(spots[0].dx_call, "EA5EE");
        assert_eq!(spots[0].de_call, "M7BYF");
        assert_eq!(spots[0].frequency, 14_259.0);
        assert_eq!(spots[0].info.as_deref(), Some("tnx 73"));
        assert_eq!(spots[1].info, None);
        assert_eq!(spots[1].dx_country.as_deref(), Some("Switzerland"));
    }

    #[test]
    fn timestamp_parses_both_formats() {
        let spots = DxSummitSpot::parse_response(FIXTURE).unwrap();
        // Timezone-less → assume UTC.
        let epoch = spots[0].timestamp_epoch_seconds().unwrap();
        let round_trip = DateTime::from_timestamp(epoch, 0).unwrap();
        assert_eq!(round_trip.format("%Y-%m-%dT%H:%M:%S").to_string(), "2026-07-02T15:27:39");

        // RFC 3339 with offset also parses.
        let mut spot = spots[0].clone();
        spot.time = "2026-07-02T15:27:39+02:00".to_string();
        assert_eq!(spot.timestamp_epoch_seconds().unwrap(), epoch - 7_200);

        spot.time = "garbage".to_string();
        assert_eq!(spot.timestamp_epoch_seconds(), None);
    }
}
