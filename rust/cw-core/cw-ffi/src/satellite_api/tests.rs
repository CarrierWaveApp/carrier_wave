//! Network-free tests of the cache-through refresh policy and the built
//! surface, via the `SatFeed::Canned` variant (the `propagation_api`
//! canned-feed pattern).

use std::collections::VecDeque;
use std::sync::Arc;
use std::sync::Mutex as StdMutex;

use super::*;

/// Scripted per-call feed responses; `None` scripts a network failure.
#[derive(Default)]
pub(super) struct CannedFeed {
    pub tles: VecDeque<Option<Vec<SatnogsTle>>>,
    pub transmitters: VecDeque<Option<Vec<SatnogsTransmitter>>>,
    pub amsat: VecDeque<Option<Vec<cw_net::AmsatStatusRow>>>,
    pub satellites: VecDeque<Option<Vec<SatnogsSatellite>>>,
    pub activity: VecDeque<Option<cw_net::AmsatActivityResponse>>,
    pub reports: VecDeque<Option<cw_net::AmsatReportsResponse>>,
    /// Receipts for `submit_report`, with each submission AMSAT "saw".
    pub submissions: VecDeque<Option<cw_net::AmsatSubmitReceipt>>,
    pub submitted: Vec<cw_net::AmsatReportSubmission>,
    /// Latency before each TLE fetch resolves (zero = immediate).
    pub tle_delay: std::time::Duration,
}

impl CannedFeed {
    fn next<T>(queue: &mut VecDeque<Option<Vec<T>>>) -> Result<Vec<T>, CwError> {
        match queue.pop_front() {
            Some(Some(rows)) => Ok(rows),
            _ => Err(CwError::Network { reason: "canned network failure".to_string() }),
        }
    }

    pub(super) fn next_tles(&mut self) -> Result<Vec<SatnogsTle>, CwError> {
        Self::next(&mut self.tles)
    }

    pub(super) fn next_transmitters(&mut self) -> Result<Vec<SatnogsTransmitter>, CwError> {
        Self::next(&mut self.transmitters)
    }

    pub(super) fn next_amsat(&mut self) -> Result<Vec<cw_net::AmsatStatusRow>, CwError> {
        Self::next(&mut self.amsat)
    }

    pub(super) fn next_satellites(&mut self) -> Result<Vec<SatnogsSatellite>, CwError> {
        Self::next(&mut self.satellites)
    }

    pub(super) fn next_reports(&mut self) -> Result<cw_net::AmsatReportsResponse, CwError> {
        match self.reports.pop_front() {
            Some(Some(response)) => Ok(response),
            _ => Err(CwError::Network { reason: "canned network failure".to_string() }),
        }
    }

    pub(super) fn next_activity(&mut self) -> Result<cw_net::AmsatActivityResponse, CwError> {
        match self.activity.pop_front() {
            Some(Some(response)) => Ok(response),
            _ => Err(CwError::Network { reason: "canned network failure".to_string() }),
        }
    }

    pub(super) fn next_submission(
        &mut self,
        submission: &cw_net::AmsatReportSubmission,
    ) -> Result<cw_net::AmsatSubmitReceipt, CwError> {
        self.submitted.push(submission.clone());
        match self.submissions.pop_front() {
            Some(Some(receipt)) => Ok(receipt),
            _ => Err(CwError::Network { reason: "A valid amateur radio callsign is required.".to_string() }),
        }
    }
}

fn iss_tle_row() -> SatnogsTle {
    serde_json::from_str(
        r#"{"tle0":"0 ISS (ZARYA)",
            "tle1":"1 25544U 98067A   26262.30395647  .00006211  00000-0  12007-3 0  9998",
            "tle2":"2 25544  51.6308 194.2901 0004815 157.3949 202.7252 15.49175317586346",
            "norad_cat_id":25544}"#,
    )
    .expect("tle row")
}

