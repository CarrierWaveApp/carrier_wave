//! Logger command parsing — port of iOS `LoggerCommand+Parsing.swift`. The
//! command grammar (`FREQ`/`MODE`/`SPOT`/`RBN`/`HUNT`/… with all their aliases)
//! shared by both apps so it isn't reimplemented per platform. What each command
//! *does* (present a panel, self-spot to POTA, start a repeat timer) stays
//! host-side; this owns only the `text -> command` parse plus the shared help
//! text and the command-row catalog.

use crate::fmt;
use crate::quick_entry::{self, QuickEntryResult, RstOrder, SessionMetadataResult};

/// A parsed logger command. Port of the Swift `LoggerCommand` enum's data (the
/// presentation bits — `description`/`icon` — stay native).
#[derive(Debug, Clone, PartialEq)]
pub enum LoggerCommand {
    /// Change frequency in MHz (`14.060`, `FREQ 14.060`).
    Frequency(f64),
    /// Change mode (`MODE CW`, or a bare mode token).
    Mode(String),
    /// Self-spot to POTA with an optional comment and optional repeat interval.
    Spot { comment: Option<String>, repeat_minutes: Option<i32> },
    /// Stop the repeating spot timer (`SPOT STOP`).
    SpotStop,
    /// Show RBN spots for a callsign (`None` = the operator's own).
    Rbn { callsign: Option<String> },
    /// Show activator spots (`HUNT`/`POTA`/`SPOTS`).
    Hunt,
    /// Log a one-off QSO at a different freq/mode without changing the session.
    HuntLog(QuickEntryResult),
    P2p,
    S2s,
    Solar,
    Weather,
    Map,
    Hidden,
    Help,
    Note { text: String },
    Manual,
    Websdr,
    Band,
    Rig,
    Checklist,
    Radio,
    Replay,
    MyCall(String),
    /// Set session defaults from a callsign-less field line (`14.046 CW CN87`).
    SessionMetadata(SessionMetadataResult),
}

/// The mode tokens accepted as a bare `MODE` shortcut (port of the Swift
/// `validModes` set).
const VALID_MODES: [&str; 18] = [
    "CW", "SSB", "USB", "LSB", "AM", "FM", "FT8", "FT4", "RTTY", "PSK31", "PSK", "DIGITAL", "DATA",
    "SSTV", "JT65", "JT9", "WSPR", "JTTY",
];

/// Parse `input` into a command, or `None` when it isn't one (treat as a
/// callsign). Parsers run most-specific first, exactly as the Swift `parse` does.
pub fn parse(input: &str) -> Option<LoggerCommand> {
    let trimmed = input.trim();
    let upper = trimmed.to_uppercase();
    parse_frequency(trimmed, &upper)
        .or_else(|| parse_mode(trimmed, &upper))
        .or_else(|| parse_spot(trimmed, &upper))
        .or_else(|| parse_rbn(trimmed, &upper))
        .or_else(|| parse_hunt(trimmed, &upper))
        .or_else(|| parse_p2p(&upper))
        .or_else(|| parse_note(trimmed, &upper))
        .or_else(|| parse_my_call(trimmed, &upper))
        .or_else(|| parse_single_word(&upper))
        .or_else(|| parse_session_metadata(trimmed))
}

/// Drop the first `n` **characters** of `s` (mirrors Swift `dropFirst(n)`), then
/// return the remainder. Char-based so a multi-byte prefix can't panic.
fn drop_first(s: &str, n: usize) -> &str {
    match s.char_indices().nth(n) {
        Some((idx, _)) => &s[idx..],
        None => "",
    }
}

fn parse_frequency(trimmed: &str, upper: &str) -> Option<LoggerCommand> {
    if let Some(freq) = fmt::parse_frequency(trimmed) {
        return Some(LoggerCommand::Frequency(freq));
    }
    if upper.starts_with("FREQ ") || upper.starts_with("FREQ\t") {
        if let Some(freq) = fmt::parse_frequency(drop_first(trimmed, 5).trim()) {
            return Some(LoggerCommand::Frequency(freq));
        }
    }
    None
}

