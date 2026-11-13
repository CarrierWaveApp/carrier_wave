//! QSO deduplication + two-fer matchers. Ports of `QSOSnapshot.swift`,
//! `DeduplicationMatcher.swift`, and `TwoferMatcher.swift`.
//!
//! `QSOSnapshot` deliberately holds nothing platform-specific — Swift's
//! version was already designed as a Sendable value type so the matcher could
//! be tested without SwiftData. We mirror that one-to-one: the iOS shim
//! converts its SwiftData objects into [`QsoSnapshot`]s before calling in.

use std::collections::HashSet;

use crate::mode::ModeEquivalence;
use crate::park_reference;

/// Lightweight QSO record for matching/dedup. Mirrors `QSOSnapshot.swift`.
#[derive(Debug, Clone, PartialEq)]
pub struct QsoSnapshot {
    /// Stable per-QSO ID. Swift uses `UUID`; we use `String` for portability
    /// (UniFFI carries strings cheaply).
    pub id: String,
    pub callsign: String,
    /// Unix epoch seconds (matches what the Swift `Date.timeIntervalSince1970`
    /// surfaces; choice of integer keeps the matcher portable).
    pub timestamp_secs: i64,
    pub band: String,
    pub mode: String,
    pub park_reference: Option<String>,
    pub frequency: Option<f64>,
    pub rst_sent: Option<String>,
    pub rst_received: Option<String>,
    pub my_grid: Option<String>,
    pub their_grid: Option<String>,
    pub notes: Option<String>,
    pub raw_adif: Option<String>,
    pub name: Option<String>,
    pub qth: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    pub power: Option<i32>,
    pub their_license_class: Option<String>,
    pub sat_name: Option<String>,
    pub prop_mode: Option<String>,
    pub synced_services_count: u32,
}

impl QsoSnapshot {
    pub fn normalized_callsign(&self) -> String {
        self.callsign.trim().to_uppercase()
    }

    pub fn normalized_band(&self) -> String {
        self.band.trim().to_uppercase()
    }

    pub fn normalized_mode(&self) -> String {
        self.mode.to_uppercase()
    }

    pub fn normalized_park_reference(&self) -> Option<String> {
        let raw = self.park_reference.as_ref()?.trim().to_string();
        if raw.is_empty() {
            None
        } else {
            Some(raw.to_uppercase())
        }
    }

