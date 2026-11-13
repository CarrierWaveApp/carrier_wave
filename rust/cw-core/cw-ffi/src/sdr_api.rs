//! Async SDR (KiwiSDR) API over UniFFI — receiver directory search, `/status`
//! enrichment, Tune-In candidate selection, the live audio connection, and the
//! QSY / receiver-quality monitors. Port of the iOS `Services/WebSDR/` stack:
//! `WebSDRDirectory`, `KiwiSDRStatusFetcher`, `KiwiSDRClient`,
//! `TuneInManager+ReceiverSelection`, and `TuneInManager+SmartFeatures`.
//!
//! The host keeps only playback and persistence: the audio ring buffer +
//! engine, the recording file writer, and followed-activator storage. Decoded
//! PCM frames stream to the host through the [`SdrAudioListener`] callback
//! (batched per websocket frame — never per sample).

use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use cw_domain::kiwisdr::{
    detect_qsy, filter_available, suggest_better_receiver, CandidateAccumulator, KiwiSdrMode,
    KiwiSdrReceiver, QsyObservation, ReceiverStatus, TuneInStrategy,
};
use cw_domain::BandUtilities;
use cw_net::{
    HamdbClient, HttpClient, KiwiSdrDirectoryClient, KiwiSdrError, KiwiSdrEvent,
    KiwiSdrStatusClient, RbnClient,
};

use crate::CwError;

/// Directory search radius in km (regional — same state or neighboring
/// states), matching `WebSDRDirectory.findNearby`'s default.
const MAX_RECEIVER_DISTANCE_KM: f64 = 500.0;

/// QSY monitor poll interval (seconds), matching `startQSYMonitor`.
const QSY_POLL_SECONDS: u64 = 45;

/// Receiver-quality monitor poll interval (seconds), matching
/// `startReceiverMonitor`.
const RECEIVER_MONITOR_POLL_SECONDS: u64 = 120;

// ---------------------------------------------------------------------------
// FFI DTOs
// ---------------------------------------------------------------------------

/// A KiwiSDR receiver from the public directory (plus enrichment).
#[derive(uniffi::Record, Clone)]
pub struct FfiKiwiReceiver {
    /// `host:port`.
    pub id: String,
    pub name: String,
    pub host: String,
    pub port: u16,
    pub latitude: f64,
    pub longitude: f64,
    pub bands: String,
    pub users: i32,
    pub max_users: i32,
    pub location: String,
    pub antenna: String,
    pub distance_km: Option<f64>,
    pub snr_all: Option<i32>,
    pub snr_hf: Option<i32>,
    pub ant_connected: Option<bool>,
    pub grid: Option<String>,
    pub asl: Option<i32>,
    pub enriched_antenna: Option<String>,
    pub is_available: bool,
}

/// Enriched `/status` data for a single receiver.
#[derive(uniffi::Record, Clone)]
pub struct FfiReceiverStatus {
    /// `host:port`.
    pub host_port: String,
    pub antenna: String,
    pub bands_hz: Option<String>,
    pub snr_all: Option<i32>,
    pub snr_hf: Option<i32>,
    pub ant_connected: bool,
    pub grid: Option<String>,
    pub asl: Option<i32>,
    pub users: i32,
    pub users_max: i32,
    pub uptime: Option<i64>,
    pub software_version: Option<String>,
}

/// Snapshot of the spot being tuned into. Park / summit coordinates are
/// resolved by the host from its local caches (POTA parks, SOTA summits) and
/// passed pre-resolved; the strategies use them in the same precedence order
/// as the Swift port.
#[derive(uniffi::Record, Clone)]
pub struct FfiTuneInSpot {
    pub callsign: String,
    pub frequency_mhz: f64,
    pub mode: String,
    pub band: String,
    pub park_ref: Option<String>,
    pub summit_code: Option<String>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub grid: Option<String>,
    pub park_latitude: Option<f64>,
    pub park_longitude: Option<f64>,
    pub summit_latitude: Option<f64>,
    pub summit_longitude: Option<f64>,
}

