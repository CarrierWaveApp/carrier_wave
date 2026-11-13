//! UniFFI surface for the Ham2K Polo callsign-notes parser
//! (`cw_domain::polo_notes`). Downloading/merging note files stays host-side;
//! the line grammar + emoji/name/note split live in Rust.

use std::collections::HashMap;

use cw_domain::polo_notes::{self, PoloNotesEntry};

/// A parsed Polo notes entry.
#[derive(uniffi::Record)]
pub struct FfiPoloNotesEntry {
    pub callsign: String,
    pub emoji: Option<String>,
    pub name: Option<String>,
    pub note: Option<String>,
}

impl From<PoloNotesEntry> for FfiPoloNotesEntry {
    fn from(entry: PoloNotesEntry) -> Self {
        FfiPoloNotesEntry {
            callsign: entry.callsign,
            emoji: entry.emoji,
            name: entry.name,
            note: entry.note,
        }
    }
}

/// Parse a Polo notes file into a map of uppercase callsign → entry.
#[uniffi::export]
pub fn parse_polo_notes(content: String) -> HashMap<String, FfiPoloNotesEntry> {
    polo_notes::parse(&content).into_iter().map(|(key, value)| (key, value.into())).collect()
}

/// Parse a single non-empty, non-comment line, or `None` if it isn't a
/// callsign line.
#[uniffi::export]
pub fn parse_polo_note_line(line: String) -> Option<FfiPoloNotesEntry> {
    polo_notes::parse_line(&line).map(Into::into)
}

/// Build an entry from a known callsign and the note text following it
/// (the callsign is assumed already validated by the caller).
#[uniffi::export]
pub fn polo_note_from_text(callsign: String, note_text: String) -> FfiPoloNotesEntry {
    PoloNotesEntry::from_note_text(&callsign, &note_text).into()
}
