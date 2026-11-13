//! Carrier Wave sync engine — journal, conflict resolution, and transport.
//!
//! Ported from `CarrierWaveData/CloudSync`. The hard parts (the change journal,
//! field-level conflict resolution, and last-writer-wins semantics) are pure and
//! transport-agnostic; CloudKit was merely the transport, now swappable for the
//! HTTPS sync server (see [`transport`]).

pub mod conflict;
pub mod error;
pub mod http_transport;
pub mod journal;
pub mod transport;

pub use conflict::{
    merge_logging_session, merge_notes, merge_qso, pick_optional, pick_value, LoggingSessionPayload,
    SyncQso,
};
pub use error::SyncError;
pub use http_transport::HttpSyncTransport;
pub use journal::{JournalEntityType, JournalOperation, JournalPayload, SyncedConfigPayload};
pub use transport::{InMemoryTransport, SyncTransport};
