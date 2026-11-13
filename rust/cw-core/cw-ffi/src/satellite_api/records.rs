//! FFI DTOs for the satellite surface. Plain scalars/Options/Vecs; epochs
//! are unix seconds; frequencies are Hz (matching SatNOGS) except the
//! explicit `*_mhz` fields.

use cw_domain::satellite::alert_planner::PlannedAlert;
use cw_domain::satellite::mode_category::ModeCategory;
use cw_domain::satellite::mutual::{MutualPass, MutualSample};
use cw_domain::satellite::pass_predictor::{PassForecast, SatPass, UpcomingPass};
use cw_domain::satellite::polarization::Polarization;
use cw_domain::satellite::tracker::SatPosition;
use cw_domain::satellite::{Observer, SatTransmitter};

/// Observer site (geodetic degrees; altitude fixed at sea level like iOS).
#[derive(uniffi::Record, Clone, Copy)]
pub struct FfiObserver {
    pub lat_deg: f64,
    pub lon_deg: f64,
}

impl From<FfiObserver> for Observer {
    fn from(observer: FfiObserver) -> Observer {
        Observer::new(observer.lat_deg, observer.lon_deg)
    }
}

#[derive(uniffi::Enum, Clone, Copy, PartialEq, Eq, Debug)]
pub enum FfiSatModeCategory {
    VoiceFm,
    Linear,
    Morse,
    Digital,
}

impl From<ModeCategory> for FfiSatModeCategory {
    fn from(category: ModeCategory) -> Self {
        match category {
            ModeCategory::VoiceFm => FfiSatModeCategory::VoiceFm,
            ModeCategory::Linear => FfiSatModeCategory::Linear,
            ModeCategory::Morse => FfiSatModeCategory::Morse,
            ModeCategory::Digital => FfiSatModeCategory::Digital,
        }
    }
}

impl From<FfiSatModeCategory> for ModeCategory {
    fn from(category: FfiSatModeCategory) -> Self {
        match category {
            FfiSatModeCategory::VoiceFm => ModeCategory::VoiceFm,
            FfiSatModeCategory::Linear => ModeCategory::Linear,
            FfiSatModeCategory::Morse => ModeCategory::Morse,
            FfiSatModeCategory::Digital => ModeCategory::Digital,
        }
    }
}

#[derive(uniffi::Record, Clone)]
pub struct FfiSatTransmitter {
    pub description: String,
    pub transmitter_type: String,
    pub alive: bool,
    pub is_active: bool,
    pub mode: Option<String>,
    pub mode_category: FfiSatModeCategory,
    pub uplink_low_hz: Option<i64>,
    pub downlink_low_hz: Option<i64>,
    /// Upper passband edges for linear transponders; `None` for FM
    /// channels and beacons.
    pub uplink_high_hz: Option<i64>,
    pub downlink_high_hz: Option<i64>,
    /// Inverting transponder: a dial move up on the downlink is a move down
    /// on the uplink (SatNOGS `invert`).
    pub invert: bool,
    /// True when an AMSAT capability row vouches for this transmitter's
    /// mode category (untracked capabilities get no heard/silent signal).
    pub amsat_tracked: bool,
    /// Freshest positive AMSAT report for this capability — the hosts'
    /// per-row heard-today dot (green within 24 h, gray when tracked but
    /// older/never).
    pub amsat_last_heard_epoch: Option<i64>,
}

impl FfiSatTransmitter {
    /// Build with the per-capability AMSAT signal for the transmitter's
    /// mode category (`workability::capability_status` over the bird's
    /// status rows).
    pub(super) fn with_amsat(
        transmitter: &SatTransmitter,
        amsat_rows: &[cw_domain::satellite::amsat::AmsatStatus],
    ) -> Self {
        let category = ModeCategory::for_transmitter(transmitter);
        let (tracked, last_heard) =
            cw_domain::satellite::workability::capability_status(category, amsat_rows);
        FfiSatTransmitter {
            description: transmitter.description.clone(),
            transmitter_type: transmitter.transmitter_type.clone(),
            alive: transmitter.alive,
            is_active: transmitter.is_active(),
            mode: transmitter.mode.clone(),
            mode_category: category.into(),
            uplink_low_hz: transmitter.uplink_low_hz,
            downlink_low_hz: transmitter.downlink_low_hz,
            uplink_high_hz: transmitter.uplink_high_hz,
            downlink_high_hz: transmitter.downlink_high_hz,
            invert: transmitter.invert,
            amsat_tracked: tracked,
            amsat_last_heard_epoch: last_heard.map(|heard| heard.timestamp()),
        }
    }
}

