//! DXWatch (dxwatch.com) compact-array spot decoding. Port of Sweep's
//! `DXWatchResponseDecoder` in `DXWebSpot.swift`.
//!
//! The API returns `{"s": {id: [spotter, freq, dxCall, comment, time,
//! ?, bandCode, flag]}, "ci": {call: [prefix, entity, continent, flagCode,
//! cqZone, ituZone, lat, lon, state, grid, ?, dxccNumber, iotaRef]}}`.

use std::collections::HashMap;

use chrono::{DateTime, Datelike, NaiveDateTime, Utc};
use serde_json::Value;

/// A single DXWatch spot decoded from the compact array format.
#[derive(Debug, Clone, PartialEq)]
pub struct DxWatchSpot {
    pub id: String,
    pub spotter: String,
    /// Frequency in kHz.
    pub frequency: f64,
    pub dx_call: String,
    pub comment: Option<String>,
    /// `1409z 20 Mar` style, no year.
    pub time_string: String,
    pub band_code: i64,
    pub flag: i64,
}

/// Band code mapping from the DXWatch JS `g_b` table.
pub fn band_meters(band_code: i64) -> Option<&'static str> {
    Some(match band_code {
        3 => "160m",
        7 => "80m",
        12 => "40m",
        17 => "30m",
        22 => "20m",
        27 => "17m",
        32 => "15m",
        37 => "12m",
        42 => "10m",
        50 => "6m",
        62 => "2m",
        _ => return None,
    })
}

impl DxWatchSpot {
    /// Unix epoch seconds parsed from the yearless `HHMMz DD Mon` time,
    /// using `now`'s UTC year (Swift parity: the current year is appended
    /// before parsing).
    pub fn timestamp_epoch_seconds(&self, now: i64) -> Option<i64> {
        let year = DateTime::<Utc>::from_timestamp(now, 0)?.year();
        let with_year = format!("{} {}", self.time_string, year);
        NaiveDateTime::parse_from_str(&with_year, "%H%Mz %d %b %Y")
            .ok()
            .map(|naive| naive.and_utc().timestamp())
    }
}

/// DXWatch callsign info decoded from the `ci` array.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct DxWatchCallInfo {
    pub prefix: Option<String>,
    pub entity_name: Option<String>,
    pub continent: Option<String>,
    pub flag_code: Option<String>,
    pub cq_zone: Option<i64>,
    pub itu_zone: Option<i64>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub state: Option<String>,
    pub grid: Option<String>,
    pub dxcc_number: Option<String>,
    pub iota_ref: Option<String>,
}

/// DXWatch API top-level response.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct DxWatchResponse {
    pub spots: Vec<DxWatchSpot>,
    pub call_info: HashMap<String, DxWatchCallInfo>,
}

impl DxWatchResponse {
    /// Decode the compact array response. Returns `None` when the payload
    /// is not a JSON object (Swift throws `invalidFormat`); rows that fail
    /// per-element checks drop silently, matching `compactMap`.
    pub fn parse_response(json: &str) -> Option<DxWatchResponse> {
        // The response may have leading whitespace/newline — serde tolerates it.
        let root: Value = serde_json::from_str(json.trim_start()).ok()?;
        let root = root.as_object()?;

        let mut spots = Vec::new();
        if let Some(spots_obj) = root.get("s").and_then(Value::as_object) {
            for (id, values) in spots_obj {
                if let Some(values) = values.as_array() {
                    if let Some(spot) = decode_spot(id, values) {
                        spots.push(spot);
                    }
                }
            }
        }
        // Deterministic order (JSON object iteration order is unspecified).
        spots.sort_by(|a, b| a.id.cmp(&b.id));

        let mut call_info = HashMap::new();
        if let Some(ci_obj) = root.get("ci").and_then(Value::as_object) {
            for (callsign, values) in ci_obj {
                if let Some(values) = values.as_array() {
                    if let Some(info) = decode_call_info(values) {
                        call_info.insert(callsign.clone(), info);
                    }
                }
            }
        }

        Some(DxWatchResponse { spots, call_info })
    }
}

fn decode_spot(id: &str, values: &[Value]) -> Option<DxWatchSpot> {
    if values.len() < 7 {
        return None;
    }
    let spotter = values[0].as_str()?.to_string();
    let dx_call = values[2].as_str()?.to_string();
    let frequency = values[1].as_f64()?;
    let comment = values[3].as_str().filter(|c| !c.is_empty()).map(str::to_string);
    let time_string = values[4].as_str().unwrap_or("").to_string();
    let band_code = values[6].as_i64().unwrap_or(0);
    let flag = values.get(7).and_then(Value::as_i64).unwrap_or(0);

    Some(DxWatchSpot { id: id.to_string(), spotter, frequency, dx_call, comment, time_string, band_code, flag })
}

