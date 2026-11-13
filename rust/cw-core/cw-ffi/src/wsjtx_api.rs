//! WSJT-X UDP listener + decoded-message surface over UniFFI (CAR-281).
//!
//! Wraps `cw_net::wsjtx` (the `QDataStream` decoder + async `WsjtxListener`,
//! CAR-277/CAR-283) and `cw_store::wsjtx_import` (message → store `Qso`,
//! CAR-280) so the iOS/macOS apps can start/stop a listener on a configurable
//! `host:port` and receive decoded events through a host-implemented delegate
//! — the same callback-bridge shape as `PanadapterListener` / `StoreObserver`.
//!
//! Surface:
//! - [`WsjtxApi`] object: async `start(host, port, delegate)` binds the socket
//!   and spawns the receive loop on the UniFFI tokio runtime, returning the
//!   bound port (useful when `port == 0`); sync `stop()` / `is_running()` /
//!   `local_port()`.
//! - [`WsjtxListenerDelegate`] foreign trait: `on_message(message, from)` per
//!   decoded datagram, `on_error(message)` for an undecodable datagram (the
//!   loop keeps listening) or a socket failure (the loop ends), `on_stopped()`
//!   once when the loop exits. Callbacks arrive on a Rust runtime thread —
//!   hop to the UI actor.
//! - `FfiWsjtx*` records mirroring the `cw_net::wsjtx` structs field-for-field
//!   with chrono types flattened: `QDateTime` → Unix **seconds** (`Option<i64>`,
//!   the store's `qso_date` unit), `QTime` → **milliseconds since UTC
//!   midnight** (`Option<u32>`). Later-version Status/Decode fields stay
//!   `Option` so a host can tell "sender predates this field" from a value.
//! - Store-mapping helpers [`wsjtx_map_qso_logged`] / [`wsjtx_map_logged_adif`]
//!   run `cw_store::wsjtx_import` and hand back [`FfiQso`] records the host
//!   inserts through the existing `FieldStore::upsert_qso`; [`wsjtx_dedup_key`]
//!   exposes the identity key for comparing against already-stored QSOs.
//!
//! Nothing here touches the store: wiring the delegate to `FieldStore` and to
//! the UI is CAR-282.

use std::net::SocketAddr;
use std::sync::{Arc, Mutex};

use chrono::{DateTime, NaiveTime, TimeZone, Timelike, Utc};
use cw_domain::wsjtx::{LoggedAdif, QsoLogged};
use cw_net::wsjtx::{
    self, Decode, Heartbeat, Status, WsjtxListener, WsjtxMessage, WSJTX_DEFAULT_PORT,
};
use cw_store::{
    qso_from_logged_adif, qso_from_qso_logged, wsjtx_dedup_key as store_dedup_key,
    WsjtxImportContext, WsjtxImportError,
};
use tokio::sync::oneshot;
use tokio::task::JoinHandle;

use crate::FfiQso;

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Everything the WSJT-X surface can fail with. Import variants mirror
/// `cw_store::WsjtxImportError` one-to-one so hosts can switch on them.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error, uniffi::Error)]
pub enum WsjtxError {
    /// `start` was called while a listener loop is already running on this
    /// object; `stop()` first.
    #[error("WSJT-X listener already running")]
    AlreadyRunning,
    /// The UDP socket could not be bound (port in use, bad host, sandbox).
    // Field is `reason`, not `message`: UniFFI's Kotlin codegen generates an
    // exception subclass and `message` collides with `Throwable.message`.
    #[error("could not bind WSJT-X listener on {address}: {reason}")]
    Bind { address: String, reason: String },
    /// A datagram handed to [`wsjtx_decode_datagram`] was not a WSJT-X message.
    #[error("WSJT-X decode error: {reason}")]
    Decode { reason: String },
    /// `QSOLogged` carried neither a time-on nor a time-off.
    #[error("WSJT-X QSO has no time on/off")]
    MissingTimestamp,
    /// `QSOLogged` carried a blank DX call.
    #[error("WSJT-X QSO has no DX callsign")]
    MissingCallsign,
    /// `LoggedADIF` parsed to zero records.
    #[error("LoggedADIF payload contained no parsable QSO record")]
    NoAdifRecords,
    /// An ADIF record had no parsable `QSO_DATE` (+ `TIME_ON`).
    #[error("ADIF record for {callsign} has no parsable QSO_DATE/TIME_ON")]
    MissingAdifTimestamp { callsign: String },
}