fn iss_transmitter_row() -> SatnogsTransmitter {
    serde_json::from_str(
        r#"{"description":"Mode V/U FM Voice Repeater","type":"Transceiver",
            "alive":true,"status":"active","service":"Amateur","mode":"FM",
            "uplink_low":145990000,"downlink_low":437800000,"norad_cat_id":25544}"#,
    )
    .expect("transmitter row")
}

fn api_with_feed(feed: CannedFeed) -> SatelliteApi {
    let store = Arc::new(FieldStore::open_in_memory("k".into()).expect("store"));
    SatelliteApi::with_feed(store, SatFeed::Canned(StdMutex::new(feed)))
}

fn feed_with(
    tles: Option<Vec<SatnogsTle>>,
    transmitters: Option<Vec<SatnogsTransmitter>>,
    amsat: Option<Vec<cw_net::AmsatStatusRow>>,
) -> CannedFeed {
    let mut feed = CannedFeed::default();
    feed.tles.push_back(tles);
    feed.transmitters.push_back(transmitters);
    feed.amsat.push_back(amsat);
    // Canonical names default to "none available" — soft-fail like AMSAT.
    feed.satellites.push_back(Some(Vec::new()));
    feed
}

#[tokio::test]
async fn refresh_builds_catalog_and_serves_surface() {
    let api = api_with_feed(feed_with(
        Some(vec![iss_tle_row()]),
        Some(vec![iss_transmitter_row()]),
        Some(Vec::new()),
    ));
    let summary = api.refresh(false).await.expect("refresh");
    assert_eq!(summary.satellite_count, 1);
    assert!(!summary.tles_stale);
    assert!(summary.amsat_available);

    let catalog = api.catalog();
    assert_eq!(catalog.len(), 1);
    assert_eq!(catalog[0].norad_id, 25_544);
    assert_eq!(catalog[0].transmitters.len(), 1);
    assert_eq!(catalog[0].transmitters[0].mode_category, FfiSatModeCategory::VoiceFm);
    // ISS has a curated (linear) polarization entry.
    assert_eq!(catalog[0].polarization.as_ref().map(|p| p.is_circular), Some(false));

    // Positions propagate with look angles for an observer.
    let positions = api.positions(1_789_852_958, Some(FfiObserver { lat_deg: 37.7749, lon_deg: -122.4194 }));
    assert_eq!(positions.len(), 1);
    assert!(positions[0].elevation_deg.is_some());
    assert!(positions[0].footprint_radius_m > 1_000_000.0);

    // Coastlines export non-empty polylines.
    assert!(!api.coastline_continents().is_empty());
}

#[tokio::test]
async fn refresh_hits_fresh_cache_without_fetching() {
    // First refresh consumes the only scripted responses…
    let mut feed = feed_with(
        Some(vec![iss_tle_row()]),
        Some(vec![iss_transmitter_row()]),
        Some(Vec::new()),
    );
    // …the second would fail if it touched the network (empty queues fail).
    feed.tles.push_back(None);
    let api = api_with_feed(feed);
    api.refresh(false).await.expect("first refresh");
    let summary = api.refresh(false).await.expect("cache-hit refresh");
    assert_eq!(summary.satellite_count, 1);
    assert!(!summary.tles_stale);
}

#[tokio::test]
async fn refresh_degrades_to_stale_cache_on_network_failure() {
    let api = api_with_feed(feed_with(
        Some(vec![iss_tle_row()]),
        Some(vec![iss_transmitter_row()]),
        Some(Vec::new()),
    ));
    api.refresh(false).await.expect("seed cache");
    // Expire the cache rows, then script a total network failure.
    {
        let inner = api.store.inner.lock().expect("store");
        for kind in [KIND_TLE, KIND_TRANSMITTERS, KIND_AMSAT, KIND_SATELLITES] {
            let (payload, _) = inner.fetch_satellite_data(kind).expect("row").expect("cached");
            inner.upsert_satellite_data(kind, &payload, 0).expect("age out");
        }
    }
    let summary = api.refresh(false).await.expect("stale degrade");
    assert_eq!(summary.satellite_count, 1);
    assert!(summary.tles_stale);
}