#[derive(uniffi::Record, Clone)]
pub struct FfiSatPolarization {
    pub label: String,
    pub is_circular: bool,
    pub pointing_hint: String,
}

impl From<Polarization> for FfiSatPolarization {
    fn from(polarization: Polarization) -> Self {
        FfiSatPolarization {
            label: polarization.label().to_string(),
            is_circular: polarization.is_circular(),
            pointing_hint: polarization.pointing_hint().to_string(),
        }
    }
}

/// One catalog satellite: identity, transmitters (active first), curated
/// polarization, and the AMSAT community badge.
#[derive(uniffi::Record, Clone)]
pub struct FfiSatelliteSummary {
    pub norad_id: u32,
    pub name: String,
    pub detail_name: Option<String>,
    pub transmitters: Vec<FfiSatTransmitter>,
    pub polarization: Option<FfiSatPolarization>,
    pub amsat_last_heard_epoch: Option<i64>,
    pub amsat_last_report: Option<String>,
    pub amsat_last_callsign: Option<String>,
    pub amsat_last_grid: Option<String>,
    pub amsat_heard_reports_24h: i32,
    pub amsat_total_reports_24h: i32,
}

#[derive(uniffi::Record, Clone)]
pub struct FfiSatelliteSearchItem {
    pub norad_id: u32,
    pub name: String,
    pub detail_name: Option<String>,
}

/// Geodetic position + optional observer-relative look, with rates for
/// dead-reckoning (mirrors the Swift `SatellitePosition`).
#[derive(uniffi::Record, Clone)]
pub struct FfiSatellitePosition {
    pub norad_id: u32,
    pub name: String,
    pub detail_name: Option<String>,
    pub lat_deg: f64,
    pub lon_deg: f64,
    pub alt_km: f64,
    pub lat_rate_deg_per_sec: f64,
    pub lon_rate_deg_per_sec: f64,
    pub azimuth_deg: Option<f64>,
    pub elevation_deg: Option<f64>,
    pub range_km: Option<f64>,
    pub az_rate_deg_per_sec: f64,
    pub el_rate_deg_per_sec: f64,
    pub range_rate_km_per_sec: f64,
    pub footprint_radius_m: f64,
}

impl From<&SatPosition> for FfiSatellitePosition {
    fn from(pos: &SatPosition) -> Self {
        FfiSatellitePosition {
            norad_id: pos.norad_id,
            name: pos.name.clone(),
            detail_name: pos.detail_name.clone(),
            lat_deg: pos.lat_deg,
            lon_deg: pos.lon_deg,
            alt_km: pos.alt_km,
            lat_rate_deg_per_sec: pos.lat_rate_deg_per_sec,
            lon_rate_deg_per_sec: pos.lon_rate_deg_per_sec,
            azimuth_deg: pos.azimuth_deg,
            elevation_deg: pos.elevation_deg,
            range_km: pos.range_km,
            az_rate_deg_per_sec: pos.az_rate_deg_per_sec,
            el_rate_deg_per_sec: pos.el_rate_deg_per_sec,
            range_rate_km_per_sec: pos.range_rate_km_per_sec,
            footprint_radius_m: pos.footprint_radius_m(),
        }
    }
}

