//! Shared satellite tracking surface: SatNOGS/AMSAT cache-through refresh,
//! catalog + live positions, pass forecasts, mutual planning, and alert
//! planning. The engine is `cw_domain::satellite` (sgp4 + the SatelliteKit-
//! parity conversion layer); this object owns the built catalog behind a
//! mutex and the cache-through policy against `cw-store::satellite_cache`
//! (6 h TTL, degrade-to-stale on network failure, AMSAT soft-fail → empty).
//!
//! No session/listener machinery: the 1–5 s position tick is a stateless
//! sync `positions()` call the host's own loop drives (time scrubbing =
//! pass `now + offset` as the epoch). Hosts keep favorites; APIs that need
//! them take `favorites` as a parameter.

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::Mutex as StdMutex;

use chrono::{DateTime, TimeZone, Utc};

use cw_domain::satellite::alert_planner;
use cw_domain::satellite::amsat::{freshest, AmsatStatus};
use cw_domain::satellite::catalog::{build_ham_satellites, Catalog};
use cw_domain::satellite::display_name;
use cw_domain::satellite::doppler_schedule;
use cw_domain::satellite::mutual;
use cw_domain::satellite::pass_predictor::{self, UpcomingPass};
use cw_domain::satellite::polarization::Polarization;
use cw_domain::satellite::tracker;
use cw_domain::satellite::{Observer, SatTle, SatTransmitter};
use cw_net::{
    AmsatReportSubmission, AmsatStatusClient, AmsatSubmitClient, AmsatSubmitError, HttpClient,
    SatnogsClient, SatnogsSatellite, SatnogsTle, SatnogsTransmitter, AMSAT_ATTRIBUTION,
    AMSAT_REPORT_VALUES, AMSAT_STATUS_API_BASE,
};
use cw_store::satellite_cache::SATELLITE_CACHE_TTL_SECS;

use crate::{CwError, FieldStore};

mod records;
#[cfg(test)]
mod tests;

pub use records::*;

const KIND_TLE: &str = "tle";
const KIND_TRANSMITTERS: &str = "transmitters";
const KIND_AMSAT: &str = "amsat";
const KIND_SATELLITES: &str = "satnogs_satellites";
const KIND_AMSAT_ACTIVITY: &str = "amsat_activity";
/// The activity grid changes every aggregator cycle (30 min server-side),
/// so it gets a much shorter TTL than the 6 h orbital data.
const AMSAT_ACTIVITY_TTL_SECS: i64 = 20 * 60;
/// Activity window requested from the server (its maximum).
const AMSAT_ACTIVITY_HOURS: u32 = 168;
/// Per-bird raw reports: cache kind prefix, window, and TTL.
const KIND_AMSAT_REPORTS_PREFIX: &str = "amsat_reports:";
const AMSAT_REPORTS_HOURS: u32 = 24;
const AMSAT_REPORTS_TTL_SECS: i64 = 10 * 60;
const PREVIOUS_ORBIT_MAX_CALLSIGNS: usize = 6;
/// How far ahead `community_activity` looks for each bird's next pass.
const NEXT_PASS_HOURS: f64 = 24.0;
/// Whole-request budget for the SatNOGS bulk downloads. The transmitter list
/// is ~4 MB served at ~240 KB/s with no compression (17–20 s on a wired
/// desktop), so the 20 s default timed it out on phones and the refresh
/// never completed.
const SATNOGS_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(120);
/// After a failed fetch, serve the stale cached payload without touching the
/// network for this long (non-forced calls only). Without it every open past
/// the TTL re-ran the slow download and waited out the timeout again,
/// because a failed fetch never advances the cached `fetched_at`.
const FETCH_FAILURE_BACKOFF_SECS: i64 = 15 * 60;

/// The built catalog plus everything derived from one refresh.
struct CatalogState {
    catalog: Catalog,
    /// Freshest row per bird — the satellite-level summary fields.
    amsat_by_norad: HashMap<u32, AmsatStatus>,
    /// Every capability row per bird — the per-transmitter heard signal.
    amsat_rows_by_norad: HashMap<u32, Vec<AmsatStatus>>,
    /// Every AMSAT row by its internal name, including birds the server
    /// couldn't map to a NORAD id — the community-activity grid shows
    /// AMSAT's whole list, mapped or not.
    amsat_rows_by_name: HashMap<String, AmsatStatus>,
    tles_fetched_at: i64,
    tles_stale: bool,
    amsat_available: bool,
}

/// Data source, factored so tests replay canned payloads with no network
/// (the `propagation_api::SpotFeed` pattern).
#[cfg_attr(test, allow(clippy::large_enum_variant))]
enum SatFeed {
    Live { satnogs: SatnogsClient, amsat: AmsatStatusClient, amsat_submit: AmsatSubmitClient },
    #[cfg(test)]
    Canned(StdMutex<tests::CannedFeed>),
}

impl SatFeed {
    async fn fetch_tles(&self) -> Result<Vec<SatnogsTle>, CwError> {
        match self {
            SatFeed::Live { satnogs, .. } => Ok(satnogs.fetch_tles().await?),
            #[cfg(test)]
            SatFeed::Canned(feed) => {
                // Optional scripted latency so tests can overlap refreshes.
                let delay = feed.lock().expect("canned feed").tle_delay;
                if !delay.is_zero() {
                    tokio::time::sleep(delay).await;
                }
                feed.lock().expect("canned feed").next_tles()
            }
        }
    }

    async fn fetch_transmitters(&self) -> Result<Vec<SatnogsTransmitter>, CwError> {
        match self {
            SatFeed::Live { satnogs, .. } => Ok(satnogs.fetch_transmitters().await?),
            #[cfg(test)]
            SatFeed::Canned(feed) => feed.lock().expect("canned feed").next_transmitters(),
        }
    }

    async fn fetch_satellites(&self) -> Result<Vec<SatnogsSatellite>, CwError> {
        match self {
            SatFeed::Live { satnogs, .. } => Ok(satnogs.fetch_satellites().await?),
            #[cfg(test)]
            SatFeed::Canned(feed) => feed.lock().expect("canned feed").next_satellites(),
        }
    }

    async fn fetch_amsat(&self) -> Result<Vec<cw_net::AmsatStatusRow>, CwError> {
        match self {
            SatFeed::Live { amsat, .. } => Ok(amsat.fetch_status().await?.satellites),
            #[cfg(test)]
            SatFeed::Canned(feed) => feed.lock().expect("canned feed").next_amsat(),
        }
    }

