use std::collections::HashMap;
use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, RwLock};

use chrono::{DateTime, Utc};
use serde::Serialize;

/// Maximum spot age before eviction.
const MAX_AGE_SECS: i64 = 3600; // 1 hour

/// A single RBN spot parsed from the telnet stream.
#[derive(Debug, Clone, Serialize)]
pub struct RbnSpot {
    pub id: u64,
    pub callsign: String,
    pub frequency: f64,
    pub mode: String,
    pub snr: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub wpm: Option<u16>,
    pub spotter: String,
    pub band: &'static str,
    pub timestamp: DateTime<Utc>,
}

/// In-memory store for RBN spots with automatic 1-hour eviction.
#[derive(Clone)]
pub struct SpotStore {
    inner: Arc<SpotStoreInner>,
}

struct SpotStoreInner {
    spots: RwLock<VecDeque<RbnSpot>>,
    next_id: AtomicU64,
    connected: RwLock<bool>,
}

impl SpotStore {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(SpotStoreInner {
                spots: RwLock::new(VecDeque::new()),
                next_id: AtomicU64::new(1),
                connected: RwLock::new(false),
            }),
        }
    }

    /// Allocate the next spot ID.
    pub fn next_id(&self) -> u64 {
        self.inner.next_id.fetch_add(1, Ordering::Relaxed)
    }

    /// Push a batch of spots and evict stale entries.
    pub fn push_batch(&self, spots: Vec<RbnSpot>) {
        let mut store = self.inner.spots.write().unwrap();
        let cutoff = Utc::now() - chrono::Duration::seconds(MAX_AGE_SECS);

        // Evict stale spots from the front
        while let Some(front) = store.front() {
            if front.timestamp < cutoff {
                store.pop_front();
            } else {
                break;
            }
        }

        // Push new spots
        for spot in spots {
            store.push_back(spot);
        }
    }

    /// Set connection status.
    /// Number of spots currently buffered.
    pub fn len(&self) -> usize {
        self.inner.spots.read().unwrap().len()
    }

    pub fn set_connected(&self, connected: bool) {
        *self.inner.connected.write().unwrap() = connected;
    }

    /// Get connection status.
    pub fn is_connected(&self) -> bool {
        *self.inner.connected.read().unwrap()
    }

    /// Query spots with filters. Returns (matching_total, limited_spots).
    pub fn query(&self, filter: &SpotFilter) -> (usize, Vec<RbnSpot>) {
        let store = self.inner.spots.read().unwrap();
        let cutoff = filter
            .since
            .unwrap_or_else(|| Utc::now() - chrono::Duration::seconds(MAX_AGE_SECS));

        let matching: Vec<RbnSpot> = store
            .iter()
            .rev() // newest first
            .filter(|s| s.timestamp >= cutoff)
            .filter(|&s| {
                if let Some(ref call) = filter.call {
                    s.callsign.eq_ignore_ascii_case(call)
                } else {
                    true
                }
            })
            .filter(|s| {
                if let Some(ref spotter) = filter.spotter {
                    s.spotter.eq_ignore_ascii_case(spotter)
                } else {
                    true
                }
            })
            .filter(|s| {
                if let Some(ref modes) = filter.modes {
                    modes.iter().any(|m| m.eq_ignore_ascii_case(&s.mode))
                } else {
                    true
                }
            })
            .filter(|s| {
                if let Some(ref band) = filter.band {
                    s.band.eq_ignore_ascii_case(band)
                } else {
                    true
                }
            })
            .filter(|s| {
                if let Some(min) = filter.min_freq {
                    s.frequency >= min
                } else {
                    true
                }
            })
            .filter(|s| {
                if let Some(max) = filter.max_freq {
                    s.frequency <= max
                } else {
                    true
                }
            })
            .cloned()
            .collect();

        let total = matching.len();
        let limit = filter.limit.unwrap_or(100).min(500) as usize;
        let limited = matching.into_iter().take(limit).collect();

        (total, limited)
    }

    /// Get aggregate stats over a time window.
    pub fn stats(&self, minutes: u32) -> StatsResult {
        let store = self.inner.spots.read().unwrap();
        let cutoff = Utc::now() - chrono::Duration::minutes(minutes as i64);

        let mut bands: HashMap<&str, u64> = HashMap::new();
        let mut modes: HashMap<String, u64> = HashMap::new();
        let mut total: u64 = 0;

        for spot in store.iter() {
            if spot.timestamp >= cutoff {
                total += 1;
                *bands.entry(spot.band).or_default() += 1;
                *modes.entry(spot.mode.clone()).or_default() += 1;
            }
        }

        let spots_per_minute = if minutes > 0 {
            total as f64 / minutes as f64
        } else {
            0.0
        };

        StatsResult {
            minutes,
            total_spots: total,
            spots_per_minute,
            bands: bands.into_iter().map(|(k, v)| (k.to_string(), v)).collect(),
            modes,
        }
    }

    /// Get active skimmers over a time window.
    pub fn skimmers(&self, minutes: u32, limit: u32) -> SkimmersResult {
        let store = self.inner.spots.read().unwrap();
        let cutoff = Utc::now() - chrono::Duration::minutes(minutes as i64);

        let mut skimmer_data: HashMap<String, SkimmerAccum> = HashMap::new();

        for spot in store.iter() {
            if spot.timestamp >= cutoff {
                let entry =
                    skimmer_data
                        .entry(spot.spotter.clone())
                        .or_insert_with(|| SkimmerAccum {
                            spot_count: 0,
                            last_spot: spot.timestamp,
                            bands: Vec::new(),
                        });
                entry.spot_count += 1;
                if spot.timestamp > entry.last_spot {
                    entry.last_spot = spot.timestamp;
                }
                if !entry.bands.contains(&spot.band) {
                    entry.bands.push(spot.band);
                }
            }
        }

        let total_count = skimmer_data.len();
        let mut skimmers: Vec<SkimmerInfo> = skimmer_data
            .into_iter()
            .map(|(callsign, acc)| SkimmerInfo {
                callsign,
                spot_count: acc.spot_count,
                last_spot: acc.last_spot,
                bands: acc.bands.iter().map(|b| b.to_string()).collect(),
            })
            .collect();

        skimmers.sort_by(|a, b| b.spot_count.cmp(&a.spot_count));
        skimmers.truncate(limit.min(500) as usize);

        SkimmersResult {
            minutes,
            count: total_count,
            skimmers,
        }
    }

    /// Store size and oldest spot timestamp (for health reporting).
    pub fn health_info(&self) -> (usize, Option<DateTime<Utc>>) {
        let store = self.inner.spots.read().unwrap();
        let oldest = store.front().map(|s| s.timestamp);
        (store.len(), oldest)
    }
}

