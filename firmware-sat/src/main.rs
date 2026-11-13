// NimBLE's C API requires mutable statics for GATT service registration.
// These are only written once during init before any concurrent access.
#![allow(static_mut_refs)]

//! CW Sat Bridge: satellite doppler CAT executor for ESP32-P4.
//!
//! Headless variant of the CW Bridge focused on satellite passes with the
//! Quansheng UV-K1/K5 CAT firmware: the app uploads a precomputed doppler
//! schedule over BLE (protobuf/NUS, same CWBP protocol), the bridge executes
//! it against the radio over USB serial on its own clock — the phone can
//! disconnect mid-pass.
//!
//! Data flow:
//!   Phone  ->  protobuf SatSchedule*/SatStart  ->  sat executor  ->  CAT FA/FB
//!   Phone  ->  protobuf CatData  ->  raw USB TX  ->  Radio (passthrough)
//!   Radio  ->  raw USB RX  ->  protobuf CatData  ->  BLE NUS TX  ->  Phone

use std::sync::mpsc;
use std::time::Duration;

use esp_idf_sys as _;
use log::{error, info, warn};

mod ble;
mod detect;
#[cfg(feature = "fs-spike")]
mod fs_spike;
mod generated;
mod protocol;
mod rtos;
mod sat;
#[cfg(feature = "freq-selftest")]
mod selftest;
mod usb;
mod verify;

use generated::cwbp::bridge_message::Msg;
use protocol::{RadioProtocol, SetResultCode, SetVerifyField, StatusCode};

/// The sat doppler executor + CatData passthrough + SetVerify all target
/// this radio slot. Detection runs on every slot so the frequency self-test
/// can drive all connected radios.
const PRIMARY_RADIO: usize = 0;

/// Events flowing from peripherals to the main loop.
pub enum BridgeEvent {
    BleConnected,
    BleDisconnected,
    BleData(Vec<u8>),
    /// Outbound BLE data from background threads (verify results, sat status)
    BleSend(Vec<u8>),
    /// Unused on this headless board (SM is disabled), but ble.rs emits it.
    BlePairingPasskey(Option<u32>),
    UsbConnected {
        radio: usize,
        vid: u16,
        pid: u16,
    },
    UsbDisconnected {
        radio: usize,
    },
    UsbData {
        radio: usize,
        data: Vec<u8>,
    },
    DetectComplete {
        radio: usize,
        result: detect::DetectResult,
    },
    DetectFailed {
        radio: usize,
    },
}

/// Per-radio slot state.
struct RadioState {
    connected: bool,
    detecting: bool,
    detect_result: Option<detect::DetectResult>,
    detected_proto: RadioProtocol,
    civ_address: u8,
}

impl Default for RadioState {
    fn default() -> Self {
        Self {
            connected: false,
            detecting: false,
            detect_result: None,
            detected_proto: RadioProtocol::ProtoUnknown,
            civ_address: 0,
        }
    }
}

/// Bridge state maintained in the main loop.
struct BridgeState {
    radios: [RadioState; usb::MAX_RADIOS],
    sat: sat::SatManager,
}

impl Default for BridgeState {
    fn default() -> Self {
        Self {
            radios: [RadioState::default(), RadioState::default()],
            sat: sat::SatManager::new(),
        }
    }
}

impl BridgeState {
    /// The sat executor needs a detected Kenwood-protocol radio on the
    /// primary slot (the UV-K1 CAT fork detects as Kenwood via the IF probe).
    fn sat_radio_ready(&self) -> bool {
        let radio = &self.radios[PRIMARY_RADIO];
        radio.connected
            && !radio.detecting
            && radio.detected_proto == RadioProtocol::ProtoKenwood
    }
}

/// BLE congestion control (same policy as the S3 bridge).
struct BleSender {
    backoff_until: u32,
}

impl BleSender {
    fn new() -> Self {
        Self { backoff_until: 0 }
    }

