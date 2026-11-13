//! USB Host serial interface for radio CAT control.
//!
//! Uses the raw ESP-IDF USB Host Library directly (NOT the CDC-ACM driver)
//! to open USB-serial adapters (FTDI, CP210x, CH340).
//!
//! The CDC-ACM driver's bulk OUT transfers silently fail with FTDI devices —
//! see `docs/usb-host-investigation.md` for details.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Sender;
use std::sync::{Condvar, Mutex, OnceLock};
use std::time::Duration;

use ::log::{error, info, warn};
use esp_idf_sys::*;

use crate::BridgeEvent;

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
    ChipDef {
        vid: 0x0403,
        pid: 0x6015,
        name: "FTDI FT-X",
        is_ftdi: true,
    },
    ChipDef {
        vid: 0x0403,
        pid: 0x6001,
        name: "FTDI FT232",
        is_ftdi: true,
    },
    ChipDef {
        vid: 0x10C4,
        pid: 0xEA60,
        name: "CP2102",
        is_ftdi: false,
    },
    ChipDef {
        vid: 0x10C4,
        pid: 0xEA70,
        name: "CP2105",
        is_ftdi: false,
    },
    ChipDef {
        vid: 0x1A86,
        pid: 0x7523,
        name: "CH340",
        is_ftdi: false,
    },
    // QRP Labs QMX/QMX+ — STM32 CDC-ACM virtual COM port
    ChipDef {
        vid: 0x0483,
        pid: 0x5740,
        name: "STM32 CDC",
        is_ftdi: false,
    },
    // Quansheng UV-K1 / UV-K5 V3 (PY32F071) running the F4HWN CAT build —
    // native USB-C CDC-ACM port (composite device, class 0xEF with an IAD;
    // the bulk pair lives on the CDC data interface). The radio only
    // transmits on the VCP while DTR is asserted, which `cdc_init_port`
    // does via SET_CONTROL_LINE_STATE.
    ChipDef {
        vid: 0x36B7,
        pid: 0xFFFF,
        name: "Quansheng UV-K5 CAT",
        is_ftdi: false,
    },
];

fn match_chip(vid: u16, pid: u16) -> Option<&'static ChipDef> {
    SUPPORTED_CHIPS
        .iter()
        .find(|c| c.vid == vid && c.pid == pid)
}

/// USB enumeration filter — runs early, before ESP-IDF spends HCD channels
/// fully enumerating the device.
///
/// Returns `true` to allow enumeration, `false` to skip the device entirely.
///
/// Radios that present as internal hubs (Yaesu FTX-1, FT-991A, Icom IC-705)
/// expose multiple downstream devices — CAT serial chip, USB audio, and
/// sometimes a separate HRI / data device. The ESP32-S3 has only 8 HCD
/// channels and ESP-IDF v5.4's hub driver can't recover from channel
/// exhaustion (IDF-10044). By rejecting everything that isn't a hub or a
/// known CAT chip up front, we keep the FTX-1 case to ~5 channels: root
/// hub + downstream hub + CP2105 (ctrl + bulk IN + bulk OUT).
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

    // Every device we care about exposes its CAT (or hub) function in
    // configuration 1, which is also ESP-IDF's default. Set it explicitly
    // so we don't depend on whatever uninitialised value the host stack
    // would otherwise pass downstream.
    if !b_cfg_value.is_null() {
        *b_cfg_value = 1;
    }

    // USB_CLASS_HUB == 0x09 — allow hubs so we can reach downstream CAT
    // chips. We refuse to claim hubs as serial devices in
    // `handle_device_connected`, so this is safe.
    if class == 0x09 {
        info!("Enum filter: allow hub (VID=0x{vid:04X} PID=0x{pid:04X})");
        return true;
    }

    if match_chip(vid, pid).is_some() {
        info!("Enum filter: allow CAT chip (VID=0x{vid:04X} PID=0x{pid:04X})");
        return true;
    }

    // CDC devices (Communications 0x02 / CDC-Data 0x0A): radios like the Yaesu
    // FTX-1 expose an extra CDC data/HRI interface behind their internal hub,
    // alongside the CP2105 CAT port. We never *claim* it (match_chip fails, so
    // `handle_device_connected` closes it), but we must let it ENUMERATE rather
    // than reject it. Returning `false` here triggers ESP-IDF's enum-abort path
    // (IDF-10044): on the S3 external-hub driver the aborted device's HCD
    // channel is not released cleanly, the hub port collapses, and the whole
    // tree re-enumerates — producing a ~3 s USB disconnect/reconnect loop.
    // Allowing enumeration and then closing the device cleanly keeps the hub
    // stable. Audio (0x01) / HID (0x03) stay rejected to conserve HCD channels.
    if class == 0x02 || class == 0x0A {
        info!("Enum filter: allow CDC (VID=0x{vid:04X} PID=0x{pid:04X} class=0x{class:02X}) — enumerate, not claimed");
        return true;
    }

    info!(
        "Enum filter: skip (VID=0x{vid:04X} PID=0x{pid:04X} class=0x{class:02X}) — not a hub or supported CAT chip"
    );
    false
}

/// Internal state shared between USB tasks. Protected by a mutex for TX.
struct UsbState {
    client_hdl: usb_host_client_handle_t,
    dev_hdl: usb_device_handle_t,
    in_xfer: *mut usb_transfer_t,
    out_xfer: *mut usb_transfer_t,
    ctrl_xfer: *mut usb_transfer_t,
    in_ep_addr: u8,
    out_ep_addr: u8,
    is_ftdi: bool,
    connected: bool,
    vid: u16,
    pid: u16,
}

