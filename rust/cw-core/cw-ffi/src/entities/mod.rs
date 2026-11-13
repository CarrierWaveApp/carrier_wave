//! Per-entity FFI surface for the synced `cw-store` entities (Phase 4 rewire).
//!
//! Each submodule mirrors one `cw-store` entity: an `Ffi<Entity>` `uniffi::Record`
//! DTO (+ `From` conversions both ways), an `Ffi<Entity>Filter` where the store
//! has a filter, and an `#[uniffi::export] impl FieldStore` block delegating to
//! the locked `cw_store::Store`. QSO stays in `lib.rs` as the template.

pub(crate) mod activation_metadata;
pub(crate) mod activity_log;
mod cloud_sync_metadata;
mod club;
mod club_member;
pub(crate) mod equipment_item;
mod friendship;
mod loadout;
pub(crate) mod logging_session;
pub(crate) mod pota_park;
mod radio_macro;
pub(crate) mod rove_stop;
pub(crate) mod service_presence;
mod session_spot;
mod upload_destination;
mod websdr_favorite;
mod websdr_recording;
