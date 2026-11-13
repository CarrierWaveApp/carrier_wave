//! Needs snapshot + spot needs matching. Port of iOS `NeedTypes.swift` and
//! `SpotNeedsMatcher.swift` — the richer of the two platforms' needs
//! systems (Sweep only checks DXCC).
//!
//! The snapshot is host-computed (iOS `NeedsEngine`) and fed in; matching
//! is pure. The CTY database comes from [`crate::cty`].

use std::collections::{HashMap, HashSet};

use crate::cty::CtyDatabase;
use crate::mode::{ModeEquivalence, ModeFamily};
use crate::spots::model::{EnrichedSpot, MatchedNeed, NeedCategory, NeedPriority};

/// Composite key for (entity, band) DXCC band-slot tracking.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct BandSlotKey {
    pub entity: String,
    pub band: String,
}

/// DXCC entities and band slots the operator has not yet worked.
#[derive(Debug, Clone, Default)]
pub struct DxccNeeds {
    /// Entity primary prefixes already worked (any band).
    pub all_time_worked: HashSet<String>,
    /// (entity, band) pairs already worked.
    pub band_slots_worked: HashSet<BandSlotKey>,
    /// Total known entities from CTY.dat for progress display.
    pub total_known_entities: i32,
    /// Operator's grid square used for this computation (None if mixed).
    pub grid_square: Option<String>,
}

/// Primary subdivisions (states, provinces, …) not yet worked. Classic WAS
/// for the USA; generalized for other subdivision awards.
#[derive(Debug, Clone, Default)]
pub struct WasNeeds {
    pub country: String,
    pub subdivision_term: String,
    pub states_worked: HashSet<String>,
    pub states_missing: HashSet<String>,
    /// Per-mode breakdown: mode → subdivisions worked on that mode.
    pub per_mode_worked: HashMap<String, HashSet<String>>,
}

impl WasNeeds {
    pub fn is_complete(&self) -> bool {
        self.states_missing.is_empty()
    }
}

/// POTA parks the operator has not yet hunted.
#[derive(Debug, Clone, Default)]
pub struct PotaHunterNeeds {
    pub parks_worked: HashSet<String>,
    pub next_tier_threshold: i32,
    pub next_tier_name: Option<String>,
}

/// States and entities not yet activated for POTA awards.
#[derive(Debug, Clone, Default)]
pub struct PotaActivatorNeeds {
    pub states_missing: HashSet<String>,
    pub entities_worked: i32,
    pub next_entity_tier_threshold: i32,
}

/// WWFF references the operator has not yet hunted.
#[derive(Debug, Clone, Default)]
pub struct WwffHunterNeeds {
    pub references_worked: HashSet<String>,
    pub next_tier_threshold: i32,
    pub next_tier_name: Option<String>,
}

/// A user-defined need pattern for spot matching.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CustomNeedPattern {
    pub pattern: String,
    pub pattern_type: CustomPatternType,
    pub label: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CustomPatternType {
    Callsign,
    Entity,
    State,
    ParkRef,
}

impl CustomNeedPattern {
    /// Test whether a value matches this pattern (supports `*` wildcards).
    /// Faithful port of the Swift prefix/suffix wildcard semantics.
    pub fn matches(&self, value: &str) -> bool {
        let upper = value.to_uppercase();
        let pat = self.pattern.to_uppercase();

        if pat.contains('*') {
            let parts: Vec<&str> = pat.split('*').collect();
            let prefix = parts.first().copied().unwrap_or("");
            let suffix = parts.last().copied().unwrap_or("");
            if !suffix.is_empty() {
                return upper.starts_with(prefix) && upper.ends_with(suffix);
            }
            return upper.starts_with(prefix);
        }
        upper == pat
    }
}

/// Frozen snapshot of all operator needs. Host-computed (iOS
/// `NeedsEngine`), consumed by [`match_spots`].
#[derive(Debug, Clone, Default)]
pub struct NeedsSnapshot {
    pub dxcc: DxccNeeds,
    pub was: WasNeeds,
    pub pota_hunter: PotaHunterNeeds,
    pub pota_activator: PotaActivatorNeeds,
    pub wwff_hunter: WwffHunterNeeds,
    pub custom_patterns: Vec<CustomNeedPattern>,
    /// Mode families ("phone", "cw", "digital", "other") the operator has
    /// actually worked. Empty = no gate.
    pub mode_families_worked: HashSet<String>,
}

