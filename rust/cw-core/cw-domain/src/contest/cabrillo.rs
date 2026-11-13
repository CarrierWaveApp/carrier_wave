//! Cabrillo 3.0 log generator. Port of
//! `Services/Contest/CabrilloExportService.swift`.
//!
//! The Swift service consumes SwiftData `LoggingSession`/`QSO` objects; the
//! Rust port takes plain snapshots (`CabrilloSession` / `CabrilloQso`) that
//! the host maps from its store. Output is byte-identical.

use chrono::{DateTime, Utc};

use super::engine::ContestScoreSnapshot;
use super::model::{ContestDefinition, ContestExchangeField, ContestExchangeFieldType};

/// Session fields the header + QSO lines need.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct CabrilloSession {
    pub my_callsign: String,
    pub contest_operator: Option<String>,
    pub contest_bands: Option<String>,
    pub contest_power: Option<String>,
}

/// QSO fields the QSO lines need.
#[derive(Debug, Clone, PartialEq)]
pub struct CabrilloQso {
    pub callsign: String,
    /// MHz, as stored on the QSO.
    pub frequency: Option<f64>,
    pub mode: String,
    pub timestamp: DateTime<Utc>,
    pub rst_sent: Option<String>,
    pub rst_received: Option<String>,
    /// Space-joined stored exchange strings.
    pub contest_exchange_sent: Option<String>,
    pub contest_exchange_received: Option<String>,
    pub is_contest_qso: bool,
    pub is_hidden: bool,
}

/// Context needed to produce Cabrillo header values that are not directly
/// available from the contest definition or the session.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct CabrilloContext {
    pub category_id: Option<String>,
    pub overlay_category_id: Option<String>,
    pub power_class: Option<String>,
    pub assisted: Option<bool>,
    pub location: Option<String>,
    pub operators: Vec<String>,
    pub club_name: Option<String>,
    pub email: Option<String>,
}

/// Generate Cabrillo 3.0 log text from a contest session.
pub fn generate(
    session: &CabrilloSession,
    qsos: &[CabrilloQso],
    definition: &ContestDefinition,
    score: &ContestScoreSnapshot,
    context: &CabrilloContext,
) -> String {
    let mut lines: Vec<String> = Vec::new();
    append_header(&mut lines, session, definition, score, context);
    append_qso_lines(&mut lines, session, qsos, definition);
    lines.push("END-OF-LOG:".to_string());
    format!("{}\n", lines.join("\n"))
}

fn append_header(
    lines: &mut Vec<String>,
    session: &CabrilloSession,
    definition: &ContestDefinition,
    score: &ContestScoreSnapshot,
    context: &CabrilloContext,
) {
    let callsign = session.contest_operator.as_deref().unwrap_or(&session.my_callsign);
    let contest_name = definition
        .cabrillo
        .as_ref()
        .map(|cabrillo| cabrillo.contest_name.as_str())
        .or(definition.short_name.as_deref())
        .unwrap_or(&definition.id);
    let version = definition
        .cabrillo
        .as_ref()
        .map_or("3.0", |cabrillo| cabrillo.version.as_str());

    lines.push(format!("START-OF-LOG: {version}"));
    lines.push(format!("CONTEST: {contest_name}"));
    lines.push(format!("CALLSIGN: {callsign}"));
    lines.push(format!(
        "CATEGORY-OPERATOR: {}",
        context.category_id.as_deref().unwrap_or("SINGLE-OP")
    ));
    lines.push(format!(
        "CATEGORY-BAND: {}",
        session.contest_bands.as_deref().unwrap_or("ALL")
    ));
    lines.push(format!(
        "CATEGORY-POWER: {}",
        context
            .power_class
            .as_deref()
            .or(session.contest_power.as_deref())
            .unwrap_or("HIGH")
    ));
    lines.push(format!(
        "CATEGORY-MODE: {}",
        definition.modes.first().map_or("CW", String::as_str)
    ));
    let assisted = match context.assisted {
        Some(true) => "ASSISTED",
        Some(false) | None => "NON-ASSISTED",
    };
    lines.push(format!("CATEGORY-ASSISTED: {assisted}"));
    if let Some(overlay) = &context.overlay_category_id {
        lines.push(format!("CATEGORY-OVERLAY: {overlay}"));
    }
    if let Some(location) = &context.location {
        lines.push(format!("LOCATION: {location}"));
    }
    lines.push(format!("CLAIMED-SCORE: {}", score.final_score));
    let ops = if context.operators.is_empty() {
        callsign.to_string()
    } else {
        context.operators.join(" ")
    };
    lines.push(format!("OPERATORS: {ops}"));
    if let Some(club) = &context.club_name {
        if !club.is_empty() {
            lines.push(format!("CLUB: {club}"));
        }
    }
    if let Some(email) = &context.email {
        if !email.is_empty() {
            lines.push(format!("EMAIL: {email}"));
        }
    }
    lines.push("CREATED-BY: Carrier Wave".to_string());
}