// SAFETY: USB handles are used from specific tasks; the Mutex guards concurrent access.
unsafe impl Send for UsbState {}
unsafe impl Sync for UsbState {}

/// Completion signal for transfer callbacks.
struct CompletionSignal {
    mutex: Mutex<bool>,
    condvar: Condvar,
}

impl CompletionSignal {
    fn new() -> Self {
        Self {
            mutex: Mutex::new(false),
            condvar: Condvar::new(),
        }
    }

    /// Clear the signal (set to not-done).
    fn clear(&self) {
        let mut done = self.mutex.lock().unwrap();
        *done = false;
    }

    /// Signal completion (called from callback context).
    fn signal(&self) {
        let mut done = self.mutex.lock().unwrap();
        *done = true;
        self.condvar.notify_one();
    }

    /// Wait for completion with a timeout in milliseconds.
    /// Returns true if signaled, false if timed out.
    fn wait_ms(&self, timeout_ms: u64) -> bool {
        let mut done = self.mutex.lock().unwrap();
        if *done {
            return true;
        }
        let result = self
            .condvar
            .wait_timeout(done, Duration::from_millis(timeout_ms))
            .unwrap();
        done = result.0;
        *done
    }
}

/// USB host interface for radio serial communication.
pub struct UsbHost {
    state: &'static Mutex<UsbState>,
    tx_sem: &'static Mutex<()>,
    ctrl_sem: &'static Mutex<()>,
}

// Completion signals for OUT and CTRL transfer callbacks (set once during init)
static OUT_DONE: OnceLock<&'static CompletionSignal> = OnceLock::new();
static CTRL_DONE: OnceLock<&'static CompletionSignal> = OnceLock::new();

// Global sender for events back to the main loop (set once during init)
static EVENT_TX: OnceLock<Sender<BridgeEvent>> = OnceLock::new();

// RX intercept callback — written from app thread, read from USB callback.
// Using Mutex rather than static mut for safe cross-thread access.
type RxInterceptFn = fn(&[u8]);
static RX_INTERCEPT: Mutex<Option<RxInterceptFn>> = Mutex::new(None);

// Pending device addresses from client callback. A queue (rather than a
// single slot) is required because an internal hub — Yaesu FTX-1, Icom
// IC-705, etc. — enumerates multiple downstream devices back-to-back, so
// several NEW_DEV events can arrive inside one usb_host_client_handle_events
// call. Losing any of them would mean the CAT chip might never be claimed.
static PENDING_QUEUE: Mutex<VecDeque<u8>> = Mutex::new(VecDeque::new());

// True while a dev_setup thread is running. Prevents concurrent setups,
// which would race on state.dev_hdl and the bulk/ctrl transfer pointers.
static SETUP_IN_PROGRESS: AtomicBool = AtomicBool::new(false);

/// RAII guard that always clears `SETUP_IN_PROGRESS` on drop. Used inside
/// the dev_setup thread closure so an early `return`, a panic-unwind, or a
/// later refactor that adds new exit points can't leave the flag stuck —
/// which would permanently wedge the event loop from spawning further
/// setups.
struct SetupInProgressGuard;
impl Drop for SetupInProgressGuard {
    fn drop(&mut self) {
        SETUP_IN_PROGRESS.store(false, Ordering::Release);
    }
}

// When true, the IN callback stops resubmitting (pauses bulk IN polling).
static IN_PAUSED: AtomicBool = AtomicBool::new(false);

/// Compute FTDI baud rate divisor (Linux ftdi_sio algorithm).
fn ftdi_baud_divisor(baud: u32) -> u16 {
    static DIVFRAC: [u8; 8] = [0, 3, 2, 4, 1, 5, 6, 7];

    let divisor3 = (48_000_000u32 + baud) / (2 * baud);
    let divisor = (divisor3 >> 3) as u16;
    let frac = DIVFRAC[(divisor3 & 0x7) as usize] as u16;
    let mut wvalue = divisor | (frac << 14);

    // Special cases for highest baud rates
    if wvalue == 1 {
        wvalue = 0; // 3 MBaud
    } else if wvalue == 0x4001 {
        wvalue = 1; // 2 MBaud
    }

    wvalue
}

