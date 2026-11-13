//! Quick-entry parser, ported from the Swift `QuickEntryParser` so the logger
//! command bar parses identically on iOS, macOS, and Android. Pure logic — the
//! `cw-ffi` crate wraps these types for Swift/Kotlin.
//!
//! A quick-entry line is a callsign followed by space-separated tokens, e.g.
//! `"K3LR 14.074 579R 559S WA CN87 FT8"`. Each token is classified by a fixed
//! precedence: explicit time, RST, park, grid, state/region, frequency, bare
//! time, mode, then anything left over becomes notes.

use std::collections::HashMap;
use std::sync::OnceLock;

use regex::Regex;

use crate::band::BandUtilities;
use crate::fmt;

// MARK: - Public types

/// Default order for unsuffixed RST values.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum RstOrder {
    /// First RST = received, second = sent (POTA convention, default).
    #[default]
    ReceivedFirst,
    /// First RST = sent, second = received (contest convention).
    SentFirst,
}

/// A conflict when two RSTs claim the same slot via explicit suffixes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RstConflict {
    DuplicateReceived,
    DuplicateSent,
}

/// Token classification for color-coded UI preview chips.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TokenType {
    Callsign,
    RstSent,
    RstReceived,
    State,
    Park,
    Grid,
    Frequency,
    Band,
    Mode,
    Notes,
    Time,
    RstConflict,
}

/// An explicit R/S suffix stripped from an RST token.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RstSuffix {
    None,
    Received,
    Sent,
}

/// A UTC time parsed from a `Z`-suffixed or colon token (e.g. `1804Z` → 18:04).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ZuluTime {
    pub hour: u8,
    pub minute: u8,
}

/// A token with its display text and type, for the live preview.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedToken {
    pub index: usize,
    pub text: String,
    pub token_type: TokenType,
}

/// Structured result of parsing a quick-entry line.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct QuickEntryResult {
    pub callsign: String,
    pub rst_sent: Option<String>,
    pub rst_received: Option<String>,
    pub state: Option<String>,
    pub their_park: Option<String>,
    pub their_grid: Option<String>,
    pub frequency: Option<f64>,
    pub band: Option<String>,
    pub mode: Option<String>,
    pub notes: Option<String>,
    pub rst_conflicts: Vec<RstConflict>,
    pub zulu_time: Option<ZuluTime>,
}

/// Session-metadata updates parsed from a callsign-less logger line (e.g.
/// `"14.046 CW"`). Settable fields are the ones a logging session carries as
/// defaults for future QSOs; every other token — recognized (park, state, RST,
/// time) or not — lands in `unsupported` so the UI can tell the user it was
/// ignored rather than silently dropping it.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct SessionMetadataResult {
    pub frequency: Option<f64>,
    pub band: Option<String>,
    pub mode: Option<String>,
    pub grid: Option<String>,
    pub unsupported: Vec<String>,
}

// MARK: - Public API

/// Parse a quick-entry line. Returns `None` when the input isn't valid quick
/// entry (fewer than 2 tokens, or the first token isn't a callsign).
pub fn parse(input: &str, rst_order: RstOrder) -> Option<QuickEntryResult> {
    let tokens = tokenize(input);
    let (callsign, remaining) = validate_tokens(&tokens)?;
    Some(build_result(callsign, remaining, rst_order))
}

/// Parse a line that may contain several callsigns sharing one set of metadata.
pub fn parse_multi(input: &str, rst_order: RstOrder) -> Option<Vec<QuickEntryResult>> {
    let tokens = tokenize(input);
    let (callsigns, metadata) = validate_multi_tokens(&tokens)?;
    Some(
        callsigns
            .into_iter()
            .map(|callsign| build_result(callsign, metadata.clone(), rst_order))
            .collect(),
    )
}

/// Parse into typed tokens for the live color-coded preview.
pub fn parse_tokens(input: &str, rst_order: RstOrder) -> Vec<ParsedToken> {
    let tokens = tokenize(input);
    let Some((callsign, remaining)) = validate_tokens(&tokens) else {
        return Vec::new();
    };
    build_parsed_tokens(callsign, remaining, rst_order)
}

/// Parse a callsign-less line into session-metadata updates (frequency, mode,
/// grid) for the active logging session. Returns `None` when any token is a
/// callsign (that line is quick entry, not a session update) or when no
/// settable field is present.
pub fn parse_session_metadata(input: &str) -> Option<SessionMetadataResult> {
    let tokens = tokenize(input);
    if tokens.is_empty() {
        return None;
    }
    let mut result = SessionMetadataResult::default();
    for token in &tokens {
        if !classify_for_session(token, &mut result) {
            return None;
        }
    }
    if result.frequency.is_none() && result.mode.is_none() && result.grid.is_none() {
        return None;
    }
    Some(result)
}

/// Multi-callsign variant of [`parse_tokens`].
pub fn parse_multi_tokens(input: &str, rst_order: RstOrder) -> Vec<ParsedToken> {
    let tokens = tokenize(input);
    let Some((callsigns, metadata)) = validate_multi_tokens(&tokens) else {
        return Vec::new();
    };
    build_multi_parsed_tokens(&callsigns, &metadata, rst_order)
}

// MARK: - Token predicates (public so the FFI can expose them)

/// Whether a string is a valid RST report, optionally with an R or S suffix.
pub fn is_rst(string: &str) -> bool {
    let (value, _) = strip_rst_suffix(string);
    is_rst_digits(&value)
}

/// Strip an R/S suffix, returning the numeric value and the detected suffix.
pub fn strip_rst_suffix(string: &str) -> (String, RstSuffix) {
    let upper = string.to_uppercase();
    if upper.ends_with('R') && upper.chars().count() >= 3 {
        let value: String = upper[..upper.len() - 1].to_string();
        return (value, RstSuffix::Received);
    }
    if upper.ends_with('S') && upper.chars().count() >= 3 {
        let value: String = upper[..upper.len() - 1].to_string();
        return (value, RstSuffix::Sent);
    }
    (upper, RstSuffix::None)
}

