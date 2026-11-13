//! WWFF Spotline models + HTML scraping. Port of `WWFFClient.swift`'s parsers
//! plus the `WWFFSpot` / `WWFFAgendaItem` data models.
//!
//! Spotline removed its JSON API; the site now serves an HTML table where each
//! `<td>` carries a `data-label` attribute that names the column. Both the
//! spots page and the agenda page use the same layout — only the column set
//! differs.

use chrono::{DateTime, Datelike, NaiveDate, NaiveDateTime, TimeZone, Utc};
use std::collections::HashMap;

/// A spot from the WWFF Spotline service.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct WwffSpot {
    pub id: usize,
    pub activator: String,
    pub reference: String,
    pub reference_info: Option<String>,
    pub spotter: String,
    /// MHz as a string, e.g. "14.244".
    pub frequency: String,
    pub mode: String,
    pub comments: Option<String>,
    /// "RBN" for automated, `None` for human spotters.
    pub source: Option<String>,
    /// ISO-8601 timestamp (UTC).
    pub time: String,
}

impl WwffSpot {
    pub fn frequency_khz(&self) -> Option<f64> {
        self.frequency.parse::<f64>().ok().map(|mhz| mhz * 1_000.0)
    }

    pub fn parsed_timestamp(&self) -> Option<DateTime<Utc>> {
        parse_iso_timestamp(&self.time)
    }
}

/// A scheduled WWFF activation pulled from the Spotline agenda page.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct WwffAgendaItem {
    pub id: usize,
    pub activator: String,
    pub reference: String,
    pub reference_info: Option<String>,
    pub start_time: String,
    pub end_time: Option<String>,
    pub frequencies: Option<String>,
    pub modes: Option<String>,
    pub comments: Option<String>,
}

/// Parse spots from a Spotline HTML payload. Each `<tr>` exposes its columns
/// via `data-label` attributes; we key cells by label and pluck the ones we
/// care about, mirroring the Swift parser.
pub fn parse_spots_html(html: &str) -> Vec<WwffSpot> {
    let rows = extract_table_rows(html);
    let now = Utc::now();
    rows.into_iter()
        .enumerate()
        .filter_map(|(index, row)| {
            let cells = extract_cells(&row);

            let activator = cells.get("Activator").cloned().filter(|s| !s.is_empty())?;
            let reference = cells.get("Reference").cloned().filter(|s| !s.is_empty())?;

            let freq_khz = cells.get("Frequency").cloned().unwrap_or_default();
            let freq_mhz = match freq_khz.parse::<f64>() {
                Ok(khz) => format!("{:.3}", khz / 1_000.0),
                Err(_) => freq_khz,
            };

            let time_str = cells.get("Time").cloned().unwrap_or_default();
            let iso_time = build_iso_timestamp(&time_str, now);

            let info = cells.get("Info").cloned();
            let is_rbn = info.as_deref().is_some_and(|s| s.contains("RBN"));

            Some(WwffSpot {
                id: index,
                activator,
                reference,
                reference_info: cells.get("Ref Name").cloned(),
                spotter: cells.get("Spotter").cloned().unwrap_or_default(),
                frequency: freq_mhz,
                mode: cells.get("Mode").cloned().unwrap_or_default(),
                comments: info,
                source: if is_rbn { Some("RBN".to_string()) } else { None },
                time: iso_time,
            })
        })
        .collect()
}

/// Parse the Spotline agenda HTML.
pub fn parse_agenda_html(html: &str) -> Vec<WwffAgendaItem> {
    let rows = extract_table_rows(html);
    rows.into_iter()
        .enumerate()
        .filter_map(|(index, row)| {
            let cells = extract_cells(&row);

            let activator = cells.get("Callsign").cloned().filter(|s| !s.is_empty())?;
            let reference = cells.get("Reference").cloned().filter(|s| !s.is_empty())?;
            let start_time = cells
                .get("Start")
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())?;

            Some(WwffAgendaItem {
                id: index,
                activator,
                reference,
                reference_info: cells.get("Reference Name").cloned(),
                start_time,
                end_time: cells.get("End").map(|s| s.trim().to_string()),
                frequencies: cells.get("Band").cloned(),
                modes: cells.get("Mode").cloned(),
                comments: cells.get("Comments").cloned(),
            })
        })
        .collect()
}