/// How the user wants to pick a receiver for Tune In. Variant names mirror
/// the Swift `TuneInStrategy` cases, hence the shared prefix.
#[derive(uniffi::Enum, Clone, Copy, PartialEq, Eq)]
#[allow(clippy::enum_variant_names)]
pub enum FfiTuneInStrategy {
    /// Near the strongest RBN spotter (best signal quality).
    NearStrongRbn,
    /// Near the activator's location (hear what they hear).
    NearActivator,
    /// Near the user's own QTH.
    NearMyQth,
}

/// Alert that the tuned activator was re-spotted on a different frequency.
#[derive(uniffi::Record, Clone)]
pub struct FfiQsyAlert {
    pub callsign: String,
    pub new_frequency_mhz: f64,
    pub new_mode: String,
    pub new_band: String,
    pub current_frequency_mhz: f64,
    pub current_band: String,
}

/// Suggestion to switch to a better receiver.
#[derive(uniffi::Record, Clone)]
pub struct FfiReceiverSuggestion {
    pub current_name: String,
    pub suggested_name: String,
    pub suggested: FfiKiwiReceiver,
    pub reason: String,
}

/// KiwiSDR mode parameters for a Carrier Wave mode string — used by hosts to
/// build receiver web URLs and show passband info.
#[derive(uniffi::Record, Clone)]
pub struct FfiKiwiModeInfo {
    /// KiwiSDR protocol name (`cw`, `usb`, …).
    pub kiwi_name: String,
    pub display_name: String,
    pub low_cut: i32,
    pub high_cut: i32,
    pub carrier_offset_khz: f64,
    pub bandwidth_hz: i32,
    pub bandwidth_description: String,
}

/// Resolve the KiwiSDR mode parameters for a Carrier Wave mode string (SSB
/// picks LSB below 10 MHz).
#[uniffi::export]
pub fn kiwi_mode_info(mode: String, frequency_mhz: Option<f64>) -> FfiKiwiModeInfo {
    let kiwi = KiwiSdrMode::from_carrier_wave_mode(&mode, frequency_mhz);
    FfiKiwiModeInfo {
        kiwi_name: kiwi.kiwi_name().to_string(),
        display_name: kiwi.display_name().to_string(),
        low_cut: kiwi.low_cut(),
        high_cut: kiwi.high_cut(),
        carrier_offset_khz: kiwi.carrier_offset_khz(),
        bandwidth_hz: kiwi.bandwidth_hz(),
        bandwidth_description: kiwi.bandwidth_description(),
    }
}

// ---------------------------------------------------------------------------
// Callback listeners (host-implemented)
// ---------------------------------------------------------------------------

/// Host-side sink for a live audio connection. Frames arrive batched per
/// decoded websocket frame; the host feeds its ring buffer / recorder / CW
/// decoder from here.
#[uniffi::export(with_foreign)]
pub trait SdrAudioListener: Send + Sync {
    /// One decoded mono PCM frame.
    fn on_audio_frame(&self, samples: Vec<i16>, s_meter: u16);
    /// The stream ended (server disconnect, redirect, or socket error). No
    /// further frames follow; the host decides whether to reconnect.
    fn on_disconnected(&self, reason: String);
}

/// Host-side sink for streamed `/status` enrichment results.
#[uniffi::export(with_foreign)]
pub trait SdrStatusListener: Send + Sync {
    /// One receiver's status arrived.
    fn on_status(&self, status: FfiReceiverStatus);
    /// All requested receivers have been attempted.
    fn on_complete(&self);
}

/// Host-side sink for QSY alerts.
#[uniffi::export(with_foreign)]
pub trait SdrQsyListener: Send + Sync {
    fn on_qsy(&self, alert: FfiQsyAlert);
}