/// Age every cached satellite kind past the TTL (fetched_at = epoch 0).
fn expire_cache(api: &SatelliteApi) {
    let inner = api.store.inner.lock().expect("store");
    for kind in [KIND_TLE, KIND_TRANSMITTERS, KIND_AMSAT, KIND_SATELLITES] {
        if let Some((payload, _)) = inner.fetch_satellite_data(kind).expect("row") {
            inner.upsert_satellite_data(kind, &payload, 0).expect("age out");
        }
    }
}

/// Queue one more full set of successful responses.
fn script_success(api: &SatelliteApi) {
    let SatFeed::Canned(feed) = &api.feed else { unreachable!() };
    let mut feed = feed.lock().expect("feed");
    feed.tles.push_back(Some(vec![iss_tle_row()]));
    feed.transmitters.push_back(Some(vec![iss_transmitter_row()]));
    feed.amsat.push_back(Some(Vec::new()));
    feed.satellites.push_back(Some(Vec::new()));
}

fn queued_tle_responses(api: &SatelliteApi) -> usize {
    let SatFeed::Canned(feed) = &api.feed else { unreachable!() };
    feed.lock().expect("feed").tles.len()
}

#[tokio::test]
async fn load_cached_is_none_when_nothing_cached() {
    let api = api_with_feed(CannedFeed::default());
    assert!(api.load_cached().await.expect("load").is_none());
    assert!(api.catalog().is_empty());
}

#[tokio::test]
async fn load_cached_builds_from_expired_cache_without_network() {
    let seeded = api_with_feed(feed_with(
        Some(vec![iss_tle_row()]),
        Some(vec![iss_transmitter_row()]),
        Some(Vec::new()),
    ));
    seeded.refresh(false).await.expect("seed cache");
    expire_cache(&seeded);

    // A fresh engine over the same store, with an empty feed: any network
    // call would fail, so a catalog proves the load was cache-only.
    let api = SatelliteApi::with_feed(seeded.store.clone(), SatFeed::Canned(StdMutex::new(CannedFeed::default())));
    let summary = api.load_cached().await.expect("load").expect("cached");
    assert_eq!(summary.satellite_count, 1);
    assert!(summary.tles_stale, "expired TLEs report stale");
    assert!(summary.amsat_available);
    assert_eq!(api.catalog().len(), 1);
}

#[tokio::test]
async fn load_cached_never_replaces_a_newer_catalog() {
    let api = api_with_feed(feed_with(
        Some(vec![iss_tle_row()]),
        Some(vec![iss_transmitter_row()]),
        Some(Vec::new()),
    ));
    let fresh = api.refresh(false).await.expect("refresh");
    // Make the cached rows older than the installed catalog.
    expire_cache(&api);
    let summary = api.load_cached().await.expect("load").expect("cached");
    assert_eq!(summary.tles_fetched_at_epoch, fresh.tles_fetched_at_epoch);
    assert!(!summary.tles_stale, "kept the newer, fresh catalog");
}

#[tokio::test]
async fn failed_fetch_backs_off_to_stale_without_network() {
    let api = api_with_feed(feed_with(
        Some(vec![iss_tle_row()]),
        Some(vec![iss_transmitter_row()]),
        Some(Vec::new()),
    ));
    api.refresh(false).await.expect("seed cache");
    expire_cache(&api);

    // Empty queues: this refresh's fetches fail and it degrades to stale.
    let failed = api.refresh(false).await.expect("stale degrade");
    assert!(failed.tles_stale);

    // The network is back, but inside the backoff a normal refresh serves
    // the stale cache without fetching.
    script_success(&api);
    let backed_off = api.refresh(false).await.expect("backed off");
    assert!(backed_off.tles_stale);
    assert_eq!(queued_tle_responses(&api), 1, "backoff must not touch the network");

    // A forced (user-initiated) refresh ignores the backoff and recovers.
    let forced = api.refresh(true).await.expect("forced");
    assert!(!forced.tles_stale);
    assert_eq!(queued_tle_responses(&api), 0);

    // Success clears the backoff: once expired again, a failure is retried.
    expire_cache(&api);
    script_success(&api);
    let retried = api.refresh(false).await.expect("retried");
    assert!(!retried.tles_stale);
}