/// Observer look sample for the pointing/sky-dome surfaces. `doppler_factor`
/// = −range_rate/c (iOS sign convention): downlink × (1 + factor),
/// uplink × (1 − factor).
#[derive(uniffi::Record, Clone)]
pub struct FfiSatelliteLook {
    pub azimuth_deg: f64,
    pub elevation_deg: f64,
    pub range_km: f64,
    pub az_rate_deg_per_sec: f64,
    pub el_rate_deg_per_sec: f64,
    pub range_rate_km_per_sec: f64,
    pub doppler_factor: f64,
}

#[derive(uniffi::Record, Clone)]
pub struct FfiSatellitePass {
    pub aos_epoch: i64,
    pub aos_azimuth_deg: f64,
    pub peak_epoch: i64,
    pub peak_azimuth_deg: f64,
    pub peak_elevation_deg: f64,
    pub peak_range_km: f64,
    pub los_epoch: i64,
    pub los_azimuth_deg: f64,
}

impl From<&SatPass> for FfiSatellitePass {
    fn from(pass: &SatPass) -> Self {
        FfiSatellitePass {
            aos_epoch: pass.aos.timestamp(),
            aos_azimuth_deg: pass.aos_azimuth_deg,
            peak_epoch: pass.peak.timestamp(),
            peak_azimuth_deg: pass.peak_azimuth_deg,
            peak_elevation_deg: pass.peak_elevation_deg,
            peak_range_km: pass.peak_range_km,
            los_epoch: pass.los.timestamp(),
            los_azimuth_deg: pass.los_azimuth_deg,
        }
    }
}

#[derive(uniffi::Record, Clone)]
pub struct FfiPassForecast {
    pub passes: Vec<FfiSatellitePass>,
    pub is_always_visible: bool,
}

impl From<&PassForecast> for FfiPassForecast {
    fn from(forecast: &PassForecast) -> Self {
        FfiPassForecast {
            passes: forecast.passes.iter().map(FfiSatellitePass::from).collect(),
            is_always_visible: forecast.is_always_visible,
        }
    }
}

#[derive(uniffi::Record, Clone)]
pub struct FfiUpcomingPass {
    pub norad_id: u32,
    pub name: String,
    pub detail_name: Option<String>,
    pub pass: FfiSatellitePass,
}

impl From<&UpcomingPass> for FfiUpcomingPass {
    fn from(upcoming: &UpcomingPass) -> Self {
        FfiUpcomingPass {
            norad_id: upcoming.norad_id,
            name: upcoming.name.clone(),
            detail_name: upcoming.detail_name.clone(),
            pass: FfiSatellitePass::from(&upcoming.pass),
        }
    }
}

#[derive(uniffi::Record, Clone)]
pub struct FfiMutualPass {
    pub norad_id: u32,
    pub name: String,
    pub detail_name: Option<String>,
    pub start_epoch: i64,
    pub end_epoch: i64,
    pub peak_epoch: i64,
    pub peak_min_elevation_deg: f64,
    pub peak_elevation_a_deg: f64,
    pub peak_elevation_b_deg: f64,
    /// Window geometry from STATION A's sky (° clockwise from north).
    pub start_azimuth_a_deg: f64,
    pub peak_azimuth_a_deg: f64,
    pub end_azimuth_a_deg: f64,
}

impl From<&MutualPass> for FfiMutualPass {
    fn from(pass: &MutualPass) -> Self {
        FfiMutualPass {
            norad_id: pass.norad_id,
            name: pass.name.clone(),
            detail_name: pass.detail_name.clone(),
            start_epoch: pass.start.timestamp(),
            end_epoch: pass.end.timestamp(),
            peak_epoch: pass.peak_date.timestamp(),
            peak_min_elevation_deg: pass.peak_min_elevation_deg,
            peak_elevation_a_deg: pass.peak_elevation_a_deg,
            peak_elevation_b_deg: pass.peak_elevation_b_deg,
            start_azimuth_a_deg: pass.start_azimuth_a_deg,
            peak_azimuth_a_deg: pass.peak_azimuth_a_deg,
            end_azimuth_a_deg: pass.end_azimuth_a_deg,
        }
    }
}