    /// Count of populated optional fields. Used as a tiebreaker when picking
    /// the merge winner.
    pub fn field_richness_score(&self) -> u32 {
        let mut score = 0u32;
        if self.rst_sent.is_some() { score += 1; }
        if self.rst_received.is_some() { score += 1; }
        if self.my_grid.is_some() { score += 1; }
        if self.their_grid.is_some() { score += 1; }
        if self.park_reference.is_some() { score += 1; }
        if self.notes.is_some() { score += 1; }
        if self.raw_adif.is_some() { score += 1; }
        if self.frequency.is_some() { score += 1; }
        if self.name.is_some() { score += 1; }
        if self.qth.is_some() { score += 1; }
        if self.state.is_some() { score += 1; }
        if self.country.is_some() { score += 1; }
        if self.power.is_some() { score += 1; }
        if self.their_license_class.is_some() { score += 1; }
        if self.sat_name.is_some() { score += 1; }
        if self.prop_mode.is_some() { score += 1; }
        score
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DuplicateGroup {
    pub winner_id: String,
    pub loser_ids: Vec<String>,
}

#[derive(Debug, Clone, Copy)]
pub struct DeduplicationConfig {
    /// Time window in seconds for considering QSOs as duplicates.
    pub time_window_secs: i64,
    /// If `false`, empty bands match anything.
    pub require_band_match: bool,
    pub require_park_match: bool,
}

impl DeduplicationConfig {
    pub const STANDARD: Self = Self {
        time_window_secs: 300,
        require_band_match: true,
        require_park_match: true,
    };

    pub const TWOFER_REPAIR: Self = Self {
        time_window_secs: 60,
        require_band_match: true,
        require_park_match: false,
    };
}

impl Default for DeduplicationConfig {
    fn default() -> Self {
        Self::STANDARD
    }
}

/// Are two QSOs duplicates under `config`?
pub fn is_duplicate(qso1: &QsoSnapshot, qso2: &QsoSnapshot, config: &DeduplicationConfig) -> bool {
    if qso1.normalized_callsign() != qso2.normalized_callsign() {
        return false;
    }
    if !ModeEquivalence::are_equivalent(&qso1.mode, &qso2.mode) {
        return false;
    }
    let delta = (qso1.timestamp_secs - qso2.timestamp_secs).abs();
    if delta > config.time_window_secs {
        return false;
    }
    if config.require_park_match {
        let p1 = qso1.normalized_park_reference();
        let p2 = qso2.normalized_park_reference();
        if p1 != p2 {
            return false;
        }
    }
    let band1 = qso1.normalized_band();
    let band2 = qso2.normalized_band();
    if config.require_band_match {
        if band1.is_empty() || band2.is_empty() {
            return true;
        }
        return band1 == band2;
    }
    true
}

/// Find duplicate groups within the snapshot set.
pub fn find_duplicate_groups(
    snapshots: &[QsoSnapshot],
    config: &DeduplicationConfig,
) -> Vec<DuplicateGroup> {
    if snapshots.len() < 2 {
        return Vec::new();
    }
    let mut sorted: Vec<&QsoSnapshot> = snapshots.iter().collect();
    sorted.sort_by_key(|s| s.timestamp_secs);

    let mut groups = Vec::new();
    let mut processed: HashSet<&str> = HashSet::new();

    for i in 0..sorted.len() {
        let qso = sorted[i];
        if processed.contains(qso.id.as_str()) {
            continue;
        }
        let mut group: Vec<&QsoSnapshot> = vec![qso];
        processed.insert(qso.id.as_str());

        for candidate in &sorted[i + 1..] {
            if processed.contains(candidate.id.as_str()) {
                continue;
            }
            let delta = candidate.timestamp_secs - qso.timestamp_secs;
            if delta > config.time_window_secs {
                break;
            }
            if is_duplicate(qso, candidate, config) {
                group.push(candidate);
                processed.insert(candidate.id.as_str());
            }
        }

        if group.len() > 1 {
            let winner = select_winner(&group);
            let loser_ids: Vec<String> = group
                .iter()
                .filter(|s| s.id != winner.id)
                .map(|s| s.id.clone())
                .collect();
            groups.push(DuplicateGroup {
                winner_id: winner.id.clone(),
                loser_ids,
            });
        }
    }
    groups
}

/// Pick the winner from a duplicate group. Priority: synced service count,
/// then field-richness score.
pub fn select_winner<'a>(group: &[&'a QsoSnapshot]) -> &'a QsoSnapshot {
    group
        .iter()
        .max_by(|a, b| {
            a.synced_services_count
                .cmp(&b.synced_services_count)
                .then_with(|| a.field_richness_score().cmp(&b.field_richness_score()))
        })
        .copied()
        .expect("non-empty group")
}