#[tokio::test]
async fn concurrent_refreshes_share_one_download() {
    // One scripted response set and a slow TLE fetch. Without the gate the
    // second refresh would find no cache and fail on the empty queue.
    let mut feed = feed_with(
        Some(vec![iss_tle_row()]),
        Some(vec![iss_transmitter_row()]),
        Some(Vec::new()),
    );
    feed.tle_delay = std::time::Duration::from_millis(50);
    let api = api_with_feed(feed);
    let (first, second) = tokio::join!(api.refresh(false), api.refresh(false));
    let (first, second) = (first.expect("first"), second.expect("second"));
    assert_eq!(first.satellite_count, 1);
    assert_eq!(second.satellite_count, 1);
    assert_eq!(second.tles_fetched_at_epoch, first.tles_fetched_at_epoch);
}

#[tokio::test]
async fn forced_refresh_reuses_a_refresh_that_finished_while_waiting() {
    let mut feed = feed_with(
        Some(vec![iss_tle_row()]),
        Some(vec![iss_transmitter_row()]),
        Some(Vec::new()),
    );
    feed.tle_delay = std::time::Duration::from_millis(50);
    let api = api_with_feed(feed);
    let (background, forced) = tokio::join!(api.refresh(false), api.refresh(true));
    background.expect("background");
    // Had the forced call downloaded again it would hit the empty queue and
    // degrade to stale; reusing the fresh result keeps it fresh.
    assert!(!forced.expect("forced").tles_stale);
}

#[tokio::test]
async fn refresh_errors_when_cold_and_offline() {
    let api = api_with_feed(feed_with(None, None, None));
    assert!(api.refresh(false).await.is_err());
    assert!(api.catalog().is_empty());
}

#[tokio::test]
async fn satnogs_catalog_names_replace_tle_placeholders() {
    let mut tle = iss_tle_row();
    tle.tle0 = "0 OBJECT C".to_string();
    tle.norad_cat_id = 44_881;
    let mut transmitter = iss_transmitter_row();
    transmitter.norad_cat_id = Some(44_881);
    let mut feed = feed_with(Some(vec![tle]), Some(vec![transmitter]), Some(Vec::new()));
    feed.satellites.clear();
    feed.satellites.push_back(Some(vec![serde_json::from_str(
        r#"{"name":"CAS-6 (TO-108)","names":"2019-093C","norad_cat_id":44881}"#,
    )
    .expect("satellite row")]));
    let api = api_with_feed(feed);
    api.refresh(false).await.expect("refresh");
    let catalog = api.catalog();
    assert_eq!(catalog.len(), 1);
    assert_eq!(catalog[0].name, "TO-108");
    assert_eq!(catalog[0].detail_name.as_deref(), Some("CAS-6"));
}

#[tokio::test]
async fn amsat_failure_is_soft() {
    let api = api_with_feed(feed_with(
        Some(vec![iss_tle_row()]),
        Some(vec![iss_transmitter_row()]),
        None, // AMSAT down
    ));
    let summary = api.refresh(false).await.expect("refresh");
    assert_eq!(summary.satellite_count, 1);
    assert!(!summary.amsat_available);
}

#[tokio::test]
async fn plan_alerts_flows_through_planner() {
    let api = api_with_feed(feed_with(
        Some(vec![iss_tle_row()]),
        Some(vec![iss_transmitter_row()]),
        Some(Vec::new()),
    ));
    api.refresh(false).await.expect("refresh");
    let observer = FfiObserver { lat_deg: 37.7749, lon_deg: -122.4194 };
    // Fixture pass 2 (peak 43.5° at epoch 1_789_858_718) sits inside this
    // 24 h window; lead 15 min.
    let alerts = api
        .plan_alerts(observer, vec![25_544], false, 900, 1_789_853_200, 24.0)
        .await
        .expect("plan");
    assert!(!alerts.is_empty());
    assert!(alerts[0].identifier.starts_with("satpass-25544-"));
    assert_eq!(alerts[0].fire_epoch, alerts[0].aos_epoch - 900);
    assert!(alerts[0].title.contains("pass in 15 min"));
    // No favorites → no alerts.
    let none = api
        .plan_alerts(observer, Vec::new(), false, 900, 1_789_853_200, 24.0)
        .await
        .expect("plan empty");
    assert!(none.is_empty());
}

