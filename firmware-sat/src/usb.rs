//! USB Host serial interface for radio CAT control — multi-radio.
//!
//! Uses the raw ESP-IDF USB Host Library directly (NOT the CDC-ACM driver)
//! to open USB-serial adapters (FTDI, CP210x, CH340) and native-USB CDC-ACM
//! radios (UV-K1). The CDC-ACM driver's bulk OUT transfers silently fail
//! with FTDI devices — see `docs/usb-host-investigation.md`.
//!
//! Up to `MAX_RADIOS` devices bind at once, each addressed by a radio index
//! (0, 1, …). A USB hub with two K1s hanging off it therefore drives both
//! radios independently — the full-duplex satellite case. Per-slot state
//! reachable from the C transfer callbacks (completion signals, RX capture,
//! is-FTDI, IN-paused) lives in fixed statics indexed by the slot number,
//! which each transfer carries in its `context` field as `idx + 1`.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Sender;
use std::sync::{Condvar, Mutex, OnceLock};
use std::time::Duration;

use ::log::{error, info, warn};
use esp_idf_sys::*;

use crate::BridgeEvent;

extern "C" {
    /// Bring up both P4 OTG PHYs in host mode (fs_host C component). Retained
    /// from the peripheral_map dual-root-port attempt; unused now that the FS
    /// controller is driven by the polled fs_host path. See `UsbHost::init`.
    #[allow(dead_code)]
    fn usb_host_phys_bringup() -> core::ffi::c_int;
}

/// Maximum simultaneously-bound CAT radios (two K1s on a hub = full duplex).
pub const MAX_RADIOS: usize = 2;

// Buffer sizes
const USB_RX_BUF_SIZE: usize = 512;
const USB_TX_BUF_SIZE: usize = 512;
const USB_CTRL_BUF_SIZE: usize = 256;

// Default serial parameters
const DEFAULT_BAUD_RATE: u32 = 38400;

// FTDI vendor request constants
const FTDI_REQTYPE_OUT: u8 = 0x40;
const FTDI_REQ_RESET: u8 = 0x00;
const FTDI_REQ_SET_MODEM: u8 = 0x01;
const FTDI_REQ_SET_FLOW: u8 = 0x02;
const FTDI_REQ_SET_BAUD: u8 = 0x03;
const FTDI_REQ_SET_DATA: u8 = 0x04;
const FTDI_REQ_SET_EVENT_CHR: u8 = 0x06;
const FTDI_REQ_SET_ERROR_CHR: u8 = 0x07;
const FTDI_REQ_SET_LATENCY: u8 = 0x09;

/// Supported USB-serial chip definitions.
struct ChipDef {
    vid: u16,
    pid: u16,
    name: &'static str,
    is_ftdi: bool,
}

const SUPPORTED_CHIPS: &[ChipDef] = &[
    ChipDef { vid: 0x0403, pid: 0x6015, name: "FTDI FT-X", is_ftdi: true },
    ChipDef { vid: 0x0403, pid: 0x6001, name: "FTDI FT232", is_ftdi: true },
    ChipDef { vid: 0x10C4, pid: 0xEA60, name: "CP2102", is_ftdi: false },
    ChipDef { vid: 0x10C4, pid: 0xEA70, name: "CP2105", is_ftdi: false },
    ChipDef { vid: 0x1A86, pid: 0x7523, name: "CH340", is_ftdi: false },
    // QRP Labs QMX/QMX+ — STM32 CDC-ACM virtual COM port.
    ChipDef { vid: 0x0483, pid: 0x5740, name: "STM32 CDC", is_ftdi: false },
    // Quansheng UV-K1 native USB-C (sugarfree90 CAT firmware) — composite
    // CDC-ACM, enumerates as 0x36B7:0xFFFF class 0xEF. CAT runs over the
    // data interface's bulk pair; baud is nominal (VCP).
    ChipDef { vid: 0x36B7, pid: 0xFFFF, name: "UV-K1 USB", is_ftdi: false },
];

fn match_chip(vid: u16, pid: u16) -> Option<&'static ChipDef> {
    SUPPORTED_CHIPS.iter().find(|c| c.vid == vid && c.pid == pid)
}

/// USB enumeration filter — runs early, before ESP-IDF spends HCD channels
/// fully enumerating the device.
///
/// # Safety
/// Called by the USB Host enumeration driver. `dev_desc` is a valid pointer
/// to a freshly-read device descriptor. `b_cfg_value` is a valid out-pointer.
unsafe extern "C" fn enum_filter_cb(
    dev_desc: *const usb_device_desc_t,
    b_cfg_value: *mut u8,
) -> bool {
    if dev_desc.is_null() {
        return false;
    }
    let desc = &*dev_desc;
    let class = desc.__bindgen_anon_1.bDeviceClass;
    let vid = desc.__bindgen_anon_1.idVendor;
    let pid = desc.__bindgen_anon_1.idProduct;

    if !b_cfg_value.is_null() {
        *b_cfg_value = 1;
    }

    // USB_CLASS_HUB == 0x09 — allow hubs so we can reach downstream CAT
    // chips. We refuse to claim hubs as serial devices below.
    if class == 0x09 {
        info!("Enum filter: allow hub (VID=0x{vid:04X} PID=0x{pid:04X})");
        return true;
    }

    if match_chip(vid, pid).is_some() {
        info!("Enum filter: allow CAT chip (VID=0x{vid:04X} PID=0x{pid:04X})");
        return true;
    }

    // CDC (0x02/0x0A) and composite devices (0x00 per-interface / 0xEF
    // Miscellaneous-IAD — the UV-K1's native USB-C CDC-ACM). Allow so a
    // matched chip / claimed CDC data interface can bind. Audio (0x01) /
    // HID (0x03) stay rejected to conserve HCD channels.
    if class == 0x02 || class == 0x0A || class == 0xEF || class == 0x00 {
        info!("Enum filter: allow CDC/composite (VID=0x{vid:04X} PID=0x{pid:04X} class=0x{class:02X})");
        return true;
    }

    info!(
        "Enum filter: skip (VID=0x{vid:04X} PID=0x{pid:04X} class=0x{class:02X}) — not a hub or supported CAT chip"
    );
    false
}

