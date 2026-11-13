//! Spot pool: merge/dedup/prune. Port of the pool half of Sweep's
//! `SpotAggregator.swift` (`unifiedSpots` + `mergeSpots` + `pruneExpired` +
//! `addClusterSpots`).

use std::collections::HashMap;

use crate::spots::model::{SpotSource, UnifiedSpot};

/// All live unified spots keyed by dedup key (`CALLSIGN-band`), preferring
/// higher-priority sources on collision.
#[derive(Debug, Default, Clone)]
pub struct SpotPool {
    spots: HashMap<String, UnifiedSpot>,
}

impl SpotPool {
    pub fn new() -> SpotPool {
        SpotPool::default()
    }

    /// Merge freshly fetched spots into the pool. A new spot replaces an
    /// existing one on the same key when its source priority is `>=` the
    /// incumbent's (Swift parity: same-source refreshes always update).
    pub fn merge(&mut self, new_spots: Vec<UnifiedSpot>) {
        for spot in new_spots {
            let key = spot.dedup_key();
            match self.spots.get(&key) {
                Some(existing)
                    if spot.source.merge_priority() < existing.source.merge_priority() => {}
                _ => {
                    self.spots.insert(key, spot);
                }
            }
        }
    }

    /// Cluster spots bypass the priority check entirely (Swift parity:
    /// `addClusterSpots` assigns unconditionally — and cluster is the
    /// highest-priority source anyway).
    pub fn merge_cluster(&mut self, cluster_spots: Vec<UnifiedSpot>) {
        for spot in cluster_spots {
            debug_assert_eq!(spot.source, SpotSource::Cluster);
            self.spots.insert(spot.dedup_key(), spot);
        }
    }

    /// Drop spots at or older than `now - max_age_secs` (Swift keeps strictly
    /// `timestamp > cutoff`).
    pub fn prune_expired(&mut self, now: i64, max_age_secs: i64) {
        let cutoff = now - max_age_secs;
        self.spots.retain(|_, spot| spot.timestamp > cutoff);
    }

    /// Current pool contents sorted newest-first (the order
    /// `enrichAndPublish` publishes in).
    pub fn snapshot(&self) -> Vec<UnifiedSpot> {
        let mut all: Vec<UnifiedSpot> = self.spots.values().cloned().collect();
        all.sort_by(|a, b| b.timestamp.cmp(&a.timestamp).then_with(|| a.id.cmp(&b.id)));
        all
    }

    /// Per-source spot counts (Sweep's `spotCounts` status display).
    pub fn counts_by_source(&self) -> HashMap<SpotSource, usize> {
        let mut counts = HashMap::new();
        for spot in self.spots.values() {
            *counts.entry(spot.source).or_insert(0) += 1;
        }
        counts
    }

    pub fn len(&self) -> usize {
        self.spots.len()
    }

    pub fn is_empty(&self) -> bool {
        self.spots.is_empty()
    }

    pub fn get(&self, dedup_key: &str) -> Option<&UnifiedSpot> {
        self.spots.get(dedup_key)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spot(id: &str, callsign: &str, khz: f64, ts: i64, source: SpotSource) -> UnifiedSpot {
        UnifiedSpot::base(
            id.to_string(),
            callsign.to_string(),
            khz,
            "CW".to_string(),
            ts,
            source,
        )
    }

    #[test]
    fn higher_priority_source_wins_collision() {
        let mut pool = SpotPool::new();
        pool.merge(vec![spot("rbn-1", "W1AW", 14_040.0, 100, SpotSource::Rbn)]);
        pool.merge(vec![spot("pota-1", "W1AW", 14_041.0, 90, SpotSource::Pota)]);
        // POTA (4) beats RBN (0) even with an older timestamp.
        assert_eq!(pool.get("W1AW-20m").unwrap().id, "pota-1");
    }

    #[test]
    fn lower_priority_source_does_not_replace() {
        let mut pool = SpotPool::new();
        pool.merge(vec![spot("pota-1", "W1AW", 14_040.0, 100, SpotSource::Pota)]);
        pool.merge(vec![spot("rbn-9", "W1AW", 14_041.0, 200, SpotSource::Rbn)]);
        assert_eq!(pool.get("W1AW-20m").unwrap().id, "pota-1");
    }

    #[test]
    fn equal_priority_refresh_updates() {
        let mut pool = SpotPool::new();
        pool.merge(vec![spot("rbn-1", "W1AW", 14_040.0, 100, SpotSource::Rbn)]);
        pool.merge(vec![spot("rbn-2", "W1AW", 14_042.0, 200, SpotSource::Rbn)]);
        // Swift's `>=` means same-source spots always refresh in place.
        assert_eq!(pool.get("W1AW-20m").unwrap().id, "rbn-2");
    }

    #[test]
    fn different_bands_do_not_collide() {
        let mut pool = SpotPool::new();
        pool.merge(vec![
            spot("rbn-1", "W1AW", 14_040.0, 100, SpotSource::Rbn),
            spot("rbn-2", "W1AW", 7_040.0, 100, SpotSource::Rbn),
        ]);
        assert_eq!(pool.len(), 2);
    }

    #[test]
    fn prune_is_strictly_greater_than_cutoff() {
        let mut pool = SpotPool::new();
        pool.merge(vec![
            spot("rbn-1", "W1AW", 14_040.0, 70, SpotSource::Rbn),
            spot("rbn-2", "K1ABC", 14_050.0, 71, SpotSource::Rbn),
        ]);
        // now=100, max_age=30 → cutoff=70; timestamp 70 is dropped, 71 kept.
        pool.prune_expired(100, 30);
        assert_eq!(pool.len(), 1);
        assert!(pool.get("K1ABC-20m").is_some());
    }

    #[test]
    fn snapshot_sorts_newest_first() {
        let mut pool = SpotPool::new();
        pool.merge(vec![
            spot("rbn-1", "W1AW", 14_040.0, 100, SpotSource::Rbn),
            spot("rbn-2", "K1ABC", 14_050.0, 300, SpotSource::Rbn),
            spot("rbn-3", "N0CALL", 14_060.0, 200, SpotSource::Rbn),
        ]);
        let ids: Vec<String> = pool.snapshot().into_iter().map(|s| s.id).collect();
        assert_eq!(ids, vec!["rbn-2", "rbn-3", "rbn-1"]);
    }

    #[test]
    fn cluster_merge_is_unconditional() {
        let mut pool = SpotPool::new();
        pool.merge(vec![spot("pota-1", "W1AW", 14_040.0, 100, SpotSource::Pota)]);
        pool.merge_cluster(vec![spot(
            "cluster-abc",
            "W1AW",
            14_040.0,
            50,
            SpotSource::Cluster,
        )]);
        assert_eq!(pool.get("W1AW-20m").unwrap().id, "cluster-abc");
    }
}