/// Host-side sink for receiver-quality suggestions.
#[uniffi::export(with_foreign)]
pub trait SdrSuggestionListener: Send + Sync {
    fn on_suggestion(&self, suggestion: FfiReceiverSuggestion);
}

// ---------------------------------------------------------------------------
// Connection + monitor handles
// ---------------------------------------------------------------------------

/// Handle to a live KiwiSDR audio connection. Retune / mode changes go
/// through here; `disconnect` (or dropping the handle) closes the socket and
/// the listener receives a final `on_disconnected`.
#[derive(uniffi::Object)]
pub struct SdrConnection {
    inner: cw_net::KiwiSdrConnection,
}

#[uniffi::export]
impl SdrConnection {
    /// Sample rate negotiated during the handshake.
    pub fn sample_rate(&self) -> f64 {
        self.inner.sample_rate
    }

    /// Host actually connected to (differs from the requested host after a
    /// server redirect).
    pub fn effective_host(&self) -> String {
        self.inner.effective_host.clone()
    }

    pub fn effective_port(&self) -> u16 {
        self.inner.effective_port
    }

    /// Retune to a new frequency in kHz, keeping the current mode.
    pub fn retune(&self, frequency_khz: f64) -> Result<(), CwError> {
        self.inner.retune(frequency_khz).map_err(kiwi_error)
    }

    /// Change mode (Carrier Wave mode string; SSB resolves by frequency).
    pub fn change_mode(&self, mode: String, frequency_mhz: Option<f64>) -> Result<(), CwError> {
        let kiwi = KiwiSdrMode::from_carrier_wave_mode(&mode, frequency_mhz);
        self.inner.change_mode(kiwi).map_err(kiwi_error)
    }

    /// Close the connection.
    pub fn disconnect(&self) {
        self.inner.disconnect();
    }
}

/// Handle to a running QSY or receiver-quality monitor. `stop` cancels it.
#[derive(uniffi::Object)]
pub struct SdrMonitorHandle {
    task: std::sync::Mutex<Option<tokio::task::JoinHandle<()>>>,
}

#[uniffi::export]
impl SdrMonitorHandle {
    pub fn stop(&self) {
        if let Some(task) = self.task.lock().expect("monitor mutex poisoned").take() {
            task.abort();
        }
    }
}

impl Drop for SdrMonitorHandle {
    fn drop(&mut self) {
        if let Some(task) = self.task.lock().expect("monitor mutex poisoned").take() {
            task.abort();
        }
    }
}

// ---------------------------------------------------------------------------
// SdrApi
// ---------------------------------------------------------------------------

/// Async SDR API. `activities_base_url` is the carrier_wave activities server
/// (for the RBN proxy); `directory_cache_path` optionally persists the
/// KiwiSDR public directory between launches (JSON file).
#[derive(uniffi::Object)]
pub struct SdrApi {
    directory: Arc<KiwiSdrDirectoryClient>,
    status: KiwiSdrStatusClient,
    rbn: RbnClient,
    hamdb: HamdbClient,
}