/// One bound device's handles. `client_hdl` is shared and lives in `UsbState`.
struct DeviceSlot {
    dev_hdl: usb_device_handle_t,
    in_xfer: *mut usb_transfer_t,
    out_xfer: *mut usb_transfer_t,
    ctrl_xfer: *mut usb_transfer_t,
    in_ep_addr: u8,
    out_ep_addr: u8,
    claimed_iface: u8,
    is_ftdi: bool,
    connected: bool,
    vid: u16,
    pid: u16,
}

impl DeviceSlot {
    const fn empty() -> Self {
        Self {
            dev_hdl: std::ptr::null_mut(),
            in_xfer: std::ptr::null_mut(),
            out_xfer: std::ptr::null_mut(),
            ctrl_xfer: std::ptr::null_mut(),
            in_ep_addr: 0,
            out_ep_addr: 0,
            claimed_iface: 0,
            is_ftdi: false,
            connected: false,
            vid: 0,
            pid: 0,
        }
    }
}

/// Internal state shared between USB tasks. Protected by a mutex.
struct UsbState {
    client_hdl: usb_host_client_handle_t,
    slots: [DeviceSlot; MAX_RADIOS],
}

// SAFETY: USB handles are used from specific tasks; the Mutex guards access.
unsafe impl Send for UsbState {}
unsafe impl Sync for UsbState {}

/// Completion signal for transfer callbacks.
struct CompletionSignal {
    mutex: Mutex<bool>,
    condvar: Condvar,
}

impl CompletionSignal {
    const fn new() -> Self {
        Self { mutex: Mutex::new(false), condvar: Condvar::new() }
    }

    fn clear(&self) {
        *self.mutex.lock().unwrap() = false;
    }

    fn signal(&self) {
        let mut done = self.mutex.lock().unwrap();
        *done = true;
        self.condvar.notify_one();
    }

    /// Wait for completion with a timeout in ms. True if signaled.
    fn wait_ms(&self, timeout_ms: u64) -> bool {
        let done = self.mutex.lock().unwrap();
        if *done {
            return true;
        }
        let (done, _) = self
            .condvar
            .wait_timeout(done, Duration::from_millis(timeout_ms))
            .unwrap();
        *done
    }
}

/// Per-slot OUT/CTRL completion signals (reachable from the C callbacks).
struct SlotSignals {
    out: CompletionSignal,
    ctrl: CompletionSignal,
}

impl SlotSignals {
    const fn new() -> Self {
        Self { out: CompletionSignal::new(), ctrl: CompletionSignal::new() }
    }
}

static SLOT_SIGNALS: [SlotSignals; MAX_RADIOS] = [SlotSignals::new(), SlotSignals::new()];

/// Per-slot RX routing: when `capture` is set (detection / CatSession),
/// inbound bytes accumulate in `buf` instead of being emitted as `UsbData`.
struct SlotRx {
    capture: AtomicBool,
    in_paused: AtomicBool,
    is_ftdi: AtomicBool,
    buf: Mutex<Vec<u8>>,
}

impl SlotRx {
    const fn new() -> Self {
        Self {
            capture: AtomicBool::new(false),
            in_paused: AtomicBool::new(false),
            is_ftdi: AtomicBool::new(false),
            buf: Mutex::new(Vec::new()),
        }
    }
}

static SLOT_RX: [SlotRx; MAX_RADIOS] = [SlotRx::new(), SlotRx::new()];

// Global sender for events back to the main loop (set once during init).
static EVENT_TX: OnceLock<Sender<BridgeEvent>> = OnceLock::new();

// Pending device addresses from the client callback. A queue because an
// internal hub enumerates several downstream devices back-to-back.
static PENDING_QUEUE: Mutex<VecDeque<u8>> = Mutex::new(VecDeque::new());

// True while a dev_setup thread is running (serializes enumeration setup).
static SETUP_IN_PROGRESS: AtomicBool = AtomicBool::new(false);

struct SetupInProgressGuard;
impl Drop for SetupInProgressGuard {
    fn drop(&mut self) {
        SETUP_IN_PROGRESS.store(false, Ordering::Release);
    }
}

/// Encode a slot index into a transfer's `context` (offset by 1 so slot 0
/// isn't a null pointer), and decode it back in the callbacks.
fn ctx_from_slot(idx: usize) -> *mut std::ffi::c_void {
    (idx + 1) as *mut std::ffi::c_void
}
fn slot_from_ctx(ctx: *mut std::ffi::c_void) -> usize {
    (ctx as usize).wrapping_sub(1)
}

/// Compute FTDI baud rate divisor (Linux ftdi_sio algorithm).
fn ftdi_baud_divisor(baud: u32) -> u16 {
    static DIVFRAC: [u8; 8] = [0, 3, 2, 4, 1, 5, 6, 7];
    let divisor3 = (48_000_000u32 + baud) / (2 * baud);
    let divisor = (divisor3 >> 3) as u16;
    let frac = DIVFRAC[(divisor3 & 0x7) as usize] as u16;
    let mut wvalue = divisor | (frac << 14);
    if wvalue == 1 {
        wvalue = 0;
    } else if wvalue == 0x4001 {
        wvalue = 1;
    }
    wvalue
}

/// USB host interface for radio serial communication.
pub struct UsbHost {
    state: &'static Mutex<UsbState>,
    tx_sem: &'static Mutex<()>,
    ctrl_sem: &'static Mutex<()>,
}

