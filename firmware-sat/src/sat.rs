//! Satellite doppler schedule: upload assembly + pass executor.
//!
//! The app uploads a precomputed pass (SatScheduleBegin + chunked packed
//! steps), then arms it with SatStart. The executor thread configures the
//! radio (modes, uplink tone, initial frequencies), counts down to AOS on
//! the FreeRTOS tick clock, and walks the step table — VFO A is always the
//! doppler-corrected downlink, VFO B the corrected uplink. BLE may drop at
//! any point after arming; status pushes are best-effort.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex};

use ::log::{info, warn};
use cw_sat_core::{unpack_steps, Cursor, StartFreqs, Step, MAX_STEPS, STEP_BYTES};

use crate::generated::cwbp::{SatScheduleBegin, SatScheduleChunk, SatSetActiveVfo, SatStart};
use crate::protocol::{self, SatAckResult, SatRunState};
use crate::rtos;
use crate::usb::UsbHost;
use crate::verify::CatSession;
use crate::BridgeEvent;

/// `seq` value used to ack a SatScheduleBegin (chunks are 0-based).
pub const BEGIN_ACK_SEQ: u32 = u32::MAX;

/// The doppler executor drives one radio's two VFOs (A = downlink, B =
/// uplink). Full-duplex across two separate radios is a later extension of
/// the executor; today it targets radio slot 0.
const SAT_RADIO: usize = 0;

/// Spacing between consecutive CAT commands during setup — the K1 fork
/// saves to EEPROM on most applies; give it room.
const CAT_GAP_MS: u32 = 50;
/// How long to back off when the TX guard sees the radio keyed.
const TX_HOLD_MS: u32 = 500;
/// Countdown status cadence while ARMED.
const COUNTDOWN_PUSH_MS: u64 = 10_000;

/// Everything from SatScheduleBegin the executor needs.
#[derive(Clone)]
struct Header {
    id: u32,
    sat_name: String,
    duration_ms: u64,
    start: StartFreqs,
    downlink_mode: u32,
    uplink_mode: u32,
    uplink_tone_dhz: u32,
}

/// A committed, fully-uploaded schedule.
struct Schedule {
    header: Header,
    steps: Vec<Step>,
}

/// In-progress upload.
struct Loading {
    header: Header,
    total_steps: usize,
    expected_seq: u32,
    bytes: Vec<u8>,
}

/// Live status mirror shared between the executor thread and the manager
/// (for StatusReq dumps).
#[derive(Clone)]
pub struct StatusSnapshot {
    pub state: SatRunState,
    pub schedule_id: u32,
    pub step_index: u32,
    pub downlink_hz: u64,
    pub uplink_hz: u64,
    pub t_ms: i64,
    pub detail: String,
}

impl StatusSnapshot {
    fn idle() -> Self {
        Self {
            state: SatRunState::SatIdle,
            schedule_id: 0,
            step_index: 0,
            downlink_hz: 0,
            uplink_hz: 0,
            t_ms: 0,
            detail: String::new(),
        }
    }

    fn encode(&self) -> Vec<u8> {
        protocol::encode_sat_status(
            self.state,
            self.schedule_id,
            self.step_index,
            self.downlink_hz,
            self.uplink_hz,
            self.t_ms,
            &self.detail,
        )
    }
}

struct RunHandle {
    stop: Arc<AtomicBool>,
    shared: Arc<Mutex<StatusSnapshot>>,
}

impl RunHandle {
    fn active(&self) -> bool {
        matches!(
            self.shared.lock().unwrap().state,
            SatRunState::SatArmed | SatRunState::SatRunning
        )
    }
}

/// Owns the loaded schedule and the executor thread. Lives in the main
/// loop's BridgeState; all handlers return frames for the caller to push
/// over BLE.
pub struct SatManager {
    loading: Option<Loading>,
    schedule: Option<Arc<Schedule>>,
    run: Option<RunHandle>,
}

impl SatManager {
    pub fn new() -> Self {
        Self { loading: None, schedule: None, run: None }
    }

    fn run_active(&self) -> bool {
        self.run.as_ref().map(RunHandle::active).unwrap_or(false)
    }

    /// Current status snapshot for the StatusReq dump.
    pub fn status_frame(&self) -> Vec<u8> {
        if let Some(ref run) = self.run {
            return run.shared.lock().unwrap().encode();
        }
        let mut snap = StatusSnapshot::idle();
        if let Some(ref loading) = self.loading {
            snap.state = SatRunState::SatLoading;
            snap.schedule_id = loading.header.id;
        } else if let Some(ref schedule) = self.schedule {
            snap.schedule_id = schedule.header.id;
            snap.detail = "loaded".into();
        }
        snap.encode()
    }

