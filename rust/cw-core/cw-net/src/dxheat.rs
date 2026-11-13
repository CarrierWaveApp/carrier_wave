//! DXHeat (dxheat.com) spot model + response parsing. Port of the decoding
//! half of Sweep's `DXHeatClient.swift` / `DXWebSpot.swift`.

use chrono::NaiveDateTime;
use serde::Deserialize;

/// A DXHeat API response element. JSON keys are PascalCase.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct DxHeatSpot {
    #[serde(rename = "Nr")]
    pub nr: i64,
    #[serde(rename = "Spotter")]
    pub spotter: String,
    /// Frequency in kHz, as a string (e.g. `"7101.0"`).
    #[serde(rename = "Frequency")]
    pub frequency: String,
    #[serde(rename = "DXCall")]
    pub dx_call: String,
    /// `HH:MM` (UTC).
    #[serde(rename = "Time")]
    pub time: String,
    /// `DD/MM/YY`.
    #[serde(rename = "Date")]
    pub date: String,
    #[serde(rename = "Beacon", default)]
    pub beacon: Option<bool>,
    #[serde(rename = "MM", default)]
    pub mm: Option<bool>,
    #[serde(rename = "AM", default)]
    pub am: Option<bool>,
    #[serde(rename = "Valid", default)]
    pub valid: Option<bool>,
    #[serde(rename = "DXHomecall", default)]
    pub dx_homecall: Option<String>,
    #[serde(rename = "Comment", default)]
    pub comment: Option<String>,
    #[serde(rename = "Flag", default)]
    pub flag: Option<String>,
    #[serde(rename = "Band", default)]
    pub band: Option<f64>,
    #[serde(rename = "Mode", default)]
    pub mode: Option<String>,
    #[serde(rename = "Continent_dx", default)]
    pub continent_dx: Option<String>,
    #[serde(rename = "Continent_spotter", default)]
    pub continent_spotter: Option<String>,
    #[serde(rename = "DXLocator", default)]
    pub dx_locator: Option<String>,
    #[serde(rename = "LOTW", default)]
    pub lotw: Option<bool>,
    #[serde(rename = "LOTW_Date", default)]
    pub lotw_date: Option<String>,
    #[serde(rename = "EQSL", default)]
    pub eqsl: Option<bool>,
}

impl DxHeatSpot {
    /// Frequency in kHz parsed from the string field.
    pub fn frequency_khz(&self) -> Option<f64> {
        self.frequency.parse().ok()
    }

    /// Unix epoch seconds from the split `Date` (`DD/MM/YY`) + `Time`
    /// (`HH:MM`) fields, UTC.
    pub fn timestamp_epoch_seconds(&self) -> Option<i64> {
        let combined = format!("{} {}", self.date, self.time);
        NaiveDateTime::parse_from_str(&combined, "%d/%m/%y %H:%M")
            .ok()
            .map(|naive| naive.and_utc().timestamp())
    }

    /// Decode the HTML entities DXHeat embeds in comments (same fixed set
    /// as the Swift `decodeHTMLEntities`).
    pub fn decoded_comment(&self) -> String {
        self.comment
            .as_deref()
            .unwrap_or("")
            .replace("&#x27;", "'")
            .replace("&amp;", "&")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
    }

    /// Parse the bare JSON array the API returns.
    pub fn parse_response(json: &str) -> Option<Vec<DxHeatSpot>> {
        serde_json::from_str(json).ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Captured from https://dxheat.com/source/spots/?limit=2 (2026-07-02).
    const FIXTURE: &str = r#"[{"Nr": 67235960, "Spotter": "IU0IBY", "Frequency": "7101.0", "DXCall": "IR0WWA", "Time": "15:27", "Date": "02/07/26", "Beacon": false, "MM": false, "AM": false, "Valid": true, "DXHomecall": "IR0WWA", "Comment": "ssb wwa", "Flag": "it", "Band": 40.0, "Mode": "LSB", "Continent_dx": "EU", "Continent_spotter": "EU", "DXLocator": "JN61GV"}, {"Nr": 67235959, "Spotter": "M7BYF", "Frequency": "14259.0", "DXCall": "EA5EE", "Time": "15:27", "Date": "02/07/26", "Beacon": false, "MM": false, "AM": false, "Valid": true, "LOTW": true, "LOTW_Date": "06/20/2026", "EQSL": true, "DXHomecall": "EA5EE", "Comment": "tnx 73", "Flag": "es", "Band": 20.0, "Mode": "USB", "Continent_dx": "EU", "Continent_spotter": "EU", "DXLocator": "IN70NI"}]"#;

    #[test]
    fn parses_live_fixture() {
        let spots = DxHeatSpot::parse_response(FIXTURE).unwrap();
        assert_eq!(spots.len(), 2);
        assert_eq!(spots[0].dx_call, "IR0WWA");
        assert_eq!(spots[0].frequency_khz(), Some(7_101.0));
        assert_eq!(spots[0].mode.as_deref(), Some("LSB"));
        assert_eq!(spots[0].dx_locator.as_deref(), Some("JN61GV"));
        // LOTW absent on the first spot, present on the second.
        assert_eq!(spots[0].lotw, None);
        assert_eq!(spots[1].lotw, Some(true));
    }

    #[test]
    fn timestamp_from_split_date_time() {
        let spots = DxHeatSpot::parse_response(FIXTURE).unwrap();
        let epoch = spots[0].timestamp_epoch_seconds().unwrap();
        let dt = chrono::DateTime::from_timestamp(epoch, 0).unwrap();
        assert_eq!(dt.format("%Y-%m-%d %H:%M").to_string(), "2026-07-02 15:27");
    }

    #[test]
    fn html_entities_decode() {
        let mut spot = DxHeatSpot::parse_response(FIXTURE).unwrap().remove(0);
        spot.comment = Some("it&#x27;s &lt;loud&gt; &amp; &quot;clear&quot;".to_string());
        assert_eq!(spot.decoded_comment(), "it's <loud> & \"clear\"");
        spot.comment = None;
        assert_eq!(spot.decoded_comment(), "");
    }
}
