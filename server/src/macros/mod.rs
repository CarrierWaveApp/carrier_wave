//! Radio macros — server-side schema, verifier, opcode tables, and validators.
//!
//! `verifier_generated.rs` is produced by `Tools/macro-codegen` from the
//! shared `macro-step-schema.json`. The hand-written modules here mirror
//! the corresponding Swift types in `swift/packages/CarrierWaveData/Sources/
//! CarrierWaveData/Macros/`. Stay in sync with the Swift side; the shared
//! fixture corpus catches drift in CI.

pub mod band_plan;
pub mod opcodes;
pub mod slug;
pub mod spec;
pub mod tag_vocabulary;
pub mod telemetry;
pub mod verifier;
pub mod verifier_generated;
