//! `PropagationApi` — the shared "How's my antenna?" propagation-check session
//! engine. Port of the iOS `PropagationCheckSession` (+`+Polling`) service, the
//! `PropagationCheck*` model shapes, and the `PropagationCheckEnrichment` grid
//! waterfall. Both platforms drive one session through this object instead of a
//! per-platform Swift/Kotlin service.
//!
//! ## Lifecycle
//! - [`PropagationApi::start_session`] freezes a [`FfiPropagationConfig`] and
//!   resets the session (spots, dedup keys, connectivity gaps).
//! - [`PropagationApi::poll`] runs one RBN + (rate-limited) PSK Reporter fetch
//!   round, ingests+dedups+windows the results, enriches missing grids, and
//!   returns the current [`FfiPropagationState`]. The host calls it on the
//!   cadence it wants; the engine still enforces the PSK Reporter 5-minute floor
//!   internally (like the Swift `pollPSKROnce` guard).
//! - [`PropagationApi::stop`] marks the session stopped (idempotent), stamps the
//!   stop reason, and closes any open connectivity gap.
//! - [`PropagationApi::results`] returns the finalized [`FfiPropagationResults`]
//!   with the full spot list + headline totals to persist an artifact.
//!
//! ## Cadence / window constants (ported verbatim — provenance below)
//! `RBN_POLL_INTERVAL_SECS` / `PSKR_POLL_INTERVAL_SECS` are the Swift
//! `PropagationCheckSession.rbnPollInterval` (30) and `.pskrPollInterval` (305).
//! `PSKR_LOOKBACK_SECS` is the Swift `pollPSKROnce` `seconds: -1_800`.
//! `RBN_LOOKBACK_HOURS` / `RBN_FETCH_LIMIT` are the `pollRBNOnce`
//! `hours: 1, limit: 200`. These are not knobs — they preserve the ingestion
//! semantics the artifact was built under.
//!
//! ## Fetch sources
//! RBN comes through the activities-server proxy (`{base}/v1/rbn/spots`) via
//! `cw_net::RbnClient` — the SAME source the iOS `RBNClient` uses. PSK Reporter
//! comes from `retrieve.pskreporter.info` via `cw_net::PskReporterClient`. Both
//! fetch calls are factored behind the [`SpotFeed`] injectable so windowing /
//! enrichment / results math is unit-tested with canned feeds (no network), the
//! way `ParkMapApi`'s cache-through is.
//!
//! ## Enrichment waterfall
//! Port of `PropagationCheckEnrichment.enrichMissingGrids`, with the Swift HamDB
//! fallback REPLACED by the Phase B callbook path: a spot's own reported grid
//! wins; on a miss we read the `callbook_location` cache (30-day TTL, like
//! `QrzApi::locate`); on a further miss we run the QRZ→HamDB merge the locate
//! flow uses (`resolve_location`, reused verbatim from `qrz_api`) and write the
//! result back to the cache. Distance / bearing are `cw_domain::maidenhead`.

mod records;

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex as StdMutex};
use std::time::{SystemTime, UNIX_EPOCH};

use cw_domain::maidenhead;
use cw_domain::BandUtilities;
use cw_net::{HttpClient, PskReporterClient, PskReporterSpot, RbnClient, RbnSpot};

use crate::qrz_api::QrzApi;
use crate::{CwError, FieldStore};

pub use records::*;

// ---------------------------------------------------------------------------
// Cadence / window constants — ported verbatim from PropagationCheckSession.
// ---------------------------------------------------------------------------

/// RBN poll cadence, seconds. Swift `PropagationCheckSession.rbnPollInterval`.
pub const RBN_POLL_INTERVAL_SECS: f64 = 30.0;
/// PSK Reporter poll cadence, seconds (public API 5-min minimum). Swift
/// `PropagationCheckSession.pskrPollInterval`.
pub const PSKR_POLL_INTERVAL_SECS: f64 = 305.0;
/// PSK Reporter lookback window (negative = "seconds back"). Swift
/// `pollPSKROnce`'s `fetchSenderSpots(seconds: -1_800)` — 30 minutes.
pub const PSKR_LOOKBACK_SECS: i64 = -1_800;
/// RBN lookback window. Swift `pollRBNOnce`'s `spots(for:hours:1,limit:200)`.
pub const RBN_LOOKBACK_HOURS: u32 = 1;
/// RBN per-poll fetch limit. Swift `pollRBNOnce`'s `limit: 200`.
pub const RBN_FETCH_LIMIT: u32 = 200;