#[test]
fn create_pass_session_is_born_completed_and_invisible_to_current() {
    let api = api_with_feed(CannedFeed::default());
    let id = api
        .create_pass_session(FfiPassSessionInput {
            my_callsign: "w6jy".to_string(),
            my_grid: Some("cm87".to_string()),
            mode: "FM".to_string(),
            frequency_mhz: Some(145.99),
            sat_name: "SO-50".to_string(),
            started_at_epoch: 1_789_853_200,
            ended_at_epoch: 1_789_853_900,
        })
        .expect("create");
    let inner = api.store.inner.lock().expect("store mutex poisoned");
    let session = inner
        .fetch_logging_session(&id)
        .expect("fetch")
        .expect("session row exists");
    assert_eq!(session.status_raw_value, "completed");
    assert_eq!(session.ended_at, Some(1_789_853_900));
    assert_eq!(session.my_callsign, "W6JY");
    assert_eq!(session.my_grid.as_deref(), Some("CM87"));
    assert_eq!(session.custom_title.as_deref(), Some("SO-50 pass"));
    assert_eq!(session.qso_count, 0);
    // The whole point: a live activation must never see this session.
    assert!(inner.fetch_current_session().expect("current").is_none());
}

/// Heard an hour ago (wall clock — the catalog's workability gate uses
/// `Utc::now()`, so a fixed date would age out of the 7-day window).
fn iss_amsat_row() -> cw_net::AmsatStatusRow {
    let heard = (Utc::now() - chrono::Duration::hours(1)).to_rfc3339();
    serde_json::from_str(&format!(
        r#"{{"name":"ISS_[FM]","noradId":25544,
            "lastHeardAt":"{heard}","lastReportedAt":"{heard}",
            "lastReport":"Heard","lastCallsign":"W6JY","lastGrid":"CM87",
            "heardReports24h":4,"totalReports24h":5}}"#
    ))
    .expect("amsat row")
}

fn activity_response() -> cw_net::AmsatActivityResponse {
    serde_json::from_str(
        r#"{"bucketSeconds":3600,
            "windowStart":"2026-07-13T12:00:00Z","windowEnd":"2026-07-20T12:00:00Z",
            "updatedAt":"2026-07-20T11:50:00Z",
            "satellites":[
              {"name":"ISS_[FM]","noradId":25544,"buckets":[
                 {"start":"2026-07-20T09:00:00Z","heard":2},
                 {"start":"2026-07-20T10:00:00Z","heard":1,"notHeard":1}
              ]},
              {"name":"MYSTERY-1_[SSB]","buckets":[
                 {"start":"2026-07-19T03:00:00Z","telemetry":1}
              ]}
            ]}"#,
    )
    .expect("activity response")
}

/// A logged satellite QSO (every other column at its logger default).
fn sat_qso(id: &str, sat: &str, qso_date: i64) -> cw_store::Qso {
    cw_store::Qso {
        id: id.to_string(),
        callsign: "W1AW".to_string(),
        band: Some("70cm".to_string()),
        mode: Some("FM".to_string()),
        freq_khz: Some(145_990.0),
        qso_date,
        my_grid: Some("CM87".to_string()),
        their_grid: Some("EM12".to_string()),
        rst_sent: None,
        rst_rcvd: None,
        my_callsign: Some("W6JY".to_string()),
        park: None,
        their_park: None,
        notes: None,
        notes_user_authored: false,
        spot_comments_data: None,
        callsign_change_note: None,
        original_callsign: None,
        import_source_raw_value: "logger".to_string(),
        imported_at: qso_date,
        modified_at: None,
        raw_adif: None,
        name: None,
        qth: None,
        state: None,
        country: None,
        power: None,
        my_rig: None,
        station_profile_name: None,
        sota_ref: None,
        wwff_ref: None,
        aoa_code: None,
        qrz_log_id: None,
        qrz_confirmed: false,
        lotw_confirmed_date: None,
        lotw_confirmed: false,
        dxcc: Some(291),
        their_license_class: None,
        contest_name: None,
        contest_serial_sent: None,
        contest_serial_received: None,
        contest_exchange_sent: None,
        contest_exchange_received: None,
        is_hidden: false,
        is_activity_log_qso: false,
        station_callsign: None,
        logging_session_id: None,
        dirty: true,
        sat_name: Some(sat.to_string()),
        prop_mode: Some("SAT".to_string()),
    }
}