/// Whether a string looks like an amateur callsign (handles `/P`, `I/W1AW`, …).
pub fn is_callsign(string: &str) -> bool {
    let upper = string.to_uppercase();
    let parts: Vec<String> = upper.split('/').filter(|part| !part.is_empty()).map(str::to_string).collect();
    if parts.is_empty() {
        return false;
    }
    let primary = if parts.len() == 1 {
        upper.clone()
    } else {
        extract_primary_callsign(&parts)
    };
    is_basic_callsign(&primary)
}

/// Whether a string is a POTA/WWFF park reference (`US-0189`).
pub fn is_park_reference(string: &str) -> bool {
    let upper = string.to_uppercase();
    let Some((prefix, number)) = upper.split_once('-') else {
        return false;
    };
    let prefix_ok = (1..=2).contains(&prefix.chars().count())
        && prefix.bytes().all(|byte| byte.is_ascii_uppercase());
    let number_ok = (4..=5).contains(&number.chars().count())
        && number.bytes().all(|byte| byte.is_ascii_digit());
    prefix_ok && number_ok
}

/// Whether a string is a valid 4/6/8-character Maidenhead grid square.
pub fn is_grid_square(string: &str) -> bool {
    let upper = string.to_uppercase();
    let chars: Vec<char> = upper.chars().collect();
    if !matches!(chars.len(), 4 | 6 | 8) {
        return false;
    }
    if !(('A'..='R').contains(&chars[0]) && ('A'..='R').contains(&chars[1])) {
        return false;
    }
    if !(chars[2].is_ascii_digit() && chars[3].is_ascii_digit()) {
        return false;
    }
    if chars.len() >= 6 && !(('A'..='X').contains(&chars[4]) && ('A'..='X').contains(&chars[5])) {
        return false;
    }
    if chars.len() == 8 && !(chars[6].is_ascii_digit() && chars[7].is_ascii_digit()) {
        return false;
    }
    true
}

/// Whether a string is a known US state, Canadian province, or DX region code.
pub fn is_state_or_region(string: &str) -> bool {
    let upper = string.to_uppercase();
    KNOWN_REGIONS.contains(&upper.as_str())
}

/// Whether a string is a recognized amateur operating mode.
pub fn is_mode(string: &str) -> bool {
    let upper = string.to_uppercase();
    KNOWN_MODES.contains(&upper.as_str())
}

/// Whether a string is a UTC time token in any supported format.
pub fn is_zulu_time(string: &str) -> bool {
    parse_zulu_time(string).is_some()
}

/// Parse a UTC time token: `HH:MM`, `HH:MMZ`, `HHMM`, `HHMMZ`, `HMMZ`.
pub fn parse_zulu_time(string: &str) -> Option<ZuluTime> {
    let upper = string.to_uppercase();
    if upper.contains(':') {
        return parse_colon_time(&upper);
    }
    let is_zulu = upper.ends_with('Z');
    let digits = if is_zulu { &upper[..upper.len() - 1] } else { upper.as_str() };
    if digits.is_empty() || !digits.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    let (hour, minute) = match digits.len() {
        4 => (digits[..2].parse().ok()?, digits[2..].parse().ok()?),
        3 => {
            if !is_zulu {
                return None;
            }
            (digits[..1].parse().ok()?, digits[1..].parse().ok()?)
        }
        _ => return None,
    };
    if hour <= 23 && minute <= 59 {
        Some(ZuluTime { hour, minute })
    } else {
        None
    }
}

// MARK: - Internal helpers

fn is_explicit_time_token(string: &str) -> bool {
    let upper = string.to_uppercase();
    upper.contains(':') || upper.ends_with('Z')
}

/// Quick-entry frequency parse. Reuses the shared [`fmt::parse_frequency`] but
/// rejects results below the 160m floor (1.8 MHz) so a bare 4-digit time like
/// `1430` (→ 1.43 MHz) falls through to time parsing instead of masquerading as
/// a frequency. Microwave inputs (e.g. `1296000` → 1296 MHz) are unaffected.
fn parse_freq(token: &str) -> Option<f64> {
    fmt::parse_frequency(token).filter(|mhz| *mhz >= 1.8)
}

fn parse_colon_time(upper: &str) -> Option<ZuluTime> {
    let body = upper.strip_suffix('Z').unwrap_or(upper);
    let (hour_part, minute_part) = body.split_once(':')?;
    let hour_ok = (1..=2).contains(&hour_part.len()) && hour_part.bytes().all(|byte| byte.is_ascii_digit());
    let minute_ok = minute_part.len() == 2 && minute_part.bytes().all(|byte| byte.is_ascii_digit());
    if !hour_ok || !minute_ok {
        return None;
    }
    let hour: u8 = hour_part.parse().ok()?;
    let minute: u8 = minute_part.parse().ok()?;
    if hour <= 23 && minute <= 59 {
        Some(ZuluTime { hour, minute })
    } else {
        None
    }
}

fn tokenize(input: &str) -> Vec<String> {
    input
        .to_uppercase()
        .split(' ')
        .filter(|token| !token.is_empty())
        .map(str::to_string)
        .collect()
}

fn validate_tokens(tokens: &[String]) -> Option<(String, Vec<String>)> {
    if tokens.len() >= 2 && is_callsign(&tokens[0]) {
        Some((tokens[0].clone(), tokens[1..].to_vec()))
    } else {
        None
    }
}