/// TTL for `callbook_location` cache reads during enrichment: 30 days, matching
/// `QrzApi::locate` (`LOCATION_TTL_SECS`) / iOS `MemberLocationCache.maxAge`.
const LOCATION_TTL_SECS: i64 = 30 * 24 * 60 * 60;
/// Max network callbook lookups per enrichment pass. Swift
/// `PropagationCheckEnrichment.enrichMissingGrids(maxLookups: 30)`.
const MAX_ENRICH_LOOKUPS: usize = 30;

// ---------------------------------------------------------------------------
// Spot feed abstraction (real clients vs canned tests)
// ---------------------------------------------------------------------------
//
// cw-ffi has no `async-trait`, so the fetch/enrich surfaces are enums with an
// inherent `async fn` that matches on the variant. The `Canned` variants exist
// only under `cfg(test)` — they replay scripted feeds so the windowing / dedup
// / enrichment / results math runs with no network (the ParkMapApi
// cache-through-testability precedent, adapted to a stateful session).

/// The RBN + PSK Reporter fetch surface. `Net` wraps the shared `cw_net`
/// clients (the real activities-server proxy + `retrieve.pskreporter.info`);
/// `Canned` (tests only) replays queued per-poll responses.
enum SpotFeed {
    Net { rbn: RbnClient, pskr: PskReporterClient },
    #[cfg(test)]
    Canned(std::sync::Mutex<tests::CannedFeed>),
}

impl SpotFeed {
    /// RBN spots for `callsign` (last [`RBN_LOOKBACK_HOURS`] hours, ≤
    /// [`RBN_FETCH_LIMIT`]). `Err` marks an RBN connectivity failure.
    async fn fetch_rbn(&self, callsign: &str) -> Result<Vec<RbnSpot>, String> {
        match self {
            SpotFeed::Net { rbn, .. } => rbn
                .fetch_spots_for_callsign(callsign, RBN_LOOKBACK_HOURS, RBN_FETCH_LIMIT)
                .await
                .map_err(|err| err.to_string()),
            #[cfg(test)]
            SpotFeed::Canned(feed) => feed.lock().expect("canned feed poisoned").next_rbn(),
        }
    }

    /// PSK Reporter reception reports for `callsign`. `Err(None)` is a soft
    /// rate-limit back-off (not a connectivity failure — matches the Swift
    /// `PSKReporterError.rateLimited` branch); `Err(Some(msg))` is a real
    /// failure.
    async fn fetch_pskr(&self, callsign: &str) -> Result<Vec<PskReporterSpot>, Option<String>> {
        match self {
            SpotFeed::Net { pskr, .. } => {
                match pskr.fetch_sender_spots(callsign, PSKR_LOOKBACK_SECS).await {
                    Ok(spots) => Ok(spots),
                    // A rate-limit is a soft back-off, not a connectivity gap —
                    // the Swift `pollPSKROnce` treats
                    // `PSKReporterError.rateLimited` separately from
                    // `handleSourceFailure`.
                    Err(cw_net::HttpError::RateLimited) => Err(None),
                    Err(err) => Err(Some(err.to_string())),
                }
            }
            #[cfg(test)]
            SpotFeed::Canned(feed) => feed.lock().expect("canned feed poisoned").next_pskr(),
        }
    }
}

/// Grid enrichment source. `Store` reads the `callbook_location` cache and fills
/// misses via the QRZ→HamDB locate flow; `Canned` (tests only) injects a fixed
/// `base callsign → grid` map so enrichment math is verified without I/O.
enum GridResolver {
    Store { store: Arc<FieldStore>, qrz: Arc<QrzApi> },
    #[cfg(test)]
    Canned(HashMap<String, String>),
}

