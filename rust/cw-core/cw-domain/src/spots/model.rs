//! Unified spot model. Port of CW Sweep's `UnifiedSpot.swift`, `SpotSource.swift`,
//! and the `EnrichedSpot` wrapper from `SpotRegion.swift`, extended with the
//! iOS-only PSKReporter source and per-spot matched needs.
//!
//! Timestamps are unix epoch seconds (the [`crate::dedup::QsoSnapshot`]
//! convention) so the model stays portable across FFI boundaries.

use crate::band::BandUtilities;
use crate::skcc::SkccMember;
use crate::spots::region::SpotRegion;

/// Source of a spot (model-level, not UI filter). Mirrors Sweep's `SpotSource`
/// plus `Pskr` (iOS hunter feed).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SpotSource {
    Rbn,
    Pota,
    Sota,
    Wwff,
    DxSummit,
    DxHeat,
    DxWatch,
    Cluster,
    Pskr,
}

impl SpotSource {
    /// Raw value, matching the Swift `rawValue` spelling (used in persisted
    /// filter configs and the `SessionSpot.source` column).
    pub fn raw_value(self) -> &'static str {
        match self {
            SpotSource::Rbn => "rbn",
            SpotSource::Pota => "pota",
            SpotSource::Sota => "sota",
            SpotSource::Wwff => "wwff",
            SpotSource::DxSummit => "dxSummit",
            SpotSource::DxHeat => "dxHeat",
            SpotSource::DxWatch => "dxWatch",
            SpotSource::Cluster => "cluster",
            SpotSource::Pskr => "pskr",
        }
    }

    pub fn from_raw(raw: &str) -> Option<SpotSource> {
        Some(match raw {
            "rbn" => SpotSource::Rbn,
            "pota" => SpotSource::Pota,
            "sota" => SpotSource::Sota,
            "wwff" => SpotSource::Wwff,
            "dxSummit" => SpotSource::DxSummit,
            "dxHeat" => SpotSource::DxHeat,
            "dxWatch" => SpotSource::DxWatch,
            "cluster" => SpotSource::Cluster,
            "pskr" => SpotSource::Pskr,
            _ => return None,
        })
    }

    pub fn display_name(self) -> &'static str {
        match self {
            SpotSource::Rbn => "RBN",
            SpotSource::Pota => "POTA",
            SpotSource::Sota => "SOTA",
            SpotSource::Wwff => "WWFF",
            SpotSource::DxSummit => "DX Summit",
            SpotSource::DxHeat => "DXHeat",
            SpotSource::DxWatch => "DXWatch",
            SpotSource::Cluster => "Cluster",
            SpotSource::Pskr => "PSKReporter",
        }
    }

    pub fn short_name(self) -> &'static str {
        match self {
            SpotSource::Rbn => "RBN",
            SpotSource::Pota => "POTA",
            SpotSource::Sota => "SOTA",
            SpotSource::Wwff => "WWFF",
            SpotSource::DxSummit => "DXSum",
            SpotSource::DxHeat => "DXHt",
            SpotSource::DxWatch => "DXW",
            SpotSource::Cluster => "Clstr",
            SpotSource::Pskr => "PSKR",
        }
    }

    /// Merge priority: on a dedup-key collision the higher-priority source
    /// wins. Sweep's table verbatim (`SpotAggregator.swift:19`), with `Pskr`
    /// slotted just above RBN — both are machine spots, and every
    /// human/program-curated source should out-rank them.
    pub fn merge_priority(self) -> u8 {
        match self {
            SpotSource::Rbn => 0,
            SpotSource::Pskr => 1,
            SpotSource::Wwff => 2,
            SpotSource::Sota => 3,
            SpotSource::Pota => 4,
            SpotSource::DxSummit => 5,
            SpotSource::DxHeat => 6,
            SpotSource::DxWatch => 7,
            SpotSource::Cluster => 8,
        }
    }
}

/// DXCC needed status for a spot. Port of Sweep's `NeededStatus`
/// (`DXCCNeededChecker.swift:26`); variant order carries the Swift
/// `Comparable` ordering (most-needed first).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum NeededStatus {
    /// New DXCC entity never worked on any band/mode.
    NewEntity,
    /// Entity worked, but not on this band.
    NewBandSlot,
    /// Entity worked on this band, but not confirmed.
    WorkedNotConfirmed,
    /// Entity worked and confirmed on this band.
    Confirmed,
    /// Cannot determine (no DXCC entity resolved).
    Unknown,
}