/// Which award tracks are enabled (iOS `NeedsPreferences` AppStorage flags).
#[derive(Debug, Clone, Copy)]
pub struct NeedsPreferences {
    pub track_dxcc: bool,
    pub track_was: bool,
    pub track_pota_hunter: bool,
    pub track_wwff_hunter: bool,
}

impl Default for NeedsPreferences {
    fn default() -> Self {
        NeedsPreferences {
            track_dxcc: true,
            track_was: true,
            track_pota_hunter: true,
            track_wwff_hunter: true,
        }
    }
}

/// Minimum states worked before WAS notifications activate — below this
/// threshold WAS isn't a meaningful pursuit.
const WAS_MINIMUM_STATES_THRESHOLD: usize = 25;

/// Match spots against a needs snapshot; returns the same spots with
/// `matched_needs` populated. Port of `SpotNeedsMatcher.match`.
pub fn match_spots(
    spots: Vec<EnrichedSpot>,
    snapshot: &NeedsSnapshot,
    prefs: NeedsPreferences,
    db: Option<&CtyDatabase>,
) -> Vec<EnrichedSpot> {
    spots
        .into_iter()
        .map(|mut spot| {
            let mut matched: Vec<MatchedNeed> = Vec::new();

            // Skip spots on modes the operator has never worked.
            let spot_family = family_name(ModeEquivalence::family(&spot.spot.mode));
            let operator_works_mode = snapshot.mode_families_worked.is_empty()
                || snapshot.mode_families_worked.contains(spot_family);

            if let Some(db) = db {
                if operator_works_mode && prefs.track_dxcc {
                    matched.extend(match_dxcc(&spot, &snapshot.dxcc, db));
                }
            }
            if operator_works_mode && prefs.track_was {
                matched.extend(match_was(&spot, &snapshot.was));
            }
            if prefs.track_pota_hunter {
                matched.extend(match_pota_hunter(&spot, &snapshot.pota_hunter));
            }
            matched.extend(match_pota_activator(&spot, &snapshot.pota_activator));
            if prefs.track_wwff_hunter {
                matched.extend(match_wwff_hunter(&spot, &snapshot.wwff_hunter));
            }
            matched.extend(match_custom(&spot, &snapshot.custom_patterns));

            spot.matched_needs = matched;
            spot
        })
        .collect()
}

/// Swift's `String(describing: ModeEquivalence.family(for:))` — lowercase
/// case names.
fn family_name(family: ModeFamily) -> &'static str {
    match family {
        ModeFamily::Phone => "phone",
        ModeFamily::Cw => "cw",
        ModeFamily::Digital => "digital",
        ModeFamily::Other => "other",
    }
}

fn match_dxcc(spot: &EnrichedSpot, needs: &DxccNeeds, db: &CtyDatabase) -> Vec<MatchedNeed> {
    let Some(entity) = db.lookup(&spot.spot.callsign) else {
        return Vec::new();
    };
    let prefix = &entity.primary_prefix;

    if !needs.all_time_worked.contains(prefix) {
        return vec![MatchedNeed {
            category: NeedCategory::DxccEntity { entity: prefix.clone() },
            label: format!("New DXCC: {}", entity.name),
            priority: NeedPriority::High,
        }];
    }
    let band = spot.spot.band();
    if !band.is_empty() {
        let key = BandSlotKey { entity: prefix.clone(), band: band.to_string() };
        if !needs.band_slots_worked.contains(&key) {
            return vec![MatchedNeed {
                category: NeedCategory::DxccBandSlot {
                    entity: prefix.clone(),
                    band: band.to_string(),
                },
                label: format!("{} on {}", entity.name, band),
                priority: NeedPriority::Medium,
            }];
        }
    }
    Vec::new()
}