impl UsbHost {
    /// Initialize the USB host stack and start scanning for devices.
    ///
    /// # Safety
    /// Must be called once from the main thread before any other USB operations.
    pub unsafe fn init(event_tx: Sender<BridgeEvent>) -> Self {
        // Store global event sender
        EVENT_TX.set(event_tx).ok();

        // Install USB host library
        #[allow(clippy::needless_update)]
        let host_config = usb_host_config_t {
            skip_phy_setup: false,
            intr_flags: ESP_INTR_FLAG_LEVEL1 as i32,
            // Reject audio / HRI / unknown-VID devices before the host
            // stack spends HCD channels on them — see enum_filter_cb.
            enum_filter_cb: Some(enum_filter_cb),
            // `..zeroed()` covers fields added in newer ESP-IDF versions
            // (e.g. `root_port_unpowered` added in v5.4+).
            ..unsafe { std::mem::zeroed() }
        };
        let err = usb_host_install(&host_config);
        if err != ESP_OK {
            panic!("USB host install failed: {err}");
        }

        // Create completion signals for OUT and CTRL transfers
        OUT_DONE
            .set(Box::leak(Box::new(CompletionSignal::new())))
            .ok();
        CTRL_DONE
            .set(Box::leak(Box::new(CompletionSignal::new())))
            .ok();

        // Allocate static state
        let state = Box::leak(Box::new(Mutex::new(UsbState {
            client_hdl: std::ptr::null_mut(),
            dev_hdl: std::ptr::null_mut(),
            in_xfer: std::ptr::null_mut(),
            out_xfer: std::ptr::null_mut(),
            ctrl_xfer: std::ptr::null_mut(),
            in_ep_addr: 0,
            out_ep_addr: 0,
            is_ftdi: false,
            connected: false,
            vid: 0,
            pid: 0,
        })));

        let tx_sem = Box::leak(Box::new(Mutex::new(())));
        let ctrl_lock = Box::leak(Box::new(Mutex::new(())));

        // Start USB host daemon task
        std::thread::Builder::new()
            .name("usb_host".into())
            .stack_size(4096)
            .spawn(|| {
                usb_host_daemon_thread();
            })
            .expect("failed to spawn USB host daemon thread");

        // Start USB client task
        let state_ptr = state as *const Mutex<UsbState> as usize;
        std::thread::Builder::new()
            .name("usb_client".into())
            .stack_size(4096)
            .spawn(move || {
                usb_client_thread(state_ptr as *const Mutex<UsbState>);
            })
            .expect("failed to spawn USB client thread");

        Self {
            state,
            tx_sem,
            ctrl_sem: ctrl_lock,
        }
    }

    /// Send raw bytes to the radio over USB serial.
    pub fn send(&self, data: &[u8]) -> Result<(), &'static str> {
        let _lock = self.tx_sem.lock().unwrap();
        let mut state = self.state.lock().unwrap();

        if !state.connected || state.out_xfer.is_null() {
            return Err("not connected");
        }

        // SAFETY: out_xfer is a valid, allocated USB transfer (checked above).
        // We hold tx_sem to prevent concurrent TX submissions.
        unsafe {
            let xfer = &mut *state.out_xfer;
            let len = data.len().min(USB_TX_BUF_SIZE);

            // Clear completion signal
            OUT_DONE.get().unwrap().clear();

            std::ptr::copy_nonoverlapping(data.as_ptr(), xfer.data_buffer, len);
            xfer.num_bytes = len as i32;

            let err = usb_host_transfer_submit(state.out_xfer);
            if err != ESP_OK {
                error!("TX submit failed: {err}");
                return Err("submit failed");
            }

            // Wait for completion (1000ms timeout)
            if !OUT_DONE.get().unwrap().wait_ms(1000) {
                warn!("TX timeout");
                return Err("timeout");
            }

            if xfer.status != usb_transfer_status_t_USB_TRANSFER_STATUS_COMPLETED {
                error!("TX failed: status={}", xfer.status);
                return Err("transfer failed");
            }
        }

        Ok(())
    }

    /// Check if a USB-serial device is connected.
    #[allow(dead_code)]
    pub fn connected(&self) -> bool {
        self.state.lock().unwrap().connected
    }

    /// Set baud rate on the connected device.
    pub fn set_baud(&self, baud: u32) -> Result<(), &'static str> {
        let _lock = self.ctrl_sem.lock().unwrap();
        let state = self.state.lock().unwrap();

        if !state.connected {
            return Err("not connected");
        }

        if state.is_ftdi {
            let wvalue = ftdi_baud_divisor(baud);
            info!("FTDI SET_BAUD: {baud} (wValue=0x{wvalue:04X})");
            // SAFETY: ctrl_xfer and client_hdl are valid while connected.
            unsafe {
                ftdi_ctrl_request_raw(
                    state.ctrl_xfer,
                    state.client_hdl,
                    FTDI_REQ_SET_BAUD,
                    wvalue,
                    0,
                )
            }
        } else if state.vid == 0x10C4 {
            info!("CP210x SET_BAUDRATE: {baud}");
            unsafe { cp210x_set_baudrate(state.ctrl_xfer, state.client_hdl, baud, 0) }
        } else {
            info!("CDC SET_LINE_CODING: {baud}");
            unsafe {
                cdc_init_port(state.ctrl_xfer, state.client_hdl, baud);
            }
            Ok(())
        }
    }

    /// Set FTDI latency timer (ms).
    #[allow(dead_code)]
    pub fn set_latency(&self, latency_ms: u8) -> Result<(), &'static str> {
        let _lock = self.ctrl_sem.lock().unwrap();
        let state = self.state.lock().unwrap();

        if !state.connected || !state.is_ftdi {
            return Err("not connected or not FTDI");
        }

        // SAFETY: ctrl_xfer and client_hdl are valid while connected.
        unsafe {
            ftdi_ctrl_request_raw(
                state.ctrl_xfer,
                state.client_hdl,
                FTDI_REQ_SET_LATENCY,
                latency_ms as u16,
                0,
            )
        }
    }

    /// Get VID/PID of the connected device.
    pub fn device_ids(&self) -> Option<(u16, u16)> {
        let state = self.state.lock().unwrap();
        if state.connected {
            Some((state.vid, state.pid))
        } else {
            None
        }
    }

    /// Set a temporary RX intercept callback for detection/verify.
    /// Pass `None` to restore normal operation.
    pub fn set_detect_rx(&self, cb: Option<fn(&[u8])>) {
        *RX_INTERCEPT.lock().unwrap() = cb;
    }

    /// Pause bulk IN polling. The current IN transfer will complete but
    /// not resubmit, freeing the USB bus for control transfers.
    pub fn pause_in(&self) {
        IN_PAUSED.store(true, Ordering::Release);
        // Give the last IN transfer time to complete and not resubmit
        std::thread::sleep(Duration::from_millis(50));
    }

    /// Resume bulk IN polling by resubmitting the IN transfer.
    pub fn resume_in(&self) {
        IN_PAUSED.store(false, Ordering::Release);
        let state = self.state.lock().unwrap();
        if state.connected && !state.in_xfer.is_null() {
            unsafe {
                usb_host_transfer_submit(state.in_xfer);
            }
        }
    }

    /// Reinitialize the port at a new baud rate.
    ///
    /// Pauses IN polling, runs the appropriate init sequence (FTDI vendor
    /// requests or CP210x vendor requests or CDC), then restarts IN.
    pub fn reinit_port(&self, baud: u32) {
        self.pause_in();

        let state = self.state.lock().unwrap();
        if !state.connected {
            drop(state);
            self.resume_in();
            return;
        }

        let ctrl_xfer = state.ctrl_xfer;
        let client_hdl = state.client_hdl;
        let is_ftdi = state.is_ftdi;
        let vid = state.vid;
        drop(state);

        unsafe {
            if is_ftdi {
                ftdi_init_port(ctrl_xfer, client_hdl, baud);
            } else if vid == 0x10C4 {
                cp210x_init_port(ctrl_xfer, client_hdl, baud);
            } else {
                cdc_init_port(ctrl_xfer, client_hdl, baud);
            }
        }

        self.resume_in();
    }
}