    fn send(&mut self, ble_dev: &ble::Ble, data: &[u8]) {
        if !ble_dev.subscribed() {
            // No client, or CCCD subscribe hasn't landed yet (iOS races
            // subscribe vs first write during handshake). Dropping silently
            // is correct — we don't queue.
            warn!(
                "BLE TX dropped — not subscribed (conn={}, sub={}, enc={})",
                ble_dev.connected(),
                ble_dev.tx_subscribed_for_log(),
                ble_dev.link_encrypted_for_log(),
            );
            return;
        }

        let now = rtos::tick_count();
        if self.backoff_until > 0 && (self.backoff_until as i32 - now as i32) > 0 {
            return;
        }
        self.backoff_until = 0;

        let max_chunk = protocol::MAX_BLE_PAYLOAD;
        let mut offset = 0;
        while offset < data.len() {
            let chunk_end = (offset + max_chunk).min(data.len());
            match ble_dev.send(&data[offset..chunk_end]) {
                Ok(()) => offset = chunk_end,
                Err(e) => {
                    warn!("BLE notify failed ({e}), backing off 100ms");
                    self.backoff_until = now + 100;
                    break;
                }
            }
        }
    }

    fn send_status(&mut self, ble_dev: &ble::Ble, code: StatusCode) {
        let frame = protocol::encode_status(code, None);
        self.send(ble_dev, &frame);
    }

    fn send_all(&mut self, ble_dev: &ble::Ble, frames: Vec<Vec<u8>>) {
        for frame in frames {
            self.send(ble_dev, &frame);
        }
    }
}

/// Push the bridge's current cached state to the client (handshake and
/// StatusReq paths).
fn send_state_dump(ble_dev: &ble::Ble, state: &BridgeState, ble_tx: &mut BleSender) {
    // The BLE-facing status mirrors the primary radio (the app controls one
    // radio today); the self-test drives every connected radio separately.
    let primary = &state.radios[PRIMARY_RADIO];
    if primary.connected {
        ble_tx.send_status(ble_dev, StatusCode::StatusUsbConnected);
        if let Some(ref result) = primary.detect_result {
            let frame =
                protocol::encode_radio_info(result.protocol, result.baud_rate, &result.id_string);
            ble_tx.send(ble_dev, &frame);
            ble_tx.send_status(ble_dev, StatusCode::StatusReady);
        }
    } else {
        ble_tx.send_status(ble_dev, StatusCode::StatusUsbDisconnected);
    }
    let sat_frame = state.sat.status_frame();
    ble_tx.send(ble_dev, &sat_frame);
}