impl UsbHost {
    /// Initialize the USB host stack and start scanning for devices.
    ///
    /// # Safety
    /// Must be called once from the main thread before any other USB op.
    pub unsafe fn init(event_tx: Sender<BridgeEvent>) -> Self {
        EVENT_TX.set(event_tx).ok();

        // P4 OTG peripheral selectors for usb_host_config_t.peripheral_map.
        // peripheral 0 = High-Speed (UTMI PHY); peripheral 1 = Full-Speed
        // (internal FSLS PHY on GPIO dp=27/dm=26). peripheral_map exists from
        // IDF v5.5.1 on (see .cargo/config.toml).
        //
        // NOTE: the released ESP-IDF host is single-root-port (hub.c has one
        // root_port_hdl, selects the peripheral via `& BIT1`), so peripheral_map
        // only CHOOSES which ONE OTG to host. Worse, on the P4 the stock host
        // does NOT work on the FS controller even alone: controller 1's
        // interrupt (usb_dwc_periph.c) is ETS_USB_OTG11_CH0_INTR_SOURCE — a
        // per-channel source, not the global core/port interrupt — so the
        // interrupt-driven hcd never sees the FS port connect (verified on
        // device). controller 0 (HS) has the full ETS_USB_OTG_INTR_SOURCE.
        //
        // So: the stock host owns the HS controller (peripheral 0 = BIT0) for
        // radio slot 0. The FS radio (GPIO 27/26) is hosted by a hand-rolled
        // POLLED HAL host in the fs_host C component — no ISR, no hcd — which is
        // the only thing proven to work on the FS controller (the spike). See
        // docs/plans/2026-09-21-dual-usb-host-fs-polled.md.
        const PERIPHERAL_HS: u32 = 1 << 0;

        #[allow(clippy::needless_update)]
        let host_config = usb_host_config_t {
            skip_phy_setup: false,
            intr_flags: ESP_INTR_FLAG_LEVEL1 as i32,
            enum_filter_cb: Some(enum_filter_cb),
            peripheral_map: PERIPHERAL_HS,
            ..unsafe { std::mem::zeroed() }
        };
        let err = usb_host_install(&host_config);
        if err != ESP_OK {
            panic!("USB host install failed: {err}");
        }

        let state = Box::leak(Box::new(Mutex::new(UsbState {
            client_hdl: std::ptr::null_mut(),
            slots: [DeviceSlot::empty(), DeviceSlot::empty()],
        })));
        let tx_sem = Box::leak(Box::new(Mutex::new(())));
        let ctrl_lock = Box::leak(Box::new(Mutex::new(())));

        std::thread::Builder::new()
            .name("usb_host".into())
            .stack_size(4096)
            .spawn(usb_host_daemon_thread)
            .expect("failed to spawn USB host daemon thread");

        let state_ptr = state as *const Mutex<UsbState> as usize;
        std::thread::Builder::new()
            .name("usb_client".into())
            .stack_size(4096)
            .spawn(move || {
                usb_client_thread(state_ptr as *const Mutex<UsbState>);
            })
            .expect("failed to spawn USB client thread");

        Self { state, tx_sem, ctrl_sem: ctrl_lock }
    }

    /// Send raw bytes to `radio` over USB serial.
    pub fn send(&self, radio: usize, data: &[u8]) -> Result<(), &'static str> {
        if radio >= MAX_RADIOS {
            return Err("bad radio index");
        }
        let _lock = self.tx_sem.lock().unwrap();
        let state = self.state.lock().unwrap();
        let slot = &state.slots[radio];
        if !slot.connected || slot.out_xfer.is_null() {
            return Err("not connected");
        }
        let out_xfer = slot.out_xfer;
        let sig = &SLOT_SIGNALS[radio].out;

        // SAFETY: out_xfer is valid while connected; tx_sem serializes TX and
        // we hold the state lock so a disconnect can't free it mid-send.
        unsafe {
            let xfer = &mut *out_xfer;
            let len = data.len().min(USB_TX_BUF_SIZE);
            sig.clear();
            std::ptr::copy_nonoverlapping(data.as_ptr(), xfer.data_buffer, len);
            xfer.num_bytes = len as i32;
            if usb_host_transfer_submit(out_xfer) != ESP_OK {
                error!("TX submit failed (radio {radio})");
                return Err("submit failed");
            }
            if !sig.wait_ms(1000) {
                warn!("TX timeout (radio {radio})");
                return Err("timeout");
            }
            if xfer.status != usb_transfer_status_t_USB_TRANSFER_STATUS_COMPLETED {
                error!("TX failed (radio {radio}): status={}", xfer.status);
                return Err("transfer failed");
            }
        }
        Ok(())
    }

    /// Indices of every currently-bound radio. (Used by the freq self-test.)
    #[allow(dead_code)]
    pub fn connected_radios(&self) -> Vec<usize> {
        let state = self.state.lock().unwrap();
        (0..MAX_RADIOS).filter(|&i| state.slots[i].connected).collect()
    }

    /// Set baud rate on `radio`.
    pub fn set_baud(&self, radio: usize, baud: u32) -> Result<(), &'static str> {
        if radio >= MAX_RADIOS {
            return Err("bad radio index");
        }
        let _lock = self.ctrl_sem.lock().unwrap();
        let state = self.state.lock().unwrap();
        let slot = &state.slots[radio];
        if !slot.connected {
            return Err("not connected");
        }
        let (ctrl_xfer, client_hdl, is_ftdi, vid) =
            (slot.ctrl_xfer, state.client_hdl, slot.is_ftdi, slot.vid);
        let sig = &SLOT_SIGNALS[radio].ctrl;

        if is_ftdi {
            let wvalue = ftdi_baud_divisor(baud);
            unsafe { ftdi_ctrl_request_raw(ctrl_xfer, client_hdl, sig, FTDI_REQ_SET_BAUD, wvalue, 0) }
        } else if vid == 0x10C4 {
            unsafe { cp210x_set_baudrate(ctrl_xfer, client_hdl, sig, baud, 0) }
        } else {
            unsafe { cdc_init_port(ctrl_xfer, client_hdl, sig, baud) };
            Ok(())
        }
    }

    /// Get VID/PID of `radio`, if bound.
    pub fn device_ids(&self, radio: usize) -> Option<(u16, u16)> {
        if radio >= MAX_RADIOS {
            return None;
        }
        let state = self.state.lock().unwrap();
        let slot = &state.slots[radio];
        slot.connected.then_some((slot.vid, slot.pid))
    }

    // --- Per-radio RX capture (detection / CatSession) ---

    /// Start capturing inbound bytes for `radio` into its buffer (cleared).
    pub fn begin_capture(&self, radio: usize) {
        if radio < MAX_RADIOS {
            SLOT_RX[radio].buf.lock().unwrap().clear();
            SLOT_RX[radio].capture.store(true, Ordering::Release);
        }
    }

    /// Snapshot `radio`'s capture buffer.
    pub fn read_capture(&self, radio: usize) -> Vec<u8> {
        if radio < MAX_RADIOS {
            SLOT_RX[radio].buf.lock().unwrap().clone()
        } else {
            Vec::new()
        }
    }

    /// Clear `radio`'s capture buffer without stopping capture.
    pub fn clear_capture(&self, radio: usize) {
        if radio < MAX_RADIOS {
            SLOT_RX[radio].buf.lock().unwrap().clear();
        }
    }

    /// Stop capturing for `radio` (inbound bytes resume flowing as UsbData).
    pub fn end_capture(&self, radio: usize) {
        if radio < MAX_RADIOS {
            SLOT_RX[radio].capture.store(false, Ordering::Release);
        }
    }

    /// Pause bulk IN polling for `radio` so control transfers own the bus.
    pub fn pause_in(&self, radio: usize) {
        if radio < MAX_RADIOS {
            SLOT_RX[radio].in_paused.store(true, Ordering::Release);
            std::thread::sleep(Duration::from_millis(50));
        }
    }

    /// Resume bulk IN polling for `radio`.
    pub fn resume_in(&self, radio: usize) {
        if radio >= MAX_RADIOS {
            return;
        }
        SLOT_RX[radio].in_paused.store(false, Ordering::Release);
        let state = self.state.lock().unwrap();
        let slot = &state.slots[radio];
        if slot.connected && !slot.in_xfer.is_null() {
            unsafe {
                usb_host_transfer_submit(slot.in_xfer);
            }
        }
    }

    /// Reinitialize `radio`'s port at a new baud rate (detection baud probe).
    pub fn reinit_port(&self, radio: usize, baud: u32) {
        if radio >= MAX_RADIOS {
            return;
        }
        self.pause_in(radio);
        let (ctrl_xfer, client_hdl, is_ftdi, vid, connected) = {
            let state = self.state.lock().unwrap();
            let slot = &state.slots[radio];
            (slot.ctrl_xfer, state.client_hdl, slot.is_ftdi, slot.vid, slot.connected)
        };
        if !connected {
            self.resume_in(radio);
            return;
        }
        let sig = &SLOT_SIGNALS[radio].ctrl;
        unsafe {
            if is_ftdi {
                ftdi_init_port(ctrl_xfer, client_hdl, sig, baud);
            } else if vid == 0x10C4 {
                cp210x_init_port(ctrl_xfer, client_hdl, sig, baud);
            } else {
                cdc_init_port(ctrl_xfer, client_hdl, sig, baud);
            }
        }
        self.resume_in(radio);
    }
}