/// FTDI vendor control transfer (blocking).
///
/// # Safety
/// Caller must hold the ctrl_sem lock and ensure the transfer is valid.
unsafe fn ftdi_ctrl_request_raw(
    ctrl_xfer: *mut usb_transfer_t,
    client_hdl: usb_host_client_handle_t,
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

    CTRL_DONE.get().unwrap().clear();
    let err = usb_host_transfer_submit_control(client_hdl, ctrl_xfer);
    if err != ESP_OK {
        error!("CTRL submit failed: {err}");
        return Err("ctrl submit failed");
    }

    // Wait for completion (2000ms timeout)
    if !CTRL_DONE.get().unwrap().wait_ms(2000) {
        error!("CTRL transfer timeout");
        return Err("ctrl timeout");
    }

    if xfer.status == usb_transfer_status_t_USB_TRANSFER_STATUS_COMPLETED {
        Ok(())
    } else {
        Err("ctrl transfer failed")
    }
}

/// FTDI full port initialization (reset, 8N1, no flow, DTR+RTS, latency).
///
/// # Safety
/// Must be called with a valid ctrl_xfer and client_hdl.
unsafe fn ftdi_init_port(
    ctrl_xfer: *mut usb_transfer_t,
    client_hdl: usb_host_client_handle_t,
    baud: u32,
) {
    let req = |r, v, i| {
        let _ = ftdi_ctrl_request_raw(ctrl_xfer, client_hdl, r, v, i);
    };

    req(FTDI_REQ_RESET, 0, 1); // Reset
    req(FTDI_REQ_SET_DATA, 0x0008, 1); // 8N1
    req(FTDI_REQ_SET_FLOW, 0, 1); // No flow control
    req(FTDI_REQ_SET_MODEM, (1 << 8) | (1 << 9) | 3, 1); // DTR + RTS
    req(FTDI_REQ_SET_LATENCY, 16, 0); // 16ms latency
    req(FTDI_REQ_SET_EVENT_CHR, 0x0000, 1); // Disable event char
    req(FTDI_REQ_SET_ERROR_CHR, 0x0000, 1); // Disable error char
    req(FTDI_REQ_RESET, 1, 1); // Purge RX
    req(FTDI_REQ_RESET, 2, 1); // Purge TX

    // Set baud
    let wvalue = ftdi_baud_divisor(baud);
    req(FTDI_REQ_SET_BAUD, wvalue, 0);

    // configTICK_RATE_HZ = 1000, so 1 tick = 1 ms
    vTaskDelay(50);
    info!("FTDI port initialized at {baud} baud");
}

// CP210x vendor request constants
const CP210X_REQTYPE_OUT: u8 = 0x41; // Vendor, host-to-device, interface
const CP210X_REQ_IFC_ENABLE: u8 = 0x00;
#[allow(dead_code)]
const CP210X_REQ_SET_BAUDDIV: u8 = 0x01;
const CP210X_REQ_SET_LINE_CTL: u8 = 0x03;
const CP210X_REQ_SET_MHS: u8 = 0x07;
const CP210X_REQ_SET_BAUDRATE: u8 = 0x1E;