fn match_was(spot: &EnrichedSpot, needs: &WasNeeds) -> Vec<MatchedNeed> {
    if needs.is_complete() {
        return Vec::new();
    }
    if needs.states_worked.len() < WAS_MINIMUM_STATES_THRESHOLD {
        return Vec::new();
    }
    let Some(raw) = spot.spot.state_abbr.as_deref() else {
        return Vec::new();
    };
    if raw.is_empty() {
        return Vec::new();
    }
    let state = us_states::normalize_abbreviation(raw);
    if !needs.states_missing.contains(&state) {
        return Vec::new();
    }

    // Higher priority if close to completion.
    let priority = if needs.states_missing.len() <= 5 {
        NeedPriority::High
    } else {
        NeedPriority::Medium
    };
    let full_name = us_states::full_name(&state).unwrap_or(&state);
    vec![MatchedNeed {
        category: NeedCategory::WasState { state: state.clone() },
        label: format!("WAS: {full_name}"),
        priority,
    }]
}

fn match_pota_hunter(spot: &EnrichedSpot, needs: &PotaHunterNeeds) -> Vec<MatchedNeed> {
    let Some(park_ref) = spot.spot.park_ref.as_deref() else {
        return Vec::new();
    };
    let park_ref = park_ref.to_uppercase();
    if park_ref.is_empty() || needs.parks_worked.contains(&park_ref) {
        return Vec::new();
    }
    vec![MatchedNeed {
        category: NeedCategory::PotaNewPark,
        label: "New Park".to_string(),
        priority: NeedPriority::Low,
    }]
}

fn match_pota_activator(spot: &EnrichedSpot, needs: &PotaActivatorNeeds) -> Vec<MatchedNeed> {
    let Some(raw) = spot.spot.state_abbr.as_deref() else {
        return Vec::new();
    };
    if raw.is_empty() {
        return Vec::new();
    }
    let state = us_states::normalize_abbreviation(raw);
    if !needs.states_missing.contains(&state) {
        return Vec::new();
    }
    let full_name = us_states::full_name(&state).unwrap_or(&state);
    vec![MatchedNeed {
        category: NeedCategory::PotaActivatorState { state: state.clone() },
        label: format!("Activate: {full_name}"),
        priority: NeedPriority::Low,
    }]
}

fn match_wwff_hunter(spot: &EnrichedSpot, needs: &WwffHunterNeeds) -> Vec<MatchedNeed> {
    let Some(wwff_ref) = spot.spot.wwff_ref.as_deref() else {
        return Vec::new();
    };
    let wwff_ref = wwff_ref.to_uppercase();
    if wwff_ref.is_empty() || needs.references_worked.contains(&wwff_ref) {
        return Vec::new();
    }
    vec![MatchedNeed {
        category: NeedCategory::WwffNewReference,
        label: "New WWFF".to_string(),
        priority: NeedPriority::Low,
    }]
}

fn match_custom(spot: &EnrichedSpot, patterns: &[CustomNeedPattern]) -> Vec<MatchedNeed> {
    let mut matched = Vec::new();
    for pattern in patterns {
        let is_match = match pattern.pattern_type {
            CustomPatternType::Callsign | CustomPatternType::Entity => {
                pattern.matches(&spot.spot.callsign)
            }
            CustomPatternType::State => {
                spot.spot.state_abbr.as_deref().map(|s| pattern.matches(s)).unwrap_or(false)
            }
            CustomPatternType::ParkRef => {
                if let Some(park) = spot.spot.park_ref.as_deref() {
                    pattern.matches(park)
                } else if let Some(wwff) = spot.spot.wwff_ref.as_deref() {
                    pattern.matches(wwff)
                } else {
                    false
                }
            }
        };
        if is_match {
            matched.push(MatchedNeed {
                category: NeedCategory::Custom {
                    pattern: pattern.pattern.clone(),
                    label: pattern.label.clone(),
                },
                label: pattern.label.clone(),
                priority: NeedPriority::High,
            });
        }
    }
    matched
}

/// Aggregated summary of needs currently on the air. Port of
/// `NeedsOnAirSummary`.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct NeedsOnAirSummary {
    pub total_matched_spots: usize,
    pub new_dxcc_entities: usize,
    pub was_states: HashSet<String>,
    pub new_pota_parks: usize,
    pub new_wwff_references: usize,
    pub custom_matches: usize,
}

