//! UniFFI surface for the quick-entry parser (`cw_domain::quick_entry`).
//!
//! Both the Apple apps and `android/` call these functions so the logger
//! command bar parses identically everywhere — the grammar lives in Rust, not
//! duplicated per platform.

use cw_domain::quick_entry as qe;

/// Default order for unsuffixed RST values.
#[derive(uniffi::Enum)]
pub enum FfiRstOrder {
    ReceivedFirst,
    SentFirst,
}

impl From<FfiRstOrder> for qe::RstOrder {
    fn from(order: FfiRstOrder) -> Self {
        match order {
            FfiRstOrder::ReceivedFirst => qe::RstOrder::ReceivedFirst,
            FfiRstOrder::SentFirst => qe::RstOrder::SentFirst,
        }
    }
}

/// Token classification for the color-coded preview.
#[derive(uniffi::Enum)]
pub enum FfiQuickTokenType {
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

impl From<qe::TokenType> for FfiQuickTokenType {
    fn from(token: qe::TokenType) -> Self {
        match token {
            qe::TokenType::Callsign => FfiQuickTokenType::Callsign,
            qe::TokenType::RstSent => FfiQuickTokenType::RstSent,
            qe::TokenType::RstReceived => FfiQuickTokenType::RstReceived,
            qe::TokenType::State => FfiQuickTokenType::State,
            qe::TokenType::Park => FfiQuickTokenType::Park,
            qe::TokenType::Grid => FfiQuickTokenType::Grid,
            qe::TokenType::Frequency => FfiQuickTokenType::Frequency,
            qe::TokenType::Band => FfiQuickTokenType::Band,
            qe::TokenType::Mode => FfiQuickTokenType::Mode,
            qe::TokenType::Notes => FfiQuickTokenType::Notes,
            qe::TokenType::Time => FfiQuickTokenType::Time,
            qe::TokenType::RstConflict => FfiQuickTokenType::RstConflict,
        }
    }
}

/// An RST conflict (two values claiming the same slot via explicit suffixes).
#[derive(uniffi::Enum)]
pub enum FfiRstConflict {
    DuplicateReceived,
    DuplicateSent,
}

impl From<qe::RstConflict> for FfiRstConflict {
    fn from(conflict: qe::RstConflict) -> Self {
        match conflict {
            qe::RstConflict::DuplicateReceived => FfiRstConflict::DuplicateReceived,
            qe::RstConflict::DuplicateSent => FfiRstConflict::DuplicateSent,
        }
    }
}

/// A UTC time parsed from a quick-entry token (e.g. `1804Z` → 18:04).
#[derive(uniffi::Record)]
pub struct FfiZuluTime {
    pub hour: u8,
    pub minute: u8,
}

impl From<qe::ZuluTime> for FfiZuluTime {
    fn from(time: qe::ZuluTime) -> Self {
        FfiZuluTime { hour: time.hour, minute: time.minute }
    }
}

/// Structured result of parsing one callsign's worth of quick entry.
#[derive(uniffi::Record)]
pub struct FfiQuickEntry {
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
    pub rst_conflicts: Vec<FfiRstConflict>,
    pub zulu_time: Option<FfiZuluTime>,
}

impl From<qe::QuickEntryResult> for FfiQuickEntry {
    fn from(result: qe::QuickEntryResult) -> Self {
        FfiQuickEntry {
            callsign: result.callsign,
            rst_sent: result.rst_sent,
            rst_received: result.rst_received,
            state: result.state,
            their_park: result.their_park,
            their_grid: result.their_grid,
            frequency: result.frequency,
            band: result.band,
            mode: result.mode,
            notes: result.notes,
            rst_conflicts: result.rst_conflicts.into_iter().map(FfiRstConflict::from).collect(),
            zulu_time: result.zulu_time.map(FfiZuluTime::from),
        }
    }
}

/// A typed token for the live preview.
#[derive(uniffi::Record)]
pub struct FfiQuickToken {
    pub index: u32,
    pub text: String,
    pub token_type: FfiQuickTokenType,
}

impl From<qe::ParsedToken> for FfiQuickToken {
    fn from(token: qe::ParsedToken) -> Self {
        FfiQuickToken {
            index: token.index as u32,
            text: token.text,
            token_type: token.token_type.into(),
        }
    }
}

/// Session-metadata updates parsed from a callsign-less logger line. Tokens a
/// session can't take (parks, states, RSTs, times, free text) are returned in
/// `unsupported` so the UI can tell the user they were ignored.
#[derive(uniffi::Record)]
pub struct FfiSessionMetadataEntry {
    pub frequency: Option<f64>,
    pub band: Option<String>,
    pub mode: Option<String>,
    pub grid: Option<String>,
    pub unsupported: Vec<String>,
}

impl From<qe::SessionMetadataResult> for FfiSessionMetadataEntry {
    fn from(result: qe::SessionMetadataResult) -> Self {
        FfiSessionMetadataEntry {
            frequency: result.frequency,
            band: result.band,
            mode: result.mode,
            grid: result.grid,
            unsupported: result.unsupported,
        }
    }
}

/// Parse a callsign-less line (e.g. `"14.046 CW"`) into session-metadata
/// updates for the active logging session, or `None` when the line contains a
/// callsign or no settable field (frequency, mode, grid).
#[uniffi::export]
pub fn parse_quick_entry_session_metadata(input: String) -> Option<FfiSessionMetadataEntry> {
    qe::parse_session_metadata(&input).map(FfiSessionMetadataEntry::from)
}

/// Parse a quick-entry line into a structured result, or `None` if the input
/// isn't valid quick entry (fewer than two tokens / first isn't a callsign).
#[uniffi::export]
pub fn parse_quick_entry(input: String, rst_order: FfiRstOrder) -> Option<FfiQuickEntry> {
    qe::parse(&input, rst_order.into()).map(FfiQuickEntry::from)
}

/// Parse a line that may contain several callsigns sharing the same metadata.
#[uniffi::export]
pub fn parse_quick_entry_multi(input: String, rst_order: FfiRstOrder) -> Option<Vec<FfiQuickEntry>> {
    qe::parse_multi(&input, rst_order.into())
        .map(|results| results.into_iter().map(FfiQuickEntry::from).collect())
}

/// Parse into typed tokens for the color-coded preview chips.
#[uniffi::export]
pub fn parse_quick_entry_tokens(input: String, rst_order: FfiRstOrder) -> Vec<FfiQuickToken> {
    qe::parse_tokens(&input, rst_order.into()).into_iter().map(FfiQuickToken::from).collect()
}

/// Multi-callsign variant of [`parse_quick_entry_tokens`].
#[uniffi::export]
pub fn parse_quick_entry_multi_tokens(input: String, rst_order: FfiRstOrder) -> Vec<FfiQuickToken> {
    qe::parse_multi_tokens(&input, rst_order.into()).into_iter().map(FfiQuickToken::from).collect()
}

// ---- Token predicates (so Swift's QuickEntryParser helpers can delegate) ----

#[uniffi::export]
pub fn quick_entry_is_callsign(value: String) -> bool {
    qe::is_callsign(&value)
}

#[uniffi::export]
pub fn quick_entry_is_rst(value: String) -> bool {
    qe::is_rst(&value)
}

#[uniffi::export]
pub fn quick_entry_is_park_reference(value: String) -> bool {
    qe::is_park_reference(&value)
}

#[uniffi::export]
pub fn quick_entry_is_grid_square(value: String) -> bool {
    qe::is_grid_square(&value)
}

#[uniffi::export]
pub fn quick_entry_is_state_or_region(value: String) -> bool {
    qe::is_state_or_region(&value)
}

#[uniffi::export]
pub fn quick_entry_is_mode(value: String) -> bool {
    qe::is_mode(&value)
}

/// Parse a standalone UTC time token (`HH:MM`, `HHMMZ`, …), or `None`.
#[uniffi::export]
pub fn quick_entry_parse_zulu_time(value: String) -> Option<FfiZuluTime> {
    qe::parse_zulu_time(&value).map(FfiZuluTime::from)
}

/// An explicit R/S suffix detected on an RST token.
#[derive(uniffi::Enum)]
pub enum FfiRstSuffix {
    None,
    Received,
    Sent,
}

impl From<qe::RstSuffix> for FfiRstSuffix {
    fn from(suffix: qe::RstSuffix) -> Self {
        match suffix {
            qe::RstSuffix::None => FfiRstSuffix::None,
            qe::RstSuffix::Received => FfiRstSuffix::Received,
            qe::RstSuffix::Sent => FfiRstSuffix::Sent,
        }
    }
}

/// An RST token split into its numeric value and detected suffix.
#[derive(uniffi::Record)]
pub struct FfiStrippedRst {
    pub value: String,
    pub suffix: FfiRstSuffix,
}

/// Strip an R/S suffix from an RST token, returning the value and suffix kind.
#[uniffi::export]
pub fn quick_entry_strip_rst_suffix(value: String) -> FfiStrippedRst {
    let (stripped, suffix) = qe::strip_rst_suffix(&value);
    FfiStrippedRst { value: stripped, suffix: suffix.into() }
}