#[tokio::test]
async fn community_activity_enriches_rows_from_catalog_log_and_passes() {
    let mut feed = feed_with(
        Some(vec![iss_tle_row()]),
        Some(vec![iss_transmitter_row()]),
        Some(vec![iss_amsat_row()]),
    );
    feed.activity.push_back(Some(activity_response()));
    let api = api_with_feed(feed);
    // 2026-07-20T12:00:00Z — inside the TLE's validity so the sweep finds a pass.
    let now = 1_784_548_800;
    api.refresh(false).await.expect("refresh");

    // Two logged ISS QSOs inside the window, one before it, one through
    // another bird.
    {
        let inner = api.store.inner.lock().expect("store");
        let log = |id: &str, sat: &str, date: i64| {
            inner.upsert_qso(&sat_qso(id, sat, date)).unwrap();
        };
        log("a", "ISS", now - 3_600);
        log("b", "iss", now - 7_200);
        log("c", "ISS", now - 10 * 24 * 3_600);
        log("d", "SO-50", now - 3_600);
    }

    let observer = FfiObserver { lat_deg: 37.7749, lon_deg: -122.4194 };
    let activity = api
        .community_activity(false, Some(observer), now, 3 * 3_600)
        .await
        .expect("activity");
    assert!(!activity.is_stale);
    assert_eq!(activity.bucket_secs, 3 * 3_600);
    assert_eq!(activity.updated_at_epoch, Some(1_784_548_200));
    assert_eq!(activity.rows.len(), 2);

    let iss = &activity.rows[0];
    assert_eq!(iss.amsat_name, "ISS_[FM]");
    assert_eq!(iss.base_name, "ISS");
    assert_eq!(iss.capability.as_deref(), Some("FM"));
    assert_eq!(iss.norad_id, Some(25_544));
    assert!(iss.in_catalog);
    assert_eq!(iss.display_name, "ISS");
    assert_eq!(iss.mode_category, Some(FfiSatModeCategory::VoiceFm));
    assert_eq!(iss.transmitter_mode.as_deref(), Some("FM"));
    assert_eq!(iss.downlink_low_hz, Some(437_800_000));
    assert_eq!(iss.transmitter_active, Some(true));
    assert_eq!(iss.heard_reports_24h, 4);
    assert_eq!(iss.my_qso_count, 2);
    assert!(iss.next_pass.is_some(), "observer given + in catalog → next pass");
    // 09:00 and 10:00 fall in the same 3 h cell (window-aligned at 12:00 → 09:00–12:00).
    assert_eq!(iss.buckets.len(), 1);
    assert_eq!(iss.buckets[0].start_epoch, 1_784_538_000);
    assert_eq!((iss.buckets[0].heard, iss.buckets[0].not_heard, iss.buckets[0].total), (3, 1, 4));
    assert_eq!(iss.buckets[0].status, FfiActivityStatus::Conflicting);

    let mystery = &activity.rows[1];
    assert!(!mystery.in_catalog);
    assert_eq!(mystery.norad_id, None);
    assert_eq!(mystery.display_name, "MYSTERY-1");
    assert_eq!(mystery.mode_category, Some(FfiSatModeCategory::Linear));
    assert!(mystery.next_pass.is_none());
    assert_eq!(mystery.my_qso_count, 0);
    assert_eq!(mystery.buckets[0].status, FfiActivityStatus::TelemetryOnly);

    // Second call inside the TTL is served from the cache without a feed hit
    // (the canned queue is empty — a fetch would fail).
    let again = api.community_activity(false, None, now + 60, 3_600).await.expect("cached");
    assert_eq!(again.rows.len(), 2);
    assert!(again.rows[0].next_pass.is_none(), "no observer → no pass sweep");
    assert_eq!(again.rows[0].buckets.len(), 2, "hourly cells");

    // Forced refresh with the feed down degrades to the stale cache.
    let stale = api.community_activity(true, None, now + 120, 3_600).await.expect("stale");
    assert!(stale.is_stale);
}