#[derive(uniffi::Record, Clone)]
pub struct FfiMutualSample {
    pub epoch: i64,
    pub lat_deg: f64,
    pub lon_deg: f64,
    pub alt_km: f64,
    pub elevation_a_deg: f64,
    pub elevation_b_deg: f64,
}

impl From<&MutualSample> for FfiMutualSample {
    fn from(sample: &MutualSample) -> Self {
        FfiMutualSample {
            epoch: sample.date.timestamp(),
            lat_deg: sample.lat_deg,
            lon_deg: sample.lon_deg,
            alt_km: sample.alt_km,
            elevation_a_deg: sample.elevation_a_deg,
            elevation_b_deg: sample.elevation_b_deg,
        }
    }
}

/// One planned pass alert: the host schedules the OS notification (exact
/// alarm on Android, `UNCalendarNotificationTrigger` on iOS) and reconciles
/// by `identifier` (`satpass-` prefixed, minute-rounded — stable under
/// ±30 s TLE drift).
#[derive(uniffi::Record, Clone)]
pub struct FfiPlannedAlert {
    pub identifier: String,
    pub fire_epoch: i64,
    pub title: String,
    pub body: String,
    pub norad_id: u32,
    pub satellite_name: String,
    pub aos_epoch: i64,
    pub los_epoch: i64,
    pub peak_elevation_deg: f64,
    pub aos_azimuth_deg: f64,
    pub los_azimuth_deg: f64,
    pub is_marginal: bool,
}

impl From<&PlannedAlert> for FfiPlannedAlert {
    fn from(alert: &PlannedAlert) -> Self {
        FfiPlannedAlert {
            identifier: alert.identifier.clone(),
            fire_epoch: alert.fire_at.timestamp(),
            title: alert.title.clone(),
            body: alert.body.clone(),
            norad_id: alert.norad_id,
            satellite_name: alert.satellite_name.clone(),
            aos_epoch: alert.aos.timestamp(),
            los_epoch: alert.los.timestamp(),
            peak_elevation_deg: alert.peak_elevation_deg,
            aos_azimuth_deg: alert.aos_azimuth_deg,
            los_azimuth_deg: alert.los_azimuth_deg,
            is_marginal: alert.is_marginal,
        }
    }
}

/// Input for the post-LOS quick log's born-completed pass session. Keeping
/// the 76-field `LoggingSession` construction in Rust means neither host
/// hand-builds the row (the iOS `SatelliteQuickLogService` predates this
/// and still builds its own; Android never should).
#[derive(uniffi::Record, Clone)]
pub struct FfiPassSessionInput {
    pub my_callsign: String,
    pub my_grid: Option<String>,
    pub mode: String,
    /// ADIF convention: FREQ/BAND = your transmit side = the uplink, MHz.
    pub frequency_mhz: Option<f64>,
    /// Short OSCAR designator — becomes the session title "<sat> pass".
    pub sat_name: String,
    pub started_at_epoch: i64,
    pub ended_at_epoch: i64,
}

#[derive(uniffi::Record, Clone)]
pub struct FfiSatelliteRefreshSummary {
    pub satellite_count: u32,
    pub tles_fetched_at_epoch: i64,
    /// True when the network refresh failed and the catalog was built from
    /// an expired cache (degrade-to-stale).
    pub tles_stale: bool,
    /// False when the AMSAT enrichment was unavailable (soft failure).
    pub amsat_available: bool,
}

/// Input for `SatelliteApi.build_doppler_schedule` — one pass, one
/// transponder. Steps must be multiples of 10 Hz.
#[derive(uniffi::Record, Clone, Copy)]
pub struct FfiDopplerScheduleInput {
    pub norad_id: u32,
    pub observer: FfiObserver,
    pub aos_epoch: i64,
    pub los_epoch: i64,
    /// Transponder downlink center, Hz.
    pub downlink_hz: u64,
    /// Transponder uplink center, Hz; None = downlink-only tracking.
    pub uplink_hz: Option<u64>,
    pub downlink_step_hz: u32,
    pub uplink_step_hz: u32,
}