// ---------------------------------------------------------------
// Chip-specific control-transfer helpers (per-slot ctrl signal)
// ---------------------------------------------------------------

/// FTDI vendor control transfer (blocking).
///
/// # Safety
/// Caller holds ctrl_sem and ensures the transfer is valid.
unsafe fn ftdi_ctrl_request_raw(
    ctrl_xfer: *mut usb_transfer_t,
    client_hdl: usb_host_client_handle_t,
    sig: &CompletionSignal,
    request: u8,
    w_value: u16,
    w_index: u16,
) -> Result<(), &'static str> {
    if ctrl_xfer.is_null() || client_hdl.is_null() {
        return Err("invalid state");
    }
    let xfer = &mut *ctrl_xfer;
    let setup = xfer.data_buffer as *mut usb_setup_packet_t;
    (*setup).__bindgen_anon_1.bmRequestType = FTDI_REQTYPE_OUT;
    (*setup).__bindgen_anon_1.bRequest = request;
    (*setup).__bindgen_anon_1.wValue = w_value;
    (*setup).__bindgen_anon_1.wIndex = w_index;
    (*setup).__bindgen_anon_1.wLength = 0;
    xfer.num_bytes = std::mem::size_of::<usb_setup_packet_t>() as i32;
    xfer.bEndpointAddress = 0x00;

    sig.clear();
    if usb_host_transfer_submit_control(client_hdl, ctrl_xfer) != ESP_OK {
        return Err("ctrl submit failed");
    }
    if !sig.wait_ms(2000) {
        return Err("ctrl timeout");
    }
    if xfer.status == usb_transfer_status_t_USB_TRANSFER_STATUS_COMPLETED {
        Ok(())
    } else {
        Err("ctrl transfer failed")
    }
}

/// FTDI full port init (reset, 8N1, no flow, DTR+RTS, latency, baud).
///
/// # Safety
/// Valid ctrl_xfer + client_hdl.
unsafe fn ftdi_init_port(
    ctrl_xfer: *mut usb_transfer_t,
    client_hdl: usb_host_client_handle_t,
    sig: &CompletionSignal,
    baud: u32,
) {
    let req = |r, v, i| {
        let _ = ftdi_ctrl_request_raw(ctrl_xfer, client_hdl, sig, r, v, i);
    };
    req(FTDI_REQ_RESET, 0, 1);
    req(FTDI_REQ_SET_DATA, 0x0008, 1);
    req(FTDI_REQ_SET_FLOW, 0, 1);
    req(FTDI_REQ_SET_MODEM, (1 << 8) | (1 << 9) | 3, 1);
    req(FTDI_REQ_SET_LATENCY, 16, 0);
    req(FTDI_REQ_SET_EVENT_CHR, 0x0000, 1);
    req(FTDI_REQ_SET_ERROR_CHR, 0x0000, 1);
    req(FTDI_REQ_RESET, 1, 1);
    req(FTDI_REQ_RESET, 2, 1);
    let wvalue = ftdi_baud_divisor(baud);
    req(FTDI_REQ_SET_BAUD, wvalue, 0);
    vTaskDelay(50);
    info!("FTDI port initialized at {baud} baud");
}

// CP210x vendor request constants
const CP210X_REQTYPE_OUT: u8 = 0x41;
const CP210X_REQ_IFC_ENABLE: u8 = 0x00;
const CP210X_REQ_SET_LINE_CTL: u8 = 0x03;
const CP210X_REQ_SET_MHS: u8 = 0x07;
const CP210X_REQ_SET_BAUDRATE: u8 = 0x1E;

