//! `SpotEngineApi` — the shared spots engine. Replaces Sweep's
//! `SpotAggregator` (+`ClusterManager`) and iOS's `SpotMonitoringService`
//! fetch/enrich internals.
//!
//! Responsibilities: poll all enabled HTTP sources on an interval, run the
//! telnet cluster connection (auto-reconnect + 5-minute SH/WWV / SH/FILTER
//! cycle), merge/dedup/prune the pool, enrich (grids, distance/bearing,
//! region, DXCC, needs), project observations into the scope SQL database,
//! evaluate the active band-scope query, and publish snapshots to the host
//! via a listener callback. Hosts feed: user context, needs snapshot, CTY
//! text, QSO mirror rows. SKCC membership display stays host-side.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use cw_domain::cty::CtyDatabase;
use cw_domain::maidenhead;
use cw_domain::spots::merge::SpotPool;
use cw_domain::spots::model::{EnrichedSpot, NeededStatus, SpotSource, UnifiedSpot};
use cw_domain::spots::needs::{self, NeedsPreferences, NeedsSnapshot};
use cw_domain::spots::observations;
use cw_domain::spots::region::SpotRegion;
use cw_net::{
    cluster, unified, DxHeatClient, DxSummitClient, DxWatchClient, HamdbClient, HttpClient,
    PotaClient, PskReporterClient, RbnClient, SotaClient, WwffClient,
};

use super::scope_db::ScopeDb;
use super::types::*;
use crate::CwError;

fn now_secs() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

/// Minimum gap between reposts of the same activator (iOS `SpotCooldownTracker`).
const RESPOT_COOLDOWN_SECS: u64 = 300;

/// Concurrent HamDB lookups per enrichment batch. Serial lookups took
/// ~0.75 s each — a full 20-callsign batch held the publish for ~15 s.
const ENRICH_CONCURRENCY: usize = 8;

/// Persisted enrichment entries older than this are dropped on load —
/// callbook data changes rarely, but not never.
const ENRICH_CACHE_TTL_SECS: i64 = 30 * 24 * 60 * 60;

/// Cap on persisted enrichment entries (newest kept).
const ENRICH_CACHE_MAX_ENTRIES: usize = 5_000;

/// Host callback surface. `on_spots_updated` fires after every publish —
/// hosts re-read `snapshot()` rather than receiving pushed arrays.
#[uniffi::export(with_foreign)]
pub trait SpotEngineListener: Send + Sync {
    fn on_spots_updated(&self, generation: u64);
    /// Every raw cluster line (Sweep's terminal view tap).
    fn on_cluster_line(&self, line: String);
    /// Cluster connection state changes.
    fn on_cluster_state(&self, connected: bool);
}

/// Per-callsign enrichment cache entry (Sweep's `CallsignEnrichment`).
/// `fetched_at` (epoch seconds) drives the persisted cache's TTL; entries
/// that predate the field deserialize as 0 and age out on the next load.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
struct CallsignEnrichment {
    state: Option<String>,
    country: Option<String>,
    operator_name: Option<String>,
    grid: Option<String>,
    #[serde(default)]
    fetched_at: i64,
}

struct UserContext {
    grid: Option<String>,
    callsign: String,
    worked: std::collections::HashSet<String>,
    worked_today: std::collections::HashSet<String>,
}

struct ClusterDesire {
    host: String,
    port: u16,
    login: String,
}

struct EngineInner {
    config: RwLock<FfiSpotEngineConfig>,
    pool: Mutex<SpotPool>,
    enriched: RwLock<Vec<EnrichedSpot>>,
    generation: AtomicU64,
    last_refresh: AtomicI64,
    listener: RwLock<Option<Arc<dyn SpotEngineListener>>>,
    errors: Mutex<HashMap<SpotSource, String>>,
    user: RwLock<UserContext>,
    needs: RwLock<Option<(NeedsSnapshot, NeedsPreferences)>>,
    cty: RwLock<Option<Arc<CtyDatabase>>>,
    enrich_cache: Mutex<HashMap<String, CallsignEnrichment>>,
    enrich_cache_path: RwLock<Option<std::path::PathBuf>>,
    scope: Arc<ScopeDb>,
    band_scope_sql: RwLock<Option<String>>,
    allowed_ids: RwLock<Option<Vec<String>>>,
    paused: AtomicBool,
    running: AtomicBool,
    cluster_desired: Mutex<Option<ClusterDesire>>,
    cluster_epoch: AtomicU64,
    pskr_rotation: std::sync::atomic::AtomicUsize,
    /// Last respot time per (uppercased) activator, for the spam cooldown.
    respot_times: Mutex<HashMap<String, Instant>>,
    // Clients
    rbn: RbnClient,
    pota: PotaClient,
    sota: SotaClient,
    wwff: WwffClient,
    dxsummit: DxSummitClient,
    dxheat: DxHeatClient,
    dxwatch: DxWatchClient,
    pskr: PskReporterClient,
    hamdb: HamdbClient,
}

#[derive(uniffi::Object)]
pub struct SpotEngineApi {
    inner: Arc<EngineInner>,
}

#[uniffi::export]
impl SpotEngineApi {
    #[uniffi::constructor]
    pub fn new(config: FfiSpotEngineConfig) -> Result<Self, CwError> {
        let http = HttpClient::new()?;
        let scope = Arc::new(ScopeDb::new_in_memory().map_err(|err| CwError::Store {
            reason: err.message,
        })?);
        let inner = Arc::new(EngineInner {
            rbn: RbnClient::new(http.clone(), config.activities_base_url.clone()),
            pota: PotaClient::new(http.clone()),
            sota: SotaClient::new(http.clone()),
            wwff: WwffClient::new(http.clone()),
            dxsummit: DxSummitClient::new(http.clone()),
            dxheat: DxHeatClient::new(http.clone()),
            dxwatch: DxWatchClient::new(http.clone()),
            pskr: PskReporterClient::new(http.clone(), "carrierwave-app@example.com"),
            hamdb: HamdbClient::new(http),
            config: RwLock::new(config),
            pool: Mutex::new(SpotPool::new()),
            enriched: RwLock::new(Vec::new()),
            generation: AtomicU64::new(0),
            last_refresh: AtomicI64::new(0),
            listener: RwLock::new(None),
            errors: Mutex::new(HashMap::new()),
            user: RwLock::new(UserContext {
                grid: None,
                callsign: String::new(),
                worked: Default::default(),
                worked_today: Default::default(),
            }),
            needs: RwLock::new(None),
            cty: RwLock::new(None),
            enrich_cache: Mutex::new(HashMap::new()),
            enrich_cache_path: RwLock::new(None),
            scope,
            band_scope_sql: RwLock::new(None),
            allowed_ids: RwLock::new(None),
            paused: AtomicBool::new(false),
            running: AtomicBool::new(false),
            cluster_desired: Mutex::new(None),
            cluster_epoch: AtomicU64::new(0),
            pskr_rotation: std::sync::atomic::AtomicUsize::new(0),
            respot_times: Mutex::new(HashMap::new()),
        });
        Ok(SpotEngineApi { inner })
    }