/// Bridge-ready doppler schedule: the `SatScheduleBegin` header fields plus
/// packed step chunks sized for one `SatScheduleChunk` BLE notification each.
#[derive(uniffi::Record, Clone)]
pub struct FfiDopplerSchedule {
    pub downlink_start_hz: u64,
    pub uplink_start_hz: u64,
    pub duration_ms: u64,
    pub total_steps: u32,
    /// `cw-sat-core` packed 6-byte steps, ≤30 steps per chunk.
    pub chunks: Vec<Vec<u8>>,
}

// MARK: - Community activity (AMSAT grid)

/// How a grid cell is coloured — amsat.org's legend plus `Quiet` (no
/// reports). Mirrors `cw_domain::satellite::amsat::ActivityStatus`.
#[derive(uniffi::Enum, Clone, Copy, PartialEq, Eq, Debug)]
pub enum FfiActivityStatus {
    Quiet,
    Heard,
    TelemetryOnly,
    NotHeard,
    Conflicting,
}

impl From<cw_domain::satellite::amsat::ActivityStatus> for FfiActivityStatus {
    fn from(status: cw_domain::satellite::amsat::ActivityStatus) -> Self {
        use cw_domain::satellite::amsat::ActivityStatus;
        match status {
            ActivityStatus::Quiet => FfiActivityStatus::Quiet,
            ActivityStatus::Heard => FfiActivityStatus::Heard,
            ActivityStatus::TelemetryOnly => FfiActivityStatus::TelemetryOnly,
            ActivityStatus::NotHeard => FfiActivityStatus::NotHeard,
            ActivityStatus::Conflicting => FfiActivityStatus::Conflicting,
        }
    }
}

/// One occupied cell of a satellite's activity row (cells with no reports
/// are omitted; `start_epoch` is the cell's inclusive start).
#[derive(uniffi::Record, Clone)]
pub struct FfiActivityBucket {
    pub start_epoch: i64,
    pub heard: i32,
    pub not_heard: i32,
    pub telemetry: i32,
    pub crew: i32,
    pub other: i32,
    pub total: i32,
    pub status: FfiActivityStatus,
}

impl From<&cw_domain::satellite::amsat::ActivityBucket> for FfiActivityBucket {
    fn from(bucket: &cw_domain::satellite::amsat::ActivityBucket) -> Self {
        FfiActivityBucket {
            start_epoch: bucket.start.timestamp(),
            heard: bucket.heard,
            not_heard: bucket.not_heard,
            telemetry: bucket.telemetry,
            crew: bucket.crew,
            other: bucket.other,
            total: bucket.total(),
            status: bucket.status().into(),
        }
    }
}

/// One AMSAT-tracked transmitter ("SO-50_[FM]") with its activity cells
/// and everything the engine could attach from its other sources: the
/// catalog identity (SatNOGS TLE + canonical name), the matching SatNOGS
/// transmitter, the observer's next pass, and the operator's own QSOs
/// through it in the window.
#[derive(uniffi::Record, Clone)]
pub struct FfiCommunityActivityRow {
    /// AMSAT's internal name, e.g. `AO-7_[U/v]`.
    pub amsat_name: String,
    /// The satellite part of the AMSAT name: `AO-7`.
    pub base_name: String,
    /// The bracket tag: `U/v`, `FM`, `SSDV`, … (None when the name has none).
    pub capability: Option<String>,
    /// NORAD id when the server's curated mapping knows it.
    pub norad_id: Option<u32>,
    /// True when the bird is in the engine's workable catalog (so it can be
    /// selected on the map and has passes).
    pub in_catalog: bool,
    /// Catalog short name (OSCAR designator) when in the catalog, else the
    /// AMSAT base name.
    pub display_name: String,
    pub detail_name: Option<String>,
    /// Mode bucket the capability tag vouches for (None when unrecognized).
    pub mode_category: Option<FfiSatModeCategory>,
    /// Best-matching catalog transmitter for the capability: SatNOGS mode
    /// string and frequencies, and whether SatNOGS still calls it active.
    pub transmitter_mode: Option<String>,
    pub downlink_low_hz: Option<i64>,
    pub uplink_low_hz: Option<i64>,
    pub transmitter_active: Option<bool>,
    /// Most recent positive community report for this capability.
    pub last_heard_epoch: Option<i64>,
    pub heard_reports_24h: i32,
    pub total_reports_24h: i32,
    /// The observer's next pass of this bird (when an observer was given
    /// and the bird is in the catalog), within the forecast window.
    pub next_pass: Option<FfiSatellitePass>,
    /// QSOs in the operator's log with this satellite's `SAT_NAME` inside
    /// the activity window.
    pub my_qso_count: u32,
    /// Occupied cells, ascending by start.
    pub buckets: Vec<FfiActivityBucket>,
}

