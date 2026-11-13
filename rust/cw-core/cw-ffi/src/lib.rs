//! Carrier Wave UniFFI surface — the single cross-language boundary.
//!
//! Everything callable from Swift/Kotlin is defined here and nowhere else, so
//! the binding surface stays small and auditable (per the migration plan §5).
//! Generating the actual Swift/Kotlin bindings + XCFramework is an
//! Xcode/Android-toolchain step (`uniffi-bindgen`), run outside this container;
//! this crate compiles the scaffolding the generated bindings call into.
//!
//! Design notes that the plan calls out:
//! - We expose **value DTOs**, never live store rows.
//! - Queries are **bounded** (`limit` is validated against `MAX_FETCH_LIMIT`).
//! - The store object wraps the connection in a `Mutex` so it is `Send + Sync`
//!   as UniFFI objects require; the encryption key is passed in by the host.

use std::sync::Mutex;

use cw_domain::maidenhead::{self, Coordinate};
use cw_domain::query::{self, QueryCost, Severity};
use cw_store::{Qso, QsoFilter, Store};

uniffi::setup_scaffolding!();

/// Per-entity FFI surface: each module adds its `FfiX` DTOs + `From` conversions
/// and an `#[uniffi::export] impl FieldStore` block delegating to `cw-store`.
mod entities;

/// Quick-entry parser surface (`cw_domain::quick_entry`) — the logger command
/// bar grammar, shared by Swift and Kotlin.
mod logger_command;
mod logger_command_handler;
mod quick_entry;

/// Super Check Partial database surface (`cw_domain::scp`) — the loaded
/// MASTER.SCP callsign matcher, shared by Swift and Kotlin.
mod scp;

/// MASTER.SCP download + kv cache (`ScpApi`) — the host side of iOS
/// `SCPService`, for hosts without their own networking (Android).
mod scp_api;

/// SKCC roster parsing surface (`cw_domain::skcc`) — pipe-delimited roster
/// parser + award resolution + by-callsign index.
mod skcc;

/// Ham2K Polo callsign-notes parsing surface (`cw_domain::polo_notes`).
mod polo_notes;

/// Reverse Beacon Network spot decoding surface (`cw_net::rbn`).
mod rbn;

/// CAT radio-control protocol surface (`cw_domain::civ` / `kenwood` / `yaesu`) —
/// CI-V / Kenwood / Yaesu command builders + response parsers, shared by Swift
/// and Kotlin.
mod cat;

/// Spot decoding surfaces (`cw_net::pota` / `sota` / `wwff` / `pskreporter`).
/// These join `rbn` as the cross-platform spot decoders so each app presents
/// spots identically.
mod pota;
mod sota;
mod wwff;
mod pskreporter;

/// ADIF parse / validate / catalog surface (`cw_domain::adif`,
/// `cw_domain::adif_validator`, `cw_domain::adif_catalog`) — ADIF tokenizing,
/// field validation, and the band/mode/submode tables shared across platforms.
mod adif;

/// Band derivation, mode classification, and US band-plan surface
/// (`cw_domain::band` / `cw_domain::mode` / `cw_domain::band_plan`).
mod band_mode;
mod frequency_scope;

/// Callsign extraction / primary-detection + edit-distance surface
/// (`cw_domain::callsign_detector` + `cw_domain::callsign_edit_distance`). The
/// `CWTextElement` rendering path stays Swift-side (UI-only).
mod callsign;

/// CTY.dat DXCC database surface (`cw_domain::cty`) — parsed prefix→entity table
/// with longest-prefix / portable-indicator lookup, exposed as an Object
/// (modeled on `scp`).
mod cty;

/// Async clubs API surface (`cw_net::ClubsClient`) — fetch→parse→store→cache,
/// the first networking exposed over async UniFFI. Shared by Swift and Kotlin.
mod clubs_api;

/// Async friends + activity-feed API (`cw_net::FriendsClient`) — social graph
/// reconcile into the store plus the on-demand feed. Shared by Swift and Kotlin.
mod friends_api;

/// Async OAuth surface (`cw_net::AuthClient`) — PKCE login + token lifecycle,
/// with secret storage delegated to a host-implemented `SecureStore`.
mod auth_api;

/// Another Morse Trainer stats (`cw_net::AmtClient`) — email-link sign-in,
/// token rotation and the read-only practice-stats fetch (streak + activity
/// calendar), with tokens and the offline snapshot in the host `SecureStore`.
mod amt_api;

/// Async spot-monitoring API (`cw_net` POTA/RBN/SOTA/WWFF clients) — live spot
/// feeds returning the same `Ffi*Spot` records as the `decode_*` functions.
mod spots_api;

/// Async QRZ callbook enrichment (`cw_net::QrzClient`) — name / QTH / grid
/// lookup, credentials delegated to the host `SecureStore`.
mod qrz_api;

/// Callsign enrichment (`cw_domain::cty` + `cw_domain::skcc` + store clubs) —
/// DXCC entity / SKCC membership / club badges, with the reference datasets
/// fetched + cached in the store.
mod enrichment_api;

/// Gear logic (`EquipmentApi`) — fuzzy catalog search (the `CatalogMatcher`
/// port) + equipment construction (custom + catalog items), persisted through
/// `FieldStore`. Reads the catalog JSON cached by `ReferenceDataApi`.
mod equipment_api;

/// External Data downloads (`ReferenceDataApi`) — POTA parks, SOTA summits,
/// the WWFF directory, the equipment catalog, the FCC callsign database, and
/// SOTA activation zones, with freshness bookkeeping in the store's kv.
mod reference_data_api;

/// Hunter-log lifecycle + QSO logging (`ActivityLogManager` port) — single
/// active log, log_qso enrichment, upload routing, today stats. Shared by Swift
/// and Kotlin.
mod activity_log_api;

/// Hunter-log pure helpers (`cw_domain::hunter_log`): primary-callsign
/// extraction, the worked-before dedup key, and FT8 DXCC derivation.
mod hunter_log;

/// Shared upload-routing rule (`QSO.markNeedsUpload` port) used by both the
/// hunter-log and session APIs.
mod upload;

/// Activation session lifecycle + QSO logging (`LoggingSessionManager` port) —
/// pause/resume/end/reopen, session-stamped log_qso, merge. Shared by Swift and
/// Kotlin.
mod session_api;

/// Session-start **wizard** assembly (`SessionWizardApi`): the portable kernel
/// behind the iOS `SessionStartSheet` "Start" action — callsign construction,
/// activation-type derivation, program encoding, reference conditioning,
/// mode-gated gear, row defaults, plus the `loggerDefault*` wizard prefill store.
mod session_wizard_api;

/// Brag Sheet API: catalog/category/preset metadata, `kv`-persisted
/// configuration, and `compute_brag` (dispatches to
/// `Store::compute_configured_brag` + overlays the club-roster stats).
mod brag_sheet_api;

/// Async SDR (KiwiSDR) API: directory search, `/status` enrichment, Tune-In
/// candidate selection, live audio streaming via callback, and the QSY /
/// receiver-quality monitors (`Services/WebSDR/` port).
mod sdr_api;

/// SDR IQ panadapter / waterfall (`cw_sdr`): rtl_tcp / SoapySDR / tone
/// sources, FFT spectrum, and IF-tap or direct-RF mapping driven by CAT state.
mod panadapter_api;

/// WSJT-X UDP listener (`cw_net::wsjtx`) + message records + the
/// `cw_store::wsjtx_import` mapping helpers: `WsjtxApi` start/stop with a
/// host-implemented `WsjtxListenerDelegate` receiving decoded events
/// (CAR-281; app wiring is CAR-282).
mod wsjtx_api;

/// Contest engine + definitions (`cw_domain::contest` + `cw_net::ContestsClient`
/// + the `contest_definition` cache): the `ContestApi` fetch/cache surface, the
/// stateful `ContestEngineApi` scorer, and stateless exchange-parse / Cabrillo /
/// schedule / off-time / band-change / WPX helpers. Replaces the Swift contest
/// engine (plan `docs/plans/2026-07-04-contest-engine-rust-port.md`).
mod contest_api;

/// Shared spots engine: poll loop over all spot sources, telnet cluster
/// manager, merge/enrich/needs pipeline, in-memory scope SQL projection +
/// query surface, `format_sql` (Sweep `SpotAggregator`/`ClusterManager` +
/// iOS `SpotMonitoringService` port; plan
/// `docs/plans/2026-07-02-spots-engine-rust-port.md`).
mod spot_engine;

/// Shared map view-model: QSO map annotations/clusters/arcs/bounds/stats
/// plus free geo helpers (great-circle segments, map bounds, tile bounds).
mod map_api;

/// Themed share-map rasterizer (`cw_domain::share_render`): the free
/// `render_share_map` export mapping an `FfiShareMapInput` onto the flat /
/// azimuthal renderers by `FfiShareMapStyle`, returning PNG bytes + azimuthal
/// ring-label anchors. Store-less; the iOS `FlatMapRenderer` /
/// `AzimuthalMapRenderer` orchestration (map port phase D).
mod share_render_api;

/// Store-backed ADIF export (`AdifApi`): the POTA single-activation bulk-export
/// path (`ADIFExportService.generateADIF` + `ADIFExportSheet`), assembling
/// `cw_domain::adif_writer` records from `qso` rows scoped to a
/// (park, callsign, UTC date) activation (map port phase D).
mod adif_api;

/// Reference-map API (`ParkMapApi`) — the shared core behind the iOS
/// `ParkSearchMapView` / Android park-map screen: viewport pins
/// (POTA/SOTA/WWFF), unified reference search, cache-through GIS boundary
/// fetch (parks/trails/admin), the WWFF-borrows-POTA loan, cached SOTA zones,
/// the activation-multiplier rosette scan, and free TOTA-tile / point-in-ring
/// exports.
mod park_map_api;

/// Shared propagation-check session engine (`PropagationApi`) — the "How's my
/// antenna?" live ingestion loop (map port phase D). Polls RBN (activities
/// proxy) + PSK Reporter, windows/dedups spots against the frozen config,
/// enriches missing skimmer grids via the callbook cache + QRZ→HamDB locate
/// flow, and finalizes headline results. Port of `PropagationCheckSession`
/// (+`+Polling`), the `PropagationCheck*` models, and
/// `PropagationCheckEnrichment`.
mod propagation_api;

/// Shared satellite tracking surface (`cw_domain::satellite` +
/// `cw_net::{satnogs,amsat}` + `cw_store::satellite_cache`): cache-through
/// refresh, catalog/positions/looks, pass forecasts, mutual planning, and
/// pass-alert planning. Rust-first replacement for the iOS Swift satellite
/// engine; Android's first consumer.
mod satellite_api;

/// Cross-entity sync-journal dirty-flag ops (`cw_store::sync_dirty`):
/// `mark_all_dirty` / `clear_dirty`, keyed by `JournalEntityType` raw value.
mod sync;