/// Merge field values, preferring non-empty values from the richer source.
pub fn merge_fields(winner: &QsoSnapshot, loser: &QsoSnapshot) -> QsoSnapshot {
    fn merge_opt<T: Clone>(a: &Option<T>, b: &Option<T>) -> Option<T> {
        a.clone().or_else(|| b.clone())
    }
    let band = if winner.normalized_band().is_empty() {
        loser.band.clone()
    } else {
        winner.band.clone()
    };
    QsoSnapshot {
        id: winner.id.clone(),
        callsign: winner.callsign.clone(),
        timestamp_secs: winner.timestamp_secs,
        band,
        mode: ModeEquivalence::more_specific(&winner.mode, &loser.mode),
        park_reference: merge_opt(&winner.park_reference, &loser.park_reference),
        frequency: merge_opt(&winner.frequency, &loser.frequency),
        rst_sent: merge_opt(&winner.rst_sent, &loser.rst_sent),
        rst_received: merge_opt(&winner.rst_received, &loser.rst_received),
        my_grid: merge_opt(&winner.my_grid, &loser.my_grid),
        their_grid: merge_opt(&winner.their_grid, &loser.their_grid),
        notes: merge_opt(&winner.notes, &loser.notes),
        raw_adif: merge_opt(&winner.raw_adif, &loser.raw_adif),
        name: merge_opt(&winner.name, &loser.name),
        qth: merge_opt(&winner.qth, &loser.qth),
        state: merge_opt(&winner.state, &loser.state),
        country: merge_opt(&winner.country, &loser.country),
        power: merge_opt(&winner.power, &loser.power),
        their_license_class: merge_opt(&winner.their_license_class, &loser.their_license_class),
        sat_name: merge_opt(&winner.sat_name, &loser.sat_name),
        prop_mode: merge_opt(&winner.prop_mode, &loser.prop_mode),
        synced_services_count: winner
            .synced_services_count
            .max(loser.synced_services_count),
    }
}

// ---- TwoferMatcher --------------------------------------------------------

#[derive(Debug, Clone, Copy)]
pub struct TwoferMatchConfig {
    pub time_window_secs: i64,
}

impl TwoferMatchConfig {
    pub const STANDARD: Self = Self { time_window_secs: 60 };
}

impl Default for TwoferMatchConfig {
    fn default() -> Self {
        Self::STANDARD
    }
}

/// Find snapshot IDs that are duplicates of a multi-park snapshot — these are
/// the QSOs that should be folded into the multi-park version.
pub fn find_twofer_duplicates_for(
    multi_park: &QsoSnapshot,
    all_snapshots: &[QsoSnapshot],
    config: &TwoferMatchConfig,
) -> Vec<String> {
    let Some(multi_park_ref) = multi_park.normalized_park_reference() else {
        return Vec::new();
    };
    if !park_reference::is_multi_park(&multi_park_ref) {
        return Vec::new();
    }
    let multi_parks = park_reference::split(&multi_park_ref);

    all_snapshots
        .iter()
        .filter_map(|candidate| {
            if candidate.id == multi_park.id {
                return None;
            }
            let candidate_ref = candidate.normalized_park_reference()?;
            let candidate_parks = park_reference::split(&candidate_ref);

            let fewer_parks = candidate_parks.len() < multi_parks.len();
            let shorter_string = candidate_ref.len() < multi_park_ref.len();
            if !(fewer_parks || shorter_string) {
                return None;
            }

            if !park_reference::is_subset(&candidate_ref, &multi_park_ref) {
                return None;
            }

            if multi_park.normalized_callsign() != candidate.normalized_callsign() {
                return None;
            }

            let delta = (multi_park.timestamp_secs - candidate.timestamp_secs).abs();
            if delta > config.time_window_secs {
                return None;
            }

            let band1 = multi_park.normalized_band();
            let band2 = candidate.normalized_band();
            if !band1.is_empty() && !band2.is_empty() && band1 != band2 {
                return None;
            }

            if !ModeEquivalence::are_equivalent(&multi_park.mode, &candidate.mode) {
                return None;
            }
            Some(candidate.id.clone())
        })
        .collect()
}

