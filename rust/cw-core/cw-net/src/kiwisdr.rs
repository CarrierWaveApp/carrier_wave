//! KiwiSDR transport: public-directory fetch + cache, per-receiver `/status`
//! enrichment, and the websocket audio client. Ports of `WebSDRDirectory`
//! (fetch/cache half), `KiwiSDRStatusFetcher` (HTTP half), `KiwiSDRClient`
//! (transport half), and `WebSDRSession.connectFollowingRedirects`. All
//! parsing is delegated to `cw_domain::kiwisdr`.

use std::path::PathBuf;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use cw_domain::kiwisdr::{
    check_for_server_error, classify_stream_text, find_nearby, is_snd_frame, parse_msg_value,
    parse_redirect_target, parse_snd_frame, parse_status_response, tune_command, AdpcmState,
    KiwiSdrMode, KiwiSdrReceiver, ReceiverStatus, ServerError, StreamTextEvent,
};
use futures_util::{SinkExt, StreamExt};
use thiserror::Error;
use tokio::sync::{mpsc, Mutex};
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message;

use crate::http::{HttpClient, HttpError};

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

#[derive(Debug, Error)]
pub enum KiwiSdrError {
    #[error("Invalid KiwiSDR URL")]
    InvalidUrl,
    #[error("Not connected to KiwiSDR")]
    NotConnected,
    #[error("KiwiSDR handshake failed: {0}")]
    HandshakeFailed(String),
    #[error("KiwiSDR authentication failed (bad password)")]
    AuthenticationFailed,
    #[error("KiwiSDR is full ({0} channels in use)")]
    TooBusy(i32),
    #[error("KiwiSDR server is down")]
    ServerDown,
    #[error("KiwiSDR redirected to {0}")]
    ServerRedirect(String),
    #[error("WebSocket error: {0}")]
    WebSocket(String),
}

impl From<ServerError> for KiwiSdrError {
    fn from(err: ServerError) -> Self {
        match err {
            ServerError::AuthenticationFailed => KiwiSdrError::AuthenticationFailed,
            ServerError::TooBusy(slots) => KiwiSdrError::TooBusy(slots),
            ServerError::ServerDown => KiwiSdrError::ServerDown,
            ServerError::Redirect(target) => KiwiSdrError::ServerRedirect(target),
        }
    }
}

// ---------------------------------------------------------------------------
// Directory client
// ---------------------------------------------------------------------------

/// Primary directory source: the Skywavelinux JS mirror (JSON, refreshed every
/// few hours, includes SNR/grid enrichment).
const DIRECTORY_JS_URL: &str = "https://rx.skywavelinux.com/kiwisdr_com.js";
/// Legacy fallback: the original kiwisdr.com HTML directory.
const DIRECTORY_HTML_URL: &str = "http://kiwisdr.com/.public/";
/// Refresh the cached directory daily, like the Swift port.
const DIRECTORY_REFRESH: Duration = Duration::from_secs(24 * 60 * 60);

/// On-disk cache format. Mirrors `WebSDRDirectory.CachedDirectory`: only the
/// static receiver fields are persisted (occupancy and SNR go stale), and
/// `users` is reset to 0 on load.
#[derive(serde::Serialize, serde::Deserialize)]
struct CachedDirectory {
    receivers: Vec<CachedReceiver>,
    /// Unix seconds.
    fetched_at: u64,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct CachedReceiver {
    name: String,
    host: String,
    port: u16,
    latitude: f64,
    longitude: f64,
    bands: String,
    max_users: i32,
    location: String,
    antenna: String,
    #[serde(default)]
    grid: Option<String>,
}

impl CachedReceiver {
    fn into_receiver(self) -> KiwiSdrReceiver {
        KiwiSdrReceiver {
            id: format!("{}:{}", self.host, self.port),
            name: self.name,
            host: self.host,
            port: self.port,
            latitude: self.latitude,
            longitude: self.longitude,
            bands: self.bands,
            users: 0,
            max_users: self.max_users,
            location: self.location,
            antenna: self.antenna,
            distance_km: None,
            snr_all: None,
            snr_hf: None,
            ant_connected: None,
            grid: self.grid,
            asl: None,
            enriched_antenna: None,
        }
    }