/// E2E escrow + HTTPS sync-transport driver surface (`cw_crypto::escrow`,
/// `cw_sync::HttpSyncTransport`): passphrase escrow create/open and a one-shot
/// pull-merge-push driver over the dumb append-only sync log.
mod sync_transport;

use entities::service_presence::FfiServicePresence;

/// Store observation API: the UniFFI callback bridge that replaces SwiftData
/// `@Query` reactivity. Adds `StoreObserver` + `add_observer`/`remove_observer`.
mod observation;

use observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable, ObserverRegistry};

// ---------- Errors ----------

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CwError {
    // Field is named `reason` (not `message`) because UniFFI's Kotlin codegen
    // generates an exception subclass; a `message` field there collides with
    // `kotlin.Throwable.message`. Swift never reads this field.
    #[error("query error: {reason}")]
    Query { reason: String },
    #[error("store error: {reason}")]
    Store { reason: String },
    #[error("network error: {reason}")]
    Network { reason: String },
    #[error("auth error: {reason}")]
    Auth { reason: String },
    #[error("crypto error: {reason}")]
    Crypto { reason: String },
}

impl From<cw_store::StoreError> for CwError {
    fn from(err: cw_store::StoreError) -> Self {
        CwError::Store { reason: err.to_string() }
    }
}

impl From<cw_net::HttpError> for CwError {
    fn from(err: cw_net::HttpError) -> Self {
        CwError::Network { reason: err.to_string() }
    }
}

impl From<cw_domain::query::QueryError> for CwError {
    fn from(err: cw_domain::query::QueryError) -> Self {
        CwError::Query { reason: err.message() }
    }
}

impl From<cw_crypto::CryptoError> for CwError {
    fn from(err: cw_crypto::CryptoError) -> Self {
        CwError::Crypto { reason: err.to_string() }
    }
}

impl From<cw_sync::SyncError> for CwError {
    fn from(err: cw_sync::SyncError) -> Self {
        match err {
            // A key mismatch is actionable (re-enter the passphrase), so it
            // must not hide behind a generic "network error".
            cw_sync::SyncError::KeyMismatch => CwError::Crypto { reason: err.to_string() },
            other => CwError::Network { reason: other.to_string() },
        }
    }
}

// ---------- Query analysis ----------

#[derive(uniffi::Enum)]
pub enum FfiQueryCost {
    Indexed,
    Bounded,
    FullScan,
}

impl From<QueryCost> for FfiQueryCost {
    fn from(cost: QueryCost) -> Self {
        match cost {
            QueryCost::Indexed => FfiQueryCost::Indexed,
            QueryCost::Bounded => FfiQueryCost::Bounded,
            QueryCost::FullScan => FfiQueryCost::FullScan,
        }
    }
}

#[derive(uniffi::Enum)]
pub enum FfiSeverity {
    Hint,
    Medium,
    High,
}

impl From<Severity> for FfiSeverity {
    fn from(sev: Severity) -> Self {
        match sev {
            Severity::Hint => FfiSeverity::Hint,
            Severity::Medium => FfiSeverity::Medium,
            Severity::High => FfiSeverity::High,
        }
    }
}

#[derive(uniffi::Record)]
pub struct FfiQueryWarning {
    pub severity: FfiSeverity,
    pub message: String,
    pub suggestion: Option<String>,
}

#[derive(uniffi::Record)]
pub struct FfiQueryAnalysis {
    pub uses_index: bool,
    pub cost: FfiQueryCost,
    pub should_warn: bool,
    pub requires_confirmation: bool,
    pub warnings: Vec<FfiQueryWarning>,
}

/// Parse + analyze a query string. Surfaces parse errors as `CwError::Query`.
#[uniffi::export]
pub fn analyze_query(input: String, qso_count: i64) -> Result<FfiQueryAnalysis, CwError> {
    let analysis = query::parse_and_analyze(&input, qso_count)
        .map_err(|err| CwError::Query { reason: err.message() })?;
    Ok(FfiQueryAnalysis {
        uses_index: analysis.uses_index,
        cost: analysis.estimated_cost.into(),
        should_warn: analysis.should_warn(),
        requires_confirmation: analysis.requires_confirmation(),
        warnings: analysis
            .warnings
            .into_iter()
            .map(|warning| FfiQueryWarning {
                severity: warning.severity.into(),
                message: warning.message,
                suggestion: warning.suggestion,
            })
            .collect(),
    })
}

/// Validate a query string without analyzing it (returns the canonical source
/// text on success). Useful for live as-you-type validation in the UI.
#[uniffi::export]
pub fn validate_query(input: String) -> Result<String, CwError> {
    let parsed = query::parse(&input).map_err(|err| CwError::Query { reason: err.message() })?;
    Ok(parsed.source_text)
}

/// A QSO's query-addressable fields for the in-memory filter. Optional fields are
/// `None` when absent (→ a leaf predicate over them is false). `frequency_khz` is
/// kHz (the evaluator divides by 1000 for `freq:`); `qso_date` is unix seconds.
#[derive(uniffi::Record)]
pub struct FfiQueryQso {
    pub callsign: Option<String>,
    pub band: Option<String>,
    pub mode: Option<String>,
    pub my_callsign: Option<String>,
    pub park: Option<String>,
    pub sota_ref: Option<String>,
    pub their_grid: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    pub name: Option<String>,
    pub qth: Option<String>,
    pub notes: Option<String>,
    pub my_grid: Option<String>,
    pub frequency_khz: Option<f64>,
    pub dxcc: Option<f64>,
    pub power: Option<f64>,
    pub qso_date: i64,
    pub qrz_confirmed: bool,
    pub lotw_confirmed: bool,
    pub import_source: String,
}

impl cw_domain::query::QueryRow for FfiQueryQso {
    fn callsign(&self) -> Option<&str> {
        self.callsign.as_deref()
    }
    fn band(&self) -> Option<&str> {
        self.band.as_deref()
    }
    fn mode(&self) -> Option<&str> {
        self.mode.as_deref()
    }
    fn my_callsign(&self) -> Option<&str> {
        self.my_callsign.as_deref()
    }
    fn park(&self) -> Option<&str> {
        self.park.as_deref()
    }
    fn sota_ref(&self) -> Option<&str> {
        self.sota_ref.as_deref()
    }
    fn their_grid(&self) -> Option<&str> {
        self.their_grid.as_deref()
    }
    fn state(&self) -> Option<&str> {
        self.state.as_deref()
    }
    fn country(&self) -> Option<&str> {
        self.country.as_deref()
    }
    fn name(&self) -> Option<&str> {
        self.name.as_deref()
    }
    fn qth(&self) -> Option<&str> {
        self.qth.as_deref()
    }
    fn notes(&self) -> Option<&str> {
        self.notes.as_deref()
    }
    fn my_grid(&self) -> Option<&str> {
        self.my_grid.as_deref()
    }
    fn frequency_khz(&self) -> Option<f64> {
        self.frequency_khz
    }
    fn dxcc(&self) -> Option<f64> {
        self.dxcc
    }
    fn power(&self) -> Option<f64> {
        self.power
    }
    fn qso_date(&self) -> i64 {
        self.qso_date
    }
    fn qrz_confirmed(&self) -> bool {
        self.qrz_confirmed
    }
    fn lotw_confirmed(&self) -> bool {
        self.lotw_confirmed
    }
    fn import_source(&self) -> &str {
        &self.import_source
    }
}

/// Filter an in-memory list of QSOs by a `.cwquery` string, returning the indices
/// of the matches (in input order). The single shared in-memory evaluator
/// (`cw-domain::query::matches`, parity-tested against the SQL compiler) — used by
/// macOS Sweep's log table so it needn't reimplement matching. An empty query
/// matches everything; a parse error surfaces as `CwError::Query`.
#[uniffi::export]
pub fn query_filter(query: String, qsos: Vec<FfiQueryQso>) -> Result<Vec<u32>, CwError> {
    let parsed = query::parse(&query).map_err(|err| CwError::Query { reason: err.message() })?;
    Ok(qsos
        .iter()
        .enumerate()
        .filter(|(_, qso)| query::matches(&parsed, *qso))
        .map(|(index, _)| index as u32)
        .collect())
}

// ---------- Maidenhead ----------

#[derive(uniffi::Record)]
pub struct FfiCoordinate {
    pub latitude: f64,
    pub longitude: f64,
}

impl From<Coordinate> for FfiCoordinate {
    fn from(coord: Coordinate) -> Self {
        FfiCoordinate { latitude: coord.latitude, longitude: coord.longitude }
    }
}

impl From<FfiCoordinate> for Coordinate {
    fn from(coord: FfiCoordinate) -> Self {
        Coordinate { latitude: coord.latitude, longitude: coord.longitude }
    }
}

/// 4/6/8-char output precision. Mirrors `MaidenheadConverter.Precision` on
/// the Swift side (raw values 4, 6, 8).
#[derive(uniffi::Enum)]
pub enum FfiMaidenheadPrecision {
    Four,
    Six,
    Eight,
}

impl From<FfiMaidenheadPrecision> for maidenhead::Precision {
    fn from(p: FfiMaidenheadPrecision) -> Self {
        match p {
            FfiMaidenheadPrecision::Four => maidenhead::Precision::Four,
            FfiMaidenheadPrecision::Six => maidenhead::Precision::Six,
            FfiMaidenheadPrecision::Eight => maidenhead::Precision::Eight,
        }
    }
}

/// Center coordinate of a Maidenhead grid, or `None` if invalid.
#[uniffi::export]
pub fn maidenhead_coordinate(grid: String) -> Option<FfiCoordinate> {
    maidenhead::coordinate_from_grid(&grid).map(FfiCoordinate::from)
}

/// Encode a coordinate as a Maidenhead grid at the requested precision.
#[uniffi::export]
pub fn maidenhead_grid(
    coordinate: FfiCoordinate,
    precision: FfiMaidenheadPrecision,
) -> String {
    maidenhead::grid_from_coordinate(coordinate.into(), precision.into())
}

/// Great-circle distance in km between two Maidenhead grids. `None` if either
/// grid is invalid.
#[uniffi::export]
pub fn maidenhead_distance_km(grid1: String, grid2: String) -> Option<f64> {
    maidenhead::distance_km(&grid1, &grid2)
}

/// Initial bearing in degrees `[0, 360)` from `grid1` to `grid2`. `None` if
/// either grid is invalid.
#[uniffi::export]
pub fn maidenhead_bearing(grid1: String, grid2: String) -> Option<f64> {
    maidenhead::bearing(&grid1, &grid2)
}

/// `true` iff `grid` is a valid Maidenhead locator.
#[uniffi::export]
pub fn maidenhead_is_valid(grid: String) -> bool {
    maidenhead::is_valid(&grid)
}

// ---------- Callsign flag ----------

/// Country flag emoji for a callsign prefix, or `None`. Port of iOS
/// `CallsignFlagHelper` — a small, intentionally partial prefix table.
#[uniffi::export]
pub fn callsign_flag(callsign: String) -> Option<String> {
    cw_domain::flag_for_callsign(&callsign)
}

