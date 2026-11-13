//! NASA DONKI (Space Weather Database) models + parsing. Port of the data
//! shapes and pure helpers from `DONKIClient.swift`.
//!
//! DONKI returns three event kinds — geomagnetic storms, solar flares, and
//! CMEs — across `GST`, `FLR`, and `CME` endpoints. The Swift client wraps
//! them in a `DONKIEvent` enum and ranks each by radio impact. We do the same.
//!
//! Date parsing matches the Swift fallbacks: the API uses mixed shapes
//! (`Z`/no-`Z`, with/without seconds), so try the variants in the same order.

use chrono::{DateTime, Duration, NaiveDateTime, Utc};
use serde::Deserialize;

/// Severity of radio propagation impact from a space-weather event.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum RadioImpactLevel {
    None,
    Minor,
    Moderate,
    Severe,
    Extreme,
}

impl RadioImpactLevel {
    pub fn label(self) -> &'static str {
        match self {
            Self::None => "None",
            Self::Minor => "Minor",
            Self::Moderate => "Moderate",
            Self::Severe => "Severe",
            Self::Extreme => "Extreme",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct KpObservation {
    #[serde(rename = "observedTime")]
    pub observed_time: String,
    #[serde(rename = "kpIndex", default, deserialize_with = "deserialize_kp_index")]
    pub kp_index: Option<f64>,
    pub source: String,
}

/// `kpIndex` can arrive as a number or a quoted string in the DONKI feed —
/// accept both, falling back to `None` on anything else.
fn deserialize_kp_index<'de, D>(deserializer: D) -> Result<Option<f64>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    use serde::de::Error;
    use serde_json::Value;

    let value = Value::deserialize(deserializer)?;
    match value {
        Value::Null => Ok(None),
        Value::Number(n) => Ok(n.as_f64()),
        Value::String(s) => Ok(s.parse::<f64>().ok()),
        other => Err(D::Error::custom(format!(
            "unexpected kpIndex value: {other}"
        ))),
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct DonkiGeostorm {
    #[serde(rename = "gstID")]
    pub gst_id: String,
    #[serde(rename = "startTime")]
    pub start_time: String,
    #[serde(rename = "allKpIndex", default)]
    pub all_kp_index: Option<Vec<KpObservation>>,
    pub link: String,
}

impl DonkiGeostorm {
    /// Peak Kp value across all observations.
    pub fn peak_kp(&self) -> f64 {
        self.all_kp_index
            .as_ref()
            .map(|obs| {
                obs.iter()
                    .filter_map(|o| o.kp_index)
                    .fold(0.0_f64, f64::max)
            })
            .unwrap_or(0.0)
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct DonkiFlare {
    #[serde(rename = "flrID")]
    pub flr_id: String,
    #[serde(rename = "beginTime")]
    pub begin_time: String,
    #[serde(rename = "peakTime", default)]
    pub peak_time: Option<String>,
    #[serde(rename = "endTime", default)]
    pub end_time: Option<String>,
    #[serde(rename = "classType")]
    pub class_type: String,
    #[serde(rename = "sourceLocation", default)]
    pub source_location: Option<String>,
    pub link: String,
    #[serde(default)]
    pub note: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct CmeAnalysis {
    #[serde(default)]
    pub speed: Option<f64>,
    #[serde(rename = "halfAngle", default)]
    pub half_angle: Option<f64>,
    #[serde(rename = "type", default)]
    pub kind: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct DonkiCme {
    #[serde(rename = "activityID")]
    pub activity_id: String,
    #[serde(rename = "startTime")]
    pub start_time: String,
    #[serde(rename = "sourceLocation", default)]
    pub source_location: Option<String>,
    pub link: String,
    #[serde(default)]
    pub note: Option<String>,
    #[serde(rename = "cmeAnalyses", default)]
    pub cme_analyses: Option<Vec<CmeAnalysis>>,
}

impl DonkiCme {
    fn max_speed(&self) -> f64 {
        self.cme_analyses
            .as_ref()
            .map(|list| {
                list.iter()
                    .filter_map(|a| a.speed)
                    .fold(0.0_f64, f64::max)
            })
            .unwrap_or(0.0)
    }
}

/// Unified space-weather event covering geomagnetic storms, flares, and CMEs.
#[derive(Debug, Clone, PartialEq)]
pub enum DonkiEvent {
    Geostorm(DonkiGeostorm),
    Flare(DonkiFlare),
    Cme(DonkiCme),
}

impl DonkiEvent {
    pub fn event_id(&self) -> &str {
        match self {
            Self::Geostorm(g) => &g.gst_id,
            Self::Flare(f) => &f.flr_id,
            Self::Cme(c) => &c.activity_id,
        }
    }

    pub fn start_time_string(&self) -> &str {
        match self {
            Self::Geostorm(g) => &g.start_time,
            Self::Flare(f) => &f.begin_time,
            Self::Cme(c) => &c.start_time,
        }
    }

    pub fn start_date(&self) -> Option<DateTime<Utc>> {
        parse_donki_date(self.start_time_string())
    }

    pub fn link(&self) -> &str {
        match self {
            Self::Geostorm(g) => &g.link,
            Self::Flare(f) => &f.link,
            Self::Cme(c) => &c.link,
        }
    }

    pub fn note(&self) -> Option<&str> {
        match self {
            Self::Geostorm(_) => None,
            Self::Flare(f) => f.note.as_deref(),
            Self::Cme(c) => c.note.as_deref(),
        }
    }

    pub fn type_name(&self) -> &'static str {
        match self {
            Self::Geostorm(_) => "Geomagnetic Storm",
            Self::Flare(_) => "Solar Flare",
            Self::Cme(_) => "CME",
        }
    }

    pub fn summary(&self) -> String {
        match self {
            Self::Geostorm(g) => {
                let kp = g.peak_kp();
                format!("Kp {:.0} — HF blackouts, auroral absorption", kp)
            }
            Self::Flare(f) => format!("{} — Sudden ionospheric disturbance", f.class_type),
            Self::Cme(c) => {
                let speed = c
                    .cme_analyses
                    .as_ref()
                    .and_then(|list| list.iter().filter_map(|a| a.speed).reduce(f64::max));
                match speed {
                    Some(s) => format!("{} km/s — GST possible in 1-3 days", s as i64),
                    None => "Coronal mass ejection detected".to_string(),
                }
            }
        }
    }

    pub fn radio_impact(&self) -> RadioImpactLevel {
        match self {
            Self::Geostorm(g) => geostorm_impact(g.peak_kp()),
            Self::Flare(f) => flare_impact(&f.class_type),
            Self::Cme(c) => cme_impact(c.max_speed()),
        }
    }

    /// Computed expiry — when the event stops being worth showing.
    pub fn expiry_date(&self) -> Option<DateTime<Utc>> {
        match self {
            Self::Flare(f) => {
                if let Some(end) = f.end_time.as_deref().and_then(parse_donki_date) {
                    return Some(end + Duration::hours(1));
                }
                self.start_date().map(|d| d + Duration::hours(3))
            }
            Self::Geostorm(g) => {
                let last_obs = g
                    .all_kp_index
                    .as_ref()
                    .and_then(|obs| obs.iter().filter_map(|o| parse_donki_date(&o.observed_time)).max());
                last_obs
                    .or_else(|| self.start_date())
                    .map(|d| d + Duration::hours(24))
            }
            Self::Cme(_) => self.start_date().map(|d| d + Duration::hours(48)),
        }
    }

    pub fn is_active(&self, now: DateTime<Utc>) -> bool {
        match self.expiry_date() {
            Some(expiry) => now < expiry,
            None => true,
        }
    }
}

fn geostorm_impact(kp: f64) -> RadioImpactLevel {
    if kp < 5.0 {
        RadioImpactLevel::Minor
    } else if kp < 7.0 {
        RadioImpactLevel::Moderate
    } else if kp < 8.0 {
        RadioImpactLevel::Severe
    } else {
        RadioImpactLevel::Extreme
    }
}

fn flare_impact(class_type: &str) -> RadioImpactLevel {
    let upper = class_type.to_uppercase();
    if upper.starts_with('X') {
        RadioImpactLevel::Severe
    } else if upper.starts_with('M') {
        RadioImpactLevel::Moderate
    } else if upper.starts_with('C') {
        RadioImpactLevel::Minor
    } else {
        RadioImpactLevel::None
    }
}

fn cme_impact(max_speed: f64) -> RadioImpactLevel {
    if max_speed < 1_000.0 {
        RadioImpactLevel::Minor
    } else if max_speed < 1_500.0 {
        RadioImpactLevel::Moderate
    } else {
        RadioImpactLevel::Severe
    }
}

/// Format a date as `YYYY-MM-DD` for the DONKI query string.
pub fn format_query_date(date: DateTime<Utc>) -> String {
    date.format("%Y-%m-%d").to_string()
}

/// Parse a DONKI timestamp. The feed uses mixed shapes — with/without `Z`,
/// with/without seconds — so try each form in order. Returns `None` if none
/// matches.
pub fn parse_donki_date(value: &str) -> Option<DateTime<Utc>> {
    let with_z: String = if value.ends_with('Z') {
        value.to_string()
    } else {
        format!("{value}Z")
    };
    if let Ok(dt) = DateTime::parse_from_rfc3339(&with_z) {
        return Some(dt.with_timezone(&Utc));
    }
    if let Ok(naive) = NaiveDateTime::parse_from_str(&with_z, "%Y-%m-%dT%H:%MZ") {
        return Some(naive.and_utc());
    }
    if let Ok(naive) = NaiveDateTime::parse_from_str(value, "%Y-%m-%dT%H:%M:%S") {
        return Some(naive.and_utc());
    }
    if let Ok(naive) = NaiveDateTime::parse_from_str(value, "%Y-%m-%dT%H:%M") {
        return Some(naive.and_utc());
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn geostorm_decodes_kp_as_number_or_string() {
        let json = r#"{
            "gstID": "GST-1",
            "startTime": "2026-06-13T01:00:00Z",
            "link": "https://example",
            "allKpIndex": [
                {"observedTime": "2026-06-13T03:00:00Z", "kpIndex": 6, "source": "NOAA"},
                {"observedTime": "2026-06-13T06:00:00Z", "kpIndex": "7.33", "source": "NOAA"},
                {"observedTime": "2026-06-13T09:00:00Z", "kpIndex": null, "source": "NOAA"}
            ]
        }"#;
        let gst: DonkiGeostorm = serde_json::from_str(json).unwrap();
        assert!((gst.peak_kp() - 7.33).abs() < 1e-6);
    }

    #[test]
    fn flare_radio_impact_by_class() {
        let make = |class: &str| -> DonkiFlare {
            DonkiFlare {
                flr_id: "f".into(),
                begin_time: "2026-06-13T00:00:00Z".into(),
                peak_time: None,
                end_time: None,
                class_type: class.into(),
                source_location: None,
                link: "x".into(),
                note: None,
            }
        };
        assert_eq!(
            DonkiEvent::Flare(make("X1.0")).radio_impact(),
            RadioImpactLevel::Severe
        );
        assert_eq!(
            DonkiEvent::Flare(make("M2.5")).radio_impact(),
            RadioImpactLevel::Moderate
        );
        assert_eq!(
            DonkiEvent::Flare(make("C1.2")).radio_impact(),
            RadioImpactLevel::Minor
        );
        assert_eq!(
            DonkiEvent::Flare(make("B5.0")).radio_impact(),
            RadioImpactLevel::None
        );
    }

    #[test]
    fn cme_summary_and_expiry() {
        let cme = DonkiCme {
            activity_id: "CME-1".into(),
            start_time: "2026-06-13T00:00:00Z".into(),
            source_location: None,
            link: "x".into(),
            note: Some("hi".into()),
            cme_analyses: Some(vec![CmeAnalysis {
                speed: Some(1_200.0),
                half_angle: None,
                kind: None,
            }]),
        };
        let event = DonkiEvent::Cme(cme);
        assert_eq!(event.summary(), "1200 km/s — GST possible in 1-3 days");
        assert_eq!(event.radio_impact(), RadioImpactLevel::Moderate);

        let start = parse_donki_date("2026-06-13T00:00:00Z").unwrap();
        let expiry = event.expiry_date().unwrap();
        assert_eq!(expiry - start, Duration::hours(48));
    }

    #[test]
    fn geostorm_expiry_uses_last_observation() {
        let gst = DonkiGeostorm {
            gst_id: "GST-1".into(),
            start_time: "2026-06-13T00:00:00Z".into(),
            all_kp_index: Some(vec![KpObservation {
                observed_time: "2026-06-13T09:00:00Z".into(),
                kp_index: Some(6.0),
                source: "NOAA".into(),
            }]),
            link: "x".into(),
        };
        let event = DonkiEvent::Geostorm(gst);
        let expiry = event.expiry_date().unwrap();
        assert_eq!(expiry, Utc.with_ymd_and_hms(2026, 6, 14, 9, 0, 0).unwrap());
    }

    #[test]
    fn parse_donki_date_handles_variants() {
        assert!(parse_donki_date("2026-06-13T03:00:00Z").is_some());
        assert!(parse_donki_date("2026-06-13T03:00:00").is_some());
        assert!(parse_donki_date("2026-06-13T03:00Z").is_some());
        assert!(parse_donki_date("2026-06-13T03:00").is_some());
        assert!(parse_donki_date("nope").is_none());
    }

    #[test]
    fn format_query_date_is_yyyy_mm_dd() {
        let date = Utc.with_ymd_and_hms(2026, 6, 13, 0, 0, 0).unwrap();
        assert_eq!(format_query_date(date), "2026-06-13");
    }
}