/// Quick summary of matched needs across all spots. Port of
/// `SpotNeedsMatcher.summarize` (band-slot and activator matches are
/// deliberately not counted).
pub fn summarize(spots: &[EnrichedSpot]) -> NeedsOnAirSummary {
    let mut summary = NeedsOnAirSummary::default();
    for spot in spots.iter().filter(|s| !s.matched_needs.is_empty()) {
        summary.total_matched_spots += 1;
        for need in &spot.matched_needs {
            match &need.category {
                NeedCategory::DxccEntity { .. } => summary.new_dxcc_entities += 1,
                NeedCategory::DxccBandSlot { .. } => {} // Don't double-count.
                NeedCategory::WasState { state }
                | NeedCategory::WasStateMode { state, .. } => {
                    summary.was_states.insert(state.clone());
                }
                NeedCategory::PotaNewPark => summary.new_pota_parks += 1,
                NeedCategory::WwffNewReference => summary.new_wwff_references += 1,
                NeedCategory::Custom { .. } => summary.custom_matches += 1,
                NeedCategory::PotaActivatorState { .. }
                | NeedCategory::PotaActivatorEntity { .. } => {}
            }
        }
    }
    summary
}

/// Reference data for the 50 US states. Port of iOS `USStates` +
/// `USStatesReference`.
pub mod us_states {
    use std::collections::HashSet;
    use std::sync::OnceLock;

    pub const NAMES: [(&str, &str); 50] = [
        ("AK", "Alaska"), ("AL", "Alabama"), ("AR", "Arkansas"), ("AZ", "Arizona"),
        ("CA", "California"), ("CO", "Colorado"), ("CT", "Connecticut"), ("DE", "Delaware"),
        ("FL", "Florida"), ("GA", "Georgia"), ("HI", "Hawaii"), ("IA", "Iowa"),
        ("ID", "Idaho"), ("IL", "Illinois"), ("IN", "Indiana"), ("KS", "Kansas"),
        ("KY", "Kentucky"), ("LA", "Louisiana"), ("MA", "Massachusetts"), ("MD", "Maryland"),
        ("ME", "Maine"), ("MI", "Michigan"), ("MN", "Minnesota"), ("MO", "Missouri"),
        ("MS", "Mississippi"), ("MT", "Montana"), ("NC", "North Carolina"),
        ("ND", "North Dakota"), ("NE", "Nebraska"), ("NH", "New Hampshire"),
        ("NJ", "New Jersey"), ("NM", "New Mexico"), ("NV", "Nevada"), ("NY", "New York"),
        ("OH", "Ohio"), ("OK", "Oklahoma"), ("OR", "Oregon"), ("PA", "Pennsylvania"),
        ("RI", "Rhode Island"), ("SC", "South Carolina"), ("SD", "South Dakota"),
        ("TN", "Tennessee"), ("TX", "Texas"), ("UT", "Utah"), ("VA", "Virginia"),
        ("VT", "Vermont"), ("WA", "Washington"), ("WI", "Wisconsin"),
        ("WV", "West Virginia"), ("WY", "Wyoming"),
    ];

    /// All 50 state abbreviations.
    pub fn all_states() -> &'static HashSet<&'static str> {
        static SET: OnceLock<HashSet<&'static str>> = OnceLock::new();
        SET.get_or_init(|| NAMES.iter().map(|(abbr, _)| *abbr).collect())
    }

    /// Normalize a state string that may carry a comment suffix
    /// (e.g. "VA // Virginia" → "VA"; LoFi API format).
    pub fn normalize_abbreviation(raw: &str) -> String {
        let trimmed = match raw.find(" // ") {
            Some(idx) => &raw[..idx],
            None => raw,
        };
        trimmed.to_uppercase().trim().to_string()
    }

