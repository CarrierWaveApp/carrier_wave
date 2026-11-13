//! DX cluster line + spot-comment parsing. Port of Sweep's
//! `DXSpotParser.swift` (spot lines, mode tokens, CW speed) and the
//! `SplitInfoParser` from `DXWebSpot.swift`.
//!
//! Pure: callers pass `now` (unix seconds, UTC) instead of the parser
//! reading a clock.

use std::sync::OnceLock;

use chrono::{DateTime, Duration, Timelike, Utc};
use regex::Regex;

/// A parsed DX cluster spot line.
#[derive(Debug, Clone, PartialEq)]
pub struct DxClusterSpot {
    pub spotter: String,
    pub frequency_khz: f64,
    pub callsign: String,
    pub comment: String,
    /// Unix epoch seconds.
    pub timestamp: i64,
}

/// Parse a single line from a DX cluster.
///
/// Standard format:
/// `DX de SPOTTER:    FREQ  CALLSIGN  comment            TIMEZ`
/// Example:
/// `DX de W3LPL:      14076.0  JA1ABC     FT8               1423Z`
pub fn parse_line(line: &str, now: i64) -> Option<DxClusterSpot> {
    static RE: OnceLock<Regex> = OnceLock::new();
    let regex = RE.get_or_init(|| {
        Regex::new(r"DX\s+de\s+(\S+?):\s+(\d+\.?\d*)\s+(\S+)\s+(.*?)\s+(\d{4})Z\s*$").unwrap()
    });
    let captures = regex.captures(line)?;

    let spotter = captures[1].trim().to_string();
    let frequency_khz: f64 = captures[2].parse().ok()?;
    let callsign = captures[3].trim().to_string();
    let comment = captures[4].trim().to_string();
    let timestamp = parse_utc_time(&captures[5], now).unwrap_or(now);

    Some(DxClusterSpot { spotter, frequency_khz, callsign, comment, timestamp })
}

/// Known mode tokens in priority order (first match wins).
const MODE_TOKENS: [&str; 18] = [
    "FT8", "FT4", "CW", "SSB", "LSB", "USB", "AM", "FM",
    "RTTY", "PSK31", "PSK63", "JT65", "JT9", "JS8",
    "OLIVIA", "SSTV", "DIGI", "DATA",
];

/// Parse mode from a DX cluster comment (e.g. "FT8 +3dB" → "FT8").
pub fn parse_mode(comment: &str) -> Option<&'static str> {
    static RES: OnceLock<Vec<Regex>> = OnceLock::new();
    let regexes = RES.get_or_init(|| {
        MODE_TOKENS
            .iter()
            .map(|token| Regex::new(&format!(r"(?i)\b{token}\b")).unwrap())
            .collect()
    });
    MODE_TOKENS
        .iter()
        .zip(regexes)
        .find(|(_, regex)| regex.is_match(comment))
        .map(|(token, _)| *token)
}

/// Parse CW speed from a DX cluster comment (e.g. "CW 28 WPM" → 28).
pub fn parse_cw_speed(comment: &str) -> Option<i32> {
    static RE: OnceLock<Regex> = OnceLock::new();
    let regex = RE.get_or_init(|| Regex::new(r"(\d{1,3})\s*WPM").unwrap());
    regex.captures(comment)?[1].parse().ok()
}

/// Parse split/listening frequency info from a spot comment. Returns a
/// human-readable split description, or `None`. Pattern order and casing
/// quirks match the Swift original exactly (e.g. QSX matches keep their
/// original case; UP/DOWN matches are uppercased).
pub fn parse_split_info(comment: Option<&str>) -> Option<String> {
    let comment = comment?;
    if comment.is_empty() {
        return None;
    }

    struct SplitRegexes {
        qsx: Regex,
        up_range: Regex,
        up_value: Regex,
        down: Regex,
        listening: Regex,
        simplex: Regex,
    }
    static RES: OnceLock<SplitRegexes> = OnceLock::new();
    let regexes = RES.get_or_init(|| SplitRegexes {
        qsx: Regex::new(r"(?i)\bQSX\s+(\d{3,6}\.?\d*)\b").unwrap(),
        up_range: Regex::new(r"(?i)\bup\s*(\d+\.?\d*)\s*-\s*(\d+\.?\d*)\b").unwrap(),
        up_value: Regex::new(r"(?i)\bup\s*(\d+\.?\d*)\+?\b").unwrap(),
        down: Regex::new(r"(?i)\bdown\s*(\d+\.?\d*)\b").unwrap(),
        listening: Regex::new(r"(?i)\blistening\s+(up|down)\b").unwrap(),
        simplex: Regex::new(r"(?i)\bsimpl[ex]+\b").unwrap(),
    });

    // QSX with explicit frequency: "QSX 14215" or "QSX 7025.00" — original case.
    if let Some(m) = regexes.qsx.find(comment) {
        return Some(m.as_str().trim().to_string());
    }
    // Up with range: "up1-4", "up 5-10" — "UP " + match minus its first two chars.
    if let Some(m) = regexes.up_range.find(comment) {
        let rest: String = m.as_str().chars().skip(2).collect();
        return Some(format!("UP {rest}").trim().to_string());
    }
    // Up with value and optional plus: "up 5", "UP1+", "up4.4" — uppercased.
    if let Some(m) = regexes.up_value.find(comment) {
        return Some(m.as_str().to_uppercase().trim().to_string());
    }
    // Down with value: "down 2" — uppercased.
    if let Some(m) = regexes.down.find(comment) {
        return Some(m.as_str().to_uppercase().trim().to_string());
    }
    // "listening up" / "listening down" — uppercased.
    if let Some(m) = regexes.listening.find(comment) {
        return Some(m.as_str().to_uppercase().trim().to_string());
    }
    // Simplex (various spellings).
    if regexes.simplex.is_match(comment) {
        return Some("SIMPLEX".to_string());
    }

    None
}