fn append_qso_lines(
    lines: &mut Vec<String>,
    session: &CabrilloSession,
    qsos: &[CabrilloQso],
    definition: &ContestDefinition,
) {
    let mut sorted: Vec<&CabrilloQso> = qsos
        .iter()
        .filter(|qso| qso.is_contest_qso && !qso.is_hidden)
        .collect();
    sorted.sort_by_key(|qso| qso.timestamp);

    let my_call = session.contest_operator.as_deref().unwrap_or(&session.my_callsign);
    for qso in sorted {
        lines.push(format_qso_line(qso, my_call, definition));
    }
}

fn format_qso_line(qso: &CabrilloQso, my_call: &str, definition: &ContestDefinition) -> String {
    let freq = format_frequency(qso.frequency);
    let mode = format_mode(&qso.mode);
    let date = qso.timestamp.format("%Y-%m-%d");
    let time = qso.timestamp.format("%H%M");
    let my_call_pad = pad(my_call, 13);
    let his_call = pad(&qso.callsign, 13);

    let sent_block = exchange_tokens(
        &definition.exchange.sent,
        qso.contest_exchange_sent.as_deref(),
        qso.rst_sent.as_deref().unwrap_or("599"),
    )
    .join(" ");
    let received_block = exchange_tokens(
        &definition.exchange.received,
        qso.contest_exchange_received.as_deref(),
        qso.rst_received.as_deref().unwrap_or("599"),
    )
    .join(" ");

    format!("QSO: {freq} {mode} {date} {time} {my_call_pad} {sent_block} {his_call} {received_block}")
}

fn exchange_tokens(
    fields: &[ContestExchangeField],
    stored: Option<&str>,
    rst: &str,
) -> Vec<String> {
    let stored_tokens: Vec<&str> = stored.unwrap_or("").split(' ').filter(|token| !token.is_empty()).collect();
    let mut tokens: Vec<String> = Vec::new();
    let mut non_rst_index = 0;
    for field in fields {
        if field.field_type == ContestExchangeFieldType::SignalReport {
            tokens.push(pad(rst, 3));
            continue;
        }
        if non_rst_index < stored_tokens.len() {
            tokens.push(pad(stored_tokens[non_rst_index], 6));
        } else {
            tokens.push(pad("", 6));
        }
        non_rst_index += 1;
    }
    if tokens.is_empty() {
        tokens.push(pad(rst, 3));
    }
    tokens
}

fn format_frequency(freq_mhz: Option<f64>) -> String {
    let Some(freq) = freq_mhz else {
        return "     ".to_string();
    };
    let khz = (freq * 1_000.0) as i64;
    format!("{khz:5}")
}

fn format_mode(mode: &str) -> &'static str {
    match mode.to_uppercase().as_str() {
        "CW" => "CW",
        "SSB" | "USB" | "LSB" => "PH",
        "FT8" | "FT4" | "RTTY" | "PSK31" | "PSK63" => "RY",
        _ => "CW",
    }
}

