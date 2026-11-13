//! Canned-feed tests for the propagation session engine. No network: a
//! [`CannedFeed`] replays queued RBN / PSK Reporter responses per poll and a
//! canned [`GridResolver`] injects grids, so the windowing / dedup / band
//! filter / enrichment / results math is exercised deterministically.

use std::collections::HashMap;
use std::sync::Mutex as StdMutex;

use cw_net::{PskReporterSpot, RbnSpot};

use super::*;

/// Scripted feed: each `next_*` call pops the front of the queue. An exhausted
/// queue returns an empty success (a poll with no new spots), so a test can
/// poll more times than it queued rounds.
pub struct CannedFeed {
    rbn: std::collections::VecDeque<Result<Vec<RbnSpot>, String>>,
    pskr: std::collections::VecDeque<Result<Vec<PskReporterSpot>, Option<String>>>,
}

impl CannedFeed {
    pub fn next_rbn(&mut self) -> Result<Vec<RbnSpot>, String> {
        self.rbn.pop_front().unwrap_or(Ok(Vec::new()))
    }

    pub fn next_pskr(&mut self) -> Result<Vec<PskReporterSpot>, Option<String>> {
        self.pskr.pop_front().unwrap_or(Ok(Vec::new()))
    }
}

/// Build a test API from a scripted feed + a canned `base → grid` enrichment map.
fn api_with(
    rbn_rounds: Vec<Result<Vec<RbnSpot>, String>>,
    pskr_rounds: Vec<Result<Vec<PskReporterSpot>, Option<String>>>,
    grids: HashMap<String, String>,
) -> PropagationApi {
    let feed = CannedFeed {
        rbn: rbn_rounds.into(),
        pskr: pskr_rounds.into(),
    };
    PropagationApi {
        session: StdMutex::new(None),
        feed: SpotFeed::Canned(StdMutex::new(feed)),
        resolver: GridResolver::Canned(grids),
    }
}

fn config(callsign: &str, bands: &[&str], user_grid: &str) -> FfiPropagationConfig {
    FfiPropagationConfig {
        callsign: callsign.to_string(),
        bands: bands.iter().map(|b| b.to_string()).collect(),
        user_grid: user_grid.to_string(),
        started_at_epoch: 1_735_000_000.0,
        solar: None,
    }
}

fn rbn(callsign: &str, freq_khz: f64, spotter: &str, grid: Option<&str>, snr: i64, ts: &str) -> RbnSpot {
    RbnSpot {
        id: 1,
        callsign: callsign.to_string(),
        frequency: freq_khz,
        mode: "CW".to_string(),
        timestamp: ts.to_string(),
        snr,
        wpm: Some(25),
        spotter: spotter.to_string(),
        spotter_grid: grid.map(str::to_string),
    }
}

fn pskr(sender: &str, receiver: &str, freq_hz: i64, loc: Option<&str>, snr: Option<i32>, flow: i64) -> PskReporterSpot {
    PskReporterSpot {
        sender_callsign: sender.to_string(),
        sender_locator: Some("CM87".to_string()),
        receiver_callsign: receiver.to_string(),
        receiver_locator: loc.map(str::to_string),
        frequency: freq_hz,
        mode: "FT8".to_string(),
        snr,
        flow_start_seconds: flow,
    }
}

async fn poll(api: &PropagationApi) -> FfiPropagationState {
    api.poll().await.expect("poll ok")
}

// -- Callsign matcher (PropagationCheckConfig.matches) ----------------------

#[test]
fn callsign_matcher_is_suffix_tolerant() {
    assert!(callsign_matches("W6JY", "W6JY"));
    assert!(callsign_matches("W6JY", "w6jy")); // case-insensitive
    assert!(callsign_matches("W6JY", "W6JY/P"));
    assert!(callsign_matches("W6JY", "W6JY/QRP"));
    assert!(!callsign_matches("W6JY", "W6JYX")); // no bare-suffix collision
    assert!(!callsign_matches("W6JY", "W6JY/")); // empty suffix rejected
    assert!(!callsign_matches("W6JY", "W6JY/P/M")); // extra slash rejected
    assert!(!callsign_matches("W6JY", "K6XYZ"));
}