impl From<WsjtxImportError> for WsjtxError {
    fn from(err: WsjtxImportError) -> Self {
        match err {
            WsjtxImportError::MissingTimestamp => WsjtxError::MissingTimestamp,
            WsjtxImportError::MissingCallsign => WsjtxError::MissingCallsign,
            WsjtxImportError::NoAdifRecords => WsjtxError::NoAdifRecords,
            WsjtxImportError::MissingAdifTimestamp { callsign } => {
                WsjtxError::MissingAdifTimestamp { callsign }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Message records — `cw_net::wsjtx` structs, field-for-field
// ---------------------------------------------------------------------------

/// Type 0 Heartbeat (`cw_net::wsjtx::Heartbeat`).
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct FfiWsjtxHeartbeat {
    pub id: String,
    pub max_schema_number: u32,
    pub version: String,
    pub revision: String,
}

/// Type 1 Status (`cw_net::wsjtx::Status`). Fields from `rx_df` on were
/// appended by later WSJT-X releases and are `None` when the sender's
/// datagram ends before them.
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct FfiWsjtxStatus {
    pub id: String,
    pub dial_frequency_hz: u64,
    pub mode: String,
    pub dx_call: String,
    pub report: String,
    pub tx_mode: String,
    pub tx_enabled: bool,
    pub transmitting: bool,
    pub decoding: bool,
    pub rx_df: Option<u32>,
    pub tx_df: Option<u32>,
    pub de_call: Option<String>,
    pub de_grid: Option<String>,
    pub dx_grid: Option<String>,
    pub tx_watchdog: Option<bool>,
    pub sub_mode: Option<String>,
    pub fast_mode: Option<bool>,
    /// WSJT-X special-operation enum: 0 none, 1 NA VHF, 2 EU VHF, 3 field
    /// day, 4 RTTY RU, 5 WW digi, 6 Fox, 7 Hound, 8 ARRL digi.
    pub special_operation_mode: Option<u8>,
    pub frequency_tolerance: Option<u32>,
    pub tr_period: Option<u32>,
    pub configuration_name: Option<String>,
    pub tx_message: Option<String>,
}

/// Type 2 Decode (`cw_net::wsjtx::Decode`).
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct FfiWsjtxDecode {
    pub id: String,
    /// `true` for a fresh decode, `false` when WSJT-X replays its
    /// band-activity window.
    pub new: bool,
    /// UTC time of day of the decoded period as milliseconds since midnight;
    /// `None` if WSJT-X sent a null `QTime`.
    pub time_ms: Option<u32>,
    pub snr: i32,
    /// Time offset from the period start, in seconds.
    pub delta_time: f64,
    /// Audio frequency offset from the dial frequency, in Hz.
    pub delta_frequency: u32,
    /// WSJT-X's one-character mode tag (e.g. `"~"` FT8, `"+"` FT4).
    pub mode: String,
    pub message: String,
    pub low_confidence: Option<bool>,
    pub off_air: Option<bool>,
}

/// Type 5 QSOLogged (`cw_domain::wsjtx::QsoLogged`). Times are Unix seconds
/// UTC (`None` for a null `QDateTime`).
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct FfiWsjtxQsoLogged {
    pub id: String,
    pub date_time_off: Option<i64>,
    pub dx_call: String,
    pub dx_grid: String,
    pub tx_frequency_hz: u64,
    pub mode: String,
    pub report_sent: String,
    pub report_received: String,
    pub tx_power: String,
    pub comments: String,
    pub name: String,
    pub date_time_on: Option<i64>,
    pub operator_call: String,
    pub my_call: String,
    pub my_grid: String,
    pub exchange_sent: String,
    pub exchange_received: String,
    pub adif_propagation_mode: String,
}

/// Type 12 LoggedADIF (`cw_domain::wsjtx::LoggedAdif`).
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct FfiWsjtxLoggedAdif {
    pub id: String,
    /// The raw ADIF text WSJT-X logged (header + one `<eor>` record).
    pub adif: String,
}

/// One decoded WSJT-X datagram (`cw_net::wsjtx::WsjtxMessage`). Message types
/// the decoder does not model surface as `Other` with their numeric type.
#[derive(uniffi::Enum, Clone, Debug, PartialEq)]
pub enum FfiWsjtxMessage {
    Heartbeat { heartbeat: FfiWsjtxHeartbeat },
    Status { status: FfiWsjtxStatus },
    Decode { decode: FfiWsjtxDecode },
    QsoLogged { qso: FfiWsjtxQsoLogged },
    LoggedAdif { adif: FfiWsjtxLoggedAdif },
    /// Type 6 — the client is shutting down.
    Close { id: String },
    /// Any other message type, payload skipped.
    Other { kind: u32, id: String },
}

/// What the store needs that a WSJT-X message does not carry
/// (`cw_store::WsjtxImportContext`).
#[derive(uniffi::Record, Clone, Debug, Default, PartialEq, Eq)]
pub struct FfiWsjtxImportContext {
    /// Operator callsign used when WSJT-X's `my_call` / `STATION_CALLSIGN`
    /// are blank.
    pub station_callsign: Option<String>,
    /// Unix seconds stamped into `imported_at`.
    pub imported_at: i64,
    /// Session to attach the QSO to when WSJT-X runs alongside an activation.
    pub logging_session_id: Option<String>,
}

// ---------- chrono flattening ----------

fn time_to_ms(time: NaiveTime) -> u32 {
    time.num_seconds_from_midnight() * 1_000 + time.nanosecond() / 1_000_000
}

fn ms_to_time(ms: u32) -> Option<NaiveTime> {
    NaiveTime::from_num_seconds_from_midnight_opt(ms / 1_000, (ms % 1_000) * 1_000_000)
}

fn secs_to_datetime(secs: i64) -> Option<DateTime<Utc>> {
    Utc.timestamp_opt(secs, 0).single()
}

// ---------- conversions ----------

impl From<Heartbeat> for FfiWsjtxHeartbeat {
    fn from(h: Heartbeat) -> Self {
        FfiWsjtxHeartbeat {
            id: h.id,
            max_schema_number: h.max_schema_number,
            version: h.version,
            revision: h.revision,
        }
    }
}

impl From<FfiWsjtxHeartbeat> for Heartbeat {
    fn from(h: FfiWsjtxHeartbeat) -> Self {
        Heartbeat {
            id: h.id,
            max_schema_number: h.max_schema_number,
            version: h.version,
            revision: h.revision,
        }
    }
}

impl From<Status> for FfiWsjtxStatus {
    fn from(s: Status) -> Self {
        FfiWsjtxStatus {
            id: s.id,
            dial_frequency_hz: s.dial_frequency_hz,
            mode: s.mode,
            dx_call: s.dx_call,
            report: s.report,
            tx_mode: s.tx_mode,
            tx_enabled: s.tx_enabled,
            transmitting: s.transmitting,
            decoding: s.decoding,
            rx_df: s.rx_df,
            tx_df: s.tx_df,
            de_call: s.de_call,
            de_grid: s.de_grid,
            dx_grid: s.dx_grid,
            tx_watchdog: s.tx_watchdog,
            sub_mode: s.sub_mode,
            fast_mode: s.fast_mode,
            special_operation_mode: s.special_operation_mode,
            frequency_tolerance: s.frequency_tolerance,
            tr_period: s.tr_period,
            configuration_name: s.configuration_name,
            tx_message: s.tx_message,
        }
    }
}

impl From<FfiWsjtxStatus> for Status {
    fn from(s: FfiWsjtxStatus) -> Self {
        Status {
            id: s.id,
            dial_frequency_hz: s.dial_frequency_hz,
            mode: s.mode,
            dx_call: s.dx_call,
            report: s.report,
            tx_mode: s.tx_mode,
            tx_enabled: s.tx_enabled,
            transmitting: s.transmitting,
            decoding: s.decoding,
            rx_df: s.rx_df,
            tx_df: s.tx_df,
            de_call: s.de_call,
            de_grid: s.de_grid,
            dx_grid: s.dx_grid,
            tx_watchdog: s.tx_watchdog,
            sub_mode: s.sub_mode,
            fast_mode: s.fast_mode,
            special_operation_mode: s.special_operation_mode,
            frequency_tolerance: s.frequency_tolerance,
            tr_period: s.tr_period,
            configuration_name: s.configuration_name,
            tx_message: s.tx_message,
        }
    }
}

impl From<Decode> for FfiWsjtxDecode {
    fn from(d: Decode) -> Self {
        FfiWsjtxDecode {
            id: d.id,
            new: d.new,
            time_ms: d.time.map(time_to_ms),
            snr: d.snr,
            delta_time: d.delta_time,
            delta_frequency: d.delta_frequency,
            mode: d.mode,
            message: d.message,
            low_confidence: d.low_confidence,
            off_air: d.off_air,
        }
    }
}

impl From<FfiWsjtxDecode> for Decode {
    fn from(d: FfiWsjtxDecode) -> Self {
        Decode {
            id: d.id,
            new: d.new,
            time: d.time_ms.and_then(ms_to_time),
            snr: d.snr,
            delta_time: d.delta_time,
            delta_frequency: d.delta_frequency,
            mode: d.mode,
            message: d.message,
            low_confidence: d.low_confidence,
            off_air: d.off_air,
        }
    }
}

impl From<QsoLogged> for FfiWsjtxQsoLogged {
    fn from(q: QsoLogged) -> Self {
        FfiWsjtxQsoLogged {
            id: q.id,
            date_time_off: q.date_time_off.map(|dt| dt.timestamp()),
            dx_call: q.dx_call,
            dx_grid: q.dx_grid,
            tx_frequency_hz: q.tx_frequency_hz,
            mode: q.mode,
            report_sent: q.report_sent,
            report_received: q.report_received,
            tx_power: q.tx_power,
            comments: q.comments,
            name: q.name,
            date_time_on: q.date_time_on.map(|dt| dt.timestamp()),
            operator_call: q.operator_call,
            my_call: q.my_call,
            my_grid: q.my_grid,
            exchange_sent: q.exchange_sent,
            exchange_received: q.exchange_received,
            adif_propagation_mode: q.adif_propagation_mode,
        }
    }
}

impl From<FfiWsjtxQsoLogged> for QsoLogged {
    fn from(q: FfiWsjtxQsoLogged) -> Self {
        QsoLogged {
            id: q.id,
            date_time_off: q.date_time_off.and_then(secs_to_datetime),
            dx_call: q.dx_call,
            dx_grid: q.dx_grid,
            tx_frequency_hz: q.tx_frequency_hz,
            mode: q.mode,
            report_sent: q.report_sent,
            report_received: q.report_received,
            tx_power: q.tx_power,
            comments: q.comments,
            name: q.name,
            date_time_on: q.date_time_on.and_then(secs_to_datetime),
            operator_call: q.operator_call,
            my_call: q.my_call,
            my_grid: q.my_grid,
            exchange_sent: q.exchange_sent,
            exchange_received: q.exchange_received,
            adif_propagation_mode: q.adif_propagation_mode,
        }
    }
}

impl From<LoggedAdif> for FfiWsjtxLoggedAdif {
    fn from(a: LoggedAdif) -> Self {
        FfiWsjtxLoggedAdif { id: a.id, adif: a.adif }
    }
}

impl From<FfiWsjtxLoggedAdif> for LoggedAdif {
    fn from(a: FfiWsjtxLoggedAdif) -> Self {
        LoggedAdif { id: a.id, adif: a.adif }
    }
}

impl From<WsjtxMessage> for FfiWsjtxMessage {
    fn from(message: WsjtxMessage) -> Self {
        match message {
            WsjtxMessage::Heartbeat(h) => FfiWsjtxMessage::Heartbeat { heartbeat: h.into() },
            WsjtxMessage::Status(s) => FfiWsjtxMessage::Status { status: (*s).into() },
            WsjtxMessage::Decode(d) => FfiWsjtxMessage::Decode { decode: d.into() },
            WsjtxMessage::QsoLogged(q) => FfiWsjtxMessage::QsoLogged { qso: (*q).into() },
            WsjtxMessage::LoggedAdif(a) => FfiWsjtxMessage::LoggedAdif { adif: a.into() },
            WsjtxMessage::Close { id } => FfiWsjtxMessage::Close { id },
            WsjtxMessage::Other { kind, id } => FfiWsjtxMessage::Other { kind, id },
        }
    }
}

impl From<FfiWsjtxImportContext> for WsjtxImportContext {
    fn from(ctx: FfiWsjtxImportContext) -> Self {
        WsjtxImportContext {
            station_callsign: ctx.station_callsign,
            imported_at: ctx.imported_at,
            logging_session_id: ctx.logging_session_id,
        }
    }
}

// ---------------------------------------------------------------------------
// Free functions
// ---------------------------------------------------------------------------

/// The UDP port WSJT-X transmits to by default (2237).
#[uniffi::export]
pub fn wsjtx_default_port() -> u16 {
    WSJTX_DEFAULT_PORT
}

/// Decode one raw WSJT-X datagram. For hosts that own their own socket (or
/// tests); the listener decodes for you.
#[uniffi::export]
pub fn wsjtx_decode_datagram(datagram: Vec<u8>) -> Result<FfiWsjtxMessage, WsjtxError> {
    wsjtx::decode(&datagram)
        .map(Into::into)
        .map_err(|err| WsjtxError::Decode { reason: err.to_string() })
}

/// Map a type-5 `QSOLogged` message to a store QSO
/// (`cw_store::qso_from_qso_logged`). Insert the result with
/// `FieldStore::upsert_qso`; its `id` is the WSJT-X dedup-derived UUIDv5, so
/// the matching `LoggedADIF` upserts into the same row.
#[uniffi::export]
pub fn wsjtx_map_qso_logged(
    message: FfiWsjtxQsoLogged,
    context: FfiWsjtxImportContext,
) -> Result<FfiQso, WsjtxError> {
    let qso = qso_from_qso_logged(&message.into(), &context.into())?;
    Ok(qso.into())
}

/// Map a type-12 `LoggedADIF` message to store QSOs, one per `<eor>` record
/// (`cw_store::qso_from_logged_adif`; WSJT-X sends exactly one).
#[uniffi::export]
pub fn wsjtx_map_logged_adif(
    message: FfiWsjtxLoggedAdif,
    context: FfiWsjtxImportContext,
) -> Result<Vec<FfiQso>, WsjtxError> {
    let qsos = qso_from_logged_adif(&message.into(), &context.into())?;
    Ok(qsos.into_iter().map(Into::into).collect())
}

/// The dedup identity of a mapped QSO (`cw_store::wsjtx_dedup_key`):
/// `CALLSIGN|BAND|MODE|2-minute-bucket`, comparable with the iOS
/// `QSO.deduplicationKey` of already-stored QSOs.
#[uniffi::export]
pub fn wsjtx_dedup_key(qso: FfiQso) -> String {
    store_dedup_key(&qso.into())
}

// ---------------------------------------------------------------------------
// Listener delegate + API object
// ---------------------------------------------------------------------------

/// Host-side sink for listener events. Called on a Rust runtime thread — hop
/// to the UI actor before touching state.
#[uniffi::export(with_foreign)]
pub trait WsjtxListenerDelegate: Send + Sync {
    /// One decoded datagram. `from` is the sender's `ip:port`.
    fn on_message(&self, message: FfiWsjtxMessage, from: String);
    /// A datagram that failed to decode (listening continues) or a socket
    /// failure (listening ends; `on_stopped` follows).
    fn on_error(&self, message: String);
    /// The receive loop exited (after `stop()`, drop, or a socket failure);
    /// no further callbacks.
    fn on_stopped(&self);
}

struct Running {
    task: JoinHandle<()>,
    shutdown: Option<oneshot::Sender<()>>,
    local_addr: SocketAddr,
}

impl Running {
    /// Ask the loop to exit. Dropping the sender is enough — the loop treats a
    /// closed channel as shutdown too.
    fn signal_shutdown(&mut self) {
        if let Some(tx) = self.shutdown.take() {
            let _ = tx.send(());
        }
    }
}

/// A WSJT-X UDP listener the host starts and stops. One receive loop at a
/// time per object; create another `WsjtxApi` to listen on a second port.
#[derive(uniffi::Object)]
pub struct WsjtxApi {
    state: Mutex<Option<Running>>,
}

impl Default for WsjtxApi {
    fn default() -> Self {
        WsjtxApi { state: Mutex::new(None) }
    }
}

impl WsjtxApi {
    fn lock(&self) -> std::sync::MutexGuard<'_, Option<Running>> {
        self.state.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

#[uniffi::export]
impl WsjtxApi {
    /// An idle listener; call `start` to bind.
    #[uniffi::constructor]
    pub fn new() -> Self {
        WsjtxApi::default()
    }

    /// `true` while the receive loop is alive (between a successful `start`
    /// and `stop()` / a socket failure).
    pub fn is_running(&self) -> bool {
        self.lock().as_ref().is_some_and(|running| !running.task.is_finished())
    }

    /// The port the running listener is bound to; `None` when not running.
    pub fn local_port(&self) -> Option<u16> {
        self.lock().as_ref().map(|running| running.local_addr.port())
    }

    /// Stop the receive loop. Returns immediately; the delegate's
    /// `on_stopped` fires asynchronously once the loop has exited (no
    /// `on_message` follows it). Idempotent.
    pub fn stop(&self) {
        let taken = self.lock().take();
        if let Some(mut running) = taken {
            running.signal_shutdown();
        }
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl WsjtxApi {
    /// Bind `host:port` (WSJT-X's default target is `127.0.0.1:2237`; use
    /// port `0` to let the OS pick) and start delivering decoded messages to
    /// `delegate`. Returns the bound port. Fails with `AlreadyRunning` if this
    /// object already has a live loop, or `Bind` if the socket can't be bound.
    pub async fn start(
        &self,
        host: String,
        port: u16,
        delegate: Arc<dyn WsjtxListenerDelegate>,
    ) -> Result<u16, WsjtxError> {
        if self.is_running() {
            return Err(WsjtxError::AlreadyRunning);
        }
        let address = format!("{host}:{port}");
        let bind_error = |reason: String| WsjtxError::Bind { address: address.clone(), reason };
        let listener = WsjtxListener::bind(address.as_str())
            .await
            .map_err(|err| bind_error(err.to_string()))?;
        let local_addr = listener.local_addr().map_err(|err| bind_error(err.to_string()))?;

        // Re-check under the lock: a concurrent `start` may have won the race
        // while we were binding.
        let mut state = self.lock();
        if state.as_ref().is_some_and(|running| !running.task.is_finished()) {
            return Err(WsjtxError::AlreadyRunning);
        }
        let (shutdown_tx, shutdown_rx) = oneshot::channel();
        let task = tokio::spawn(receive_loop(listener, delegate, shutdown_rx));
        *state = Some(Running { task, shutdown: Some(shutdown_tx), local_addr });
        Ok(local_addr.port())
    }
}

impl Drop for WsjtxApi {
    fn drop(&mut self) {
        if let Some(running) = self.lock().as_mut() {
            running.signal_shutdown();
        }
    }
}

/// The receive loop: decode each datagram into the delegate until shutdown
/// or a socket error. Always ends with exactly one `on_stopped`.
async fn receive_loop(
    listener: WsjtxListener,
    delegate: Arc<dyn WsjtxListenerDelegate>,
    mut shutdown: oneshot::Receiver<()>,
) {
    loop {
        tokio::select! {
            // Fires on `stop()` (Ok) and when the sender is dropped (Err).
            _ = &mut shutdown => break,
            received = listener.recv() => match received {
                Ok((message, from)) => delegate.on_message(message.into(), from.to_string()),
                Err(wsjtx::WsjtxError::Io(err)) => {
                    delegate.on_error(format!("socket error: {err}"));
                    break;
                }
                Err(err) => delegate.on_error(err.to_string()),
            },
        }
    }
    delegate.on_stopped();
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{Datelike, NaiveDate};
    use cw_net::wsjtx::WSJTX_MAGIC;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::Duration;
    use tokio::sync::mpsc;

    // ---- sample messages ---------------------------------------------------

    fn sample_status() -> Status {
        Status {
            id: "WSJT-X".into(),
            dial_frequency_hz: 14_074_000,
            mode: "FT8".into(),
            dx_call: "JA1ABC".into(),
            report: "-15".into(),
            tx_mode: "FT8".into(),
            tx_enabled: true,
            transmitting: false,
            decoding: true,
            rx_df: Some(1500),
            tx_df: Some(1200),
            de_call: Some("W6JY".into()),
            de_grid: Some("CM87".into()),
            dx_grid: Some("PM95".into()),
            tx_watchdog: Some(false),
            sub_mode: Some(String::new()),
            fast_mode: Some(false),
            special_operation_mode: Some(7),
            frequency_tolerance: Some(20),
            tr_period: Some(15),
            configuration_name: Some("Default".into()),
            tx_message: Some("JA1ABC W6JY CM87".into()),
        }
    }

    fn sample_decode() -> Decode {
        Decode {
            id: "JTDX".into(),
            new: false,
            time: NaiveTime::from_hms_milli_opt(23, 59, 45, 500),
            snr: -12,
            delta_time: 0.3,
            delta_frequency: 1523,
            mode: "~".into(),
            message: "CQ DX JA1ABC PM95".into(),
            low_confidence: Some(true),
            off_air: Some(false),
        }
    }

    fn time_on() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 3, 14, 18, 30, 15).unwrap()
    }

    fn time_off() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 3, 14, 18, 31, 0).unwrap()
    }

    fn sample_qso_logged() -> QsoLogged {
        QsoLogged {
            id: "WSJT-X".into(),
            date_time_off: Some(time_off()),
            dx_call: "K1ABC".into(),
            dx_grid: "FN42".into(),
            tx_frequency_hz: 14_075_245,
            mode: "FT8".into(),
            report_sent: "-10".into(),
            report_received: "-05".into(),
            tx_power: "50".into(),
            comments: "Nice QSO".into(),
            name: "Bob".into(),
            date_time_on: Some(time_on()),
            operator_call: "N0CAL".into(),
            my_call: "W6JY".into(),
            my_grid: "CM87xx".into(),
            exchange_sent: "579 CA".into(),
            exchange_received: "599 MA".into(),
            adif_propagation_mode: "ES".into(),
        }
    }

    const SAMPLE_ADIF: &str = "WSJT-X ADIF Export<eoh>\n\
        <call:5>K1ABC <gridsquare:4>FN42 <mode:3>FT8 <rst_sent:3>-10 <rst_rcvd:3>-05 \
        <qso_date:8>20260314 <time_on:6>183015 <band:3>20m <freq:9>14.075245 \
        <station_callsign:4>W6JY <my_gridsquare:6>CM87xx <tx_pwr:2>50 <eor>";

    fn ctx() -> FfiWsjtxImportContext {
        FfiWsjtxImportContext {
            station_callsign: Some("w6jy".into()),
            imported_at: 1_800_000_000,
            logging_session_id: Some("session-1".into()),
        }
    }

    // ---- record round-trips ------------------------------------------------

    #[test]
    fn status_round_trips_every_field() {
        let original = sample_status();
        let ffi: FfiWsjtxStatus = original.clone().into();
        assert_eq!(ffi.id, "WSJT-X");
        assert_eq!(ffi.dial_frequency_hz, 14_074_000);
        assert_eq!(ffi.mode, "FT8");
        assert_eq!(ffi.dx_call, "JA1ABC");
        assert_eq!(ffi.report, "-15");
        assert_eq!(ffi.tx_mode, "FT8");
        assert!(ffi.tx_enabled);
        assert!(!ffi.transmitting);
        assert!(ffi.decoding);
        assert_eq!(ffi.rx_df, Some(1500));
        assert_eq!(ffi.tx_df, Some(1200));
        assert_eq!(ffi.de_call.as_deref(), Some("W6JY"));
        assert_eq!(ffi.de_grid.as_deref(), Some("CM87"));
        assert_eq!(ffi.dx_grid.as_deref(), Some("PM95"));
        assert_eq!(ffi.tx_watchdog, Some(false));
        assert_eq!(ffi.sub_mode.as_deref(), Some(""));
        assert_eq!(ffi.fast_mode, Some(false));
        assert_eq!(ffi.special_operation_mode, Some(7));
        assert_eq!(ffi.frequency_tolerance, Some(20));
        assert_eq!(ffi.tr_period, Some(15));
        assert_eq!(ffi.configuration_name.as_deref(), Some("Default"));
        assert_eq!(ffi.tx_message.as_deref(), Some("JA1ABC W6JY CM87"));
        assert_eq!(Status::from(ffi), original);

        // An original-schema sender: every appended field stays None.
        let old = Status {
            rx_df: None,
            tx_df: None,
            de_call: None,
            de_grid: None,
            dx_grid: None,
            tx_watchdog: None,
            sub_mode: None,
            fast_mode: None,
            special_operation_mode: None,
            frequency_tolerance: None,
            tr_period: None,
            configuration_name: None,
            tx_message: None,
            ..sample_status()
        };
        let ffi: FfiWsjtxStatus = old.clone().into();
        assert_eq!(ffi.rx_df, None);
        assert_eq!(ffi.tx_message, None);
        assert_eq!(Status::from(ffi), old);
    }

    #[test]
    fn decode_round_trips_every_field() {
        let original = sample_decode();
        let ffi: FfiWsjtxDecode = original.clone().into();
        assert_eq!(ffi.id, "JTDX");
        assert!(!ffi.new);
        assert_eq!(ffi.time_ms, Some(23 * 3_600_000 + 59 * 60_000 + 45_500));
        assert_eq!(ffi.snr, -12);
        assert_eq!(ffi.delta_time, 0.3);
        assert_eq!(ffi.delta_frequency, 1523);
        assert_eq!(ffi.mode, "~");
        assert_eq!(ffi.message, "CQ DX JA1ABC PM95");
        assert_eq!(ffi.low_confidence, Some(true));
        assert_eq!(ffi.off_air, Some(false));
        assert_eq!(Decode::from(ffi), original);

        // Null QTime + original-schema flags.
        let old = Decode { time: None, low_confidence: None, off_air: None, ..sample_decode() };
        let ffi: FfiWsjtxDecode = old.clone().into();
        assert_eq!(ffi.time_ms, None);
        assert_eq!(ffi.low_confidence, None);
        assert_eq!(Decode::from(ffi), old);

        // Midnight and the last millisecond of the day both survive.
        for time in [
            NaiveTime::from_hms_opt(0, 0, 0).unwrap(),
            NaiveTime::from_hms_milli_opt(23, 59, 59, 999).unwrap(),
        ] {
            assert_eq!(ms_to_time(time_to_ms(time)), Some(time));
        }
    }

    #[test]
    fn qso_logged_round_trips_every_field() {
        let original = sample_qso_logged();
        let ffi: FfiWsjtxQsoLogged = original.clone().into();
        assert_eq!(ffi.id, "WSJT-X");
        assert_eq!(ffi.date_time_off, Some(time_off().timestamp()));
        assert_eq!(ffi.dx_call, "K1ABC");
        assert_eq!(ffi.dx_grid, "FN42");
        assert_eq!(ffi.tx_frequency_hz, 14_075_245);
        assert_eq!(ffi.mode, "FT8");
        assert_eq!(ffi.report_sent, "-10");
        assert_eq!(ffi.report_received, "-05");
        assert_eq!(ffi.tx_power, "50");
        assert_eq!(ffi.comments, "Nice QSO");
        assert_eq!(ffi.name, "Bob");
        assert_eq!(ffi.date_time_on, Some(time_on().timestamp()));
        assert_eq!(ffi.date_time_on, Some(1_773_513_015), "epoch seconds, not ms");
        assert_eq!(ffi.operator_call, "N0CAL");
        assert_eq!(ffi.my_call, "W6JY");
        assert_eq!(ffi.my_grid, "CM87xx");
        assert_eq!(ffi.exchange_sent, "579 CA");
        assert_eq!(ffi.exchange_received, "599 MA");
        assert_eq!(ffi.adif_propagation_mode, "ES");
        assert_eq!(QsoLogged::from(ffi), original);

        let no_times = QsoLogged { date_time_on: None, date_time_off: None, ..sample_qso_logged() };
        let ffi: FfiWsjtxQsoLogged = no_times.clone().into();
        assert_eq!(ffi.date_time_on, None);
        assert_eq!(ffi.date_time_off, None);
        assert_eq!(QsoLogged::from(ffi), no_times);
    }

    #[test]
    fn heartbeat_and_logged_adif_round_trip() {
        let heartbeat = Heartbeat {
            id: "WSJT-X".into(),
            max_schema_number: 3,
            version: "2.6.1".into(),
            revision: "a1b2c3d".into(),
        };
        let ffi: FfiWsjtxHeartbeat = heartbeat.clone().into();
        assert_eq!(ffi.max_schema_number, 3);
        assert_eq!(ffi.version, "2.6.1");
        assert_eq!(ffi.revision, "a1b2c3d");
        assert_eq!(Heartbeat::from(ffi), heartbeat);

        let adif = LoggedAdif { id: "WSJT-X".into(), adif: SAMPLE_ADIF.into() };
        let ffi: FfiWsjtxLoggedAdif = adif.clone().into();
        assert_eq!(ffi.adif, SAMPLE_ADIF);
        assert_eq!(LoggedAdif::from(ffi), adif);
    }

    #[test]
    fn every_message_variant_maps() {
        let cases: Vec<(WsjtxMessage, FfiWsjtxMessage)> = vec![
            (
                WsjtxMessage::Status(Box::new(sample_status())),
                FfiWsjtxMessage::Status { status: sample_status().into() },
            ),
            (
                WsjtxMessage::Decode(sample_decode()),
                FfiWsjtxMessage::Decode { decode: sample_decode().into() },
            ),
            (
                WsjtxMessage::QsoLogged(Box::new(sample_qso_logged())),
                FfiWsjtxMessage::QsoLogged { qso: sample_qso_logged().into() },
            ),
            (
                WsjtxMessage::LoggedAdif(LoggedAdif { id: "X".into(), adif: "<eor>".into() }),
                FfiWsjtxMessage::LoggedAdif {
                    adif: FfiWsjtxLoggedAdif { id: "X".into(), adif: "<eor>".into() },
                },
            ),
            (
                WsjtxMessage::Close { id: "WSJT-X".into() },
                FfiWsjtxMessage::Close { id: "WSJT-X".into() },
            ),
            (
                WsjtxMessage::Other { kind: 3, id: "WSJT-X".into() },
                FfiWsjtxMessage::Other { kind: 3, id: "WSJT-X".into() },
            ),
        ];
        for (message, expected) in cases {
            assert_eq!(FfiWsjtxMessage::from(message), expected);
        }
    }

    // ---- store-mapping helpers ----------------------------------------------

    #[test]
    fn map_qso_logged_matches_the_store_mapping() {
        let ffi_qso = wsjtx_map_qso_logged(sample_qso_logged().into(), ctx()).unwrap();
        let direct = qso_from_qso_logged(&sample_qso_logged(), &ctx().into()).unwrap();
        assert_eq!(ffi_qso.id, direct.id);
        assert_eq!(ffi_qso.callsign, "K1ABC");
        assert_eq!(ffi_qso.band.as_deref(), Some("20m"));
        assert_eq!(ffi_qso.mode.as_deref(), Some("FT8"));
        assert_eq!(ffi_qso.freq_khz, Some(14_075.245));
        assert_eq!(ffi_qso.qso_date, time_on().timestamp());
        assert_eq!(ffi_qso.my_callsign.as_deref(), Some("N0CAL"));
        assert_eq!(ffi_qso.station_callsign.as_deref(), Some("W6JY"));
        assert_eq!(ffi_qso.import_source_raw_value, cw_store::WSJTX_IMPORT_SOURCE);
        assert_eq!(ffi_qso.imported_at, 1_800_000_000);
        assert_eq!(ffi_qso.logging_session_id.as_deref(), Some("session-1"));
        assert!(ffi_qso.dirty);
        assert!(ffi_qso.presence.is_empty());

        // The dedup key round-trips through the FFI QSO and is what CAR-282
        // compares against existing rows.
        let bucket = Utc.with_ymd_and_hms(2026, 3, 14, 18, 30, 0).unwrap().timestamp();
        assert_eq!(wsjtx_dedup_key(ffi_qso), format!("K1ABC|20M|FT8|{bucket}"));
    }

    #[test]
    fn map_logged_adif_yields_the_same_identity() {
        let from_logged = wsjtx_map_qso_logged(
            FfiWsjtxQsoLogged {
                operator_call: String::new(),
                exchange_sent: String::new(),
                exchange_received: String::new(),
                adif_propagation_mode: String::new(),
                ..sample_qso_logged().into()
            },
            ctx(),
        )
        .unwrap();
        let from_adif = wsjtx_map_logged_adif(
            FfiWsjtxLoggedAdif { id: "WSJT-X".into(), adif: SAMPLE_ADIF.into() },
            ctx(),
        )
        .unwrap();
        assert_eq!(from_adif.len(), 1);
        assert_eq!(from_adif[0].id, from_logged.id);
        assert_eq!(from_adif[0].callsign, "K1ABC");
        assert!(from_adif[0].raw_adif.as_deref().unwrap().contains("<call:5>K1ABC"));
        assert_eq!(from_adif[0].power, Some(50));
    }

    #[test]
    fn import_errors_map_one_to_one() {
        // `FfiQso` is not `Debug`/`PartialEq`, so compare the `Err` side only.
        let blank_call = FfiWsjtxQsoLogged { dx_call: "  ".into(), ..sample_qso_logged().into() };
        assert_eq!(
            wsjtx_map_qso_logged(blank_call, ctx()).err(),
            Some(WsjtxError::MissingCallsign)
        );

        let no_time = FfiWsjtxQsoLogged {
            date_time_on: None,
            date_time_off: None,
            ..sample_qso_logged().into()
        };
        assert_eq!(
            wsjtx_map_qso_logged(no_time, ctx()).err(),
            Some(WsjtxError::MissingTimestamp)
        );

        let empty = FfiWsjtxLoggedAdif { id: "X".into(), adif: "WSJT-X<eoh>".into() };
        assert_eq!(wsjtx_map_logged_adif(empty, ctx()).err(), Some(WsjtxError::NoAdifRecords));

        let no_date = FfiWsjtxLoggedAdif {
            id: "X".into(),
            adif: "<call:5>K1ABC <band:3>20m <mode:3>FT8 <eor>".into(),
        };
        assert_eq!(
            wsjtx_map_logged_adif(no_date, ctx()).err(),
            Some(WsjtxError::MissingAdifTimestamp { callsign: "K1ABC".into() })
        );
    }

    #[test]
    fn default_port_and_datagram_decode() {
        assert_eq!(wsjtx_default_port(), 2237);
        assert_eq!(
            wsjtx_decode_datagram(header(6, "WSJT-X")),
            Ok(FfiWsjtxMessage::Close { id: "WSJT-X".into() })
        );
        assert!(matches!(
            wsjtx_decode_datagram(vec![0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0]),
            Err(WsjtxError::Decode { .. })
        ));
    }

    // ---- wire encoder (mirrors cw-net's test helpers) ----------------------

    fn put_u32(b: &mut Vec<u8>, v: u32) {
        b.extend_from_slice(&v.to_be_bytes());
    }
    fn put_string(b: &mut Vec<u8>, s: &str) {
        put_u32(b, s.len() as u32);
        b.extend_from_slice(s.as_bytes());
    }
    /// Qt `QDateTime` in UTC (timespec 1). JDN 2440588 == 1970-01-01, and
    /// chrono's `num_days_from_ce` is 719163 for that date.
    fn put_datetime(b: &mut Vec<u8>, dt: Option<DateTime<Utc>>) {
        match dt {
            None => {
                b.extend_from_slice(&0i64.to_be_bytes());
                put_u32(b, 0);
                b.push(1);
            }
            Some(dt) => {
                let jdn = i64::from(dt.date_naive().num_days_from_ce()) + 1_721_425;
                b.extend_from_slice(&jdn.to_be_bytes());
                put_u32(b, dt.num_seconds_from_midnight() * 1_000);
                b.push(1);
            }
        }
    }
    fn header(kind: u32, id: &str) -> Vec<u8> {
        let mut b = Vec::new();
        put_u32(&mut b, WSJTX_MAGIC);
        put_u32(&mut b, 3);
        put_u32(&mut b, kind);
        put_string(&mut b, id);
        b
    }
    fn qso_logged_datagram(q: &QsoLogged) -> Vec<u8> {
        let mut b = header(5, &q.id);
        put_datetime(&mut b, q.date_time_off);
        put_string(&mut b, &q.dx_call);
        put_string(&mut b, &q.dx_grid);
        b.extend_from_slice(&q.tx_frequency_hz.to_be_bytes());
        for s in [&q.mode, &q.report_sent, &q.report_received, &q.tx_power, &q.comments, &q.name] {
            put_string(&mut b, s);
        }
        put_datetime(&mut b, q.date_time_on);
        for s in [
            &q.operator_call,
            &q.my_call,
            &q.my_grid,
            &q.exchange_sent,
            &q.exchange_received,
            &q.adif_propagation_mode,
        ] {
            put_string(&mut b, s);
        }
        b
    }

    #[test]
    fn test_encoder_jdn_anchor() {
        let epoch = NaiveDate::from_ymd_opt(1970, 1, 1).unwrap();
        assert_eq!(i64::from(epoch.num_days_from_ce()) + 1_721_425, 2_440_588);
    }

    // ---- listener ----------------------------------------------------------

    enum Event {
        // Boxed: `FfiWsjtxMessage` is ~400 bytes (clippy::large_enum_variant).
        Message(Box<FfiWsjtxMessage>, String),
        Error(String),
        Stopped,
    }

    struct ChannelDelegate {
        tx: mpsc::UnboundedSender<Event>,
        stopped: AtomicUsize,
    }

    impl ChannelDelegate {
        fn new() -> (Arc<Self>, mpsc::UnboundedReceiver<Event>) {
            let (tx, rx) = mpsc::unbounded_channel();
            (Arc::new(ChannelDelegate { tx, stopped: AtomicUsize::new(0) }), rx)
        }
    }

    impl WsjtxListenerDelegate for ChannelDelegate {
        fn on_message(&self, message: FfiWsjtxMessage, from: String) {
            let _ = self.tx.send(Event::Message(Box::new(message), from));
        }
        fn on_error(&self, message: String) {
            let _ = self.tx.send(Event::Error(message));
        }
        fn on_stopped(&self) {
            self.stopped.fetch_add(1, Ordering::SeqCst);
            let _ = self.tx.send(Event::Stopped);
        }
    }

    async fn next_event(rx: &mut mpsc::UnboundedReceiver<Event>) -> Event {
        tokio::time::timeout(Duration::from_secs(5), rx.recv())
            .await
            .expect("timed out waiting for delegate event")
            .expect("delegate channel closed")
    }

    #[tokio::test]
    async fn listener_delivers_decoded_qso_to_the_delegate() {
        let api = WsjtxApi::new();
        let (delegate, mut rx) = ChannelDelegate::new();
        assert!(!api.is_running());
        assert_eq!(api.local_port(), None);

        let port = api.start("127.0.0.1".into(), 0, delegate.clone()).await.unwrap();
        assert_ne!(port, 0, "port 0 resolves to the OS-assigned port");
        assert!(api.is_running());
        assert_eq!(api.local_port(), Some(port));

        // A second start on the same object is refused, not silently replaced.
        assert_eq!(
            api.start("127.0.0.1".into(), 0, delegate.clone()).await,
            Err(WsjtxError::AlreadyRunning)
        );

        let client = tokio::net::UdpSocket::bind("127.0.0.1:0").await.unwrap();
        client
            .send_to(&qso_logged_datagram(&sample_qso_logged()), ("127.0.0.1", port))
            .await
            .unwrap();

        let Event::Message(message, from) = next_event(&mut rx).await else {
            panic!("expected a decoded message first");
        };
        assert_eq!(from, client.local_addr().unwrap().to_string());
        assert_eq!(*message, FfiWsjtxMessage::QsoLogged { qso: sample_qso_logged().into() });

        // The event maps straight into a store QSO for CAR-282 to upsert.
        let FfiWsjtxMessage::QsoLogged { qso } = *message else { unreachable!() };
        let mapped = wsjtx_map_qso_logged(qso, ctx()).unwrap();
        assert_eq!(mapped.callsign, "K1ABC");
        assert_eq!(mapped.qso_date, time_on().timestamp());

        // An undecodable datagram is reported and listening continues.
        client.send_to(&[1, 2, 3], ("127.0.0.1", port)).await.unwrap();
        let Event::Error(reason) = next_event(&mut rx).await else {
            panic!("expected an error event");
        };
        assert!(reason.contains("unexpected end of datagram"), "{reason}");
        client.send_to(&header(6, "WSJT-X"), ("127.0.0.1", port)).await.unwrap();
        let Event::Message(message, _) = next_event(&mut rx).await else {
            panic!("expected a Close message after the bad datagram");
        };
        assert_eq!(*message, FfiWsjtxMessage::Close { id: "WSJT-X".into() });
        assert!(api.is_running());

        // stop() ends the loop with exactly one on_stopped; a second stop is a no-op.
        api.stop();
        assert!(!api.is_running());
        assert_eq!(api.local_port(), None);
        let Event::Stopped = next_event(&mut rx).await else {
            panic!("expected on_stopped after stop()");
        };
        api.stop();
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert_eq!(delegate.stopped.load(Ordering::SeqCst), 1);

        // The object is reusable after stop.
        let port2 = api.start("127.0.0.1".into(), 0, delegate.clone()).await.unwrap();
        assert!(api.is_running());
        assert_eq!(api.local_port(), Some(port2));
        api.stop();
        let Event::Stopped = next_event(&mut rx).await else {
            panic!("expected on_stopped after the second stop()");
        };
    }

    #[tokio::test]
    async fn bind_failure_surfaces_as_bind_error() {
        let api = WsjtxApi::new();
        let (delegate, _rx) = ChannelDelegate::new();
        let err = api.start("999.999.999.999".into(), 0, delegate).await.unwrap_err();
        match err {
            WsjtxError::Bind { address, .. } => assert_eq!(address, "999.999.999.999:0"),
            other => panic!("expected Bind, got {other:?}"),
        }
        assert!(!api.is_running());
    }

    #[tokio::test]
    async fn dropping_the_api_stops_the_loop() {
        let api = WsjtxApi::new();
        let (delegate, mut rx) = ChannelDelegate::new();
        api.start("127.0.0.1".into(), 0, delegate).await.unwrap();
        drop(api);
        let Event::Stopped = next_event(&mut rx).await else {
            panic!("expected on_stopped after drop");
        };
    }
}