impl GridResolver {
    /// Resolve grids for `base_callsigns` (already suffix-stripped, uppercased,
    /// deduped). Returns `base → grid` for the ones that resolved. Misses are
    /// simply absent (retried next pass).
    async fn resolve_grids(&self, base_callsigns: &[String]) -> HashMap<String, String> {
        if base_callsigns.is_empty() {
            return HashMap::new();
        }
        match self {
            GridResolver::Store { store, qrz } => {
                Self::resolve_via_store(store, qrz, base_callsigns).await
            }
            #[cfg(test)]
            GridResolver::Canned(map) => base_callsigns
                .iter()
                .filter_map(|base| map.get(base).map(|grid| (base.clone(), grid.clone())))
                .collect(),
        }
    }

    /// `callbook_location` cache read-through, then the QRZ → HamDB merge the
    /// locate flow uses (via [`QrzApi::locate`], which writes hits back to the
    /// cache so a later session reuses them).
    async fn resolve_via_store(
        store: &Arc<FieldStore>,
        qrz: &Arc<QrzApi>,
        base_callsigns: &[String],
    ) -> HashMap<String, String> {
        let now = now_secs();

        // 1. Cache read (30-day TTL) — a hit with a grid resolves immediately.
        let cached = {
            let inner = store.inner.lock().expect("store mutex poisoned");
            inner
                .fetch_callbook_locations(base_callsigns, now, LOCATION_TTL_SECS)
                .unwrap_or_default()
        };
        let mut resolved: HashMap<String, String> = HashMap::new();
        for loc in &cached {
            if let Some(grid) = &loc.grid {
                resolved.insert(loc.callsign.to_uppercase(), grid.clone());
            }
        }

        // 2. Misses go to the network locate flow (QRZ → HamDB), capped at
        //    MAX_ENRICH_LOOKUPS to match the Swift enrichment budget.
        let misses: Vec<String> = base_callsigns
            .iter()
            .filter(|call| !resolved.contains_key(*call))
            .take(MAX_ENRICH_LOOKUPS)
            .cloned()
            .collect();
        if misses.is_empty() {
            return resolved;
        }
        // `QrzApi::locate` already read-throughs + writes back the cache; it
        // returns `FfiCallsignLocation`s carrying the resolved grid.
        if let Ok(locations) = qrz.locate(misses).await {
            for location in locations {
                if let Some(grid) = location.grid {
                    resolved.insert(location.callsign.to_uppercase(), grid);
                }
            }
        }
        resolved
    }
}

// ---------------------------------------------------------------------------
// Session state
// ---------------------------------------------------------------------------

/// The live, mutation-owning session state, guarded by the object's `Mutex`.
struct SessionState {
    config: FfiPropagationConfig,
    /// Ordered spots (insertion order preserved, like the Swift `[spots]`).
    spots: Vec<FfiPropagationSpot>,
    /// Per-session dedup keys (`PropagationCheck.dedupKey`).
    seen: HashSet<String>,
    is_running: bool,
    started_at_epoch: f64,
    ended_at_epoch: Option<f64>,
    rbn_connected: bool,
    pskr_connected: bool,
    last_error: Option<String>,
    /// Last PSK Reporter poll time (epoch secs) — enforces the 5-min floor.
    last_pskr_poll: Option<f64>,
    /// Cached enriched grids (`base callsign → grid`), accumulated across polls.
    enriched_grids: HashMap<String, String>,
    /// Open RBN gap start (epoch secs), if RBN is currently down. Port of the
    /// Swift `currentRBNGapStart` — set on the first failed RBN fetch, cleared
    /// (and pushed to `connectivity_gaps`) on reconnect or in `stop()`.
    current_rbn_gap_start: Option<f64>,
    /// Open PSK Reporter gap start (epoch secs). Port of the Swift
    /// `currentPSKRGapStart`.
    current_pskr_gap_start: Option<f64>,
    /// Closed connectivity gaps, in the order they closed. Port of the Swift
    /// `connectivityGaps`.
    connectivity_gaps: Vec<FfiPropagationConnectivityGap>,
    /// Host-supplied solar snapshot, frozen at start. Port of `recordedSolar`
    /// (host does the fetch + `autoRecordConditions` gate; see the config doc).
    solar: Option<FfiPropagationSolar>,
    /// Why the session stopped. Port of the Swift `stopReason` — defaults to
    /// `.user` until `stop(reason:)` overwrites it.
    stop_reason: FfiPropagationStopReason,
}

