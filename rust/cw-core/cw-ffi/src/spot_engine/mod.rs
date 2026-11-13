//! Shared spots engine (plan: `docs/plans/2026-07-02-spots-engine-rust-port.md`,
//! Phase 3). `SpotEngineApi` is the UniFFI surface; `scope_db` is the
//! in-memory SQL projection behind the query workbench.

pub mod scope_db;

mod api;
mod types;