    async fn fetch_reports(&self, norad_id: u32) -> Result<cw_net::AmsatReportsResponse, CwError> {
        match self {
            SatFeed::Live { amsat, .. } => Ok(amsat.fetch_reports(norad_id, AMSAT_REPORTS_HOURS).await?),
            #[cfg(test)]
            SatFeed::Canned(feed) => feed.lock().expect("canned feed").next_reports(),
        }
    }

    async fn fetch_activity(&self) -> Result<cw_net::AmsatActivityResponse, CwError> {
        match self {
            SatFeed::Live { amsat, .. } => Ok(amsat.fetch_activity(AMSAT_ACTIVITY_HOURS).await?),
            #[cfg(test)]
            SatFeed::Canned(feed) => feed.lock().expect("canned feed").next_activity(),
        }
    }

    async fn submit_report(
        &self,
        submission: &AmsatReportSubmission,
    ) -> Result<cw_net::AmsatSubmitReceipt, CwError> {
        match self {
            SatFeed::Live { amsat_submit, .. } => {
                amsat_submit.submit_report(submission).await.map_err(|e| match e {
                    // AMSAT's own reason ("A valid amateur radio callsign is
                    // required.") is what the operator should read.
                    AmsatSubmitError::Rejected { message, .. } => CwError::Network { reason: message },
                    AmsatSubmitError::Http(http) => http.into(),
                })
            }
            #[cfg(test)]
            SatFeed::Canned(feed) => feed.lock().expect("canned feed").next_submission(submission),
        }
    }
}

/// The verdicts AMSAT accepts in a status report, in their display order.
#[uniffi::export]
pub fn amsat_report_values() -> Vec<String> {
    AMSAT_REPORT_VALUES.iter().map(|value| value.to_string()).collect()
}

/// The attribution AMSAT asks for wherever its report data is shown.
#[uniffi::export]
pub fn amsat_attribution() -> String {
    AMSAT_ATTRIBUTION.to_string()
}

/// Canonical AMSAT verdict for a host-supplied value ("not heard" →
/// "Not Heard"); None when it isn't one AMSAT accepts.
fn canonical_report_value(report: &str) -> Option<&'static str> {
    let wanted = report.split_whitespace().collect::<Vec<_>>().join(" ");
    AMSAT_REPORT_VALUES
        .iter()
        .copied()
        .find(|value| value.eq_ignore_ascii_case(&wanted))
}

#[derive(uniffi::Object)]
pub struct SatelliteApi {
    store: Arc<FieldStore>,
    feed: SatFeed,
    state: StdMutex<Option<Arc<CatalogState>>>,
    /// Single-flight gate for `refresh`: a second caller (the tab opening
    /// while the alert scheduler refreshes) waits for the in-flight refresh
    /// and then reads its freshly cached result instead of starting a second
    /// download from the same throttled server.
    refresh_gate: tokio::sync::Mutex<()>,
    /// Bumped by every `refresh` that fetched fresh TLEs. A forced caller that
    /// waited on the gate while one completed skips its own download.
    refresh_generation: std::sync::atomic::AtomicU64,
    /// Unix seconds of the last failed network fetch per cache kind
    /// ([`FETCH_FAILURE_BACKOFF_SECS`]). In-memory: a relaunch retries.
    fetch_failed_at: StdMutex<HashMap<String, i64>>,
}

impl SatelliteApi {
    fn with_feed(store: Arc<FieldStore>, feed: SatFeed) -> Self {
        SatelliteApi {
            store,
            feed,
            state: StdMutex::new(None),
            refresh_gate: tokio::sync::Mutex::new(()),
            refresh_generation: std::sync::atomic::AtomicU64::new(0),
            fetch_failed_at: StdMutex::new(HashMap::new()),
        }
    }
}