/// Parse an HHMM UTC time string into a unix timestamp on `now`'s UTC day;
/// if that lands in the future it was probably yesterday.
fn parse_utc_time(time_str: &str, now: i64) -> Option<i64> {
    if time_str.len() != 4 {
        return None;
    }
    let hour: u32 = time_str[..2].parse().ok()?;
    let minute: u32 = time_str[2..].parse().ok()?;

    let now_utc = DateTime::<Utc>::from_timestamp(now, 0)?;
    let candidate = now_utc
        .with_hour(hour)?
        .with_minute(minute)?
        .with_second(0)?
        .with_nanosecond(0)?;
    if candidate > now_utc {
        return Some((candidate - Duration::days(1)).timestamp());
    }
    Some(candidate.timestamp())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn now() -> i64 {
        // 2026-07-02 12:00:00 UTC
        DateTime::parse_from_rfc3339("2026-07-02T12:00:00Z").unwrap().timestamp()
    }

    #[test]
    fn parses_standard_spot_line() {
        let line = "DX de W3LPL:      14076.0  JA1ABC     FT8               1423Z";
        // 1423Z is in the future relative to 12:00 → yesterday.
        let spot = parse_line(line, now()).unwrap();
        assert_eq!(spot.spotter, "W3LPL");
        assert_eq!(spot.frequency_khz, 14_076.0);
        assert_eq!(spot.callsign, "JA1ABC");
        assert_eq!(spot.comment, "FT8");
        let now = DateTime::<Utc>::from_timestamp(now(), 0).unwrap();
        let ts = DateTime::<Utc>::from_timestamp(spot.timestamp, 0).unwrap();
        assert_eq!(ts.format("%H%M").to_string(), "1423");
        assert!(ts < now);
    }

    #[test]
    fn parses_past_time_same_day() {
        let line = "DX de K3LR:       7005.5  W1AW       CW 28 WPM         0930Z";
        let spot = parse_line(line, now()).unwrap();
        let ts = DateTime::<Utc>::from_timestamp(spot.timestamp, 0).unwrap();
        assert_eq!(ts.format("%Y-%m-%d %H%M").to_string(), "2026-07-02 0930");
    }

    #[test]
    fn rejects_non_spot_lines() {
        assert!(parse_line("WWV de W0MU <18Z> : SFI=140", now()).is_none());
        assert!(parse_line("login: please enter your call", now()).is_none());
    }

    #[test]
    fn mode_token_priority_order() {
        assert_eq!(parse_mode("FT8 +3dB"), Some("FT8"));
        assert_eq!(parse_mode("loud cw sig"), Some("CW"));
        // FT8 listed before CW: first token match wins.
        assert_eq!(parse_mode("CW then FT8"), Some("FT8"));
        assert_eq!(parse_mode("tnx 73"), None);
        // Word boundary: "SSTV" must not match "SSB"'s pattern.
        assert_eq!(parse_mode("SSTV image"), Some("SSTV"));
    }

    #[test]
    fn cw_speed_parses() {
        assert_eq!(parse_cw_speed("CW 28 WPM"), Some(28));
        assert_eq!(parse_cw_speed("CW 5WPM QRS"), Some(5));
        assert_eq!(parse_cw_speed("no speed here"), None);
    }

    #[test]
    fn split_info_qsx_keeps_case() {
        assert_eq!(parse_split_info(Some("qsx 14215 tnx")), Some("qsx 14215".to_string()));
        assert_eq!(parse_split_info(Some("QSX 7025.00")), Some("QSX 7025.00".to_string()));
    }

    #[test]
    fn split_info_up_variants() {
        assert_eq!(parse_split_info(Some("up1-4")), Some("UP 1-4".to_string()));
        assert_eq!(parse_split_info(Some("big pile up 5")), Some("UP 5".to_string()));
        assert_eq!(parse_split_info(Some("up4.4")), Some("UP4.4".to_string()));
    }

    #[test]
    fn split_info_down_listening_simplex() {
        assert_eq!(parse_split_info(Some("down 2")), Some("DOWN 2".to_string()));
        assert_eq!(
            parse_split_info(Some("listening up for NA")),
            Some("LISTENING UP".to_string())
        );
        assert_eq!(parse_split_info(Some("working simplex")), Some("SIMPLEX".to_string()));
        assert_eq!(parse_split_info(Some("tnx qso")), None);
        assert_eq!(parse_split_info(None), None);
        assert_eq!(parse_split_info(Some("")), None);
    }
}