/// CP210x vendor control request (no data phase).
///
/// # Safety
/// Valid ctrl_xfer + client_hdl.
unsafe fn cp210x_ctrl_request(
    ctrl_xfer: *mut usb_transfer_t,
    client_hdl: usb_host_client_handle_t,
    sig: &CompletionSignal,
    request: u8,
    w_value: u16,
    w_index: u16,
) -> Result<(), &'static str> {
    if ctrl_xfer.is_null() || client_hdl.is_null() {
        return Err("invalid state");
    }
    let xfer = &mut *ctrl_xfer;
    let setup = xfer.data_buffer as *mut usb_setup_packet_t;
    (*setup).__bindgen_anon_1.bmRequestType = CP210X_REQTYPE_OUT;
    (*setup).__bindgen_anon_1.bRequest = request;
    (*setup).__bindgen_anon_1.wValue = w_value;
    (*setup).__bindgen_anon_1.wIndex = w_index;
    (*setup).__bindgen_anon_1.wLength = 0;
    xfer.num_bytes = std::mem::size_of::<usb_setup_packet_t>() as i32;
    xfer.bEndpointAddress = 0x00;

    sig.clear();
    if usb_host_transfer_submit_control(client_hdl, ctrl_xfer) != ESP_OK {
        return Err("cp210x ctrl submit failed");
    }
    if !sig.wait_ms(2000) {
        return Err("cp210x ctrl timeout");
    }
    if xfer.status == usb_transfer_status_t_USB_TRANSFER_STATUS_COMPLETED {
        Ok(())
    } else {
        Err("cp210x ctrl transfer failed")
    }
}

/// CP210x SET_BAUDRATE with 4-byte data payload.
///
/// # Safety
/// Valid ctrl_xfer + client_hdl.
unsafe fn cp210x_set_baudrate(
    ctrl_xfer: *mut usb_transfer_t,
    client_hdl: usb_host_client_handle_t,
    sig: &CompletionSignal,
    baud: u32,
    iface: u16,
) -> Result<(), &'static str> {
    if ctrl_xfer.is_null() || client_hdl.is_null() {
        return Err("invalid state");
    }
    let xfer = &mut *ctrl_xfer;
    let setup = xfer.data_buffer as *mut usb_setup_packet_t;
    (*setup).__bindgen_anon_1.bmRequestType = CP210X_REQTYPE_OUT;
    (*setup).__bindgen_anon_1.bRequest = CP210X_REQ_SET_BAUDRATE;
    (*setup).__bindgen_anon_1.wValue = 0;
    (*setup).__bindgen_anon_1.wIndex = iface;
    (*setup).__bindgen_anon_1.wLength = 4;
    let data_ptr = xfer.data_buffer.add(std::mem::size_of::<usb_setup_packet_t>());
    let baud_data = std::slice::from_raw_parts_mut(data_ptr, 4);
    baud_data[0] = (baud & 0xFF) as u8;
    baud_data[1] = ((baud >> 8) & 0xFF) as u8;
    baud_data[2] = ((baud >> 16) & 0xFF) as u8;
    baud_data[3] = ((baud >> 24) & 0xFF) as u8;
    xfer.num_bytes = (std::mem::size_of::<usb_setup_packet_t>() + 4) as i32;
    xfer.bEndpointAddress = 0x00;

    sig.clear();
    if usb_host_transfer_submit_control(client_hdl, ctrl_xfer) != ESP_OK {
        return Err("cp210x baudrate submit failed");
    }
    if !sig.wait_ms(2000) {
        return Err("cp210x baudrate timeout");
    }
    if xfer.status == usb_transfer_status_t_USB_TRANSFER_STATUS_COMPLETED {
        Ok(())
    } else {
        Err("cp210x baudrate transfer failed")
    }
}

/// CP210x port init (enable, baud, 8N2, DTR+RTS).
///
/// # Safety
/// Valid ctrl_xfer + client_hdl.
unsafe fn cp210x_init_port(
    ctrl_xfer: *mut usb_transfer_t,
    client_hdl: usb_host_client_handle_t,
    sig: &CompletionSignal,
    baud: u32,
) {
    let iface: u16 = 0;
    let _ = cp210x_ctrl_request(ctrl_xfer, client_hdl, sig, CP210X_REQ_IFC_ENABLE, 1, iface);
    let _ = cp210x_set_baudrate(ctrl_xfer, client_hdl, sig, baud, iface);
    let _ = cp210x_ctrl_request(ctrl_xfer, client_hdl, sig, CP210X_REQ_SET_LINE_CTL, 0x0802, iface);
    let _ = cp210x_ctrl_request(ctrl_xfer, client_hdl, sig, CP210X_REQ_SET_MHS, 0x0303, iface);
    vTaskDelay(50);
    info!("CP210x port initialized at {baud} baud (8N1, DTR+RTS)");
}