fn extract_table_rows(html: &str) -> Vec<String> {
    let Some(tbody_start) = html.find("<tbody>") else {
        return Vec::new();
    };
    let after_tbody_open = tbody_start + "<tbody>".len();
    let Some(tbody_end_rel) = html[after_tbody_open..].find("</tbody>") else {
        return Vec::new();
    };
    let tbody = &html[after_tbody_open..after_tbody_open + tbody_end_rel];

    let mut rows = Vec::new();
    let mut cursor = 0;
    while let Some(start_rel) = tbody[cursor..].find("<tr") {
        let row_start = cursor + start_rel;
        // Find the end of this <tr...> tag and the matching </tr>.
        let Some(end_rel) = tbody[row_start..].find("</tr>") else {
            break;
        };
        let row_end = row_start + end_rel + "</tr>".len();
        rows.push(tbody[row_start..row_end].to_string());
        cursor = row_end;
    }
    rows
}

fn extract_cells(row: &str) -> HashMap<String, String> {
    const LABEL_MARKER: &str = "data-label=\"";
    let mut cells = HashMap::new();
    let mut cursor = 0;
    while let Some(label_start) = row[cursor..].find(LABEL_MARKER) {
        let after_quote = cursor + label_start + LABEL_MARKER.len();
        let Some(label_end_rel) = row[after_quote..].find('"') else {
            break;
        };
        let label_end = after_quote + label_end_rel;
        let label = &row[after_quote..label_end];

        let Some(tag_close_rel) = row[label_end..].find('>') else {
            break;
        };
        let content_start = label_end + tag_close_rel + 1;

        let Some(td_end_rel) = row[content_start..].find("</td>") else {
            break;
        };
        let content_end = content_start + td_end_rel;

        let raw_content = &row[content_start..content_end];
        let cleaned = strip_html(raw_content);
        cells.insert(label.to_string(), cleaned.trim().to_string());

        cursor = content_end + "</td>".len();
    }
    cells
}

fn strip_html(html: &str) -> String {
    let mut result = String::with_capacity(html.len());
    let mut chars = html.chars();
    while let Some(c) = chars.next() {
        if c == '<' {
            // Skip until the matching '>'. If there isn't one, drop the rest.
            let mut found_close = false;
            for inner in chars.by_ref() {
                if inner == '>' {
                    found_close = true;
                    break;
                }
            }
            if !found_close {
                break;
            }
        } else {
            result.push(c);
        }
    }
    result
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&nbsp;", " ")
}

/// Build an ISO-8601 UTC timestamp from Spotline's "HH:MM" time, anchored to
/// `today`. If the time can't be parsed, return the raw string unchanged
/// (matches the Swift fallback).
fn build_iso_timestamp(time_str: &str, today: DateTime<Utc>) -> String {
    let parts: Vec<&str> = time_str.split(':').collect();
    if parts.len() != 2 {
        return time_str.to_string();
    }
    let (Ok(hour), Ok(minute)) = (parts[0].parse::<u32>(), parts[1].parse::<u32>()) else {
        return time_str.to_string();
    };
    let Some(date) = NaiveDate::from_ymd_opt(today.year(), today.month(), today.day()) else {
        return time_str.to_string();
    };
    let Some(naive) = date.and_hms_opt(hour, minute, 0) else {
        return time_str.to_string();
    };
    Utc.from_utc_datetime(&naive)
        .format("%Y-%m-%dT%H:%M:%SZ")
        .to_string()
}

