//! HamQSL solar-XML model + parser. Port of `HamQSLClient.swift`'s `parse`
//! pipeline plus the `HamQSLSolarData` / `HamQSLBandCondition` models.
//!
//! The Swift client regex-extracts `<tag>value</tag>` plus the
//! `<band name="X" time="day|night">...</band>` table. We do the same with
//! `quick-xml`, accumulating per-tag values as we walk the document.

use chrono::{DateTime, Utc};
use quick_xml::events::Event;
use quick_xml::Reader;
use std::collections::{HashMap, HashSet};
use thiserror::Error;

/// Day/night propagation condition for one HamQSL band group.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct HamQslBandCondition {
    /// Band group name, e.g. "80m-40m", "30m-20m", "17m-15m", "12m-10m".
    pub band_name: String,
    /// Daytime condition: "Good", "Fair", or "Poor".
    pub day: String,
    /// Nighttime condition: "Good", "Fair", or "Poor".
    pub night: String,
}

/// Structured solar conditions + per-band propagation conditions from HamQSL.
#[derive(Debug, Clone, PartialEq)]
pub struct HamQslSolarData {
    pub k_index: f64,
    pub a_index: Option<i32>,
    pub solar_flux: Option<f64>,
    pub sunspots: Option<i32>,
    pub band_conditions: Vec<HamQslBandCondition>,
    pub timestamp: DateTime<Utc>,
}

impl HamQslSolarData {
    /// Overall propagation rating based on K-index. Matches Swift exactly.
    pub fn propagation_rating(&self) -> &'static str {
        match self.k_index {
            k if k < 2.0 => "Excellent",
            k if k < 3.0 => "Good",
            k if k < 4.0 => "Fair",
            k if k < 5.0 => "Poor",
            _ => "Very Poor",
        }
    }
}

#[derive(Debug, Error)]
pub enum HamQslParseError {
    #[error("XML parse error: {0}")]
    Xml(String),
}

/// Parse a HamQSL `solarxml.php` payload. `now` becomes the result's
/// `timestamp` (Swift sets it to `Date()` at parse time).
pub fn parse(xml: &str, now: DateTime<Utc>) -> Result<HamQslSolarData, HamQslParseError> {
    let mut reader = Reader::from_str(xml);
    reader.config_mut().trim_text(true);

    let mut buf = Vec::new();

    // Stack of tag names so we know where text events belong.
    let mut stack: Vec<String> = Vec::new();
    // Most-recent scalar values keyed by lowercased tag name (HamQSL is
    // case-insensitive in practice; Swift uses `.caseInsensitive` regex).
    let mut scalars: HashMap<String, String> = HashMap::new();

    // Per band-group day/night conditions. Built up as we walk.
    let mut days: HashMap<String, String> = HashMap::new();
    let mut nights: HashMap<String, String> = HashMap::new();
    let mut current_band: Option<(String, String)> = None; // (name, time)

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(start)) | Ok(Event::Empty(start)) => {
                let name = String::from_utf8_lossy(start.name().as_ref()).to_lowercase();
                if name == "band" {
                    let mut band_name = None;
                    let mut band_time = None;
                    for attr in start.attributes().with_checks(false).flatten() {
                        let key = String::from_utf8_lossy(attr.key.as_ref()).to_lowercase();
                        let value = attr
                            .unescape_value()
                            .map(|c| c.into_owned())
                            .unwrap_or_default();
                        if key == "name" {
                            band_name = Some(value);
                        } else if key == "time" {
                            band_time = Some(value);
                        }
                    }
                    if let (Some(n), Some(t)) = (band_name, band_time) {
                        current_band = Some((n, t));
                    }
                }
                stack.push(name);
            }
            Ok(Event::End(end)) => {
                let _ = stack.pop();
                let name = String::from_utf8_lossy(end.name().as_ref()).to_lowercase();
                if name == "band" {
                    current_band = None;
                }
            }
            Ok(Event::Text(text)) => {
                let raw = match text.unescape() {
                    Ok(cow) => cow.into_owned(),
                    Err(_) => continue,
                };
                let value = raw.trim().to_string();
                if value.is_empty() {
                    continue;
                }
                let Some(top) = stack.last() else { continue };
                if top == "band" {
                    if let Some((name, time)) = &current_band {
                        if time.eq_ignore_ascii_case("day") {
                            days.insert(name.clone(), value);
                        } else {
                            nights.insert(name.clone(), value);
                        }
                    }
                } else {
                    scalars.insert(top.clone(), value);
                }
            }
            Ok(Event::Eof) => break,
            Err(err) => return Err(HamQslParseError::Xml(err.to_string())),
            _ => {}
        }
        buf.clear();
    }

    let k_index = scalars
        .get("kindex")
        .and_then(|s| s.parse::<f64>().ok())
        .unwrap_or(0.0);
    let a_index = scalars.get("aindex").and_then(|s| s.parse::<i32>().ok());
    let solar_flux = scalars.get("solarflux").and_then(|s| s.parse::<f64>().ok());
    let sunspots = scalars.get("sunspots").and_then(|s| s.parse::<i32>().ok());

    let band_conditions = collect_band_conditions(days, nights);

    Ok(HamQslSolarData {
        k_index,
        a_index,
        solar_flux,
        sunspots,
        band_conditions,
        timestamp: now,
    })
}

