// NimBLE's C API requires mutable statics for GATT service registration.
// These are only written once during init before any concurrent access.
#![allow(static_mut_refs)]

//! CW Bridge: BLE-to-USB Radio CAT Bridge
//!
//! Bridges BLE (Nordic UART Service) to USB serial for wireless CAT
//! control of amateur radios from Carrier Wave on iOS/macOS.
//!
//! Uses protobuf (CWBP v2) for structured messaging over BLE NUS.
//!
//! Data flow:
//!   Phone  ->  protobuf CatData  ->  BLE NUS RX  ->  raw USB TX  ->  Radio
//!   Radio  ->  raw USB RX  ->  protobuf CatData  ->  BLE NUS TX  ->  Phone

use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use esp_idf_hal::i2c::{I2cConfig, I2cDriver};
use esp_idf_hal::peripherals::Peripherals;
use esp_idf_hal::units::Hertz;
use esp_idf_sys as _;
use log::{error, info, warn};

mod audio;
mod ble;
mod board;
mod buttons;
mod detect;
mod display;
mod encoder;
mod expander;
mod ft8;
mod generated;
mod i2c_bus;
mod keyer;
mod protocol;
mod rtos;
mod usb;
mod verify;

use display::{DisplayState, DisplayView, MenuItem, MENU_ITEMS};
use expander::{Expander, Led};
use generated::cwbp::bridge_message::Msg;
use i2c_bus::SharedI2c;
use protocol::{Ft8State, RadioProtocol, SetResultCode, SetVerifyField, StatusCode};

/// WPM range enforced at the UI; individual CAT encoders clamp further.
const MIN_WPM: u32 = 5;
const MAX_WPM: u32 = 50;
/// Hold the post-rotate WPM arrow hint on-screen for this many ticks (ms).
const WPM_OVERLAY_TICKS: u32 = 1_500;

/// Minimum spacing between encoder-driven CAT writes (FreeRTOS ticks ≈ ms).
/// Keeps a fast spin from flooding the radio — Yaesu DSP clicks under rapid
/// CAT and the link has little headroom. The shadow value updates every
/// detent; only the on-wire write is throttled.
const ENCODER_CAT_MIN_TICKS: u32 = 50;

/// AF-gain change per encoder detent (0..=255 scale).
const AF_GAIN_STEP: i32 = 4;

/// What the rotary encoder adjusts on the Home screen. Encoder *press* cycles
/// through these; *rotate* changes the active one. WPM is bridge-local (the
/// keyer); AF gain is a CAT parameter sent to the radio.
#[derive(Clone, Copy, PartialEq, Eq)]
enum EncoderTarget {
    Wpm,
    AfGain,
}

impl EncoderTarget {
    fn next(self) -> Self {
        match self {
            Self::Wpm => Self::AfGain,
            Self::AfGain => Self::Wpm,
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Wpm => "WPM",
            Self::AfGain => "AF gain",
        }
    }
}

/// Events flowing from peripherals to the main loop.
pub enum BridgeEvent {
    BleConnected,
    BleDisconnected,
    BleData(Vec<u8>),
    /// Outbound BLE data from background threads (verify results, CW progress)
    BleSend(Vec<u8>),
    /// `Some(passkey)` while SMP is waiting for the user to enter the 6-digit
    /// code; `None` once pairing completes (success or failure) or the peer
    /// disconnects. Drives the OLED pairing prompt.
    BlePairingPasskey(Option<u32>),
    UsbConnected {
        vid: u16,
        pid: u16,
    },
    UsbDisconnected,
    UsbData(Vec<u8>),
    /// Radio auto-detection completed successfully
    DetectComplete(detect::DetectResult),
    /// Radio auto-detection failed
    DetectFailed,
    /// FT8 transmit finished; bridge is idle again.
    Ft8TxComplete,
    /// Rotary encoder rotated (+/- detents; positive = clockwise).
    EncoderRotate(i32),
    /// Encoder button pressed and released in < 1 s.
    EncoderPress,
    /// Encoder button held for ≥ 1 s, then released.
    EncoderLongPress,
    /// Front-panel button pressed and released in < 1 s.
    ButtonPress(u8),
    /// Front-panel button held for ≥ 1 s. Fires once at the threshold,
    /// while still held. The release does not also emit `ButtonPress`.
    ButtonLongPress(u8),
    /// A button-triggered CW memory finished keying; clears the TX flag.
    CwMemoryComplete,
}

/// Bridge state maintained in the main loop.
struct BridgeState {
    usb_connected: bool,
    ble_connected: bool,
    ble_subscribed: bool,
    radio_detecting: bool,
    detect_result: Option<detect::DetectResult>,
    detected_proto: RadioProtocol,
    civ_address: u8,
    is_yaesu: bool,
    /// Tick count of last USB CAT send (for inter-command spacing).
    /// TODO: use for inter-command pacing once timing is tuned.
    #[allow(dead_code)]
    last_cat_send_tick: u32,
    has_verify_result: bool,
    last_verify_ok: bool,
    keyer: keyer::CwEngine,
    cw_sending: bool,
    ft8_transmitting: bool,
    /// FT8 audio-in capture task. `None` when idle.
    ft8_capture: Option<Ft8Capture>,
    /// Current on-screen view.
    display_view: DisplayView,
    /// Selected row index while `display_view == Menu`.
    menu_selection: usize,
    /// Tick count at which the post-rotate WPM hint should disappear.
    /// `0` means "no overlay active".
    wpm_overlay_until: u32,
    /// USB device ids cached at connect time (for the diagnostics screen).
    usb_vid: u16,
    usb_pid: u16,
    /// Baud rate reported by radio detection.
    baud_rate: u32,
    /// `Some(code)` while a pairing passkey is waiting to be entered on the
    /// iOS/macOS side. Renders a full-screen prompt over the normal views.
    pairing_passkey: Option<u32>,
    /// Outcome of the most recent `detect::detect()` call. `None` until the
    /// first attempt finishes, then `Some(true)` for success / `Some(false)`
    /// for `DetectFailed`. Persists across USB-disconnect for diagnosis.
    last_detect_ok: Option<bool>,
    /// FreeRTOS tick at which the next telemetry refresh (RSSI, bond count)
    /// is due.
    next_telemetry_tick: u32,
    /// Cached RSSI reading for the Health view; refreshed on the same
    /// schedule as the telemetry refresh.
    last_rssi_dbm: Option<i8>,
    /// Cached NVS bond count for the Health view; refreshed lazily.
    nvs_bond_count: u32,
    /// Which parameter the rotary encoder adjusts on the Home screen.
    encoder_target: EncoderTarget,
    /// Bridge-side shadow of the radio's AF gain (0..=255). Seeded to mid and
    /// owned by the encoder — the radio's front panel can drift it, but the
    /// knob writes absolute values from here.
    af_gain: u8,
}