#[uniffi::export]
impl SdrApi {
    #[uniffi::constructor]
    pub fn new(
        activities_base_url: String,
        directory_cache_path: Option<String>,
    ) -> Result<Self, CwError> {
        let http = HttpClient::new()?;
        Ok(SdrApi {
            directory: Arc::new(KiwiSdrDirectoryClient::new(
                http.clone(),
                directory_cache_path.map(std::path::PathBuf::from),
            )),
            status: KiwiSdrStatusClient::new()?,
            rbn: RbnClient::new(http.clone(), activities_base_url),
            hamdb: HamdbClient::new(http),
        })
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl SdrApi {
    /// Force-refresh the public directory from the network.
    pub async fn refresh_directory(&self) {
        self.directory.refresh().await;
    }

    /// Find nearby receivers sorted by distance. Reference precedence:
    /// explicit lat/lon, else Maidenhead grid, else unfiltered.
    pub async fn find_nearby_receivers(
        &self,
        grid: Option<String>,
        latitude: Option<f64>,
        longitude: Option<f64>,
        max_distance_km: f64,
        limit: u32,
    ) -> Vec<FfiKiwiReceiver> {
        self.directory
            .find_nearby(grid.as_deref(), latitude, longitude, max_distance_km, limit as usize)
            .await
            .into_iter()
            .map(receiver_to_ffi)
            .collect()
    }

    /// Fetch `/status` for a single receiver (5 s timeout, best-effort).
    pub async fn fetch_receiver_status(
        &self,
        host: String,
        port: u16,
    ) -> Option<FfiReceiverStatus> {
        self.status.fetch_status(&host, port).await.map(status_to_ffi)
    }

    /// Fetch `/status` for many receivers with bounded concurrency (5 in
    /// flight); results stream to `listener` as they arrive.
    pub async fn enrich_statuses(
        &self,
        receivers: Vec<FfiKiwiReceiver>,
        listener: Arc<dyn SdrStatusListener>,
    ) {
        let targets: Vec<(String, u16)> =
            receivers.iter().map(|rx| (rx.host.clone(), rx.port)).collect();
        let mut results = self.status.fetch_statuses(targets);
        tokio::spawn(async move {
            while let Some(status) = results.recv().await {
                listener.on_status(status_to_ffi(status));
            }
            listener.on_complete();
        });
    }

    /// Ranked candidate receivers for a Tune-In strategy — available
    /// receivers in priority order (best first). Port of
    /// `TuneInManager.selectCandidateReceivers`. `my_grid` is the operator's
    /// grid (used by the near-my-QTH strategy).
    pub async fn select_candidate_receivers(
        &self,
        spot: FfiTuneInSpot,
        strategy: FfiTuneInStrategy,
        my_grid: Option<String>,
    ) -> Vec<FfiKiwiReceiver> {
        let strategy = match strategy {
            FfiTuneInStrategy::NearStrongRbn => TuneInStrategy::NearStrongRbn,
            FfiTuneInStrategy::NearActivator => TuneInStrategy::NearActivator,
            FfiTuneInStrategy::NearMyQth => TuneInStrategy::NearMyQth,
        };
        let candidates = match strategy {
            TuneInStrategy::NearStrongRbn => self.candidates_near_rbn(&spot).await,
            TuneInStrategy::NearActivator => self.candidates_near_activator(&spot).await,
            TuneInStrategy::NearMyQth => {
                self.candidates_near_my_qth(&spot, my_grid.as_deref()).await
            }
        };
        candidates.into_iter().map(receiver_to_ffi).collect()
    }

    /// Connect to a receiver and stream decoded PCM to `listener`. Follows
    /// server redirects (up to 3). The Carrier Wave `mode` string is resolved
    /// to a KiwiSDR mode using the spot frequency.
    pub async fn connect(
        &self,
        host: String,
        port: u16,
        frequency_khz: f64,
        mode: String,
        password: Option<String>,
        listener: Arc<dyn SdrAudioListener>,
    ) -> Result<Arc<SdrConnection>, CwError> {
        let kiwi_mode =
            KiwiSdrMode::from_carrier_wave_mode(&mode, Some(frequency_khz / 1_000.0));
        let (connection, mut events) = cw_net::connect_following_redirects(
            &host,
            port,
            frequency_khz,
            kiwi_mode,
            password.as_deref(),
        )
        .await
        .map_err(kiwi_error)?;

        tokio::spawn(async move {
            while let Some(event) = events.recv().await {
                match event {
                    KiwiSdrEvent::AudioFrame { samples, s_meter } => {
                        listener.on_audio_frame(samples, s_meter);
                    }
                    KiwiSdrEvent::Disconnected { reason } => {
                        listener.on_disconnected(reason);
                        break;
                    }
                }
            }
        });

        Ok(Arc::new(SdrConnection { inner: connection }))
    }

    /// Start monitoring RBN for a QSY of the tuned activator. Polls every
    /// 45 s; fires `listener.on_qsy` at most once, then stops (one alert per
    /// session, like the Swift port). Port of `startQSYMonitor`.
    pub async fn start_qsy_monitor(
        &self,
        callsign: String,
        current_frequency_mhz: f64,
        current_mode: String,
        current_band: String,
        listener: Arc<dyn SdrQsyListener>,
    ) -> Arc<SdrMonitorHandle> {
        let rbn = self.rbn.clone();
        let task = tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_secs(QSY_POLL_SECONDS)).await;

                let Ok(spots) = rbn.fetch_spots_for_callsign(&callsign, 1, 20).await else {
                    // Network error — silently retry next cycle.
                    continue;
                };
                let observations: Vec<QsyObservation> = spots
                    .iter()
                    .filter_map(|spot| {
                        Some(QsyObservation {
                            epoch_seconds: spot.timestamp_epoch_seconds()?,
                            frequency_khz: spot.frequency,
                        })
                    })
                    .collect();

                if let Some(new_mhz) =
                    detect_qsy(&observations, current_frequency_mhz, now_epoch_f64())
                {
                    let new_band = BandUtilities::derive_band(Some(new_mhz * 1_000.0))
                        .unwrap_or("")
                        .to_string();
                    listener.on_qsy(FfiQsyAlert {
                        callsign: callsign.clone(),
                        new_frequency_mhz: new_mhz,
                        new_mode: current_mode.clone(),
                        new_band,
                        current_frequency_mhz,
                        current_band: current_band.clone(),
                    });
                    break; // One alert per session, don't spam.
                }
            }
        });
        Arc::new(SdrMonitorHandle { task: std::sync::Mutex::new(Some(task)) })
    }

    /// Start monitoring the current receiver's quality. Every 120 s: if its
    /// SNR is poor (< 10 dB), scan the 5 nearest alternatives and suggest the
    /// first one that beats it by more than 5 dB, then stop. Port of
    /// `startReceiverMonitor`.
    pub async fn start_receiver_monitor(
        &self,
        current: FfiKiwiReceiver,
        spot: FfiTuneInSpot,
        listener: Arc<dyn SdrSuggestionListener>,
    ) -> Arc<SdrMonitorHandle> {
        let status = self.status.clone();
        let directory = self.directory.clone();
        let current_domain = ffi_to_receiver(&current);
        let task = tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_secs(RECEIVER_MONITOR_POLL_SECONDS)).await;

                let current_status =
                    status.fetch_status(&current_domain.host, current_domain.port).await;
                let Some(snr) = current_status.as_ref().and_then(ReceiverStatus::effective_snr)
                else {
                    continue;
                };
                if !cw_domain::kiwisdr::selection::snr_is_poor(snr) {
                    continue;
                }

                let alternatives = directory
                    .find_nearby(
                        spot.grid.as_deref(),
                        spot.latitude,
                        spot.longitude,
                        MAX_RECEIVER_DISTANCE_KM,
                        5,
                    )
                    .await;
                for alt in &alternatives {
                    if alt.id == current_domain.id || !alt.is_available() {
                        continue;
                    }
                    let alt_snr = status
                        .fetch_status(&alt.host, alt.port)
                        .await
                        .as_ref()
                        .and_then(ReceiverStatus::effective_snr)
                        .unwrap_or(0);
                    if let Some(suggestion) =
                        suggest_better_receiver(&current_domain, snr, alt, alt_snr)
                    {
                        listener.on_suggestion(FfiReceiverSuggestion {
                            current_name: suggestion.current_name,
                            suggested_name: suggestion.suggested.name.clone(),
                            suggested: receiver_to_ffi(suggestion.suggested),
                            reason: suggestion.reason,
                        });
                        return;
                    }
                }
            }
        });
        Arc::new(SdrMonitorHandle { task: std::sync::Mutex::new(Some(task)) })
    }
}