fn validate_multi_tokens(tokens: &[String]) -> Option<(Vec<String>, Vec<String>)> {
    if tokens.len() < 2 || !is_callsign(&tokens[0]) {
        return None;
    }
    let mut callsigns = vec![tokens[0].clone()];
    let mut metadata = Vec::new();
    for token in &tokens[1..] {
        // Check RST before callsign — "579S"/"559R" match the callsign regex
        // but are RSTs with sent/received suffixes.
        if !is_rst(token) && is_callsign(token) && !is_state_or_region(token) {
            callsigns.push(token.clone());
        } else {
            metadata.push(token.clone());
        }
    }
    if callsigns.len() >= 2 || !metadata.is_empty() {
        Some((callsigns, metadata))
    } else {
        None
    }
}

fn is_rst_digits(string: &str) -> bool {
    if !matches!(string.len(), 2 | 3) || !string.bytes().all(|byte| byte.is_ascii_digit()) {
        return false;
    }
    let digits: Vec<u32> = string.chars().map(|ch| ch.to_digit(10).unwrap()).collect();
    if !(1..=5).contains(&digits[0]) {
        return false;
    }
    if !(1..=9).contains(&digits[1]) {
        return false;
    }
    if digits.len() == 3 && !(1..=9).contains(&digits[2]) {
        return false;
    }
    true
}

fn is_basic_callsign(string: &str) -> bool {
    static RE: OnceLock<Regex> = OnceLock::new();
    let regex = RE.get_or_init(|| Regex::new(r"^[A-Z0-9]{1,3}[0-9][A-Z]{1,4}$").unwrap());
    regex.is_match(string)
}

/// Extract the primary callsign from a portable/prefix callsign — faithful port
/// of the iOS `QuickLogSection.extractPrimary` (e.g. `"I/W6JSV/P" -> "W6JSV"`,
/// `"VE3/W6JSV" -> "W6JSV"`). Case is preserved; a callsign with no usable `/`
/// segments is returned unchanged. Backs the hunter quick-log lookup + dedup.
pub fn extract_primary(callsign: &str) -> String {
    // Swift `split(separator:)` omits empty subsequences by default.
    let parts: Vec<String> =
        callsign.split('/').filter(|part| !part.is_empty()).map(str::to_string).collect();
    if parts.len() <= 1 {
        return callsign.to_string();
    }
    extract_primary_callsign(&parts)
}

fn extract_primary_callsign(parts: &[String]) -> String {
    const KNOWN_SUFFIXES: [&str; 8] = ["P", "M", "MM", "AM", "QRP", "R", "A", "B"];
    if parts.len() == 2 {
        let (first, second) = (&parts[0], &parts[1]);
        if KNOWN_SUFFIXES.contains(&second.as_str()) || second.chars().count() <= 2 {
            return first.clone();
        }
        if first.chars().count() <= 2 {
            return second.clone();
        }
        return if first.chars().count() >= second.chars().count() {
            first.clone()
        } else {
            second.clone()
        };
    }
    if parts.len() == 3 {
        return parts[1].clone();
    }
    parts
        .iter()
        .max_by_key(|part| part.chars().count())
        .cloned()
        .unwrap_or_default()
}

// MARK: - Region / mode tables

const KNOWN_MODES: [&str; 20] = [
    "CW", "SSB", "USB", "LSB", "AM", "FM", "DV", "FT8", "FT4", "PSK31", "PSK", "RTTY", "JT65", "JT9",
    "JTTY", "MFSK", "OLIVIA", "DATA", "PHONE", "DIGITAL",
];

const KNOWN_REGIONS: &[&str] = &[
    // US states + DC
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS",
    "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY",
    "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV",
    "WI", "WY", "DC", // Canadian provinces/territories
    "AB", "BC", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT", // DX regions
    "DL", "EA", "EI", "HA", "HB", "LU", "LZ", "OE", "OH", "OM", "OZ", "SM", "SP", "UA", "UR", "VK",
    "ZL", "ZS", "JA", "HL", "BV", "BY", "YB", "HS", "VU", "UK",
];

// MARK: - Result building

fn build_result(callsign: String, remaining: Vec<String>, rst_order: RstOrder) -> QuickEntryResult {
    let mut result = QuickEntryResult { callsign, ..Default::default() };
    let mut unrecognized: Vec<String> = Vec::new();
    let mut unsuffixed: Vec<String> = Vec::new();
    let mut parks: Vec<String> = Vec::new();

    for token in &remaining {
        classify_for_result(token, &mut result, &mut unsuffixed, &mut unrecognized, &mut parks);
    }

    // Multiple space-separated park tokens (a POTA n-fer, e.g. `US-1044 US-3791`)
    // are joined into the comma-separated `their_park` storage format, in the
    // order typed. Single-park entry yields a bare reference, unchanged.
    if !parks.is_empty() {
        result.their_park = Some(parks.join(", "));
    }

    assign_unsuffixed_rsts(&unsuffixed, rst_order, &mut result, &mut unrecognized);

    if !unrecognized.is_empty() {
        result.notes = Some(unrecognized.join(" "));
    }
    result
}

fn classify_for_result(
    token: &str,
    result: &mut QuickEntryResult,
    unsuffixed: &mut Vec<String>,
    unrecognized: &mut Vec<String>,
    parks: &mut Vec<String>,
) {
    if is_explicit_time_token(token) {
        if let Some(zulu) = parse_zulu_time(token) {
            result.zulu_time = Some(zulu);
            return;
        }
    }
    if is_rst(token) {
        let (value, suffix) = strip_rst_suffix(token);
        match suffix {
            RstSuffix::Received => assign_rst_received(value, result),
            RstSuffix::Sent => assign_rst_sent(value, result),
            RstSuffix::None => unsuffixed.push(value),
        }
    } else if is_park_reference(token) {
        parks.push(token.to_string());
    } else if is_grid_square(token) {
        result.their_grid = Some(token.to_uppercase());
    } else if is_state_or_region(token) {
        result.state = Some(token.to_string());
    } else if let Some(freq) = parse_freq(token) {
        result.frequency = Some(freq);
        result.band = BandUtilities::derive_band(Some(freq * 1_000.0)).map(str::to_string);
    } else if let Some(zulu) = parse_zulu_time(token) {
        result.zulu_time = Some(zulu);
    } else if is_mode(token) {
        result.mode = Some(token.to_uppercase());
    } else {
        unrecognized.push(token.to_string());
    }
}