impl Default for BridgeState {
    fn default() -> Self {
        Self {
            usb_connected: false,
            ble_connected: false,
            ble_subscribed: false,
            radio_detecting: false,
            detect_result: None,
            detected_proto: RadioProtocol::Unknown,
            civ_address: 0,
            is_yaesu: false,
            last_cat_send_tick: 0,
            has_verify_result: false,
            last_verify_ok: false,
            keyer: keyer::CwEngine::new(),
            cw_sending: false,
            ft8_transmitting: false,
            ft8_capture: None,
            display_view: DisplayView::Home,
            menu_selection: 0,
            wpm_overlay_until: 0,
            usb_vid: 0,
            usb_pid: 0,
            baud_rate: 0,
            pairing_passkey: None,
            last_detect_ok: None,
            next_telemetry_tick: 0,
            last_rssi_dbm: None,
            nvs_bond_count: 0,
            encoder_target: EncoderTarget::Wpm,
            af_gain: 128,
        }
    }
}

impl BridgeState {
    /// Big-readout text for the Home screen, reflecting the active encoder
    /// target (e.g. `"22 WPM"` or `"AF 128"`).
    fn encoder_readout(&self) -> String {
        match self.encoder_target {
            EncoderTarget::Wpm => format!("{} WPM", self.keyer.wpm),
            EncoderTarget::AfGain => format!("AF {}", self.af_gain),
        }
    }
}

/// Cadence for the periodic RSSI / bond-count refresh. The controller-side
/// RSSI is a rolling average, so 10 s is plenty.
const TELEMETRY_INTERVAL_TICKS: u32 = 10_000;

/// Half-period of the status-LED blink (ms).
const LED_BLINK_TICKS: u32 = 500;

/// Drive the BT and USB status LEDs (on-board D9/D10 + panel header J12)
/// from bridge state. BT: blinking = advertising / searching, solid = a
/// phone or Mac is connected. USB: blinking = a device is attached but not
/// yet identified, solid = radio detected, off = nothing on the host port.
/// `set_led` is a no-op when unchanged, so this is cheap every iteration.
fn update_status_leds(expander: &Mutex<Expander>, state: &BridgeState, now: u32) {
    let blink_phase = (now / LED_BLINK_TICKS).is_multiple_of(2);
    let bt_on = state.ble_connected || blink_phase;
    let usb_on = state.usb_connected && (state.detect_result.is_some() || blink_phase);
    if let Ok(mut exp) = expander.lock() {
        if let Err(err) = exp.set_led(Led::Bluetooth, bt_on) {
            warn!("LED update failed: {err:?}");
            return;
        }
        let _ = exp.set_led(Led::Usb, usb_on);
    }
}

/// Snapshot the ESP-IDF heap allocator: `(current_free, low_watermark)`
/// in bytes. Used by the Health view; cheap (no syscall, just a sum).
fn heap_snapshot() -> (u32, u32) {
    // SAFETY: these are read-only accessors documented to be safe from any
    // task context. They return `size_t` which we widen to u32 (heap is
    // bounded by SoC SRAM + PSRAM ≪ 4 GiB).
    unsafe {
        (
            esp_idf_sys::esp_get_free_heap_size(),
            esp_idf_sys::esp_get_minimum_free_heap_size(),
        )
    }
}

/// Handle to the running FT8 capture/decode pipeline.
struct Ft8Capture {
    stop: audio::CaptureStop,
}

impl Ft8Capture {
    fn stop(self) {
        self.stop.stop();
    }
}

/// BLE congestion control
struct BleSender {
    backoff_until: u32,
}

impl BleSender {
    fn new() -> Self {
        Self { backoff_until: 0 }
    }