// ---------------------------------------------------------------------------
// Candidate strategies (port of TuneInManager+ReceiverSelection)
// ---------------------------------------------------------------------------

impl SdrApi {
    /// All available receivers near a coordinate, sorted by distance.
    async fn find_all_nearby_available(&self, latitude: f64, longitude: f64) -> Vec<KiwiSdrReceiver> {
        let receivers = self
            .directory
            .find_nearby(None, Some(latitude), Some(longitude), MAX_RECEIVER_DISTANCE_KM, 20)
            .await;
        filter_available(receivers)
    }

    /// Fallback candidates using the spot's own location data.
    async fn fallback_candidates(&self, spot: &FfiTuneInSpot) -> Vec<KiwiSdrReceiver> {
        let receivers = self
            .directory
            .find_nearby(
                spot.grid.as_deref(),
                spot.latitude,
                spot.longitude,
                MAX_RECEIVER_DISTANCE_KM,
                20,
            )
            .await;
        filter_available(receivers)
    }

    /// Candidates near the strongest RBN spotters, with fallback appended.
    async fn candidates_near_rbn(&self, spot: &FfiTuneInSpot) -> Vec<KiwiSdrReceiver> {
        let mut acc = CandidateAccumulator::new();

        if let Ok(mut spots) = self.rbn.fetch_spots_for_callsign(&spot.callsign, 1, 20).await {
            spots.sort_by_key(|spot| std::cmp::Reverse(spot.snr));
            for rbn_spot in &spots {
                let Some(coord) = rbn_spot
                    .spotter_grid
                    .as_deref()
                    .and_then(cw_domain::maidenhead::coordinate_from_grid)
                else {
                    continue;
                };
                acc.extend(self.find_all_nearby_available(coord.latitude, coord.longitude).await);
            }
        }

        acc.extend(self.fallback_candidates(spot).await);
        acc.into_candidates()
    }

