//! Shared logger command *handler* — the execution side of `logger_command`.
//!
//! Where `parse_logger_command` turns text into an [`FfiLoggerCommand`], this runs
//! it: session-field mutations (frequency / mode / grid / callsign / note /
//! session-metadata) are applied to cw-store here and returned as
//! [`FfiCommandOutcome::SessionUpdated`], so both apps get identical command
//! behavior instead of reimplementing it natively. Commands whose effect is a
//! network post (self-spot), a one-off log, or a UI panel come back as a typed
//! *intent* the host carries out (it still owns the actual radio/network/UI —
//! those can't live in Rust — but the decision + shared state change do).

use std::sync::Arc;

use chrono::{SecondsFormat, Utc};
use cw_domain::band::BandUtilities;
use cw_store::LoggingSession;

use crate::entities::logging_session::FfiLoggingSession;
use crate::logger_command::FfiLoggerCommand;
use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::quick_entry::FfiQuickEntry;
use crate::session_api::FfiSessionLogInput;
use crate::{CwError, FieldStore};

/// Host preferences the handler needs to reproduce the native command behavior.
#[derive(uniffi::Record)]
pub struct FfiCommandContext {
    /// POTA/SOTA QSY-spot prompt is enabled — gates `prompt_qsy_spot`.
    pub pota_qsy_spot_enabled: bool,
    /// Auto-spot on the first frequency of a POTA session is enabled.
    pub pota_auto_spot_enabled: bool,
}

/// Severity for a host toast.
#[derive(uniffi::Enum)]
pub enum FfiMessageLevel {
    Info,
    Success,
    Warning,
    Error,
}

/// A native panel the host should present. The data behind some (RBN spots,
/// solar, weather) is fetched host-side; the icon is host-native.
#[derive(uniffi::Enum)]
pub enum FfiCommandPanel {
    Rbn { callsign: Option<String> },
    Hunt,
    P2p,
    S2s,
    Solar,
    Weather,
    Map,
    Hidden,
    Help,
    Manual,
    Checklist,
    Radio,
    Websdr,
    Band,
    Rig,
    Replay,
}

/// What the host should do after a command runs. State changes are already
/// applied to cw-store; everything else is an intent the host carries out.
// `SessionUpdated` carries a full session row; uniffi enums can't box a variant,
// so the size spread is expected.
#[allow(clippy::large_enum_variant)]
#[derive(uniffi::Enum)]
pub enum FfiCommandOutcome {
    /// The session was changed (freq / mode / grid / callsign / note / metadata).
    /// The host reflects `session`, shows `notice`, and runs its native side
    /// effects: tune the radio to `tuned_frequency_mhz`, present the QSY-spot
    /// sheet when `prompt_qsy_spot`, and post the initial spot when
    /// `auto_spot_first_set`.
    SessionUpdated {
        session: FfiLoggingSession,
        notice: String,
        tuned_frequency_mhz: Option<f64>,
        prompt_qsy_spot: bool,
        auto_spot_first_set: bool,
    },
    /// Log a one-off HUNT QSO (host routes it through the normal log path so
    /// uploads / side effects stay consistent).
    LogQso { input: FfiSessionLogInput },
    /// Post a POTA/SOTA self-spot with this comment (host does the network call).
    PostSpot { comment: Option<String> },
    /// Start a repeating self-spot timer (host owns the timer).
    StartRepeatSpot { comment: Option<String>, interval_minutes: i32 },
    /// Stop the repeating self-spot timer.
    StopRepeatSpot,
    /// Present a native panel.
    Present { panel: FfiCommandPanel },
    /// Show a toast (validation failures, "start a session first", etc.).
    Message { level: FfiMessageLevel, text: String },
}

/// Command handler bound to a [`FieldStore`]. Stateless — reads/mutates the
/// session row per call, so it never drifts from the host's view of the store.
#[derive(uniffi::Object)]
pub struct LoggerCommandApi {
    store: Arc<FieldStore>,
}