#[uniffi::export]
impl SatelliteApi {
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>, activities_base_url: String) -> Result<Self, CwError> {
        let http = HttpClient::new()
            .map_err(|e| CwError::Network { reason: e.to_string() })?;
        let satnogs_http = HttpClient::with_timeout(SATNOGS_TIMEOUT)
            .map_err(|e| CwError::Network { reason: e.to_string() })?;
        Ok(SatelliteApi::with_feed(
            store,
            SatFeed::Live {
                satnogs: SatnogsClient::new(satnogs_http),
                amsat: AmsatStatusClient::new(http.clone(), activities_base_url),
                amsat_submit: AmsatSubmitClient::new(http, AMSAT_STATUS_API_BASE),
            },
        ))
    }

    /// The workable catalog (empty until the first `refresh`).
    pub fn catalog(&self) -> Vec<FfiSatelliteSummary> {
        let Some(state) = self.current_state() else {
            return Vec::new();
        };
        state
            .catalog
            .satellites
            .iter()
            .map(|sat| {
                let rows = state
                    .amsat_rows_by_norad
                    .get(&sat.norad_id)
                    .map(Vec::as_slice)
                    .unwrap_or(&[]);
                let transmitters = state
                    .catalog
                    .transmitters_by_norad
                    .get(&sat.norad_id)
                    .map(|list| {
                        list.iter().map(|t| FfiSatTransmitter::with_amsat(t, rows)).collect()
                    })
                    .unwrap_or_default();
                let amsat = state.amsat_by_norad.get(&sat.norad_id);
                FfiSatelliteSummary {
                    norad_id: sat.norad_id,
                    name: sat.name.clone(),
                    detail_name: sat.detail_name.clone(),
                    transmitters,
                    polarization: Polarization::lookup(sat.norad_id)
                        .map(FfiSatPolarization::from),
                    amsat_last_heard_epoch: amsat
                        .and_then(|row| row.last_heard_at.map(|d| d.timestamp())),
                    amsat_last_report: amsat.and_then(|row| row.last_report.clone()),
                    amsat_last_callsign: amsat.and_then(|row| row.last_callsign.clone()),
                    amsat_last_grid: amsat.and_then(|row| row.last_grid.clone()),
                    amsat_heard_reports_24h: amsat.map_or(0, |row| row.heard_reports_24h),
                    amsat_total_reports_24h: amsat.map_or(0, |row| row.total_reports_24h),
                }
            })
            .collect()
    }

    /// Search entries, sorted case-insensitively by short name (the iOS
    /// `searchItems` sort).
    pub fn search_items(&self) -> Vec<FfiSatelliteSearchItem> {
        let Some(state) = self.current_state() else {
            return Vec::new();
        };
        let mut items: Vec<FfiSatelliteSearchItem> = state
            .catalog
            .satellites
            .iter()
            .map(|sat| FfiSatelliteSearchItem {
                norad_id: sat.norad_id,
                name: sat.name.clone(),
                detail_name: sat.detail_name.clone(),
            })
            .collect();
        items.sort_by_key(|item| item.name.to_lowercase());
        items
    }

    /// Propagate the whole catalog to `epoch_secs`. Pure CPU (single-digit
    /// milliseconds for a few hundred birds) — the host polls this from its
    /// own off-main loop; time scrubbing passes `now + offset`.
    pub fn positions(
        &self,
        epoch_secs: i64,
        observer: Option<FfiObserver>,
    ) -> Vec<FfiSatellitePosition> {
        let Some(state) = self.current_state() else {
            return Vec::new();
        };
        let at = epoch(epoch_secs);
        tracker::propagate_all(
            &state.catalog.satellites,
            at,
            observer.map(Observer::from),
        )
        .iter()
        .map(FfiSatellitePosition::from)
        .collect()
    }

    /// Ground track one orbital period forward from `epoch_secs` (30 s
    /// samples) — the map track and the sky-dome pass arc.
    pub fn ground_track(
        &self,
        norad_id: u32,
        epoch_secs: i64,
        observer: Option<FfiObserver>,
    ) -> Vec<FfiSatellitePosition> {
        let Some(state) = self.current_state() else {
            return Vec::new();
        };
        let Some(sat) =
            state.catalog.satellites.iter().find(|sat| sat.norad_id == norad_id)
        else {
            return Vec::new();
        };
        tracker::ground_track(sat, epoch(epoch_secs), observer.map(Observer::from))
            .iter()
            .map(FfiSatellitePosition::from)
            .collect()
    }

    /// One look sample for the pointing/sky-dome instruments, with rates and
    /// the Doppler factor (−ṙ/c; downlink × (1 + f), uplink × (1 − f)).
    pub fn look(
        &self,
        norad_id: u32,
        epoch_secs: i64,
        observer: FfiObserver,
    ) -> Option<FfiSatelliteLook> {
        let state = self.current_state()?;
        let sat = state.catalog.satellites.iter().find(|sat| sat.norad_id == norad_id)?;
        let positions =
            tracker::propagate_all(std::slice::from_ref(sat), epoch(epoch_secs), Some(observer.into()));
        let pos = positions.first()?;
        let (azimuth, elevation, range) =
            (pos.azimuth_deg?, pos.elevation_deg?, pos.range_km?);
        Some(FfiSatelliteLook {
            azimuth_deg: azimuth,
            elevation_deg: elevation,
            range_km: range,
            az_rate_deg_per_sec: pos.az_rate_deg_per_sec,
            el_rate_deg_per_sec: pos.el_rate_deg_per_sec,
            range_rate_km_per_sec: pos.range_rate_km_per_sec,
            doppler_factor: -pos.range_rate_km_per_sec / 299_792.458,
        })
    }

    /// Create the **born-completed** session the post-LOS quick log writes
    /// under (`status = "completed"`, `ended_at` set BEFORE any QSO is
    /// logged) — invisible to `fetch_current_session`, so a live activation
    /// is never paused. Returns the new session id (lowercase UUID) for
    /// `SessionApi.log_qso` calls; `log_qso` maintains `qso_count` itself.
    pub fn create_pass_session(&self, input: FfiPassSessionInput) -> Result<String, CwError> {
        let session = build_pass_session(&input);
        let id = session.id.clone();
        let inner = self.store.inner.lock().expect("store mutex poisoned");
        inner.upsert_logging_session(&session)?;
        Ok(id)
    }

    /// Build a bridge-ready doppler schedule for one pass + transponder:
    /// the shared `doppler_schedule` sampler (1 s cadence, per-link
    /// quantization, ≤60 s keepalives) packed into `SatScheduleChunk`-sized
    /// byte chunks via `cw-sat-core`. Pure CPU (~1 ms per pass minute).
    pub fn build_doppler_schedule(
        &self,
        input: FfiDopplerScheduleInput,
    ) -> Result<FfiDopplerSchedule, CwError> {
        let state = self.state_or_err()?;
        let sat = state
            .catalog
            .satellites
            .iter()
            .find(|sat| sat.norad_id == input.norad_id)
            .ok_or_else(|| CwError::Store { reason: "satellite not in catalog".to_string() })?;
        let params = doppler_schedule::DopplerScheduleParams {
            downlink_hz: input.downlink_hz,
            uplink_hz: input.uplink_hz,
            downlink_step_hz: input.downlink_step_hz,
            uplink_step_hz: input.uplink_step_hz,
        };
        let schedule = doppler_schedule::build(
            &sat.propagator,
            Observer::from(input.observer),
            epoch(input.aos_epoch),
            epoch(input.los_epoch),
            &params,
        )
        .ok_or_else(|| CwError::Store {
            reason: "doppler schedule build failed (empty window or propagation error)"
                .to_string(),
        })?;
        let packed = cw_sat_core::pack_steps(schedule.start, &schedule.steps)
            .map_err(|e| CwError::Store { reason: format!("schedule pack: {e:?}") })?;
        let chunk_bytes = cw_sat_core::STEPS_PER_CHUNK * cw_sat_core::STEP_BYTES;
        Ok(FfiDopplerSchedule {
            downlink_start_hz: schedule.start.downlink_hz,
            uplink_start_hz: schedule.start.uplink_hz,
            duration_ms: schedule.duration_ms,
            total_steps: schedule.steps.len() as u32,
            chunks: packed.chunks(chunk_bytes).map(<[u8]>::to_vec).collect(),
        })
    }

    /// Natural Earth 110m coastline polylines (lat, lon) for host-drawn
    /// charts — single source of truth with the share-map renderers.
    pub fn coastline_continents(&self) -> Vec<Vec<crate::FfiCoordinate>> {
        cw_domain::coastline::continents()
            .iter()
            .map(|polyline| {
                polyline
                    .iter()
                    .map(|(lat, lon)| crate::FfiCoordinate { latitude: *lat, longitude: *lon })
                    .collect()
            })
            .collect()
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl SatelliteApi {
    /// Cache-through refresh: TLEs + transmitters (6 h TTL, write-through,
    /// stale fallback when the network fails, error only when both fail) and
    /// the AMSAT aggregate (enrichment — failure degrades to empty). Builds
    /// the catalog off the runtime thread and swaps it in.
    ///
    /// Single-flight: concurrent calls run one at a time, so a caller that
    /// arrives mid-refresh waits and then hits the cache the first one just
    /// wrote. A forced call skips its own download when a refresh that
    /// fetched fresh TLEs completed while it waited. After a failed fetch the
    /// stale cache is served without network for 15 minutes unless forced.
    pub async fn refresh(&self, force: bool) -> Result<FfiSatelliteRefreshSummary, CwError> {
        use std::sync::atomic::Ordering;
        let generation_before = self.refresh_generation.load(Ordering::SeqCst);
        let _gate = self.refresh_gate.lock().await;
        let force = force && self.refresh_generation.load(Ordering::SeqCst) == generation_before;
        let now = Utc::now().timestamp();
        let (tles_json, tles_fetched_at, tles_stale) = self
            .cache_through(KIND_TLE, force, now, || async {
                serde_json::to_string(&self.feed.fetch_tles().await?)
                    .map_err(|e| CwError::Network { reason: e.to_string() })
            })
            .await?;
        let (transmitters_json, _, _) = self
            .cache_through(KIND_TRANSMITTERS, force, now, || async {
                serde_json::to_string(&self.feed.fetch_transmitters().await?)
                    .map_err(|e| CwError::Network { reason: e.to_string() })
            })
            .await?;
        let (amsat_json, amsat_available) = match self
            .cache_through(KIND_AMSAT, force, now, || async {
                serde_json::to_string(&self.feed.fetch_amsat().await?)
                    .map_err(|e| CwError::Network { reason: e.to_string() })
            })
            .await
        {
            Ok((json, _, _)) => (json, true),
            // Enrichment only — never load-bearing.
            Err(_) => ("[]".to_string(), false),
        };
        // Canonical names (fixes "OBJECT C" TLE placeholders) — enrichment
        // like AMSAT: a failure just leaves the TLE names.
        let satellites_json = self
            .cache_through(KIND_SATELLITES, force, now, || async {
                serde_json::to_string(&self.feed.fetch_satellites().await?)
                    .map_err(|e| CwError::Network { reason: e.to_string() })
            })
            .await
            .map(|(json, _, _)| json)
            .unwrap_or_else(|_| "[]".to_string());

        let state = tokio::task::spawn_blocking(move || {
            build_state(
                &tles_json,
                &transmitters_json,
                &amsat_json,
                &satellites_json,
                tles_fetched_at,
                tles_stale,
                amsat_available,
            )
        })
        .await
        .map_err(|e| CwError::Store { reason: e.to_string() })??;

        if tles_fetched_at == now && !tles_stale {
            self.refresh_generation.fetch_add(1, Ordering::SeqCst);
        }
        Ok(self.install_state(state, false))
    }

    /// Build the catalog from whatever is cached, however old, without
    /// touching the network — so a host can show satellites immediately and
    /// run `refresh` in the background. `None` when TLEs or transmitters were
    /// never cached (first launch): the host must `refresh`. `tles_stale` is
    /// true when the cached TLEs are past the 6 h TTL. Never replaces a newer
    /// catalog that a concurrent `refresh` installed.
    pub async fn load_cached(&self) -> Result<Option<FfiSatelliteRefreshSummary>, CwError> {
        let now = Utc::now().timestamp();
        let (tles, transmitters, amsat, satellites) = {
            let inner = self.store.inner.lock().expect("store mutex poisoned");
            (
                inner.fetch_satellite_data(KIND_TLE)?,
                inner.fetch_satellite_data(KIND_TRANSMITTERS)?,
                inner.fetch_satellite_data(KIND_AMSAT)?,
                inner.fetch_satellite_data(KIND_SATELLITES)?,
            )
        };
        let (Some((tles_json, tles_fetched_at)), Some((transmitters_json, _))) = (tles, transmitters) else {
            return Ok(None);
        };
        let tles_stale = now - tles_fetched_at >= SATELLITE_CACHE_TTL_SECS;
        let amsat_available = amsat.is_some();
        let amsat_json = amsat.map(|(json, _)| json).unwrap_or_else(|| "[]".to_string());
        let satellites_json = satellites.map(|(json, _)| json).unwrap_or_else(|| "[]".to_string());
        let state = tokio::task::spawn_blocking(move || {
            build_state(
                &tles_json,
                &transmitters_json,
                &amsat_json,
                &satellites_json,
                tles_fetched_at,
                tles_stale,
                amsat_available,
            )
        })
        .await
        .map_err(|e| CwError::Store { reason: e.to_string() })??;
        Ok(Some(self.install_state(state, true)))
    }

    /// The AMSAT community-activity grid, enriched from the engine's other
    /// sources. Cache-through on the server's `/activity` histogram
    /// (20 min TTL, stale fallback, error only with no cache at all); each
    /// AMSAT row is joined to the catalog by NORAD id for its display name
    /// and best-matching SatNOGS transmitter, to the pass predictor for the
    /// observer's next pass (24 h, skipped without an observer), and to the
    /// operator's log for QSOs through that bird inside the window.
    /// `cell_secs` ≥ 3600 merges the hourly wire buckets into coarser cells
    /// aligned to the window start; `now_epoch` anchors the next-pass sweep.
    /// Requires a loaded catalog (`refresh` first).
    pub async fn community_activity(
        &self,
        force: bool,
        observer: Option<FfiObserver>,
        now_epoch: i64,
        cell_secs: i64,
    ) -> Result<FfiCommunityActivity, CwError> {
        let state = self.state_or_err()?;
        let now = epoch(now_epoch);
        let (json, fetched_at, is_stale) = self
            .cache_through_ttl(KIND_AMSAT_ACTIVITY, force, now.timestamp(), AMSAT_ACTIVITY_TTL_SECS, || async {
                serde_json::to_string(&self.feed.fetch_activity().await?)
                    .map_err(|e| CwError::Network { reason: e.to_string() })
            })
            .await?;
        let response: cw_net::AmsatActivityResponse = serde_json::from_str(&json)
            .map_err(|e| CwError::Store { reason: format!("amsat activity cache decode: {e}") })?;
        let my_counts: HashMap<String, u32> = {
            let inner = self.store.inner.lock().expect("store mutex poisoned");
            inner
                .satellite_qso_counts_since(response.window_start.timestamp())?
                .into_iter()
                .map(|(name, count)| (name, u32::try_from(count).unwrap_or(u32::MAX)))
                .collect()
        };
        let site = observer.map(Observer::from);
        let window_start_epoch = response.window_start.timestamp();
        let window_end_epoch = response.window_end.timestamp();
        let updated_at_epoch = response.updated_at.map(|d| d.timestamp());
        let rows = tokio::task::spawn_blocking(move || {
            build_activity_rows(&state, &response, site, now, cell_secs, &my_counts)
        })
        .await
        .map_err(|e| CwError::Store { reason: e.to_string() })?;
        Ok(FfiCommunityActivity {
            window_start_epoch,
            window_end_epoch,
            bucket_secs: cell_secs.max(3_600),
            updated_at_epoch,
            fetched_at_epoch: fetched_at,
            is_stale,
            rows,
        })
    }

    /// The raw community reports for one bird over the last 24 h (cache-
    /// through, 10 min TTL, stale fallback), each placed at the reporter's
    /// grid square, plus the previous-orbit summary (reports within one
    /// orbital period + half an hour of `now_epoch`) when the bird is in
    /// the catalog. Works for birds outside the catalog too (no orbit).
    pub async fn community_reports(
        &self,
        norad_id: u32,
        force: bool,
        now_epoch: i64,
    ) -> Result<FfiCommunityReports, CwError> {
        let now = epoch(now_epoch);
        let kind = format!("{KIND_AMSAT_REPORTS_PREFIX}{norad_id}");
        let (json, fetched_at, is_stale) = self
            .cache_through_ttl(&kind, force, now.timestamp(), AMSAT_REPORTS_TTL_SECS, || async {
                serde_json::to_string(&self.feed.fetch_reports(norad_id).await?)
                    .map_err(|e| CwError::Network { reason: e.to_string() })
            })
            .await?;
        let response: cw_net::AmsatReportsResponse = serde_json::from_str(&json)
            .map_err(|e| CwError::Store { reason: format!("amsat reports cache decode: {e}") })?;
        let reports: Vec<cw_domain::satellite::amsat::AmsatReport> =
            response.reports.iter().map(Into::into).collect();
        let period = self.current_state().and_then(|state| {
            state
                .catalog
                .satellites
                .iter()
                .find(|sat| sat.norad_id == norad_id)
                .map(|sat| sat.propagator.period_minutes())
        });
        let previous_orbit = period.map(|period_minutes| {
            let orbit = cw_domain::satellite::amsat::previous_orbit(
                &reports,
                now,
                period_minutes,
                PREVIOUS_ORBIT_MAX_CALLSIGNS,
            );
            FfiPreviousOrbit {
                period_minutes,
                window_start_epoch: orbit.window_start.timestamp(),
                heard: orbit.heard,
                telemetry: orbit.telemetry,
                not_heard: orbit.not_heard,
                status: orbit.status().into(),
                heard_callsigns: orbit.heard_callsigns,
            }
        });
        Ok(FfiCommunityReports {
            norad_id,
            window_start_epoch: response.window_start.timestamp(),
            window_end_epoch: response.window_end.timestamp(),
            fetched_at_epoch: fetched_at,
            is_stale,
            reports: response
                .reports
                .iter()
                .zip(reports.iter())
                .map(|(wire, report)| {
                    let coordinate = report
                        .grid
                        .as_deref()
                        .and_then(cw_domain::maidenhead::coordinate_from_grid);
                    FfiCommunityReport {
                        amsat_name: report.name.clone(),
                        epoch: report.time.timestamp(),
                        callsign: report.callsign.clone(),
                        grid: report.grid.clone(),
                        latitude: coordinate.map(|c| c.latitude),
                        longitude: coordinate.map(|c| c.longitude),
                        report: wire.report.clone(),
                        status: report.kind.status().into(),
                    }
                })
                .collect(),
            previous_orbit,
        })
    }

    /// File a status report with AMSAT (status.amsat.org) on the operator's
    /// behalf. Only ever call this from an explicit operator action: AMSAT's
    /// guidelines forbid automated or background submissions, and the
    /// report must be the operator's own observation under their own
    /// callsign, stamped with the observation time. The grid shows up here
    /// after the activities server's next poll (≤ 30 min).
    pub async fn submit_community_report(
        &self,
        submission: FfiCommunityReportSubmission,
    ) -> Result<FfiCommunityReportReceipt, CwError> {
        let name = submission.amsat_name.trim();
        if name.is_empty() {
            return Err(CwError::Network { reason: "Choose a satellite to report.".to_string() });
        }
        let callsign = submission.callsign.trim();
        if callsign.is_empty() {
            return Err(CwError::Network { reason: "Enter your callsign to file a report.".to_string() });
        }
        let Some(report) = canonical_report_value(&submission.report) else {
            return Err(CwError::Network {
                reason: format!(
                    "Report must be one of {}.",
                    AMSAT_REPORT_VALUES.join(", ")
                ),
            });
        };
        let reported_at = epoch(submission.reported_at_epoch);
        if reported_at > Utc::now() + chrono::Duration::minutes(1) {
            return Err(CwError::Network { reason: "The report time can't be in the future.".to_string() });
        }
        let wire = AmsatReportSubmission::new(name, report, callsign, submission.grid.clone(), reported_at);
        let receipt = self.feed.submit_report(&wire).await?;
        Ok(FfiCommunityReportReceipt {
            id: receipt.id,
            amsat_name: receipt.name,
            reported_at_epoch: receipt.reported_time.timestamp(),
            report: receipt.report,
            callsign: receipt.callsign,
            replaced_count: receipt.replaced_count,
        })
    }

    /// Pass forecast for one satellite (defaults mirror iOS: 48 h / 12).
    pub async fn pass_forecast(
        &self,
        norad_id: u32,
        observer: FfiObserver,
        start_epoch: i64,
        hours: f64,
        max_passes: u32,
    ) -> Result<FfiPassForecast, CwError> {
        let state = self.state_or_err()?;
        let start = epoch(start_epoch);
        let site = Observer::from(observer);
        let result = tokio::task::spawn_blocking(move || {
            let Some(sat) =
                state.catalog.satellites.iter().find(|sat| sat.norad_id == norad_id)
            else {
                return pass_predictor::PassForecast::default();
            };
            pass_predictor::forecast(&sat.propagator, site, start, hours, max_passes as usize)
        })
        .await
        .map_err(|e| CwError::Store { reason: e.to_string() })?;
        Ok(FfiPassForecast::from(&result))
    }

    /// Upcoming passes across the catalog (max 2 per satellite, the iOS
    /// all-sky sweep). Empty `favorites` = every catalog bird.
    pub async fn upcoming_passes(
        &self,
        observer: FfiObserver,
        start_epoch: i64,
        hours: f64,
        favorites: Vec<u32>,
    ) -> Result<Vec<FfiUpcomingPass>, CwError> {
        let passes = self
            .sweep_upcoming(observer.into(), epoch(start_epoch), hours, favorites)
            .await?;
        Ok(passes.iter().map(FfiUpcomingPass::from).collect())
    }

    /// Mutual windows between two sites over satellites with an active
    /// transmitter in one of the requested categories (empty = all).
    pub async fn mutual_passes(
        &self,
        site_a: FfiObserver,
        site_b: FfiObserver,
        start_epoch: i64,
        hours: f64,
        categories: Vec<FfiSatModeCategory>,
    ) -> Result<Vec<FfiMutualPass>, CwError> {
        let state = self.state_or_err()?;
        let start = epoch(start_epoch);
        let (a, b) = (Observer::from(site_a), Observer::from(site_b));
        let wanted: Vec<cw_domain::satellite::mode_category::ModeCategory> =
            categories.into_iter().map(Into::into).collect();
        let mut passes = tokio::task::spawn_blocking(move || {
            let mut all = Vec::new();
            for sat in &state.catalog.satellites {
                if !candidate_matches(&state, sat.norad_id, &wanted) {
                    continue;
                }
                all.extend(mutual::mutual_passes(
                    sat,
                    a,
                    b,
                    start,
                    hours,
                    mutual::MAX_PASSES,
                ));
            }
            all
        })
        .await
        .map_err(|e| CwError::Store { reason: e.to_string() })?;
        passes.sort_by_key(|pass| pass.start);
        Ok(passes.iter().map(FfiMutualPass::from).collect())
    }

    /// Fine-grained samples of one mutual window for the profile view.
    pub async fn mutual_profile(
        &self,
        norad_id: u32,
        start_epoch: i64,
        end_epoch: i64,
        site_a: FfiObserver,
        site_b: FfiObserver,
    ) -> Result<Vec<FfiMutualSample>, CwError> {
        let state = self.state_or_err()?;
        let (start, end) = (epoch(start_epoch), epoch(end_epoch));
        let (a, b) = (Observer::from(site_a), Observer::from(site_b));
        let samples = tokio::task::spawn_blocking(move || {
            let Some(sat) =
                state.catalog.satellites.iter().find(|sat| sat.norad_id == norad_id)
            else {
                return Vec::new();
            };
            mutual::profile_samples(&sat.propagator, start, end, a, b)
        })
        .await
        .map_err(|e| CwError::Store { reason: e.to_string() })?;
        Ok(samples.iter().map(FfiMutualSample::from).collect())
    }

    /// Plan pass alerts for the favorited birds: sweep their passes, then
    /// run the shared planner (10°/20° gating, AOS−lead fire times,
    /// nearest-first, 24 cap, minute-rounded identifiers, notification
    /// copy). Hosts schedule the platform notifications from the result.
    pub async fn plan_alerts(
        &self,
        observer: FfiObserver,
        favorites: Vec<u32>,
        include_marginal: bool,
        lead_secs: i64,
        now_epoch: i64,
        hours: f64,
    ) -> Result<Vec<FfiPlannedAlert>, CwError> {
        if favorites.is_empty() {
            return Ok(Vec::new());
        }
        let now = epoch(now_epoch);
        let passes = self.sweep_upcoming(observer.into(), now, hours, favorites).await?;
        let planned = alert_planner::plan(&passes, include_marginal, lead_secs, now);
        Ok(planned.iter().map(FfiPlannedAlert::from).collect())
    }
}

impl SatelliteApi {
    fn current_state(&self) -> Option<Arc<CatalogState>> {
        self.state.lock().expect("satellite state poisoned").clone()
    }

    /// Swap in a built catalog and summarize what is now installed. With
    /// `only_if_newer`, an installed catalog built from newer TLEs is kept
    /// (the cache-only load racing a network refresh).
    fn install_state(&self, state: CatalogState, only_if_newer: bool) -> FfiSatelliteRefreshSummary {
        let mut slot = self.state.lock().expect("satellite state poisoned");
        let keep_current = only_if_newer
            && slot.as_ref().is_some_and(|current| current.tles_fetched_at > state.tles_fetched_at);
        if !keep_current {
            *slot = Some(Arc::new(state));
        }
        let installed = slot.as_ref().expect("catalog just installed");
        FfiSatelliteRefreshSummary {
            satellite_count: installed.catalog.satellites.len() as u32,
            tles_fetched_at_epoch: installed.tles_fetched_at,
            tles_stale: installed.tles_stale,
            amsat_available: installed.amsat_available,
        }
    }

    /// True when `kind`'s last network fetch failed within
    /// [`FETCH_FAILURE_BACKOFF_SECS`] of `wall_now` (real time, not the
    /// scrubbed epoch some callers pass as `now`).
    fn in_failure_backoff(&self, kind: &str, wall_now: i64) -> bool {
        self.fetch_failed_at
            .lock()
            .expect("fetch backoff poisoned")
            .get(kind)
            .is_some_and(|failed_at| wall_now - failed_at < FETCH_FAILURE_BACKOFF_SECS)
    }

    fn record_fetch_result(&self, kind: &str, failed_at: Option<i64>) {
        let mut failures = self.fetch_failed_at.lock().expect("fetch backoff poisoned");
        match failed_at {
            Some(at) => {
                failures.insert(kind.to_string(), at);
            }
            None => {
                failures.remove(kind);
            }
        }
    }

    fn state_or_err(&self) -> Result<Arc<CatalogState>, CwError> {
        self.current_state().ok_or_else(|| CwError::Store {
            reason: "satellite catalog not loaded — call refresh() first".to_string(),
        })
    }

    /// Cache-through for one blob kind: fresh cache → hit; else fetch +
    /// write-through; network failure → stale cache row of any age; error
    /// only when both fail. Returns `(payload, fetched_at, is_stale)`.
    async fn cache_through<F, Fut>(
        &self,
        kind: &str,
        force: bool,
        now: i64,
        fetch: F,
    ) -> Result<(String, i64, bool), CwError>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<String, CwError>>,
    {
        self.cache_through_ttl(kind, force, now, SATELLITE_CACHE_TTL_SECS, fetch).await
    }

    /// [`Self::cache_through`] with an explicit freshness window.
    async fn cache_through_ttl<F, Fut>(
        &self,
        kind: &str,
        force: bool,
        now: i64,
        ttl_secs: i64,
        fetch: F,
    ) -> Result<(String, i64, bool), CwError>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<String, CwError>>,
    {
        let cached = {
            let inner = self.store.inner.lock().expect("store mutex poisoned");
            inner.fetch_satellite_data(kind)?
        };
        let wall_now = Utc::now().timestamp();
        if let Some((payload, fetched_at)) = &cached {
            if !force && now - fetched_at < ttl_secs {
                return Ok((payload.clone(), *fetched_at, false));
            }
            // A recent fetch failed: don't make every caller wait out the
            // network again — serve stale until the backoff lapses.
            if !force && self.in_failure_backoff(kind, wall_now) {
                return Ok((payload.clone(), *fetched_at, true));
            }
        }
        let result = fetch().await;
        self.record_fetch_result(kind, result.is_err().then_some(wall_now));
        match result {
            Ok(payload) => {
                let inner = self.store.inner.lock().expect("store mutex poisoned");
                inner.upsert_satellite_data(kind, &payload, now)?;
                Ok((payload, now, false))
            }
            Err(error) => match cached {
                // Stale beats nothing — the iOS disk-cache fallback posture.
                Some((payload, fetched_at)) => Ok((payload, fetched_at, true)),
                None => Err(error),
            },
        }
    }

    /// Cross-satellite pass sweep (max 2 passes each, iOS `upcomingPasses`),
    /// blocking-pool fan-out. Empty `favorites` = all catalog birds.
    async fn sweep_upcoming(
        &self,
        observer: Observer,
        start: DateTime<Utc>,
        hours: f64,
        favorites: Vec<u32>,
    ) -> Result<Vec<UpcomingPass>, CwError> {
        let state = self.state_or_err()?;
        let mut all = tokio::task::spawn_blocking(move || {
            let mut passes = Vec::new();
            for sat in &state.catalog.satellites {
                if !favorites.is_empty() && !favorites.contains(&sat.norad_id) {
                    continue;
                }
                let forecast = pass_predictor::forecast(&sat.propagator, observer, start, hours, 2);
                passes.extend(forecast.passes.into_iter().map(|pass| UpcomingPass {
                    norad_id: sat.norad_id,
                    name: sat.name.clone(),
                    detail_name: sat.detail_name.clone(),
                    pass,
                }));
            }
            passes
        })
        .await
        .map_err(|e| CwError::Store { reason: e.to_string() })?;
        all.sort_by_key(|item| item.pass.aos);
        Ok(all)
    }
}

/// Does the satellite carry an active transmitter in one of the wanted
/// categories (empty = any)? Port of the iOS `activeCandidates(matching:)`.
fn candidate_matches(
    state: &CatalogState,
    norad_id: u32,
    wanted: &[cw_domain::satellite::mode_category::ModeCategory],
) -> bool {
    let Some(transmitters) = state.catalog.transmitters_by_norad.get(&norad_id) else {
        return false;
    };
    transmitters.iter().any(|transmitter| {
        transmitter.is_active()
            && (wanted.is_empty()
                || wanted.contains(
                    &cw_domain::satellite::mode_category::ModeCategory::for_transmitter(
                        transmitter,
                    ),
                ))
    })
}

/// Decode the cached wire payloads and build the catalog. Runs on the
/// blocking pool — SGP4 initialization over the full TLE set.
fn build_state(
    tles_json: &str,
    transmitters_json: &str,
    amsat_json: &str,
    satellites_json: &str,
    tles_fetched_at: i64,
    tles_stale: bool,
    amsat_available: bool,
) -> Result<CatalogState, CwError> {
    let tles_wire: Vec<SatnogsTle> = serde_json::from_str(tles_json)
        .map_err(|e| CwError::Store { reason: format!("tle cache decode: {e}") })?;
    let transmitters_wire: Vec<SatnogsTransmitter> = serde_json::from_str(transmitters_json)
        .map_err(|e| CwError::Store { reason: format!("transmitter cache decode: {e}") })?;
    let amsat_wire: Vec<cw_net::AmsatStatusRow> = serde_json::from_str(amsat_json)
        .map_err(|e| CwError::Store { reason: format!("amsat cache decode: {e}") })?;
    let satellites_wire: Vec<SatnogsSatellite> = serde_json::from_str(satellites_json)
        .map_err(|e| CwError::Store { reason: format!("satellite cache decode: {e}") })?;

    let tles: Vec<SatTle> = tles_wire.iter().map(SatTle::from).collect();
    let transmitters: Vec<SatTransmitter> =
        transmitters_wire.iter().map(SatTransmitter::from).collect();
    let mut amsat_rows: HashMap<u32, Vec<AmsatStatus>> = HashMap::new();
    let mut amsat_rows_by_name: HashMap<String, AmsatStatus> = HashMap::new();
    for row in &amsat_wire {
        let status = AmsatStatus::from(row);
        amsat_rows_by_name.insert(status.name.clone(), status.clone());
        if let Some(norad) = status.norad_id {
            amsat_rows.entry(norad).or_default().push(status);
        }
    }
    let catalog_names: HashMap<u32, String> = satellites_wire
        .iter()
        .filter_map(|sat| {
            let norad = sat.norad_cat_id?;
            Some((
                norad,
                display_name::catalog_base_name(Some(&sat.name), sat.names.as_deref(), ""),
            ))
        })
        .filter(|(_, name)| !name.is_empty())
        .collect();

    let catalog =
        build_ham_satellites(&tles, &transmitters, &amsat_rows, &catalog_names, Utc::now());
    let amsat_by_norad = amsat_rows
        .iter()
        .filter_map(|(norad, rows)| freshest(rows).map(|row| (*norad, row.clone())))
        .collect();
    Ok(CatalogState {
        catalog,
        amsat_by_norad,
        amsat_rows_by_norad: amsat_rows,
        amsat_rows_by_name,
        tles_fetched_at,
        tles_stale,
        amsat_available,
    })
}

/// Join every AMSAT activity row to the catalog, the pass predictor, and
/// the operator's log. Runs on the blocking pool (one short pass sweep per
/// catalog bird when an observer is given).
fn build_activity_rows(
    state: &CatalogState,
    response: &cw_net::AmsatActivityResponse,
    site: Option<Observer>,
    now: DateTime<Utc>,
    cell_secs: i64,
    my_counts: &HashMap<String, u32>,
) -> Vec<FfiCommunityActivityRow> {
    use cw_domain::satellite::amsat::{self as amsat_domain, ActivityBucket};
    use cw_domain::satellite::workability::categories_for_amsat_tag;

    // One next-pass sweep per NORAD id, shared by its capability rows.
    let mut next_pass_cache: HashMap<u32, Option<FfiSatellitePass>> = HashMap::new();

    response
        .satellites
        .iter()
        .map(|wire| {
            let base = amsat_domain::base_name(&wire.name).to_string();
            let capability = amsat_domain::capability_tag(&wire.name);
            let status = state.amsat_rows_by_name.get(&wire.name);
            let norad_id = wire
                .norad_id
                .and_then(|id| u32::try_from(id).ok())
                .or_else(|| status.and_then(|row| row.norad_id));
            let catalog_sat = norad_id
                .and_then(|id| state.catalog.satellites.iter().find(|sat| sat.norad_id == id));
            let mode_category = capability
                .as_deref()
                .and_then(categories_for_amsat_tag)
                .and_then(|categories| primary_category(&categories));
            let transmitter = norad_id
                .and_then(|id| state.catalog.transmitters_by_norad.get(&id))
                .and_then(|list| best_transmitter(list, mode_category));
            let next_pass = match (site, catalog_sat) {
                (Some(site), Some(sat)) => next_pass_cache
                    .entry(sat.norad_id)
                    .or_insert_with(|| {
                        pass_predictor::forecast(&sat.propagator, site, now, NEXT_PASS_HOURS, 1)
                            .passes
                            .first()
                            .map(FfiSatellitePass::from)
                    })
                    .clone(),
                _ => None,
            };
            let hourly: Vec<ActivityBucket> = wire.buckets.iter().map(ActivityBucket::from).collect();
            let buckets = amsat_domain::merge_buckets(&hourly, response.window_start, cell_secs);
            FfiCommunityActivityRow {
                amsat_name: wire.name.clone(),
                display_name: catalog_sat.map_or_else(|| base.clone(), |sat| sat.name.clone()),
                detail_name: catalog_sat.and_then(|sat| sat.detail_name.clone()),
                my_qso_count: my_counts.get(&base.to_uppercase()).copied().unwrap_or(0),
                base_name: base,
                capability,
                norad_id,
                in_catalog: catalog_sat.is_some(),
                mode_category: mode_category.map(Into::into),
                transmitter_mode: transmitter.and_then(|t| t.mode.clone()),
                downlink_low_hz: transmitter.and_then(|t| t.downlink_low_hz),
                uplink_low_hz: transmitter.and_then(|t| t.uplink_low_hz),
                transmitter_active: transmitter.map(SatTransmitter::is_active),
                last_heard_epoch: status.and_then(|row| row.last_heard_at.map(|d| d.timestamp())),
                heard_reports_24h: status.map_or(0, |row| row.heard_reports_24h),
                total_reports_24h: status.map_or(0, |row| row.total_reports_24h),
                next_pass,
                buckets: buckets.iter().map(FfiActivityBucket::from).collect(),
            }
        })
        .collect()
}

/// The one mode bucket to badge a capability tag with when the tag vouches
/// for several (linear transponders also carry CW): voice/linear/digital
/// beat the CW subpassband.
fn primary_category(
    categories: &std::collections::HashSet<cw_domain::satellite::mode_category::ModeCategory>,
) -> Option<cw_domain::satellite::mode_category::ModeCategory> {
    use cw_domain::satellite::mode_category::ModeCategory;
    [ModeCategory::VoiceFm, ModeCategory::Linear, ModeCategory::Digital, ModeCategory::Morse]
        .into_iter()
        .find(|category| categories.contains(category))
}

/// The catalog transmitter that best represents an AMSAT capability: an
/// active one in the capability's mode bucket, else any in that bucket,
/// else (unrecognized tag) the first active transmitter.
fn best_transmitter(
    transmitters: &[SatTransmitter],
    category: Option<cw_domain::satellite::mode_category::ModeCategory>,
) -> Option<&SatTransmitter> {
    use cw_domain::satellite::mode_category::ModeCategory;
    match category {
        Some(category) => {
            let same_bucket =
                |t: &&SatTransmitter| ModeCategory::for_transmitter(t) == category;
            transmitters
                .iter()
                .filter(same_bucket)
                .find(|t| t.is_active())
                .or_else(|| transmitters.iter().find(same_bucket))
        }
        None => transmitters.iter().find(|t| t.is_active()).or_else(|| transmitters.first()),
    }
}

fn epoch(secs: i64) -> DateTime<Utc> {
    Utc.timestamp_opt(secs, 0).single().unwrap_or_else(Utc::now)
}

/// The satellite quick-log session row: casual, no programs, born completed
/// with the pass window and a "<sat> pass" title. Every other column takes
/// the same defaults as `session_wizard_api::assemble`.
fn build_pass_session(input: &FfiPassSessionInput) -> cw_store::logging_session::LoggingSession {
    cw_store::logging_session::LoggingSession {
        id: uuid::Uuid::new_v4().to_string(),
        my_callsign: input.my_callsign.trim().to_uppercase(),
        started_at: input.started_at_epoch,
        ended_at: Some(input.ended_at_epoch),
        frequency: input.frequency_mhz,
        mode: input.mode.clone(),
        activation_type_raw_value: "casual".to_string(),
        programs_raw_value: String::new(),
        status_raw_value: "completed".to_string(),
        park_reference: None,
        sota_reference: None,
        mission_reference: None,
        wwff_reference: None,
        my_grid: input
            .my_grid
            .as_deref()
            .map(|grid| grid.trim().to_uppercase())
            .filter(|grid| !grid.is_empty()),
        power: None,
        my_rig: None,
        notes: None,
        qso_comment: None,
        custom_title: Some(format!("{} pass", input.sat_name)),
        qso_count: 0,
        spot_comments_data: None,
        is_rove: false,
        rove_stops_data: None,
        my_antenna: None,
        my_key: None,
        my_mic: None,
        extra_equipment: None,
        attendees: None,
        photo_filenames: "[]".to_string(),
        radio_item_id: None,
        station_callsign: None,
        operator_callsigns_raw_value: "[]".to_string(),
        solar_k_index: None,
        solar_flux: None,
        solar_sunspots: None,
        solar_propagation_rating: None,
        solar_a_index: None,
        solar_band_conditions: None,
        solar_timestamp: None,
        solar_conditions: None,
        weather_temperature_f: None,
        weather_temperature_c: None,
        weather_humidity: None,
        weather_wind_speed: None,
        weather_wind_direction: None,
        weather_description: None,
        weather_timestamp: None,
        weather: None,
        cloud_dirty_flag: true,
        contest_id: None,
        contest_category: None,
        contest_overlay_category: None,
        contest_power: None,
        contest_bands: None,
        contest_operator: None,
        activation_latitude: None,
        activation_longitude: None,
        activation_distance_miles: None,
        activation_elevation_gain_feet: None,
        ruck_weight_pounds: None,
        qrp_activation: false,
        with_pets: false,
        with_kids: false,
        winlink_sent: false,
        aprs_sent: false,
        varac_sent: false,
        adaptive_sport: false,
        track_points_data: None,
        tota_category_raw_value: None,
        personal_effort_factor: None,
        first_activation_of_tile_ever: false,
        winter_activation_override: None,
        tiles_activated_data: None,
        tota_t3_candidates_data: None,
        tota_t3_snapshot_at: None,
        tota_official_points: None,
    }
}