    /// Candidates near the activator: park → summit → HamDB grid → RBN
    /// fallback. Park/summit coordinates come pre-resolved from the host.
    async fn candidates_near_activator(&self, spot: &FfiTuneInSpot) -> Vec<KiwiSdrReceiver> {
        let mut acc = CandidateAccumulator::new();

        if let (Some(lat), Some(lon)) = (spot.park_latitude, spot.park_longitude) {
            acc.extend(self.find_all_nearby_available(lat, lon).await);
        }

        if let (Some(lat), Some(lon)) = (spot.summit_latitude, spot.summit_longitude) {
            acc.extend(self.find_all_nearby_available(lat, lon).await);
        }

        if let Ok(Some(license)) = self.hamdb.lookup(&spot.callsign).await {
            if let Some(coord) =
                license.grid.as_deref().and_then(cw_domain::maidenhead::coordinate_from_grid)
            {
                acc.extend(self.find_all_nearby_available(coord.latitude, coord.longitude).await);
            }
        }

        acc.extend(self.candidates_near_rbn(spot).await);
        acc.into_candidates()
    }

    /// Candidates near the user's QTH, with RBN fallback appended.
    async fn candidates_near_my_qth(
        &self,
        spot: &FfiTuneInSpot,
        my_grid: Option<&str>,
    ) -> Vec<KiwiSdrReceiver> {
        let mut acc = CandidateAccumulator::new();

        if let Some(coord) = my_grid.and_then(cw_domain::maidenhead::coordinate_from_grid) {
            acc.extend(self.find_all_nearby_available(coord.latitude, coord.longitude).await);
        }

        acc.extend(self.candidates_near_rbn(spot).await);
        acc.into_candidates()
    }
}

// ---------------------------------------------------------------------------
// Mapping helpers
// ---------------------------------------------------------------------------