fn parse_mode(trimmed: &str, upper: &str) -> Option<LoggerCommand> {
    if upper.starts_with("MODE ") || upper.starts_with("MODE\t") {
        let mode = drop_first(trimmed, 5).trim().to_uppercase();
        return VALID_MODES.contains(&mode.as_str()).then_some(LoggerCommand::Mode(mode));
    }
    if VALID_MODES.contains(&upper) {
        return Some(LoggerCommand::Mode(upper.to_string()));
    }
    None
}

fn parse_spot(trimmed: &str, upper: &str) -> Option<LoggerCommand> {
    if upper == "SPOT" {
        return Some(LoggerCommand::Spot { comment: None, repeat_minutes: None });
    }
    if !upper.starts_with("SPOT ") {
        return None;
    }
    let rest = drop_first(trimmed, 5).trim().to_string();
    let rest_upper = rest.to_uppercase();

    if rest_upper == "STOP" {
        return Some(LoggerCommand::SpotStop);
    }

    // "SPOT [comment] REPEAT <minutes>" — last " REPEAT " wins (backwards search).
    if let Some(pos) = rest_upper.rfind(" REPEAT ") {
        let minutes_str = rest_upper[pos + " REPEAT ".len()..].trim();
        if let Ok(minutes) = minutes_str.parse::<i32>() {
            if minutes > 0 {
                let comment = rest[..pos].trim();
                return Some(LoggerCommand::Spot {
                    comment: (!comment.is_empty()).then(|| comment.to_string()),
                    repeat_minutes: Some(minutes),
                });
            }
        }
    }

    // "SPOT REPEAT <minutes>" (no comment).
    if rest_upper.starts_with("REPEAT ") {
        let minutes_str = drop_first(&rest, 7).trim();
        if let Ok(minutes) = minutes_str.parse::<i32>() {
            if minutes > 0 {
                return Some(LoggerCommand::Spot { comment: None, repeat_minutes: Some(minutes) });
            }
        }
    }

    Some(LoggerCommand::Spot { comment: (!rest.is_empty()).then_some(rest), repeat_minutes: None })
}

fn parse_rbn(trimmed: &str, upper: &str) -> Option<LoggerCommand> {
    if upper == "RBN" {
        return Some(LoggerCommand::Rbn { callsign: None });
    }
    if upper.starts_with("RBN ") {
        let callsign = drop_first(trimmed, 4).trim().to_uppercase();
        return Some(LoggerCommand::Rbn {
            callsign: (!callsign.is_empty()).then_some(callsign),
        });
    }
    None
}

fn parse_hunt(trimmed: &str, upper: &str) -> Option<LoggerCommand> {
    if upper == "HUNT" || upper == "POTA" || upper == "SPOTS" {
        return Some(LoggerCommand::Hunt);
    }
    if !upper.starts_with("HUNT ") {
        return None;
    }
    let rest = drop_first(trimmed, 5).trim();
    // A one-off log only when the user gave a callsign plus a freq or mode (the
    // missing one falls back to the session host-side). Otherwise bare HUNT.
    if let Some(result) = quick_entry::parse(rest, RstOrder::ReceivedFirst) {
        if !result.callsign.is_empty() && (result.frequency.is_some() || result.mode.is_some()) {
            return Some(LoggerCommand::HuntLog(result));
        }
    }
    Some(LoggerCommand::Hunt)
}

fn parse_p2p(upper: &str) -> Option<LoggerCommand> {
    match upper {
        "P2P" => Some(LoggerCommand::P2p),
        "S2S" => Some(LoggerCommand::S2s),
        _ => None,
    }
}

fn parse_note(trimmed: &str, upper: &str) -> Option<LoggerCommand> {
    if upper.starts_with("NOTE ") {
        let text = drop_first(trimmed, 5).trim();
        if !text.is_empty() {
            return Some(LoggerCommand::Note { text: text.to_string() });
        }
    }
    None
}