    // ---- Host-fed context ----

    /// User grid + callsign (distance origin, self-spot detection, the
    /// `cw_user_*` SQL functions).
    pub fn set_user_context(&self, grid: Option<String>, callsign: String) {
        {
            let mut user = self.inner.user.write().expect("user lock");
            user.grid = grid.clone().filter(|value| !value.is_empty());
            user.callsign = callsign;
        }
        self.inner.scope.set_user_grid(grid);
    }

    /// Worked-callsign sets for filter evaluation.
    pub fn set_worked_context(&self, context: FfiWorkedContext) {
        let mut user = self.inner.user.write().expect("user lock");
        user.worked = context.worked.into_iter().collect();
        user.worked_today = context.worked_today.into_iter().collect();
    }

    /// Host-computed needs snapshot; `None` disables needs matching.
    pub fn set_needs_snapshot(&self, snapshot: Option<FfiNeedsSnapshot>) {
        *self.inner.needs.write().expect("needs lock") =
            snapshot.map(|ffi| ffi.to_domain());
    }

    /// Raw CTY.dat content (host downloads/caches the file).
    pub fn set_cty_database(&self, cty_content: String) {
        let db = cw_domain::cty::parse(&cty_content);
        *self.inner.cty.write().expect("cty lock") = Some(Arc::new(db));
    }

    /// Replace the enabled-source set / limits without restarting.
    pub fn set_config(&self, config: FfiSpotEngineConfig) {
        *self.inner.config.write().expect("config lock") = config;
    }

    /// Point the engine at a JSON file that persists the per-callsign
    /// enrichment cache across launches — without it every launch re-pays
    /// the HamDB lookups. Loads (and TTL-prunes) any prior contents
    /// immediately; the file is rewritten after each enrichment batch.
    /// Callbook data is public, so plain JSON is fine.
    pub fn set_enrichment_cache_path(&self, path: String) {
        let path = std::path::PathBuf::from(path);
        let loaded = load_enrich_cache(&path);
        {
            let mut cache = self.inner.enrich_cache.lock().expect("enrich lock");
            for (call, entry) in loaded {
                cache.entry(call).or_insert(entry);
            }
        }
        *self.inner.enrich_cache_path.write().expect("enrich path lock") = Some(path);
    }

    // ---- Filters / snapshot ----

    /// Filtered, published view of the pool. Pass `None` for everything.
    pub fn snapshot(
        &self,
        filter: Option<FfiSpotFilter>,
        worked: Option<FfiWorkedContext>,
    ) -> FfiSpotSnapshot {
        let enriched = self.inner.enriched.read().expect("enriched lock");
        let spots: Vec<FfiEnrichedSpot> = match &filter {
            Some(filter) => {
                let domain = filter.to_domain();
                let ctx = worked.unwrap_or_default().to_domain(now_secs());
                enriched
                    .iter()
                    .filter(|spot| domain.matches(spot, &ctx))
                    .map(FfiEnrichedSpot::from)
                    .collect()
            }
            None => enriched.iter().map(FfiEnrichedSpot::from).collect(),
        };
        let mut counts: HashMap<SpotSource, u32> = HashMap::new();
        for spot in enriched.iter() {
            *counts.entry(spot.spot.source).or_insert(0) += 1;
        }
        FfiSpotSnapshot {
            generation: self.inner.generation.load(Ordering::SeqCst),
            spots,
            counts: counts
                .into_iter()
                .map(|(source, count)| FfiSourceCount { source: source.into(), count })
                .collect(),
            errors: self
                .inner
                .errors
                .lock()
                .expect("errors lock")
                .iter()
                .map(|(source, message)| FfiSourceError {
                    source: (*source).into(),
                    message: message.clone(),
                })
                .collect(),
            last_refresh: self.inner.last_refresh.load(Ordering::SeqCst),
            allowed_spot_ids: self.inner.allowed_ids.read().expect("allowed lock").clone(),
        }
    }

    // ---- Query surface ----

    pub fn run_query(&self, sql: String, limit: u32) -> Result<FfiQueryResultSet, SpotQueryError> {
        Ok(self.inner.scope.run_query(&sql, limit).map(FfiQueryResultSet::from)?)
    }

    pub fn profile_query(&self, sql: String) -> Result<FfiQueryResultSet, SpotQueryError> {
        Ok(self.inner.scope.profile_query(&sql).map(FfiQueryResultSet::from)?)
    }

    /// Validate a band-scope query (read-only + emits `spot_id`).
    pub fn validate_scope_query(&self, sql: String) -> Result<(), SpotQueryError> {
        Ok(self.inner.scope.validate_scope_query(&sql)?)
    }

    /// Break the currently-running query (`sqlite3_interrupt`).
    pub fn interrupt_query(&self) {
        self.inner.scope.interrupt();
    }

    /// Set (or clear) the band-scope allow-list query. Validated first;
    /// re-evaluated after every publish.
    pub fn set_band_scope_query(&self, sql: Option<String>) -> Result<(), SpotQueryError> {
        if let Some(sql) = &sql {
            self.inner.scope.validate_scope_query(sql)?;
        }
        *self.inner.band_scope_sql.write().expect("band scope lock") = sql;
        self.inner.refresh_allowed_ids();
        Ok(())
    }

    // ---- Mirror writes ----

    pub fn mirror_qsos(&self, rows: Vec<FfiScopeQso>) -> Result<(), SpotQueryError> {
        let rows: Vec<_> = rows.iter().map(Into::into).collect();
        Ok(self.inner.scope.upsert_qsos(&rows)?)
    }

    pub fn delete_mirrored_qso(&self, id: String) -> Result<(), SpotQueryError> {
        Ok(self.inner.scope.delete_qso(&id)?)
    }

    pub fn seed_dxcc(&self, rows: Vec<FfiScopeDxcc>) -> Result<(), SpotQueryError> {
        let rows: Vec<_> = rows.iter().map(Into::into).collect();
        Ok(self.inner.scope.seed_dxcc(&rows)?)
    }