/// CP210x vendor control request (no data phase).
///
/// # Safety
/// Caller must hold the ctrl_sem lock and ensure the transfer is valid.
unsafe fn cp210x_ctrl_request(
    ctrl_xfer: *mut usb_transfer_t,
    client_hdl: usb_host_client_handle_t,
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

    CTRL_DONE.get().unwrap().clear();
    let err = usb_host_transfer_submit_control(client_hdl, ctrl_xfer);
    if err != ESP_OK {
        return Err("cp210x ctrl submit failed");
    }
    if !CTRL_DONE.get().unwrap().wait_ms(2000) {
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
/// Caller must hold the ctrl_sem lock and ensure the transfer is valid.
unsafe fn cp210x_set_baudrate(
    ctrl_xfer: *mut usb_transfer_t,
    client_hdl: usb_host_client_handle_t,
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

    // Baud rate as little-endian u32 after setup packet
    let data_ptr = xfer
        .data_buffer
        .add(std::mem::size_of::<usb_setup_packet_t>());
    let baud_data = std::slice::from_raw_parts_mut(data_ptr, 4);
    baud_data[0] = (baud & 0xFF) as u8;
    baud_data[1] = ((baud >> 8) & 0xFF) as u8;
    baud_data[2] = ((baud >> 16) & 0xFF) as u8;
    baud_data[3] = ((baud >> 24) & 0xFF) as u8;

    xfer.num_bytes = (std::mem::size_of::<usb_setup_packet_t>() + 4) as i32;
    xfer.bEndpointAddress = 0x00;

    CTRL_DONE.get().unwrap().clear();
    let err = usb_host_transfer_submit_control(client_hdl, ctrl_xfer);
    if err != ESP_OK {
        return Err("cp210x baudrate submit failed");
    }
    if !CTRL_DONE.get().unwrap().wait_ms(2000) {
        return Err("cp210x baudrate timeout");
    }
    if xfer.status == usb_transfer_status_t_USB_TRANSFER_STATUS_COMPLETED {
        Ok(())
    } else {
        Err("cp210x baudrate transfer failed")
    }
}

/// CP210x port initialization.
///
/// Enables the interface, sets baud rate, line control (8N1), and
/// asserts DTR+RTS via the modem handshake register.
///
/// # Safety
/// Must be called with a valid ctrl_xfer and client_hdl.
unsafe fn cp210x_init_port(
    ctrl_xfer: *mut usb_transfer_t,
    client_hdl: usb_host_client_handle_t,
    baud: u32,
) {
    let iface: u16 = 0; // Interface 0 = Enhanced port (CAT on FT-891)

    // IFC_ENABLE: enable the UART (wValue=1)
    let _ = cp210x_ctrl_request(ctrl_xfer, client_hdl, CP210X_REQ_IFC_ENABLE, 1, iface);

    // SET_BAUDRATE: 4-byte little-endian baud rate
    let _ = cp210x_set_baudrate(ctrl_xfer, client_hdl, baud, iface);

    // SET_LINE_CTL: 8 data bits, 2 stop bits, no parity
    // CP210x wValue: stop_bits | parity | data_bits
    //   0x0800 = 8 data bits, 0x0000 = no parity, 0x0002 = 2 stop bits
    // 8N2 = 0x0802 (required by FT-891 and other Yaesu radios)
    let _ = cp210x_ctrl_request(
        ctrl_xfer,
        client_hdl,
        CP210X_REQ_SET_LINE_CTL,
        0x0802,
        iface,
    );

    // SET_MHS: assert DTR+RTS
    // wValue: bit0=DTR value, bit1=RTS value, bit8=DTR mask, bit9=RTS mask
    let _ = cp210x_ctrl_request(ctrl_xfer, client_hdl, CP210X_REQ_SET_MHS, 0x0303, iface);

    vTaskDelay(50);
    info!("CP210x port initialized at {baud} baud (8N1, DTR+RTS)");
}

/// CDC ACM port initialization (CH340, STM32 CDC, generic).
///
/// Sends SET_LINE_CODING (baud, 8N1) and SET_CONTROL_LINE_STATE (DTR+RTS).
///
/// # Safety
/// Must be called with a valid ctrl_xfer and client_hdl.
unsafe fn cdc_init_port(
    ctrl_xfer: *mut usb_transfer_t,
    client_hdl: usb_host_client_handle_t,
    baud: u32,
) {
    if ctrl_xfer.is_null() || client_hdl.is_null() {
        return;
    }

    // CDC SET_LINE_CODING (0x20): 7 bytes = baud(4) + stop(1) + parity(1) + data_bits(1)
    let xfer = &mut *ctrl_xfer;
    let setup = xfer.data_buffer as *mut usb_setup_packet_t;
    (*setup).__bindgen_anon_1.bmRequestType = 0x21; // Host-to-device, class, interface
    (*setup).__bindgen_anon_1.bRequest = 0x20; // SET_LINE_CODING
    (*setup).__bindgen_anon_1.wValue = 0;
    (*setup).__bindgen_anon_1.wIndex = 0;
    (*setup).__bindgen_anon_1.wLength = 7;

    let data_ptr = xfer
        .data_buffer
        .add(std::mem::size_of::<usb_setup_packet_t>());
    let line_coding = std::slice::from_raw_parts_mut(data_ptr, 7);
    line_coding[0] = (baud & 0xFF) as u8;
    line_coding[1] = ((baud >> 8) & 0xFF) as u8;
    line_coding[2] = ((baud >> 16) & 0xFF) as u8;
    line_coding[3] = ((baud >> 24) & 0xFF) as u8;
    line_coding[4] = 0; // 1 stop bit
    line_coding[5] = 0; // No parity
    line_coding[6] = 8; // 8 data bits

    xfer.num_bytes = (std::mem::size_of::<usb_setup_packet_t>() + 7) as i32;
    xfer.bEndpointAddress = 0x00;

    CTRL_DONE.get().unwrap().clear();
    let err = usb_host_transfer_submit_control(client_hdl, ctrl_xfer);
    if err != ESP_OK {
        warn!("CDC SET_LINE_CODING submit failed: {err}");
    } else if !CTRL_DONE.get().unwrap().wait_ms(2000) {
        warn!("CDC SET_LINE_CODING timeout");
    }

    // CDC SET_CONTROL_LINE_STATE (0x22): assert DTR + RTS
    (*setup).__bindgen_anon_1.bmRequestType = 0x21;
    (*setup).__bindgen_anon_1.bRequest = 0x22;
    (*setup).__bindgen_anon_1.wValue = 0x0003; // DTR=1, RTS=1
    (*setup).__bindgen_anon_1.wIndex = 0;
    (*setup).__bindgen_anon_1.wLength = 0;

    xfer.num_bytes = std::mem::size_of::<usb_setup_packet_t>() as i32;

    CTRL_DONE.get().unwrap().clear();
    let err = usb_host_transfer_submit_control(client_hdl, ctrl_xfer);
    if err != ESP_OK {
        warn!("CDC SET_CONTROL_LINE_STATE submit failed: {err}");
    } else if !CTRL_DONE.get().unwrap().wait_ms(2000) {
        warn!("CDC SET_CONTROL_LINE_STATE timeout");
    }

    vTaskDelay(50);
    info!("CDC port initialized at {baud} baud (8N1, DTR+RTS)");
}

// ---------------------------------------------------------------
// Transfer callbacks (called from USB host event loop context)
// ---------------------------------------------------------------

unsafe extern "C" fn in_xfer_cb(transfer: *mut usb_transfer_t) {
    let xfer = &*transfer;

    if xfer.status != usb_transfer_status_t_USB_TRANSFER_STATUS_COMPLETED {
        if xfer.status == usb_transfer_status_t_USB_TRANSFER_STATUS_CANCELED {
            return;
        }
        warn!("Bulk IN error: status={}", xfer.status);
        usb_host_transfer_submit(transfer);
        return;
    }

    let data = std::slice::from_raw_parts(xfer.data_buffer, xfer.actual_num_bytes as usize);

    // FTDI: strip 2-byte modem status prefix
    let is_ftdi = xfer.context as usize == 1;
    let payload = if is_ftdi {
        if data.len() <= 2 {
            usb_host_transfer_submit(transfer);
            return;
        }
        &data[2..]
    } else {
        data
    };

    // Dispatch to intercept or normal callback
    let intercept = RX_INTERCEPT.lock().ok().and_then(|g| *g);
    if let Some(cb) = intercept {
        cb(payload);
    } else if let Some(tx) = EVENT_TX.get() {
        let _ = tx.send(BridgeEvent::UsbData(payload.to_vec()));
    }

    // Resubmit for continuous reception (unless paused for detection)
    if !IN_PAUSED.load(Ordering::Relaxed) {
        usb_host_transfer_submit(transfer);
    }
}

unsafe extern "C" fn out_xfer_cb(transfer: *mut usb_transfer_t) {
    let xfer = &*transfer;
    if xfer.status != usb_transfer_status_t_USB_TRANSFER_STATUS_COMPLETED {
        error!("Bulk OUT error: status={}", xfer.status);
    }
    if let Some(sig) = OUT_DONE.get() {
        sig.signal();
    }
}

unsafe extern "C" fn ctrl_xfer_cb(transfer: *mut usb_transfer_t) {
    let xfer = &*transfer;
    if xfer.status != usb_transfer_status_t_USB_TRANSFER_STATUS_COMPLETED {
        warn!("CTRL transfer error: status={}", xfer.status);
    }
    if let Some(sig) = CTRL_DONE.get() {
        sig.signal();
    }
}

// ---------------------------------------------------------------
// Descriptor parsing
// ---------------------------------------------------------------

/// Parse bulk IN and OUT endpoint addresses from the device descriptors.
///
/// # Safety
/// dev_hdl must be a valid, open USB device handle.
unsafe fn parse_endpoints(dev_hdl: usb_device_handle_t) -> Option<(u8, u8)> {
    let mut config_desc: *const usb_config_desc_t = std::ptr::null();
    if usb_host_get_active_config_descriptor(dev_hdl, &mut config_desc) != ESP_OK {
        return None;
    }

    let total_len = (*config_desc).__bindgen_anon_1.wTotalLength as usize;
    let base = config_desc as *const u8;
    let mut offset = 0usize;
    let mut in_ep = 0u8;
    let mut out_ep = 0u8;

    while offset < total_len {
        let desc = base.add(offset) as *const usb_standard_desc_t;
        let len = (*desc).__bindgen_anon_1.bLength as usize;
        if len == 0 {
            break;
        }

        if (*desc).__bindgen_anon_1.bDescriptorType == USB_B_DESCRIPTOR_TYPE_ENDPOINT as u8 {
            let ep = desc as *const usb_ep_desc_t;
            let attrs = (*ep).__bindgen_anon_1.bmAttributes & USB_BM_ATTRIBUTES_XFERTYPE_MASK as u8;
            if attrs == USB_BM_ATTRIBUTES_XFER_BULK as u8 {
                let addr = (*ep).__bindgen_anon_1.bEndpointAddress;
                if addr & 0x80 != 0 && in_ep == 0 {
                    in_ep = addr;
                    info!("Bulk IN endpoint: 0x{addr:02X}");
                } else if addr & 0x80 == 0 && out_ep == 0 {
                    out_ep = addr;
                    info!("Bulk OUT endpoint: 0x{addr:02X}");
                }
                // Stop after first complete pair (interface 0 on dual-port chips)
                if in_ep != 0 && out_ep != 0 {
                    break;
                }
            }
        }

        offset += len;
    }

    if in_ep != 0 && out_ep != 0 {
        Some((in_ep, out_ep))
    } else {
        error!("Could not find bulk endpoints");
        None
    }
}

// ---------------------------------------------------------------
// Device connect/disconnect handling
// ---------------------------------------------------------------

/// Handle a newly connected USB device.
///
/// # Safety
/// Must be called from the client task context with valid state pointer.
unsafe fn handle_device_connected(state_ptr: *const Mutex<UsbState>, dev_addr: u8) {
    let state_mtx = &*state_ptr;
    let mut state = state_mtx.lock().unwrap();

    // Open device
    let mut dev_hdl: usb_device_handle_t = std::ptr::null_mut();
    if usb_host_device_open(state.client_hdl, dev_addr, &mut dev_hdl) != ESP_OK {
        error!("Failed to open USB device");
        return;
    }

    // Check VID/PID
    let mut dev_desc: *const usb_device_desc_t = std::ptr::null();
    usb_host_get_device_descriptor(dev_hdl, &mut dev_desc);
    let vid = (*dev_desc).__bindgen_anon_1.idVendor;
    let pid = (*dev_desc).__bindgen_anon_1.idProduct;
    let class = (*dev_desc).__bindgen_anon_1.bDeviceClass;

    // Always log VID/PID up front so it shows in the serial monitor even if
    // chip matching, endpoint parsing, or interface claim fails downstream.
    info!("USB device enumerated: VID=0x{vid:04X} PID=0x{pid:04X} class=0x{class:02X}");

    // Hubs reach this path because the enum filter allows them through —
    // we need them enumerated to see the downstream CAT chip on the FTX-1
    // and similar radios. But we must NOT try to claim a hub as a serial
    // device: parse_endpoints would either misread the hub's interrupt EP
    // as a bulk IN, or interface_claim would fail. Either way the hub
    // descriptor's bDeviceClass is the canonical signal. USB_CLASS_HUB == 0x09.
    if class == 0x09 {
        info!("Skipping USB hub (class 0x09) — keep enumerated, do not claim as CAT");
        usb_host_device_close(state.client_hdl, dev_hdl);
        return;
    }

    let chip = match match_chip(vid, pid) {
        Some(c) => c,
        None => {
            warn!("Unsupported USB device (VID=0x{vid:04X} PID=0x{pid:04X}) — add to CABLE_HINTS / SUPPORTED_CHIPS to enable");
            usb_host_device_close(state.client_hdl, dev_hdl);
            return;
        }
    };

    info!("{} matched (VID=0x{vid:04X} PID=0x{pid:04X})", chip.name);

    // Parse endpoints
    let (in_ep, out_ep) = match parse_endpoints(dev_hdl) {
        Some(eps) => eps,
        None => {
            usb_host_device_close(state.client_hdl, dev_hdl);
            return;
        }
    };

    // Claim interface 0
    if usb_host_interface_claim(state.client_hdl, dev_hdl, 0, 0) != ESP_OK {
        error!("Failed to claim interface");
        usb_host_device_close(state.client_hdl, dev_hdl);
        return;
    }

    // Allocate transfers
    let mut in_xfer: *mut usb_transfer_t = std::ptr::null_mut();
    let mut out_xfer: *mut usb_transfer_t = std::ptr::null_mut();
    let mut ctrl_xfer: *mut usb_transfer_t = std::ptr::null_mut();
    usb_host_transfer_alloc(USB_RX_BUF_SIZE, 0, &mut in_xfer);
    usb_host_transfer_alloc(USB_TX_BUF_SIZE, 0, &mut out_xfer);
    usb_host_transfer_alloc(USB_CTRL_BUF_SIZE, 0, &mut ctrl_xfer);

    // Configure IN transfer
    (*in_xfer).device_handle = dev_hdl;
    (*in_xfer).bEndpointAddress = in_ep;
    (*in_xfer).callback = Some(in_xfer_cb);
    (*in_xfer).num_bytes = USB_RX_BUF_SIZE as i32;
    (*in_xfer).context = if chip.is_ftdi {
        std::ptr::dangling_mut()
    } else {
        std::ptr::null_mut()
    };

    // Configure OUT transfer
    (*out_xfer).device_handle = dev_hdl;
    (*out_xfer).bEndpointAddress = out_ep;
    (*out_xfer).callback = Some(out_xfer_cb);

    // Configure CTRL transfer
    (*ctrl_xfer).device_handle = dev_hdl;
    (*ctrl_xfer).callback = Some(ctrl_xfer_cb);

    state.dev_hdl = dev_hdl;
    state.in_xfer = in_xfer;
    state.out_xfer = out_xfer;
    state.ctrl_xfer = ctrl_xfer;
    state.in_ep_addr = in_ep;
    state.out_ep_addr = out_ep;
    state.is_ftdi = chip.is_ftdi;
    state.vid = vid;
    state.pid = pid;

    // Port init (before marking connected, uses ctrl transfers)
    if chip.is_ftdi {
        ftdi_init_port(ctrl_xfer, state.client_hdl, DEFAULT_BAUD_RATE);
    } else if vid == 0x10C4 {
        cp210x_init_port(ctrl_xfer, state.client_hdl, DEFAULT_BAUD_RATE);
    } else {
        cdc_init_port(ctrl_xfer, state.client_hdl, DEFAULT_BAUD_RATE);
    }

    // Start bulk IN reception
    if usb_host_transfer_submit(in_xfer) != ESP_OK {
        error!("Failed to submit IN transfer");
    } else {
        info!("Bulk IN polling started on EP 0x{in_ep:02X}");
    }

    state.connected = true;
    info!("CAT link ready ({})", chip.name);

    // Notify main loop
    if let Some(tx) = EVENT_TX.get() {
        let _ = tx.send(BridgeEvent::UsbConnected { vid, pid });
    }
}

/// Handle USB device disconnection.
///
/// # Safety
/// Must be called from the client task context.
unsafe fn handle_device_disconnected(state_ptr: *const Mutex<UsbState>) {
    let state_mtx = &*state_ptr;
    let mut state = state_mtx.lock().unwrap();

    warn!("USB device disconnected");
    state.connected = false;

    if !state.in_xfer.is_null() {
        usb_host_transfer_free(state.in_xfer);
        state.in_xfer = std::ptr::null_mut();
    }
    if !state.out_xfer.is_null() {
        usb_host_transfer_free(state.out_xfer);
        state.out_xfer = std::ptr::null_mut();
    }
    if !state.ctrl_xfer.is_null() {
        usb_host_transfer_free(state.ctrl_xfer);
        state.ctrl_xfer = std::ptr::null_mut();
    }

    if !state.dev_hdl.is_null() {
        usb_host_interface_release(state.client_hdl, state.dev_hdl, 0);
        usb_host_device_close(state.client_hdl, state.dev_hdl);
        state.dev_hdl = std::ptr::null_mut();
    }

    state.vid = 0;
    state.pid = 0;

    if let Some(tx) = EVENT_TX.get() {
        let _ = tx.send(BridgeEvent::UsbDisconnected);
    }
}

// ---------------------------------------------------------------
// USB host threads
// ---------------------------------------------------------------

/// USB host library daemon thread (handles library events).
fn usb_host_daemon_thread() {
    info!("USB host daemon started");
    loop {
        // SAFETY: usb_host_lib_handle_events is safe to call from any thread.
        unsafe {
            let mut event_flags: u32 = 0;
            usb_host_lib_handle_events(u32::MAX, &mut event_flags);
        }
    }
}

/// USB client event callback.
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
            // Append to queue — multiple devices may enumerate from one hub.
            if let Ok(mut q) = PENDING_QUEUE.lock() {
                q.push_back(addr);
            }
        }
        usb_host_client_event_t_USB_HOST_CLIENT_EVENT_DEV_GONE => {
            info!("USB device gone");
            handle_device_disconnected(arg as *const Mutex<UsbState>);
        }
        _ => {}
    }
}