fn parse_my_call(trimmed: &str, upper: &str) -> Option<LoggerCommand> {
    if !upper.starts_with("MYCALL ") {
        return None;
    }
    let call = drop_first(trimmed, 7).trim().to_uppercase();
    (!call.is_empty()).then_some(LoggerCommand::MyCall(call))
}

fn parse_session_metadata(trimmed: &str) -> Option<LoggerCommand> {
    quick_entry::parse_session_metadata(trimmed).map(LoggerCommand::SessionMetadata)
}

fn parse_single_word(upper: &str) -> Option<LoggerCommand> {
    let command = match upper {
        "BAND" => LoggerCommand::Band,
        "RIG" => LoggerCommand::Rig,
        "SOLAR" => LoggerCommand::Solar,
        "WEATHER" | "WX" => LoggerCommand::Weather,
        "MAP" => LoggerCommand::Map,
        "HIDDEN" | "DELETED" => LoggerCommand::Hidden,
        "MANUAL" | "MAN" => LoggerCommand::Manual,
        "CHECKLIST" | "CL" => LoggerCommand::Checklist,
        "WEBSDR" | "SDR" | "REC" | "RECORD" | "SWL" => LoggerCommand::Websdr,
        "RADIO" | "CAT" | "RIG-BLE" => LoggerCommand::Radio,
        "REPLAY" | "AGN" | "HUH" => LoggerCommand::Replay,
        "QRT" => LoggerCommand::Spot { comment: Some("QRT".to_string()), repeat_minutes: None },
        "HELP" | "?" => LoggerCommand::Help,
        _ => return None,
    };
    Some(command)
}

/// One entry in the keyboard command row (port of the Swift `CommandRowItem`).
/// `key` is the stable identifier, `label` the button text, `insert` the text
/// inserted into the entry field when tapped, `description` the accessibility /
/// tooltip text. The icon stays platform-native (SF Symbols vs Material).
#[derive(Debug, Clone, PartialEq)]
pub struct CommandRowItem {
    pub key: String,
    pub label: String,
    pub insert: String,
    pub description: String,
}

fn row_item(key: &str, label: &str, description: &str) -> CommandRowItem {
    CommandRowItem {
        key: key.to_string(),
        label: label.to_string(),
        insert: label.to_string(),
        description: description.to_string(),
    }
}

