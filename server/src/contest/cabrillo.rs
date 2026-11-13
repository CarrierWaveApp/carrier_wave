//! Cabrillo 3.0 export for contest sessions.
//!
//! Generates a Cabrillo log from a [`ContestSession`]'s scored QSOs.
//! The QSO line layout is derived from the contest's `exchange` definition;
//! the `cabrillo` block on the contest provides the contest name.
//!
//! This is a deliberate, minimal implementation. Contests with non-standard
//! QSO line layouts will need a `qso_format` override (reserved for v0.4 of
//! the format).

use chrono::{DateTime, Utc};

use super::engine::{CallsignResolver, ContestSession, ScoredQso, StationConfig};
use super::types::{Cabrillo, Contest, ExchangeField};

/// Generate a Cabrillo 3.0 log for the given session.
pub fn export<R: CallsignResolver>(session: &ContestSession<R>) -> String {
    let contest = session.contest();
    let cabrillo = contest
        .cabrillo
        .as_ref()
        .cloned()
        .unwrap_or_else(default_cabrillo_block);

    let mut out = String::new();
    out.push_str(&format!("START-OF-LOG: {}\n", cabrillo.version));
    out.push_str(&format!("CONTEST: {}\n", cabrillo.contest_name));
    out.push_str(&format!("CALLSIGN: {}\n", session.station().callsign));
    out.push_str(&format!("CREATED-BY: carrierwave-contest-engine/0.3\n"));
    if !session.station().country.is_empty() {
        out.push_str(&format!("LOCATION: {}\n", session.station().country));
    }
    if let Some(grid) = &session.station().grid {
        out.push_str(&format!("GRID-LOCATOR: {}\n", grid));
    }

    for qso in session.qsos() {
        if qso.is_dupe {
            // Cabrillo logs may include dupes flagged with X-QSO; we just
            // skip them in this minimal implementation.
            continue;
        }
        out.push_str(&format_qso_line(qso, contest, session.station()));
        out.push('\n');
    }

    out.push_str("END-OF-LOG:\n");
    out
}

fn default_cabrillo_block() -> Cabrillo {
    Cabrillo {
        contest_name: "UNKNOWN".to_string(),
        version: "3.0".to_string(),
        qso_format: None,
    }
}

fn format_qso_line(
    qso: &ScoredQso,
    contest: &Contest,
    station: &StationConfig,
) -> String {
    let freq = freq_token(&qso.band);
    let mode = cabrillo_mode(&qso.mode);
    let (date, time) = format_timestamp(qso.timestamp_ms);

    let mut parts: Vec<String> = vec![
        "QSO:".to_string(),
        freq.to_string(),
        mode.to_string(),
        date,
        time,
        pad(&station.callsign, 13),
    ];

    // Sent exchange fields, in declaration order.
    for field in &contest.exchange.sent {
        parts.push(pad(&render_sent_field(field, qso, station), field_width(field)));
    }

    parts.push(pad(&qso.normalized_callsign, 13));

    // Received exchange fields, in declaration order.
    for field in &contest.exchange.received {
        parts.push(pad(&render_received_field(field, qso), field_width(field)));
    }

    parts.join(" ")
}

fn render_sent_field(field: &ExchangeField, qso: &ScoredQso, station: &StationConfig) -> String {
    if field.field_type == "serial_number" {
        return qso
            .sent_serial
            .map(|s| format!("{:03}", s))
            .unwrap_or_default();
    }
    if let Some(autofill) = &field.autofill {
        return autofill_value(autofill, station);
    }
    if let Some(default) = &field.default {
        return value_to_string(default);
    }
    if field.field_type == "signal_report" {
        return "599".to_string();
    }
    String::new()
}

fn render_received_field(field: &ExchangeField, qso: &ScoredQso) -> String {
    // We don't carry the original received-exchange map on ScoredQso (to
    // keep it small), so for v0.3 we render received fields from the
    // resolved station info where possible. The session can be extended
    // to retain the raw received map per QSO if richer Cabrillo output
    // is needed.
    match field.field_type.as_str() {
        "signal_report" => "599".to_string(),
        "cq_zone" => qso
            .resolved
            .as_ref()
            .map(|r| r.cq_zone.to_string())
            .unwrap_or_default(),
        "itu_zone" => qso
            .resolved
            .as_ref()
            .map(|r| r.itu_zone.to_string())
            .unwrap_or_default(),
        _ => String::new(),
    }
}

fn autofill_value(source: &str, station: &StationConfig) -> String {
    match source {
        "station_cq_zone" => station.cq_zone.to_string(),
        "station_itu_zone" => station.itu_zone.to_string(),
        "station_country" => station.country.clone(),
        "station_continent" => station.continent.clone(),
        "station_grid" => station.grid.clone().unwrap_or_default(),
        "station_state" => station.state.clone().unwrap_or_default(),
        "station_province" => station.province.clone().unwrap_or_default(),
        "station_section" => station.section.clone().unwrap_or_default(),
        "station_name" => station.name.clone().unwrap_or_default(),
        "station_power" => station.power.clone().unwrap_or_default(),
        "station_class" => station.class.clone().unwrap_or_default(),
        _ => String::new(),
    }
}

fn value_to_string(v: &serde_json::Value) -> String {
    match v {
        serde_json::Value::String(s) => s.clone(),
        serde_json::Value::Number(n) => n.to_string(),
        serde_json::Value::Bool(b) => b.to_string(),
        serde_json::Value::Null => String::new(),
        other => other.to_string(),
    }
}

fn field_width(field: &ExchangeField) -> usize {
    match field.field_type.as_str() {
        "signal_report" => 3,
        "cq_zone" | "itu_zone" => 3,
        "serial_number" => 4,
        "name" | "text" | "section_list" | "arrl_section" => 6,
        _ => 6,
    }
}

fn pad(s: &str, width: usize) -> String {
    if s.len() >= width {
        s.to_string()
    } else {
        let mut out = s.to_string();
        for _ in s.len()..width {
            out.push(' ');
        }
        out
    }
}

fn freq_token(band: &str) -> &'static str {
    // Cabrillo expects a frequency in kHz at the band's lower edge as a
    // sensible default when the actual frequency is not preserved.
    match band {
        "160m" => "1800",
        "80m" => "3500",
        "60m" => "5330",
        "40m" => "7000",
        "30m" => "10100",
        "20m" => "14000",
        "17m" => "18068",
        "15m" => "21000",
        "12m" => "24890",
        "10m" => "28000",
        "6m" => "50",
        "2m" => "144",
        "70cm" => "432",
        _ => "0",
    }
}

fn cabrillo_mode(mode: &str) -> &'static str {
    match mode.to_uppercase().as_str() {
        "CW" => "CW",
        "SSB" | "USB" | "LSB" => "PH",
        "FM" | "AM" => "PH",
        "RTTY" => "RY",
        _ => "DG",
    }
}

fn format_timestamp(ms: i64) -> (String, String) {
    let dt = DateTime::<Utc>::from_timestamp_millis(ms).unwrap_or_else(|| Utc::now());
    (
        dt.format("%Y-%m-%d").to_string(),
        dt.format("%H%M").to_string(),
    )
}