fn collect_band_conditions(
    days: HashMap<String, String>,
    nights: HashMap<String, String>,
) -> Vec<HamQslBandCondition> {
    // Standard order Swift uses; anything else falls in afterwards, sorted.
    const STANDARD_ORDER: &[&str] = &["80m-40m", "30m-20m", "17m-15m", "12m-10m"];

    let all_names: HashSet<String> = days.keys().chain(nights.keys()).cloned().collect();
    let mut conditions = Vec::new();
    let standard_set: HashSet<&str> = STANDARD_ORDER.iter().copied().collect();

    for name in STANDARD_ORDER {
        if all_names.contains(*name) {
            conditions.push(HamQslBandCondition {
                band_name: (*name).to_string(),
                day: days.get(*name).cloned().unwrap_or_else(|| "N/A".into()),
                night: nights.get(*name).cloned().unwrap_or_else(|| "N/A".into()),
            });
        }
    }

    let mut leftovers: Vec<String> = all_names
        .iter()
        .filter(|n| !standard_set.contains(n.as_str()))
        .cloned()
        .collect();
    leftovers.sort();
    for name in leftovers {
        conditions.push(HamQslBandCondition {
            day: days.get(&name).cloned().unwrap_or_else(|| "N/A".into()),
            night: nights.get(&name).cloned().unwrap_or_else(|| "N/A".into()),
            band_name: name,
        });
    }

    conditions
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    const SAMPLE: &str = r##"
        <solar>
            <solardata>
                <kindex>3.33</kindex>
                <aindex>12</aindex>
                <solarflux>145</solarflux>
                <sunspots>87</sunspots>
                <calculatedconditions>
                    <band name="80m-40m" time="day">Good</band>
                    <band name="80m-40m" time="night">Fair</band>
                    <band name="30m-20m" time="day">Good</band>
                    <band name="30m-20m" time="night">Good</band>
                    <band name="17m-15m" time="day">Fair</band>
                    <band name="17m-15m" time="night">Poor</band>
                    <band name="12m-10m" time="day">Poor</band>
                    <band name="12m-10m" time="night">Poor</band>
                </calculatedconditions>
            </solardata>
        </solar>
    "##;

    #[test]
    fn parses_solar_scalars_and_band_table() {
        let now = Utc.with_ymd_and_hms(2026, 6, 13, 12, 0, 0).unwrap();
        let data = parse(SAMPLE, now).unwrap();

        assert!((data.k_index - 3.33).abs() < 1e-6);
        assert_eq!(data.a_index, Some(12));
        assert_eq!(data.solar_flux, Some(145.0));
        assert_eq!(data.sunspots, Some(87));
        assert_eq!(data.propagation_rating(), "Fair");

        let names: Vec<&str> = data
            .band_conditions
            .iter()
            .map(|c| c.band_name.as_str())
            .collect();
        assert_eq!(names, vec!["80m-40m", "30m-20m", "17m-15m", "12m-10m"]);

        let twenty = &data.band_conditions[1];
        assert_eq!(twenty.day, "Good");
        assert_eq!(twenty.night, "Good");
    }

    #[test]
    fn unknown_band_groups_fall_after_standard_order_sorted() {
        let xml = r##"
            <solar>
                <kindex>0</kindex>
                <band name="6m" time="day">Good</band>
                <band name="6m" time="night">Poor</band>
                <band name="80m-40m" time="day">Fair</band>
                <band name="80m-40m" time="night">Fair</band>
                <band name="2m" time="day">Good</band>
            </solar>
        "##;
        let data = parse(xml, Utc::now()).unwrap();
        let names: Vec<&str> = data
            .band_conditions
            .iter()
            .map(|c| c.band_name.as_str())
            .collect();
        assert_eq!(names, vec!["80m-40m", "2m", "6m"]);
        let two_m = data
            .band_conditions
            .iter()
            .find(|c| c.band_name == "2m")
            .unwrap();
        assert_eq!(two_m.day, "Good");
        assert_eq!(two_m.night, "N/A");
    }

    #[test]
    fn defaults_when_kindex_missing() {
        let data = parse("<solar></solar>", Utc::now()).unwrap();
        assert_eq!(data.k_index, 0.0);
        assert_eq!(data.propagation_rating(), "Excellent");
    }
}
