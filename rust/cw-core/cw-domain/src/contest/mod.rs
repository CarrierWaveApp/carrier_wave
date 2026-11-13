//! Contest engine (server contest-definition format v0.3). Ports:
//! - `Models/ContestDefinition.swift` / `ContestExchange.swift` /
//!   `ContestScoring.swift` / `ContestScoringRule.swift` /
//!   `ContestSchedule.swift` / `ContestOperatingConstraints.swift` → `model`
//! - `Services/Contest/ContestEngine.swift` (+ `+Phases.swift`) → `engine`
//! - `Services/Contest/ContestConditionContext.swift` → `condition`
//! - `Services/Contest/ContestExchangeParser.swift` → `exchange_parser`
//! - `Services/Contest/ContestCallsign.swift` → `callsign`
//! - `Services/Contest/CabrilloExportService.swift` → `cabrillo`
//! - `Services/Contest/ContestScheduleEvaluator.swift`
//!   (+ `ContestAnnualResolver.swift`) → `schedule`
//! - `Services/Contest/OffTimeTracker.swift` → `off_time`
//! - `Services/Contest/BandChangeTracker.swift` → `band_change`
//! - `Services/Contest/ContestEnrichmentMatcher.swift` → `enrichment`
//!
//! The engine is pure: definitions are parsed from server JSON, QSOs come in
//! as value snapshots with caller-resolved derived fields (country, zones),
//! and all "now"-dependent entry points take an explicit timestamp.

pub mod band_change;
pub mod cabrillo;
pub mod callsign;
pub mod condition;
pub mod engine;
pub mod enrichment;
pub mod exchange_parser;
pub mod model;
pub mod off_time;
pub mod schedule;

pub use band_change::{BandChangeSummary, BandChangeViolation};
pub use cabrillo::{CabrilloContext, CabrilloQso, CabrilloSession};
pub use condition::ContestConditionValue;
pub use engine::{ContestDupeStatus, ContestEngine, ContestQsoRecord, ContestScoreSnapshot,
    MyStationContext, RateBucket};
pub use exchange_parser::ContestExchangeParseResult;
pub use model::{ContestDefinition, JsonValue};
pub use off_time::{OffPeriod, OffTimeSummary, OffTimeViolation};
pub use schedule::ContestOccurrence;