    fn from_receiver(rx: &KiwiSdrReceiver) -> Self {
        CachedReceiver {
            name: rx.name.clone(),
            host: rx.host.clone(),
            port: rx.port,
            latitude: rx.latitude,
            longitude: rx.longitude,
            bands: rx.bands.clone(),
            max_users: rx.max_users,
            location: rx.location.clone(),
            antenna: rx.antenna.clone(),
            grid: rx.grid.clone(),
        }
    }
}

struct DirectoryState {
    receivers: Vec<KiwiSdrReceiver>,
    /// Unix seconds of the last successful fetch (or cache stamp).
    fetched_at: Option<u64>,
}

/// Fetches and caches the KiwiSDR public directory. Cache is held in memory
/// and optionally persisted to `cache_path` (JSON) so a fresh process can
/// search before the first network fetch, matching the Swift behavior.
pub struct KiwiSdrDirectoryClient {
    http: HttpClient,
    cache_path: Option<PathBuf>,
    state: Mutex<DirectoryState>,
}

impl KiwiSdrDirectoryClient {
    pub fn new(http: HttpClient, cache_path: Option<PathBuf>) -> Self {
        KiwiSdrDirectoryClient {
            http,
            cache_path,
            state: Mutex::new(DirectoryState { receivers: Vec::new(), fetched_at: None }),
        }
    }

    /// Number of receivers currently cached.
    pub async fn receiver_count(&self) -> usize {
        self.state.lock().await.receivers.len()
    }

    /// Find nearby receivers sorted by distance. Reference point precedence:
    /// explicit lat/lon, else the Maidenhead grid, else unfiltered.
    pub async fn find_nearby(
        &self,
        grid: Option<&str>,
        latitude: Option<f64>,
        longitude: Option<f64>,
        max_distance_km: f64,
        limit: usize,
    ) -> Vec<KiwiSdrReceiver> {
        let reference = match (latitude, longitude) {
            (Some(lat), Some(lon)) => Some((lat, lon)),
            _ => grid
                .and_then(cw_domain::maidenhead::coordinate_from_grid)
                .map(|coord| (coord.latitude, coord.longitude)),
        };

        self.ensure_loaded().await;

        let state = self.state.lock().await;
        find_nearby(&state.receivers, reference, max_distance_km, limit)
    }

    /// Force a network refresh.
    pub async fn refresh(&self) {
        self.fetch_directory().await;
    }

    /// Load from disk cache or network if the in-memory list is empty; kick a
    /// refresh when the cache is stale (> 24 h).
    async fn ensure_loaded(&self) {
        let (is_empty, stale) = {
            let state = self.state.lock().await;
            let stale = state
                .fetched_at
                .map_or(true, |at| now_unix().saturating_sub(at) > DIRECTORY_REFRESH.as_secs());
            (state.receivers.is_empty(), stale)
        };

        if is_empty {
            if let Some(cached) = self.load_disk_cache() {
                let cache_stale =
                    now_unix().saturating_sub(cached.fetched_at) > DIRECTORY_REFRESH.as_secs();
                {
                    let mut state = self.state.lock().await;
                    state.receivers =
                        cached.receivers.into_iter().map(CachedReceiver::into_receiver).collect();
                    state.fetched_at = Some(cached.fetched_at);
                }
                if cache_stale {
                    self.fetch_directory().await;
                }
                return;
            }
            self.fetch_directory().await;
        } else if stale {
            self.fetch_directory().await;
        }
    }

    async fn fetch_directory(&self) {
        let receivers = match self.fetch_from_network().await {
            Ok(list) if !list.is_empty() => list,
            _ => return, // Keep whatever we had; fetch failures are non-fatal.
        };

        let fetched_at = now_unix();
        {
            let mut state = self.state.lock().await;
            state.receivers = receivers.clone();
            state.fetched_at = Some(fetched_at);
        }
        self.save_disk_cache(&receivers, fetched_at);
    }