// ---------- RST defaults ----------

/// Default RST report string for `mode` — `"599"` for 3-digit (CW/digital)
/// modes, `"59"` for phone. Port of iOS `LoggerView.defaultRST`; the single
/// cross-platform source of truth so the logger form's default matches what
/// `SessionApi.log_qso` fills for a blank field.
#[uniffi::export]
pub fn default_rst(mode: String) -> String {
    cw_domain::default_rst(&mode)
}

// ---------- Duplicate status ----------

/// Day-scoped duplicate status of a callsign for the logger. Port of iOS
/// `CallsignDuplicateStatus`. Returned by [`FieldStore::duplicate_status`].
#[derive(uniffi::Enum, Debug, PartialEq, Eq)]
pub enum FfiDuplicateStatus {
    /// First contact with this callsign today.
    FirstContact,
    /// Worked today but the current band is unknown — informational only.
    PreviouslyWorked { previous_bands: Vec<String> },
    /// Worked today on other band(s), not this one.
    NewBand { previous_bands: Vec<String> },
    /// Same band today, different mode family — a valid new QSO.
    NewMode { band: String, previous_modes: Vec<String> },
    /// Same band and equivalent mode today — a true dupe.
    DuplicateBand { band: String, is_pota: bool },
}

/// Fold the day's candidate QSOs into a duplicate status (pure; port of iOS
/// `classifyDuplicateStatus`). `candidates` are `(band, mode, their_park)`.
fn classify_duplicate_status(
    candidates: Vec<cw_store::DupeCandidate>,
    band: Option<String>,
    mode: &str,
    park: Option<&str>,
    is_pota: bool,
) -> FfiDuplicateStatus {
    use cw_domain::ModeEquivalence;

    // Park-scope to the activation park when working POTA. Uses per-park set
    // overlap rather than string equality so a POTA n-fer (a candidate or the
    // target carrying several comma-separated parks) matches when the two share
    // any park — e.g. re-typing one park of a logged 2-fer is the same park.
    // Both-nil still matches, mirroring iOS `filterMatchingQSOs`.
    let matching: Vec<(Option<String>, Option<String>)> = candidates
        .into_iter()
        .filter(|(_, _, their_park)| {
            !is_pota
                || match (their_park.as_deref(), park) {
                    (Some(candidate), Some(target)) => {
                        cw_domain::park_reference::has_overlap(candidate, target)
                    }
                    (None, None) => true,
                    _ => false,
                }
        })
        .map(|(band, mode, _)| (band, mode))
        .collect();

    if matching.is_empty() {
        return FfiDuplicateStatus::FirstContact;
    }

    let mut previous_bands: Vec<String> =
        matching.iter().filter_map(|(band, _)| band.clone()).collect();
    previous_bands.sort();
    previous_bands.dedup();

    let effective_band = band.filter(|value| !value.is_empty() && value != "Unknown");
    let Some(effective_band) = effective_band else {
        return FfiDuplicateStatus::PreviouslyWorked { previous_bands };
    };
    if !previous_bands.contains(&effective_band) {
        return FfiDuplicateStatus::NewBand { previous_bands };
    }

    let same_band_modes: Vec<String> = matching
        .iter()
        .filter(|(band, _)| band.as_deref() == Some(effective_band.as_str()))
        .filter_map(|(_, mode)| mode.clone())
        .collect();

    if same_band_modes.iter().any(|candidate| ModeEquivalence::are_equivalent(candidate, mode)) {
        FfiDuplicateStatus::DuplicateBand { band: effective_band, is_pota }
    } else {
        FfiDuplicateStatus::NewMode {
            band: effective_band,
            previous_modes: ModeEquivalence::deduplicated_modes(&same_band_modes),
        }
    }
}

#[cfg(test)]
mod dupe_tests {
    use super::*;

    fn cand(band: &str, mode: &str, park: Option<&str>) -> cw_store::DupeCandidate {
        (Some(band.into()), Some(mode.into()), park.map(Into::into))
    }

    #[test]
    fn first_contact_when_no_candidates() {
        let status = classify_duplicate_status(vec![], Some("20m".into()), "CW", None, false);
        assert_eq!(status, FfiDuplicateStatus::FirstContact);
    }

    #[test]
    fn nfer_park_overlap_is_same_park() {
        // Logged a 2-fer today; re-typing one of its parks on the same band/mode
        // is a dupe (park sets overlap), not a fresh FirstContact.
        let status = classify_duplicate_status(
            vec![cand("20m", "CW", Some("US-1044, US-3791"))],
            Some("20m".into()),
            "CW",
            Some("US-1044"),
            true,
        );
        assert_eq!(status, FfiDuplicateStatus::DuplicateBand { band: "20m".into(), is_pota: true });

        // Typing a 2-fer when one of its parks was worked solo today also
        // overlaps => same park scope.
        let target_nfer = classify_duplicate_status(
            vec![cand("20m", "CW", Some("US-1044"))],
            Some("20m".into()),
            "CW",
            Some("US-1044, US-3791"),
            true,
        );
        assert_eq!(
            target_nfer,
            FfiDuplicateStatus::DuplicateBand { band: "20m".into(), is_pota: true }
        );
    }

    #[test]
    fn non_overlapping_parks_are_first_contact() {
        // A different park entirely => not park-matched => FirstContact.
        let status = classify_duplicate_status(
            vec![cand("20m", "CW", Some("US-3791"))],
            Some("20m".into()),
            "CW",
            Some("US-1044"),
            true,
        );
        assert_eq!(status, FfiDuplicateStatus::FirstContact);
    }

    #[test]
    fn new_band_when_worked_other_band() {
        let status =
            classify_duplicate_status(vec![cand("40m", "CW", None)], Some("20m".into()), "CW", None, false);
        assert_eq!(status, FfiDuplicateStatus::NewBand { previous_bands: vec!["40m".into()] });
    }

    #[test]
    fn duplicate_band_on_equivalent_mode() {
        let status =
            classify_duplicate_status(vec![cand("20m", "SSB", None)], Some("20m".into()), "USB", None, false);
        assert_eq!(status, FfiDuplicateStatus::DuplicateBand { band: "20m".into(), is_pota: false });
    }

    #[test]
    fn new_mode_on_same_band_different_family() {
        let status =
            classify_duplicate_status(vec![cand("20m", "CW", None)], Some("20m".into()), "SSB", None, false);
        assert_eq!(
            status,
            FfiDuplicateStatus::NewMode { band: "20m".into(), previous_modes: vec!["CW".into()] }
        );
    }

    #[test]
    fn previously_worked_when_band_unknown() {
        let status =
            classify_duplicate_status(vec![cand("20m", "CW", None)], Some("Unknown".into()), "CW", None, false);
        assert_eq!(status, FfiDuplicateStatus::PreviouslyWorked { previous_bands: vec!["20m".into()] });
    }

    #[test]
    fn pota_park_scoping_excludes_other_parks() {
        let candidates = vec![cand("20m", "CW", Some("US-0001"))];
        // Different park → no match → first contact.
        let status = classify_duplicate_status(
            candidates.clone(),
            Some("20m".into()),
            "CW",
            Some("US-9999"),
            true,
        );
        assert_eq!(status, FfiDuplicateStatus::FirstContact);
        // Same park → dupe.
        let status =
            classify_duplicate_status(candidates, Some("20m".into()), "CW", Some("US-0001"), true);
        assert_eq!(status, FfiDuplicateStatus::DuplicateBand { band: "20m".into(), is_pota: true });
    }
}

// ---------- QSO DTO ----------

#[derive(uniffi::Record, Default)]
pub struct FfiQso {
    pub id: String,
    pub callsign: String,
    pub band: Option<String>,
    pub mode: Option<String>,
    pub freq_khz: Option<f64>,
    pub qso_date: i64,
    pub my_grid: Option<String>,
    pub their_grid: Option<String>,
    pub rst_sent: Option<String>,
    pub rst_rcvd: Option<String>,
    pub my_callsign: Option<String>,
    pub park: Option<String>,
    pub their_park: Option<String>,
    pub notes: Option<String>,
    pub notes_user_authored: bool,
    pub spot_comments_data: Option<Vec<u8>>,
    pub callsign_change_note: Option<String>,
    pub original_callsign: Option<String>,
    pub import_source_raw_value: String,
    pub imported_at: i64,
    pub modified_at: Option<i64>,
    pub raw_adif: Option<String>,
    pub name: Option<String>,
    pub qth: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    pub power: Option<i64>,
    pub my_rig: Option<String>,
    pub station_profile_name: Option<String>,
    pub sota_ref: Option<String>,
    pub wwff_ref: Option<String>,
    pub aoa_code: Option<String>,
    pub qrz_log_id: Option<String>,
    pub qrz_confirmed: bool,
    pub lotw_confirmed_date: Option<i64>,
    pub lotw_confirmed: bool,
    pub dxcc: Option<i64>,
    pub their_license_class: Option<String>,
    pub contest_name: Option<String>,
    pub contest_serial_sent: Option<i64>,
    pub contest_serial_received: Option<i64>,
    pub contest_exchange_sent: Option<String>,
    pub contest_exchange_received: Option<String>,
    pub is_hidden: bool,
    pub is_activity_log_qso: bool,
    pub station_callsign: Option<String>,
    pub logging_session_id: Option<String>,
    pub dirty: bool,
    /// ADIF SAT_NAME — satellite short name (e.g. "AO-91").
    pub sat_name: Option<String>,
    /// ADIF PROP_MODE — "SAT" when the QSO came from the satellite feature.
    pub prop_mode: Option<String>,
    /// Per-service upload/confirmation badges for this QSO. Populated only by the
    /// Logbook query path (`fetch_qsos_query`); empty on all other conversions.
    pub presence: Vec<FfiServicePresence>,
}