/// CDC-ACM port init: SET_LINE_CODING (baud, 8N1) + SET_CONTROL_LINE_STATE
/// (DTR+RTS). Covers CH340, STM32 CDC, and the UV-K1's native USB-C.
///
/// # Safety
/// Valid ctrl_xfer + client_hdl.
unsafe fn cdc_init_port(
    ctrl_xfer: *mut usb_transfer_t,
    client_hdl: usb_host_client_handle_t,
    sig: &CompletionSignal,
    baud: u32,
) {
    if ctrl_xfer.is_null() || client_hdl.is_null() {
        return;
    }
    let xfer = &mut *ctrl_xfer;
    let setup = xfer.data_buffer as *mut usb_setup_packet_t;
    (*setup).__bindgen_anon_1.bmRequestType = 0x21;
    (*setup).__bindgen_anon_1.bRequest = 0x20; // SET_LINE_CODING
    (*setup).__bindgen_anon_1.wValue = 0;
    (*setup).__bindgen_anon_1.wIndex = 0;
    (*setup).__bindgen_anon_1.wLength = 7;
    let data_ptr = xfer.data_buffer.add(std::mem::size_of::<usb_setup_packet_t>());
    let line_coding = std::slice::from_raw_parts_mut(data_ptr, 7);
    line_coding[0] = (baud & 0xFF) as u8;
    line_coding[1] = ((baud >> 8) & 0xFF) as u8;
    line_coding[2] = ((baud >> 16) & 0xFF) as u8;
    line_coding[3] = ((baud >> 24) & 0xFF) as u8;
    line_coding[4] = 0; // 1 stop bit
    line_coding[5] = 0; // no parity
    line_coding[6] = 8; // 8 data bits
    xfer.num_bytes = (std::mem::size_of::<usb_setup_packet_t>() + 7) as i32;
    xfer.bEndpointAddress = 0x00;
    sig.clear();
    if usb_host_transfer_submit_control(client_hdl, ctrl_xfer) != ESP_OK {
        warn!("CDC SET_LINE_CODING submit failed");
    } else if !sig.wait_ms(2000) {
        warn!("CDC SET_LINE_CODING timeout");
    }

    (*setup).__bindgen_anon_1.bmRequestType = 0x21;
    (*setup).__bindgen_anon_1.bRequest = 0x22; // SET_CONTROL_LINE_STATE
    (*setup).__bindgen_anon_1.wValue = 0x0003; // DTR + RTS
    (*setup).__bindgen_anon_1.wIndex = 0;
    (*setup).__bindgen_anon_1.wLength = 0;
    xfer.num_bytes = std::mem::size_of::<usb_setup_packet_t>() as i32;
    sig.clear();
    if usb_host_transfer_submit_control(client_hdl, ctrl_xfer) != ESP_OK {
        warn!("CDC SET_CONTROL_LINE_STATE submit failed");
    } else if !sig.wait_ms(2000) {
        warn!("CDC SET_CONTROL_LINE_STATE timeout");
    }
    vTaskDelay(50);
    info!("CDC port initialized at {baud} baud (8N1, DTR+RTS)");
}

// ---------------------------------------------------------------
// Transfer callbacks (USB host event loop context)
// ---------------------------------------------------------------

unsafe extern "C" fn in_xfer_cb(transfer: *mut usb_transfer_t) {
    let xfer = &*transfer;
    let idx = slot_from_ctx(xfer.context);
    if idx >= MAX_RADIOS {
        return;
    }

    if xfer.status != usb_transfer_status_t_USB_TRANSFER_STATUS_COMPLETED {
        if xfer.status == usb_transfer_status_t_USB_TRANSFER_STATUS_CANCELED {
            return;
        }
        warn!("Bulk IN error (radio {idx}): status={}", xfer.status);
        usb_host_transfer_submit(transfer);
        return;
    }

    let data = std::slice::from_raw_parts(xfer.data_buffer, xfer.actual_num_bytes as usize);
    // FTDI prepends a 2-byte modem status prefix on every packet.
    let is_ftdi = SLOT_RX[idx].is_ftdi.load(Ordering::Relaxed);
    let payload = if is_ftdi {
        if data.len() <= 2 {
            usb_host_transfer_submit(transfer);
            return;
        }
        &data[2..]
    } else {
        data
    };

    if SLOT_RX[idx].capture.load(Ordering::Acquire) {
        if let Ok(mut buf) = SLOT_RX[idx].buf.lock() {
            buf.extend_from_slice(payload);
        }
    } else if let Some(tx) = EVENT_TX.get() {
        let _ = tx.send(BridgeEvent::UsbData { radio: idx, data: payload.to_vec() });
    }

    if !SLOT_RX[idx].in_paused.load(Ordering::Relaxed) {
        usb_host_transfer_submit(transfer);
    }
}

unsafe extern "C" fn out_xfer_cb(transfer: *mut usb_transfer_t) {
    let xfer = &*transfer;
    if xfer.status != usb_transfer_status_t_USB_TRANSFER_STATUS_COMPLETED {
        error!("Bulk OUT error: status={}", xfer.status);
    }
    let idx = slot_from_ctx(xfer.context);
    if idx < MAX_RADIOS {
        SLOT_SIGNALS[idx].out.signal();
    }
}

unsafe extern "C" fn ctrl_xfer_cb(transfer: *mut usb_transfer_t) {
    let xfer = &*transfer;
    if xfer.status != usb_transfer_status_t_USB_TRANSFER_STATUS_COMPLETED {
        warn!("CTRL transfer error: status={}", xfer.status);
    }
    let idx = slot_from_ctx(xfer.context);
    if idx < MAX_RADIOS {
        SLOT_SIGNALS[idx].ctrl.signal();
    }
}

// ---------------------------------------------------------------
// Descriptor parsing
// ---------------------------------------------------------------

/// Parse the bulk IN/OUT endpoint addresses AND the interface that owns them
/// (interface 0 for simple chips; the data interface for composite CDC-ACM).
///
/// # Safety
/// dev_hdl must be valid + open.
unsafe fn parse_endpoints(dev_hdl: usb_device_handle_t) -> Option<(u8, u8, u8)> {
    let mut config_desc: *const usb_config_desc_t = std::ptr::null();
    if usb_host_get_active_config_descriptor(dev_hdl, &mut config_desc) != ESP_OK {
        return None;
    }
    let total_len = (*config_desc).__bindgen_anon_1.wTotalLength as usize;
    let base = config_desc as *const u8;
    let mut offset = 0usize;
    let mut in_ep = 0u8;
    let mut out_ep = 0u8;
    let mut cur_iface = 0u8;
    let mut bulk_iface = 0u8;

    while offset < total_len {
        let desc = base.add(offset) as *const usb_standard_desc_t;
        let len = (*desc).__bindgen_anon_1.bLength as usize;
        if len == 0 {
            break;
        }
        let desc_type = (*desc).__bindgen_anon_1.bDescriptorType;
        if desc_type == USB_B_DESCRIPTOR_TYPE_INTERFACE as u8 {
            let iface = desc as *const usb_intf_desc_t;
            cur_iface = (*iface).__bindgen_anon_1.bInterfaceNumber;
        } else if desc_type == USB_B_DESCRIPTOR_TYPE_ENDPOINT as u8 {
            let ep = desc as *const usb_ep_desc_t;
            let attrs = (*ep).__bindgen_anon_1.bmAttributes & USB_BM_ATTRIBUTES_XFERTYPE_MASK as u8;
            if attrs == USB_BM_ATTRIBUTES_XFER_BULK as u8 {
                let addr = (*ep).__bindgen_anon_1.bEndpointAddress;
                if addr & 0x80 != 0 && in_ep == 0 {
                    in_ep = addr;
                    bulk_iface = cur_iface;
                    info!("Bulk IN endpoint: 0x{addr:02X} (iface {cur_iface})");
                } else if addr & 0x80 == 0 && out_ep == 0 {
                    out_ep = addr;
                    bulk_iface = cur_iface;
                    info!("Bulk OUT endpoint: 0x{addr:02X} (iface {cur_iface})");
                }
                if in_ep != 0 && out_ep != 0 {
                    break;
                }
            }
        }
        offset += len;
    }

    if in_ep != 0 && out_ep != 0 {
        Some((in_ep, out_ep, bulk_iface))
    } else {
        error!("Could not find bulk endpoints");
        None
    }
}