/// A spot from any source in a unified format. Field-for-field port of
/// Sweep's `UnifiedSpot.swift`.
#[derive(Debug, Clone, PartialEq)]
pub struct UnifiedSpot {
    /// Prefixed id: `rbn-…`, `pota-…`, `sota-…`, `wwff-…`, `dxs-…`, `dxh-…`,
    /// `dxw-…`, `cluster-…`, `pskr-…`.
    pub id: String,
    pub callsign: String,
    pub frequency_khz: f64,
    pub mode: String,
    /// Unix epoch seconds.
    pub timestamp: i64,
    pub source: SpotSource,

    // RBN-specific fields
    pub snr: Option<i32>,
    pub wpm: Option<i32>,
    pub spotter: Option<String>,
    pub spotter_grid: Option<String>,

    // POTA-specific fields
    pub park_ref: Option<String>,
    pub park_name: Option<String>,
    pub comments: Option<String>,
    /// POTA's raw `source` field ("RBN" for skimmer-relayed spots) — feeds
    /// the host's human-vs-automated split (`isHumanSpot` on iOS).
    pub pota_source: Option<String>,

    // SOTA-specific fields
    pub summit_code: Option<String>,
    pub summit_name: Option<String>,
    pub summit_points: Option<i32>,

    // WWFF-specific fields
    pub wwff_ref: Option<String>,
    pub wwff_name: Option<String>,

    // DX web spot enrichment fields
    pub dx_grid: Option<String>,
    pub continent: Option<String>,
    pub split_info: Option<String>,
    pub lotw_user: Option<bool>,
    pub dxcc_prefix: Option<String>,
    pub cq_zone: Option<i32>,
    pub iota_ref: Option<String>,

    // Location fields
    pub location_desc: Option<String>,
    pub state_abbr: Option<String>,
}

impl UnifiedSpot {
    /// A spot with only the universal fields set; factory mappers fill in the
    /// source-specific extras. Keeps call sites from spelling 20 `None`s.
    #[allow(clippy::too_many_arguments)]
    pub fn base(
        id: String,
        callsign: String,
        frequency_khz: f64,
        mode: String,
        timestamp: i64,
        source: SpotSource,
    ) -> UnifiedSpot {
        UnifiedSpot {
            id,
            callsign,
            frequency_khz,
            mode,
            timestamp,
            source,
            snr: None,
            wpm: None,
            spotter: None,
            spotter_grid: None,
            park_ref: None,
            park_name: None,
            comments: None,
            pota_source: None,
            summit_code: None,
            summit_name: None,
            summit_points: None,
            wwff_ref: None,
            wwff_name: None,
            dx_grid: None,
            continent: None,
            split_info: None,
            lotw_user: None,
            dxcc_prefix: None,
            cq_zone: None,
            iota_ref: None,
            location_desc: None,
            state_abbr: None,
        }
    }

    pub fn frequency_mhz(&self) -> f64 {
        self.frequency_khz / 1_000.0
    }

    /// Band derived from frequency; empty string when unknown (Swift parity —
    /// `UnifiedSpot.band` returns `""` so dedup keys stay stable).
    pub fn band(&self) -> &'static str {
        BandUtilities::derive_band(Some(self.frequency_khz)).unwrap_or("")
    }

    pub fn formatted_frequency(&self) -> String {
        format!("{:.1} kHz", self.frequency_khz)
    }

    /// Deduplication key: uppercased callsign + band.
    pub fn dedup_key(&self) -> String {
        format!("{}-{}", self.callsign.to_uppercase(), self.band())
    }

    /// Display name for the reference (park, summit, or WWFF ref).
    pub fn reference_display(&self) -> Option<&str> {
        self.park_ref
            .as_deref()
            .or(self.summit_code.as_deref())
            .or(self.wwff_ref.as_deref())
    }

    /// Display name for the location.
    pub fn location_display(&self) -> Option<&str> {
        self.park_name
            .as_deref()
            .or(self.summit_name.as_deref())
            .or(self.wwff_name.as_deref())
    }

    /// Is this spot the user spotting themselves? Compares base callsigns
    /// (portable-suffix stripped).
    pub fn is_self_spot(&self, user_callsign: &str) -> bool {
        normalize_callsign(user_callsign) == normalize_callsign(&self.callsign)
    }
}