impl From<Qso> for FfiQso {
    fn from(qso: Qso) -> Self {
        FfiQso {
            id: qso.id,
            callsign: qso.callsign,
            band: qso.band,
            mode: qso.mode,
            freq_khz: qso.freq_khz,
            qso_date: qso.qso_date,
            my_grid: qso.my_grid,
            their_grid: qso.their_grid,
            rst_sent: qso.rst_sent,
            rst_rcvd: qso.rst_rcvd,
            my_callsign: qso.my_callsign,
            park: qso.park,
            their_park: qso.their_park,
            notes: qso.notes,
            notes_user_authored: qso.notes_user_authored,
            spot_comments_data: qso.spot_comments_data,
            callsign_change_note: qso.callsign_change_note,
            original_callsign: qso.original_callsign,
            import_source_raw_value: qso.import_source_raw_value,
            imported_at: qso.imported_at,
            modified_at: qso.modified_at,
            raw_adif: qso.raw_adif,
            name: qso.name,
            qth: qso.qth,
            state: qso.state,
            country: qso.country,
            power: qso.power,
            my_rig: qso.my_rig,
            station_profile_name: qso.station_profile_name,
            sota_ref: qso.sota_ref,
            wwff_ref: qso.wwff_ref,
            aoa_code: qso.aoa_code,
            qrz_log_id: qso.qrz_log_id,
            qrz_confirmed: qso.qrz_confirmed,
            lotw_confirmed_date: qso.lotw_confirmed_date,
            lotw_confirmed: qso.lotw_confirmed,
            dxcc: qso.dxcc,
            their_license_class: qso.their_license_class,
            contest_name: qso.contest_name,
            contest_serial_sent: qso.contest_serial_sent,
            contest_serial_received: qso.contest_serial_received,
            contest_exchange_sent: qso.contest_exchange_sent,
            contest_exchange_received: qso.contest_exchange_received,
            is_hidden: qso.is_hidden,
            is_activity_log_qso: qso.is_activity_log_qso,
            station_callsign: qso.station_callsign,
            logging_session_id: qso.logging_session_id,
            dirty: qso.dirty,
            sat_name: qso.sat_name,
            prop_mode: qso.prop_mode,
            presence: Vec::new(),
        }
    }
}

impl From<FfiQso> for Qso {
    fn from(qso: FfiQso) -> Self {
        Qso {
            id: qso.id,
            callsign: qso.callsign,
            band: qso.band,
            mode: qso.mode,
            freq_khz: qso.freq_khz,
            qso_date: qso.qso_date,
            my_grid: qso.my_grid,
            their_grid: qso.their_grid,
            rst_sent: qso.rst_sent,
            rst_rcvd: qso.rst_rcvd,
            my_callsign: qso.my_callsign,
            park: qso.park,
            their_park: qso.their_park,
            notes: qso.notes,
            notes_user_authored: qso.notes_user_authored,
            spot_comments_data: qso.spot_comments_data,
            callsign_change_note: qso.callsign_change_note,
            original_callsign: qso.original_callsign,
            import_source_raw_value: qso.import_source_raw_value,
            imported_at: qso.imported_at,
            modified_at: qso.modified_at,
            raw_adif: qso.raw_adif,
            name: qso.name,
            qth: qso.qth,
            state: qso.state,
            country: qso.country,
            power: qso.power,
            my_rig: qso.my_rig,
            station_profile_name: qso.station_profile_name,
            sota_ref: qso.sota_ref,
            wwff_ref: qso.wwff_ref,
            aoa_code: qso.aoa_code,
            qrz_log_id: qso.qrz_log_id,
            qrz_confirmed: qso.qrz_confirmed,
            lotw_confirmed_date: qso.lotw_confirmed_date,
            lotw_confirmed: qso.lotw_confirmed,
            dxcc: qso.dxcc,
            their_license_class: qso.their_license_class,
            contest_name: qso.contest_name,
            contest_serial_sent: qso.contest_serial_sent,
            contest_serial_received: qso.contest_serial_received,
            contest_exchange_sent: qso.contest_exchange_sent,
            contest_exchange_received: qso.contest_exchange_received,
            is_hidden: qso.is_hidden,
            is_activity_log_qso: qso.is_activity_log_qso,
            station_callsign: qso.station_callsign,
            logging_session_id: qso.logging_session_id,
            dirty: qso.dirty,
            sat_name: qso.sat_name,
            prop_mode: qso.prop_mode,
        }
    }
}

#[derive(uniffi::Record, Default)]
pub struct FfiQsoFilter {
    pub callsign_prefix: Option<String>,
    pub band: Option<String>,
    pub mode: Option<String>,
    pub since: Option<i64>,
    pub dirty_only: bool,
}

impl From<FfiQsoFilter> for QsoFilter {
    fn from(filter: FfiQsoFilter) -> Self {
        QsoFilter {
            callsign_prefix: filter.callsign_prefix,
            band: filter.band,
            mode: filter.mode,
            since: filter.since,
            dirty_only: filter.dirty_only,
        }
    }
}

// ---------- Analytics (aggregation surface) ----------

/// Headline distinct counts for the stats dashboard.
#[derive(uniffi::Record)]
pub struct FfiDistinctCounts {
    pub qsos: i64,
    pub bands: i64,
    pub grids: i64,
    pub entities: i64,
    pub parks: i64,
    pub confirmed: i64,
    pub qrz_confirmed: i64,
    pub lotw_confirmed: i64,
    pub with_grid: i64,
    pub with_park: i64,
    pub with_dxcc: i64,
    pub unique_callsigns: i64,
}

impl From<cw_store::DistinctCounts> for FfiDistinctCounts {
    fn from(counts: cw_store::DistinctCounts) -> Self {
        FfiDistinctCounts {
            qsos: counts.qsos,
            bands: counts.bands,
            grids: counts.grids,
            entities: counts.entities,
            parks: counts.parks,
            confirmed: counts.confirmed,
            qrz_confirmed: counts.qrz_confirmed,
            lotw_confirmed: counts.lotw_confirmed,
            with_grid: counts.with_grid,
            with_park: counts.with_park,
            with_dxcc: counts.with_dxcc,
            unique_callsigns: counts.unique_callsigns,
        }
    }
}

/// A grouped count row (key + label + QSO count + distinct callsigns).
#[derive(uniffi::Record)]
pub struct FfiDimensionCount {
    pub key: String,
    pub label: String,
    pub count: i64,
    pub distinct_calls: i64,
}

impl From<cw_store::DimensionCount> for FfiDimensionCount {
    fn from(row: cw_store::DimensionCount) -> Self {
        FfiDimensionCount {
            key: row.key,
            label: row.label,
            count: row.count,
            distinct_calls: row.distinct_calls,
        }
    }
}

/// One worked grid tile (map overlay).
#[derive(uniffi::Record)]
pub struct FfiGridTile {
    pub tile: String,
    pub count: i64,
    pub confirmed: i64,
    pub last_qso: i64,
    pub callsigns: Vec<String>,
    pub bands: Vec<String>,
    pub modes: Vec<String>,
}

impl From<cw_store::GridTile> for FfiGridTile {
    fn from(tile: cw_store::GridTile) -> Self {
        FfiGridTile {
            tile: tile.tile,
            count: tile.count,
            confirmed: tile.confirmed,
            last_qso: tile.last_qso,
            callsigns: tile.callsigns,
            bands: tile.bands,
            modes: tile.modes,
        }
    }
}

/// One POTA activation rollup row.
#[derive(uniffi::Record)]
pub struct FfiActivationRollup {
    pub park: String,
    pub operator_callsign: String,
    pub utc_date: String,
    pub unique_qsos: i64,
    pub total_qsos: i64,
    pub successful: bool,
}

impl From<cw_store::ActivationRollup> for FfiActivationRollup {
    fn from(row: cw_store::ActivationRollup) -> Self {
        FfiActivationRollup {
            park: row.park,
            operator_callsign: row.operator_callsign,
            utc_date: row.utc_date,
            unique_qsos: row.unique_qsos,
            total_qsos: row.total_qsos,
            successful: row.successful,
        }
    }
}

/// A park approaching the 1,000-QSO kilo threshold.
#[derive(uniffi::Record)]
pub struct FfiNearKiloPark {
    pub reference: String,
    pub qso_count: i64,
}

impl From<cw_store::NearKiloPark> for FfiNearKiloPark {
    fn from(park: cw_store::NearKiloPark) -> Self {
        FfiNearKiloPark { reference: park.reference, qso_count: park.qso_count }
    }
}

/// POTA activator awards progress (mirror of `POTAAwardsProgress`).
#[derive(uniffi::Record)]
pub struct FfiPotaAwards {
    pub unique_parks_count: i64,
    pub dx_entities_count: i64,
    pub states_activated: Vec<String>,
    pub rover_max_parks: i64,
    pub repeat_offender_max_count: i64,
    pub park_to_park_count: i64,
    pub kilo_parks: Vec<String>,
    pub near_kilo_parks: Vec<FfiNearKiloPark>,
    pub la_porta_earned: bool,
    pub la_porta_qualifying_parks: i64,
    pub six_pack_earned: bool,
    pub best_single_park_total: i64,
    pub total_park_qsos: i64,
    pub metadata_excluded: i64,
    pub total_activation_groups: i64,
    pub valid_activation_groups: i64,
}

impl From<cw_store::PotaAwards> for FfiPotaAwards {
    fn from(awards: cw_store::PotaAwards) -> Self {
        FfiPotaAwards {
            unique_parks_count: awards.unique_parks_count,
            dx_entities_count: awards.dx_entities_count,
            states_activated: awards.states_activated,
            rover_max_parks: awards.rover_max_parks,
            repeat_offender_max_count: awards.repeat_offender_max_count,
            park_to_park_count: awards.park_to_park_count,
            kilo_parks: awards.kilo_parks,
            near_kilo_parks: awards.near_kilo_parks.into_iter().map(FfiNearKiloPark::from).collect(),
            la_porta_earned: awards.la_porta_earned,
            la_porta_qualifying_parks: awards.la_porta_qualifying_parks,
            six_pack_earned: awards.six_pack_earned,
            best_single_park_total: awards.best_single_park_total,
            total_park_qsos: awards.total_park_qsos,
            metadata_excluded: awards.metadata_excluded,
            total_activation_groups: awards.total_activation_groups,
            valid_activation_groups: awards.valid_activation_groups,
        }
    }
}

/// America 250 WAS progress (mirror of `WAS250Progress`).
#[derive(uniffi::Record)]
pub struct FfiWas250 {
    pub states_worked: Vec<String>,
    pub cw_states: Vec<String>,
    pub phone_states: Vec<String>,
    pub digital_states: Vec<String>,
    pub total_qsos: i64,
    pub metadata_excluded: i64,
    pub with_state_field: i64,
    pub with_valid_state: i64,
}

impl From<cw_store::Was250> for FfiWas250 {
    fn from(was: cw_store::Was250) -> Self {
        FfiWas250 {
            states_worked: was.states_worked,
            cw_states: was.cw_states,
            phone_states: was.phone_states,
            digital_states: was.digital_states,
            total_qsos: was.total_qsos,
            metadata_excluded: was.metadata_excluded,
            with_state_field: was.with_state_field,
            with_valid_state: was.with_valid_state,
        }
    }
}

/// One WAS drilldown row (source × mode × state → count + distinct callsigns).
#[derive(uniffi::Record)]
pub struct FfiWasDrilldownRow {
    pub source: String,
    pub mode: Option<String>,
    pub state: String,
    pub count: i64,
    pub callsigns: Vec<String>,
}

impl From<cw_store::WasDrilldownRow> for FfiWasDrilldownRow {
    fn from(row: cw_store::WasDrilldownRow) -> Self {
        FfiWasDrilldownRow {
            source: row.source,
            mode: row.mode,
            state: row.state,
            count: row.count,
            callsigns: row.callsigns,
        }
    }
}