    /// Full state name for a 2-letter abbreviation.
    pub fn full_name(abbreviation: &str) -> Option<&'static str> {
        let upper = abbreviation.to_uppercase();
        NAMES.iter().find(|(abbr, _)| *abbr == upper).map(|(_, name)| *name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::spots::model::{SpotSource, UnifiedSpot};
    use crate::spots::region::SpotRegion;

    fn enriched(callsign: &str, khz: f64) -> EnrichedSpot {
        let spot = UnifiedSpot::base(
            "rbn-1".to_string(),
            callsign.to_string(),
            khz,
            "CW".to_string(),
            1_000_000,
            SpotSource::Rbn,
        );
        EnrichedSpot::bare(spot, SpotRegion::Other)
    }

    fn cty_db() -> CtyDatabase {
        // Minimal CTY.dat with two entities.
        crate::cty::parse(
            "United States:            05:  08:  NA:   37.53:    91.67:     5.0:  K:\n    K,W,N,AA;\nJapan:                    25:  45:  AS:   36.40:  -138.38:    -9.0:  JA:\n    JA,JE,7J;\n",
        )
    }

    #[test]
    fn dxcc_new_entity_matches_high_priority() {
        let db = cty_db();
        let snapshot = NeedsSnapshot::default();
        let out = match_spots(
            vec![enriched("JA1ABC", 14_040.0)],
            &snapshot,
            NeedsPreferences::default(),
            Some(&db),
        );
        let needs = &out[0].matched_needs;
        assert!(needs.iter().any(|n| matches!(
            &n.category,
            NeedCategory::DxccEntity { entity } if entity == "JA"
        )));
        assert_eq!(needs[0].priority, NeedPriority::High);
        assert!(needs[0].label.starts_with("New DXCC: "));
    }

    #[test]
    fn dxcc_band_slot_when_entity_worked() {
        let db = cty_db();
        let mut snapshot = NeedsSnapshot::default();
        snapshot.dxcc.all_time_worked.insert("JA".to_string());
        let out = match_spots(
            vec![enriched("JA1ABC", 14_040.0)],
            &snapshot,
            NeedsPreferences::default(),
            Some(&db),
        );
        assert!(out[0].matched_needs.iter().any(|n| matches!(
            &n.category,
            NeedCategory::DxccBandSlot { entity, band } if entity == "JA" && band == "20m"
        )));
    }

    #[test]
    fn mode_family_gate_suppresses_dxcc_and_was() {
        let db = cty_db();
        let mut snapshot = NeedsSnapshot::default();
        snapshot.mode_families_worked.insert("phone".to_string());
        // Spot is CW; operator only works phone → DXCC suppressed.
        let out = match_spots(
            vec![enriched("JA1ABC", 14_040.0)],
            &snapshot,
            NeedsPreferences::default(),
            Some(&db),
        );
        assert!(out[0].matched_needs.is_empty());
    }

    #[test]
    fn was_needs_threshold_and_missing_state() {
        let mut snapshot = NeedsSnapshot::default();
        // 25 states worked, WY missing.
        for (abbr, _) in us_states::NAMES.iter().take(25) {
            snapshot.was.states_worked.insert(abbr.to_string());
        }
        snapshot.was.states_missing.insert("WY".to_string());

        let mut spot = enriched("W7XYZ", 14_040.0);
        spot.spot.state_abbr = Some("wy // Wyoming".to_string());
        let out =
            match_spots(vec![spot], &snapshot, NeedsPreferences::default(), None);
        let was_match = out[0]
            .matched_needs
            .iter()
            .find(|n| matches!(&n.category, NeedCategory::WasState { state } if state == "WY"))
            .unwrap();
        // ≤5 missing → high priority; label uses the full state name.
        assert_eq!(was_match.priority, NeedPriority::High);
        assert_eq!(was_match.label, "WAS: Wyoming");
    }

    #[test]
    fn was_below_threshold_is_silent() {
        let mut snapshot = NeedsSnapshot::default();
        snapshot.was.states_worked.insert("CA".to_string());
        snapshot.was.states_missing.insert("WY".to_string());
        let mut spot = enriched("W7XYZ", 14_040.0);
        spot.spot.state_abbr = Some("WY".to_string());
        let out =
            match_spots(vec![spot], &snapshot, NeedsPreferences::default(), None);
        assert!(out[0].matched_needs.is_empty());
    }

    #[test]
    fn pota_and_wwff_hunter_matching() {
        let snapshot = NeedsSnapshot::default();
        let mut spot = enriched("W1AW", 14_040.0);
        spot.spot.park_ref = Some("us-1234".to_string());
        spot.spot.wwff_ref = Some("KFF-0001".to_string());
        let out =
            match_spots(vec![spot], &snapshot, NeedsPreferences::default(), None);
        let cats: Vec<&NeedCategory> =
            out[0].matched_needs.iter().map(|n| &n.category).collect();
        assert!(cats.iter().any(|c| matches!(c, NeedCategory::PotaNewPark)));
        assert!(cats.iter().any(|c| matches!(c, NeedCategory::WwffNewReference)));

        // Already worked (uppercased comparison) → no match.
        let mut worked = NeedsSnapshot::default();
        worked.pota_hunter.parks_worked.insert("US-1234".to_string());
        worked.wwff_hunter.references_worked.insert("KFF-0001".to_string());
        let mut spot2 = enriched("W1AW", 14_040.0);
        spot2.spot.park_ref = Some("us-1234".to_string());
        spot2.spot.wwff_ref = Some("kff-0001".to_string());
        let out2 =
            match_spots(vec![spot2], &worked, NeedsPreferences::default(), None);
        assert!(out2[0].matched_needs.is_empty());
    }

    #[test]
    fn custom_pattern_wildcards() {
        let call_prefix = CustomNeedPattern {
            pattern: "JA*".to_string(),
            pattern_type: CustomPatternType::Callsign,
            label: "Japan".to_string(),
        };
        assert!(call_prefix.matches("ja1abc"));
        assert!(!call_prefix.matches("W1AW"));

        let prefix_suffix = CustomNeedPattern {
            pattern: "K*W".to_string(),
            pattern_type: CustomPatternType::Callsign,
            label: "K…W".to_string(),
        };
        assert!(prefix_suffix.matches("K1AW"));
        assert!(!prefix_suffix.matches("K1AB"));

        let exact = CustomNeedPattern {
            pattern: "W6JY".to_string(),
            pattern_type: CustomPatternType::Callsign,
            label: "me".to_string(),
        };
        assert!(exact.matches("w6jy"));
        assert!(!exact.matches("W6JYA"));
    }

    #[test]
    fn custom_park_pattern_falls_back_to_wwff() {
        let pattern = CustomNeedPattern {
            pattern: "KFF-*".to_string(),
            pattern_type: CustomPatternType::ParkRef,
            label: "KFF refs".to_string(),
        };
        let snapshot = NeedsSnapshot {
            custom_patterns: vec![pattern],
            ..NeedsSnapshot::default()
        };
        let mut spot = enriched("W1AW", 14_040.0);
        spot.spot.wwff_ref = Some("KFF-0001".to_string());
        let out =
            match_spots(vec![spot], &snapshot, NeedsPreferences::default(), None);
        let custom = out[0]
            .matched_needs
            .iter()
            .find(|n| matches!(&n.category, NeedCategory::Custom { .. }))
            .unwrap();
        assert_eq!(custom.priority, NeedPriority::High);
    }

    #[test]
    fn summarize_counts_and_dedups_was_states() {
        let mut spot1 = enriched("JA1ABC", 14_040.0);
        spot1.matched_needs.push(MatchedNeed {
            category: NeedCategory::DxccEntity { entity: "JA".to_string() },
            label: "New DXCC: Japan".to_string(),
            priority: NeedPriority::High,
        });
        let mut spot2 = enriched("W7XYZ", 7_040.0);
        spot2.matched_needs.push(MatchedNeed {
            category: NeedCategory::WasState { state: "WY".to_string() },
            label: "WAS: Wyoming".to_string(),
            priority: NeedPriority::Medium,
        });
        let mut spot3 = enriched("K7ZZZ", 7_050.0);
        spot3.matched_needs.push(MatchedNeed {
            category: NeedCategory::WasState { state: "WY".to_string() },
            label: "WAS: Wyoming".to_string(),
            priority: NeedPriority::Medium,
        });
        let unmatched = enriched("W1AW", 14_050.0);

        let summary = summarize(&[spot1, spot2, spot3, unmatched]);
        assert_eq!(summary.total_matched_spots, 3);
        assert_eq!(summary.new_dxcc_entities, 1);
        assert_eq!(summary.was_states.len(), 1);
    }
}