/// Guess mode from comment text and frequency position within the band.
/// Port of `UnifiedSpot.guessMode` (Sweep): comment token first, then the
/// band-edge digital/SSB boundary heuristic, defaulting to CW.
pub fn guess_mode(comment: Option<&str>, frequency_khz: f64) -> &'static str {
    if let Some(comment) = comment {
        if let Some(parsed) = crate::spots::cluster_parser::parse_mode(comment) {
            return parsed;
        }
    }
    if let Some(edge) = crate::spots::band_edges::band_for(frequency_khz) {
        if let Some(digital_bound) = edge.digital_boundary_khz() {
            if frequency_khz < digital_bound {
                return "CW";
            }
        }
        if let Some(ssb_bound) = edge.ssb_boundary_khz() {
            if frequency_khz >= ssb_bound {
                return "SSB";
            }
        }
        return "DIGI";
    }
    "CW"
}

/// Uppercase and strip everything from the first `/` (portable designators).
fn normalize_callsign(callsign: &str) -> String {
    let upper = callsign.to_uppercase();
    match upper.find('/') {
        Some(idx) => upper[..idx].to_string(),
        None => upper,
    }
}

/// What the operator still needs — each variant carries enough context for
/// display labels and spot matching. Port of iOS `NeedCategory`
/// (`NeedTypes.swift`).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum NeedCategory {
    DxccEntity { entity: String },
    DxccBandSlot { entity: String, band: String },
    WasState { state: String },
    WasStateMode { state: String, mode: String },
    PotaNewPark,
    PotaActivatorState { state: String },
    PotaActivatorEntity { entity: String },
    WwffNewReference,
    Custom { pattern: String, label: String },
}

impl NeedCategory {
    /// Stable string key for the `scope.spot_needs` SQL projection —
    /// what goal-profile queries match against.
    pub fn key(&self) -> &'static str {
        match self {
            NeedCategory::DxccEntity { .. } => "dxcc",
            NeedCategory::DxccBandSlot { .. } => "dxcc_band",
            NeedCategory::WasState { .. } => "was",
            NeedCategory::WasStateMode { .. } => "was_mode",
            NeedCategory::PotaNewPark => "pota_new_park",
            NeedCategory::PotaActivatorState { .. } => "pota_activator_state",
            NeedCategory::PotaActivatorEntity { .. } => "pota_activator_entity",
            NeedCategory::WwffNewReference => "wwff",
            NeedCategory::Custom { .. } => "custom",
        }
    }
}

/// Urgency level for a matched need. Port of iOS `NeedPriority`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum NeedPriority {
    Low,
    Medium,
    High,
}

/// A need matched against a specific spot. Port of iOS `MatchedNeed`
/// (structural equality here; Swift's per-instance UUID identity only
/// serves SwiftUI list diffing).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MatchedNeed {
    pub category: NeedCategory,
    pub label: String,
    pub priority: NeedPriority,
}

/// A spot enriched with distance, region, DXCC, and needs information.
/// Port of Sweep's `EnrichedSpot` + iOS's `matchedNeeds` extension.
#[derive(Debug, Clone, PartialEq)]
pub struct EnrichedSpot {
    pub spot: UnifiedSpot,
    pub distance_meters: Option<f64>,
    pub bearing_degrees: Option<f64>,
    pub region: SpotRegion,
    pub state: Option<String>,
    pub country: Option<String>,
    pub dxcc_entity: Option<String>,
    pub dxcc_code: Option<i32>,
    pub needed_status: NeededStatus,
    pub operator_name: Option<String>,
    pub skcc_member: Option<SkccMember>,
    /// iOS hunter-log needs matches; empty when needs matching is off.
    pub matched_needs: Vec<MatchedNeed>,
}

impl EnrichedSpot {
    /// Bare enrichment wrapper with nothing resolved yet.
    pub fn bare(spot: UnifiedSpot, region: SpotRegion) -> EnrichedSpot {
        EnrichedSpot {
            spot,
            distance_meters: None,
            bearing_degrees: None,
            region,
            state: None,
            country: None,
            dxcc_entity: None,
            dxcc_code: None,
            needed_status: NeededStatus::Unknown,
            operator_name: None,
            skcc_member: None,
            matched_needs: Vec::new(),
        }
    }