/// WAS rollup: valid states worked overall and per mode family.
#[derive(uniffi::Record)]
pub struct FfiWasSummary {
    pub all_states: Vec<String>,
    pub per_mode: Vec<FfiWasModeStates>,
}

impl From<cw_store::WasSummary> for FfiWasSummary {
    fn from(summary: cw_store::WasSummary) -> Self {
        FfiWasSummary {
            all_states: summary.all_states,
            per_mode: summary.per_mode.into_iter().map(FfiWasModeStates::from).collect(),
        }
    }
}

/// States worked on one mode family (a row of `FfiWasSummary::per_mode`).
#[derive(uniffi::Record)]
pub struct FfiWasModeStates {
    pub mode_family: String,
    pub states: Vec<String>,
}

impl From<cw_store::WasModeStates> for FfiWasModeStates {
    fn from(row: cw_store::WasModeStates) -> Self {
        FfiWasModeStates { mode_family: row.mode_family, states: row.states }
    }
}

/// One worked DXCC entity with location and QSO count.
#[derive(uniffi::Record)]
pub struct FfiDxccWorked {
    pub dxcc_id: i64,
    pub name: String,
    pub latitude: f64,
    pub longitude: f64,
    pub count: i64,
    pub bands: Vec<String>,
}

impl From<cw_store::DxccWorked> for FfiDxccWorked {
    fn from(row: cw_store::DxccWorked) -> Self {
        FfiDxccWorked {
            dxcc_id: row.dxcc_id,
            name: row.name,
            latitude: row.latitude,
            longitude: row.longitude,
            count: row.count,
            bands: row.bands,
        }
    }
}

/// Per-service uploaded/pending unique-QSO counts.
#[derive(uniffi::Record)]
pub struct FfiServicePresenceCount {
    pub service: String,
    pub uploaded: i64,
    pub pending: i64,
}

impl From<cw_store::ServicePresenceCount> for FfiServicePresenceCount {
    fn from(row: cw_store::ServicePresenceCount) -> Self {
        FfiServicePresenceCount {
            service: row.service,
            uploaded: row.uploaded,
            pending: row.pending,
        }
    }
}

/// One park's activity rollup.
#[derive(uniffi::Record)]
pub struct FfiParkRollup {
    pub park: String,
    pub activation_days: i64,
    pub hunt_qsos: i64,
    pub last_worked: i64,
}

impl From<cw_store::ParkRollup> for FfiParkRollup {
    fn from(row: cw_store::ParkRollup) -> Self {
        FfiParkRollup {
            park: row.park,
            activation_days: row.activation_days,
            hunt_qsos: row.hunt_qsos,
            last_worked: row.last_worked,
        }
    }
}

/// One worked US state with its QSO count.
#[derive(uniffi::Record)]
pub struct FfiStateCount {
    pub state: String,
    pub count: i64,
}

impl From<cw_store::StateCount> for FfiStateCount {
    fn from(row: cw_store::StateCount) -> Self {
        FfiStateCount { state: row.state, count: row.count }
    }
}

/// One equipment item's session rollup.
#[derive(uniffi::Record)]
pub struct FfiSessionEquipmentRollup {
    pub kind: String,
    pub name: String,
    pub session_count: i64,
    pub total_qsos: i64,
    pub first_used: i64,
    pub last_used: i64,
}

impl From<cw_store::SessionEquipmentRollup> for FfiSessionEquipmentRollup {
    fn from(row: cw_store::SessionEquipmentRollup) -> Self {
        FfiSessionEquipmentRollup {
            kind: row.kind,
            name: row.name,
            session_count: row.session_count,
            total_qsos: row.total_qsos,
            first_used: row.first_used,
            last_used: row.last_used,
        }
    }
}

/// One rig+antenna combo's session rollup.
#[derive(uniffi::Record)]
pub struct FfiSessionComboRollup {
    pub rig: String,
    pub antenna: String,
    pub session_count: i64,
    pub total_qsos: i64,
}

impl From<cw_store::SessionComboRollup> for FfiSessionComboRollup {
    fn from(row: cw_store::SessionComboRollup) -> Self {
        FfiSessionComboRollup {
            rig: row.rig,
            antenna: row.antenna,
            session_count: row.session_count,
            total_qsos: row.total_qsos,
        }
    }
}

/// A furthest-contact brag record (mirrors cw-store `BragContact`).
#[derive(uniffi::Record)]
pub struct FfiBragContact {
    pub callsign: String,
    pub band: String,
    pub distance_km: f64,
}

impl From<cw_store::BragContact> for FfiBragContact {
    fn from(row: cw_store::BragContact) -> Self {
        FfiBragContact { callsign: row.callsign, band: row.band, distance_km: row.distance_km }
    }
}

/// A per-band furthest-contact brag record (mirrors cw-store `BragBandRecord`).
#[derive(uniffi::Record)]
pub struct FfiBragBandRecord {
    pub band: String,
    pub callsign: String,
    pub distance_km: f64,
}

impl From<cw_store::BragBandRecord> for FfiBragBandRecord {
    fn from(row: cw_store::BragBandRecord) -> Self {
        FfiBragBandRecord { band: row.band, callsign: row.callsign, distance_km: row.distance_km }
    }
}

/// The lowest-power brag contact (mirrors cw-store `BragPowerContact`).
#[derive(uniffi::Record)]
pub struct FfiBragPowerContact {
    pub watts: i64,
    pub callsign: String,
    pub band: String,
    pub distance_km: Option<f64>,
}

impl From<cw_store::BragPowerContact> for FfiBragPowerContact {
    fn from(row: cw_store::BragPowerContact) -> Self {
        FfiBragPowerContact {
            watts: row.watts,
            callsign: row.callsign,
            band: row.band,
            distance_km: row.distance_km,
        }
    }
}

/// The best watts-per-mile brag contact (mirrors cw-store `BragEfficiency`).
#[derive(uniffi::Record)]
pub struct FfiBragEfficiency {
    pub watts: i64,
    pub callsign: String,
    pub band: String,
    pub distance_km: f64,
}

impl From<cw_store::BragEfficiency> for FfiBragEfficiency {
    fn from(row: cw_store::BragEfficiency) -> Self {
        FfiBragEfficiency {
            watts: row.watts,
            callsign: row.callsign,
            band: row.band,
            distance_km: row.distance_km,
        }
    }
}

/// The distance-shaped brag-sheet stats (mirrors cw-store `BragDistanceStats`).
#[derive(uniffi::Record)]
pub struct FfiBragDistanceStats {
    pub furthest: Option<FfiBragContact>,
    pub furthest_qrp: Option<FfiBragContact>,
    pub furthest_cw: Option<FfiBragContact>,
    pub furthest_cw_qrp: Option<FfiBragContact>,
    pub furthest_perfect_rst: Option<FfiBragContact>,
    pub furthest_per_band: Vec<FfiBragBandRecord>,
    pub average_km: Option<f64>,
    pub lowest_power: Option<FfiBragPowerContact>,
    pub best_watts_per_mile: Option<FfiBragEfficiency>,
}

impl From<cw_store::BragDistanceStats> for FfiBragDistanceStats {
    fn from(stats: cw_store::BragDistanceStats) -> Self {
        FfiBragDistanceStats {
            furthest: stats.furthest.map(FfiBragContact::from),
            furthest_qrp: stats.furthest_qrp.map(FfiBragContact::from),
            furthest_cw: stats.furthest_cw.map(FfiBragContact::from),
            furthest_cw_qrp: stats.furthest_cw_qrp.map(FfiBragContact::from),
            furthest_perfect_rst: stats.furthest_perfect_rst.map(FfiBragContact::from),
            furthest_per_band: stats.furthest_per_band.into_iter().map(FfiBragBandRecord::from).collect(),
            average_km: stats.average_km,
            lowest_power: stats.lowest_power.map(FfiBragPowerContact::from),
            best_watts_per_mile: stats.best_watts_per_mile.map(FfiBragEfficiency::from),
        }
    }
}

/// The SQL-expressible volume / records / "fun" brag-sheet stats (mirrors cw-store
/// `BragRecords`). `*_day` / `most_qsos_session` / `active_modes` are 0 over no data; the
/// "best" fields are `None` then. Reuses `FfiItemTally` for the `(label, count)` records.
#[derive(uniffi::Record)]
pub struct FfiBragRecords {
    pub most_qsos_day: i64,
    pub most_qsos_session: i64,
    pub most_countries_day: i64,
    pub most_bands_day: i64,
    pub most_active_weekday: Option<FfiItemTally>,
    pub busiest_band: Option<FfiItemTally>,
    pub busiest_mode: Option<FfiItemTally>,
    pub repeat_customer: Option<FfiItemTally>,
    pub earliest_qso: Option<i64>,
    pub latest_qso: Option<i64>,
    pub total_distance_km: Option<f64>,
    pub active_modes: i64,
}

impl From<cw_store::BragRecords> for FfiBragRecords {
    fn from(rec: cw_store::BragRecords) -> Self {
        FfiBragRecords {
            most_qsos_day: rec.most_qsos_day,
            most_qsos_session: rec.most_qsos_session,
            most_countries_day: rec.most_countries_day,
            most_bands_day: rec.most_bands_day,
            most_active_weekday: rec.most_active_weekday.map(FfiItemTally::from),
            busiest_band: rec.busiest_band.map(FfiItemTally::from),
            busiest_mode: rec.busiest_mode.map(FfiItemTally::from),
            repeat_customer: rec.repeat_customer.map(FfiItemTally::from),
            earliest_qso: rec.earliest_qso,
            latest_qso: rec.latest_qso,
            total_distance_km: rec.total_distance_km,
            active_modes: rec.active_modes,
        }
    }
}

/// The session-/sequence-based brag-sheet stats (mirrors cw-store `BragSessionStats`).
/// Durations are seconds; `peak_15_min_count` / `largest_nfer` are 0 over no data.
#[derive(uniffi::Record)]
pub struct FfiBragSessionStats {
    pub operating_seconds: Option<f64>,
    pub fastest_ten_seconds: Option<f64>,
    pub best_session_rate: Option<f64>,
    pub fastest_activation_seconds: Option<f64>,
    pub longest_session_seconds: Option<f64>,
    pub peak_15_min_count: i64,
    pub largest_nfer: i64,
}

impl From<cw_store::BragSessionStats> for FfiBragSessionStats {
    fn from(stats: cw_store::BragSessionStats) -> Self {
        FfiBragSessionStats {
            operating_seconds: stats.operating_seconds,
            fastest_ten_seconds: stats.fastest_ten_seconds,
            best_session_rate: stats.best_session_rate,
            fastest_activation_seconds: stats.fastest_activation_seconds,
            longest_session_seconds: stats.longest_session_seconds,
            peak_15_min_count: stats.peak_15_min_count,
            largest_nfer: stats.largest_nfer,
        }
    }
}