    /// Skywavelinux JSON first, kiwisdr.com HTML as fallback.
    async fn fetch_from_network(&self) -> Result<Vec<KiwiSdrReceiver>, HttpError> {
        if let Ok(js) = self.http.get_text(DIRECTORY_JS_URL, "*/*").await {
            let receivers = cw_domain::kiwisdr::directory::parse_directory_js(&js);
            if !receivers.is_empty() {
                return Ok(receivers);
            }
        }
        let html = self.http.get_text(DIRECTORY_HTML_URL, "*/*").await?;
        Ok(cw_domain::kiwisdr::directory::parse_directory_html(&html))
    }

    fn load_disk_cache(&self) -> Option<CachedDirectory> {
        let path = self.cache_path.as_ref()?;
        let data = std::fs::read(path).ok()?;
        serde_json::from_slice(&data).ok()
    }

    fn save_disk_cache(&self, receivers: &[KiwiSdrReceiver], fetched_at: u64) {
        let Some(path) = self.cache_path.as_ref() else {
            return;
        };
        let cached = CachedDirectory {
            receivers: receivers.iter().map(CachedReceiver::from_receiver).collect(),
            fetched_at,
        };
        if let Ok(json) = serde_json::to_vec(&cached) {
            let _ = std::fs::write(path, json);
        }
    }
}

fn now_unix() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

// ---------------------------------------------------------------------------
// Status client
// ---------------------------------------------------------------------------

/// Max concurrent `/status` fetches, matching `KiwiSDRStatusFetcher`.
const STATUS_MAX_CONCURRENT: usize = 5;

/// Fetches `/status` from individual receivers (5 s timeout per request).
#[derive(Clone)]
pub struct KiwiSdrStatusClient {
    client: reqwest::Client,
}

impl KiwiSdrStatusClient {
    pub fn new() -> Result<Self, HttpError> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .user_agent(crate::http::USER_AGENT_VALUE)
            .build()
            .map_err(HttpError::Network)?;
        Ok(KiwiSdrStatusClient { client })
    }

    /// Fetch a single receiver's `/status`. Returns `None` on any failure —
    /// enrichment is best-effort, like the Swift port.
    pub async fn fetch_status(&self, host: &str, port: u16) -> Option<ReceiverStatus> {
        let url = format!("http://{host}:{port}/status");
        let response = self.client.get(&url).send().await.ok()?;
        let text = response.text().await.ok()?;
        Some(parse_status_response(&text, host, port))
    }

    /// Fetch `/status` for many receivers with bounded concurrency; results
    /// stream back on the returned channel as they arrive.
    pub fn fetch_statuses(
        &self,
        receivers: Vec<(String, u16)>,
    ) -> mpsc::Receiver<ReceiverStatus> {
        let (tx, rx) = mpsc::channel(receivers.len().max(1));
        let client = self.clone();
        tokio::spawn(async move {
            let semaphore = std::sync::Arc::new(tokio::sync::Semaphore::new(STATUS_MAX_CONCURRENT));
            let mut handles = Vec::with_capacity(receivers.len());
            for (host, port) in receivers {
                let permit_source = semaphore.clone();
                let client = client.clone();
                let tx = tx.clone();
                handles.push(tokio::spawn(async move {
                    let _permit = permit_source.acquire().await;
                    if let Some(status) = client.fetch_status(&host, port).await {
                        let _ = tx.send(status).await;
                    }
                }));
            }
            for handle in handles {
                let _ = handle.await;
            }
        });
        rx
    }
}

// ---------------------------------------------------------------------------
// Audio client
// ---------------------------------------------------------------------------

/// Events emitted by an active KiwiSDR audio connection.
#[derive(Debug, Clone, PartialEq)]
pub enum KiwiSdrEvent {
    /// A decoded mono PCM frame.
    AudioFrame { samples: Vec<i16>, s_meter: u16 },
    /// The stream ended (server disconnect, redirect, or socket error). No
    /// further events follow.
    Disconnected { reason: String },
}