    pub fn seed_polo_notes(&self, rows: Vec<FfiScopePoloNote>) -> Result<(), SpotQueryError> {
        let rows: Vec<_> = rows.iter().map(Into::into).collect();
        Ok(self.inner.scope.seed_polo_notes(&rows)?)
    }

    /// Replace the club roster used by goal-profile SQL (`scope.club_members`).
    /// SKCC seeds a full roster; LICW/CWOps arrive opportunistically.
    pub fn seed_club_members(&self, rows: Vec<FfiScopeClubMember>) -> Result<(), SpotQueryError> {
        let rows: Vec<_> = rows.iter().map(Into::into).collect();
        Ok(self.inner.scope.seed_club_members(&rows)?)
    }

    // ---- Lifecycle ----

    /// iOS backgrounding: skip poll ticks without tearing anything down.
    pub fn pause(&self) {
        self.inner.paused.store(true, Ordering::SeqCst);
    }

    pub fn resume(&self) {
        self.inner.paused.store(false, Ordering::SeqCst);
    }

    pub fn is_running(&self) -> bool {
        self.inner.running.load(Ordering::SeqCst)
    }

    // ---- POTA respot ----

    /// Seconds left in the per-activator respot cooldown, or `None` when the
    /// activator is free to respot. Port of iOS `SpotCooldownTracker`; hosts
    /// surface a "recently spotted" warning in their confirm step and may
    /// still post (the cooldown is advisory, bypassable after the warning).
    pub fn pota_respot_cooldown_remaining(&self, activator: String) -> Option<u32> {
        let times = self.inner.respot_times.lock().expect("respot lock");
        let elapsed = times.get(&activator.trim().to_uppercase())?.elapsed().as_secs();
        (elapsed < RESPOT_COOLDOWN_SECS).then(|| (RESPOT_COOLDOWN_SECS - elapsed) as u32)
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl SpotEngineApi {
    /// Start the poll loop. Idempotent; `stop()` ends it.
    pub async fn start(&self, listener: Arc<dyn SpotEngineListener>) {
        *self.inner.listener.write().expect("listener lock") = Some(listener);
        if self.inner.running.swap(true, Ordering::SeqCst) {
            return;
        }
        let inner = Arc::clone(&self.inner);
        tokio::spawn(async move {
            while inner.running.load(Ordering::SeqCst) {
                if !inner.paused.load(Ordering::SeqCst) {
                    poll_once(&inner).await;
                }
                let interval =
                    inner.config.read().expect("config lock").poll_interval_secs.max(5);
                tokio::time::sleep(Duration::from_secs(interval as u64)).await;
            }
        });
    }

    pub async fn stop(&self) {
        self.inner.running.store(false, Ordering::SeqCst);
        self.disconnect_cluster().await;
    }

    /// One manual refresh outside the timer (pull-to-refresh).
    pub async fn refresh(&self) {
        poll_once(&self.inner).await;
    }

    // ---- Cluster ----

    /// Connect (and keep reconnecting with backoff) to a DX cluster node.
    /// Replaces any previous cluster connection.
    pub async fn connect_cluster(&self, host: String, port: u16, login_callsign: String) {
        *self.inner.cluster_desired.lock().expect("cluster lock") =
            Some(ClusterDesire { host: host.clone(), port, login: login_callsign.clone() });
        let epoch = self.inner.cluster_epoch.fetch_add(1, Ordering::SeqCst) + 1;
        let inner = Arc::clone(&self.inner);
        tokio::spawn(async move {
            run_cluster(inner, epoch).await;
        });
    }

    pub async fn disconnect_cluster(&self) {
        *self.inner.cluster_desired.lock().expect("cluster lock") = None;
        // Bump the epoch so any live manager loop exits at its next check.
        self.inner.cluster_epoch.fetch_add(1, Ordering::SeqCst);
    }

    // ---- POTA respot ----

    /// Post a POTA respot for `activator` as the configured user (an
    /// explicit host action — the engine never respots on its own). The
    /// spotter callsign comes from `set_user_context`. Records the
    /// per-activator cooldown timestamp on success.
    pub async fn pota_respot(
        &self,
        activator: String,
        reference: String,
        frequency_khz: f64,
        mode: String,
        comments: Option<String>,
    ) -> Result<(), CwError> {
        let spotter = {
            let user = self.inner.user.read().expect("user lock");
            user.callsign.trim().to_uppercase()
        };
        if spotter.is_empty() {
            return Err(CwError::Query { reason: "set your callsign before spotting".into() });
        }
        let body = cw_net::PotaSpotPost::respot(
            &activator,
            &spotter,
            &reference,
            frequency_khz,
            &mode,
            comments,
        )
        .ok_or_else(|| CwError::Query {
            reason: format!(
                "invalid respot for '{reference}' at {frequency_khz} kHz"
            ),
        })?;
        self.inner.pota.post_spot(&body).await?;
        self.inner
            .respot_times
            .lock()
            .expect("respot lock")
            .insert(body.activator.clone(), Instant::now());
        Ok(())
    }

    // ---- Per-callsign (activator) fetch ----

    /// One-shot per-callsign spot fetch — RBN (server-side `call=` filter)
    /// plus optionally POTA filtered to the activator, windowed to
    /// `minutes`, grid-enriched and sorted newest-first. Port of iOS
    /// `SpotsService.fetchSpots(for:minutes:)`; bypasses the global pool so
    /// activator sessions see their own spots even when they wouldn't crack
    /// the global RBN cap.
    pub async fn fetch_callsign_spots(
        &self,
        callsign: String,
        minutes: u32,
        include_pota: bool,
    ) -> Result<Vec<FfiEnrichedSpot>, CwError> {
        let cutoff = now_secs() - (minutes as i64) * 60;
        let mut spots: Vec<UnifiedSpot> = Vec::new();

        let rbn_spots = self.inner.rbn.fetch_spots_for_callsign(&callsign, 1, 50).await?;
        spots.extend(
            rbn_spots
                .iter()
                .filter_map(unified::from_rbn)
                .filter(|spot| spot.timestamp >= cutoff),
        );

        if include_pota {
            if let Ok(pota_spots) = self.inner.pota.fetch_spots().await {
                let target = cw_net::PotaSpot::normalize_callsign(&callsign);
                spots.extend(
                    pota_spots
                        .iter()
                        .filter(|spot| {
                            cw_net::PotaSpot::normalize_callsign(&spot.activator) == target
                        })
                        .filter_map(unified::from_pota)
                        .filter(|spot| spot.timestamp >= cutoff),
                );
            }
        }

        // Grid-enrich spotters via the shared HamDB cache (iOS
        // `enrichSpotsWithGrids`, skimmer suffix stripped, cap 15).
        let mut lookups = 0;
        for spot in spots.iter_mut() {
            if spot.spotter_grid.is_some() || lookups >= 15 {
                continue;
            }
            let Some(spotter) = spot.spotter.clone() else { continue };
            let base = spotter.split('-').next().unwrap_or(&spotter).to_uppercase();
            let cached = {
                let cache = self.inner.enrich_cache.lock().expect("enrich lock");
                // Expired entries don't satisfy the fast path (same TTL as
                // `load_enrich_cache`) — fall through to a live lookup that
                // overwrites them.
                let cutoff = now_secs() - ENRICH_CACHE_TTL_SECS;
                cache
                    .get(&base)
                    .filter(|entry| entry.fetched_at >= cutoff)
                    .map(|entry| entry.grid.clone())
            };
            let grid = match cached {
                Some(grid) => grid,
                None => {
                    lookups += 1;
                    let lookup = self.inner.hamdb.lookup(&base).await.ok().flatten();
                    let enrichment = CallsignEnrichment {
                        state: lookup.as_ref().and_then(|l| l.state.clone()),
                        country: lookup.as_ref().and_then(|l| l.country.clone()),
                        operator_name: lookup.as_ref().and_then(|l| l.name.clone()),
                        grid: lookup.as_ref().and_then(|l| l.grid.clone()),
                        fetched_at: now_secs(),
                    };
                    let grid = enrichment.grid.clone();
                    self.inner
                        .enrich_cache
                        .lock()
                        .expect("enrich lock")
                        .insert(base, enrichment);
                    grid
                }
            };
            if let Some(grid) = grid {
                if !grid.is_empty() {
                    spot.spotter_grid = Some(grid);
                }
            }
        }

        spots.sort_by(|a, b| b.timestamp.cmp(&a.timestamp).then_with(|| a.id.cmp(&b.id)));

        let user_grid = self.inner.user.read().expect("user lock").grid.clone();
        let cty = self.inner.cty.read().expect("cty lock").clone();
        Ok(spots
            .into_iter()
            .map(|spot| {
                let grid_for_geo =
                    spot.dx_grid.clone().or_else(|| spot.spotter_grid.clone());
                let region = SpotRegion::from_grid(grid_for_geo.as_deref());
                let (distance, bearing) = match (&user_grid, &grid_for_geo) {
                    (Some(user), Some(spot_grid)) => (
                        maidenhead::distance_km(user, spot_grid).map(|km| km * 1_000.0),
                        maidenhead::bearing(user, spot_grid),
                    ),
                    _ => (None, None),
                };
                let entity = cty.as_deref().and_then(|db| db.lookup(&spot.callsign));
                let mut enriched = EnrichedSpot::bare(spot, region);
                enriched.distance_meters = distance;
                enriched.bearing_degrees = bearing;
                enriched.dxcc_entity = entity.map(|e| e.name.clone());
                enriched.country = entity.map(|e| e.name.clone());
                FfiEnrichedSpot::from(&enriched)
            })
            .collect())
    }
}

/// Format a SQL string (the workbench Format button). Shared by both apps
/// so formatting stays byte-identical.
#[uniffi::export]
pub fn format_sql(sql: String) -> String {
    cw_domain::sql_format::format_sql(&sql)
}

/// Compile a goal profile + quick toggles into the Band Scope v2 per-lens
/// filter queries (run via `run_query`; see `cw_domain::spots::goal_profile`).
#[uniffi::export]
pub fn compile_profile_queries(
    profile: FfiGoalProfile,
    toggles: FfiQuickToggles,
) -> FfiCompiledProfileQueries {
    let compiled =
        cw_domain::spots::goal_profile::compile_profile_queries(&profile.into(), &toggles.into());
    FfiCompiledProfileQueries {
        scope_pass: compiled.scope_pass,
        heard_pass: compiled.heard_pass,
        wpm_dim: compiled.wpm_dim,
    }
}

// ---- Poll cycle ----

async fn poll_once(inner: &Arc<EngineInner>) {
    let config = inner.config.read().expect("config lock").clone();
    let fetch_start = now_secs();
    let enabled = |source: FfiSpotSource| config.enabled_sources.contains(&source);

    // Fetch all enabled HTTP sources concurrently, each independently
    // error-handled (Sweep's `fetchAllSpots`).
    let (rbn, pota, sota, wwff, dxs, dxh, dxw, pskr) = tokio::join!(
        fetch_rbn(inner, &config, enabled(FfiSpotSource::Rbn)),
        fetch_pota(inner, enabled(FfiSpotSource::Pota)),
        fetch_sota(inner, &config, enabled(FfiSpotSource::Sota)),
        fetch_wwff(inner, enabled(FfiSpotSource::Wwff)),
        fetch_dxsummit(inner, &config, enabled(FfiSpotSource::DxSummit)),
        fetch_dxheat(inner, &config, enabled(FfiSpotSource::DxHeat)),
        fetch_dxwatch(inner, &config, enabled(FfiSpotSource::DxWatch)),
        fetch_pskr(inner, enabled(FfiSpotSource::Pskr)),
    );

    let batches = [rbn, pota, sota, wwff, dxs, dxh, dxw, pskr];
    {
        let mut pool = inner.pool.lock().expect("pool lock");
        for batch in batches {
            if batch.is_empty() {
                continue;
            }
            record_observations(inner, &batch);
            pool.merge(batch);
        }
        pool.prune_expired(now_secs(), config.max_spot_age_secs as i64);
    }
    let _ = inner
        .scope
        .prune_scope(now_secs() as f64, config.max_spot_age_secs as f64);

    // Publish the merged pool immediately — spots reach the UI in fetch
    // time — then run one bounded HamDB enrichment batch (converges over
    // cycles) and publish again only if it added anything.
    inner.last_refresh.store(fetch_start, Ordering::SeqCst);
    publish(inner);

    if enrich_callsign_batch(inner).await {
        publish(inner);
    }
}

macro_rules! fetch_source {
    ($inner:expr, $source:expr, $result:expr, $map:expr) => {{
        match $result {
            Ok(items) => {
                $inner.errors.lock().expect("errors lock").remove(&$source);
                items.iter().filter_map($map).collect()
            }
            Err(err) => {
                $inner
                    .errors
                    .lock()
                    .expect("errors lock")
                    .insert($source, err.to_string());
                Vec::new()
            }
        }
    }};
}

async fn fetch_rbn(
    inner: &EngineInner,
    config: &FfiSpotEngineConfig,
    enabled: bool,
) -> Vec<UnifiedSpot> {
    if !enabled {
        return Vec::new();
    }
    fetch_source!(
        inner,
        SpotSource::Rbn,
        inner.rbn.fetch_spots(config.rbn_limit).await,
        unified::from_rbn
    )
}

async fn fetch_pota(inner: &EngineInner, enabled: bool) -> Vec<UnifiedSpot> {
    if !enabled {
        return Vec::new();
    }
    fetch_source!(
        inner,
        SpotSource::Pota,
        inner.pota.fetch_spots().await,
        unified::from_pota
    )
}

/// Global SOTA kill-switch: the SOTAwatch v2 API shuts down 2026-08-31 and
/// its replacement (api-db2) requires prior approval under its terms of
/// service before any client may connect. Flip back to `false` once the
/// migration to the new API lands.
const SOTA_FETCH_DISABLED: bool = true;

async fn fetch_sota(
    inner: &EngineInner,
    config: &FfiSpotEngineConfig,
    enabled: bool,
) -> Vec<UnifiedSpot> {
    if SOTA_FETCH_DISABLED || !enabled {
        return Vec::new();
    }
    fetch_source!(
        inner,
        SpotSource::Sota,
        inner.sota.fetch_spots(config.sota_count, None).await,
        unified::from_sota
    )
}

async fn fetch_wwff(inner: &EngineInner, enabled: bool) -> Vec<UnifiedSpot> {
    if !enabled {
        return Vec::new();
    }
    fetch_source!(
        inner,
        SpotSource::Wwff,
        inner.wwff.fetch_spots().await,
        unified::from_wwff
    )
}

async fn fetch_dxsummit(
    inner: &EngineInner,
    config: &FfiSpotEngineConfig,
    enabled: bool,
) -> Vec<UnifiedSpot> {
    if !enabled {
        return Vec::new();
    }
    let now = now_secs();
    fetch_source!(
        inner,
        SpotSource::DxSummit,
        inner.dxsummit.fetch_spots(config.dx_web_limit).await,
        |spot| Some(unified::from_dxsummit(spot, now))
    )
}

async fn fetch_dxheat(
    inner: &EngineInner,
    config: &FfiSpotEngineConfig,
    enabled: bool,
) -> Vec<UnifiedSpot> {
    if !enabled {
        return Vec::new();
    }
    let now = now_secs();
    fetch_source!(
        inner,
        SpotSource::DxHeat,
        inner.dxheat.fetch_spots(config.dx_web_limit).await,
        |spot| unified::from_dxheat(spot, now)
    )
}

async fn fetch_dxwatch(
    inner: &EngineInner,
    config: &FfiSpotEngineConfig,
    enabled: bool,
) -> Vec<UnifiedSpot> {
    if !enabled {
        return Vec::new();
    }
    let now = now_secs();
    match inner.dxwatch.fetch_spots(config.dx_web_limit).await {
        Ok(response) => {
            inner.errors.lock().expect("errors lock").remove(&SpotSource::DxWatch);
            response
                .spots
                .iter()
                .map(|spot| {
                    unified::from_dxwatch(spot, response.call_info.get(&spot.dx_call), now)
                })
                .collect()
        }
        Err(err) => {
            inner
                .errors
                .lock()
                .expect("errors lock")
                .insert(SpotSource::DxWatch, err.to_string());
            Vec::new()
        }
    }
}

/// FT8 dial frequencies the PSKR fetch rotates through (iOS
/// `ft8BandRanges`, ±3 kHz window).
const PSKR_FT8_DIALS_HZ: [i64; 6] =
    [14_074_000, 7_074_000, 21_074_000, 28_074_000, 18_100_000, 50_313_000];
const PSKR_SPREAD_HZ: i64 = 3_000;

async fn fetch_pskr(inner: &EngineInner, enabled: bool) -> Vec<UnifiedSpot> {
    if !enabled {
        return Vec::new();
    }
    // Rotate through bands per cycle (PSK Reporter enforces a 5-minute
    // per-instance floor inside the client; denied cycles return empty).
    let rotation = inner.pskr_rotation.fetch_add(1, Ordering::SeqCst);
    let dial = PSKR_FT8_DIALS_HZ[rotation % PSKR_FT8_DIALS_HZ.len()];
    match inner
        .pskr
        .fetch_spots("FT8", dial - PSKR_SPREAD_HZ, dial + PSKR_SPREAD_HZ, -1_800, 100)
        .await
    {
        Ok(spots) => {
            inner.errors.lock().expect("errors lock").remove(&SpotSource::Pskr);
            // Dedup by sender — keep only the newest report per station
            // (iOS `deduplicatePSKRSpots`).
            let mut sorted = spots;
            sorted.sort_by_key(|spot| std::cmp::Reverse(spot.flow_start_seconds));
            let mut seen = std::collections::HashSet::new();
            sorted
                .iter()
                .filter(|spot| seen.insert(spot.sender_callsign.to_uppercase()))
                .map(unified::from_pskr)
                .collect()
        }
        Err(cw_net::HttpError::RateLimited) => Vec::new(),
        Err(err) => {
            inner
                .errors
                .lock()
                .expect("errors lock")
                .insert(SpotSource::Pskr, err.to_string());
            Vec::new()
        }
    }
}

// ---- Observations ----

fn record_observations(inner: &EngineInner, spots: &[UnifiedSpot]) {
    let cty = inner.cty.read().expect("cty lock").clone();
    let rows: Vec<_> = spots
        .iter()
        .map(|spot| {
            let entity = cty.as_deref().and_then(|db| db.lookup(&spot.callsign));
            observations::observation_row(
                spot,
                spot.source.merge_priority() as i32,
                entity,
                uuid::Uuid::new_v4().to_string(),
            )
        })
        .collect();
    let _ = inner.scope.record_observations(&rows);

    // Tier 1 — CTY prefix lookup for the spotter (centroid + continent).
    // When CTY gives no coords but the spot carries a spotter grid, use the
    // grid centre (beats nothing; a HamDB tier-2 pass can refine later).
    for spot in spots {
        let entity = spot
            .spotter
            .as_deref()
            .and_then(|call| cty.as_deref().and_then(|db| db.lookup(call)));
        if let Some(mut row) = observations::spotter_row(spot, entity) {
            if row.lat.is_none() {
                if let Some(coord) =
                    row.grid.as_deref().and_then(maidenhead::coordinate_from_grid)
                {
                    row.lat = Some(coord.latitude);
                    row.lon = Some(coord.longitude);
                }
            }
            let _ = inner.scope.upsert_spotter(&row);
        }
    }
}

// ---- Enrichment ----

/// One bounded batch of HamDB lookups per poll cycle (max 20, Sweep's
/// batch size). Results land in the enrichment cache consumed by
/// `publish`.
async fn enrich_callsign_batch(inner: &Arc<EngineInner>) -> bool {
    let batch: Vec<String> = {
        let pool = inner.pool.lock().expect("pool lock");
        let cache = inner.enrich_cache.lock().expect("enrich lock");
        let mut seen = std::collections::HashSet::new();
        // The TTL must gate in-session reads too, not just `load_enrich_cache`
        // — a long-running process would otherwise serve a stale operator
        // name/grid forever. Expired entries count as absent so this batch
        // re-fetches and overwrites them.
        let cutoff = now_secs() - ENRICH_CACHE_TTL_SECS;
        pool.snapshot()
            .into_iter()
            .map(|spot| spot.callsign.to_uppercase())
            .filter(|call| {
                let fresh = cache.get(call).is_some_and(|entry| entry.fetched_at >= cutoff);
                !fresh && seen.insert(call.clone())
            })
            .take(20)
            .collect()
    };
    if batch.is_empty() {
        return false;
    }

    // Lookups run concurrently (semaphore-capped) — serially each batch
    // took ~15 s of wall clock at ~0.75 s per HamDB round trip.
    let semaphore = Arc::new(tokio::sync::Semaphore::new(ENRICH_CONCURRENCY));
    let mut tasks = tokio::task::JoinSet::new();
    for call in batch {
        let hamdb = inner.hamdb.clone();
        let semaphore = Arc::clone(&semaphore);
        tasks.spawn(async move {
            let _permit = semaphore.acquire_owned().await;
            let lookup = hamdb.lookup(&call).await.ok().flatten();
            (call, lookup)
        });
    }

    let fetched_at = now_secs();
    let mut results: HashMap<String, CallsignEnrichment> = HashMap::new();
    while let Some(joined) = tasks.join_next().await {
        let Ok((call, lookup)) = joined else { continue };
        let enrichment = match lookup {
            Some(info) => CallsignEnrichment {
                state: info.state,
                country: info.country,
                operator_name: info.name,
                grid: info.grid,
                fetched_at,
            },
            // Negative results are cached too so we don't re-query.
            None => CallsignEnrichment { fetched_at, ..Default::default() },
        };
        results.insert(call, enrichment);
    }
    let added = !results.is_empty();
    inner.enrich_cache.lock().expect("enrich lock").extend(results);
    if added {
        save_enrich_cache(inner);
    }
    added
}

/// Read + TTL-prune a persisted enrichment cache. Missing or malformed
/// files are an empty cache, never an error.
fn load_enrich_cache(path: &std::path::Path) -> HashMap<String, CallsignEnrichment> {
    let Ok(raw) = std::fs::read_to_string(path) else {
        return HashMap::new();
    };
    let Ok(map) = serde_json::from_str::<HashMap<String, CallsignEnrichment>>(&raw) else {
        return HashMap::new();
    };
    let cutoff = now_secs() - ENRICH_CACHE_TTL_SECS;
    map.into_iter().filter(|(_, entry)| entry.fetched_at >= cutoff).collect()
}

/// Write the cache to the configured path (atomic tmp + rename), keeping
/// the newest `ENRICH_CACHE_MAX_ENTRIES`. No-op when no path is set.
fn save_enrich_cache(inner: &EngineInner) {
    let Some(path) = inner.enrich_cache_path.read().expect("enrich path lock").clone() else {
        return;
    };
    let mut entries: Vec<(String, CallsignEnrichment)> = {
        let cache = inner.enrich_cache.lock().expect("enrich lock");
        cache.iter().map(|(call, entry)| (call.clone(), entry.clone())).collect()
    };
    if entries.len() > ENRICH_CACHE_MAX_ENTRIES {
        entries.sort_by_key(|(_, entry)| std::cmp::Reverse(entry.fetched_at));
        entries.truncate(ENRICH_CACHE_MAX_ENTRIES);
    }
    let map: HashMap<String, CallsignEnrichment> = entries.into_iter().collect();
    let Ok(json) = serde_json::to_string(&map) else {
        return;
    };
    let tmp = path.with_extension("json.tmp");
    if std::fs::write(&tmp, json).is_ok() {
        let _ = std::fs::rename(&tmp, &path);
    }
}

/// Rebuild the enriched list from the pool + caches, run needs matching,
/// re-evaluate the band-scope query, bump the generation, and notify.
/// Port of Sweep's `enrichAndPublish` + iOS's `SpotNeedsMatcher.match`.
fn publish(inner: &Arc<EngineInner>) {
    let user_grid = inner.user.read().expect("user lock").grid.clone();
    let cty = inner.cty.read().expect("cty lock").clone();
    let cache = inner.enrich_cache.lock().expect("enrich lock").clone();
    let needs = inner.needs.read().expect("needs lock").clone();

    let unified_spots = inner.pool.lock().expect("pool lock").snapshot();
    let mut enriched: Vec<EnrichedSpot> = unified_spots
        .into_iter()
        .map(|mut spot| {
            let cached = cache.get(&spot.callsign.to_uppercase());
            // Apply cached grid if the spot has no DX grid.
            if spot.dx_grid.is_none() {
                if let Some(grid) = cached.and_then(|c| c.grid.clone()) {
                    if !grid.is_empty() {
                        spot.dx_grid = Some(grid);
                    }
                }
            }
            let grid_for_geo = spot.dx_grid.clone().or_else(|| spot.spotter_grid.clone());
            let region = SpotRegion::from_grid(grid_for_geo.as_deref());
            let (distance, bearing) = match (&user_grid, &grid_for_geo) {
                (Some(user), Some(spot_grid)) => (
                    maidenhead::distance_km(user, spot_grid).map(|km| km * 1_000.0),
                    maidenhead::bearing(user, spot_grid),
                ),
                _ => (None, None),
            };
            let entity = cty.as_deref().and_then(|db| db.lookup(&spot.callsign));
            let needed = derive_needed_status(&spot, entity, needs.as_ref());

            let mut result = EnrichedSpot::bare(spot, region);
            result.distance_meters = distance;
            result.bearing_degrees = bearing;
            result.state = result
                .spot
                .state_abbr
                .clone()
                .or_else(|| cached.and_then(|c| c.state.clone()));
            result.country = entity
                .map(|e| e.name.clone())
                .or_else(|| cached.and_then(|c| c.country.clone()));
            result.dxcc_entity = entity.map(|e| e.name.clone());
            result.needed_status = needed;
            result.operator_name = cached.and_then(|c| c.operator_name.clone());
            result
        })
        .collect();

    if let Some((snapshot, prefs)) = &needs {
        enriched = needs::match_spots(enriched, snapshot, *prefs, cty.as_deref());
    }

    // Project matched needs into scope.spot_needs so goal-profile SQL can
    // reference "needed" state. Rewritten wholesale every publish (and
    // cleared when needs matching is off — an empty table is the truth).
    let need_rows: Vec<super::scope_db::ScopeSpotNeedRow> = enriched
        .iter()
        .flat_map(|spot| {
            spot.matched_needs.iter().map(|need| super::scope_db::ScopeSpotNeedRow {
                spot_id: spot.spot.id.clone(),
                category: need.category.key().to_string(),
                label: need.label.clone(),
                priority: need.priority as i64,
            })
        })
        .collect();
    let _ = inner.scope.replace_spot_needs(&need_rows);

    *inner.enriched.write().expect("enriched lock") = enriched;
    inner.refresh_allowed_ids();
    let generation = inner.generation.fetch_add(1, Ordering::SeqCst) + 1;
    if let Some(listener) = inner.listener.read().expect("listener lock").clone() {
        listener.on_spots_updated(generation);
    }
}

/// Needed status from the host-fed needs snapshot: matches Sweep's
/// `DXCCNeededChecker` semantics against the snapshot's worked sets.
/// (Confirmation data isn't in the snapshot, so "worked" maps to
/// `WorkedNotConfirmed`.)
fn derive_needed_status(
    spot: &UnifiedSpot,
    entity: Option<&cw_domain::cty::DxccEntity>,
    needs: Option<&(NeedsSnapshot, NeedsPreferences)>,
) -> NeededStatus {
    let (Some(entity), Some((snapshot, _))) = (entity, needs) else {
        return NeededStatus::Unknown;
    };
    let prefix = &entity.primary_prefix;
    if !snapshot.dxcc.all_time_worked.contains(prefix) {
        return NeededStatus::NewEntity;
    }
    let band = spot.band();
    if band.is_empty() {
        return NeededStatus::WorkedNotConfirmed;
    }
    let key = cw_domain::spots::needs::BandSlotKey {
        entity: prefix.clone(),
        band: band.to_string(),
    };
    if !snapshot.dxcc.band_slots_worked.contains(&key) {
        return NeededStatus::NewBandSlot;
    }
    NeededStatus::WorkedNotConfirmed
}

impl EngineInner {
    fn refresh_allowed_ids(&self) {
        let sql = self.band_scope_sql.read().expect("band scope lock").clone();
        let allowed = sql.and_then(|sql| self.scope.allowed_spot_ids(&sql).ok());
        *self.allowed_ids.write().expect("allowed lock") = allowed;
    }
}

// ---- Cluster manager ----

/// Long-running cluster manager: connect → forward events → periodic
/// SH/WWV + SH/FILTER → reconnect with backoff. Exits when the desire is
/// cleared or a newer epoch supersedes this task (`connect_cluster` bumps
/// the epoch per call).
async fn run_cluster(inner: Arc<EngineInner>, epoch: u64) {
    let mut backoff_secs = 5u64;
    loop {
        if inner.cluster_epoch.load(Ordering::SeqCst) != epoch {
            return;
        }
        let Some((host, port, login)) = ({
            let desired = inner.cluster_desired.lock().expect("cluster lock");
            desired.as_ref().map(|d| (d.host.clone(), d.port, d.login.clone()))
        }) else {
            return;
        };

        match cluster::connect(&host, port, &login).await {
            Ok((conn, mut events)) => {
                backoff_secs = 5;
                notify_cluster_state(&inner, true);
                let mut query_timer =
                    tokio::time::interval(Duration::from_secs(300));
                query_timer.set_missed_tick_behavior(
                    tokio::time::MissedTickBehavior::Delay,
                );
                query_timer.tick().await; // first tick fires immediately
                let _ = conn.send("SH/WWV");
                let _ = conn.send("SH/FILTER");

                loop {
                    if inner.cluster_epoch.load(Ordering::SeqCst) != epoch {
                        conn.disconnect();
                        notify_cluster_state(&inner, false);
                        return;
                    }
                    tokio::select! {
                        event = events.recv() => match event {
                            Some(cluster::ClusterEvent::Line(line)) => {
                                if let Some(listener) =
                                    inner.listener.read().expect("listener lock").clone()
                                {
                                    listener.on_cluster_line(line);
                                }
                            }
                            Some(cluster::ClusterEvent::Spot(spot)) => {
                                let unified_spot = unified::from_cluster(&spot);
                                record_observations(&inner, std::slice::from_ref(&unified_spot));
                                inner
                                    .pool
                                    .lock()
                                    .expect("pool lock")
                                    .merge_cluster(vec![unified_spot]);
                                publish(&inner);
                            }
                            Some(cluster::ClusterEvent::Disconnected { .. }) | None => {
                                break;
                            }
                        },
                        _ = query_timer.tick() => {
                            let _ = conn.send("SH/WWV");
                            let _ = conn.send("SH/FILTER");
                        }
                    }
                }
                notify_cluster_state(&inner, false);
            }
            Err(_) => {
                notify_cluster_state(&inner, false);
            }
        }

        // Reconnect with capped exponential backoff while still desired.
        tokio::time::sleep(Duration::from_secs(backoff_secs)).await;
        backoff_secs = (backoff_secs * 2).min(60);
    }
}

fn notify_cluster_state(inner: &Arc<EngineInner>, connected: bool) {
    if let Some(listener) = inner.listener.read().expect("listener lock").clone() {
        listener.on_cluster_state(connected);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn engine() -> SpotEngineApi {
        SpotEngineApi::new(FfiSpotEngineConfig::default()).unwrap()
    }

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

    /// Test-only ingest: merge + observations + publish without network.
    fn ingest(api: &SpotEngineApi, spots: Vec<UnifiedSpot>) {
        record_observations(&api.inner, &spots);
        api.inner.pool.lock().unwrap().merge(spots);
        publish(&api.inner);
    }

    #[test]
    fn enrichment_cache_persists_and_prunes_by_ttl() {
        let dir = std::env::temp_dir().join(format!("cw-enrich-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("cache.json");

        let mut map = HashMap::new();
        map.insert(
            "W1AW".to_string(),
            CallsignEnrichment {
                state: Some("CT".into()),
                country: Some("United States".into()),
                operator_name: Some("ARRL".into()),
                grid: Some("FN31".into()),
                fetched_at: now_secs(),
            },
        );
        map.insert(
            "K6OLD".to_string(),
            CallsignEnrichment {
                fetched_at: now_secs() - ENRICH_CACHE_TTL_SECS - 60,
                ..Default::default()
            },
        );
        std::fs::write(&path, serde_json::to_string(&map).unwrap()).unwrap();

        // Loading merges fresh entries and drops expired ones.
        let api = engine();
        api.set_enrichment_cache_path(path.to_string_lossy().to_string());
        {
            let cache = api.inner.enrich_cache.lock().unwrap();
            assert_eq!(
                cache.get("W1AW").and_then(|entry| entry.grid.clone()).as_deref(),
                Some("FN31")
            );
            assert!(!cache.contains_key("K6OLD"));
        }

        // Saving rewrites the file with the surviving entries only.
        save_enrich_cache(&api.inner);
        let reloaded = load_enrich_cache(&path);
        assert!(reloaded.contains_key("W1AW"));
        assert!(!reloaded.contains_key("K6OLD"));

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn ingest_publish_snapshot_round_trip() {
        let api = engine();
        api.set_user_context(Some("DM04".to_string()), "W6JY".to_string());
        let now = now_secs();
        let mut s1 = spot("rbn-1", "JA1ABC", 14_040.0, now, SpotSource::Rbn);
        s1.spotter = Some("W3LPL".to_string());
        s1.spotter_grid = Some("FM19".to_string());
        ingest(&api, vec![s1, spot("pota-1", "W1AW", 7_040.0, now, SpotSource::Pota)]);

        let snapshot = api.snapshot(None, None);
        assert_eq!(snapshot.spots.len(), 2);
        assert!(snapshot.generation >= 1);
        // Spot with a spotter grid gets region + distance.
        let ja = snapshot.spots.iter().find(|s| s.callsign == "JA1ABC").unwrap();
        assert!(ja.distance_meters.is_some());
        assert_ne!(ja.region, "");
    }

    #[test]
    fn snapshot_filter_applies() {
        let api = engine();
        let now = now_secs();
        ingest(&api, vec![
            spot("rbn-1", "JA1ABC", 14_040.0, now, SpotSource::Rbn),
            spot("pota-1", "W1AW", 7_040.0, now, SpotSource::Pota),
        ]);
        let filter = FfiSpotFilter {
            sources: vec![FfiSpotSource::Pota],
            ..FfiSpotFilter::default()
        };
        let snapshot = api.snapshot(Some(filter), None);
        assert_eq!(snapshot.spots.len(), 1);
        assert_eq!(snapshot.spots[0].callsign, "W1AW");
    }

    #[test]
    fn observations_land_in_scope_and_band_scope_query_filters() {
        let api = engine();
        let now = now_secs();
        ingest(&api, vec![
            spot("rbn-1", "JA1ABC", 14_040.0, now, SpotSource::Rbn),
            spot("rbn-2", "W1AW", 7_040.0, now, SpotSource::Rbn),
        ]);
        let result = api
            .run_query("SELECT callsign FROM scope.spots ORDER BY callsign".to_string(), 10)
            .unwrap();
        assert_eq!(result.rows.len(), 2);

        api.set_band_scope_query(Some(
            "SELECT spot_id FROM scope.spots WHERE band = '20m'".to_string(),
        ))
        .unwrap();
        let snapshot = api.snapshot(None, None);
        let allowed = snapshot.allowed_spot_ids.unwrap();
        assert_eq!(allowed, vec!["rbn-1".to_string()]);

        // Clearing the query clears the allow-list.
        api.set_band_scope_query(None).unwrap();
        assert!(api.snapshot(None, None).allowed_spot_ids.is_none());
    }

    #[test]
    fn needs_snapshot_drives_matches_and_needed_status() {
        let api = engine();
        api.set_cty_database(
            "Japan:                    25:  45:  AS:   36.40:  -138.38:    -9.0:  JA:\n    JA,JE,7J;\n"
                .to_string(),
        );
        api.set_needs_snapshot(Some(FfiNeedsSnapshot {
            track_dxcc: true,
            track_was: true,
            track_pota_hunter: true,
            track_wwff_hunter: true,
            ..FfiNeedsSnapshot::default()
        }));
        let now = now_secs();
        ingest(&api, vec![spot("rbn-1", "JA1ABC", 14_040.0, now, SpotSource::Rbn)]);

        let snapshot = api.snapshot(None, None);
        let ja = &snapshot.spots[0];
        assert_eq!(ja.needed_status, FfiNeededStatus::NewEntity);
        assert!(ja
            .matched_needs
            .iter()
            .any(|need| need.kind == FfiNeedKind::DxccEntity));
    }

    #[test]
    fn query_error_carries_position() {
        let api = engine();
        let err = api
            .run_query("SELECT bogus FROM scope.spots".to_string(), 10)
            .unwrap_err();
        let SpotQueryError::Query { reason, .. } = err;
        assert!(reason.contains("bogus") || reason.contains("no such column"));
    }

    #[test]
    fn format_sql_export_works() {
        let formatted = format_sql("select a from b where c = 1".to_string());
        assert!(formatted.starts_with("SELECT"));
    }

    #[test]
    fn qso_mirror_supports_workbench_joins() {
        let api = engine();
        api.mirror_qsos(vec![FfiScopeQso {
            id: "q1".to_string(),
            callsign: "W1AW".to_string(),
            band: "20m".to_string(),
            mode: "CW".to_string(),
            frequency: Some(14.04),
            timestamp: 1_000.0,
            my_callsign: "W6JY".to_string(),
            their_grid: None,
            my_grid: None,
            park_ref: None,
            their_park_ref: None,
            dxcc: None,
            modified_at: None,
            is_hidden: false,
            is_activity_log: false,
        }])
        .unwrap();
        let result = api
            .run_query("SELECT COUNT(*) FROM qsos".to_string(), 1)
            .unwrap();
        assert_eq!(result.rows[0].values[0].as_deref(), Some("1"));
    }
}
