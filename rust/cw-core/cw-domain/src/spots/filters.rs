//! Spot filter predicates — the union of Sweep's widget filter stack
//! (`SpotListView+Actions.applyWidgetFilters`, `SpotModeFilter`,
//! `SpotStatusFilter`) and iOS's `SpotFilters.apply`
//! (`SpotFilterSheet.swift`).
//!
//! One `SpotFilter` covers both platforms; unset components pass
//! everything. Platform quirks preserved:
//! - Sweep filters mode by **family** (CW/Phone/Digital via
//!   `ModeEquivalence`), iOS by **exact uppercased mode string** — both
//!   components exist and compose (AND) if both are set.
//! - iOS's `clubOnly` flag is deliberately absent: the Swift `apply` never
//!   consults it (club spots are filtered upstream).
//! - Text search is a case-insensitive substring across callsign /
//!   reference / location / spotter / comments (Sweep's filter bar).

use std::collections::HashSet;

use crate::mode::{ModeEquivalence, ModeFamily};
use crate::spots::model::{EnrichedSpot, NeededStatus, SpotSource};
use crate::spots::region::{SpotContinent, SpotRegionGroup};

/// Mode-family filter (Sweep's `SpotModeFilter`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SpotModeFilter {
    All,
    Cw,
    Phone,
    Digital,
}

impl SpotModeFilter {
    pub fn matches(self, mode: &str) -> bool {
        match self {
            SpotModeFilter::All => true,
            SpotModeFilter::Cw => ModeEquivalence::family(mode) == ModeFamily::Cw,
            SpotModeFilter::Phone => ModeEquivalence::family(mode) == ModeFamily::Phone,
            SpotModeFilter::Digital => ModeEquivalence::family(mode) == ModeFamily::Digital,
        }
    }
}

/// Worked/needed status filter (Sweep's `SpotStatusFilter`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub enum SpotStatusFilter {
    #[default]
    All,
    NewOnly,
    NeededOnly,
    NewAndNeeded,
}

impl SpotStatusFilter {
    /// Whether a spot with the given needed status passes this filter.
    pub fn matches(self, status: NeededStatus, is_worked_today: bool) -> bool {
        match self {
            SpotStatusFilter::All => true,
            SpotStatusFilter::NewOnly => !is_worked_today,
            SpotStatusFilter::NeededOnly => {
                status == NeededStatus::NewEntity || status == NeededStatus::NewBandSlot
            }
            SpotStatusFilter::NewAndNeeded => {
                !is_worked_today
                    || status == NeededStatus::NewEntity
                    || status == NeededStatus::NewBandSlot
            }
        }
    }
}

/// Per-evaluation context the filter needs beyond the spot itself.
#[derive(Debug, Default)]
pub struct FilterContext {
    /// Unix seconds "now" for the age cutoff.
    pub now: i64,
    /// Uppercased callsigns already worked (iOS `hideWorked` via
    /// `WorkedBeforeResult.hasBeenWorked`).
    pub worked: HashSet<String>,
    /// Uppercased callsigns worked today (contest workflows; both Sweep
    /// spot views currently pass `false`, i.e. an empty set).
    pub worked_today: HashSet<String>,
}

/// The composed filter. `None` components pass all spots.
#[derive(Debug, Clone, Default)]
pub struct SpotFilter {
    /// Allowed sources (`None` = all; empty set = all, matching both
    /// platforms' "no selection means no filter" behavior).
    pub sources: Option<HashSet<SpotSource>>,
    /// Allowed band strings, e.g. `"20m"` (empty = all).
    pub bands: Option<HashSet<String>>,
    /// Sweep mode-family chips (a spot passes if ANY selected family matches).
    pub mode_families: Option<HashSet<SpotModeFilter>>,
    /// iOS exact mode strings, uppercased (empty = all).
    pub modes: Option<HashSet<String>>,
    /// Allowed continents. Swift parity: selecting ALL continents (or none)
    /// disables the check, so pass `None` in that case.
    pub continents: Option<HashSet<SpotContinent>>,
    /// Allowed region groups (Sweep only).
    pub region_groups: Option<HashSet<SpotRegionGroup>>,
    /// Worked/needed status filter.
    pub status: SpotStatusFilter,
    /// Maximum age in minutes; spots strictly older than the cutoff drop.
    pub max_age_minutes: Option<i64>,
    /// Case-insensitive substring over callsign / reference / location /
    /// spotter / comments.
    pub text: Option<String>,
    /// Hide already-worked callsigns (iOS).
    pub hide_worked: bool,
    /// Only spots with at least one matched need (iOS).
    pub needs_only: bool,
}

