//! Activities server — Carrier Wave's Rust backend.
//!
//! Library facade so integration tests (`server/tests/*.rs`) can call into
//! handlers and DB queries directly. `src/main.rs` is the binary entry
//! point and lives alongside.

pub mod achievements;
pub mod aggregators;
pub mod auth;
pub mod config;
pub mod contest;
pub mod db;
pub mod error;
pub mod extractors;
pub mod handlers;
pub mod macros;
pub mod metrics;
pub mod models;
pub mod observability;
pub mod rbn;
pub mod snapshots;
pub mod sota_az;
pub mod storage;
