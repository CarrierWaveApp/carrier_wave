//! Shared spots engine domain logic — the pure core of the Sweep/iOS spot
//! pipeline port (plan: `docs/plans/2026-07-02-spots-engine-rust-port.md`).
//!
//! Sources of truth ported here: CW Sweep's `Models/Spots/*` and
//! `Services/Spots/SpotAggregator.swift` (merge/prune), plus iOS's
//! `SpotNeedsMatcher`/`NeedsSnapshot`. No I/O — source clients live in
//! `cw-net`, the engine loop in `cw-ffi`.

pub mod band_edges;
pub mod cluster_parser;
pub mod filters;
pub mod goal_profile;
pub mod merge;
pub mod model;
pub mod needs;
pub mod observations;
pub mod region;

pub use filters::{FilterContext, SpotFilter, SpotModeFilter, SpotStatusFilter};
pub use goal_profile::{
    compile_profile_queries, BasePredicate, CompiledProfileQueries, GoalProfile, QuickToggles,
};
pub use merge::SpotPool;
pub use model::{
    EnrichedSpot, MatchedNeed, NeedCategory, NeededStatus, NeedPriority, SpotSource, UnifiedSpot,
};
pub use needs::{NeedsPreferences, NeedsSnapshot};
pub use region::{SpotContinent, SpotRegion, SpotRegionGroup};