/// USB client thread (handles device enumeration and events).
fn usb_client_thread(state_ptr: *const Mutex<UsbState>) {
    info!("USB client task started");

    // SAFETY: state_ptr is a leaked Box pointer that lives for the program's lifetime.
    // The USB client registration and event loop require raw FFI calls.
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
        let err = usb_host_client_register(&client_config, &mut client_hdl);
        if err != ESP_OK {
            panic!("USB client register failed: {err}");
        }

        // Store client handle in state
        {
            let mut state = (*state_ptr).lock().unwrap();
            state.client_hdl = client_hdl;
        }

        info!("USB client registered, scanning for devices...");

        loop {
            usb_host_client_handle_events(client_hdl, u32::MAX);

            // Don't start a new setup while one is already in flight.
            // handle_device_connected mutates shared state (dev_hdl,
            // in/out/ctrl transfer pointers) and runs blocking control
            // transfers — two of them in parallel would corrupt that state.
            if SETUP_IN_PROGRESS.load(Ordering::Acquire) {
                continue;
            }

            // Pop the next pending device address, if any.
            let addr = match PENDING_QUEUE.lock().ok().and_then(|mut q| q.pop_front()) {
                Some(a) => a,
                None => continue,
            };

            // If we're already bound to a device, drop subsequent addresses.
            // SETUP_IN_PROGRESS already guards against the dev_setup race; the
            // remaining lock holders (send / set_baud / reinit_port) finish
            // quickly enough that a plain lock won't meaningfully stall the
            // event loop.
            let busy = {
                let s = (*state_ptr).lock().unwrap();
                s.connected || !s.dev_hdl.is_null()
            };
            if busy {
                info!("Already bound to a USB device, ignoring addr={addr}");
                continue;
            }

            SETUP_IN_PROGRESS.store(true, Ordering::Release);
            let sp = state_ptr as usize;
            // 8192 (was 4096): hub support enables deeper call paths in
            // the USB Host Library, and chip-specific init (FTDI/CP210x)
            // chains several blocking control transfers whose waiters
            // each consume a frame of stack via FreeRTOS task notify.
            let spawn_result = std::thread::Builder::new()
                .name("dev_setup".into())
                .stack_size(8192)
                .spawn(move || {
                    // Guard always clears SETUP_IN_PROGRESS — handles early
                    // return paths in handle_device_connected and any
                    // panic-unwind without leaving the event loop wedged.
                    let _guard = SetupInProgressGuard;
                    // SAFETY: inherits the outer unsafe block's guarantees —
                    // sp is a leaked Box pointer valid for the program lifetime.
                    handle_device_connected(sp as *const Mutex<UsbState>, addr);
                });
            if spawn_result.is_err() {
                error!("Failed to spawn dev_setup thread for addr={addr}");
                SETUP_IN_PROGRESS.store(false, Ordering::Release);
            }
        }
    }
}