    pub fn handle_begin(&mut self, msg: &SatScheduleBegin) -> Vec<Vec<u8>> {
        if self.run_active() {
            warn!("SAT_BEGIN rejected: pass already armed/running (id={})", msg.schedule_id);
            return vec![protocol::encode_sat_ack(
                msg.schedule_id,
                BEGIN_ACK_SEQ,
                SatAckResult::SatAckBusy,
                0,
            )];
        }
        let total = msg.total_steps as usize;
        if total == 0 || total > MAX_STEPS {
            warn!("SAT_BEGIN rejected: bad step count {total} (id={})", msg.schedule_id);
            return vec![protocol::encode_sat_ack(
                msg.schedule_id,
                BEGIN_ACK_SEQ,
                SatAckResult::SatAckOverflow,
                0,
            )];
        }
        info!(
            "SAT_BEGIN: id={} sat={:?} steps={} duration={}ms",
            msg.schedule_id, msg.sat_name, total, msg.duration_ms
        );
        self.run = None;
        self.loading = Some(Loading {
            header: Header {
                id: msg.schedule_id,
                sat_name: msg.sat_name.clone(),
                duration_ms: u64::from(msg.duration_ms),
                start: StartFreqs {
                    downlink_hz: msg.downlink_start_hz,
                    uplink_hz: msg.uplink_start_hz,
                },
                downlink_mode: msg.downlink_mode,
                uplink_mode: msg.uplink_mode,
                uplink_tone_dhz: msg.uplink_tone_dhz,
            },
            total_steps: total,
            expected_seq: 0,
            bytes: Vec::with_capacity(total * STEP_BYTES),
        });
        let mut snap = StatusSnapshot::idle();
        snap.state = SatRunState::SatLoading;
        snap.schedule_id = msg.schedule_id;
        vec![
            protocol::encode_sat_ack(msg.schedule_id, BEGIN_ACK_SEQ, SatAckResult::SatAckOk, 0),
            snap.encode(),
        ]
    }

    pub fn handle_chunk(&mut self, msg: &SatScheduleChunk) -> Vec<Vec<u8>> {
        let ack = |result, loaded| {
            vec![protocol::encode_sat_ack(msg.schedule_id, msg.seq, result, loaded)]
        };
        let Some(loading) = self.loading.as_mut() else {
            return ack(SatAckResult::SatAckUnknownId, 0);
        };
        if loading.header.id != msg.schedule_id {
            return ack(SatAckResult::SatAckUnknownId, 0);
        }
        if msg.seq != loading.expected_seq {
            warn!("SAT_CHUNK: bad seq {} (expected {})", msg.seq, loading.expected_seq);
            self.loading = None;
            return ack(SatAckResult::SatAckBadSeq, 0);
        }
        if msg.steps.is_empty() || !msg.steps.len().is_multiple_of(STEP_BYTES) {
            self.loading = None;
            return ack(SatAckResult::SatAckBadData, 0);
        }
        let loaded = (loading.bytes.len() + msg.steps.len()) / STEP_BYTES;
        if loaded > loading.total_steps {
            self.loading = None;
            return ack(SatAckResult::SatAckOverflow, 0);
        }
        loading.bytes.extend_from_slice(&msg.steps);
        loading.expected_seq += 1;

        if loaded < loading.total_steps {
            return ack(SatAckResult::SatAckOk, loaded as u32);
        }

        // Final chunk: unpack and commit.
        let loading = self.loading.take().unwrap();
        match unpack_steps(loading.header.start, &loading.bytes) {
            Ok(steps) => {
                info!("SAT schedule {} committed: {} steps", loading.header.id, steps.len());
                self.schedule = Some(Arc::new(Schedule { header: loading.header, steps }));
                let mut frames = ack(SatAckResult::SatAckOk, loaded as u32);
                frames.push(self.status_frame());
                frames
            }
            Err(err) => {
                warn!("SAT schedule unpack failed: {err:?}");
                ack(SatAckResult::SatAckBadData, 0)
            }
        }
    }