enum Command {
    Send(String),
    Close,
}

/// Handle to an active KiwiSDR audio connection. Dropping the handle (or
/// calling [`KiwiSdrConnection::disconnect`]) tears the connection down.
pub struct KiwiSdrConnection {
    /// Sample rate negotiated during the handshake.
    pub sample_rate: f64,
    /// Host actually connected to (differs from the requested host after a
    /// redirect).
    pub effective_host: String,
    pub effective_port: u16,
    command_tx: mpsc::UnboundedSender<Command>,
    tuning: std::sync::Mutex<(f64, KiwiSdrMode)>,
}

impl KiwiSdrConnection {
    /// Retune to a new frequency, keeping the current mode.
    pub fn retune(&self, frequency_khz: f64) -> Result<(), KiwiSdrError> {
        let mode = {
            let mut tuning = self.tuning.lock().expect("tuning mutex poisoned");
            tuning.0 = frequency_khz;
            tuning.1
        };
        self.send(&tune_command(frequency_khz, mode))
    }

    /// Change mode, retuning at the current frequency.
    pub fn change_mode(&self, mode: KiwiSdrMode) -> Result<(), KiwiSdrError> {
        let frequency_khz = {
            let mut tuning = self.tuning.lock().expect("tuning mutex poisoned");
            tuning.1 = mode;
            tuning.0
        };
        self.send(&tune_command(frequency_khz, mode))
    }

    /// Close the connection. The event channel receives a final
    /// `Disconnected` when the socket actually closes.
    pub fn disconnect(&self) {
        let _ = self.command_tx.send(Command::Close);
    }

    fn send(&self, message: &str) -> Result<(), KiwiSdrError> {
        self.command_tx
            .send(Command::Send(message.to_string()))
            .map_err(|_| KiwiSdrError::NotConnected)
    }
}

impl Drop for KiwiSdrConnection {
    fn drop(&mut self) {
        let _ = self.command_tx.send(Command::Close);
    }
}

/// Build the SND stream websocket URL. Modern KiwiSDR firmware (the `/ws/`
/// scheme) is the default; legacy firmware uses the bare timestamp path.
/// Legacy-path connections against modern firmware complete the websocket
/// handshake but never attach a stream (total silence), so modern-first with
/// a legacy retry on *handshake failure* is the only reliable order.
pub fn snd_stream_url(host: &str, port: u16, timestamp: u64, legacy: bool) -> String {
    if legacy {
        format!("ws://{host}:{port}/{timestamp}/SND")
    } else {
        format!("ws://{host}:{port}/ws/kiwi/{timestamp}/SND")
    }
}

/// KiwiSDR web assets fetched before the audio socket opens. Modern firmware
/// classifies a client that opened only the websocket — without loading web
/// assets from the same IP — as a "non-Kiwi app" and kicks it with
/// `MSG too_busy` at exactly 10 s (rx_sound.cpp `EXT_API_DECISION_SECS`).
/// Fetching a handful of assets first (as a browser loading the UI does)
/// pushes the receiver's per-IP `web_served` counter past its threshold (3),
/// so the audio connection is treated as the Kiwi UI and allowed to stream.
const WARMUP_ASSETS: [&str; 4] = ["/", "/kiwisdr.min.js", "/config/config.js", "/status"];

/// Fetch a few of the receiver's web assets so the impending audio connection
/// is classified as the Kiwi UI rather than a non-Kiwi app. Best-effort: all
/// requests share a short deadline and failures are ignored.
async fn warm_up_served_counter(host: &str, port: u16) {
    let Ok(client) =
        reqwest::Client::builder().timeout(Duration::from_secs(4)).build()
    else {
        return;
    };
    let fetches = WARMUP_ASSETS.iter().map(|path| {
        let url = format!("http://{host}:{port}{path}");
        let client = client.clone();
        async move {
            let _ = client.get(&url).send().await;
        }
    });
    let _ = tokio::time::timeout(
        Duration::from_secs(4),
        futures_util::future::join_all(fetches),
    )
    .await;
}