    pub fn id(&self) -> &str {
        &self.spot.id
    }

    pub fn distance_miles(&self) -> Option<f64> {
        self.distance_meters.map(|m| m / 1_609.344)
    }

    pub fn distance_km(&self) -> Option<f64> {
        self.distance_meters.map(|m| m / 1_000.0)
    }

    /// Best available location string: state (for US) or country.
    pub fn location_display(&self) -> Option<&str> {
        if let Some(state) = self.state.as_deref() {
            if !state.is_empty() {
                return Some(state);
            }
        }
        if let Some(country) = self.country.as_deref() {
            if !country.is_empty() {
                return Some(country);
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spot(callsign: &str, khz: f64, source: SpotSource) -> UnifiedSpot {
        UnifiedSpot::base(
            format!("{}-1", source.raw_value()),
            callsign.to_string(),
            khz,
            "CW".to_string(),
            1_700_000_000,
            source,
        )
    }

    #[test]
    fn dedup_key_uppercases_and_appends_band() {
        let s = spot("w6jy", 14_040.0, SpotSource::Rbn);
        assert_eq!(s.dedup_key(), "W6JY-20m");
    }

    #[test]
    fn dedup_key_empty_band_out_of_range() {
        let s = spot("W6JY", 2_500.0, SpotSource::Rbn);
        assert_eq!(s.dedup_key(), "W6JY-");
    }

    #[test]
    fn self_spot_strips_portable_suffix() {
        let s = spot("W6JY/P", 7_040.0, SpotSource::Pota);
        assert!(s.is_self_spot("w6jy"));
        assert!(!s.is_self_spot("W1AW"));
    }

    #[test]
    fn reference_display_prefers_park() {
        let mut s = spot("W6JY", 14_040.0, SpotSource::Pota);
        s.park_ref = Some("US-1234".to_string());
        s.summit_code = Some("W6/CT-001".to_string());
        assert_eq!(s.reference_display(), Some("US-1234"));
    }

    #[test]
    fn merge_priority_matches_sweep_table_order() {
        // Sweep order preserved: rbn < wwff < sota < pota < dxSummit <
        // dxHeat < dxWatch < cluster; pskr sits between rbn and wwff.
        let order = [
            SpotSource::Rbn,
            SpotSource::Pskr,
            SpotSource::Wwff,
            SpotSource::Sota,
            SpotSource::Pota,
            SpotSource::DxSummit,
            SpotSource::DxHeat,
            SpotSource::DxWatch,
            SpotSource::Cluster,
        ];
        for pair in order.windows(2) {
            assert!(pair[0].merge_priority() < pair[1].merge_priority());
        }
    }

    #[test]
    fn needed_status_orders_most_needed_first() {
        assert!(NeededStatus::NewEntity < NeededStatus::NewBandSlot);
        assert!(NeededStatus::NewBandSlot < NeededStatus::WorkedNotConfirmed);
        assert!(NeededStatus::Confirmed < NeededStatus::Unknown);
    }

    #[test]
    fn guess_mode_comment_then_boundaries() {
        // Comment token wins.
        assert_eq!(guess_mode(Some("FT8 -12dB"), 14_200.0), "FT8");
        // Below 20m digital boundary (14070) → CW.
        assert_eq!(guess_mode(None, 14_040.0), "CW");
        // At/above 20m SSB boundary (14150) → SSB.
        assert_eq!(guess_mode(None, 14_200.0), "SSB");
        // Between digital and SSB boundaries → DIGI.
        assert_eq!(guess_mode(Some("loud sig"), 14_074.0), "DIGI");
        // Out-of-band → CW default.
        assert_eq!(guess_mode(None, 2_500.0), "CW");
    }

    #[test]
    fn source_raw_round_trip() {
        for source in [
            SpotSource::Rbn,
            SpotSource::Pota,
            SpotSource::Sota,
            SpotSource::Wwff,
            SpotSource::DxSummit,
            SpotSource::DxHeat,
            SpotSource::DxWatch,
            SpotSource::Cluster,
            SpotSource::Pskr,
        ] {
            assert_eq!(SpotSource::from_raw(source.raw_value()), Some(source));
        }
    }
}