fn decode_call_info(values: &[Value]) -> Option<DxWatchCallInfo> {
    if values.len() < 10 {
        return None;
    }
    let str_at = |idx: usize| values.get(idx).and_then(Value::as_str).map(str::to_string);
    let non_empty = |v: Option<String>| v.filter(|s| !s.is_empty());

    Some(DxWatchCallInfo {
        prefix: str_at(0),
        entity_name: str_at(1),
        continent: str_at(2),
        flag_code: str_at(3),
        cq_zone: values.get(4).and_then(Value::as_i64),
        itu_zone: values.get(5).and_then(Value::as_i64),
        latitude: values.get(6).and_then(Value::as_f64),
        longitude: values.get(7).and_then(Value::as_f64),
        state: non_empty(str_at(8)),
        grid: non_empty(str_at(9)),
        dxcc_number: if values.len() > 11 { str_at(11) } else { None },
        iota_ref: if values.len() > 12 { non_empty(str_at(12)) } else { None },
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    // Trimmed capture from https://dxwatch.com/dxsd1/s.php?s=0&r=3 (2026-07-02).
    const FIXTURE: &str = r#"
{"s":{"60924348":["YB5NVE",14269,"SN0WWA","59","1527z 02 Jul",12,22,1],"60924349":["N2NRV",7260,"K2D","listening 5 up","1527z 02 Jul",6,12,1],"60924350":["EA5ET",7196,"EA5DF","","1527z 02 Jul",6,12]},"ci":{"SN0WWA":["SP","Poland","EU","pl",28,15,52.2708,21.0417,"","KO02MG","","232",""],"YB5NVE":["YB","Indonesia","OC","id",54,28,0.5208,101.375,"West Sumatra/Riau","OJ00QM"],"K2D":["K","USA","NA","us",5,8]}}"#;

    #[test]
    fn parses_live_fixture() {
        let response = DxWatchResponse::parse_response(FIXTURE).unwrap();
        assert_eq!(response.spots.len(), 3);
        let spot = &response.spots[0];
        assert_eq!(spot.id, "60924348");
        assert_eq!(spot.spotter, "YB5NVE");
        assert_eq!(spot.dx_call, "SN0WWA");
        assert_eq!(spot.frequency, 14_269.0);
        assert_eq!(spot.comment.as_deref(), Some("59"));
        assert_eq!(spot.band_code, 22);
        assert_eq!(spot.flag, 1);
        // Empty comment → None; missing flag → 0.
        assert_eq!(response.spots[2].comment, None);
        assert_eq!(response.spots[2].flag, 0);
    }

    #[test]
    fn call_info_decodes_and_drops_short_rows() {
        let response = DxWatchResponse::parse_response(FIXTURE).unwrap();
        let sn0 = &response.call_info["SN0WWA"];
        assert_eq!(sn0.prefix.as_deref(), Some("SP"));
        assert_eq!(sn0.entity_name.as_deref(), Some("Poland"));
        assert_eq!(sn0.cq_zone, Some(28));
        assert_eq!(sn0.grid.as_deref(), Some("KO02MG"));
        assert_eq!(sn0.state, None); // empty string → None
        assert_eq!(sn0.dxcc_number.as_deref(), Some("232"));
        assert_eq!(sn0.iota_ref, None); // empty string → None

        let yb5 = &response.call_info["YB5NVE"];
        assert_eq!(yb5.state.as_deref(), Some("West Sumatra/Riau"));
        assert_eq!(yb5.dxcc_number, None); // only 10 elements

        // K2D has 6 elements — below the 10 minimum → dropped.
        assert!(!response.call_info.contains_key("K2D"));
    }

    #[test]
    fn timestamp_uses_now_year() {
        let response = DxWatchResponse::parse_response(FIXTURE).unwrap();
        let now = DateTime::parse_from_rfc3339("2026-07-02T16:00:00Z").unwrap().timestamp();
        let epoch = response.spots[0].timestamp_epoch_seconds(now).unwrap();
        let dt = DateTime::<Utc>::from_timestamp(epoch, 0).unwrap();
        assert_eq!(dt.format("%Y-%m-%d %H:%M").to_string(), "2026-07-02 15:27");
    }

    #[test]
    fn rejects_non_object_payload() {
        assert!(DxWatchResponse::parse_response("[1,2,3]").is_none());
        assert!(DxWatchResponse::parse_response("garbage").is_none());
    }

    #[test]
    fn band_code_map() {
        assert_eq!(band_meters(22), Some("20m"));
        assert_eq!(band_meters(62), Some("2m"));
        assert_eq!(band_meters(99), None);
    }
}
