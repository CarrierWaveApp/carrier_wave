//! UniFFI surface for the logger command parser (`cw_domain::logger_command`).
//!
//! Both apps parse logger commands here so the grammar (`FREQ`/`SPOT`/`RBN`/… +
//! aliases) lives in Rust, not duplicated per platform. What each command *does*
//! (present a panel, self-spot, …) and its icon stay host-side.

use cw_domain::logger_command as lc;

use crate::quick_entry::{FfiQuickEntry, FfiSessionMetadataEntry};

/// A parsed logger command. Mirrors `cw_domain::LoggerCommand`; the host maps
/// this to its native action + icon.
#[derive(uniffi::Enum)]
pub enum FfiLoggerCommand {
    Frequency { mhz: f64 },
    Mode { mode: String },
    Spot { comment: Option<String>, repeat_minutes: Option<i32> },
    SpotStop,
    Rbn { callsign: Option<String> },
    Hunt,
    HuntLog { entry: FfiQuickEntry },
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
    MyCall { callsign: String },
    SessionMetadata { entry: FfiSessionMetadataEntry },
}

impl From<lc::LoggerCommand> for FfiLoggerCommand {
    fn from(command: lc::LoggerCommand) -> Self {
        match command {
            lc::LoggerCommand::Frequency(mhz) => FfiLoggerCommand::Frequency { mhz },
            lc::LoggerCommand::Mode(mode) => FfiLoggerCommand::Mode { mode },
            lc::LoggerCommand::Spot { comment, repeat_minutes } => {
                FfiLoggerCommand::Spot { comment, repeat_minutes }
            }
            lc::LoggerCommand::SpotStop => FfiLoggerCommand::SpotStop,
            lc::LoggerCommand::Rbn { callsign } => FfiLoggerCommand::Rbn { callsign },
            lc::LoggerCommand::Hunt => FfiLoggerCommand::Hunt,
            lc::LoggerCommand::HuntLog(result) => {
                FfiLoggerCommand::HuntLog { entry: FfiQuickEntry::from(result) }
            }
            lc::LoggerCommand::P2p => FfiLoggerCommand::P2p,
            lc::LoggerCommand::S2s => FfiLoggerCommand::S2s,
            lc::LoggerCommand::Solar => FfiLoggerCommand::Solar,
            lc::LoggerCommand::Weather => FfiLoggerCommand::Weather,
            lc::LoggerCommand::Map => FfiLoggerCommand::Map,
            lc::LoggerCommand::Hidden => FfiLoggerCommand::Hidden,
            lc::LoggerCommand::Help => FfiLoggerCommand::Help,
            lc::LoggerCommand::Note { text } => FfiLoggerCommand::Note { text },
            lc::LoggerCommand::Manual => FfiLoggerCommand::Manual,
            lc::LoggerCommand::Websdr => FfiLoggerCommand::Websdr,
            lc::LoggerCommand::Band => FfiLoggerCommand::Band,
            lc::LoggerCommand::Rig => FfiLoggerCommand::Rig,
            lc::LoggerCommand::Checklist => FfiLoggerCommand::Checklist,
            lc::LoggerCommand::Radio => FfiLoggerCommand::Radio,
            lc::LoggerCommand::Replay => FfiLoggerCommand::Replay,
            lc::LoggerCommand::MyCall(callsign) => FfiLoggerCommand::MyCall { callsign },
            lc::LoggerCommand::SessionMetadata(result) => {
                FfiLoggerCommand::SessionMetadata { entry: FfiSessionMetadataEntry::from(result) }
            }
        }
    }
}

/// Parse `input` into a logger command, or `None` when it isn't one (the host
/// then treats it as a callsign / QSO).
#[uniffi::export]
pub fn parse_logger_command(input: String) -> Option<FfiLoggerCommand> {
    lc::parse(&input).map(FfiLoggerCommand::from)
}

/// One entry in the keyboard command row. `key` is the stable id, `label` the
/// button text, `insert` the text placed in the entry field when tapped,
/// `description` the tooltip. The icon stays host-native.
#[derive(uniffi::Record)]
pub struct FfiCommandRowItem {
    pub key: String,
    pub label: String,
    pub insert: String,
    pub description: String,
}

impl From<lc::CommandRowItem> for FfiCommandRowItem {
    fn from(item: lc::CommandRowItem) -> Self {
        FfiCommandRowItem {
            key: item.key,
            label: item.label,
            insert: item.insert,
            description: item.description,
        }
    }
}

/// The command-row catalog (display order) — the shared source for both apps'
/// keyboard command rows.
#[uniffi::export]
pub fn logger_command_row_catalog() -> Vec<FfiCommandRowItem> {
    lc::command_row_catalog().into_iter().map(FfiCommandRowItem::from).collect()
}