#[uniffi::export]
impl LoggerCommandApi {
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>) -> Self {
        LoggerCommandApi { store }
    }

    /// Parse `input` as a command and run it, or `None` when it isn't a command
    /// (the host then treats the input as a callsign / QSO). Lets a host pass raw
    /// text without re-converting a parsed command back across the boundary.
    pub fn handle_text(
        &self,
        session_id: String,
        input: String,
        context: FfiCommandContext,
    ) -> Result<Option<FfiCommandOutcome>, CwError> {
        match cw_domain::logger_command::parse(&input) {
            Some(command) => Ok(Some(self.handle(session_id, FfiLoggerCommand::from(command), context)?)),
            None => Ok(None),
        }
    }

    /// Run `command` against the current session `session_id`. See
    /// [`FfiCommandOutcome`] for what the host does with the result.
    pub fn handle(
        &self,
        session_id: String,
        command: FfiLoggerCommand,
        context: FfiCommandContext,
    ) -> Result<FfiCommandOutcome, CwError> {
        match command {
            FfiLoggerCommand::Frequency { mhz } => self.set_frequency(&session_id, mhz, &context),
            FfiLoggerCommand::Mode { mode } => self.set_mode(&session_id, &mode, &context),
            FfiLoggerCommand::MyCall { callsign } => self.set_my_callsign(&session_id, &callsign),
            FfiLoggerCommand::Note { text } => self.append_note(&session_id, &text),
            FfiLoggerCommand::SessionMetadata { entry } => {
                self.apply_session_metadata(&session_id, entry, &context)
            }
            FfiLoggerCommand::Spot { comment, repeat_minutes } => {
                self.spot(&session_id, comment, repeat_minutes)
            }
            FfiLoggerCommand::SpotStop => Ok(FfiCommandOutcome::StopRepeatSpot),
            FfiLoggerCommand::HuntLog { entry } => self.hunt_log(&session_id, entry),
            FfiLoggerCommand::Rbn { callsign } => {
                Ok(present(FfiCommandPanel::Rbn { callsign }))
            }
            FfiLoggerCommand::Hunt => Ok(present(FfiCommandPanel::Hunt)),
            FfiLoggerCommand::P2p => self.gated_panel(&session_id, Program::Pota, FfiCommandPanel::P2p, "P2P is only available during POTA activations"),
            FfiLoggerCommand::S2s => self.gated_panel(&session_id, Program::Sota, FfiCommandPanel::S2s, "S2S is only available during SOTA activations"),
            FfiLoggerCommand::Solar => Ok(present(FfiCommandPanel::Solar)),
            FfiLoggerCommand::Weather => Ok(present(FfiCommandPanel::Weather)),
            FfiLoggerCommand::Map => Ok(present(FfiCommandPanel::Map)),
            FfiLoggerCommand::Hidden => Ok(present(FfiCommandPanel::Hidden)),
            FfiLoggerCommand::Help => Ok(present(FfiCommandPanel::Help)),
            FfiLoggerCommand::Manual => Ok(present(FfiCommandPanel::Manual)),
            FfiLoggerCommand::Checklist => Ok(present(FfiCommandPanel::Checklist)),
            FfiLoggerCommand::Radio => Ok(present(FfiCommandPanel::Radio)),
            FfiLoggerCommand::Websdr => Ok(present(FfiCommandPanel::Websdr)),
            FfiLoggerCommand::Band => Ok(present(FfiCommandPanel::Band)),
            FfiLoggerCommand::Rig => Ok(present(FfiCommandPanel::Rig)),
            FfiLoggerCommand::Replay => Ok(present(FfiCommandPanel::Replay)),
        }
    }
}

impl LoggerCommandApi {
    fn set_frequency(
        &self,
        id: &str,
        mhz: f64,
        ctx: &FfiCommandContext,
    ) -> Result<FfiCommandOutcome, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let Some(mut session) = store.fetch_logging_session(id)? else {
            return Ok(need_session());
        };
        let old = session.frequency;
        let is_first = old.is_none();
        session.frequency = Some(mhz);
        session.cloud_dirty_flag = true;
        store.upsert_logging_session(&session)?;
        drop(store);
        self.notify_session();