fn parse_iso_timestamp(value: &str) -> Option<DateTime<Utc>> {
    if let Ok(dt) = DateTime::parse_from_rfc3339(value) {
        return Some(dt.with_timezone(&Utc));
    }
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

    const SPOTS_HTML: &str = r##"
        <html><body><table><tbody>
        <tr>
            <td data-label="Time">17:30</td>
            <td data-label="Activator"><a href="x">W6JY</a></td>
            <td data-label="Frequency">14244</td>
            <td data-label="Mode">SSB</td>
            <td data-label="Reference">KFF-1234</td>
            <td data-label="Ref Name">Some Park</td>
            <td data-label="Spotter">K2ABC</td>
            <td data-label="Info">Loud signal</td>
        </tr>
        <tr>
            <td data-label="Time">17:31</td>
            <td data-label="Activator">N0CALL</td>
            <td data-label="Frequency">7023</td>
            <td data-label="Mode">CW</td>
            <td data-label="Reference">KFF-9999</td>
            <td data-label="Ref Name">Other Park</td>
            <td data-label="Spotter">RBN-W6KP</td>
            <td data-label="Info">RBN +12 dB</td>
        </tr>
        </tbody></table></body></html>
    "##;

    #[test]
    fn parses_spots_with_data_labels() {
        let spots = parse_spots_html(SPOTS_HTML);
        assert_eq!(spots.len(), 2);

        let first = &spots[0];
        assert_eq!(first.activator, "W6JY");
        assert_eq!(first.reference, "KFF-1234");
        assert_eq!(first.frequency, "14.244"); // kHz → MHz
        assert_eq!(first.mode, "SSB");
        assert_eq!(first.reference_info.as_deref(), Some("Some Park"));
        assert_eq!(first.spotter, "K2ABC");
        assert!(first.source.is_none());
        assert_eq!(first.comments.as_deref(), Some("Loud signal"));
        assert_eq!(first.frequency_khz(), Some(14_244.0));

        let second = &spots[1];
        assert_eq!(second.source.as_deref(), Some("RBN"));
        assert_eq!(second.frequency, "7.023");
    }

    #[test]
    fn rejects_rows_missing_required_cells() {
        let html = r#"
            <tbody>
            <tr><td data-label="Time">17:30</td><td data-label="Reference">KFF-1</td></tr>
            <tr><td data-label="Time">17:30</td><td data-label="Activator">W6JY</td></tr>
            </tbody>
        "#;
        assert!(parse_spots_html(html).is_empty());
    }

    #[test]
    fn agenda_extracts_required_columns() {
        let html = r#"
            <tbody>
            <tr>
                <td data-label="Status">Scheduled</td>
                <td data-label="Start">2026-06-14T18:00:00Z</td>
                <td data-label="End">2026-06-14T20:00:00Z</td>
                <td data-label="Callsign">W6JY/P</td>
                <td data-label="Reference">KFF-1234</td>
                <td data-label="Reference Name">Some Park</td>
                <td data-label="Band">14.244, 7.023</td>
                <td data-label="Mode">SSB, CW</td>
                <td data-label="Comments">Hello world &amp; friends</td>
            </tr>
            </tbody>
        "#;
        let items = parse_agenda_html(html);
        assert_eq!(items.len(), 1);
        let item = &items[0];
        assert_eq!(item.activator, "W6JY/P");
        assert_eq!(item.reference, "KFF-1234");
        assert_eq!(item.reference_info.as_deref(), Some("Some Park"));
        assert_eq!(item.start_time, "2026-06-14T18:00:00Z");
        assert_eq!(item.end_time.as_deref(), Some("2026-06-14T20:00:00Z"));
        assert_eq!(item.frequencies.as_deref(), Some("14.244, 7.023"));
        assert_eq!(item.modes.as_deref(), Some("SSB, CW"));
        assert_eq!(item.comments.as_deref(), Some("Hello world & friends"));
    }

    #[test]
    fn strip_html_drops_tags_and_decodes_entities() {
        assert_eq!(strip_html("<a href=\"x\">W6JY&nbsp;P</a>"), "W6JY P");
        assert_eq!(strip_html("a &amp; b"), "a & b");
    }

    #[test]
    fn build_iso_timestamp_anchors_to_today_utc() {
        let today = Utc.with_ymd_and_hms(2026, 6, 13, 23, 30, 0).unwrap();
        let iso = build_iso_timestamp("17:30", today);
        assert_eq!(iso, "2026-06-13T17:30:00Z");
    }

    #[test]
    fn build_iso_timestamp_falls_through_on_garbage() {
        let today = Utc::now();
        assert_eq!(build_iso_timestamp("not a time", today), "not a time");
    }
}