/// Classify one token of a session-metadata line. Returns `false` when the
/// token is a callsign, which disqualifies the whole line. Grid is checked
/// before the callsign test because 6-char grids like `CN87WK` also match the
/// callsign regex (same overlap trick as RST-before-callsign in
/// `validate_multi_tokens`).
fn classify_for_session(token: &str, result: &mut SessionMetadataResult) -> bool {
    if is_grid_square(token) {
        result.grid = Some(token.to_uppercase());
    } else if is_rst(token) || is_park_reference(token) || is_state_or_region(token) {
        result.unsupported.push(token.to_string());
    } else if let Some(freq) = parse_freq(token) {
        result.frequency = Some(freq);
        result.band = BandUtilities::derive_band(Some(freq * 1_000.0)).map(str::to_string);
    } else if is_zulu_time(token) {
        result.unsupported.push(token.to_string());
    } else if is_mode(token) {
        result.mode = Some(token.to_uppercase());
    } else if is_callsign(token) {
        return false;
    } else {
        result.unsupported.push(token.to_string());
    }
    true
}

fn assign_rst_received(value: String, result: &mut QuickEntryResult) {
    if result.rst_received.is_some() {
        result.rst_conflicts.push(RstConflict::DuplicateReceived);
    } else {
        result.rst_received = Some(value);
    }
}

fn assign_rst_sent(value: String, result: &mut QuickEntryResult) {
    if result.rst_sent.is_some() {
        result.rst_conflicts.push(RstConflict::DuplicateSent);
    } else {
        result.rst_sent = Some(value);
    }
}

fn assign_unsuffixed_rsts(
    values: &[String],
    order: RstOrder,
    result: &mut QuickEntryResult,
    overflow: &mut Vec<String>,
) {
    let both_empty = result.rst_received.is_none() && result.rst_sent.is_none();
    if values.len() == 1 && both_empty {
        if order == RstOrder::SentFirst {
            result.rst_sent = Some(values[0].clone());
        } else {
            result.rst_received = Some(values[0].clone());
        }
        return;
    }
    let slots = available_rst_slots(result.rst_received.is_some(), result.rst_sent.is_some(), order);
    for (idx, value) in values.iter().enumerate() {
        match slots.get(idx) {
            Some(TokenType::RstReceived) => result.rst_received = Some(value.clone()),
            Some(TokenType::RstSent) => result.rst_sent = Some(value.clone()),
            _ => overflow.push(value.clone()),
        }
    }
}

fn available_rst_slots(has_received: bool, has_sent: bool, order: RstOrder) -> Vec<TokenType> {
    let ordered = if order == RstOrder::ReceivedFirst {
        [TokenType::RstReceived, TokenType::RstSent]
    } else {
        [TokenType::RstSent, TokenType::RstReceived]
    };
    ordered
        .into_iter()
        .filter(|slot| match slot {
            TokenType::RstReceived => !has_received,
            TokenType::RstSent => !has_sent,
            _ => true,
        })
        .collect()
}

// MARK: - Token building (preview)

#[derive(Default)]
struct RstInfo {
    assignments: HashMap<usize, TokenType>,
    display_values: HashMap<usize, String>,
}

#[derive(Default)]
struct RstCategories {
    received_idx: Option<usize>,
    sent_idx: Option<usize>,
    unsuffixed: Vec<usize>,
    dup_received: Vec<usize>,
    dup_sent: Vec<usize>,
}

fn categorize_rst_tokens(tokens: &[String], info: &mut RstInfo) -> RstCategories {
    let mut cats = RstCategories::default();
    for (index, token) in tokens.iter().enumerate() {
        if index == 0 || is_zulu_time(token) || !is_rst(token) {
            continue;
        }
        let (value, suffix) = strip_rst_suffix(token);
        info.display_values.insert(index, value);
        match suffix {
            RstSuffix::Received => {
                if cats.received_idx.is_some() {
                    cats.dup_received.push(index);
                } else {
                    cats.received_idx = Some(index);
                }
            }
            RstSuffix::Sent => {
                if cats.sent_idx.is_some() {
                    cats.dup_sent.push(index);
                } else {
                    cats.sent_idx = Some(index);
                }
            }
            RstSuffix::None => cats.unsuffixed.push(index),
        }
    }
    cats
}

fn build_rst_info(tokens: &[String], order: RstOrder) -> RstInfo {
    let mut info = RstInfo::default();
    let cats = categorize_rst_tokens(tokens, &mut info);

    if let Some(ri) = cats.received_idx {
        info.assignments.insert(ri, TokenType::RstReceived);
    }
    if let Some(si) = cats.sent_idx {
        info.assignments.insert(si, TokenType::RstSent);
    }
    for di in cats.dup_received {
        info.assignments.insert(di, TokenType::RstConflict);
    }
    for di in cats.dup_sent {
        info.assignments.insert(di, TokenType::RstConflict);
    }

    let both_empty = cats.received_idx.is_none() && cats.sent_idx.is_none();
    if cats.unsuffixed.len() == 1 && both_empty {
        let slot = if order == RstOrder::SentFirst { TokenType::RstSent } else { TokenType::RstReceived };
        info.assignments.insert(cats.unsuffixed[0], slot);
    } else {
        let mut remaining = available_rst_slots(cats.received_idx.is_some(), cats.sent_idx.is_some(), order);
        for ui in cats.unsuffixed {
            if remaining.is_empty() {
                info.assignments.insert(ui, TokenType::Notes);
            } else {
                info.assignments.insert(ui, remaining.remove(0));
            }
        }
    }
    info
}