#[test]
fn base_skimmer_strips_hyphen_suffix() {
    assert_eq!(base_skimmer_callsign("AK6RI-1-#"), "AK6RI");
    assert_eq!(base_skimmer_callsign("k2abc"), "K2ABC");
    assert_eq!(base_skimmer_callsign("W1AW"), "W1AW");
}

// -- Ingestion / dedup / filters --------------------------------------------

#[tokio::test]
async fn ingests_rbn_and_pskr_matching_callsign() {
    let api = api_with(
        vec![Ok(vec![rbn("W6JY", 14_025.0, "K2ABC", Some("FN20"), 19, "2026-02-03T20:43:36Z")])],
        vec![Ok(vec![pskr("W6JY", "K3XYZ", 14_074_000, Some("EM10"), Some(-10), 1_735_000_100)])],
        HashMap::new(),
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    let state = poll(&api).await;
    assert_eq!(state.total_spots, 2);
    assert_eq!(state.unique_skimmers, 2);
    assert!(state.rbn_connected && state.pskr_connected);
}

#[tokio::test]
async fn drops_non_matching_callsign() {
    let api = api_with(
        vec![Ok(vec![rbn("K6XYZ", 14_025.0, "K2ABC", Some("FN20"), 19, "2026-02-03T20:43:36Z")])],
        vec![],
        HashMap::new(),
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    let state = poll(&api).await;
    assert_eq!(state.total_spots, 0);
}

#[tokio::test]
async fn band_filter_excludes_off_band_spots() {
    let api = api_with(
        vec![Ok(vec![
            rbn("W6JY", 14_025.0, "K2ABC", Some("FN20"), 19, "2026-02-03T20:43:36Z"), // 20m
            rbn("W6JY", 7_030.0, "K4DEF", Some("EM73"), 12, "2026-02-03T20:44:00Z"),  // 40m
        ])],
        vec![],
        HashMap::new(),
    );
    api.start_session(config("W6JY", &["20m"], "CM87")).unwrap();
    let state = poll(&api).await;
    assert_eq!(state.total_spots, 1);
    assert_eq!(state.bands_with_activity, vec!["20m".to_string()]);
}

#[tokio::test]
async fn dedups_identical_spots_across_polls() {
    let dup = rbn("W6JY", 14_025.0, "K2ABC", Some("FN20"), 19, "2026-02-03T20:43:36Z");
    let api = api_with(
        vec![Ok(vec![dup.clone()]), Ok(vec![dup.clone()])],
        vec![Ok(vec![]), Ok(vec![])],
        HashMap::new(),
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    let first = poll(&api).await;
    assert_eq!(first.total_spots, 1);
    let second = poll(&api).await;
    assert_eq!(second.total_spots, 1, "the identical spot must collapse on the dedup key");
}

// -- Connectivity failure handling ------------------------------------------

#[tokio::test]
async fn rbn_failure_flags_disconnect_but_keeps_running() {
    let api = api_with(
        vec![Err("boom".to_string())],
        vec![Ok(vec![])],
        HashMap::new(),
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    let state = poll(&api).await;
    assert!(!state.rbn_connected);
    assert!(state.last_error.as_deref().unwrap().contains("rbn"));
    assert!(state.is_running);
}

#[tokio::test]
async fn pskr_rate_limit_is_soft_and_does_not_disconnect() {
    let api = api_with(
        vec![Ok(vec![])],
        vec![Err(None)], // soft rate-limit
        HashMap::new(),
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    let state = poll(&api).await;
    assert!(state.pskr_connected, "a rate-limit must not be treated as a connectivity gap");
    assert!(state.last_error.is_none());
}

// -- Enrichment waterfall (grid → callbook fallback → projection) ------------

#[tokio::test]
async fn reported_grid_projects_distance_and_bearing() {
    let api = api_with(
        vec![Ok(vec![rbn("W6JY", 14_025.0, "K2ABC", Some("FN20"), 19, "2026-02-03T20:43:36Z")])],
        vec![],
        HashMap::new(),
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    let state = poll(&api).await;
    let enriched = &state.enriched_spots[0];
    assert_eq!(enriched.effective_grid.as_deref(), Some("FN20"));
    assert!(enriched.latitude.is_some() && enriched.longitude.is_some());
    let expected = maidenhead::distance_km("CM87", "FN20").unwrap();
    assert!((enriched.distance_km.unwrap() - expected).abs() < 1e-6);
    assert!(enriched.bearing.is_some());
}

#[tokio::test]
async fn missing_grid_is_filled_from_the_callbook_resolver() {
    // The skimmer has no reported grid; the canned resolver supplies it by the
    // hyphen-stripped base call ("AK6RI-#" → "AK6RI").
    let mut grids = HashMap::new();
    grids.insert("AK6RI".to_string(), "DM04".to_string());
    let api = api_with(
        vec![Ok(vec![rbn("W6JY", 14_025.0, "AK6RI-#", None, 15, "2026-02-03T20:43:36Z")])],
        vec![],
        grids,
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    let state = poll(&api).await;
    let enriched = &state.enriched_spots[0];
    assert_eq!(enriched.effective_grid.as_deref(), Some("DM04"));
    let expected = maidenhead::distance_km("CM87", "DM04").unwrap();
    assert!((enriched.distance_km.unwrap() - expected).abs() < 1e-6);
}

#[tokio::test]
async fn unresolvable_grid_keeps_spot_without_coordinate() {
    let api = api_with(
        vec![Ok(vec![rbn("W6JY", 14_025.0, "NOGRID", None, 15, "2026-02-03T20:43:36Z")])],
        vec![],
        HashMap::new(), // resolver has nothing
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    let state = poll(&api).await;
    assert_eq!(state.total_spots, 1, "spot is kept even with no grid");
    let enriched = &state.enriched_spots[0];
    assert!(enriched.effective_grid.is_none());
    assert!(enriched.latitude.is_none() && enriched.distance_km.is_none());
}

// -- Headline stats ----------------------------------------------------------

#[tokio::test]
async fn headline_stats_track_max_distance_and_peak_snr() {
    let api = api_with(
        vec![Ok(vec![
            rbn("W6JY", 14_025.0, "K2ABC", Some("FN20"), 19, "2026-02-03T20:43:36Z"), // far
            rbn("W6JY", 14_025.0, "K7NEAR", Some("CM88"), 30, "2026-02-03T20:44:00Z"), // near, higher SNR
        ])],
        vec![],
        HashMap::new(),
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    let state = poll(&api).await;
    assert_eq!(state.total_spots, 2);
    assert_eq!(state.peak_snr_db, 30.0);
    let far = maidenhead::distance_km("CM87", "FN20").unwrap();
    assert!((state.max_distance_km - far).abs() < 1e-6, "max distance uses the farther skimmer");
}

// -- Lifecycle: stop + results ----------------------------------------------

#[tokio::test]
async fn results_finalize_full_spot_list_and_totals() {
    let api = api_with(
        vec![Ok(vec![rbn("W6JY", 14_025.0, "K2ABC", Some("FN20"), 19, "2026-02-03T20:43:36Z")])],
        vec![Ok(vec![pskr("W6JY", "K3XYZ", 14_074_000, Some("EM10"), Some(-10), 1_735_000_100)])],
        HashMap::new(),
    );
    api.start_session(config("W6JY", &["20m"], "CM87")).unwrap();
    poll(&api).await;
    api.stop(FfiPropagationStopReason::User).unwrap();
    let results = api.results().unwrap();
    assert_eq!(results.callsign, "W6JY");
    assert_eq!(results.user_grid, "CM87");
    assert_eq!(results.bands_requested, vec!["20m".to_string()]);
    assert_eq!(results.total_spots, 2);
    assert_eq!(results.spots.len(), 2);
    assert_eq!(results.enriched_spots.len(), 2);
    assert!(results.ended_at_epoch >= results.started_at_epoch);
}

#[tokio::test]
async fn poll_on_stopped_session_returns_snapshot_without_fetch() {
    let api = api_with(
        vec![Ok(vec![rbn("W6JY", 14_025.0, "K2ABC", Some("FN20"), 19, "2026-02-03T20:43:36Z")])],
        vec![],
        HashMap::new(),
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    poll(&api).await;
    api.stop(FfiPropagationStopReason::User).unwrap();
    // A second RBN round was NOT queued; if poll fetched it'd get the empty
    // fallback anyway, but the spot count must stay put and is_running false.
    let state = poll(&api).await;
    assert!(!state.is_running);
    assert_eq!(state.total_spots, 1);
}

#[tokio::test]
async fn start_session_resets_prior_spots() {
    let api = api_with(
        vec![
            Ok(vec![rbn("W6JY", 14_025.0, "K2ABC", Some("FN20"), 19, "2026-02-03T20:43:36Z")]),
            Ok(vec![]),
        ],
        vec![Ok(vec![]), Ok(vec![])],
        HashMap::new(),
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    poll(&api).await;
    // Restart — spots + dedup keys must clear.
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    let state = poll(&api).await;
    assert_eq!(state.total_spots, 0);
}

// -- PSK Reporter 5-minute floor --------------------------------------------

#[test]
fn pskr_due_honors_five_minute_floor() {
    // First poll always due.
    assert!(pskr_due(None, 1_000.0));
    // Just after a poll: not due (< 305 - 5).
    assert!(!pskr_due(Some(1_000.0), 1_100.0));
    // Past the floor: due again.
    assert!(pskr_due(Some(1_000.0), 1_000.0 + PSKR_POLL_INTERVAL_SECS - 5.0));
    assert!(pskr_due(Some(1_000.0), 1_400.0));
}

#[tokio::test]
async fn pskr_not_refetched_within_the_floor() {
    // Two polls in quick succession: the second must NOT consume a PSKR round
    // (the floor blocks it), so the queued second PSKR batch is untouched.
    let api = api_with(
        vec![Ok(vec![]), Ok(vec![])],
        vec![
            Ok(vec![pskr("W6JY", "K3XYZ", 14_074_000, Some("EM10"), Some(-10), 1_735_000_100)]),
            Ok(vec![pskr("W6JY", "K9LATE", 14_074_000, Some("EN50"), Some(-8), 1_735_000_200)]),
        ],
        HashMap::new(),
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    let first = poll(&api).await;
    assert_eq!(first.total_spots, 1);
    // Immediate second poll — PSKR floor not elapsed, so no second PSKR fetch.
    let second = poll(&api).await;
    assert_eq!(second.total_spots, 1, "PSKR must not be re-polled inside the 5-min floor");
}

// -- Connectivity-gap state machine (map port phase D fix) -------------------

#[tokio::test]
async fn rbn_gap_opens_on_failure_and_closes_on_reconnect() {
    // Round 1: RBN fails (opens a gap). Round 2: RBN succeeds (closes it).
    let api = api_with(
        vec![
            Err("boom".to_string()),
            Ok(vec![rbn("W6JY", 14_025.0, "K2ABC", Some("FN20"), 19, "2026-02-03T20:43:36Z")]),
        ],
        vec![Ok(vec![]), Ok(vec![])],
        HashMap::new(),
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    poll(&api).await; // failure — gap open, not yet in results
    let mid = api.results().unwrap();
    assert!(mid.connectivity_gaps.is_empty(), "an open gap is not surfaced until it closes");
    poll(&api).await; // reconnect — gap closes
    let results = api.results().unwrap();
    assert_eq!(results.connectivity_gaps.len(), 1);
    let gap = &results.connectivity_gaps[0];
    assert_eq!(gap.source, "rbn");
    // Endpoints are real epoch timestamps and ordered.
    assert!(gap.started_at_epoch > 0.0);
    assert!(gap.ended_at_epoch >= gap.started_at_epoch);
}

#[tokio::test]
async fn pskr_gap_opens_on_hard_failure_and_closes_on_reconnect() {
    let api = api_with(
        vec![Ok(vec![]), Ok(vec![])],
        vec![
            Err(Some("pskr down".to_string())), // hard failure — opens a gap
            Ok(vec![pskr("W6JY", "K3XYZ", 14_074_000, Some("EM10"), Some(-10), 1_735_000_100)]),
        ],
        HashMap::new(),
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    // First poll fails PSKR. The PSKR floor blocks the second poll from
    // re-fetching immediately, so drive results after just the failure...
    poll(&api).await;
    let after_fail = api.results().unwrap();
    assert!(after_fail.connectivity_gaps.is_empty(), "gap still open, not surfaced");
    // ...then stop() must close the still-open PSKR gap.
    api.stop(FfiPropagationStopReason::User).unwrap();
    let results = api.results().unwrap();
    assert_eq!(results.connectivity_gaps.len(), 1);
    assert_eq!(results.connectivity_gaps[0].source, "pskr");
}

#[tokio::test]
async fn stop_closes_an_open_rbn_gap() {
    let api = api_with(
        vec![Err("boom".to_string())],
        vec![Ok(vec![])],
        HashMap::new(),
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    poll(&api).await; // gap opens, never reconnects
    api.stop(FfiPropagationStopReason::Duration).unwrap();
    let results = api.results().unwrap();
    assert_eq!(results.connectivity_gaps.len(), 1, "stop() must close the still-open gap");
    assert_eq!(results.connectivity_gaps[0].source, "rbn");
    let gap = &results.connectivity_gaps[0];
    assert!(gap.ended_at_epoch >= gap.started_at_epoch);
}

#[tokio::test]
async fn multiple_rbn_gaps_per_source_are_recorded_separately() {
    // fail (open A) -> ok (close A) -> fail (open B) -> ok (close B) => 2 gaps.
    let api = api_with(
        vec![
            Err("boom1".to_string()),
            Ok(vec![]),
            Err("boom2".to_string()),
            Ok(vec![]),
        ],
        vec![Ok(vec![]), Ok(vec![]), Ok(vec![]), Ok(vec![])],
        HashMap::new(),
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    poll(&api).await;
    poll(&api).await;
    poll(&api).await;
    poll(&api).await;
    let results = api.results().unwrap();
    assert_eq!(results.connectivity_gaps.len(), 2, "each failure/reconnect cycle is its own gap");
    assert!(results.connectivity_gaps.iter().all(|g| g.source == "rbn"));
}

#[tokio::test]
async fn consecutive_failures_do_not_reopen_a_gap() {
    // fail (open) -> fail (still same gap) -> ok (close) => exactly one gap
    // whose start is the FIRST failure.
    let api = api_with(
        vec![
            Err("boom1".to_string()),
            Err("boom2".to_string()),
            Ok(vec![]),
        ],
        vec![Ok(vec![]), Ok(vec![]), Ok(vec![])],
        HashMap::new(),
    );
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    poll(&api).await;
    poll(&api).await;
    poll(&api).await;
    let results = api.results().unwrap();
    assert_eq!(results.connectivity_gaps.len(), 1, "consecutive failures stay one gap");
}

// -- Solar snapshot passthrough (map port phase D fix) ----------------------

#[tokio::test]
async fn solar_snapshot_is_threaded_through_to_results() {
    let api = api_with(vec![Ok(vec![])], vec![Ok(vec![])], HashMap::new());
    let mut cfg = config("W6JY", &[], "CM87");
    cfg.solar = Some(FfiPropagationSolar {
        k_index: Some(2.0),
        a_index: Some(7),
        flux: Some(142.5),
        sunspots: Some(96),
        propagation_rating: Some("Good".to_string()),
        band_conditions: Some("20m-15m: Good".to_string()),
        timestamp_epoch: Some(1_735_000_050.0),
    });
    api.start_session(cfg.clone()).unwrap();
    poll(&api).await;
    api.stop(FfiPropagationStopReason::User).unwrap();
    let results = api.results().unwrap();
    assert_eq!(results.solar, cfg.solar, "solar passes through verbatim");
}

#[tokio::test]
async fn absent_solar_snapshot_stays_none() {
    let api = api_with(vec![Ok(vec![])], vec![], HashMap::new());
    api.start_session(config("W6JY", &[], "CM87")).unwrap(); // solar: None
    poll(&api).await;
    let results = api.results().unwrap();
    assert!(results.solar.is_none());
}

// -- Stop reason stamping (map port phase D fix) ----------------------------

#[tokio::test]
async fn stop_reason_is_stamped_into_results() {
    let api = api_with(vec![Ok(vec![])], vec![], HashMap::new());
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    poll(&api).await;
    api.stop(FfiPropagationStopReason::RadioFault).unwrap();
    let results = api.results().unwrap();
    assert_eq!(results.stop_reason, FfiPropagationStopReason::RadioFault);
}

#[tokio::test]
async fn stop_reason_defaults_to_user_before_stop() {
    let api = api_with(vec![Ok(vec![])], vec![], HashMap::new());
    api.start_session(config("W6JY", &[], "CM87")).unwrap();
    poll(&api).await;
    // results() read before stop() — defaults to User.
    let results = api.results().unwrap();
    assert_eq!(results.stop_reason, FfiPropagationStopReason::User);
}