/// The geographic-reach brag-sheet stats (mirrors cw-store `BragGeographic`).
#[derive(uniffi::Record)]
pub struct FfiBragGeographic {
    pub dxcc_entities: i64,
    pub new_dxcc_entities: i64,
    pub states_provinces: i64,
    pub grid_squares: i64,
    pub continents: i64,
    pub most_continents_day: i64,
    pub was_states: i64,
}

impl From<cw_store::BragGeographic> for FfiBragGeographic {
    fn from(geo: cw_store::BragGeographic) -> Self {
        FfiBragGeographic {
            dxcc_entities: geo.dxcc_entities,
            new_dxcc_entities: geo.new_dxcc_entities,
            states_provinces: geo.states_provinces,
            grid_squares: geo.grid_squares,
            continents: geo.continents,
            most_continents_day: geo.most_continents_day,
            was_states: geo.was_states,
        }
    }
}

/// One park activation extreme (mirrors cw-store `BragBestActivation`). `day` is a
/// `YYYY-MM-DD` UTC calendar day.
#[derive(uniffi::Record)]
pub struct FfiBragBestActivation {
    pub park: String,
    pub day: String,
    pub count: i64,
}

impl From<cw_store::BragBestActivation> for FfiBragBestActivation {
    fn from(best: cw_store::BragBestActivation) -> Self {
        FfiBragBestActivation { park: best.park, day: best.day, count: best.count }
    }
}

/// The POTA-category brag-sheet stats (mirrors cw-store `BragPota`).
#[derive(uniffi::Record)]
pub struct FfiBragPota {
    pub parks_activated: i64,
    pub parks_hunted: i64,
    pub park_to_park: i64,
    pub best_activation: Option<FfiBragBestActivation>,
    pub new_parks: i64,
}

impl From<cw_store::BragPota> for FfiBragPota {
    fn from(pota: cw_store::BragPota) -> Self {
        FfiBragPota {
            parks_activated: pota.parks_activated,
            parks_hunted: pota.parks_hunted,
            park_to_park: pota.park_to_park,
            best_activation: pota.best_activation.map(FfiBragBestActivation::from),
            new_parks: pota.new_parks,
        }
    }
}

/// A current/longest streak pair (mirrors cw-store `StreakValue`).
#[derive(uniffi::Record)]
pub struct FfiStreakValue {
    pub current: i64,
    pub longest: i64,
}

impl From<cw_store::StreakValue> for FfiStreakValue {
    fn from(value: cw_store::StreakValue) -> Self {
        FfiStreakValue { current: value.current, longest: value.longest }
    }
}

/// A per-mode-family streak (mirrors cw-store `ModeStreak`).
#[derive(uniffi::Record)]
pub struct FfiModeStreak {
    pub mode: String,
    pub current: i64,
    pub longest: i64,
}

impl From<cw_store::ModeStreak> for FfiModeStreak {
    fn from(row: cw_store::ModeStreak) -> Self {
        FfiModeStreak { mode: row.mode, current: row.current, longest: row.longest }
    }
}

/// The streak-shaped brag-sheet stats (mirrors cw-store `BragStreaks`).
#[derive(uniffi::Record)]
pub struct FfiBragStreaks {
    pub on_air: FfiStreakValue,
    pub activation: Option<FfiStreakValue>,
    pub modes: Vec<FfiModeStreak>,
}

impl From<cw_store::BragStreaks> for FfiBragStreaks {
    fn from(streaks: cw_store::BragStreaks) -> Self {
        FfiBragStreaks {
            on_air: streaks.on_air.into(),
            activation: streaks.activation.map(FfiStreakValue::from),
            modes: streaks.modes.into_iter().map(FfiModeStreak::from).collect(),
        }
    }
}

/// One (name, count) tally row in a `FfiSessionItemDetail` breakdown.
#[derive(uniffi::Record)]
pub struct FfiItemTally {
    pub name: String,
    pub count: i64,
}

impl From<cw_store::ItemTally> for FfiItemTally {
    fn from(row: cw_store::ItemTally) -> Self {
        FfiItemTally { name: row.name, count: row.count }
    }
}

/// Per-equipment-item QSO breakdown (mirrors cw-store `SessionItemDetail`). Distance
/// extremes are `None` when no QSO has a positive, computable distance.
#[derive(uniffi::Record)]
pub struct FfiSessionItemDetail {
    pub total_qsos: i64,
    pub unique_entities: i64,
    pub farthest_km: Option<f64>,
    pub shortest_km: Option<f64>,
    pub average_km: Option<f64>,
    pub band_breakdown: Vec<FfiItemTally>,
    pub mode_breakdown: Vec<FfiItemTally>,
}

impl From<cw_store::SessionItemDetail> for FfiSessionItemDetail {
    fn from(detail: cw_store::SessionItemDetail) -> Self {
        FfiSessionItemDetail {
            total_qsos: detail.total_qsos,
            unique_entities: detail.unique_entities,
            farthest_km: detail.farthest_km,
            shortest_km: detail.shortest_km,
            average_km: detail.average_km,
            band_breakdown: detail.band_breakdown.into_iter().map(FfiItemTally::from).collect(),
            mode_breakdown: detail.mode_breakdown.into_iter().map(FfiItemTally::from).collect(),
        }
    }
}

/// The SQL-trivial subset of brag-sheet period metrics.
#[derive(uniffi::Record)]
pub struct FfiBragPeriodMetrics {
    pub total_qsos: i64,
    pub cw_qsos: i64,
    pub phone_qsos: i64,
    pub digital_qsos: i64,
    pub operating_days: i64,
    pub active_bands: i64,
    pub unique_callsigns: i64,
    pub dxcc_entities: i64,
    pub qrp_qsos: i64,
    pub milliwatt_qsos: i64,
    pub parks_hunted: i64,
    pub park_to_park: i64,
    pub perfect_reports: i64,
}

impl From<cw_store::BragPeriodMetrics> for FfiBragPeriodMetrics {
    fn from(metrics: cw_store::BragPeriodMetrics) -> Self {
        FfiBragPeriodMetrics {
            total_qsos: metrics.total_qsos,
            cw_qsos: metrics.cw_qsos,
            phone_qsos: metrics.phone_qsos,
            digital_qsos: metrics.digital_qsos,
            operating_days: metrics.operating_days,
            active_bands: metrics.active_bands,
            unique_callsigns: metrics.unique_callsigns,
            dxcc_entities: metrics.dxcc_entities,
            qrp_qsos: metrics.qrp_qsos,
            milliwatt_qsos: metrics.milliwatt_qsos,
            parks_hunted: metrics.parks_hunted,
            park_to_park: metrics.park_to_park,
            perfect_reports: metrics.perfect_reports,
        }
    }
}

/// Dimension to group `qso_count_by` on.
#[derive(uniffi::Enum)]
pub enum FfiAggregateDimension {
    Band,
    ModeFamily,
    Dxcc,
    Month,
}

impl From<FfiAggregateDimension> for cw_store::AggregateDimension {
    fn from(dimension: FfiAggregateDimension) -> Self {
        match dimension {
            FfiAggregateDimension::Band => cw_store::AggregateDimension::Band,
            FfiAggregateDimension::ModeFamily => cw_store::AggregateDimension::ModeFamily,
            FfiAggregateDimension::Dxcc => cw_store::AggregateDimension::Dxcc,
            FfiAggregateDimension::Month => cw_store::AggregateDimension::Month,
        }
    }
}

// ---------- Store object ----------

/// The encrypted store, exposed to the host. `Mutex` makes it `Sync` for UniFFI
/// and serializes DB access (a single writer, as SQLite wants).
#[derive(uniffi::Object)]
pub struct FieldStore {
    // `pub(crate)` so each entity's FFI module (entities/*.rs) can add its own
    // `#[uniffi::export] impl FieldStore` block that locks the shared store.
    pub(crate) inner: Mutex<Store>,
    // Registered change observers. A separate lock from `inner` so a mutation
    // releases the DB lock *before* notifying — observers re-enter the store.
    pub(crate) observers: Mutex<ObserverRegistry>,
}

#[uniffi::export]
impl FieldStore {
    /// Open (or create) an encrypted store at `path` with `key`.
    #[uniffi::constructor]
    pub fn open(path: String, key: String) -> Result<Self, CwError> {
        let store = Store::open(path, &key)?;
        Ok(FieldStore {
            inner: Mutex::new(store),
            observers: Mutex::new(ObserverRegistry::default()),
        })
    }

    /// Open an ephemeral encrypted store (tests / previews).
    #[uniffi::constructor]
    pub fn open_in_memory(key: String) -> Result<Self, CwError> {
        let store = Store::open_in_memory(&key)?;
        Ok(FieldStore {
            inner: Mutex::new(store),
            observers: Mutex::new(ObserverRegistry::default()),
        })
    }