fn build_parsed_tokens(callsign: String, remaining: Vec<String>, order: RstOrder) -> Vec<ParsedToken> {
    let mut all_tokens = vec![callsign.clone()];
    all_tokens.extend(remaining.iter().cloned());
    let rst_info = build_rst_info(&all_tokens, order);

    let mut result = vec![ParsedToken { index: 0, text: callsign, token_type: TokenType::Callsign }];
    for (index, token) in remaining.iter().enumerate() {
        classify_for_tokens(token, index + 1, &rst_info, &mut result);
    }
    result
}

fn build_multi_parsed_tokens(callsigns: &[String], metadata: &[String], order: RstOrder) -> Vec<ParsedToken> {
    let mut result: Vec<ParsedToken> = Vec::new();
    for callsign in callsigns {
        let index = result.len();
        result.push(ParsedToken { index, text: callsign.clone(), token_type: TokenType::Callsign });
    }
    // Prepend a dummy first token so metadata indexing aligns with build_rst_info.
    let mut meta_tokens = vec![String::new()];
    meta_tokens.extend(metadata.iter().cloned());
    let rst_info = build_rst_info(&meta_tokens, order);

    for (index, token) in metadata.iter().enumerate() {
        classify_for_tokens(token, index + 1, &rst_info, &mut result);
    }
    result
}

fn classify_for_tokens(token: &str, original_index: usize, rst_info: &RstInfo, result: &mut Vec<ParsedToken>) {
    let push = |result: &mut Vec<ParsedToken>, text: String, token_type: TokenType| {
        let index = result.len();
        result.push(ParsedToken { index, text, token_type });
    };

    if is_explicit_time_token(token) && is_zulu_time(token) {
        push(result, token.to_uppercase(), TokenType::Time);
    } else if let Some(rst_type) = rst_info.assignments.get(&original_index) {
        let display = rst_info.display_values.get(&original_index).cloned().unwrap_or_else(|| token.to_string());
        push(result, display, *rst_type);
    } else if is_park_reference(token) {
        push(result, token.to_string(), TokenType::Park);
    } else if is_grid_square(token) {
        push(result, token.to_uppercase(), TokenType::Grid);
    } else if is_state_or_region(token) {
        push(result, token.to_string(), TokenType::State);
    } else if let Some(freq) = parse_freq(token) {
        push(result, fmt::format_frequency_with_unit(freq), TokenType::Frequency);
        if let Some(band) = BandUtilities::derive_band(Some(freq * 1_000.0)) {
            push(result, band.to_string(), TokenType::Band);
        }
    } else if is_zulu_time(token) {
        push(result, token.to_uppercase(), TokenType::Time);
    } else if is_mode(token) {
        push(result, token.to_uppercase(), TokenType::Mode);
    } else {
        push(result, token.to_string(), TokenType::Notes);
    }
}