    pub fn handle_start(
        &mut self,
        msg: &SatStart,
        usb: &'static UsbHost,
        radio_ready: bool,
        event_tx: &Sender<BridgeEvent>,
    ) -> Vec<Vec<u8>> {
        let error_status = |schedule_id: u32, detail: &str| {
            let mut snap = StatusSnapshot::idle();
            snap.state = SatRunState::SatError;
            snap.schedule_id = schedule_id;
            snap.detail = detail.into();
            vec![snap.encode()]
        };

        let Some(schedule) = self.schedule.clone() else {
            return error_status(msg.schedule_id, "no schedule loaded");
        };
        if schedule.header.id != msg.schedule_id {
            return error_status(msg.schedule_id, "schedule id mismatch");
        }
        if self.run_active() {
            return error_status(msg.schedule_id, "pass already armed");
        }
        if !radio_ready {
            return error_status(msg.schedule_id, "no radio");
        }

        info!(
            "SAT_START: id={} aos_in={}ms elapsed={}ms",
            msg.schedule_id, msg.aos_in_ms, msg.elapsed_ms
        );
        let stop = Arc::new(AtomicBool::new(false));
        let shared = Arc::new(Mutex::new(StatusSnapshot {
            state: SatRunState::SatArmed,
            schedule_id: schedule.header.id,
            step_index: 0,
            downlink_hz: schedule.header.start.downlink_hz,
            uplink_hz: schedule.header.start.uplink_hz,
            t_ms: -(msg.aos_in_ms as i64),
            detail: String::new(),
        }));
        self.run = Some(RunHandle { stop: stop.clone(), shared: shared.clone() });

        let aos_in_ms = msg.aos_in_ms;
        let elapsed_ms = msg.elapsed_ms;
        let tx = event_tx.clone();
        std::thread::Builder::new()
            .stack_size(8192)
            .name("sat-exec".into())
            .spawn(move || {
                run_pass(&schedule, aos_in_ms, elapsed_ms, usb, &stop, &shared, &tx);
            })
            .ok();
        // The thread pushes ARMED itself once radio setup succeeds.
        Vec::new()
    }

    pub fn handle_abort(&mut self) -> Vec<Vec<u8>> {
        if let Some(run) = self.run.take() {
            run.stop.store(true, Ordering::Release);
            info!("SAT_ABORT");
        }
        let mut snap = StatusSnapshot::idle();
        if let Some(ref schedule) = self.schedule {
            snap.schedule_id = schedule.header.id;
            snap.detail = "aborted".into();
        }
        vec![snap.encode()]
    }

    pub fn handle_set_vfo(&self, msg: &SatSetActiveVfo, usb: &UsbHost, usb_connected: bool) {
        if !usb_connected {
            warn!("SAT_SET_VFO ignored: no USB radio");
            return;
        }
        let cmd: &[u8] = if msg.vfo == 1 { b"FR1;" } else { b"FR0;" };
        let cat = CatSession::open(usb, SAT_RADIO);
        cat.send(cmd);
        info!("SAT_SET_VFO -> {}", if msg.vfo == 1 { "uplink (B)" } else { "downlink (A)" });
    }
}

// ---------------------------------------------------------------
// Executor
// ---------------------------------------------------------------

fn push_status(
    shared: &Arc<Mutex<StatusSnapshot>>,
    event_tx: &Sender<BridgeEvent>,
    update: impl FnOnce(&mut StatusSnapshot),
) {
    let frame = {
        let mut snap = shared.lock().unwrap();
        update(&mut snap);
        snap.encode()
    };
    let _ = event_tx.send(BridgeEvent::BleSend(frame));
}

/// `MD` digit for a UniversalMode value — the K1 CAT fork accepts the
/// standard Kenwood digits for the modes it supports (2=USB, 4=FM, 5=AM).
fn mode_digit(universal: u32) -> Option<u8> {
    match universal {
        2 => Some(b'2'),
        4 => Some(b'4'),
        5 => Some(b'5'),
        _ => None,
    }
}

fn freq_cmd(vfo: u8, hz: u64) -> Vec<u8> {
    format!("F{}{:011};", if vfo == 0 { 'A' } else { 'B' }, hz).into_bytes()
}

/// Configure the radio for the pass. Tone and mode apply only to the ACTIVE
/// VFO on the K1 fork, so we flip to B (uplink), configure it, then land on
/// A (downlink) configured — the operator starts listening.
fn setup_radio(cat: &CatSession, header: &Header) -> bool {
    let mut ok = true;
    let mut send = |cmd: &[u8]| {
        ok &= cat.send(cmd);
        rtos::delay_ticks(CAT_GAP_MS);
    };

    let has_uplink = header.start.uplink_hz > 0;
    if has_uplink {
        send(b"FR1;");
        if let Some(digit) = mode_digit(header.uplink_mode) {
            send(&[b'M', b'D', digit, b';']);
        }
        if header.uplink_tone_dhz > 0 {
            send(format!("CT{:04};", header.uplink_tone_dhz.min(9999)).into_bytes().as_slice());
        } else {
            send(b"OF;");
        }
        send(freq_cmd(1, header.start.uplink_hz).as_slice());
    }

    send(b"FR0;");
    if let Some(digit) = mode_digit(header.downlink_mode) {
        send(&[b'M', b'D', digit, b';']);
    }
    send(b"OF;");
    send(freq_cmd(0, header.start.downlink_hz).as_slice());
    ok
}

/// Is the radio currently transmitting? Parses the `IF` response — byte 30
/// (0-based, right before the terminator) is '1' during TX. An empty or
/// malformed response counts as not transmitting (fail-open: a dead radio
/// shouldn't wedge the executor; the actual send will surface the error).
fn tx_active(cat: &CatSession) -> bool {
    let rsp = cat.query(b"IF;", 300);
    let Some(start) = rsp.windows(2).position(|w| w == b"IF") else {
        return false;
    };
    rsp.get(start + 30) == Some(&b'1')
}