/// The whole community-activity grid for one window.
#[derive(uniffi::Record, Clone)]
pub struct FfiCommunityActivity {
    pub window_start_epoch: i64,
    pub window_end_epoch: i64,
    /// Width of every bucket in seconds (the server's hour unless a coarser
    /// `cell_secs` was requested).
    pub bucket_secs: i64,
    /// When the server last refreshed from AMSAT, if it said.
    pub updated_at_epoch: Option<i64>,
    /// When this payload was fetched (or last fetched, when stale).
    pub fetched_at_epoch: i64,
    /// True when the network refresh failed and an expired cache served.
    pub is_stale: bool,
    /// Rows in AMSAT's order.
    pub rows: Vec<FfiCommunityActivityRow>,
}

// MARK: - Community reports (one bird)

/// One community report, placed at the reporter's grid square when they
/// gave one.
#[derive(uniffi::Record, Clone)]
pub struct FfiCommunityReport {
    pub amsat_name: String,
    pub epoch: i64,
    pub callsign: String,
    pub grid: Option<String>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    /// Verdict verbatim ("Heard", "Not Heard", "Telemetry Only", …).
    pub report: String,
    /// The legend colour of this one report.
    pub status: FfiActivityStatus,
}

/// What the community saw on the bird's previous orbit.
#[derive(uniffi::Record, Clone)]
pub struct FfiPreviousOrbit {
    pub period_minutes: f64,
    pub window_start_epoch: i64,
    pub heard: u32,
    pub telemetry: u32,
    pub not_heard: u32,
    /// Distinct callsigns that heard it, newest first (≤ 6).
    pub heard_callsigns: Vec<String>,
    pub status: FfiActivityStatus,
}

/// What the operator files with AMSAT: their own observation of one
/// transmitter, under their own callsign, at the time it was made.
#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiCommunityReportSubmission {
    /// AMSAT's API name for the transmitter, e.g. `SO-50_[FM]`.
    pub amsat_name: String,
    /// One of `amsat_report_values()` (case-insensitive).
    pub report: String,
    pub callsign: String,
    /// Maidenhead locator (4 or 6 characters); None/empty omits it.
    pub grid: Option<String>,
    /// When the bird was heard (or not) — never "now" by default unless
    /// the operator is reporting what they're hearing right now.
    pub reported_at_epoch: i64,
}

/// AMSAT's acknowledgement of a filed report.
#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiCommunityReportReceipt {
    pub id: i64,
    pub amsat_name: String,
    /// AMSAT's hour-quantised stamp for the report.
    pub reported_at_epoch: i64,
    pub report: String,
    pub callsign: String,
    /// Earlier reports by the same callsign for the same satellite, hour
    /// and 15-minute period that this one replaced.
    pub replaced_count: u32,
}

#[derive(uniffi::Record, Clone)]
pub struct FfiCommunityReports {
    pub norad_id: u32,
    pub window_start_epoch: i64,
    pub window_end_epoch: i64,
    pub fetched_at_epoch: i64,
    pub is_stale: bool,
    /// Newest first.
    pub reports: Vec<FfiCommunityReport>,
    /// None when the bird isn't in the catalog (no orbital period).
    pub previous_orbit: Option<FfiPreviousOrbit>,
}