/// Truncate-or-pad to an exact width, mirroring Swift's
/// `prefix(width).padding(toLength:width, withPad:" ")`.
fn pad(text: &str, width: usize) -> String {
    let truncated: String = text.chars().take(width).collect();
    format!("{truncated:<width$}")
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone;

    use super::*;
    use crate::contest::model::parse_definition;

    fn definition() -> ContestDefinition {
        parse_definition(
            r#"
            {
              "id": "sst",
              "name": "Slow Speed Test",
              "short_name": "SST",
              "modes": ["CW"],
              "bands": ["40m"],
              "schedule": {
                "type": "recurring_weekly",
                "sessions": [{ "day": "monday", "start_utc": "00:00", "duration_minutes": 60 }],
                "session_scoring": "independent"
              },
              "exchange": {
                "sent": [
                  { "name": "name", "type": "name", "label": "Name" },
                  { "name": "state", "type": "state_province", "label": "State" }
                ],
                "received": [
                  { "name": "name", "type": "name", "label": "Name" },
                  { "name": "state", "type": "state_province", "label": "State" }
                ]
              },
              "dupe_rules": { "scope": "session", "key": ["callsign"] },
              "scoring": { "phases": [] },
              "cabrillo": { "contest_name": "K1USN-SST", "version": "3.0" },
              "categories": []
            }
            "#,
        )
        .expect("decode")
    }

    fn qso(callsign: &str, minute: u32) -> CabrilloQso {
        CabrilloQso {
            callsign: callsign.to_string(),
            frequency: Some(7.038),
            mode: "CW".to_string(),
            timestamp: Utc.with_ymd_and_hms(2026, 7, 4, 0, minute, 0).unwrap(),
            rst_sent: None,
            rst_received: None,
            contest_exchange_sent: Some("JAY OR".to_string()),
            contest_exchange_received: Some("TIM MA".to_string()),
            is_contest_qso: true,
            is_hidden: false,
        }
    }

    #[test]
    fn generates_full_log() {
        let session = CabrilloSession {
            my_callsign: "W6JY".to_string(),
            contest_operator: None,
            contest_bands: None,
            contest_power: Some("LOW".to_string()),
        };
        let score = ContestScoreSnapshot { final_score: 42, ..Default::default() };
        let context = CabrilloContext {
            category_id: Some("SINGLE-OP".to_string()),
            location: Some("OR".to_string()),
            ..Default::default()
        };
        // Out of order on purpose: generator must sort by timestamp, and the
        // hidden QSO must be dropped.
        let mut hidden = qso("K9ZZZ", 1);
        hidden.is_hidden = true;
        let qsos = vec![qso("K1USN", 5), qso("N3ABC", 2), hidden];

        let output = generate(&session, &qsos, &definition(), &score, &context);
        // Exchange blocks are space-padded, so QSO lines carry trailing
        // spaces — build those two lines explicitly to keep them visible.
        let expected = [
            "START-OF-LOG: 3.0",
            "CONTEST: K1USN-SST",
            "CALLSIGN: W6JY",
            "CATEGORY-OPERATOR: SINGLE-OP",
            "CATEGORY-BAND: ALL",
            "CATEGORY-POWER: LOW",
            "CATEGORY-MODE: CW",
            "CATEGORY-ASSISTED: NON-ASSISTED",
            "LOCATION: OR",
            "CLAIMED-SCORE: 42",
            "OPERATORS: W6JY",
            "CREATED-BY: Carrier Wave",
            "QSO:  7038 CW 2026-07-04 0002 W6JY          JAY    OR     N3ABC         TIM    MA\u{20}\u{20}\u{20}\u{20}",
            "QSO:  7038 CW 2026-07-04 0005 W6JY          JAY    OR     K1USN         TIM    MA\u{20}\u{20}\u{20}\u{20}",
            "END-OF-LOG:",
        ]
        .join("\n")
            + "\n";
        assert_eq!(output, expected);
    }

    #[test]
    fn rst_fields_ride_the_rst_slot_not_stored_tokens() {
        let definition = parse_definition(
            r#"
            {
              "id": "wpx",
              "name": "WPX",
              "modes": ["CW"],
              "bands": ["40m"],
              "schedule": { "type": "fixed_dates", "occurrences": [] },
              "exchange": {
                "sent": [
                  { "name": "rst", "type": "signal_report", "label": "RST" },
                  { "name": "serial", "type": "serial_number", "label": "Serial" }
                ],
                "received": [
                  { "name": "rst", "type": "signal_report", "label": "RST" },
                  { "name": "serial", "type": "serial_number", "label": "Serial" }
                ]
              },
              "dupe_rules": { "scope": "contest", "key": ["callsign", "band"] },
              "scoring": { "phases": [] },
              "categories": []
            }
            "#,
        )
        .expect("decode");
        let session = CabrilloSession { my_callsign: "W6JY".to_string(), ..Default::default() };
        let mut record = qso("K1USN", 0);
        record.rst_sent = Some("579".to_string());
        record.rst_received = Some("559".to_string());
        record.contest_exchange_sent = Some("001".to_string());
        record.contest_exchange_received = Some("123".to_string());

        let output = generate(
            &session,
            &[record],
            &definition,
            &ContestScoreSnapshot::default(),
            &CabrilloContext::default(),
        );
        let qso_line = output.lines().find(|line| line.starts_with("QSO:")).unwrap();
        assert_eq!(
            qso_line,
            "QSO:  7038 CW 2026-07-04 0000 W6JY          579 001    K1USN         559 123   "
        );
    }

    #[test]
    fn missing_frequency_renders_blank_field() {
        let session = CabrilloSession { my_callsign: "W6JY".to_string(), ..Default::default() };
        let mut record = qso("K1USN", 0);
        record.frequency = None;
        let output = generate(
            &session,
            &[record],
            &definition(),
            &ContestScoreSnapshot::default(),
            &CabrilloContext::default(),
        );
        assert!(output.contains("QSO:       CW"));
    }
}