/// Find all two-fer duplicate groups. Winners are the multi-park QSOs.
pub fn find_twofer_duplicate_groups(
    snapshots: &[QsoSnapshot],
    config: &TwoferMatchConfig,
) -> Vec<DuplicateGroup> {
    let multi_park_snapshots: Vec<&QsoSnapshot> = snapshots
        .iter()
        .filter(|s| {
            s.normalized_park_reference()
                .map(|r| park_reference::is_multi_park(&r))
                .unwrap_or(false)
        })
        .collect();

    let mut groups = Vec::new();
    let mut processed: HashSet<String> = HashSet::new();

    for multi in multi_park_snapshots {
        if processed.contains(&multi.id) {
            continue;
        }
        let duplicate_ids = find_twofer_duplicates_for(multi, snapshots, config);
        if duplicate_ids.is_empty() {
            continue;
        }
        processed.insert(multi.id.clone());
        for id in &duplicate_ids {
            processed.insert(id.clone());
        }
        groups.push(DuplicateGroup {
            winner_id: multi.id.clone(),
            loser_ids: duplicate_ids,
        });
    }
    groups
}

/// The app-wide duplicate-import identity of a QSO. Port of
/// `QSO.makeDeduplicationKey` (`QSO+Dedup.swift`), which `ImportService`
/// compares against `fetchExistingDeduplicationKeys()` to skip re-imports:
/// `CALLSIGN|BAND|MODE|ts` with the callsign trimmed + uppercased, the band
/// uppercased, the mode via [`ModeEquivalence::canonical_name_for_dedup`], and
/// the timestamp truncated to a 2-minute bucket (`Int(ts / 120) * 120`).
pub fn deduplication_key(callsign: &str, band: &str, mode: &str, timestamp_secs: i64) -> String {
    let rounded = (timestamp_secs / 120) * 120;
    let trimmed_callsign = callsign.trim().to_uppercase();
    let canonical_mode = ModeEquivalence::canonical_name_for_dedup(mode);
    format!("{trimmed_callsign}|{}|{canonical_mode}|{rounded}", band.to_uppercase())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deduplication_key_matches_swift_shape() {
        // 1_700_000_050 floors to the 1_700_000_040 bucket (Int(ts/120)*120).
        assert_eq!(
            deduplication_key(" k1abc ", "20m", "ft8", 1_700_000_050),
            "K1ABC|20M|FT8|1700000040"
        );
        // Phone modes collapse to SSB; the same 2-minute bucket
        // (1_700_000_040 is a bucket start) is one key.
        assert_eq!(
            deduplication_key("W1AW", "40m", "usb", 1_700_000_040),
            deduplication_key("W1AW", "40M", "SSB", 1_700_000_159)
        );
        assert_ne!(
            deduplication_key("W1AW", "40m", "SSB", 1_700_000_040),
            deduplication_key("W1AW", "40m", "SSB", 1_700_000_160)
        );
    }

    fn base(id: &str, callsign: &str, ts: i64, band: &str, mode: &str) -> QsoSnapshot {
        QsoSnapshot {
            id: id.into(),
            callsign: callsign.into(),
            timestamp_secs: ts,
            band: band.into(),
            mode: mode.into(),
            park_reference: None,
            frequency: None,
            rst_sent: None,
            rst_received: None,
            my_grid: None,
            their_grid: None,
            notes: None,
            raw_adif: None,
            name: None,
            qth: None,
            state: None,
            country: None,
            power: None,
            their_license_class: None,
            sat_name: None,
            prop_mode: None,
            synced_services_count: 0,
        }
    }

    // ---- DeduplicationMatcher --------------------------------------------

    #[test]
    fn dedup_matches_same_call_band_mode_within_window() {
        let a = base("a", "W6JY", 1000, "20m", "FT8");
        let b = base("b", "w6jy", 1100, "20m", "FT8");
        assert!(is_duplicate(&a, &b, &DeduplicationConfig::STANDARD));
    }

    #[test]
    fn dedup_rejects_out_of_window() {
        let a = base("a", "W6JY", 0, "20m", "FT8");
        let b = base("b", "W6JY", 1000, "20m", "FT8");
        assert!(!is_duplicate(&a, &b, &DeduplicationConfig::STANDARD));
    }

    #[test]
    fn dedup_park_required_means_both_or_neither() {
        let mut a = base("a", "W6JY", 0, "20m", "FT8");
        let b = base("b", "W6JY", 60, "20m", "FT8");
        a.park_reference = Some("US-1234".into());
        assert!(!is_duplicate(&a, &b, &DeduplicationConfig::STANDARD));
    }

    #[test]
    fn dedup_band_agnostic_when_one_empty() {
        let mut a = base("a", "W6JY", 0, "", "FT8");
        let b = base("b", "W6JY", 60, "20m", "FT8");
        a.band = "".into();
        assert!(is_duplicate(&a, &b, &DeduplicationConfig::STANDARD));
    }

    #[test]
    fn find_duplicate_groups_finds_pair() {
        let a = base("a", "W6JY", 0, "20m", "FT8");
        let b = base("b", "W6JY", 100, "20m", "FT8");
        let c = base("c", "K2ABC", 50, "20m", "FT8");
        let groups = find_duplicate_groups(&[a, b, c], &DeduplicationConfig::STANDARD);
        assert_eq!(groups.len(), 1);
        let g = &groups[0];
        assert!(g.winner_id == "a" || g.winner_id == "b");
        assert_eq!(g.loser_ids.len(), 1);
    }

    #[test]
    fn select_winner_prefers_more_synced_services() {
        let mut a = base("a", "W6JY", 0, "20m", "FT8");
        let mut b = base("b", "W6JY", 0, "20m", "FT8");
        a.synced_services_count = 0;
        b.synced_services_count = 2;
        let group = [&a, &b];
        let winner = select_winner(&group);
        assert_eq!(winner.id, "b");
    }

    #[test]
    fn merge_fields_picks_richer_when_winner_lacks_field() {
        let mut winner = base("a", "W6JY", 0, "", "FT8");
        let mut loser = base("b", "W6JY", 0, "20m", "FT8");
        loser.notes = Some("nice QSO".into());
        winner.synced_services_count = 1;
        let merged = merge_fields(&winner, &loser);
        assert_eq!(merged.band, "20m"); // winner's empty band → loser's
        assert_eq!(merged.notes.as_deref(), Some("nice QSO"));
    }

    // ---- TwoferMatcher ----------------------------------------------------

    fn snap_with_park(id: &str, ts: i64, park: &str) -> QsoSnapshot {
        let mut s = base(id, "W6JY", ts, "20m", "FT8");
        s.park_reference = Some(park.into());
        s
    }

    #[test]
    fn twofer_finds_single_in_multi() {
        let multi = snap_with_park("multi", 0, "US-1044, US-3791");
        let single = snap_with_park("single", 30, "US-1044");
        let groups = find_twofer_duplicate_groups(
            &[multi, single],
            &TwoferMatchConfig::STANDARD,
        );
        assert_eq!(groups.len(), 1);
        let g = &groups[0];
        assert_eq!(g.winner_id, "multi");
        assert_eq!(g.loser_ids, vec!["single".to_string()]);
    }

    #[test]
    fn twofer_skips_when_callsign_differs() {
        let mut multi = snap_with_park("multi", 0, "US-1044, US-3791");
        let mut single = snap_with_park("single", 0, "US-1044");
        multi.callsign = "W6JY".into();
        single.callsign = "K2ABC".into();
        let groups = find_twofer_duplicate_groups(
            &[multi, single],
            &TwoferMatchConfig::STANDARD,
        );
        assert!(groups.is_empty());
    }

    #[test]
    fn twofer_skips_outside_window() {
        let multi = snap_with_park("multi", 0, "US-1044, US-3791");
        let single = snap_with_park("single", 1_000, "US-1044");
        let groups = find_twofer_duplicate_groups(
            &[multi, single],
            &TwoferMatchConfig::STANDARD,
        );
        assert!(groups.is_empty());
    }
}