// ---------------------------------------------------------------
// Device connect/disconnect handling
// ---------------------------------------------------------------

/// Handle a newly connected USB device — bind it to the first free slot.
///
/// # Safety
/// Client task context, valid state pointer.
unsafe fn handle_device_connected(state_ptr: *const Mutex<UsbState>, dev_addr: u8) {
    let state_mtx = &*state_ptr;
    let mut state = state_mtx.lock().unwrap();

    let mut dev_hdl: usb_device_handle_t = std::ptr::null_mut();
    if usb_host_device_open(state.client_hdl, dev_addr, &mut dev_hdl) != ESP_OK {
        error!("Failed to open USB device");
        return;
    }

    let mut dev_desc: *const usb_device_desc_t = std::ptr::null();
    usb_host_get_device_descriptor(dev_hdl, &mut dev_desc);
    let vid = (*dev_desc).__bindgen_anon_1.idVendor;
    let pid = (*dev_desc).__bindgen_anon_1.idProduct;
    let class = (*dev_desc).__bindgen_anon_1.bDeviceClass;
    info!("USB device enumerated: VID=0x{vid:04X} PID=0x{pid:04X} class=0x{class:02X}");

    if class == 0x09 {
        info!("Skipping USB hub (class 0x09) — keep enumerated, do not claim");
        usb_host_device_close(state.client_hdl, dev_hdl);
        return;
    }

    let chip = match match_chip(vid, pid) {
        Some(c) => c,
        None => {
            warn!("Unsupported USB device (VID=0x{vid:04X} PID=0x{pid:04X}) — add to SUPPORTED_CHIPS");
            usb_host_device_close(state.client_hdl, dev_hdl);
            return;
        }
    };

    let Some(idx) = (0..MAX_RADIOS).find(|&i| !state.slots[i].connected) else {
        warn!("All {MAX_RADIOS} radio slots full — ignoring {}", chip.name);
        usb_host_device_close(state.client_hdl, dev_hdl);
        return;
    };
    info!("{} matched → radio slot {idx} (VID=0x{vid:04X} PID=0x{pid:04X})", chip.name);

    let (in_ep, out_ep, bulk_iface) = match parse_endpoints(dev_hdl) {
        Some(eps) => eps,
        None => {
            usb_host_device_close(state.client_hdl, dev_hdl);
            return;
        }
    };

    if usb_host_interface_claim(state.client_hdl, dev_hdl, bulk_iface, 0) != ESP_OK {
        error!("Failed to claim interface {bulk_iface}");
        usb_host_device_close(state.client_hdl, dev_hdl);
        return;
    }
    info!("Claimed interface {bulk_iface} (radio {idx})");

    let mut in_xfer: *mut usb_transfer_t = std::ptr::null_mut();
    let mut out_xfer: *mut usb_transfer_t = std::ptr::null_mut();
    let mut ctrl_xfer: *mut usb_transfer_t = std::ptr::null_mut();
    usb_host_transfer_alloc(USB_RX_BUF_SIZE, 0, &mut in_xfer);
    usb_host_transfer_alloc(USB_TX_BUF_SIZE, 0, &mut out_xfer);
    usb_host_transfer_alloc(USB_CTRL_BUF_SIZE, 0, &mut ctrl_xfer);

    let ctx = ctx_from_slot(idx);
    (*in_xfer).device_handle = dev_hdl;
    (*in_xfer).bEndpointAddress = in_ep;
    (*in_xfer).callback = Some(in_xfer_cb);
    (*in_xfer).num_bytes = USB_RX_BUF_SIZE as i32;
    (*in_xfer).context = ctx;
    (*out_xfer).device_handle = dev_hdl;
    (*out_xfer).bEndpointAddress = out_ep;
    (*out_xfer).callback = Some(out_xfer_cb);
    (*out_xfer).context = ctx;
    (*ctrl_xfer).device_handle = dev_hdl;
    (*ctrl_xfer).callback = Some(ctrl_xfer_cb);
    (*ctrl_xfer).context = ctx;

    // Per-slot callback state must be live before the first transfer fires.
    SLOT_RX[idx].is_ftdi.store(chip.is_ftdi, Ordering::Release);
    SLOT_RX[idx].in_paused.store(false, Ordering::Release);
    SLOT_RX[idx].capture.store(false, Ordering::Release);
    SLOT_RX[idx].buf.lock().unwrap().clear();

    let slot = &mut state.slots[idx];
    slot.dev_hdl = dev_hdl;
    slot.in_xfer = in_xfer;
    slot.out_xfer = out_xfer;
    slot.ctrl_xfer = ctrl_xfer;
    slot.in_ep_addr = in_ep;
    slot.out_ep_addr = out_ep;
    slot.claimed_iface = bulk_iface;
    slot.is_ftdi = chip.is_ftdi;
    slot.vid = vid;
    slot.pid = pid;

    let sig = &SLOT_SIGNALS[idx].ctrl;
    if chip.is_ftdi {
        ftdi_init_port(ctrl_xfer, state.client_hdl, sig, DEFAULT_BAUD_RATE);
    } else if vid == 0x10C4 {
        cp210x_init_port(ctrl_xfer, state.client_hdl, sig, DEFAULT_BAUD_RATE);
    } else {
        cdc_init_port(ctrl_xfer, state.client_hdl, sig, DEFAULT_BAUD_RATE);
    }

    if usb_host_transfer_submit(in_xfer) != ESP_OK {
        error!("Failed to submit IN transfer (radio {idx})");
    } else {
        info!("Bulk IN polling started on EP 0x{in_ep:02X} (radio {idx})");
    }

    state.slots[idx].connected = true;
    info!("CAT link ready ({}, radio {idx})", chip.name);

    if let Some(tx) = EVENT_TX.get() {
        let _ = tx.send(BridgeEvent::UsbConnected { radio: idx, vid, pid });
    }
}