#[tokio::test]
async fn community_activity_requires_catalog() {
    let api = api_with_feed(CannedFeed::default());
    assert!(api.community_activity(false, None, 0, 3_600).await.is_err());
}

#[tokio::test]
async fn community_reports_place_reporters_and_summarize_previous_orbit() {
    let mut feed = feed_with(
        Some(vec![iss_tle_row()]),
        Some(vec![iss_transmitter_row()]),
        Some(vec![iss_amsat_row()]),
    );
    // now = 2026-07-20T12:00:00Z; ISS period ≈ 93 min → window opens ~2 h ago.
    let now = 1_784_548_800;
    let json = r#"{"windowStart":"2026-07-19T12:00:00Z","windowEnd":"2026-07-20T12:00:00Z",
            "names":["ISS_[FM]"],
            "reports":[
              {"name":"ISS_[FM]","reportedAt":"2026-07-20T11:30:00Z","callsign":"EI6FZ","report":"Heard","grid":"IO63"},
              {"name":"ISS_[FM]","reportedAt":"2026-07-20T10:30:00Z","callsign":"DL6AP","report":"Not Heard","grid":"JO64ae"},
              {"name":"ISS_[FM]","reportedAt":"2026-07-20T02:30:00Z","callsign":"BG7NTA","report":"Heard"}
            ]}"#;
    feed.reports.push_back(Some(serde_json::from_str(json).expect("reports")));
    let api = api_with_feed(feed);
    api.refresh(false).await.expect("refresh");

    let reports = api.community_reports(25_544, false, now).await.expect("reports");
    assert!(!reports.is_stale);
    assert_eq!(reports.reports.len(), 3);
    let first = &reports.reports[0];
    assert_eq!(first.callsign, "EI6FZ");
    assert_eq!(first.status, FfiActivityStatus::Heard);
    // IO63 → roughly 53.5°N, 7°W.
    assert!((first.latitude.unwrap() - 53.5).abs() < 1.0);
    assert!((first.longitude.unwrap() - -7.0).abs() < 1.5);
    assert!(reports.reports[2].latitude.is_none(), "no grid → no placement");

    let orbit = reports.previous_orbit.expect("catalog bird has a period");
    assert!((orbit.period_minutes - 93.0).abs() < 2.0);
    assert_eq!((orbit.heard, orbit.not_heard, orbit.telemetry), (1, 1, 0));
    assert_eq!(orbit.heard_callsigns, vec!["EI6FZ".to_string()]);
    assert_eq!(orbit.status, FfiActivityStatus::Conflicting);

    // Cached on the second call (feed queue is empty).
    let again = api.community_reports(25_544, false, now + 60, ).await.expect("cached");
    assert_eq!(again.reports.len(), 3);
}