impl SpotFilter {
    pub fn matches(&self, spot: &EnrichedSpot, ctx: &FilterContext) -> bool {
        if let Some(max_age) = self.max_age_minutes {
            // iOS parity: `timestamp < cutoff` fails (equal-to-cutoff passes).
            let cutoff = ctx.now - max_age * 60;
            if spot.spot.timestamp < cutoff {
                return false;
            }
        }

        if let Some(sources) = &self.sources {
            if !sources.is_empty() && !sources.contains(&spot.spot.source) {
                return false;
            }
        }

        if let Some(bands) = &self.bands {
            if !bands.is_empty() && !bands.contains(spot.spot.band()) {
                return false;
            }
        }

        if let Some(families) = &self.mode_families {
            if !families.is_empty()
                && !families.iter().any(|family| family.matches(&spot.spot.mode))
            {
                return false;
            }
        }

        if let Some(modes) = &self.modes {
            if !modes.is_empty() && !modes.contains(&spot.spot.mode.to_uppercase()) {
                return false;
            }
        }

        if let Some(continents) = &self.continents {
            if !continents.is_empty() && !continents.contains(&spot.region.continent()) {
                return false;
            }
        }

        if let Some(groups) = &self.region_groups {
            if !groups.is_empty() && !groups.contains(&spot.region.group()) {
                return false;
            }
        }

        let callsign_upper = spot.spot.callsign.to_uppercase();
        if !self.status.matches(spot.needed_status, ctx.worked_today.contains(&callsign_upper)) {
            return false;
        }

        if self.hide_worked && ctx.worked.contains(&callsign_upper) {
            return false;
        }

        if self.needs_only && spot.matched_needs.is_empty() {
            return false;
        }

        if let Some(text) = &self.text {
            if !text.is_empty() && !text_matches(spot, text) {
                return false;
            }
        }

        true
    }

    /// Apply the filter to a list, preserving order.
    pub fn apply(&self, spots: &[EnrichedSpot], ctx: &FilterContext) -> Vec<EnrichedSpot> {
        spots.iter().filter(|spot| self.matches(spot, ctx)).cloned().collect()
    }
}