        let band = band_for(mhz);
        let prompt_qsy_spot = ctx.pota_qsy_spot_enabled
            && is_pota(&session)
            && !is_first
            && old != Some(mhz);
        Ok(FfiCommandOutcome::SessionUpdated {
            notice: format!("Frequency set to {mhz:.3} MHz ({band})"),
            session: FfiLoggingSession::from(session),
            tuned_frequency_mhz: Some(mhz),
            prompt_qsy_spot,
            auto_spot_first_set: is_first && ctx.pota_auto_spot_enabled,
        })
    }

    fn set_mode(
        &self,
        id: &str,
        mode: &str,
        ctx: &FfiCommandContext,
    ) -> Result<FfiCommandOutcome, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let Some(mut session) = store.fetch_logging_session(id)? else {
            return Ok(need_session());
        };
        let old = session.mode.clone();
        session.mode = mode.to_string();
        session.cloud_dirty_flag = true;
        store.upsert_logging_session(&session)?;
        drop(store);
        self.notify_session();

        let prompt_qsy_spot = ctx.pota_qsy_spot_enabled && is_pota(&session) && old != mode;
        Ok(FfiCommandOutcome::SessionUpdated {
            notice: format!("Mode set to {mode}"),
            session: FfiLoggingSession::from(session),
            tuned_frequency_mhz: None,
            prompt_qsy_spot,
            auto_spot_first_set: false,
        })
    }

    fn set_my_callsign(&self, id: &str, callsign: &str) -> Result<FfiCommandOutcome, CwError> {
        self.mutate(id, |session| session.my_callsign = callsign.to_string(), format!("Station callsign set to {callsign}"))
    }

    fn append_note(&self, id: &str, text: &str) -> Result<FfiCommandOutcome, CwError> {
        // Port of iOS `appendNote`: newline-joined `[ISO8601|HH:mm] text` lines.
        let now = Utc::now();
        let iso = now.to_rfc3339_opts(SecondsFormat::Secs, true);
        let hhmm = now.format("%H:%M");
        let entry = format!("[{iso}|{hhmm}] {text}");
        self.mutate(
            id,
            |session| {
                session.notes = Some(match session.notes.as_deref() {
                    Some(existing) if !existing.is_empty() => format!("{existing}\n{entry}"),
                    _ => entry.clone(),
                });
            },
            "Note added to session log".to_string(),
        )
    }

    fn apply_session_metadata(
        &self,
        id: &str,
        entry: crate::quick_entry::FfiSessionMetadataEntry,
        ctx: &FfiCommandContext,
    ) -> Result<FfiCommandOutcome, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let Some(mut session) = store.fetch_logging_session(id)? else {
            return Ok(need_session());
        };
        let old_freq = session.frequency;
        let mut applied: Vec<String> = Vec::new();
        if let Some(freq) = entry.frequency {
            session.frequency = Some(freq);
            let band = entry.band.clone().unwrap_or_else(|| band_for(freq));
            applied.push(format!("{freq:.3} MHz ({band})"));
        }
        if let Some(mode) = &entry.mode {
            session.mode = mode.clone();
            applied.push(mode.clone());
        }
        if let Some(grid) = &entry.grid {
            session.my_grid = Some(grid.to_uppercase());
            applied.push(format!("grid {}", grid.to_uppercase()));
        }
        session.cloud_dirty_flag = true;
        store.upsert_logging_session(&session)?;
        drop(store);
        self.notify_session();

        let prompt_qsy_spot = ctx.pota_qsy_spot_enabled
            && is_pota(&session)
            && entry.frequency.is_some()
            && old_freq.is_some()
            && old_freq != entry.frequency;
        Ok(FfiCommandOutcome::SessionUpdated {
            notice: format!("Session set for future QSOs: {}", applied.join(" · ")),
            tuned_frequency_mhz: entry.frequency,
            session: FfiLoggingSession::from(session),
            prompt_qsy_spot,
            auto_spot_first_set: false,
        })
    }

    fn spot(
        &self,
        id: &str,
        comment: Option<String>,
        repeat_minutes: Option<i32>,
    ) -> Result<FfiCommandOutcome, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let Some(session) = store.fetch_logging_session(id)? else {
            return Ok(need_session());
        };
        drop(store);

        // Validation mirrors iOS `postSpot`.
        if !is_pota(&session) && !is_sota(&session) {
            return Ok(error("SPOT requires a POTA or SOTA session"));
        }
        if session.frequency.is_none() {
            return Ok(error("SPOT requires a frequency"));
        }
        if is_pota(&session) && session.park_reference.as_deref().unwrap_or("").is_empty() {
            return Ok(error("POTA spot needs a park reference"));
        }
        if is_sota(&session) && session.sota_reference.as_deref().unwrap_or("").is_empty() {
            return Ok(error("SOTA spot needs a summit reference"));
        }
        if session.my_callsign.is_empty() {
            return Ok(error("No callsign configured"));
        }

        Ok(match repeat_minutes {
            Some(minutes) => FfiCommandOutcome::StartRepeatSpot { comment, interval_minutes: minutes },
            None => FfiCommandOutcome::PostSpot { comment },
        })
    }

    fn hunt_log(&self, id: &str, entry: FfiQuickEntry) -> Result<FfiCommandOutcome, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        if store.fetch_logging_session(id)?.is_none() {
            return Ok(need_session());
        }
        drop(store);
        Ok(FfiCommandOutcome::LogQso { input: hunt_log_input(id, entry) })
    }

    /// Gate a panel on a session program (P2P→POTA, S2S→SOTA).
    fn gated_panel(
        &self,
        id: &str,
        program: Program,
        panel: FfiCommandPanel,
        error_text: &str,
    ) -> Result<FfiCommandOutcome, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let Some(session) = store.fetch_logging_session(id)? else {
            return Ok(need_session());
        };
        drop(store);
        let allowed = match program {
            Program::Pota => is_pota(&session),
            Program::Sota => is_sota(&session),
        };
        Ok(if allowed { present(panel) } else { error(error_text) })
    }

    /// Fetch → mutate → upsert → return a `SessionUpdated` with `notice`.
    fn mutate(
        &self,
        id: &str,
        change: impl FnOnce(&mut LoggingSession),
        notice: String,
    ) -> Result<FfiCommandOutcome, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let Some(mut session) = store.fetch_logging_session(id)? else {
            return Ok(need_session());
        };
        change(&mut session);
        session.cloud_dirty_flag = true;
        store.upsert_logging_session(&session)?;
        drop(store);
        self.notify_session();
        Ok(FfiCommandOutcome::SessionUpdated {
            session: FfiLoggingSession::from(session),
            notice,
            tuned_frequency_mhz: None,
            prompt_qsy_spot: false,
            auto_spot_first_set: false,
        })
    }

    fn notify_session(&self) {
        self.store.notify(FfiStoreChange {
            table: FfiStoreTable::LoggingSession,
            kind: FfiChangeKind::Upsert,
        });
    }
}