// `fs_spike::run()` diverges, making the rest of main unreachable when the
// spike feature is on; harmless allow (unused when the feature is off).
#[allow(unreachable_code)]
fn main() {
    esp_idf_svc::sys::link_patches();
    esp_idf_svc::log::EspLogger::initialize_default();

    info!("=== CW Sat Bridge {} ===", protocol::FW_VERSION);

    // Dual-host spike runs standalone: no BLE, no HS USB host — just the FS
    // controller bring-up, to isolate it and avoid AHB-DMA contention.
    #[cfg(feature = "fs-spike")]
    fs_spike::run();

    let (event_tx, event_rx) = mpsc::channel::<BridgeEvent>();

    info!("Initializing BLE (NUS)...");
    let ble_dev = unsafe { ble::Ble::init(event_tx.clone()) };

    info!("Initializing USB host...");
    let usb_dev: &'static usb::UsbHost =
        Box::leak(Box::new(unsafe { usb::UsbHost::init(event_tx.clone()) }));

    let mut state = BridgeState::default();
    let mut ble_tx = BleSender::new();

    // Bring-up self-test: a background poller that sweeps every connected
    // radio's frequency (radio 0 up on 2m, radio 1 down on 70cm) once they
    // appear, logging readbacks to serial. Feature-gated — not a normal build.
    #[cfg(feature = "freq-selftest")]
    {
        let usb_ref = usb_dev;
        std::thread::Builder::new()
            .stack_size(8192)
            .name("freq-selftest".into())
            .spawn(move || selftest::run_loop(usb_ref))
            .ok();
    }

    info!("Sat bridge running. Connect via BLE to \"CW Sat Bridge\"");

    loop {
        match event_rx.recv_timeout(Duration::from_millis(500)) {
            Ok(event) => {
                handle_event(event, &ble_dev, usb_dev, &mut state, &mut ble_tx, &event_tx);
                while let Ok(event) = event_rx.try_recv() {
                    handle_event(event, &ble_dev, usb_dev, &mut state, &mut ble_tx, &event_tx);
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                error!("Event channel disconnected");
                break;
            }
        }
    }
}

fn spawn_detect(
    radio: usize,
    vid: u16,
    pid: u16,
    usb_dev: &'static usb::UsbHost,
    event_tx: &mpsc::Sender<BridgeEvent>,
) {
    let tx = event_tx.clone();
    std::thread::Builder::new()
        .stack_size(4096)
        .spawn(move || match detect::detect(usb_dev, radio, vid, pid) {
            Some(result) => {
                let _ = tx.send(BridgeEvent::DetectComplete { radio, result });
            }
            None => {
                let _ = tx.send(BridgeEvent::DetectFailed { radio });
            }
        })
        .ok();
}

fn handle_event(
    event: BridgeEvent,
    ble_dev: &ble::Ble,
    usb_dev: &'static usb::UsbHost,
    state: &mut BridgeState,
    ble_tx: &mut BleSender,
    event_tx: &mpsc::Sender<BridgeEvent>,
) {
    match event {
        BridgeEvent::BleConnected | BridgeEvent::BleDisconnected => {
            // The sat executor is deliberately BLE-independent; nothing to do.
        }

        BridgeEvent::BlePairingPasskey(_) => {}

        BridgeEvent::BleData(data) => {
            handle_ble_data(&data, ble_dev, usb_dev, state, ble_tx, event_tx);
        }

        BridgeEvent::BleSend(data) => {
            ble_tx.send(ble_dev, &data);
        }

        BridgeEvent::UsbConnected { radio, vid, pid } => {
            info!("USB radio {radio} connected: VID=0x{vid:04X} PID=0x{pid:04X}");
            if radio < usb::MAX_RADIOS {
                state.radios[radio].connected = true;
                state.radios[radio].detecting = true;
            }
            if radio == PRIMARY_RADIO {
                ble_tx.send_status(ble_dev, StatusCode::StatusUsbConnected);
                ble_tx.send_status(ble_dev, StatusCode::StatusDetecting);
            }
            spawn_detect(radio, vid, pid, usb_dev, event_tx);
        }

        BridgeEvent::DetectComplete { radio, result } => {
            if radio < usb::MAX_RADIOS {
                let slot = &mut state.radios[radio];
                slot.detecting = false;
                slot.detected_proto = result.protocol;
                slot.civ_address = result.civ_address.unwrap_or(0);
                slot.detect_result = Some(result.clone());
            }
            if radio == PRIMARY_RADIO {
                let frame = protocol::encode_radio_info(
                    result.protocol,
                    result.baud_rate,
                    &result.id_string,
                );
                ble_tx.send(ble_dev, &frame);
                ble_tx.send_status(ble_dev, StatusCode::StatusReady);
            }
        }

        BridgeEvent::DetectFailed { radio } => {
            if radio < usb::MAX_RADIOS {
                state.radios[radio].detecting = false;
            }
            if radio == PRIMARY_RADIO {
                ble_tx.send_status(ble_dev, StatusCode::StatusDetectionFailed);
            }
        }

        BridgeEvent::UsbDisconnected { radio } => {
            info!("USB radio {radio} disconnected");
            if radio < usb::MAX_RADIOS {
                state.radios[radio] = RadioState::default();
            }
            if radio == PRIMARY_RADIO {
                ble_tx.send_status(ble_dev, StatusCode::StatusUsbDisconnected);
                // A running pass can't continue without the primary radio.
                let frames = state.sat.handle_abort();
                ble_tx.send_all(ble_dev, frames);
            }
        }

        BridgeEvent::UsbData { radio, data } => {
            // Only the primary radio's traffic is bridged to the app.
            if radio == PRIMARY_RADIO {
                let frame = protocol::encode_cat_data(&data);
                ble_tx.send(ble_dev, &frame);
            }
        }
    }
}

fn handle_ble_data(
    data: &[u8],
    ble_dev: &ble::Ble,
    usb_dev: &'static usb::UsbHost,
    state: &mut BridgeState,
    ble_tx: &mut BleSender,
    event_tx: &mpsc::Sender<BridgeEvent>,
) {
    let msg = match protocol::decode(data) {
        Some(msg) => msg,
        None => {
            // Not valid protobuf — forward as raw CAT to the primary radio.
            if state.radios[PRIMARY_RADIO].connected {
                let _ = usb_dev.send(PRIMARY_RADIO, data);
            }
            return;
        }
    };

    match protocol::unwrap_msg(msg) {
        Some(Msg::HandshakeReq(req)) => {
            info!("Handshake from client (v{})", req.protocol_version);
            let rsp = protocol::encode_handshake_rsp();
            ble_tx.send(ble_dev, &rsp);
            send_state_dump(ble_dev, state, ble_tx);
        }

        Some(Msg::StatusReq(_)) => {
            info!("Client requested status dump");
            send_state_dump(ble_dev, state, ble_tx);
        }

        Some(Msg::CatData(cat)) => {
            if !state.radios[PRIMARY_RADIO].connected {
                return;
            }
            if let Err(err) = usb_dev.send(PRIMARY_RADIO, &cat.payload) {
                warn!("USB send failed: {err}");
            }
        }

        Some(Msg::RequestDetect(_)) => {
            info!("Client requested radio re-detection");
            if let Some((vid, pid)) = usb_dev.device_ids(PRIMARY_RADIO) {
                state.radios[PRIMARY_RADIO].detecting = true;
                ble_tx.send_status(ble_dev, StatusCode::StatusDetecting);
                spawn_detect(PRIMARY_RADIO, vid, pid, usb_dev, event_tx);
            } else {
                ble_tx.send_status(ble_dev, StatusCode::StatusUsbDisconnected);
            }
        }

        Some(Msg::SetBaud(baud_msg)) => {
            info!("Client set baud: {}", baud_msg.baud_rate);
            let _ = usb_dev.set_baud(PRIMARY_RADIO, baud_msg.baud_rate);
        }

        Some(Msg::SetVerify(sv)) => {
            let field = SetVerifyField::try_from(sv.field).unwrap_or(SetVerifyField::FieldUnknown);
            let primary = &state.radios[PRIMARY_RADIO];

            if primary.detecting || primary.detect_result.is_none() {
                warn!("SET_VERIFY rejected (detecting or no radio)");
                let frame = protocol::encode_set_result(SetResultCode::ResultFail);
                ble_tx.send(ble_dev, &frame);
                return;
            }

            info!("SET_VERIFY: field={}", field.as_str_name());

            let proto = primary.detected_proto;
            let civ_addr = primary.civ_address;
            let qrp_variant = primary
                .detect_result
                .as_ref()
                .map(|r| r.qrp_variant)
                .unwrap_or_default();
            let freq_digits = primary.detect_result.as_ref().map(|r| r.freq_digits).unwrap_or(11);
            let value = sv.value.clone();
            let tx = event_tx.clone();

            std::thread::Builder::new()
                .stack_size(4096)
                .spawn(move || {
                    let result = verify::verify(
                        usb_dev,
                        PRIMARY_RADIO,
                        field,
                        &value,
                        proto,
                        civ_addr,
                        qrp_variant,
                        freq_digits,
                    );
                    let frame = protocol::encode_set_result(result);
                    let _ = tx.send(BridgeEvent::BleSend(frame));
                })
                .ok();
        }

        // --- Satellite doppler schedule ---
        Some(Msg::SatBegin(begin)) => {
            let frames = state.sat.handle_begin(&begin);
            ble_tx.send_all(ble_dev, frames);
        }

        Some(Msg::SatChunk(chunk)) => {
            let frames = state.sat.handle_chunk(&chunk);
            ble_tx.send_all(ble_dev, frames);
        }

        Some(Msg::SatStart(start)) => {
            let radio_ready = state.sat_radio_ready();
            let frames = state.sat.handle_start(&start, usb_dev, radio_ready, event_tx);
            ble_tx.send_all(ble_dev, frames);
        }

        Some(Msg::SatAbort(_)) => {
            let frames = state.sat.handle_abort();
            ble_tx.send_all(ble_dev, frames);
        }

        Some(Msg::SatSetVfo(set_vfo)) => {
            let connected = state.radios[PRIMARY_RADIO].connected;
            state.sat.handle_set_vfo(&set_vfo, usb_dev, connected);
        }

        // Bridge -> client messages, or messages this firmware doesn't
        // implement (CW keyer, FT8): ignore.
        Some(_) => {}

        None => {
            warn!("Empty protobuf message");
        }
    }
}
