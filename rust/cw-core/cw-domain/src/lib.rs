//! Carrier Wave portable domain logic.
//!
//! Pure, dependency-light ports of `CarrierWaveCore`'s Swift logic. No I/O, no
//! platform frameworks — everything here compiles for Apple, Android, Linux and
//! Windows identically and is the foundation the UniFFI surface (`cw-ffi`) is
//! built on.
//!
//! Phase 2 of the migration is closed on the Rust side: every Swift module
//! identified for the domain layer is ported, including the reference-data
//! tables (DXCC primary-prefix table, US FCC band plan, Natural Earth
//! coastlines). `data/coastline.json` is the canonical source for the
//! ~5,000 coastline coordinate pairs the iOS/macOS apps draw; the Swift side
//! is regenerated from here.

pub mod adif;
pub mod adif_catalog;
pub mod adif_validator;
pub mod adif_writer;
pub mod antenna;
pub mod azimuthal;
pub mod band;
pub mod band_plan;
pub mod brag_sheet;
pub mod frequency_planner;
pub mod frequency_scope;
pub mod gear_reminders;
pub mod great_circle;
pub mod map_bounds;
pub mod callsign_detector;
pub mod callsign_edit_distance;
pub mod callsign_flag;
pub mod catalog_matcher;
pub mod civ;
pub mod club_cache;
pub mod coastline;
pub mod contest;
pub mod continent;
pub mod cty;
pub mod cw_text_element;
pub mod dedup;
pub mod fmt;
pub mod hunter_log;
pub mod iaru_region;
pub mod kenwood;
pub mod kiwisdr;
pub mod location_prefix;
pub mod maidenhead;
pub mod logger_command;
pub mod mode;
pub mod morse;
pub mod multiplier;
pub mod nato_phonetics;
pub mod park_geometry;
pub mod park_reference;
pub mod polo_notes;
pub mod prefix_suggest;
pub mod propagation;
pub mod query;
pub mod quick_entry;
pub mod reference_csv;
pub mod satellite;
pub mod scp;
pub mod service_type;
pub mod share_render;
pub mod skcc;
pub mod spots;
pub mod sql_format;
pub mod streak;
pub mod text_protocol;
pub mod timeline;
pub mod tota;
pub mod us_grid_state;
pub mod wsjtx;
pub mod yaesu;

pub use band::BandUtilities;
pub use callsign_flag::flag_for_callsign;
pub use hunter_log::{band_mode_park_key, derive_dxcc, DxccDerivation};
pub use maidenhead::{Coordinate, Precision};
pub use logger_command::{command_row_catalog, CommandRowItem, LoggerCommand};
pub use mode::{default_rst, is_metadata_mode, ModeEquivalence, ModeFamily, METADATA_MODES};
pub use service_type::{ServiceType, SyncMode};