/// Connect to a KiwiSDR and start streaming audio. Mirrors
/// `KiwiSDRClient.connect`: auth, sample-rate wait (30-message budget),
/// `AR OK` / ident / compression, tune, AGC, keepalive every 5 s.
/// Tries the modern `/ws/kiwi/{ts}/SND` path first, falling back to the
/// legacy `/{ts}/SND` path if the modern handshake is rejected (old
/// firmware 404s the `/ws/` prefix).
pub async fn connect(
    host: &str,
    port: u16,
    frequency_khz: f64,
    mode: KiwiSdrMode,
    password: Option<&str>,
) -> Result<(KiwiSdrConnection, mpsc::UnboundedReceiver<KiwiSdrEvent>), KiwiSdrError> {
    // Warm the receiver's per-IP web-served counter, or the stream is kicked
    // after ~10 s on API-limited receivers.
    warm_up_served_counter(host, port).await;

    let timestamp = now_unix();

    let mut ws = match connect_async(&snd_stream_url(host, port, timestamp, false)).await {
        Ok((ws, _)) => ws,
        Err(_) => {
            let (ws, _) = connect_async(&snd_stream_url(host, port, timestamp, true))
                .await
                .map_err(|err| KiwiSdrError::WebSocket(err.to_string()))?;
            ws
        }
    };

    // Auth ("#" means "no password", like the Swift port).
    let auth_password = password.unwrap_or("#");
    ws.send(Message::Text(format!("SET auth t=kiwi p={auth_password}")))
        .await
        .map_err(|err| KiwiSdrError::WebSocket(err.to_string()))?;

    // Wait for the server's sample_rate message. KiwiSDR sends MSG text as
    // binary frames, so both frame types are checked.
    let mut sample_rate: Option<f64> = None;
    for _ in 0..30 {
        let Some(message) = ws.next().await else {
            break;
        };
        let message = message.map_err(|err| KiwiSdrError::WebSocket(err.to_string()))?;
        let Some(text) = message_text(&message) else {
            continue;
        };

        check_for_server_error(&text)?;

        if let Some(rate) =
            parse_msg_value(&text, "sample_rate").and_then(|val| val.parse::<f64>().ok())
        {
            sample_rate = Some(rate);
            break;
        }
    }
    let sample_rate = sample_rate
        .ok_or_else(|| KiwiSdrError::HandshakeFailed("No sample_rate received".to_string()))?;

    // Acknowledge, identify, and configure.
    let in_rate = sample_rate as i64;
    for setup in [
        format!("SET AR OK in={in_rate} out={in_rate}"),
        "SET ident_user=CarrierWave".to_string(),
        "SET compression=1".to_string(),
        tune_command(frequency_khz, mode),
        "SET agc=1 hang=0 thresh=-100 slope=6 decay=1000 manGain=50".to_string(),
    ] {
        ws.send(Message::Text(setup))
            .await
            .map_err(|err| KiwiSdrError::WebSocket(err.to_string()))?;
    }

    let (command_tx, mut command_rx) = mpsc::unbounded_channel::<Command>();
    let (event_tx, event_rx) = mpsc::unbounded_channel::<KiwiSdrEvent>();

    let (mut sink, mut stream) = ws.split();

    // Writer: serializes outbound commands onto the socket.
    tokio::spawn(async move {
        while let Some(command) = command_rx.recv().await {
            match command {
                Command::Send(text) => {
                    if sink.send(Message::Text(text)).await.is_err() {
                        break;
                    }
                }
                Command::Close => {
                    let _ = sink.send(Message::Close(None)).await;
                    break;
                }
            }
        }
    });

    // Keepalive every 5 seconds (first one immediately), via the writer.
    let keepalive_tx = command_tx.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(5));
        loop {
            interval.tick().await;
            if keepalive_tx.send(Command::Send("SET keepalive".to_string())).is_err() {
                break;
            }
        }
    });

    // Reader: decodes SND frames and classifies MSG text.
    tokio::spawn(async move {
        let mut adpcm = AdpcmState::default();
        loop {
            let Some(message) = stream.next().await else {
                let _ = event_tx.send(KiwiSdrEvent::Disconnected {
                    reason: "Connection closed".to_string(),
                });
                break;
            };
            let message = match message {
                Ok(msg) => msg,
                Err(err) => {
                    let _ = event_tx
                        .send(KiwiSdrEvent::Disconnected { reason: err.to_string() });
                    break;
                }
            };

            match message {
                Message::Binary(data) if is_snd_frame(&data) => {
                    if let Some(frame) = parse_snd_frame(&data, &mut adpcm) {
                        if event_tx
                            .send(KiwiSdrEvent::AudioFrame {
                                samples: frame.samples,
                                s_meter: frame.s_meter,
                            })
                            .is_err()
                        {
                            break;
                        }
                    }
                }
                Message::Binary(data) => {
                    let Ok(text) = String::from_utf8(data) else {
                        continue;
                    };
                    if handle_stream_text(&text, &mut adpcm, &event_tx) {
                        break;
                    }
                }
                Message::Text(text)
                    if handle_stream_text(&text, &mut adpcm, &event_tx) =>
                {
                    break;
                }
                Message::Close(_) => {
                    let _ = event_tx.send(KiwiSdrEvent::Disconnected {
                        reason: "Connection closed".to_string(),
                    });
                    break;
                }
                _ => {}
            }
        }
    });

    let connection = KiwiSdrConnection {
        sample_rate,
        effective_host: host.to_string(),
        effective_port: port,
        command_tx,
        tuning: std::sync::Mutex::new((frequency_khz, mode)),
    };
    Ok((connection, event_rx))
}