    /// Re-encrypt this open store in place with `new_key` (SQLCipher rekey).
    /// The store must already be open with the current key. Used to migrate the
    /// at-rest key from the legacy random device key to the passphrase-derived
    /// (escrowed) key without deleting or copying the file. See
    /// `docs/plans/2026-07-08-cwstore-passphrase-recovery.md`.
    pub fn rekey(&self, new_key: String) -> Result<(), CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        store.rekey(&new_key)?;
        Ok(())
    }

    pub fn upsert_qso(&self, qso: FfiQso) -> Result<(), CwError> {
        // Scope the DB lock so it is dropped before we notify — observers
        // re-enter the store from `on_change` and would deadlock otherwise.
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.upsert_qso(&qso.into())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::Qso, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    /// Upsert a batch of QSOs in a single transaction — one commit (one fsync
    /// cycle) for the whole batch. The SwiftData seed importer writes logs of
    /// 100k+ rows; per-row autocommit under `synchronous=FULL` + `fullfsync`
    /// took minutes and tripped the iOS watchdog. Atomic per batch; notifies
    /// observers once.
    pub fn upsert_qsos(&self, qsos: Vec<FfiQso>) -> Result<(), CwError> {
        if qsos.is_empty() {
            return Ok(());
        }
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.in_transaction(|| {
                for qso in qsos {
                    store.upsert_qso(&qso.into())?;
                }
                Ok(())
            })?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::Qso, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    pub fn delete_qso(&self, id: String) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_qso(&id)?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::Qso, kind: FfiChangeKind::Delete });
        Ok(())
    }

    pub fn qso_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.qso_count()?)
    }

    /// Fetch a single QSO by id, including hidden rows. Backs the sync journal's
    /// inbound merge (which must read the live row — soft-deleted ones included).
    pub fn fetch_qso(&self, id: String) -> Result<Option<FfiQso>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.fetch_qso(&id)?.map(FfiQso::from))
    }

    /// Count of dirty (un-synced) QSOs — the outbound backlog for the sync panel.
    pub fn dirty_qso_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.dirty_qso_count()?)
    }

    /// All-time count of visible, real QSOs with this exact callsign — the
    /// "previously worked" badge. Port of iOS `fetchPreviousQSOCount`.
    pub fn worked_before_count(&self, callsign: String) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.worked_before_count(&callsign)?)
    }

    /// Day-scoped duplicate status for logging `callsign` now. Port of iOS
    /// `LoggerView+Data.classifyDuplicateStatus`: matches this callsign's
    /// visible QSOs since `day_start` (UTC start-of-day epoch seconds),
    /// park-scoped to `park` when `is_pota`, then classifies against the current
    /// `band`/`mode`. `band == "Unknown"`/empty is treated as an unknown band.
    pub fn duplicate_status(
        &self,
        callsign: String,
        band: Option<String>,
        mode: String,
        park: Option<String>,
        is_pota: bool,
        day_start: i64,
    ) -> Result<FfiDuplicateStatus, CwError> {
        let candidates = {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.dupe_candidates(&callsign, day_start)?
        };
        Ok(classify_duplicate_status(candidates, band, &mode, park.as_deref(), is_pota))
    }

    /// Day-scoped duplicate status for logging `callsign` now **into an activation**
    /// — the activator's side of the same dedup the hunter log runs. Identical to
    /// [`Self::duplicate_status`] and sharing its classifier, except the POTA park
    /// scope is the operator's own activation park (`my_park`, matched against each
    /// QSO's `park`) rather than the contacted station's park. Port of the iOS
    /// `LoggerView` activation dupe (`filterMatchingQSOs` scoping by
    /// `qso.parkReference == session.parkReference`). Pass `my_park =
    /// session.park_reference` and `is_pota = session.is_pota`.
    pub fn activation_duplicate_status(
        &self,
        callsign: String,
        band: Option<String>,
        mode: String,
        my_park: Option<String>,
        is_pota: bool,
        day_start: i64,
    ) -> Result<FfiDuplicateStatus, CwError> {
        let candidates = {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.dupe_candidates_for_activation(&callsign, day_start)?
        };
        Ok(classify_duplicate_status(candidates, band, &mode, my_park.as_deref(), is_pota))
    }

    /// Bounded fetch. `limit` above `MAX_FETCH_LIMIT` is rejected by the store.
    pub fn fetch_qsos(
        &self,
        filter: FfiQsoFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiQso>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_qsos(&filter.into(), limit, offset)?;
        Ok(rows.into_iter().map(FfiQso::from).collect())
    }

    /// Fetch QSOs matching a full DSL query string.  Rust parses + compiles +
    /// executes the query so Swift only passes the raw string.
    pub fn fetch_qsos_query(
        &self,
        query: String,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiQso>, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?;
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_qsos_query(&parsed, limit, offset)?;

        // Project per-QSO service presence onto the page in one batched query,
        // then attach by qso_id. Rows without presence keep an empty vec.
        let ids: Vec<String> = rows.iter().map(|qso| qso.id.clone()).collect();
        let presence = store.fetch_service_presences_for_qsos(&ids)?;
        let mut by_qso: std::collections::HashMap<String, Vec<FfiServicePresence>> =
            std::collections::HashMap::new();
        for sp in presence {
            if let Some(qso_id) = sp.qso_id.clone() {
                by_qso.entry(qso_id).or_default().push(sp.into());
            }
        }

        Ok(rows
            .into_iter()
            .map(|qso| {
                let mut ffi = FfiQso::from(qso);
                if let Some(list) = by_qso.remove(&ffi.id) {
                    ffi.presence = list;
                }
                ffi
            })
            .collect())
    }

    /// Count QSOs matching a full DSL query string.
    pub fn qso_count_query(&self, query: String) -> Result<i64, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?;
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.count_query(&parsed)?)
    }

    /// Headline distinct counts (total / bands / grids / entities / parks /
    /// confirmed) over visible QSOs matching the DSL `query`.
    pub fn qso_distinct_counts(&self, query: String) -> Result<FfiDistinctCounts, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?;
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.qso_distinct_counts(&parsed)?.into())
    }

    /// QSO counts grouped by `dimension`, over visible QSOs matching the DSL
    /// `query`. Bounded by group cardinality, not by QSO count.
    pub fn qso_count_by(
        &self,
        query: String,
        dimension: FfiAggregateDimension,
    ) -> Result<Vec<FfiDimensionCount>, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?;
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store
            .qso_count_by(&parsed, dimension.into())?
            .into_iter()
            .map(FfiDimensionCount::from)
            .collect())
    }

    /// POTA activation rollup (park × operator × UTC-day) with unique/total QSO
    /// counts; `min_qsos` is the threshold for `successful`.
    pub fn qso_activation_rollup(
        &self,
        query: String,
        min_qsos: i64,
    ) -> Result<Vec<FfiActivationRollup>, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?;
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store
            .qso_activation_rollup(&parsed, min_qsos)?
            .into_iter()
            .map(FfiActivationRollup::from)
            .collect())
    }

    /// POTA activator awards progress (unique parks, WAS states, kilo/near-kilo,
    /// LaPorta, six-pack, …) over non-hidden park QSOs matching `query`. The app
    /// passes an empty query. Resolves `statesActivated` via the `pota_park`
    /// reference table with a Maidenhead grid fallback; faithful port of
    /// `POTAAwardsActor`.
    pub fn pota_awards(&self, query: String) -> Result<FfiPotaAwards, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?;
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.pota_awards(&parsed)?.into())
    }

    /// Worked grid tiles at `precision` (e.g. 4) over visible QSOs matching `query`.
    pub fn qso_grid_tiles(
        &self,
        query: String,
        precision: i64,
    ) -> Result<Vec<FfiGridTile>, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?;
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store
            .qso_grid_tiles(&parsed, precision)?
            .into_iter()
            .map(FfiGridTile::from)
            .collect())
    }

    /// WAS rollup (valid states worked overall + per mode family) over visible QSOs
    /// matching the DSL `query`.
    pub fn was_summary(&self, query: String) -> Result<FfiWasSummary, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?;
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.was_summary(&parsed)?.into())
    }

    /// America 250 WAS progress (states worked / per-mode-family in the 2026 window,
    /// + pipeline counts) over non-hidden 2026 QSOs with a state, matching `query`
    /// (the app passes an empty filter). Faithful port of `POTAAwardsActor.computeWAS250`.
    pub fn was250(&self, query: String) -> Result<FfiWas250, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?;
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.was250(&parsed)?.into())
    }

    /// WAS drilldown (per source × mode × state: count + distinct callsigns) over
    /// visible QSOs matching the DSL `query`. Faithful port of `StatsComputationActor`'s
    /// `wasData`.
    pub fn was_drilldown(&self, query: String) -> Result<Vec<FfiWasDrilldownRow>, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?;
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.was_drilldown(&parsed)?.into_iter().map(FfiWasDrilldownRow::from).collect())
    }

    /// Worked DXCC entities (id + name + lat/lon + count) over visible QSOs matching
    /// the DSL `query`, most-frequent first.
    pub fn dxcc_worked(&self, query: String) -> Result<Vec<FfiDxccWorked>, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?;
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.dxcc_worked(&parsed)?.into_iter().map(FfiDxccWorked::from).collect())
    }

    /// Per-service uploaded/pending unique-QSO counts over non-hidden QSOs matching the
    /// DSL `query`. `primary_callsign` (when set) and `configured_services` restrict the
    /// pending side, mirroring `PresenceComputationActor.computeCounts`.
    pub fn service_presence_counts(
        &self,
        query: String,
        primary_callsign: Option<String>,
        configured_services: Vec<String>,
    ) -> Result<Vec<FfiServicePresenceCount>, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?;
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store
            .service_presence_counts(&parsed, primary_callsign.as_deref(), &configured_services)?
            .into_iter()
            .map(FfiServicePresenceCount::from)
            .collect())
    }

    /// Per-park activity rollup (activation days + hunt QSOs + last-worked) over visible
    /// QSOs matching the DSL `query`.
    pub fn qso_park_rollup(&self, query: String) -> Result<Vec<FfiParkRollup>, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?;
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.qso_park_rollup(&parsed)?.into_iter().map(FfiParkRollup::from).collect())
    }

    /// Per-state QSO counts (valid 50 states) over visible QSOs matching the DSL `query`.
    pub fn qso_state_counts(&self, query: String) -> Result<Vec<FfiStateCount>, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?;
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.qso_state_counts(&parsed)?.into_iter().map(FfiStateCount::from).collect())
    }

    /// Equipment rollup over the `logging_session` table (per kind+name). No DSL filter —
    /// sessions are not QSO-queryable.
    pub fn session_equipment_rollup(&self) -> Result<Vec<FfiSessionEquipmentRollup>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store
            .session_equipment_rollup()?
            .into_iter()
            .map(FfiSessionEquipmentRollup::from)
            .collect())
    }

    /// Rig+antenna combo rollup over the `logging_session` table.
    pub fn session_combo_rollup(&self) -> Result<Vec<FfiSessionComboRollup>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store
            .session_combo_rollup()?
            .into_iter()
            .map(FfiSessionComboRollup::from)
            .collect())
    }

    /// Per-equipment-item QSO breakdown (totals, distance extremes, band/mode tallies) for
    /// the item named `name`. Faithful port of `EquipmentItemDetailActor.computeQSOStats`.
    pub fn session_item_detail(&self, name: String) -> Result<FfiSessionItemDetail, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.session_item_detail(&name)?.into())
    }

    /// Distance-shaped brag-sheet stats (furthest contacts, per-band, average, lowest power,
    /// best watts-per-mile) over visible QSOs matching the DSL `query` within the inclusive
    /// `[start, end]` unix-second window (the brag period; pass `None`/`None` for all-time).
    /// Faithful port of `BragSheetComputationActor`'s distance math.
    pub fn brag_distance_stats(
        &self,
        query: String,
        start: Option<i64>,
        end: Option<i64>,
    ) -> Result<FfiBragDistanceStats, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?.with_date_window(start, end);
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.brag_distance_stats(&parsed)?.into())
    }

    /// Streak-shaped brag-sheet stats (on-air / activation / per-mode day streaks) over visible
    /// QSOs matching the DSL `query` within the `[start, end]` window, relative to `today` (a
    /// `YYYY-MM-DD` UTC calendar day). Faithful port of `BragSheetComputationActor`'s streak
    /// math, with all day-bucketing normalized to UTC.
    pub fn brag_streaks(
        &self,
        query: String,
        today: String,
        start: Option<i64>,
        end: Option<i64>,
    ) -> Result<FfiBragStreaks, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?.with_date_window(start, end);
        let today = chrono::NaiveDate::parse_from_str(&today, "%Y-%m-%d")
            .map_err(|err| CwError::Query { reason: format!("invalid today '{today}': {err}") })?;
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.brag_streaks(&parsed, today)?.into())
    }

    /// SQL-expressible volume / records / "fun" brag-sheet stats (most-QSOs-in-a-day/session,
    /// most countries/bands per day, busiest band/mode, most-active weekday, repeat customer,
    /// earliest/latest QSO, total distance, active modes) over visible QSOs matching the DSL
    /// `query` within the `[start, end]` window. Faithful port of the volume/fun/misc-totals set.
    pub fn brag_records(
        &self,
        query: String,
        start: Option<i64>,
        end: Option<i64>,
    ) -> Result<FfiBragRecords, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?.with_date_window(start, end);
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.brag_records(&parsed)?.into())
    }

    /// Session-/sequence-based brag-sheet stats (operating hours, fastest-10, best session
    /// rate, fastest activation, longest session, peak 15-min rate, largest Nfer) over visible
    /// QSOs matching the DSL `query` within the `[start, end]` window. Faithful port of the
    /// speed/rate/operating/longest-session/largest-Nfer math (fetch-and-fold).
    pub fn brag_session_stats(
        &self,
        query: String,
        start: Option<i64>,
        end: Option<i64>,
    ) -> Result<FfiBragSessionStats, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?.with_date_window(start, end);
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.brag_session_stats(&parsed)?.into())
    }

    /// Average RST strength (S) digit over visible QSOs matching the DSL `query` within the
    /// `[start, end]` window, or `None` when no QSO qualifies. Faithful port of
    /// `computeAverageRST`; the caller renders it as `String(format: "S%.1f", value)`.
    pub fn brag_average_rst(
        &self,
        query: String,
        start: Option<i64>,
        end: Option<i64>,
    ) -> Result<Option<f64>, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?.with_date_window(start, end);
        let store = self.inner.lock().expect("store mutex poisoned");
        store.brag_average_rst(&parsed).map_err(CwError::from)
    }

    /// The DISTINCT uppercased QSO callsigns (over visible QSOs matching the DSL `query` within the
    /// `[start, end]` window) that are in the (uppercased) `members` set, sorted ascending. Supplies
    /// the worked-member set for the club brag stats; the club→callsign mapping stays app-side.
    /// Empty `members` → empty list.
    pub fn worked_member_callsigns(
        &self,
        query: String,
        members: Vec<String>,
        start: Option<i64>,
        end: Option<i64>,
    ) -> Result<Vec<String>, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?.with_date_window(start, end);
        let store = self.inner.lock().expect("store mutex poisoned");
        store.worked_member_callsigns(&parsed, &members).map_err(CwError::from)
    }

    /// Geographic-reach brag-sheet stats (DXCC entities, new-this-period, states, grid squares,
    /// continents, most-continents-in-a-day, WAS progress) over visible QSOs matching the DSL
    /// `query` within the `[start, end]` window. Faithful port of the `computeGeoStat` set.
    pub fn brag_geographic(
        &self,
        query: String,
        start: Option<i64>,
        end: Option<i64>,
    ) -> Result<FfiBragGeographic, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?.with_date_window(start, end);
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.brag_geographic(&parsed)?.into())
    }

    /// POTA-category brag-sheet stats (parks activated / hunted, park-to-park, best activation,
    /// new-this-period parks) over visible QSOs matching the DSL `query` within the `[start, end]`
    /// window. Faithful port of `BragSheetComputationActor+POTA`.
    pub fn brag_pota(
        &self,
        query: String,
        start: Option<i64>,
        end: Option<i64>,
    ) -> Result<FfiBragPota, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?.with_date_window(start, end);
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.brag_pota(&parsed)?.into())
    }

    /// SQL-trivial brag-sheet period metrics over visible QSOs matching the DSL `query` within the
    /// inclusive `[start, end]` unix-second window (the brag period; `None`/`None` for all-time).
    pub fn brag_period_metrics(
        &self,
        query: String,
        start: Option<i64>,
        end: Option<i64>,
    ) -> Result<FfiBragPeriodMetrics, CwError> {
        let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?.with_date_window(start, end);
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.brag_period_metrics(&parsed)?.into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn query_qso(id_call: &str, band: &str, mode: &str) -> FfiQueryQso {
        FfiQueryQso {
            callsign: Some(id_call.into()),
            band: Some(band.into()),
            mode: Some(mode.into()),
            my_callsign: None,
            park: None,
            sota_ref: None,
            their_grid: None,
            state: None,
            country: None,
            name: None,
            qth: None,
            notes: None,
            my_grid: None,
            frequency_khz: None,
            dxcc: None,
            power: None,
            qso_date: 0,
            qrz_confirmed: false,
            lotw_confirmed: false,
            import_source: "logger".into(),
        }
    }

    #[test]
    fn query_filter_returns_matching_indices() {
        let qsos = vec![
            query_qso("W1AW", "20m", "FT8"),
            query_qso("K6ABC", "40m", "CW"),
            query_qso("VK3XYZ", "20m", "SSB"),
        ];
        // band:20m → indices 0 and 2
        assert_eq!(query_filter("band:20m".into(), qsos_clone(&qsos)).unwrap(), vec![0, 2]);
        // bare callsign prefix
        assert_eq!(query_filter("W1".into(), qsos_clone(&qsos)).unwrap(), vec![0]);
        // empty query → everything
        assert_eq!(query_filter("".into(), qsos_clone(&qsos)).unwrap(), vec![0, 1, 2]);
        // negation
        assert_eq!(query_filter("-band:20m".into(), qsos_clone(&qsos)).unwrap(), vec![1]);
        // parse error surfaces
        assert!(query_filter("band:".into(), qsos_clone(&qsos)).is_err());
    }

    // FfiQueryQso isn't Clone (uniffi::Record), so rebuild the fixture per call.
    fn qsos_clone(_src: &[FfiQueryQso]) -> Vec<FfiQueryQso> {
        vec![
            query_qso("W1AW", "20m", "FT8"),
            query_qso("K6ABC", "40m", "CW"),
            query_qso("VK3XYZ", "20m", "SSB"),
        ]
    }

    #[test]
    fn analyze_query_through_ffi_layer() {
        let analysis = analyze_query("notes:foo".into(), 50_000).unwrap();
        assert!(!analysis.uses_index);
        assert!(analysis.requires_confirmation);
        assert!(matches!(analysis.cost, FfiQueryCost::FullScan));
    }

    #[test]
    fn validate_query_reports_errors() {
        assert!(validate_query("band:20m".into()).is_ok());
        assert!(validate_query("bogus:1".into()).is_err());
    }

    #[test]
    fn upsert_qsos_batch_commits_and_is_idempotent() {
        let store = FieldStore::open_in_memory("k".into()).unwrap();
        let batch = || {
            vec![
                FfiQso { id: "a".into(), callsign: "W1AW".into(), qso_date: 1000, ..Default::default() },
                FfiQso { id: "b".into(), callsign: "K2XX".into(), qso_date: 2000, ..Default::default() },
            ]
        };
        store.upsert_qsos(batch()).unwrap();
        assert_eq!(store.qso_count().unwrap(), 2);
        // Re-running the same batch upserts in place — no duplicate rows.
        store.upsert_qsos(batch()).unwrap();
        assert_eq!(store.qso_count().unwrap(), 2);
        // Empty batch is a no-op.
        store.upsert_qsos(Vec::new()).unwrap();
        assert_eq!(store.qso_count().unwrap(), 2);
    }

    #[test]
    fn fetch_qsos_query_filters_by_dsl() {
        let store = FieldStore::open_in_memory("k".into()).unwrap();
        store
            .upsert_qso(FfiQso {
                id: "a".into(),
                callsign: "W1AW".into(),
                band: Some("20m".into()),
                mode: Some("FT8".into()),
                qso_date: 1000,
                ..Default::default()
            })
            .unwrap();
        store
            .upsert_qso(FfiQso {
                id: "b".into(),
                callsign: "K2XX".into(),
                band: Some("40m".into()),
                mode: Some("CW".into()),
                qso_date: 2000,
                ..Default::default()
            })
            .unwrap();
        let rows = store.fetch_qsos_query("band:20m".to_string(), 100, 0).unwrap();
        assert_eq!(
            rows.iter().map(|r| r.id.clone()).collect::<Vec<_>>(),
            vec!["a"]
        );
        assert_eq!(store.qso_count_query("band:20m".to_string()).unwrap(), 1);
    }

    #[test]
    fn fetch_qsos_query_projects_presence() {
        let store = FieldStore::open_in_memory("k".into()).unwrap();
        store
            .upsert_qso(FfiQso {
                id: "a".into(),
                callsign: "W1AW".into(),
                band: Some("20m".into()),
                qso_date: 1000,
                ..Default::default()
            })
            .unwrap();
        store
            .upsert_qso(FfiQso {
                id: "b".into(),
                callsign: "K2XX".into(),
                band: Some("20m".into()),
                qso_date: 2000,
                ..Default::default()
            })
            .unwrap();
        // Two presence rows on "a", none on "b".
        store
            .upsert_service_presence(FfiServicePresence {
                id: "sp1".into(),
                service_type_raw_value: "pota".into(),
                is_present: true,
                qso_id: Some("a".into()),
                ..Default::default()
            })
            .unwrap();
        store
            .upsert_service_presence(FfiServicePresence {
                id: "sp2".into(),
                service_type_raw_value: "lotw".into(),
                is_submitted: true,
                qso_id: Some("a".into()),
                ..Default::default()
            })
            .unwrap();

        let rows = store.fetch_qsos_query("band:20m".to_string(), 100, 0).unwrap();
        let row_a = rows.iter().find(|r| r.id == "a").unwrap();
        let row_b = rows.iter().find(|r| r.id == "b").unwrap();
        assert_eq!(row_a.presence.len(), 2);
        assert!(row_b.presence.is_empty());
        let services: std::collections::HashSet<&str> = row_a
            .presence
            .iter()
            .map(|sp| sp.service_type_raw_value.as_str())
            .collect();
        assert!(services.contains("pota"));
        assert!(services.contains("lotw"));
    }

    #[test]
    fn fetch_qsos_query_reports_parse_error() {
        let store = FieldStore::open_in_memory("k".into()).unwrap();
        let result = store.fetch_qsos_query("bogus:1".to_string(), 100, 0);
        let err = result.err().expect("expected an error");
        assert!(matches!(err, CwError::Query { .. }));
    }

    #[test]
    fn store_round_trip_through_ffi_layer() {
        let store = FieldStore::open_in_memory("k".into()).unwrap();
        store
            .upsert_qso(FfiQso {
                id: "1".into(),
                callsign: "W1AW".into(),
                band: Some("20m".into()),
                mode: Some("FT8".into()),
                freq_khz: Some(14_074.0),
                qso_date: 1000,
                their_grid: Some("EM12".into()),
                notes: Some("hi".into()),
                power: Some(5),
                dirty: true,
                ..Default::default()
            })
            .unwrap();
        assert_eq!(store.qso_count().unwrap(), 1);
        let rows = store.fetch_qsos(FfiQsoFilter::default(), 10, 0).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].callsign, "W1AW");
        // New fidelity fields round-trip through the FFI value type.
        assert_eq!(rows[0].their_grid.as_deref(), Some("EM12"));
        assert_eq!(rows[0].power, Some(5));
    }
}