enum Program {
    Pota,
    Sota,
}

fn present(panel: FfiCommandPanel) -> FfiCommandOutcome {
    FfiCommandOutcome::Present { panel }
}

fn error(text: &str) -> FfiCommandOutcome {
    FfiCommandOutcome::Message { level: FfiMessageLevel::Error, text: text.to_string() }
}

fn need_session() -> FfiCommandOutcome {
    FfiCommandOutcome::Message {
        level: FfiMessageLevel::Warning,
        text: "Start a session first".to_string(),
    }
}

fn band_for(mhz: f64) -> String {
    BandUtilities::derive_band(Some(mhz * 1000.0)).map(str::to_string).unwrap_or_else(|| "?".to_string())
}

fn programs(session: &LoggingSession) -> std::collections::BTreeSet<String> {
    if !session.programs_raw_value.is_empty() {
        if let Ok(slugs) = serde_json::from_str::<Vec<String>>(&session.programs_raw_value) {
            return slugs.into_iter().collect();
        }
    }
    let activation = session.activation_type_raw_value.as_str();
    if activation == "casual" || activation.is_empty() {
        std::collections::BTreeSet::new()
    } else {
        std::collections::BTreeSet::from([activation.to_string()])
    }
}

fn is_pota(session: &LoggingSession) -> bool {
    programs(session).contains("pota")
}

fn is_sota(session: &LoggingSession) -> bool {
    programs(session).contains("sota")
}

/// Build the one-off HUNT QSO input from the parsed entry (freq/mode as
/// overrides so the session's own freq/mode is untouched).
fn hunt_log_input(session_id: &str, entry: FfiQuickEntry) -> FfiSessionLogInput {
    FfiSessionLogInput {
        session_id: session_id.to_string(),
        callsign: entry.callsign,
        rst_sent: entry.rst_sent.unwrap_or_default(),
        rst_received: entry.rst_received.unwrap_or_default(),
        their_grid: entry.their_grid,
        their_park: entry.their_park,
        notes: entry.notes,
        name: None,
        qth: None,
        state: entry.state,
        country: None,
        their_license_class: None,
        aoa_code: None,
        callsign_change_note: None,
        frequency_override_mhz: entry.frequency,
        mode_override: entry.mode,
        timestamp_override: None,
        contest_name: None,
        contest_serial_sent: None,
        contest_serial_received: None,
        contest_exchange_sent: None,
        contest_exchange_received: None,
        sat_name: None,
        prop_mode: None,
        upload_qrz: false,
        upload_pota: false,
        upload_lofi: false,
        upload_clublog: false,
    }
}