fn text_matches(spot: &EnrichedSpot, text: &str) -> bool {
    let query = text.to_lowercase();
    let contains = |value: Option<&str>| {
        value.map(|v| v.to_lowercase().contains(&query)).unwrap_or(false)
    };
    spot.spot.callsign.to_lowercase().contains(&query)
        || contains(spot.spot.reference_display())
        || contains(spot.spot.location_display())
        || contains(spot.spot.spotter.as_deref())
        || contains(spot.spot.comments.as_deref())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::spots::model::{MatchedNeed, UnifiedSpot};
    use crate::spots::region::SpotRegion;

    fn enriched(callsign: &str, khz: f64, mode: &str, source: SpotSource) -> EnrichedSpot {
        let mut spot = UnifiedSpot::base(
            format!("{}-1", source.raw_value()),
            callsign.to_string(),
            khz,
            mode.to_string(),
            1_000_000,
            source,
        );
        spot.spotter = Some("W3LPL".to_string());
        EnrichedSpot::bare(spot, SpotRegion::NeUs)
    }

    fn ctx() -> FilterContext {
        FilterContext { now: 1_000_060, ..FilterContext::default() }
    }

    #[test]
    fn empty_filter_passes_everything() {
        let filter = SpotFilter::default();
        assert!(filter.matches(&enriched("W1AW", 14_040.0, "CW", SpotSource::Rbn), &ctx()));
    }

    #[test]
    fn age_cutoff_is_strict_less_than() {
        let filter = SpotFilter { max_age_minutes: Some(1), ..SpotFilter::default() };
        let spot = enriched("W1AW", 14_040.0, "CW", SpotSource::Rbn);
        // now=1_000_060, age 1 min → cutoff=1_000_000; timestamp==cutoff passes.
        assert!(filter.matches(&spot, &ctx()));
        let older_ctx = FilterContext { now: 1_000_061, ..FilterContext::default() };
        assert!(!filter.matches(&spot, &older_ctx));
    }

    #[test]
    fn source_band_mode_compose() {
        let filter = SpotFilter {
            sources: Some([SpotSource::Pota].into()),
            bands: Some(["20m".to_string()].into()),
            modes: Some(["CW".to_string()].into()),
            ..SpotFilter::default()
        };
        assert!(filter.matches(&enriched("W1AW", 14_040.0, "cw", SpotSource::Pota), &ctx()));
        assert!(!filter.matches(&enriched("W1AW", 14_040.0, "CW", SpotSource::Rbn), &ctx()));
        assert!(!filter.matches(&enriched("W1AW", 7_040.0, "CW", SpotSource::Pota), &ctx()));
        assert!(!filter.matches(&enriched("W1AW", 14_200.0, "SSB", SpotSource::Pota), &ctx()));
    }

    #[test]
    fn empty_component_sets_pass_all() {
        let filter = SpotFilter {
            sources: Some(HashSet::new()),
            bands: Some(HashSet::new()),
            ..SpotFilter::default()
        };
        assert!(filter.matches(&enriched("W1AW", 14_040.0, "CW", SpotSource::Rbn), &ctx()));
    }

    #[test]
    fn mode_family_filter_uses_equivalence() {
        let filter = SpotFilter {
            mode_families: Some([SpotModeFilter::Digital].into()),
            ..SpotFilter::default()
        };
        assert!(filter.matches(&enriched("W1AW", 14_074.0, "FT8", SpotSource::Rbn), &ctx()));
        assert!(!filter.matches(&enriched("W1AW", 14_040.0, "CW", SpotSource::Rbn), &ctx()));
    }

    #[test]
    fn status_filter_needed_only() {
        let filter =
            SpotFilter { status: SpotStatusFilter::NeededOnly, ..SpotFilter::default() };
        let mut spot = enriched("W1AW", 14_040.0, "CW", SpotSource::Rbn);
        assert!(!filter.matches(&spot, &ctx()));
        spot.needed_status = NeededStatus::NewEntity;
        assert!(filter.matches(&spot, &ctx()));
        spot.needed_status = NeededStatus::NewBandSlot;
        assert!(filter.matches(&spot, &ctx()));
        spot.needed_status = NeededStatus::Confirmed;
        assert!(!filter.matches(&spot, &ctx()));
    }

    #[test]
    fn hide_worked_uses_uppercased_callsign() {
        let filter = SpotFilter { hide_worked: true, ..SpotFilter::default() };
        let mut context = ctx();
        context.worked.insert("W1AW".to_string());
        assert!(!filter.matches(&enriched("w1aw", 14_040.0, "CW", SpotSource::Rbn), &context));
        assert!(filter.matches(&enriched("K1ABC", 14_050.0, "CW", SpotSource::Rbn), &context));
    }

    #[test]
    fn needs_only_requires_matched_needs() {
        let filter = SpotFilter { needs_only: true, ..SpotFilter::default() };
        let mut spot = enriched("W1AW", 14_040.0, "CW", SpotSource::Rbn);
        assert!(!filter.matches(&spot, &ctx()));
        spot.matched_needs.push(MatchedNeed {
            category: crate::spots::model::NeedCategory::WasState { state: "WY".to_string() },
            label: "WAS: Wyoming".to_string(),
            priority: crate::spots::model::NeedPriority::Medium,
        });
        assert!(filter.matches(&spot, &ctx()));
    }

    #[test]
    fn text_search_spans_fields() {
        let filter = SpotFilter { text: Some("w3lp".to_string()), ..SpotFilter::default() };
        // Matches the spotter field, case-insensitively.
        assert!(filter.matches(&enriched("W1AW", 14_040.0, "CW", SpotSource::Rbn), &ctx()));
        let miss = SpotFilter { text: Some("zzz".to_string()), ..SpotFilter::default() };
        assert!(!miss.matches(&enriched("W1AW", 14_040.0, "CW", SpotSource::Rbn), &ctx()));
    }

    #[test]
    fn continent_filter() {
        let filter = SpotFilter {
            continents: Some([SpotContinent::Europe].into()),
            ..SpotFilter::default()
        };
        // NeUs region → North America → filtered out.
        assert!(!filter.matches(&enriched("W1AW", 14_040.0, "CW", SpotSource::Rbn), &ctx()));
    }
}