    fn send(&mut self, ble_dev: &ble::Ble, data: &[u8]) {
        if !ble_dev.subscribed() {
            // Two reasons we land here:
            //   1. No client connected at all.
            //   2. Client is connected and writing to us but hasn't yet
            //      finished CCCD subscribe (or link not yet encrypted) —
            //      so notifies would be rejected. iOS races subscribe vs
            //      first write, so this is normal during handshake.
            // Either way, dropping silently is correct; we don't queue.
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
            return; // In backoff period
        }
        self.backoff_until = 0;

        // Send in chunks of 240 bytes
        let max_chunk = protocol::MAX_BLE_PAYLOAD;
        let mut offset = 0;
        while offset < data.len() {
            let chunk_end = (offset + max_chunk).min(data.len());
            match ble_dev.send(&data[offset..chunk_end]) {
                Ok(()) => offset = chunk_end,
                Err(e) => {
                    warn!("BLE notify failed ({e}), backing off 100ms");
                    // configTICK_RATE_HZ = 1000, so 1 tick = 1 ms
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
}

/// Push the bridge's current cached state to the client. Called from both
/// the handshake handler and the client-driven `StatusReq` interrogation
/// path so the two stay in sync.
fn send_state_dump(ble_dev: &ble::Ble, state: &BridgeState, ble_tx: &mut BleSender) {
    if state.usb_connected {
        ble_tx.send_status(ble_dev, StatusCode::UsbConnected);
        if let Some(ref result) = state.detect_result {
            let frame =
                protocol::encode_radio_info(result.protocol, result.baud_rate, &result.id_string);
            ble_tx.send(ble_dev, &frame);
            ble_tx.send_status(ble_dev, StatusCode::Ready);
        }
    } else {
        ble_tx.send_status(ble_dev, StatusCode::UsbDisconnected);
    }
}

fn main() {
    // Initialize ESP-IDF
    esp_idf_svc::sys::link_patches();
    esp_idf_svc::log::EspLogger::initialize_default();

    info!("=== CW Bridge {} ===", protocol::FW_VERSION);

    let (event_tx, event_rx) = mpsc::channel::<BridgeEvent>();

    // Initialize BLE
    info!("Initializing BLE (NUS)...");
    let ble_dev = unsafe { ble::Ble::init(event_tx.clone()) };

    // Shared I²C bus first: the OLED, the PCAL6416A expander and the ES8388
    // codec all hang off it. Bring the OLED up *before* USB host so its I2C
    // transactions complete before USB enumeration draws a current spike on
    // VBUS — plugging an FT-X1 (CP210x) at boot was sagging 3V3 enough to
    // NACK the SSD1306 mid-init and panic the whole bridge.
    info!(
        "Initializing I2C bus (SDA=GPIO{}, SCL=GPIO{}) + OLED display...",
        board::PIN_I2C_SDA,
        board::PIN_I2C_SCL
    );
    let peripherals = unsafe { Peripherals::steal() };
    let i2c_cfg = I2cConfig::new().baudrate(Hertz(400_000));
    let i2c_bus = match I2cDriver::new(
        peripherals.i2c0,
        peripherals.pins.gpio5,
        peripherals.pins.gpio6,
        &i2c_cfg,
    ) {
        Ok(driver) => Some(SharedI2c::new(driver)),
        Err(err) => {
            error!("I2C bus init failed: {err} — OLED, buttons and audio disabled");
            None
        }
    };
    let mut oled = i2c_bus
        .as_ref()
        .and_then(|bus| display::Display::init(bus.clone()));

    // I/O expander: front-panel buttons, encoder switch, status LEDs.
    info!("Initializing I/O expander...");
    let expander: Option<Arc<Mutex<Expander>>> = i2c_bus.as_ref().and_then(|bus| {
        match Expander::init(bus.clone(), peripherals.pins.gpio44) {
            Ok(exp) => Some(Arc::new(Mutex::new(exp))),
            Err(err) => {
                warn!("Expander init failed: {err:?} (buttons + status LEDs disabled)");
                None
            }
        }
    });

    // Initialize USB host — leaked to 'static so it can be shared across threads
    info!("Initializing USB host...");
    let usb_dev: &'static usb::UsbHost =
        Box::leak(Box::new(unsafe { usb::UsbHost::init(event_tx.clone()) }));

    // Rotary encoder phases on native GPIO: rotate = WPM / AF gain.
    info!("Spawning encoder task...");
    encoder::spawn(
        peripherals.pins.gpio1,
        peripherals.pins.gpio2,
        event_tx.clone(),
    );

    // Front-panel push buttons + encoder switch, polled through the expander.
    if let Some(exp) = expander.clone() {
        info!("Spawning buttons task...");
        buttons::spawn(exp, event_tx.clone());
    }

    // FT8 audio: ES8388 codec over I2C + I2S0 full duplex. Capture reads the
    // codec ADC on demand when the app requests it.
    info!("Initializing FT8 audio (ES8388 codec)...");
    let audio_init = i2c_bus.as_ref().and_then(|bus| {
        match audio::AudioOut::init(
            peripherals.i2s0,
            peripherals.pins.gpio43,
            peripherals.pins.gpio39,
            peripherals.pins.gpio40,
            peripherals.pins.gpio42,
            peripherals.pins.gpio3,
            bus,
        ) {
            Ok(out) => Some(out),
            Err(err) => {
                warn!("Audio init failed: {err:?} (FT8 TX/RX disabled)");
                None
            }
        }
    });
    let audio_out: &'static Mutex<Option<audio::AudioOut>> =
        Box::leak(Box::new(Mutex::new(audio_init)));

    let mut state = BridgeState::default();
    let mut ble_tx = BleSender::new();

    // Seed default CW memory slots for the encoder/button POC if the operator
    // hasn't programmed them over BLE yet. `set_slot` persists to NVS, so this
    // only writes on first boot (or after an NVS erase) — app-set text wins.
    if state.keyer.slot_text(1).is_none() {
        let _ = state.keyer.set_slot(1, "CQ CQ DE N9HO N9HO K");
    }
    if state.keyer.slot_text(2).is_none() {
        let _ = state.keyer.set_slot(2, "TU 73 DE N9HO");
    }

    info!("Bridge running. Connect via BLE to \"CW Bridge\"");

    // Main event loop
    loop {
        match event_rx.recv_timeout(Duration::from_millis(500)) {
            Ok(event) => {
                handle_event(
                    event,
                    &ble_dev,
                    usb_dev,
                    audio_out,
                    &mut state,
                    &mut ble_tx,
                    &event_tx,
                );
                // Drain all queued events before updating display to prevent channel backlog
                while let Ok(event) = event_rx.try_recv() {
                    handle_event(
                        event,
                        &ble_dev,
                        usb_dev,
                        audio_out,
                        &mut state,
                        &mut ble_tx,
                        &event_tx,
                    );
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                error!("Event channel disconnected");
                break;
            }
        }

        // Periodic telemetry: BLE RSSI + bond count for the Health view.
        let now = rtos::tick_count();
        if (now.wrapping_sub(state.next_telemetry_tick) as i32) >= 0 {
            state.next_telemetry_tick = now.wrapping_add(TELEMETRY_INTERVAL_TICKS);
            state.last_rssi_dbm = ble_dev.rssi();
            state.nvs_bond_count = ble_dev.bond_count();
        }

        // Status LEDs on the expander (mirrored to the panel header J12).
        if let Some(exp) = expander.as_ref() {
            update_status_leds(exp, &state, now);
        }

        // Update display
        let overlay_active =
            state.wpm_overlay_until != 0 && (state.wpm_overlay_until as i32 - now as i32) > 0;
        if !overlay_active {
            state.wpm_overlay_until = 0;
        }
        let (free_heap, min_free_heap) = heap_snapshot();
        let ds = DisplayState {
            usb_connected: state.usb_connected,
            ble_connected: state.ble_connected,
            ble_subscribed: state.ble_subscribed,
            radio_detecting: state.radio_detecting,
            radio_detected: state.detect_result.is_some(),
            radio_id: state.detect_result.as_ref().map(|r| r.id_string.clone()),
            radio_name: state
                .detect_result
                .as_ref()
                .and_then(|r| r.radio_name().map(String::from)),
            has_verify_result: state.has_verify_result,
            last_verify_ok: state.last_verify_ok,
            // No jack-detect switches on the rev 2 board.
            mic_plugged: false,
            phone_plugged: false,
            wpm: state.keyer.wpm,
            encoder_readout: state.encoder_readout(),
            cw_sending: state.cw_sending,
            view: state.display_view,
            menu_selection: state.menu_selection,
            wpm_overlay_active: overlay_active,
            uptime_secs: now / 1000,
            usb_vid: state.usb_vid,
            usb_pid: state.usb_pid,
            baud_rate: state.baud_rate,
            rssi_dbm: state.last_rssi_dbm,
            free_heap_bytes: free_heap,
            min_free_heap_bytes: min_free_heap,
            nvs_bond_count: state.nvs_bond_count,
            last_detect_ok: state.last_detect_ok,
            // No VBAT sense on the rev 2 board.
            battery_mv: 0,
            battery_pct: 0,
            battery_present: false,
            pairing_passkey: state.pairing_passkey,
        };
        if let Some(o) = oled.as_mut() {
            o.update(&ds);
        }
    }
}

// ---------------------------------------------------------------
// Encoder gesture handlers
// ---------------------------------------------------------------

fn handle_encoder_rotate(
    detents: i32,
    usb_dev: &'static usb::UsbHost,
    ble_dev: &ble::Ble,
    ble_tx: &mut BleSender,
    state: &mut BridgeState,
) {
    match state.display_view {
        DisplayView::Home => match state.encoder_target {
            EncoderTarget::Wpm => {
                let current = state.keyer.wpm as i32;
                let target = (current + detents).clamp(MIN_WPM as i32, MAX_WPM as i32) as u32;
                if target != state.keyer.wpm {
                    state.keyer.set_speed(
                        target,
                        usb_dev,
                        state.detected_proto,
                        state.civ_address,
                        state.is_yaesu,
                    );
                    let frame = protocol::encode_cw_speed(target);
                    ble_tx.send(ble_dev, &frame);
                }
                state.wpm_overlay_until = rtos::tick_count().wrapping_add(WPM_OVERLAY_TICKS);
            }
            EncoderTarget::AfGain => {
                let target = (state.af_gain as i32 + detents * AF_GAIN_STEP).clamp(0, 255) as u8;
                if target != state.af_gain {
                    state.af_gain = target;
                    // Throttle the on-wire write; the shadow is always current.
                    let now = rtos::tick_count();
                    if state.usb_connected
                        && now.wrapping_sub(state.last_cat_send_tick) >= ENCODER_CAT_MIN_TICKS
                    {
                        state.last_cat_send_tick = now;
                        // Kenwood/Yaesu AF gain: "AG0nnn;" (0 = main RX, 000..255).
                        let cmd = format!("AG0{target:03};");
                        let _ = usb_dev.send(cmd.as_bytes());
                    }
                }
                state.wpm_overlay_until = rtos::tick_count().wrapping_add(WPM_OVERLAY_TICKS);
            }
        },
        DisplayView::Menu => {
            let len = MENU_ITEMS.len() as i32;
            let new_idx = ((state.menu_selection as i32 + detents).rem_euclid(len)) as usize;
            state.menu_selection = new_idx;
        }
        DisplayView::Diagnostics | DisplayView::Health | DisplayView::About => {
            // Rotation has no effect on read-only screens.
        }
    }
}

fn handle_encoder_press(state: &mut BridgeState) {
    match state.display_view {
        DisplayView::Home => {
            // Short press on Home cycles which parameter the knob adjusts
            // (WPM ↔ AF gain). Long-press still opens the menu.
            state.encoder_target = state.encoder_target.next();
            info!("Encoder target -> {}", state.encoder_target.label());
            state.wpm_overlay_until = rtos::tick_count().wrapping_add(WPM_OVERLAY_TICKS);
        }
        DisplayView::Menu => {
            let Some(item) = MENU_ITEMS.get(state.menu_selection) else {
                state.display_view = DisplayView::Home;
                return;
            };
            match item {
                MenuItem::Diagnostics => state.display_view = DisplayView::Diagnostics,
                MenuItem::Health => state.display_view = DisplayView::Health,
                MenuItem::About => state.display_view = DisplayView::About,
                MenuItem::Back => {
                    state.display_view = DisplayView::Home;
                    state.menu_selection = 0;
                }
            }
        }
        DisplayView::Diagnostics | DisplayView::Health | DisplayView::About => {
            state.display_view = DisplayView::Menu;
        }
    }
}

fn handle_encoder_long_press(state: &mut BridgeState) {
    match state.display_view {
        DisplayView::Home => {
            state.display_view = DisplayView::Menu;
            state.menu_selection = 0;
        }
        DisplayView::Menu => {
            state.display_view = DisplayView::Home;
            state.menu_selection = 0;
        }
        DisplayView::Diagnostics | DisplayView::Health | DisplayView::About => {
            state.display_view = DisplayView::Home;
        }
    }
}

/// Key CW memory `slot` (1-based) on a worker thread so the multi-second
/// transmission never blocks the event loop. Mirrors the BLE `CwSend` path
/// but pulls the message text from the keyer's NVS-backed slot. Emits
/// `CwMemoryComplete` when done so the main loop clears the TX flag.
fn play_cw_memory(
    slot: u32,
    usb_dev: &'static usb::UsbHost,
    event_tx: &mpsc::Sender<BridgeEvent>,
    state: &mut BridgeState,
) {
    if !state.usb_connected {
        warn!("CW memory {slot} ignored: no USB radio connected");
        return;
    }
    if state.cw_sending {
        warn!("CW memory {slot} ignored: already sending");
        return;
    }
    let Some(template) = state.keyer.slot_text(slot) else {
        info!("CW memory slot {slot} is empty — nothing to send");
        return;
    };
    let text = keyer::expand_template(&template, &std::collections::HashMap::new());
    let proto = state.detected_proto;
    let civ_addr = state.civ_address;
    let is_yaesu = state.is_yaesu;
    let no_tb_poll = is_yaesu
        || state
            .detect_result
            .as_ref()
            .map(|r| r.qrp_variant == detect::QrpLabsVariant::Qmx)
            .unwrap_or(false);
    let wpm = state.keyer.wpm;
    let usb_ref = usb_dev;
    let tx = event_tx.clone();
    state.cw_sending = true;
    info!("Playing CW memory {slot}: {text:?}");

    std::thread::Builder::new()
        .stack_size(8192)
        .name("cw-memory".into())
        .spawn(move || {
            let mut engine = keyer::CwEngine::lightweight(wpm);
            let _ = engine.send(
                &text,
                usb_ref,
                proto,
                civ_addr,
                no_tb_poll,
                is_yaesu,
                |depth, flags| {
                    let frame = protocol::encode_cw_progress(depth, flags);
                    let _ = tx.send(BridgeEvent::BleSend(frame));
                },
            );
            let _ = tx.send(BridgeEvent::CwMemoryComplete);
        })
        .ok();
}

fn handle_event(
    event: BridgeEvent,
    ble_dev: &ble::Ble,
    usb_dev: &'static usb::UsbHost,
    audio_out: &'static Mutex<Option<audio::AudioOut>>,
    state: &mut BridgeState,
    ble_tx: &mut BleSender,
    event_tx: &mpsc::Sender<BridgeEvent>,
) {
    match event {
        BridgeEvent::BleConnected => {
            state.ble_connected = true;
            state.ble_subscribed = true;
        }

        BridgeEvent::BleDisconnected => {
            state.ble_connected = false;
            state.ble_subscribed = false;
        }

        BridgeEvent::BleData(data) => {
            handle_ble_data(&data, ble_dev, usb_dev, audio_out, state, ble_tx, event_tx);
        }

        BridgeEvent::Ft8TxComplete => {
            state.ft8_transmitting = false;
            let frame = protocol::encode_ft8_status(Ft8State::Idle, None);
            ble_tx.send(ble_dev, &frame);
        }

        BridgeEvent::BleSend(data) => {
            ble_tx.send(ble_dev, &data);
        }

        BridgeEvent::BlePairingPasskey(code) => {
            state.pairing_passkey = code;
        }

        BridgeEvent::UsbConnected { vid, pid } => {
            info!("USB device connected: VID=0x{vid:04X} PID=0x{pid:04X}");
            state.usb_connected = true;
            state.usb_vid = vid;
            state.usb_pid = pid;
            ble_tx.send_status(ble_dev, StatusCode::UsbConnected);

            // Start auto-detection on a background thread
            state.radio_detecting = true;
            ble_tx.send_status(ble_dev, StatusCode::Detecting);

            let tx = event_tx.clone();
            let usb_ref = usb_dev;
            std::thread::Builder::new()
                .stack_size(4096)
                .spawn(move || match detect::detect(usb_ref, vid, pid) {
                    Some(result) => {
                        let _ = tx.send(BridgeEvent::DetectComplete(result));
                    }
                    None => {
                        let _ = tx.send(BridgeEvent::DetectFailed);
                    }
                })
                .ok();
        }

        BridgeEvent::DetectComplete(result) => {
            state.radio_detecting = false;
            state.last_detect_ok = Some(true);
            state.detected_proto = result.protocol;
            state.civ_address = result.civ_address.unwrap_or(0);
            state.is_yaesu = result.freq_digits == 9;
            state.baud_rate = result.baud_rate;

            let frame =
                protocol::encode_radio_info(result.protocol, result.baud_rate, &result.id_string);
            ble_tx.send(ble_dev, &frame);
            ble_tx.send_status(ble_dev, StatusCode::Ready);

            // Yaesu init: disable auto-info, set CAT timeout to 100ms
            if state.is_yaesu {
                let _ = usb_dev.send(b"AI0;");
                rtos::delay_ticks(50);
                let _ = usb_dev.send(b"EX05071;");
                rtos::delay_ticks(50);
                info!("Yaesu init: AI0, CAT TOT=100ms");
            }

            state.detect_result = Some(result);
        }

        BridgeEvent::DetectFailed => {
            state.radio_detecting = false;
            state.last_detect_ok = Some(false);
            ble_tx.send_status(ble_dev, StatusCode::DetectionFailed);
        }

        BridgeEvent::UsbDisconnected => {
            info!("USB device disconnected");
            state.usb_connected = false;
            state.radio_detecting = false;
            state.detect_result = None;
            state.detected_proto = RadioProtocol::Unknown;
            state.civ_address = 0;
            state.usb_vid = 0;
            state.usb_pid = 0;
            state.baud_rate = 0;
            ble_tx.send_status(ble_dev, StatusCode::UsbDisconnected);
        }

        BridgeEvent::EncoderRotate(detents) => {
            handle_encoder_rotate(detents, usb_dev, ble_dev, ble_tx, state);
        }

        BridgeEvent::EncoderPress => {
            handle_encoder_press(state);
        }

        BridgeEvent::EncoderLongPress => {
            handle_encoder_long_press(state);
        }

        BridgeEvent::ButtonPress(idx) => {
            info!("Button {} pressed", idx + 1);
            // BTN3 short press dismisses the Health overlay. BTN1/BTN2 play
            // CW memory slots 1/2 from the Home screen.
            if idx == 2 && state.display_view == DisplayView::Health {
                state.display_view = DisplayView::Home;
            } else if matches!(idx, 0 | 1) && state.display_view == DisplayView::Home {
                play_cw_memory(idx as u32 + 1, usb_dev, event_tx, state);
            }
        }

        BridgeEvent::ButtonLongPress(idx) => {
            info!("Button {} long-press", idx + 1);
            if idx == 2 {
                // BTN3 long-press: toggle the Health view from anywhere —
                // a hardware shortcut that bypasses the menu.
                state.display_view = if state.display_view == DisplayView::Health {
                    DisplayView::Home
                } else {
                    DisplayView::Health
                };
            } else if state.cw_sending {
                // BTN1/BTN2 long-press: abort an in-flight CW memory.
                if state.usb_connected {
                    state.keyer.stop(
                        usb_dev,
                        state.detected_proto,
                        state.civ_address,
                        state.is_yaesu,
                    );
                }
                state.cw_sending = false;
            }
        }

        BridgeEvent::CwMemoryComplete => {
            state.cw_sending = false;
        }

        BridgeEvent::UsbData(data) => {
            // Wrap CAT data in protobuf and send to phone
            let frame = protocol::encode_cat_data(&data);
            ble_tx.send(ble_dev, &frame);
        }
    }
}

fn handle_ble_data(
    data: &[u8],
    ble_dev: &ble::Ble,
    usb_dev: &'static usb::UsbHost,
    audio_out: &'static Mutex<Option<audio::AudioOut>>,
    state: &mut BridgeState,
    ble_tx: &mut BleSender,
    event_tx: &mpsc::Sender<BridgeEvent>,
) {
    // Decode protobuf message
    let msg = match protocol::decode(data) {
        Some(msg) => msg,
        None => {
            // Not valid protobuf — forward as raw CAT (only if USB attached).
            if state.usb_connected {
                let _ = usb_dev.send(data);
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
            // Client is interrogating the bridge for current state — re-emit
            // the same dump as the handshake handler. Used by the apps as a
            // self-heal poll so a missed/raced status push doesn't leave the
            // app stuck thinking USB is disconnected.
            info!("Client requested status dump");
            send_state_dump(ble_dev, state, ble_tx);
        }

        Some(Msg::CatData(cat)) => {
            // Drop CAT writes when no USB radio is attached. The iOS session
            // does periodic state polling (MD;/FA;/SM;/etc.) and that traffic
            // would otherwise hammer `usb_dev.send` with "not connected"
            // failures every poll interval.
            if !state.usb_connected {
                return;
            }
            if let Err(err) = usb_dev.send(&cat.payload) {
                warn!("USB send failed: {err}");
            }
        }

        Some(Msg::RequestDetect(_)) => {
            info!("Client requested radio re-detection");
            if let Some((vid, pid)) = usb_dev.device_ids() {
                state.radio_detecting = true;
                ble_tx.send_status(ble_dev, StatusCode::Detecting);

                let tx = event_tx.clone();
                let usb_ref = usb_dev;
                std::thread::Builder::new()
                    .stack_size(4096)
                    .spawn(move || match detect::detect(usb_ref, vid, pid) {
                        Some(result) => {
                            let _ = tx.send(BridgeEvent::DetectComplete(result));
                        }
                        None => {
                            let _ = tx.send(BridgeEvent::DetectFailed);
                        }
                    })
                    .ok();
            } else {
                ble_tx.send_status(ble_dev, StatusCode::UsbDisconnected);
            }
        }

        Some(Msg::SetBaud(baud_msg)) => {
            info!("Client set baud: {}", baud_msg.baud_rate);
            let _ = usb_dev.set_baud(baud_msg.baud_rate);
        }

        Some(Msg::SetVerify(sv)) => {
            let field = SetVerifyField::try_from(sv.field).unwrap_or(SetVerifyField::Unknown);

            if state.radio_detecting {
                warn!("SET_VERIFY rejected (detecting)");
                let frame = protocol::encode_set_result(SetResultCode::Fail);
                ble_tx.send(ble_dev, &frame);
                return;
            }

            if state.detect_result.is_none() {
                warn!("SET_VERIFY rejected (no radio)");
                let frame = protocol::encode_set_result(SetResultCode::Fail);
                ble_tx.send(ble_dev, &frame);
                return;
            }

            info!("SET_VERIFY: field={}", field.as_str_name());

            let proto = state.detected_proto;
            let civ_addr = state.civ_address;
            let qrp_variant = state
                .detect_result
                .as_ref()
                .map(|r| r.qrp_variant)
                .unwrap_or_default();
            let freq_digits = state
                .detect_result
                .as_ref()
                .map(|r| r.freq_digits)
                .unwrap_or(11);
            let value = sv.value.clone();
            let usb_ref = usb_dev;
            let tx = event_tx.clone();

            std::thread::Builder::new()
                .stack_size(4096)
                .spawn(move || {
                    let result = verify::verify(
                        usb_ref,
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

        Some(Msg::CwSend(msg)) => {
            info!("CW_SEND: {}", msg.text);
            // Refuse keying if no USB radio is attached. Without a CAT link
            // there's nothing to key — sending into the void confuses the
            // operator and wastes the buffer-depth tracking on the app side.
            if !state.usb_connected {
                warn!("CW_SEND rejected: no USB radio connected");
                let ack = protocol::encode_cw_ack(protocol::CwAckResult::Fail, 0);
                ble_tx.send(ble_dev, &ack);
                ble_tx.send_status(ble_dev, StatusCode::UsbDisconnected);
                return;
            }
            let proto = state.detected_proto;
            let civ_addr = state.civ_address;
            let is_yaesu = state.is_yaesu;
            let no_tb_poll = is_yaesu
                || state
                    .detect_result
                    .as_ref()
                    .map(|r| r.qrp_variant == detect::QrpLabsVariant::Qmx)
                    .unwrap_or(false);
            let usb_ref = usb_dev;
            let wpm = state.keyer.wpm;
            let tx = event_tx.clone();
            state.cw_sending = true;

            // ACK immediately
            let ack = protocol::encode_cw_ack(protocol::CwAckResult::Ok, msg.text.len() as u32);
            ble_tx.send(ble_dev, &ack);

            std::thread::Builder::new()
                .stack_size(8192)
                .spawn(move || {
                    let mut engine = keyer::CwEngine::lightweight(wpm);
                    let _result = engine.send(
                        &msg.text,
                        usb_ref,
                        proto,
                        civ_addr,
                        no_tb_poll,
                        is_yaesu,
                        |depth, flags| {
                            let frame = protocol::encode_cw_progress(depth, flags);
                            let _ = tx.send(BridgeEvent::BleSend(frame));
                        },
                    );
                })
                .ok();
        }

        Some(Msg::CwStop(_)) => {
            info!("CW_STOP");
            // Skip the radio CAT command if no USB radio is attached, but
            // still update internal state and ack the app.
            if state.usb_connected {
                state.keyer.stop(
                    usb_dev,
                    state.detected_proto,
                    state.civ_address,
                    state.is_yaesu,
                );
            }
            state.cw_sending = false;
            let frame = protocol::encode_cw_progress(0, keyer::FLAG_COMPLETE);
            ble_tx.send(ble_dev, &frame);
        }

        Some(Msg::CwSpeed(msg)) => {
            info!("CW_SPEED: {} WPM", msg.wpm);
            // Update internal WPM bookkeeping even with no radio attached
            // so the value persists for when one is plugged in. Only push
            // it to the radio over USB when the link is actually up.
            state.keyer.wpm = msg.wpm;
            if state.usb_connected {
                state.keyer.set_speed(
                    msg.wpm,
                    usb_dev,
                    state.detected_proto,
                    state.civ_address,
                    state.is_yaesu,
                );
            }
        }

        Some(Msg::CwSlotPlay(msg)) => {
            info!("CW_SLOT_PLAY: slot={} ctx={}", msg.slot, msg.context.len());

            // Refuse keying if no USB radio is attached.
            if !state.usb_connected {
                warn!("CW_SLOT_PLAY rejected: no USB radio connected");
                let ack = protocol::encode_cw_ack(protocol::CwAckResult::Fail, 0);
                ble_tx.send(ble_dev, &ack);
                ble_tx.send_status(ble_dev, StatusCode::UsbDisconnected);
                return;
            }

            // Validate slot and expand template on main thread
            let slot_idx = msg.slot as usize;
            if !(1..=keyer::MAX_SLOTS).contains(&slot_idx) {
                let ack = protocol::encode_cw_ack(protocol::CwAckResult::BadSlot, 0);
                ble_tx.send(ble_dev, &ack);
            } else {
                let template = state.keyer.slots[slot_idx - 1].text.clone();
                let expanded = keyer::expand_template(&template, &msg.context);
                info!("Playing slot {}: {:?}", msg.slot, expanded);

                // ACK immediately, send on background thread (like CW_SEND)
                let ack = protocol::encode_cw_ack(protocol::CwAckResult::Ok, expanded.len() as u32);
                ble_tx.send(ble_dev, &ack);

                let proto = state.detected_proto;
                let civ_addr = state.civ_address;
                let is_yaesu = state.is_yaesu;
                let no_tb_poll = is_yaesu
                    || state
                        .detect_result
                        .as_ref()
                        .map(|r| r.qrp_variant == detect::QrpLabsVariant::Qmx)
                        .unwrap_or(false);
                let usb_ref = usb_dev;
                let wpm = state.keyer.wpm;
                let tx = event_tx.clone();
                state.cw_sending = true;

                std::thread::Builder::new()
                    .stack_size(8192)
                    .spawn(move || {
                        let mut engine = keyer::CwEngine::lightweight(wpm);
                        let _result = engine.send(
                            &expanded,
                            usb_ref,
                            proto,
                            civ_addr,
                            no_tb_poll,
                            is_yaesu,
                            |depth, flags| {
                                let frame = protocol::encode_cw_progress(depth, flags);
                                let _ = tx.send(BridgeEvent::BleSend(frame));
                            },
                        );
                    })
                    .ok();
            }
        }

        Some(Msg::CwSlotSet(msg)) => {
            info!("CW_SLOT_SET: slot={} text=\"{}\"", msg.slot, msg.text);
            let result = state.keyer.set_slot(msg.slot, &msg.text);
            let ack = protocol::encode_cw_ack(
                protocol::CwAckResult::try_from(result as i32)
                    .unwrap_or(protocol::CwAckResult::Fail),
                0,
            );
            ble_tx.send(ble_dev, &ack);
        }

        Some(Msg::CwStatusReq(_)) => {
            info!("CW_STATUS_REQ");
            let (wpm, depth, flags, slots) = state.keyer.get_status();
            let frame = protocol::encode_cw_status_rsp(wpm, depth, flags, slots);
            ble_tx.send(ble_dev, &frame);
        }

        Some(Msg::Ft8EncodeReq(req)) => {
            info!("FT8_ENCODE_REQ: {:?}", req.text);
            match ft8::encode_message(&req.text) {
                Ok(tones) => {
                    let frame = protocol::encode_ft8_encode_rsp_ok(&tones);
                    ble_tx.send(ble_dev, &frame);
                }
                Err(err) => {
                    let detail = format!("{err:?}");
                    warn!("FT8 encode failed: {detail}");
                    let frame = protocol::encode_ft8_encode_rsp_err(&detail);
                    ble_tx.send(ble_dev, &frame);
                }
            }
        }

        Some(Msg::Ft8Send(req)) => {
            if state.ft8_transmitting {
                warn!("FT8_SEND rejected (already transmitting)");
                let frame = protocol::encode_ft8_status(Ft8State::Error, Some("busy"));
                ble_tx.send(ble_dev, &frame);
                return;
            }
            let base_freq = if req.base_freq_hz == 0 {
                1500
            } else {
                req.base_freq_hz
            };
            info!("FT8_SEND: {:?} @ {} Hz", req.text, base_freq);
            match ft8::encode_message(&req.text) {
                Ok(tones) => {
                    state.ft8_transmitting = true;
                    let frame = protocol::encode_ft8_status(Ft8State::Transmitting, None);
                    ble_tx.send(ble_dev, &frame);

                    let tx = event_tx.clone();
                    let out_handle = audio_out;
                    std::thread::Builder::new()
                        .stack_size(6144)
                        .name("ft8-tx".into())
                        .spawn(move || {
                            let pcm = ft8::synthesize_tones(&tones, base_freq as f32);
                            if let Ok(mut guard) = out_handle.lock() {
                                if let Some(out) = guard.as_mut() {
                                    if let Err(err) = out.write_pcm(&pcm) {
                                        warn!("FT8 TX I2S write failed: {err:?}");
                                    }
                                    // Flush silence so the radio's last audio frame drops cleanly.
                                    let _ = out.mute();
                                } else {
                                    warn!("FT8 TX skipped — audio output unavailable");
                                }
                            }
                            let _ = tx.send(BridgeEvent::Ft8TxComplete);
                        })
                        .ok();
                }
                Err(err) => {
                    let detail = format!("{err:?}");
                    warn!("FT8 encode for send failed: {detail}");
                    let frame = protocol::encode_ft8_status(Ft8State::Error, Some(&detail));
                    ble_tx.send(ble_dev, &frame);
                }
            }
        }

        Some(Msg::Ft8CapStart(req)) => {
            if state.ft8_capture.is_some() {
                info!("FT8_CAP_START ignored (already capturing)");
                return;
            }
            let min_hz = if req.min_freq_hz == 0 {
                100
            } else {
                req.min_freq_hz
            };
            let max_hz = if req.max_freq_hz == 0 {
                3000
            } else {
                req.max_freq_hz
            };
            info!("FT8_CAP_START: {} Hz .. {} Hz", min_hz, max_hz);

            let handle = audio_out
                .lock()
                .ok()
                .and_then(|guard| guard.as_ref().map(|out| out.capture_handle()));
            let Some(handle) = handle else {
                let detail = "audio codec unavailable".to_string();
                warn!("FT8_CAP_START failed: {detail}");
                let frame = protocol::encode_ft8_status(Ft8State::Error, Some(&detail));
                ble_tx.send(ble_dev, &frame);
                return;
            };
            match audio::start_capture(handle) {
                Ok((stop, rx)) => {
                    let ble_send_tx = event_tx.clone();
                    let stop_for_task = stop.clone();
                    std::thread::Builder::new()
                        .stack_size(16 * 1024)
                        .name("ft8-decode".into())
                        .spawn(move || {
                            ft8_decode_loop(min_hz, max_hz, rx, stop_for_task, ble_send_tx);
                        })
                        .ok();
                    state.ft8_capture = Some(Ft8Capture { stop });
                    let frame = protocol::encode_ft8_status(Ft8State::Capturing, None);
                    ble_tx.send(ble_dev, &frame);
                }
                Err(err) => {
                    let detail = format!("capture start failed: {err:?}");
                    warn!("FT8_CAP_START failed: {detail}");
                    let frame = protocol::encode_ft8_status(Ft8State::Error, Some(&detail));
                    ble_tx.send(ble_dev, &frame);
                }
            }
        }

        Some(Msg::Ft8CapStop(_)) => {
            if let Some(cap) = state.ft8_capture.take() {
                info!("FT8_CAP_STOP");
                cap.stop();
                let frame = protocol::encode_ft8_status(Ft8State::Idle, None);
                ble_tx.send(ble_dev, &frame);
            }
        }

        Some(Msg::HandshakeRsp(_))
        | Some(Msg::Status(_))
        | Some(Msg::RadioInfo(_))
        | Some(Msg::SetResult(_))
        | Some(Msg::CwAck(_))
        | Some(Msg::CwProgress(_))
        | Some(Msg::CwStatusRsp(_))
        | Some(Msg::Ft8EncodeRsp(_))
        | Some(Msg::Ft8Decode(_))
        | Some(Msg::Ft8Status(_))
        | Some(Msg::JackStatus(_))
        | Some(Msg::BatteryStatus(_)) => {
            // These are bridge->client messages, ignore if received from client
        }

        None => {
            warn!("Empty protobuf message");
        }
    }
}

/// Background task: feed ADC chunks into the FT8 decoder, emit decoded
/// messages over BLE, exit when the stop handle fires.
///
/// Each FT8 slot is 15 s of audio. We accumulate samples up to one slot, run
/// `decode` at the boundary, then reset for the next slot. The slot clock is
/// not aligned to wall time — the app is expected to start capture a few
/// seconds before its own slot boundary and filter by `delta_time_s`.
fn ft8_decode_loop(
    min_hz: u32,
    max_hz: u32,
    rx: mpsc::Receiver<audio::CaptureChunk>,
    stop: audio::CaptureStop,
    tx: mpsc::Sender<BridgeEvent>,
) {
    let mut decoder = match ft8::Decoder::new(min_hz as f32, max_hz as f32) {
        Ok(dec) => dec,
        Err(err) => {
            warn!("FT8 decoder init failed: {err:?}");
            let detail = format!("{err:?}");
            let frame = protocol::encode_ft8_status(Ft8State::Error, Some(&detail));
            let _ = tx.send(BridgeEvent::BleSend(frame));
            return;
        }
    };

    let mut samples_in_slot: usize = 0;
    while stop.is_running() {
        let chunk = match rx.recv_timeout(Duration::from_millis(500)) {
            Ok(chunk) => chunk,
            Err(mpsc::RecvTimeoutError::Timeout) => continue,
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        };
        samples_in_slot += chunk.samples.len();
        decoder.feed(&chunk.samples);

        if samples_in_slot >= audio::FT8_SLOT_SAMPLES {
            for result in decoder.decode() {
                let frame = protocol::encode_ft8_decode(
                    &result.text,
                    result.snr_db,
                    result.frequency_hz,
                    result.delta_time_s,
                );
                if tx.send(BridgeEvent::BleSend(frame)).is_err() {
                    return;
                }
            }
            // Re-init decoder for the next slot; monitor_free/init drops the waterfall.
            decoder = match ft8::Decoder::new(min_hz as f32, max_hz as f32) {
                Ok(dec) => dec,
                Err(err) => {
                    warn!("FT8 decoder re-init failed: {err:?}");
                    break;
                }
            };
            samples_in_slot = 0;
        }
    }
    info!("FT8 decode loop exiting");
}
