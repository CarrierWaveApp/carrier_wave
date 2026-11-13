//! UniFFI surface for the Super Check Partial database (`cw_domain::scp`).
//!
//! Exposed as an Object so the loaded ~80K-callsign database lives once in Rust
//! and both the Apple apps and `android/` query it identically. `merging`
//! returns a fresh database (the user's repeat contacts augmenting MASTER.SCP).

use std::sync::Arc;

use cw_domain::scp::ScpDatabase as CoreScp;

/// A near-match result: a candidate callsign and its edit distance.
#[derive(uniffi::Record)]
pub struct FfiScpNearMatch {
    pub callsign: String,
    pub distance: u32,
}

/// In-memory Super Check Partial database, shared by Swift + Kotlin.
#[derive(uniffi::Object)]
pub struct ScpDatabase {
    inner: CoreScp,
}

#[uniffi::export]
impl ScpDatabase {
    /// Build from callsigns (deduplicated, uppercased, empties dropped).
    #[uniffi::constructor]
    pub fn new(callsigns: Vec<String>) -> Self {
        Self { inner: CoreScp::new(callsigns) }
    }

    /// Number of callsigns in the database.
    pub fn count(&self) -> u64 {
        self.inner.count() as u64
    }

    /// Whether the database has no callsigns loaded.
    pub fn is_empty(&self) -> bool {
        self.inner.is_empty()
    }

    /// Classic SCP: prefix matches first, then substring. Fragments shorter
    /// than 3 chars return empty. Up to `limit` results.
    pub fn partial_match(&self, fragment: String, limit: u32) -> Vec<String> {
        self.inner.partial_match(&fragment, limit as usize)
    }

    /// Exact (case-insensitive) membership.
    pub fn contains(&self, callsign: String) -> bool {
        self.inner.contains(&callsign)
    }

    /// A new database with `additional` callsigns merged in.
    pub fn merging(&self, additional: Vec<String>) -> Arc<ScpDatabase> {
        Arc::new(ScpDatabase { inner: self.inner.merging(additional) })
    }

    /// Near-misses within `max_distance` for a complete (4+ char) callsign,
    /// sorted by distance, excluding exact matches.
    pub fn near_matches(&self, callsign: String, max_distance: u32) -> Vec<FfiScpNearMatch> {
        self.inner
            .near_matches(&callsign, max_distance as usize)
            .into_iter()
            .map(|(callsign, distance)| FfiScpNearMatch { callsign, distance: distance as u32 })
            .collect()
    }
}