#[tokio::test]
async fn linear_transponder_carries_passband_edges_and_invert() {
    let linear: SatnogsTransmitter = serde_json::from_str(
        r#"{"description":"Mode V/U Linear Transponder","type":"Transponder",
            "alive":true,"status":"active","service":"Amateur","mode":"SSB",
            "uplink_low":145935000,"uplink_high":145995000,
            "downlink_low":435610000,"downlink_high":435670000,
            "invert":true,"norad_cat_id":25544}"#,
    )
    .expect("linear row");
    let api = api_with_feed(feed_with(
        Some(vec![iss_tle_row()]),
        Some(vec![iss_transmitter_row(), linear]),
        Some(Vec::new()),
    ));
    api.refresh(false).await.expect("refresh");

    let catalog = api.catalog();
    let transmitters = &catalog[0].transmitters;
    assert_eq!(transmitters.len(), 2);
    let fm = transmitters.iter().find(|t| t.mode.as_deref() == Some("FM")).expect("fm row");
    assert!(!fm.invert);
    assert_eq!(fm.uplink_high_hz, None);
    let ssb = transmitters.iter().find(|t| t.mode.as_deref() == Some("SSB")).expect("ssb row");
    assert!(ssb.invert);
    assert_eq!(ssb.uplink_high_hz, Some(145_995_000));
    assert_eq!(ssb.downlink_high_hz, Some(435_670_000));
}

// MARK: - Filing a report

#[tokio::test]
async fn submit_community_report_normalizes_and_returns_the_receipt() {
    let mut feed = CannedFeed::default();
    feed.submissions.push_back(Some(cw_net::AmsatSubmitReceipt {
        id: 456,
        name: "SO-50_[FM]".into(),
        reported_time: chrono::DateTime::parse_from_rfc3339("2026-10-31T13:30:00Z").unwrap().into(),
        callsign: "W6JY".into(),
        report: "Heard".into(),
        grid_square: Some("CM87".into()),
        replaced_count: 1,
    }));
    let api = api_with_feed(feed);
    let receipt = api
        .submit_community_report(FfiCommunityReportSubmission {
            amsat_name: "SO-50_[FM]".into(),
            report: "not  heard".into(),
            callsign: " w6jy ".into(),
            grid: Some("CM87".into()),
            reported_at_epoch: 1_793_000_000,
        })
        .await
        .expect("canned receipt");
    assert_eq!(receipt.id, 456);
    assert_eq!(receipt.replaced_count, 1);
    assert_eq!(receipt.reported_at_epoch, 1_793_453_400);

    let SatFeed::Canned(feed) = &api.feed else { unreachable!() };
    let sent = &feed.lock().unwrap().submitted;
    assert_eq!(sent.len(), 1);
    // Verdict canonicalised, callsign upper-cased, time in AMSAT's layout.
    assert_eq!(sent[0].report, "Not Heard");
    assert_eq!(sent[0].callsign, "W6JY");
    assert_eq!(sent[0].reported_at, "2026-10-26T07:33:20Z");
}

#[tokio::test]
async fn submit_community_report_validates_before_the_network() {
    let api = api_with_feed(CannedFeed::default());
    let base = FfiCommunityReportSubmission {
        amsat_name: "SO-50_[FM]".into(),
        report: "Heard".into(),
        callsign: "W6JY".into(),
        grid: None,
        reported_at_epoch: 1_793_000_000,
    };
    let bad_verdict = FfiCommunityReportSubmission { report: "Loud".into(), ..base.clone() };
    let err = api.submit_community_report(bad_verdict).await.unwrap_err().to_string();
    assert!(err.contains("Heard, Telemetry Only, Not Heard, Crew Active"), "{err}");

    let no_call = FfiCommunityReportSubmission { callsign: "  ".into(), ..base.clone() };
    assert!(api.submit_community_report(no_call).await.unwrap_err().to_string().contains("callsign"));

    let future = FfiCommunityReportSubmission {
        reported_at_epoch: chrono::Utc::now().timestamp() + 86_400,
        ..base.clone()
    };
    assert!(api.submit_community_report(future).await.unwrap_err().to_string().contains("future"));

    // Nothing reached the (canned) network.
    let SatFeed::Canned(feed) = &api.feed else { unreachable!() };
    assert!(feed.lock().unwrap().submitted.is_empty());

    // AMSAT's rejection message is surfaced verbatim.
    let err = api.submit_community_report(base).await.unwrap_err().to_string();
    assert!(err.contains("A valid amateur radio callsign is required."), "{err}");
    assert_eq!(amsat_report_values(), ["Heard", "Telemetry Only", "Not Heard", "Crew Active"]);
    assert!(amsat_attribution().contains("https://status.amsat.org"));
}