// MARK: - Tests (ported from CarrierWaveCore Swift suites)

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_default(input: &str) -> Option<QuickEntryResult> {
        parse(input, RstOrder::ReceivedFirst)
    }

    // ---- Callsign detection ----

    #[test]
    fn single_callsign_returns_none() {
        assert!(parse_default("W1AW").is_none());
        assert!(parse_default("W1AW ").is_none());
    }

    #[test]
    fn valid_callsign_patterns() {
        for call in ["W1AW", "K3LR", "VE3ABC", "JA1ABC", "G4ABC", "DL1ABC", "9A1A", "3DA0ABC"] {
            assert!(is_callsign(call), "{call} should be a callsign");
        }
    }

    #[test]
    fn callsign_with_modifiers() {
        for call in ["W1AW/P", "W1AW/M", "I/W1AW", "VE3/K1ABC", "W1AW/MM"] {
            assert!(is_callsign(call), "{call} should be a callsign");
        }
    }

    #[test]
    fn invalid_callsign_patterns() {
        for value in ["599", "WA", "FREQ", "US-0189", "CN87"] {
            assert!(!is_callsign(value), "{value} should not be a callsign");
        }
    }

    // ---- RST ----

    #[test]
    fn single_rst_applied_to_received() {
        let result = parse_default("W1AW 579").unwrap();
        assert_eq!(result.callsign, "W1AW");
        assert_eq!(result.rst_sent, None);
        assert_eq!(result.rst_received.as_deref(), Some("579"));
    }

    #[test]
    fn two_rsts_received_then_sent() {
        let result = parse_default("W1AW 559 579").unwrap();
        assert_eq!(result.rst_received.as_deref(), Some("559"));
        assert_eq!(result.rst_sent.as_deref(), Some("579"));
    }

    #[test]
    fn phone_rst() {
        assert_eq!(parse_default("W1AW 57").unwrap().rst_received.as_deref(), Some("57"));
    }

    #[test]
    fn valid_rst_patterns() {
        for value in ["599", "579", "339", "59", "57", "44", "11"] {
            assert!(is_rst(value), "{value} should be RST");
        }
    }

    #[test]
    fn invalid_rst_patterns() {
        for value in ["999", "69", "50", "5", "5999", "WA"] {
            assert!(!is_rst(value), "{value} should not be RST");
        }
    }

    // ---- Park ----

    #[test]
    fn park_reference_detection() {
        assert_eq!(parse_default("W1AW US-0189").unwrap().their_park.as_deref(), Some("US-0189"));
        let combined = parse_default("W1AW 579 US-0189").unwrap();
        assert_eq!(combined.rst_received.as_deref(), Some("579"));
        assert_eq!(combined.their_park.as_deref(), Some("US-0189"));
    }

    #[test]
    fn multi_park_nfer_joined_comma_separated() {
        // Two space-separated parks (a 2-fer) join into the storage format, in
        // the order typed.
        let two = parse_default("W1AW US-1044 US-3791").unwrap();
        assert_eq!(two.their_park.as_deref(), Some("US-1044, US-3791"));
        // Three-fer, mixed with RST and frequency tokens.
        let three = parse_default("K3LR 14.060 599 US-1044 K-4567 VE-0001").unwrap();
        assert_eq!(three.their_park.as_deref(), Some("US-1044, K-4567, VE-0001"));
        assert_eq!(three.rst_received.as_deref(), Some("599"));
        assert_eq!(three.frequency, Some(14.060));
        // Single park is unchanged (bare reference, no trailing separator).
        assert_eq!(parse_default("W1AW US-0189").unwrap().their_park.as_deref(), Some("US-0189"));
    }

    #[test]
    fn multi_park_shared_across_callsigns() {
        let results = parse_multi("W1AW K3LR 599 US-1044 US-3791", RstOrder::ReceivedFirst).unwrap();
        assert_eq!(results.len(), 2);
        for result in &results {
            assert_eq!(result.their_park.as_deref(), Some("US-1044, US-3791"));
        }
    }

    #[test]
    fn valid_park_patterns() {
        for value in ["US-0189", "K-1234", "VE-0001", "G-0001", "DL-0001", "JA-12345"] {
            assert!(is_park_reference(value), "{value} should be a park");
        }
    }

    #[test]
    fn invalid_park_patterns() {
        for value in ["US0189", "US-01", "USA-0189", "W1AW", "579"] {
            assert!(!is_park_reference(value), "{value} should not be a park");
        }
    }

    // ---- Grid ----

    #[test]
    fn grid_square_detection() {
        assert_eq!(parse_default("W1AW CN87").unwrap().their_grid.as_deref(), Some("CN87"));
        assert_eq!(parse_default("W1AW FN31pr").unwrap().their_grid.as_deref(), Some("FN31PR"));
    }

    #[test]
    fn valid_grid_patterns() {
        for value in ["CN87", "FN31", "JO22", "AA00", "RR99", "FN31pr", "CN87wk"] {
            assert!(is_grid_square(value), "{value} should be a grid");
        }
    }

    #[test]
    fn invalid_grid_patterns() {
        for value in ["CN8", "CN877", "SN87", "1N87", "W1AW", "WA"] {
            assert!(!is_grid_square(value), "{value} should not be a grid");
        }
    }

    // ---- State / region ----

    #[test]
    fn state_detection() {
        assert_eq!(parse_default("W1AW WA").unwrap().state.as_deref(), Some("WA"));
        assert_eq!(parse_default("VE3ABC ON").unwrap().state.as_deref(), Some("ON"));
        assert_eq!(parse_default("DL1ABC DL").unwrap().state.as_deref(), Some("DL"));
    }

    #[test]
    fn valid_state_patterns() {
        for value in ["WA", "CA", "TX", "NY", "DC", "ON", "BC", "QC", "AB", "DL", "EA", "JA", "VK", "ZL"] {
            assert!(is_state_or_region(value), "{value} should be a region");
        }
    }

    #[test]
    fn invalid_state_patterns() {
        for value in ["XX", "W1", "599", "USA"] {
            assert!(!is_state_or_region(value), "{value} should not be a region");
        }
    }

    // ---- Frequency ----

    #[test]
    fn frequency_with_decimal() {
        let result = parse_default("W1AW 14.060").unwrap();
        assert_eq!(result.frequency, Some(14.060));
        assert_eq!(result.band.as_deref(), Some("20m"));
    }

    #[test]
    fn frequency_in_khz() {
        let result = parse_default("W1AW 7030").unwrap();
        assert_eq!(result.frequency, Some(7.030));
        assert_eq!(result.band.as_deref(), Some("40m"));
    }

    #[test]
    fn frequency_with_rst_and_park() {
        let result = parse_default("K3LR 14.060 599 US-0189").unwrap();
        assert_eq!(result.frequency, Some(14.060));
        assert_eq!(result.band.as_deref(), Some("20m"));
        assert_eq!(result.rst_received.as_deref(), Some("599"));
        assert_eq!(result.their_park.as_deref(), Some("US-0189"));
    }

    #[test]
    fn frequency_token_displayed_with_mhz() {
        let tokens = parse_tokens("W1AW 14.060", RstOrder::ReceivedFirst);
        assert_eq!(tokens.len(), 3);
        assert_eq!(tokens[0].token_type, TokenType::Callsign);
        assert_eq!(tokens[1].token_type, TokenType::Frequency);
        assert_eq!(tokens[1].text, "14.060 MHz");
        assert_eq!(tokens[2].token_type, TokenType::Band);
        assert_eq!(tokens[2].text, "20m");
    }

    #[test]
    fn frequency_70cm_band_token() {
        let tokens = parse_tokens("W1AW 440.000", RstOrder::ReceivedFirst);
        assert_eq!(tokens.len(), 3);
        assert_eq!(tokens[1].token_type, TokenType::Frequency);
        assert_eq!(tokens[2].token_type, TokenType::Band);
        assert_eq!(tokens[2].text, "70cm");
    }

    #[test]
    fn rst_not_confused_with_frequency() {
        let result = parse_default("W1AW 599").unwrap();
        assert_eq!(result.rst_received.as_deref(), Some("599"));
        assert_eq!(result.frequency, None);
    }

    // ---- Edge cases ----

    #[test]
    fn empty_and_whitespace_return_none() {
        assert!(parse_default("").is_none());
        assert!(parse_default("   ").is_none());
    }

    #[test]
    fn lowercase_callsign_normalized() {
        let result = parse_default("w1aw 59").unwrap();
        assert_eq!(result.callsign, "W1AW");
        assert_eq!(result.rst_received.as_deref(), Some("59"));
    }

    #[test]
    fn three_rst_values_third_is_notes() {
        let result = parse_default("W1AW 559 579 599").unwrap();
        assert_eq!(result.rst_received.as_deref(), Some("559"));
        assert_eq!(result.rst_sent.as_deref(), Some("579"));
        assert_eq!(result.notes.as_deref(), Some("599"));
    }

    #[test]
    fn second_callsign_becomes_notes() {
        let result = parse_default("W1AW K3LR 59").unwrap();
        assert_eq!(result.callsign, "W1AW");
        assert_eq!(result.rst_received.as_deref(), Some("59"));
        assert_eq!(result.notes.as_deref(), Some("K3LR"));
    }

    // ---- RST suffixes & order ----

    #[test]
    fn rst_suffixes() {
        assert!(is_rst("579R") && is_rst("59R") && is_rst("559S") && is_rst("57S"));
        assert_eq!(parse_default("W1AW 579R").unwrap().rst_received.as_deref(), Some("579"));
        assert_eq!(parse_default("W1AW 559S").unwrap().rst_sent.as_deref(), Some("559"));
        let mixed = parse_default("W1AW 559S 579R").unwrap();
        assert_eq!(mixed.rst_sent.as_deref(), Some("559"));
        assert_eq!(mixed.rst_received.as_deref(), Some("579"));
        let reordered = parse_default("W1AW 579R 559S").unwrap();
        assert_eq!(reordered.rst_received.as_deref(), Some("579"));
        assert_eq!(reordered.rst_sent.as_deref(), Some("559"));
        let lower = parse_default("W1AW 579r 559s").unwrap();
        assert_eq!(lower.rst_received.as_deref(), Some("579"));
        assert_eq!(lower.rst_sent.as_deref(), Some("559"));
    }

    #[test]
    fn strip_rst_suffix_values() {
        assert_eq!(strip_rst_suffix("579R"), ("579".to_string(), RstSuffix::Received));
        assert_eq!(strip_rst_suffix("559S"), ("559".to_string(), RstSuffix::Sent));
        assert_eq!(strip_rst_suffix("599"), ("599".to_string(), RstSuffix::None));
    }

    #[test]
    fn rst_order_variants() {
        assert_eq!(parse("W1AW 579", RstOrder::SentFirst).unwrap().rst_sent.as_deref(), Some("579"));
        let two = parse("W1AW 559 579", RstOrder::SentFirst).unwrap();
        assert_eq!(two.rst_sent.as_deref(), Some("559"));
        assert_eq!(two.rst_received.as_deref(), Some("579"));
        // Suffix overrides order preference.
        let suffixed = parse("W1AW 579R", RstOrder::SentFirst).unwrap();
        assert_eq!(suffixed.rst_received.as_deref(), Some("579"));
        assert_eq!(suffixed.rst_sent, None);
        // Unsuffixed fills the remaining slot after a suffixed one.
        let fill = parse_default("W1AW 559S 579").unwrap();
        assert_eq!(fill.rst_sent.as_deref(), Some("559"));
        assert_eq!(fill.rst_received.as_deref(), Some("579"));
    }

    #[test]
    fn rst_conflicts() {
        let dup_r = parse_default("W1AW 559R 579R").unwrap();
        assert_eq!(dup_r.rst_received.as_deref(), Some("559"));
        assert_eq!(dup_r.rst_conflicts, vec![RstConflict::DuplicateReceived]);
        let dup_s = parse_default("W1AW 559S 579S").unwrap();
        assert_eq!(dup_s.rst_sent.as_deref(), Some("559"));
        assert_eq!(dup_s.rst_conflicts, vec![RstConflict::DuplicateSent]);
        assert!(parse_default("W1AW 559S 579R").unwrap().rst_conflicts.is_empty());
        assert!(parse_default("W1AW 559 579").unwrap().rst_conflicts.is_empty());
    }

    #[test]
    fn token_preview_rst() {
        let tokens = parse_tokens("W1AW 559S 579R", RstOrder::ReceivedFirst);
        assert_eq!(tokens.len(), 3);
        assert_eq!(tokens[1].text, "559");
        assert_eq!(tokens[1].token_type, TokenType::RstSent);
        assert_eq!(tokens[2].text, "579");
        assert_eq!(tokens[2].token_type, TokenType::RstReceived);

        let conflict = parse_tokens("W1AW 559R 579R", RstOrder::ReceivedFirst);
        assert_eq!(conflict[1].token_type, TokenType::RstReceived);
        assert_eq!(conflict[2].token_type, TokenType::RstConflict);

        let sent_first = parse_tokens("W1AW 579", RstOrder::SentFirst);
        assert_eq!(sent_first[1].token_type, TokenType::RstSent);
        assert_eq!(sent_first[1].text, "579");

        let two_sent_first = parse_tokens("W1AW 559 579", RstOrder::SentFirst);
        assert_eq!(two_sent_first[1].token_type, TokenType::RstSent);
        assert_eq!(two_sent_first[2].token_type, TokenType::RstReceived);
    }

    // ---- Time ----

    #[test]
    fn zulu_time_formats() {
        let hhmmz = parse_default("W1AW 1804Z").unwrap().zulu_time.unwrap();
        assert_eq!((hhmmz.hour, hhmmz.minute), (18, 4));
        let hmmz = parse_default("W1AW 930Z").unwrap().zulu_time.unwrap();
        assert_eq!((hmmz.hour, hmmz.minute), (9, 30));
    }

    #[test]
    fn colon_time_formats() {
        let plain = parse_default("W1AW 14:30").unwrap();
        assert_eq!(plain.zulu_time, Some(ZuluTime { hour: 14, minute: 30 }));
        assert_eq!(plain.notes, None);
        let with_z = parse_default("W1AW 09:05Z").unwrap().zulu_time.unwrap();
        assert_eq!((with_z.hour, with_z.minute), (9, 5));
        let single = parse_default("W1AW 2:30").unwrap().zulu_time.unwrap();
        assert_eq!((single.hour, single.minute), (2, 30));
    }

    #[test]
    fn bare_hhmm_as_time() {
        let result = parse_default("W1AW 1430").unwrap();
        assert_eq!(result.zulu_time, Some(ZuluTime { hour: 14, minute: 30 }));
        assert_eq!(result.frequency, None);
        assert_eq!(result.notes, None);
        let leading_zero = parse_default("W1AW 0930").unwrap().zulu_time.unwrap();
        assert_eq!((leading_zero.hour, leading_zero.minute), (9, 30));
    }

    #[test]
    fn bare_frequency_wins_over_time() {
        let result = parse_default("W1AW 1804").unwrap();
        assert_eq!(result.frequency, Some(1.804));
        assert_eq!(result.zulu_time, None);
    }

    #[test]
    fn z_suffix_forces_time() {
        let result = parse_default("W1AW 1804Z").unwrap();
        assert_eq!(result.zulu_time, Some(ZuluTime { hour: 18, minute: 4 }));
        assert_eq!(result.frequency, None);
    }

    #[test]
    fn invalid_times_return_none() {
        assert_eq!(parse_default("W1AW 25:30").unwrap().zulu_time, None);
        assert_eq!(parse_default("W1AW 14:75").unwrap().zulu_time, None);
    }

    #[test]
    fn rst_not_confused_with_time() {
        let result = parse_default("W1AW 599").unwrap();
        assert_eq!(result.rst_received.as_deref(), Some("599"));
        assert_eq!(result.zulu_time, None);
    }

    #[test]
    fn time_and_frequency_together() {
        let result = parse_default("W1AW 14250 599 14:30").unwrap();
        assert_eq!(result.frequency, Some(14.25));
        assert_eq!(result.rst_received.as_deref(), Some("599"));
        assert_eq!(result.zulu_time, Some(ZuluTime { hour: 14, minute: 30 }));
    }

    #[test]
    fn token_preview_time() {
        let colon = parse_tokens("W1AW 14:30", RstOrder::ReceivedFirst);
        assert!(colon.iter().any(|tok| tok.token_type == TokenType::Time && tok.text == "14:30"));
        let bare = parse_tokens("W1AW 0930", RstOrder::ReceivedFirst);
        assert!(bare.iter().any(|tok| tok.token_type == TokenType::Time && tok.text == "0930"));
        let freq = parse_tokens("W1AW 1804", RstOrder::ReceivedFirst);
        assert!(freq.iter().any(|tok| tok.token_type == TokenType::Frequency));
        assert!(!freq.iter().any(|tok| tok.token_type == TokenType::Time));
    }

    // ---- Session metadata (callsign-less lines) ----

    #[test]
    fn session_metadata_frequency_and_mode() {
        let result = parse_session_metadata("14.046 cw").unwrap();
        assert_eq!(result.frequency, Some(14.046));
        assert_eq!(result.band.as_deref(), Some("20m"));
        assert_eq!(result.mode.as_deref(), Some("CW"));
        assert_eq!(result.grid, None);
        assert!(result.unsupported.is_empty());
    }

    #[test]
    fn session_metadata_single_field_lines() {
        assert_eq!(parse_session_metadata("14046").unwrap().frequency, Some(14.046));
        assert_eq!(parse_session_metadata("ssb").unwrap().mode.as_deref(), Some("SSB"));
        assert_eq!(parse_session_metadata("cn87").unwrap().grid.as_deref(), Some("CN87"));
    }

    #[test]
    fn session_metadata_grid_beats_callsign_regex() {
        // 6-char grids match the callsign regex; grid classification must win.
        let result = parse_session_metadata("14.046 CW CN87WK").unwrap();
        assert_eq!(result.frequency, Some(14.046));
        assert_eq!(result.mode.as_deref(), Some("CW"));
        assert_eq!(result.grid.as_deref(), Some("CN87WK"));
    }

    #[test]
    fn session_metadata_rejects_callsign_lines() {
        assert!(parse_session_metadata("W1AW").is_none());
        assert!(parse_session_metadata("W1AW 14.046").is_none());
        assert!(parse_session_metadata("14.046 W1AW").is_none());
    }

    #[test]
    fn session_metadata_surfaces_unsupported_tokens() {
        let result = parse_session_metadata("14.046 US-0189 599 WA hello").unwrap();
        assert_eq!(result.frequency, Some(14.046));
        assert_eq!(result.unsupported, vec!["US-0189", "599", "WA", "HELLO"]);
    }

    #[test]
    fn session_metadata_requires_a_settable_field() {
        assert!(parse_session_metadata("").is_none());
        assert!(parse_session_metadata("US-0189").is_none());
        assert!(parse_session_metadata("599 WA").is_none());
        // Bare HHMM is a time token, which sessions can't take.
        assert!(parse_session_metadata("1430").is_none());
    }

    #[test]
    fn session_metadata_time_tokens_unsupported() {
        let result = parse_session_metadata("7030 1430Z").unwrap();
        assert_eq!(result.frequency, Some(7.030));
        assert_eq!(result.band.as_deref(), Some("40m"));
        assert_eq!(result.unsupported, vec!["1430Z"]);
    }

    // ---- Multi-callsign ----

    #[test]
    fn multi_callsign_shares_metadata() {
        let results = parse_multi("W1AW K3LR 599 US-0189", RstOrder::ReceivedFirst).unwrap();
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].callsign, "W1AW");
        assert_eq!(results[1].callsign, "K3LR");
        for result in &results {
            assert_eq!(result.rst_received.as_deref(), Some("599"));
            assert_eq!(result.their_park.as_deref(), Some("US-0189"));
        }
    }
}