/// Handle USB device disconnection — free the slot matching `dev_hdl`.
///
/// # Safety
/// Client task context.
unsafe fn handle_device_disconnected(state_ptr: *const Mutex<UsbState>, dev_hdl: usb_device_handle_t) {
    let state_mtx = &*state_ptr;
    let mut state = state_mtx.lock().unwrap();

    let Some(idx) = (0..MAX_RADIOS).find(|&i| state.slots[i].dev_hdl == dev_hdl && !dev_hdl.is_null())
    else {
        warn!("DEV_GONE for an unknown device handle");
        return;
    };
    warn!("USB device disconnected (radio {idx})");

    let client_hdl = state.client_hdl;
    let slot = &mut state.slots[idx];
    slot.connected = false;
    SLOT_RX[idx].capture.store(false, Ordering::Release);

    if !slot.in_xfer.is_null() {
        usb_host_transfer_free(slot.in_xfer);
        slot.in_xfer = std::ptr::null_mut();
    }
    if !slot.out_xfer.is_null() {
        usb_host_transfer_free(slot.out_xfer);
        slot.out_xfer = std::ptr::null_mut();
    }
    if !slot.ctrl_xfer.is_null() {
        usb_host_transfer_free(slot.ctrl_xfer);
        slot.ctrl_xfer = std::ptr::null_mut();
    }
    if !slot.dev_hdl.is_null() {
        usb_host_interface_release(client_hdl, slot.dev_hdl, slot.claimed_iface);
        usb_host_device_close(client_hdl, slot.dev_hdl);
        slot.dev_hdl = std::ptr::null_mut();
    }
    slot.vid = 0;
    slot.pid = 0;

    if let Some(tx) = EVENT_TX.get() {
        let _ = tx.send(BridgeEvent::UsbDisconnected { radio: idx });
    }
}

// ---------------------------------------------------------------
// USB host threads
// ---------------------------------------------------------------

fn usb_host_daemon_thread() {
    info!("USB host daemon started");
    loop {
        // SAFETY: safe to call from any thread.
        unsafe {
            let mut event_flags: u32 = 0;
            usb_host_lib_handle_events(u32::MAX, &mut event_flags);
        }
    }
}

unsafe extern "C" fn client_event_cb(
    event: *const usb_host_client_event_msg_t,
    arg: *mut std::ffi::c_void,
) {
    let evt = &*event;
    #[allow(non_upper_case_globals)]
    match evt.event {
        usb_host_client_event_t_USB_HOST_CLIENT_EVENT_NEW_DEV => {
            let addr = evt.__bindgen_anon_1.new_dev.address;
            info!("New USB device (addr={addr})");
            if let Ok(mut q) = PENDING_QUEUE.lock() {
                q.push_back(addr);
            }
        }
        usb_host_client_event_t_USB_HOST_CLIENT_EVENT_DEV_GONE => {
            let dev_hdl = evt.__bindgen_anon_1.dev_gone.dev_hdl;
            info!("USB device gone");
            handle_device_disconnected(arg as *const Mutex<UsbState>, dev_hdl);
        }
        _ => {}
    }
}

fn usb_client_thread(state_ptr: *const Mutex<UsbState>) {
    info!("USB client task started");
    // SAFETY: state_ptr is a leaked Box pointer valid for the program lifetime.
    unsafe {
        let client_config = usb_host_client_config_t {
            is_synchronous: false,
            max_num_event_msg: 5,
            __bindgen_anon_1: usb_host_client_config_t__bindgen_ty_1 {
                async_: usb_host_client_config_t__bindgen_ty_1__bindgen_ty_1 {
                    client_event_callback: Some(client_event_cb),
                    callback_arg: state_ptr as *mut std::ffi::c_void,
                },
            },
        };
        let mut client_hdl: usb_host_client_handle_t = std::ptr::null_mut();
        if usb_host_client_register(&client_config, &mut client_hdl) != ESP_OK {
            panic!("USB client register failed");
        }
        {
            let mut state = (*state_ptr).lock().unwrap();
            state.client_hdl = client_hdl;
        }
        info!("USB client registered, scanning for devices...");

        loop {
            usb_host_client_handle_events(client_hdl, u32::MAX);

            if SETUP_IN_PROGRESS.load(Ordering::Acquire) {
                continue;
            }
            let addr = match PENDING_QUEUE.lock().ok().and_then(|mut q| q.pop_front()) {
                Some(a) => a,
                None => continue,
            };
            // Drop new devices only when every radio slot is already bound.
            let full = {
                let s = (*state_ptr).lock().unwrap();
                s.slots.iter().all(|slot| slot.connected)
            };
            if full {
                info!("All radio slots full, ignoring addr={addr}");
                continue;
            }

            SETUP_IN_PROGRESS.store(true, Ordering::Release);
            let sp = state_ptr as usize;
            let spawn_result = std::thread::Builder::new()
                .name("dev_setup".into())
                .stack_size(8192)
                .spawn(move || {
                    let _guard = SetupInProgressGuard;
                    handle_device_connected(sp as *const Mutex<UsbState>, addr);
                });
            if spawn_result.is_err() {
                error!("Failed to spawn dev_setup thread for addr={addr}");
                SETUP_IN_PROGRESS.store(false, Ordering::Release);
            }
        }
    }
}
