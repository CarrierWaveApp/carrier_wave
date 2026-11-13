//! FFI record/enum shapes for [`super::PropagationApi`]. Ports the model shapes
//! in `swift/ios/CarrierWave/Models/PropagationCheck.swift` and the enriched
//! spot from `PropagationCheckEnrichment.swift`.

/// Frozen-at-start configuration for a propagation check. Port of the Swift
/// `PropagationCheckConfig`.
#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiPropagationConfig {
    /// Callsign to match spots against (suffix-tolerant — see
    /// [`super::callsign_matches`]).
    pub callsign: String,
    /// Bands the user chose to watch (`"20m"`, `"40m"`, …). Empty = all bands.
    pub bands: Vec<String>,
    /// Operator's Maidenhead grid at session start (frozen for distances).
    pub user_grid: String,
    /// Session start, Unix epoch seconds.
    pub started_at_epoch: f64,
    /// Solar / space-weather snapshot captured by the host at session start.
    ///
    /// Host-supplied on purpose: the engine stays store-/`UserDefaults`-free and
    /// canned-testable. The Swift `recordSolarConditions()` fetch (gated on the
    /// `autoRecordConditions` `UserDefault`) stays host-side — the host does the
    /// fetch, applies the gate, and hands the result (or `None`) in here. Ported
    /// from `PropagationCheckSession.Snapshot`'s `solar*` fields.
    pub solar: Option<FfiPropagationSolar>,
}

/// Solar / space-weather conditions captured at session start. Port of the
/// `solar*` fields on `PropagationCheckSession.Snapshot` (sourced from the Swift
/// `SolarConditions` / `NOAAClient.fetchSolarConditions`). All fields are
/// optional because the upstream fetch can partially populate. `None` for the
/// whole record means the host skipped or failed the fetch (offline, or the
/// `autoRecordConditions` gate was off) — exactly the Swift `recordedSolar ==
/// nil` case.
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct FfiPropagationSolar {
    pub k_index: Option<f64>,
    pub a_index: Option<i32>,
    pub flux: Option<f64>,
    pub sunspots: Option<i32>,
    pub propagation_rating: Option<String>,
    pub band_conditions: Option<String>,
    /// Snapshot time, Unix epoch seconds.
    pub timestamp_epoch: Option<f64>,
}

/// Why a session stopped. FFI mirror of the Swift `PropagationStopReason`
/// (`user` / `duration` / `radio-fault`); the codebase prefers `uniffi::Enum`
/// over stringly-typed reasons. The persisted artifact renders it
/// (`PropagationCheckResultsView` :238).
#[derive(uniffi::Enum, Clone, Copy, PartialEq, Eq, Debug)]
pub enum FfiPropagationStopReason {
    /// User tapped Stop. Swift `.user`.
    User,
    /// The session hit its duration cap. Swift `.duration`.
    Duration,
    /// A radio fault aborted the session (Auto-CQ). Swift `.radioFault`.
    RadioFault,
}

/// A recorded network outage during a session, surfaced on the artifact for
/// transparency. Port of the Swift `PropagationConnectivityGap`. A gap opens on
/// the first failed fetch of a source and closes on the next successful fetch of
/// that source (or in `stop()` if still open at teardown).
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct FfiPropagationConnectivityGap {
    /// `"rbn"` | `"pskr"` — the raw values of the Swift `PropagationSpotSource`,
    /// matching the persisted artifact's decoder.
    pub source: String,
    /// Gap open, Unix epoch seconds.
    pub started_at_epoch: f64,
    /// Gap close, Unix epoch seconds.
    pub ended_at_epoch: f64,
}

/// The `PropagationSpotSource` raw values (`"rbn"` / `"pskr"`).
pub const SOURCE_RBN: &str = "rbn";
pub const SOURCE_PSKR: &str = "pskr";

/// A single collected spot. Port of the Swift `PropagationSpotEntry` (the
/// opaque-blob element).
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct FfiPropagationSpot {
    /// `"rbn"` | `"pskr"`.
    pub source: String,
    /// Skimmer / receiver callsign that heard us.
    pub skimmer_call: String,
    /// Grid as the source reported it (before enrichment), if any.
    pub skimmer_grid: Option<String>,
    /// Frequency in Hz.
    pub freq_hz: i64,
    /// Derived band (`None` when out of any band).
    pub band: Option<String>,
    pub mode: String,
    /// Signal-to-noise ratio in dB, if reported.
    pub snr_db: Option<f64>,
    /// Spot time, Unix epoch seconds.
    pub timestamp_epoch: f64,
}

/// A spot augmented with derived geographic data — effective grid (after the
/// enrichment waterfall), coordinate, distance, and bearing from the operator's
/// grid. Port of the Swift `PropagationEnrichedSpot`.
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct FfiPropagationEnrichedSpot {
    /// Dedup key (matches `PropagationCheck.dedupKey`).
    pub id: String,
    pub spot: FfiPropagationSpot,
    /// Grid used for projection (reported grid, else the enriched fallback).
    pub effective_grid: Option<String>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub distance_km: Option<f64>,
    pub bearing: Option<f64>,
}

/// Live session snapshot returned by [`super::PropagationApi::poll`]:
/// enriched windowed spots plus rolling headline stats. Mirrors the observable
/// surface of the Swift `PropagationCheckSession`.
#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiPropagationState {
    pub is_running: bool,
    pub enriched_spots: Vec<FfiPropagationEnrichedSpot>,
    pub total_spots: i64,
    pub unique_skimmers: i64,
    pub bands_with_activity: Vec<String>,
    pub max_distance_km: f64,
    pub peak_snr_db: f64,
    pub rbn_connected: bool,
    pub pskr_connected: bool,
    /// Most recent per-source failure message, if any.
    pub last_error: Option<String>,
}

/// Final finalized snapshot from [`super::PropagationApi::results`]. Carries the
/// full (un-windowed) spot list and the derived headline totals used to persist
/// a `PropagationCheck` artifact.
#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiPropagationResults {
    pub callsign: String,
    pub user_grid: String,
    pub bands_requested: Vec<String>,
    pub started_at_epoch: f64,
    pub ended_at_epoch: f64,
    pub spots: Vec<FfiPropagationSpot>,
    pub enriched_spots: Vec<FfiPropagationEnrichedSpot>,
    pub total_spots: i64,
    pub unique_skimmers: i64,
    pub bands_with_activity: Vec<String>,
    pub max_distance_km: f64,
    pub peak_snr_db: f64,
    /// Network outages recorded during the session, in the order they closed.
    /// Port of `PropagationCheckSession.connectivityGaps` — the iOS saved-results
    /// UI (`PropagationCheckResultsView` :21-23,238-255) renders these.
    pub connectivity_gaps: Vec<FfiPropagationConnectivityGap>,
    /// The host-supplied solar snapshot, threaded through verbatim from the
    /// config. `None` when the host didn't record conditions.
    pub solar: Option<FfiPropagationSolar>,
    /// Why the session stopped. Stamped by [`super::PropagationApi::stop`].
    /// Defaults to [`FfiPropagationStopReason::User`] if `results()` is read
    /// before `stop()`.
    pub stop_reason: FfiPropagationStopReason,
}