fn run_pass(
    schedule: &Arc<Schedule>,
    aos_in_ms: u64,
    start_elapsed_ms: u64,
    usb: &'static UsbHost,
    stop: &Arc<AtomicBool>,
    shared: &Arc<Mutex<StatusSnapshot>>,
    event_tx: &Sender<BridgeEvent>,
) {
    let header = &schedule.header;

    // 1. Radio setup.
    let setup_ok = {
        let cat = CatSession::open(usb, SAT_RADIO);
        setup_radio(&cat, header)
    };
    if !setup_ok {
        warn!("SAT setup failed — aborting pass");
        push_status(shared, event_tx, |snap| {
            snap.state = SatRunState::SatError;
            snap.detail = "radio setup failed".into();
        });
        return;
    }
    info!("SAT armed: {} (AOS in {} ms)", header.sat_name, aos_in_ms);
    push_status(shared, event_tx, |snap| {
        snap.state = SatRunState::SatArmed;
        snap.t_ms = -(aos_in_ms as i64);
    });

    // 2. Countdown to AOS.
    let mut remaining = aos_in_ms;
    let mut next_push = remaining.saturating_sub(COUNTDOWN_PUSH_MS);
    while remaining > 0 {
        if stop.load(Ordering::Acquire) {
            return;
        }
        let sleep = remaining.min(1_000);
        rtos::delay_ticks(sleep as u32);
        remaining -= sleep;
        if remaining <= next_push {
            next_push = remaining.saturating_sub(COUNTDOWN_PUSH_MS);
            push_status(shared, event_tx, |snap| snap.t_ms = -(remaining as i64));
        }
    }

    // 3. Execute the step table.
    info!("SAT pass running: {}", header.sat_name);
    push_status(shared, event_tx, |snap| {
        snap.state = SatRunState::SatRunning;
        snap.t_ms = start_elapsed_ms as i64;
    });

    let steps = &schedule.steps;
    let mut cursor = Cursor::new();
    cursor.seek(steps, start_elapsed_ms);
    let t0 = rtos::tick_count();
    let mut last_down: u64 = header.start.downlink_hz;
    let mut last_up: u64 = header.start.uplink_hz;

    loop {
        if stop.load(Ordering::Acquire) {
            return;
        }
        let elapsed = start_elapsed_ms + rtos::tick_count().wrapping_sub(t0) as u64;

        if cursor.finished(steps) {
            if elapsed >= header.duration_ms {
                break;
            }
            rtos::delay_ticks((header.duration_ms - elapsed).min(1_000) as u32);
            continue;
        }

        let due_in = cursor.next_due_in(steps, elapsed).unwrap_or(0);
        if due_in > 0 {
            rtos::delay_ticks(due_in.min(1_000) as u32);
            continue;
        }

        // A step is due. TX guard first — never retune mid-transmission.
        // The cursor is only advanced after the guard passes, so held-back
        // steps coalesce to the latest values once the operator unkeys.
        let mut write_ok = true;
        {
            let cat = CatSession::open(usb, SAT_RADIO);
            if tx_active(&cat) {
                drop(cat);
                push_status(shared, event_tx, |snap| {
                    snap.t_ms = elapsed as i64;
                    snap.detail = "tx hold".into();
                });
                rtos::delay_ticks(TX_HOLD_MS);
                continue;
            }
            let Some(step) = cursor.due(steps, elapsed) else {
                continue;
            };
            if step.uplink_hz > 0 && step.uplink_hz != last_up {
                write_ok &= cat.send(freq_cmd(1, step.uplink_hz).as_slice());
                rtos::delay_ticks(CAT_GAP_MS);
                last_up = step.uplink_hz;
            }
            if step.downlink_hz != last_down {
                write_ok &= cat.send(freq_cmd(0, step.downlink_hz).as_slice());
                last_down = step.downlink_hz;
            }
        }

        if !write_ok {
            warn!("SAT retune failed — radio lost?");
            push_status(shared, event_tx, |snap| {
                snap.state = SatRunState::SatError;
                snap.detail = "retune failed".into();
            });
            return;
        }

        let index = cursor.next_index() as u32;
        push_status(shared, event_tx, |snap| {
            snap.step_index = index;
            snap.downlink_hz = last_down;
            snap.uplink_hz = last_up;
            snap.t_ms = elapsed as i64;
            snap.detail.clear();
        });
    }

    info!("SAT pass complete: {}", header.sat_name);
    push_status(shared, event_tx, |snap| {
        snap.state = SatRunState::SatDone;
        snap.t_ms = header.duration_ms as i64;
    });
}