fn receiver_to_ffi(rx: KiwiSdrReceiver) -> FfiKiwiReceiver {
    let is_available = rx.is_available();
    FfiKiwiReceiver {
        id: rx.id,
        name: rx.name,
        host: rx.host,
        port: rx.port,
        latitude: rx.latitude,
        longitude: rx.longitude,
        bands: rx.bands,
        users: rx.users,
        max_users: rx.max_users,
        location: rx.location,
        antenna: rx.antenna,
        distance_km: rx.distance_km,
        snr_all: rx.snr_all,
        snr_hf: rx.snr_hf,
        ant_connected: rx.ant_connected,
        grid: rx.grid,
        asl: rx.asl,
        enriched_antenna: rx.enriched_antenna,
        is_available,
    }
}

fn ffi_to_receiver(rx: &FfiKiwiReceiver) -> KiwiSdrReceiver {
    KiwiSdrReceiver {
        id: rx.id.clone(),
        name: rx.name.clone(),
        host: rx.host.clone(),
        port: rx.port,
        latitude: rx.latitude,
        longitude: rx.longitude,
        bands: rx.bands.clone(),
        users: rx.users,
        max_users: rx.max_users,
        location: rx.location.clone(),
        antenna: rx.antenna.clone(),
        distance_km: rx.distance_km,
        snr_all: rx.snr_all,
        snr_hf: rx.snr_hf,
        ant_connected: rx.ant_connected,
        grid: rx.grid.clone(),
        asl: rx.asl,
        enriched_antenna: rx.enriched_antenna.clone(),
    }
}

fn status_to_ffi(status: ReceiverStatus) -> FfiReceiverStatus {
    FfiReceiverStatus {
        host_port: status.host_port,
        antenna: status.antenna,
        bands_hz: status.bands_hz,
        snr_all: status.snr_all,
        snr_hf: status.snr_hf,
        ant_connected: status.ant_connected,
        grid: status.grid,
        asl: status.asl,
        users: status.users,
        users_max: status.users_max,
        uptime: status.uptime,
        software_version: status.software_version,
    }
}

fn kiwi_error(err: KiwiSdrError) -> CwError {
    match err {
        KiwiSdrError::AuthenticationFailed => CwError::Auth { reason: err.to_string() },
        other => CwError::Network { reason: other.to_string() },
    }
}

fn now_epoch_f64() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mode_info_maps_ssb_by_frequency() {
        let low = kiwi_mode_info("SSB".into(), Some(7.2));
        assert_eq!(low.kiwi_name, "lsb");
        let high = kiwi_mode_info("SSB".into(), Some(14.2));
        assert_eq!(high.kiwi_name, "usb");
        let cw = kiwi_mode_info("CW".into(), None);
        assert_eq!(cw.low_cut, 300);
        assert_eq!(cw.high_cut, 800);
        assert!((cw.carrier_offset_khz - 0.55).abs() < 1e-12);
    }

    #[test]
    fn receiver_round_trip_preserves_fields() {
        let ffi = FfiKiwiReceiver {
            id: "h:8073".into(),
            name: "Kiwi".into(),
            host: "h".into(),
            port: 8_073,
            latitude: 1.0,
            longitude: 2.0,
            bands: "0-30 MHz".into(),
            users: 3,
            max_users: 4,
            location: "Somewhere".into(),
            antenna: "Dipole".into(),
            distance_km: Some(12.5),
            snr_all: Some(20),
            snr_hf: Some(25),
            ant_connected: Some(true),
            grid: Some("CN85".into()),
            asl: Some(100),
            enriched_antenna: None,
            is_available: true,
        };
        let domain = ffi_to_receiver(&ffi);
        assert!(domain.is_available());
        let back = receiver_to_ffi(domain);
        assert_eq!(back.id, ffi.id);
        assert_eq!(back.users, 3);
        assert!(back.is_available);
        assert_eq!(back.snr_hf, Some(25));
    }
}