/// Handle a mid-stream text message. Returns `true` when the reader loop
/// should stop.
fn handle_stream_text(
    text: &str,
    adpcm: &mut AdpcmState,
    event_tx: &mpsc::UnboundedSender<KiwiSdrEvent>,
) -> bool {
    match classify_stream_text(text) {
        StreamTextEvent::AdpcmReset { step_index, predictor } => {
            adpcm.reset(step_index, predictor);
            false
        }
        StreamTextEvent::Redirect => {
            let _ = event_tx
                .send(KiwiSdrEvent::Disconnected { reason: "Server redirect".to_string() });
            true
        }
        StreamTextEvent::Disconnected(message) => {
            let _ = event_tx.send(KiwiSdrEvent::Disconnected {
                reason: format!("Server disconnected: {message}"),
            });
            true
        }
        StreamTextEvent::None => false,
    }
}

/// Extract text content from a websocket message, decoding non-`SND` binary
/// frames as UTF-8 (KiwiSDR sends MSG text in binary frames).
fn message_text(message: &Message) -> Option<String> {
    match message {
        Message::Text(text) => Some(text.clone()),
        Message::Binary(data) if !is_snd_frame(data) => String::from_utf8(data.clone()).ok(),
        _ => None,
    }
}

/// Connect to a KiwiSDR, following server redirects up to 3 times. Port of
/// `WebSDRSession.connectFollowingRedirects`.
pub async fn connect_following_redirects(
    host: &str,
    port: u16,
    frequency_khz: f64,
    mode: KiwiSdrMode,
    password: Option<&str>,
) -> Result<(KiwiSdrConnection, mpsc::UnboundedReceiver<KiwiSdrEvent>), KiwiSdrError> {
    const MAX_REDIRECTS: usize = 3;
    let mut current_host = host.to_string();
    let mut current_port = port;

    for _ in 0..=MAX_REDIRECTS {
        match connect(&current_host, current_port, frequency_khz, mode, password).await {
            Ok(pair) => return Ok(pair),
            Err(KiwiSdrError::ServerRedirect(redirect)) => {
                let Some((next_host, next_port)) = parse_redirect_target(&redirect) else {
                    return Err(KiwiSdrError::ServerRedirect(redirect));
                };
                current_host = next_host;
                current_port = next_port;
            }
            Err(other) => return Err(other),
        }
    }

    Err(KiwiSdrError::HandshakeFailed("Too many redirects".to_string()))
}