/// Async propagation-check session engine bound to a [`FieldStore`] + the
/// activities-server base URL. State lives inside the object behind a `Mutex`
/// (the `spot_engine` pattern); async fetch/enrichment happens outside the lock.
#[derive(uniffi::Object)]
pub struct PropagationApi {
    session: StdMutex<Option<SessionState>>,
    feed: SpotFeed,
    resolver: GridResolver,
}

#[uniffi::export]
impl PropagationApi {
    /// Build a network-backed API. `base_url` is the activities-server base
    /// (same URL the other net APIs take); `qrz` supplies the callbook locate
    /// flow used to fill missing skimmer grids.
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>, qrz: Arc<QrzApi>, base_url: String) -> Result<Self, CwError> {
        let http = HttpClient::new()?;
        let feed = SpotFeed::Net {
            rbn: RbnClient::new(http.clone(), base_url),
            // App-contact mirrors the iOS `PSKReporterClient` default.
            pskr: PskReporterClient::new(http, "carrierwave-app@example.com"),
        };
        let resolver = GridResolver::Store { store, qrz };
        Ok(PropagationApi {
            session: StdMutex::new(None),
            feed,
            resolver,
        })
    }

    /// Freeze `config` and (re)start the session, clearing prior spots / dedup
    /// keys / connectivity state. Port of `PropagationCheckSession.start`.
    pub fn start_session(&self, config: FfiPropagationConfig) -> Result<(), CwError> {
        let mut guard = self.session.lock().expect("propagation session mutex poisoned");
        // Solar is host-supplied on the config and frozen onto the session (the
        // Swift `recordedSolar`); the config's own copy is retained too so
        // `results()` can thread it through.
        let solar = config.solar.clone();
        *guard = Some(SessionState {
            started_at_epoch: config.started_at_epoch,
            config,
            spots: Vec::new(),
            seen: HashSet::new(),
            is_running: true,
            ended_at_epoch: None,
            rbn_connected: true,
            pskr_connected: true,
            last_error: None,
            last_pskr_poll: None,
            enriched_grids: HashMap::new(),
            current_rbn_gap_start: None,
            current_pskr_gap_start: None,
            connectivity_gaps: Vec::new(),
            solar,
            stop_reason: FfiPropagationStopReason::User,
        });
        Ok(())
    }

    /// Mark the session stopped (idempotent). Ingested spots are retained so
    /// [`Self::results`] can still finalize. `reason` is stamped onto the
    /// results. Port of `PropagationCheckSession.stop(reason:)` — including its
    /// open-gap close: any RBN / PSK Reporter gap still open at teardown is
    /// closed at the stop time and pushed to `connectivity_gaps` (Swift
    /// :217-233).
    pub fn stop(&self, reason: FfiPropagationStopReason) -> Result<(), CwError> {
        let mut guard = self.session.lock().expect("propagation session mutex poisoned");
        if let Some(state) = guard.as_mut() {
            if state.is_running {
                let end_time = now_secs() as f64;
                state.is_running = false;
                state.ended_at_epoch = Some(end_time);
                state.stop_reason = reason;
                // Close any gap still open at teardown (Swift `stop` :217-233).
                close_gap(&mut state.current_rbn_gap_start, SOURCE_RBN, end_time, &mut state.connectivity_gaps);
                close_gap(&mut state.current_pskr_gap_start, SOURCE_PSKR, end_time, &mut state.connectivity_gaps);
            }
        }
        Ok(())
    }

    /// Finalized results snapshot: the full (un-windowed) spot list, its
    /// enriched projection, and the headline totals. Errors if no session was
    /// ever started.
    pub fn results(&self) -> Result<FfiPropagationResults, CwError> {
        let guard = self.session.lock().expect("propagation session mutex poisoned");
        let state = guard
            .as_ref()
            .ok_or_else(|| CwError::Store { reason: "no propagation session started".into() })?;
        let enriched = project_spots(&state.spots, &state.config.user_grid, &state.enriched_grids);
        let headline = compute_headline(&state.spots, &state.config.user_grid);
        Ok(FfiPropagationResults {
            callsign: state.config.callsign.clone(),
            user_grid: state.config.user_grid.clone(),
            bands_requested: state.config.bands.clone(),
            started_at_epoch: state.started_at_epoch,
            ended_at_epoch: state.ended_at_epoch.unwrap_or_else(|| now_secs() as f64),
            spots: state.spots.clone(),
            enriched_spots: enriched,
            total_spots: headline.total_spots,
            unique_skimmers: headline.unique_skimmers,
            bands_with_activity: headline.bands_with_activity,
            max_distance_km: headline.max_distance_km,
            peak_snr_db: headline.peak_snr_db,
            connectivity_gaps: state.connectivity_gaps.clone(),
            solar: state.solar.clone(),
            stop_reason: state.stop_reason,
        })
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl PropagationApi {
    /// Run one poll round (RBN + rate-limited PSK Reporter), ingest / dedup /
    /// window / enrich, and return the live [`FfiPropagationState`]. A single
    /// call maps to one iteration of the Swift `pollLoop` body. Errors only if
    /// no session is active.
    pub async fn poll(&self) -> Result<FfiPropagationState, CwError> {
        // Snapshot the bits the fetches need without holding the lock across
        // `.await` (the store/network work must not block other callers).
        let (callsign, bands, should_poll_pskr) = {
            let guard = self.session.lock().expect("propagation session mutex poisoned");
            let state = guard
                .as_ref()
                .ok_or_else(|| CwError::Store { reason: "no propagation session started".into() })?;
            if !state.is_running {
                // Stopped session: return the current snapshot, no fetch.
                return Ok(build_state(state));
            }
            let should_poll_pskr = pskr_due(state.last_pskr_poll, now_secs() as f64);
            (state.config.callsign.clone(), state.config.bands.clone(), should_poll_pskr)
        };

        // --- RBN fetch (every poll) ---
        let rbn_result = self.feed.fetch_rbn(&callsign).await;
        // --- PSK Reporter fetch (rate-limited to the 5-min floor) ---
        let pskr_result = if should_poll_pskr {
            Some(self.feed.fetch_pskr(&callsign).await)
        } else {
            None
        };

        // Ingest under the lock, then compute the missing-grid set for
        // enrichment (which needs another await, so it's done after unlocking).
        let missing_bases = {
            let mut guard = self.session.lock().expect("propagation session mutex poisoned");
            let Some(state) = guard.as_mut() else {
                return Err(CwError::Store { reason: "no propagation session started".into() });
            };

            match rbn_result {
                Ok(spots) => {
                    // Reconnect: close an open RBN gap (Swift `pollRBNOnce`
                    // :45-52). A successful fetch — even an empty one — closes it.
                    close_gap(
                        &mut state.current_rbn_gap_start,
                        SOURCE_RBN,
                        now_secs() as f64,
                        &mut state.connectivity_gaps,
                    );
                    state.rbn_connected = true;
                    for spot in spots {
                        if let Some(entry) = rbn_to_entry(&spot, &state.config, &bands) {
                            commit(state, entry);
                        }
                    }
                }
                Err(reason) => {
                    // Open a gap on the first failed RBN fetch (Swift
                    // `handleSourceFailure(.rbn)` :168-172).
                    open_gap(&mut state.current_rbn_gap_start, now_secs() as f64);
                    state.rbn_connected = false;
                    state.last_error = Some(format!("{}: {reason}", SOURCE_RBN));
                }
            }

            if let Some(pskr_result) = pskr_result {
                match pskr_result {
                    Ok(spots) => {
                        state.last_pskr_poll = Some(now_secs() as f64);
                        // Reconnect: close an open PSKR gap (Swift `pollPSKROnce`
                        // :77-84).
                        close_gap(
                            &mut state.current_pskr_gap_start,
                            SOURCE_PSKR,
                            now_secs() as f64,
                            &mut state.connectivity_gaps,
                        );
                        state.pskr_connected = true;
                        for spot in spots {
                            if let Some(entry) = pskr_to_entry(&spot, &state.config, &bands) {
                                commit(state, entry);
                            }
                        }
                    }
                    // Soft rate-limit: record the attempt so we honor the floor,
                    // but don't flag a connectivity gap (Swift parity —
                    // `pollPSKROnce` :91-93 treats `.rateLimited` separately from
                    // `handleSourceFailure`, so no gap opens/closes).
                    Err(None) => {
                        state.last_pskr_poll = Some(now_secs() as f64);
                    }
                    Err(Some(reason)) => {
                        // Open a gap on the first hard PSKR failure (Swift
                        // `handleSourceFailure(.pskr)` :173-177).
                        open_gap(&mut state.current_pskr_gap_start, now_secs() as f64);
                        state.pskr_connected = false;
                        state.last_error = Some(format!("{}: {reason}", SOURCE_PSKR));
                    }
                }
            }

            missing_grid_bases(state)
        };

        // --- Enrichment (outside the lock) ---
        if !missing_bases.is_empty() {
            let resolved = self.resolver.resolve_grids(&missing_bases).await;
            let mut guard = self.session.lock().expect("propagation session mutex poisoned");
            if let Some(state) = guard.as_mut() {
                for (base, grid) in resolved {
                    state.enriched_grids.insert(base, grid);
                }
            }
        }

        let guard = self.session.lock().expect("propagation session mutex poisoned");
        let state = guard
            .as_ref()
            .ok_or_else(|| CwError::Store { reason: "no propagation session started".into() })?;
        Ok(build_state(state))
    }
}

// ---------------------------------------------------------------------------
// Ingestion — ports of PropagationCheckSession+Polling.{ingestRBN,ingestPSKR,commit}
// ---------------------------------------------------------------------------

/// Suffix-tolerant callsign match: `^<base>(/[A-Z0-9]+)?$`, case-insensitive.
/// Port of `PropagationCheckConfig.matches` — catches `/P`, `/M`, `/QRP`, …
pub fn callsign_matches(base: &str, candidate: &str) -> bool {
    let trimmed = candidate.trim().to_uppercase();
    let base = base.trim().to_uppercase();
    if trimmed == base {
        return true;
    }
    let prefix = format!("{base}/");
    if let Some(suffix) = trimmed.strip_prefix(&prefix) {
        return !suffix.is_empty() && suffix.chars().all(|ch| ch.is_ascii_alphanumeric());
    }
    false
}

/// Dedup key for a spot. Port of `PropagationCheck.dedupKey` —
/// `source-CALL-freqHz-secondBucket`.
fn dedup_key(entry: &FfiPropagationSpot) -> String {
    let second_bucket = entry.timestamp_epoch as i64;
    format!("{}-{}-{}-{}", entry.source, entry.skimmer_call.to_uppercase(), entry.freq_hz, second_bucket)
}

/// Convert an RBN spot to an entry, applying the callsign + band filters. Port
/// of `ingestRBN`. RBN frequency is kHz; `freqHz = frequency * 1000`.
fn rbn_to_entry(
    spot: &RbnSpot,
    config: &FfiPropagationConfig,
    bands: &[String],
) -> Option<FfiPropagationSpot> {
    if !callsign_matches(&config.callsign, &spot.callsign) {
        return None;
    }
    let band = BandUtilities::derive_band(Some(spot.frequency)).unwrap_or("").to_string();
    if !bands.is_empty() && !bands.iter().any(|b| b == &band) {
        return None;
    }
    Some(FfiPropagationSpot {
        source: SOURCE_RBN.to_string(),
        skimmer_call: spot.spotter.clone(),
        skimmer_grid: spot.spotter_grid.clone(),
        freq_hz: (spot.frequency * 1_000.0) as i64,
        band: if band.is_empty() { None } else { Some(band) },
        mode: spot.mode.clone(),
        snr_db: Some(spot.snr as f64),
        timestamp_epoch: spot.timestamp_epoch_seconds().unwrap_or(0.0),
    })
}

/// Convert a PSK Reporter spot to an entry, applying the filters. Port of
/// `ingestPSKR`. PSKR frequency is already Hz; band is derived from kHz.
fn pskr_to_entry(
    spot: &PskReporterSpot,
    config: &FfiPropagationConfig,
    bands: &[String],
) -> Option<FfiPropagationSpot> {
    if !callsign_matches(&config.callsign, &spot.sender_callsign) {
        return None;
    }
    let band = BandUtilities::derive_band(Some(spot.frequency_khz())).unwrap_or("").to_string();
    if !bands.is_empty() && !bands.iter().any(|b| b == &band) {
        return None;
    }
    Some(FfiPropagationSpot {
        source: SOURCE_PSKR.to_string(),
        skimmer_call: spot.receiver_callsign.clone(),
        skimmer_grid: spot.receiver_locator.clone(),
        freq_hz: spot.frequency,
        band: if band.is_empty() { None } else { Some(band) },
        mode: spot.mode.clone(),
        snr_db: spot.snr.map(f64::from),
        timestamp_epoch: spot.flow_start_seconds as f64,
    })
}

/// Insert an entry iff its dedup key is new. Port of `commit`.
fn commit(state: &mut SessionState, entry: FfiPropagationSpot) {
    let key = dedup_key(&entry);
    if state.seen.insert(key) {
        state.spots.push(entry);
    }
}

// ---------------------------------------------------------------------------
// Connectivity-gap state machine — port of the Swift gap logic in
// PropagationCheckSession.{handleSourceFailure,stop} and +Polling.{pollRBNOnce,
// pollPSKROnce}. A gap opens on the FIRST failed fetch of a source (subsequent
// consecutive failures don't move the start), and closes on the next successful
// fetch of that source (or in stop() if still open).
// ---------------------------------------------------------------------------

/// Open a gap at `now` iff one isn't already open (Swift `handleSourceFailure`:
/// `if currentXGapStart == nil { currentXGapStart = now }`).
fn open_gap(current_start: &mut Option<f64>, now: f64) {
    if current_start.is_none() {
        *current_start = Some(now);
    }
}

/// Close an open gap for `source` at `end`, pushing it onto `gaps`; no-op if no
/// gap is open. Port of the reconnect branch (`pollRBNOnce` :45-52 /
/// `pollPSKROnce` :77-84) and the `stop()` teardown close (:217-233).
fn close_gap(current_start: &mut Option<f64>, source: &str, end: f64, gaps: &mut Vec<FfiPropagationConnectivityGap>) {
    if let Some(start) = current_start.take() {
        gaps.push(FfiPropagationConnectivityGap {
            source: source.to_string(),
            started_at_epoch: start,
            ended_at_epoch: end,
        });
    }
}

// ---------------------------------------------------------------------------
// Enrichment — port of PropagationCheckEnrichment
// ---------------------------------------------------------------------------

/// Strip an RBN skimmer hyphen-suffix (`"AK6RI-1-#"` → `"AK6RI"`) and uppercase.
/// Port of `PropagationCheckEnrichment.baseSkimmerCallsign`.
pub fn base_skimmer_callsign(spotter: &str) -> String {
    let upper = spotter.to_uppercase();
    match upper.find('-') {
        Some(idx) => upper[..idx].to_string(),
        None => upper,
    }
}

/// Ordered, deduped base callsigns whose spots lack a reported grid AND aren't
/// already enriched. Port of `uniqueBaseCallsignsMissingGrid`, extended to skip
/// bases we already resolved so re-enrichment budget isn't wasted.
fn missing_grid_bases(state: &SessionState) -> Vec<String> {
    let mut seen: HashSet<String> = HashSet::new();
    let mut ordered: Vec<String> = Vec::new();
    for spot in &state.spots {
        if spot.skimmer_grid.is_some() {
            continue;
        }
        let base = base_skimmer_callsign(&spot.skimmer_call);
        if base.is_empty() || state.enriched_grids.contains_key(&base) || !seen.insert(base.clone()) {
            continue;
        }
        ordered.push(base);
    }
    ordered
}

/// Project spots to coordinate / distance / bearing using the operator's grid
/// and the enriched-grid fallback. Spots with no resolvable grid keep
/// `latitude/longitude == None` (kept in the list, not dropped). Port of
/// `PropagationCheckEnrichment.project`.
fn project_spots(
    spots: &[FfiPropagationSpot],
    user_grid: &str,
    enriched: &HashMap<String, String>,
) -> Vec<FfiPropagationEnrichedSpot> {
    let user_coord = maidenhead::coordinate_from_grid(user_grid);
    spots
        .iter()
        .map(|entry| {
            let effective_grid = entry
                .skimmer_grid
                .clone()
                .or_else(|| enriched.get(&base_skimmer_callsign(&entry.skimmer_call)).cloned());
            let coord = effective_grid.as_deref().and_then(maidenhead::coordinate_from_grid);
            let (mut distance_km, mut bearing) = (None, None);
            if let (Some(grid), Some(_)) = (effective_grid.as_deref(), user_coord.as_ref()) {
                distance_km = maidenhead::distance_km(user_grid, grid);
                bearing = maidenhead::bearing(user_grid, grid);
            }
            FfiPropagationEnrichedSpot {
                id: dedup_key(entry),
                spot: entry.clone(),
                effective_grid,
                latitude: coord.as_ref().map(|c| c.latitude),
                longitude: coord.as_ref().map(|c| c.longitude),
                distance_km,
                bearing,
            }
        })
        .collect()
}

// ---------------------------------------------------------------------------
// Headline stats — port of PropagationCheckSession's computed properties
// ---------------------------------------------------------------------------

struct Headline {
    total_spots: i64,
    unique_skimmers: i64,
    bands_with_activity: Vec<String>,
    max_distance_km: f64,
    peak_snr_db: f64,
}

/// Compute the headline stats. Port of `totalSpots` / `uniqueSkimmers` /
/// `bandsWithActivity` / `maxDistanceKm` / `peakSNRdB`. `maxDistanceKm` uses
/// the spot's own reported grid only (matching the Swift computed property,
/// which reads `spot.skimmerGrid`, not the enriched fallback).
fn compute_headline(spots: &[FfiPropagationSpot], user_grid: &str) -> Headline {
    let total = spots.len() as i64;
    let unique = spots.iter().map(|s| s.skimmer_call.to_uppercase()).collect::<HashSet<_>>().len() as i64;
    let bands: Vec<String> = spots
        .iter()
        .filter_map(|s| s.band.clone())
        .collect::<HashSet<_>>()
        .into_iter()
        .collect();
    let max_dist = spots
        .iter()
        .filter_map(|s| {
            s.skimmer_grid.as_deref().and_then(|grid| maidenhead::distance_km(user_grid, grid))
        })
        .fold(0.0_f64, f64::max);
    let peak_snr = spots.iter().filter_map(|s| s.snr_db).fold(f64::NEG_INFINITY, f64::max);
    Headline {
        total_spots: total,
        unique_skimmers: unique,
        bands_with_activity: bands,
        max_distance_km: max_dist,
        peak_snr_db: if peak_snr.is_finite() { peak_snr } else { 0.0 },
    }
}

/// Build the live state snapshot from the session. Enriched spots are projected
/// with the grids accumulated so far.
fn build_state(state: &SessionState) -> FfiPropagationState {
    let enriched = project_spots(&state.spots, &state.config.user_grid, &state.enriched_grids);
    let headline = compute_headline(&state.spots, &state.config.user_grid);
    FfiPropagationState {
        is_running: state.is_running,
        enriched_spots: enriched,
        total_spots: headline.total_spots,
        unique_skimmers: headline.unique_skimmers,
        bands_with_activity: headline.bands_with_activity,
        max_distance_km: headline.max_distance_km,
        peak_snr_db: headline.peak_snr_db,
        rbn_connected: state.rbn_connected,
        pskr_connected: state.pskr_connected,
        last_error: state.last_error.clone(),
    }
}

/// Whether a PSK Reporter poll is due, honoring the 5-min floor minus a 5s slop
/// (the Swift `pollPSKROnce` guard: `< pskrPollInterval - 5`).
fn pskr_due(last_poll: Option<f64>, now: f64) -> bool {
    match last_poll {
        None => true,
        Some(last) => now - last >= PSKR_POLL_INTERVAL_SECS - 5.0,
    }
}

fn now_secs() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

/// The ported poll cadences, in seconds, so the host schedules `poll()` at the
/// same intervals the Swift `PropagationCheckSession.pollLoop` used (RBN every
/// 30s, PSK Reporter every 305s). The PSK Reporter floor is also enforced
/// inside [`PropagationApi::poll`]; this just lets the host avoid busy-polling.
#[derive(uniffi::Record)]
pub struct FfiPropagationCadence {
    pub rbn_interval_secs: f64,
    pub pskr_interval_secs: f64,
}

/// Return the ported RBN + PSK Reporter poll cadences.
#[uniffi::export]
pub fn propagation_poll_cadence() -> FfiPropagationCadence {
    FfiPropagationCadence {
        rbn_interval_secs: RBN_POLL_INTERVAL_SECS,
        pskr_interval_secs: PSKR_POLL_INTERVAL_SECS,
    }
}

#[cfg(test)]
mod tests;