/// The full command-row catalog (port of `CommandRowItem.allCases`), in display
/// order. Hosts pick a subset for the keyboard accessory.
pub fn command_row_catalog() -> Vec<CommandRowItem> {
    vec![
        row_item("rbn", "RBN", "Show RBN spots"),
        row_item("hunt", "HUNT", "Show activator spots"),
        row_item("p2p", "P2P", "Find park-to-park opportunities"),
        row_item("s2s", "S2S", "Find summit-to-summit opportunities"),
        row_item("solar", "SOLAR", "Show solar conditions"),
        row_item("weather", "WX", "Show weather conditions"),
        row_item("spot", "SPOT", "Self-spot to POTA"),
        row_item("map", "MAP", "Show session QSO map"),
        row_item("manual", "MANUAL", "Open radio manual"),
        row_item("help", "HELP", "Show command help"),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_bare_and_prefixed_frequency() {
        assert_eq!(parse("14.060"), Some(LoggerCommand::Frequency(14.06)));
        assert_eq!(parse("FREQ 14.060"), Some(LoggerCommand::Frequency(14.06)));
        assert_eq!(parse("freq 7040"), Some(LoggerCommand::Frequency(7.04)));
    }

    #[test]
    fn parses_mode_bare_and_prefixed_and_rejects_unknown() {
        assert_eq!(parse("CW"), Some(LoggerCommand::Mode("CW".into())));
        assert_eq!(parse("mode ssb"), Some(LoggerCommand::Mode("SSB".into())));
        assert_eq!(parse("MODE ZZ"), None); // unknown mode after MODE -> not a command
    }

    #[test]
    fn parses_spot_variants() {
        assert_eq!(parse("SPOT"), Some(LoggerCommand::Spot { comment: None, repeat_minutes: None }));
        assert_eq!(parse("spot stop"), Some(LoggerCommand::SpotStop));
        assert_eq!(
            parse("SPOT QRQ REPEAT 5"),
            Some(LoggerCommand::Spot { comment: Some("QRQ".into()), repeat_minutes: Some(5) })
        );
        assert_eq!(
            parse("SPOT REPEAT 10"),
            Some(LoggerCommand::Spot { comment: None, repeat_minutes: Some(10) })
        );
        assert_eq!(
            parse("SPOT QSY"),
            Some(LoggerCommand::Spot { comment: Some("QSY".into()), repeat_minutes: None })
        );
        // Non-positive / non-numeric repeat falls back to a plain comment.
        assert_eq!(
            parse("SPOT REPEAT 0"),
            Some(LoggerCommand::Spot { comment: Some("REPEAT 0".into()), repeat_minutes: None })
        );
        assert_eq!(
            parse("QRT"),
            Some(LoggerCommand::Spot { comment: Some("QRT".into()), repeat_minutes: None })
        );
    }

    #[test]
    fn parses_rbn_and_hunt_and_aliases() {
        assert_eq!(parse("RBN"), Some(LoggerCommand::Rbn { callsign: None }));
        assert_eq!(parse("rbn w1aw"), Some(LoggerCommand::Rbn { callsign: Some("W1AW".into()) }));
        assert_eq!(parse("HUNT"), Some(LoggerCommand::Hunt));
        assert_eq!(parse("POTA"), Some(LoggerCommand::Hunt));
        assert_eq!(parse("SPOTS"), Some(LoggerCommand::Hunt));
        // HUNT <call> alone (no freq/mode) is still the panel, not a one-off log.
        assert_eq!(parse("HUNT W6JY"), Some(LoggerCommand::Hunt));
        // HUNT <call> <freq> is a one-off log.
        match parse("HUNT W6JY 14067 CW") {
            Some(LoggerCommand::HuntLog(result)) => {
                assert_eq!(result.callsign, "W6JY");
                assert_eq!(result.mode.as_deref(), Some("CW"));
            }
            other => panic!("expected HuntLog, got {other:?}"),
        }
    }

    #[test]
    fn parses_single_word_aliases() {
        assert_eq!(parse("WX"), Some(LoggerCommand::Weather));
        assert_eq!(parse("weather"), Some(LoggerCommand::Weather));
        assert_eq!(parse("SDR"), Some(LoggerCommand::Websdr));
        assert_eq!(parse("agn"), Some(LoggerCommand::Replay));
        assert_eq!(parse("?"), Some(LoggerCommand::Help));
        assert_eq!(parse("P2P"), Some(LoggerCommand::P2p));
        assert_eq!(parse("S2S"), Some(LoggerCommand::S2s));
    }

    #[test]
    fn parses_note_and_mycall() {
        assert_eq!(parse("NOTE tnx for the contact"), Some(LoggerCommand::Note { text: "tnx for the contact".into() }));
        assert_eq!(parse("NOTE "), None); // empty note is not a command
        assert_eq!(parse("MYCALL w5abc"), Some(LoggerCommand::MyCall("W5ABC".into())));
    }

    #[test]
    fn callsign_and_qso_are_not_commands() {
        assert_eq!(parse("W1AW"), None); // a bare callsign is not a command
        // A full QSO line ("W1AW 599 20m") is a QSO, not a command.
        assert_eq!(parse("W1AW 599 20m"), None);
    }

    #[test]
    fn callsign_less_field_line_is_session_metadata() {
        match parse("14.046 CW CN87") {
            Some(LoggerCommand::SessionMetadata(_)) => {}
            // Bare "14.046" is a frequency command (more specific), which is fine;
            // only multi-token field lines fall through to session metadata.
            other => panic!("expected SessionMetadata, got {other:?}"),
        }
    }

    #[test]
    fn command_row_catalog_matches_ios_items() {
        let keys: Vec<String> = command_row_catalog().into_iter().map(|item| item.key).collect();
        assert_eq!(keys, ["rbn", "hunt", "p2p", "s2s", "solar", "weather", "spot", "map", "manual", "help"]);
    }
}