/// Filter parameters for spot queries.
pub struct SpotFilter {
    pub call: Option<String>,
    pub spotter: Option<String>,
    pub modes: Option<Vec<String>>,
    pub band: Option<String>,
    pub min_freq: Option<f64>,
    pub max_freq: Option<f64>,
    pub since: Option<DateTime<Utc>>,
    pub limit: Option<u32>,
}

struct SkimmerAccum {
    spot_count: u64,
    last_spot: DateTime<Utc>,
    bands: Vec<&'static str>,
}

#[derive(Serialize)]
pub struct StatsResult {
    pub minutes: u32,
    pub total_spots: u64,
    pub spots_per_minute: f64,
    pub bands: HashMap<String, u64>,
    pub modes: HashMap<String, u64>,
}

#[derive(Serialize)]
pub struct SkimmersResult {
    pub minutes: u32,
    pub count: usize,
    pub skimmers: Vec<SkimmerInfo>,
}

#[derive(Serialize)]
pub struct SkimmerInfo {
    pub callsign: String,
    pub spot_count: u64,
    pub last_spot: DateTime<Utc>,
    pub bands: Vec<String>,
}

/// Derive band from frequency in kHz.
pub fn freq_to_band(freq: f64) -> Option<&'static str> {
    match freq as u32 {
        1800..=2000 => Some("160m"),
        3500..=4000 => Some("80m"),
        5330..=5410 => Some("60m"),
        7000..=7300 => Some("40m"),
        10100..=10150 => Some("30m"),
        14000..=14350 => Some("20m"),
        18068..=18168 => Some("17m"),
        21000..=21450 => Some("15m"),
        24890..=24990 => Some("12m"),
        28000..=29700 => Some("10m"),
        50000..=54000 => Some("6m"),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Duration;

    fn make_spot(
        store: &SpotStore,
        callsign: &str,
        freq: f64,
        mode: &str,
        spotter: &str,
        age_secs: i64,
    ) -> RbnSpot {
        RbnSpot {
            id: store.next_id(),
            callsign: callsign.to_string(),
            frequency: freq,
            mode: mode.to_string(),
            snr: 15,
            wpm: if mode == "CW" { Some(25) } else { None },
            spotter: spotter.to_string(),
            band: freq_to_band(freq).unwrap_or("unknown"),
            timestamp: Utc::now() - Duration::seconds(age_secs),
        }
    }

    // ── freq_to_band ────────────────────────────────────────────────────────

    #[test]
    fn test_freq_to_band_all_bands() {
        assert_eq!(freq_to_band(1840.0), Some("160m"));
        assert_eq!(freq_to_band(3573.0), Some("80m"));
        assert_eq!(freq_to_band(5357.0), Some("60m"));
        assert_eq!(freq_to_band(7074.0), Some("40m"));
        assert_eq!(freq_to_band(10136.0), Some("30m"));
        assert_eq!(freq_to_band(14074.0), Some("20m"));
        assert_eq!(freq_to_band(18100.0), Some("17m"));
        assert_eq!(freq_to_band(21074.0), Some("15m"));
        assert_eq!(freq_to_band(24915.0), Some("12m"));
        assert_eq!(freq_to_band(28074.0), Some("10m"));
        assert_eq!(freq_to_band(50313.0), Some("6m"));
    }

    #[test]
    fn test_freq_to_band_out_of_range() {
        assert_eq!(freq_to_band(0.0), None);
        assert_eq!(freq_to_band(1799.0), None);
        assert_eq!(freq_to_band(2001.0), None);
        assert_eq!(freq_to_band(100000.0), None);
    }

    #[test]
    fn test_freq_to_band_boundaries() {
        // Lower boundary
        assert_eq!(freq_to_band(1800.0), Some("160m"));
        assert_eq!(freq_to_band(7000.0), Some("40m"));
        assert_eq!(freq_to_band(14000.0), Some("20m"));
        // Upper boundary
        assert_eq!(freq_to_band(2000.0), Some("160m"));
        assert_eq!(freq_to_band(7300.0), Some("40m"));
        assert_eq!(freq_to_band(14350.0), Some("20m"));
    }

    // ── SpotStore eviction ──────────────────────────────────────────────────

    #[test]
    fn test_store_evicts_stale_spots() {
        let store = SpotStore::new();

        // Add spots: one old (2 hours ago), one recent (30 seconds ago)
        let old_spot = make_spot(&store, "W1AW", 14074.0, "FT8", "KM3T-#", 7200);
        let new_spot = make_spot(&store, "N5XX", 7074.0, "FT8", "W3LPL-#", 30);

        store.push_batch(vec![old_spot]);
        assert_eq!(store.len(), 1);

        // Pushing a new batch triggers eviction of spots > 1 hour old
        store.push_batch(vec![new_spot]);
        assert_eq!(store.len(), 1, "Old spot should have been evicted");

        let (total, spots) = store.query(&SpotFilter {
            call: None,
            spotter: None,
            modes: None,
            band: None,
            min_freq: None,
            max_freq: None,
            since: None,
            limit: None,
        });
        assert_eq!(total, 1);
        assert_eq!(spots[0].callsign, "N5XX");
    }

    // ── SpotStore memory bounded ────────────────────────────────────────────

    #[test]
    fn test_store_memory_bounded_under_load() {
        let store = SpotStore::new();

        // Simulate high throughput: push 10,000 spots
        for batch_num in 0..100 {
            let mut batch = Vec::with_capacity(100);
            for i in 0..100 {
                batch.push(RbnSpot {
                    id: store.next_id(),
                    callsign: format!("CALL{}", batch_num * 100 + i),
                    frequency: 14074.0,
                    mode: "FT8".to_string(),
                    snr: 10,
                    wpm: None,
                    spotter: "KM3T-#".to_string(),
                    band: "20m",
                    timestamp: Utc::now() - Duration::seconds(5), // recent
                });
            }
            store.push_batch(batch);
        }

        // All 10,000 should still be present (all within 1-hour window)
        assert_eq!(store.len(), 10_000);

        // Now push spots that are old — they shouldn't accumulate
        let mut old_batch = Vec::with_capacity(100);
        for i in 0..100 {
            old_batch.push(RbnSpot {
                id: store.next_id(),
                callsign: format!("OLD{}", i),
                frequency: 7074.0,
                mode: "CW".to_string(),
                snr: 5,
                wpm: Some(20),
                spotter: "W3LPL-#".to_string(),
                band: "40m",
                timestamp: Utc::now() - Duration::seconds(7200), // 2 hours old
            });
        }
        // Push old batch first, then a trigger batch
        store.push_batch(old_batch);
        // Old spots were added but next push will evict them
        store.push_batch(vec![make_spot(
            &store, "TRIGGER", 14074.0, "FT8", "KM3T", 1,
        )]);
        // Old spots from 2h ago should be evicted
        assert!(store.len() <= 10_101, "Store should not grow unbounded");
    }

    // ── SpotStore query filters ─────────────────────────────────────────────

    #[test]
    fn test_query_filter_by_callsign() {
        let store = SpotStore::new();
        store.push_batch(vec![
            make_spot(&store, "W1AW", 14074.0, "FT8", "KM3T-#", 10),
            make_spot(&store, "N5XX", 7074.0, "FT8", "W3LPL-#", 10),
            make_spot(&store, "W1AW", 21074.0, "CW", "KM3T-#", 10),
        ]);

        let (total, spots) = store.query(&SpotFilter {
            call: Some("w1aw".to_string()), // case insensitive
            spotter: None,
            modes: None,
            band: None,
            min_freq: None,
            max_freq: None,
            since: None,
            limit: None,
        });
        assert_eq!(total, 2);
        assert!(spots.iter().all(|s| s.callsign == "W1AW"));
    }

    #[test]
    fn test_query_filter_by_mode() {
        let store = SpotStore::new();
        store.push_batch(vec![
            make_spot(&store, "W1AW", 14074.0, "FT8", "KM3T-#", 10),
            make_spot(&store, "N5XX", 14039.8, "CW", "W3LPL-#", 10),
            make_spot(&store, "K1ABC", 7074.0, "FT8", "KM3T-#", 10),
        ]);

        let (total, _) = store.query(&SpotFilter {
            call: None,
            spotter: None,
            modes: Some(vec!["CW".to_string()]),
            band: None,
            min_freq: None,
            max_freq: None,
            since: None,
            limit: None,
        });
        assert_eq!(total, 1);
    }

    #[test]
    fn test_query_filter_by_band() {
        let store = SpotStore::new();
        store.push_batch(vec![
            make_spot(&store, "W1AW", 14074.0, "FT8", "KM3T-#", 10),
            make_spot(&store, "N5XX", 7074.0, "FT8", "W3LPL-#", 10),
        ]);

        let (total, spots) = store.query(&SpotFilter {
            call: None,
            spotter: None,
            modes: None,
            band: Some("20m".to_string()),
            min_freq: None,
            max_freq: None,
            since: None,
            limit: None,
        });
        assert_eq!(total, 1);
        assert_eq!(spots[0].band, "20m");
    }

    #[test]
    fn test_query_filter_by_freq_range() {
        let store = SpotStore::new();
        store.push_batch(vec![
            make_spot(&store, "W1AW", 14074.0, "FT8", "KM3T-#", 10),
            make_spot(&store, "N5XX", 14039.8, "CW", "W3LPL-#", 10),
            make_spot(&store, "K1ABC", 7074.0, "FT8", "KM3T-#", 10),
        ]);

        let (total, _) = store.query(&SpotFilter {
            call: None,
            spotter: None,
            modes: None,
            band: None,
            min_freq: Some(14000.0),
            max_freq: Some(14100.0),
            since: None,
            limit: None,
        });
        assert_eq!(total, 2);
    }

    #[test]
    fn test_query_limit() {
        let store = SpotStore::new();
        let mut spots = Vec::new();
        for i in 0..50 {
            spots.push(make_spot(
                &store,
                &format!("CALL{}", i),
                14074.0,
                "FT8",
                "KM3T-#",
                10,
            ));
        }
        store.push_batch(spots);

        let (total, limited) = store.query(&SpotFilter {
            call: None,
            spotter: None,
            modes: None,
            band: None,
            min_freq: None,
            max_freq: None,
            since: None,
            limit: Some(10),
        });
        assert_eq!(total, 50);
        assert_eq!(limited.len(), 10);
    }

    // ── SpotStore stats ─────────────────────────────────────────────────────

    #[test]
    fn test_stats_band_and_mode_breakdown() {
        let store = SpotStore::new();
        store.push_batch(vec![
            make_spot(&store, "W1AW", 14074.0, "FT8", "KM3T-#", 10),
            make_spot(&store, "N5XX", 14039.8, "CW", "W3LPL-#", 10),
            make_spot(&store, "K1ABC", 7074.0, "FT8", "KM3T-#", 10),
        ]);

        let stats = store.stats(60);
        assert_eq!(stats.total_spots, 3);
        assert_eq!(*stats.modes.get("FT8").unwrap(), 2);
        assert_eq!(*stats.modes.get("CW").unwrap(), 1);
        assert_eq!(*stats.bands.get("20m").unwrap(), 2);
        assert_eq!(*stats.bands.get("40m").unwrap(), 1);
        assert!(stats.spots_per_minute > 0.0);
    }

    // ── SpotStore skimmers ──────────────────────────────────────────────────

    #[test]
    fn test_skimmers_aggregation() {
        let store = SpotStore::new();
        store.push_batch(vec![
            make_spot(&store, "W1AW", 14074.0, "FT8", "KM3T-#", 10),
            make_spot(&store, "N5XX", 7074.0, "FT8", "KM3T-#", 20),
            make_spot(&store, "K1ABC", 14039.8, "CW", "W3LPL-#", 10),
        ]);

        let result = store.skimmers(60, 100);
        assert_eq!(result.count, 2);
        // KM3T-# has 2 spots, should be first
        assert_eq!(result.skimmers[0].callsign, "KM3T-#");
        assert_eq!(result.skimmers[0].spot_count, 2);
        assert_eq!(result.skimmers[1].callsign, "W3LPL-#");
        assert_eq!(result.skimmers[1].spot_count, 1);
    }

    // ── SpotStore concurrent access ─────────────────────────────────────────

    #[test]
    fn test_concurrent_read_write() {
        use std::thread;

        let store = SpotStore::new();
        let store_writer = store.clone();
        let store_reader = store.clone();

        let writer = thread::spawn(move || {
            for i in 0..1000 {
                store_writer.push_batch(vec![RbnSpot {
                    id: store_writer.next_id(),
                    callsign: format!("W{}", i),
                    frequency: 14074.0,
                    mode: "FT8".to_string(),
                    snr: 10,
                    wpm: None,
                    spotter: "KM3T-#".to_string(),
                    band: "20m",
                    timestamp: Utc::now(),
                }]);
            }
        });

        let reader = thread::spawn(move || {
            let mut queries = 0;
            for _ in 0..1000 {
                let _ = store_reader.query(&SpotFilter {
                    call: None,
                    spotter: None,
                    modes: None,
                    band: None,
                    min_freq: None,
                    max_freq: None,
                    since: None,
                    limit: Some(10),
                });
                queries += 1;
            }
            queries
        });

        writer.join().unwrap();
        let queries = reader.join().unwrap();
        assert_eq!(
            queries, 1000,
            "All queries should complete without deadlock"
        );
    }

    // ── Connection status ───────────────────────────────────────────────────

    #[test]
    fn test_connection_status() {
        let store = SpotStore::new();
        assert!(!store.is_connected());
        store.set_connected(true);
        assert!(store.is_connected());
        store.set_connected(false);
        assert!(!store.is_connected());
    }

    #[test]
    fn test_health_info() {
        let store = SpotStore::new();
        let (len, oldest) = store.health_info();
        assert_eq!(len, 0);
        assert!(oldest.is_none());

        store.push_batch(vec![make_spot(
            &store, "W1AW", 14074.0, "FT8", "KM3T-#", 100,
        )]);
        let (len, oldest) = store.health_info();
        assert_eq!(len, 1);
        assert!(oldest.is_some());
    }
}
