//! Radio auto-detection via USB CAT probing.
//!
//! Detection flow:
//!   1. USB device enumerates — caller provides VID/PID
//!   2. VID/PID lookup gives candidate baud rates to try
//!   3. At each baud: send CI-V identify, wait 500ms for response
//!   4. If no CI-V response: send Kenwood "ID;", wait 500ms
//!   5. Quansheng UV-K5 CAT only (matched by VID/PID): if "ID;" is not
//!      answered, send "FA;" and accept an 11-digit "FAnnnnnnnnnnn;" reply
//!      as a Kenwood-dialect radio with the synthetic ID `IDQSK5`
//!   6. Report result via event channel

use std::sync::{Arc, Mutex};

use ::log::{info, warn};

use crate::protocol::RadioProtocol;
use crate::rtos;
use crate::usb::UsbHost;

/// QRP Labs radio variant detected during auto-detection.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub enum QrpLabsVariant {
    /// Not a QRP Labs radio (or not identified as one).
    #[default]
    None,
    /// QCX/QCX+/QCX-mini: CW-only, no RC;, no PC, has TB;/QU;/OM;
    Qcx,
    /// QMX/QMX+: multi-mode, has RC;, PC read-only, no TB;, has VN;
    Qmx,
}

/// VID/PID to baud rate hint mapping.
struct CableHint {
    vid: u16,
    pid: u16,
    name: &'static str,
    bauds: &'static [u32],
}

const CABLE_HINTS: &[CableHint] = &[
    CableHint {
        vid: 0x0403,
        pid: 0x6015,
        name: "FTDI FT-X",
        bauds: &[38400, 9600],
    },
    CableHint {
        vid: 0x0403,
        pid: 0x6001,
        name: "FTDI FT232",
        bauds: &[38400, 9600, 19200],
    },
    CableHint {
        vid: 0x10C4,
        pid: 0xEA60,
        name: "CP2102",
        bauds: &[4800, 19200, 9600, 38400],
    },
    // Yaesu FT-891 built-in USB (CP2105 dual-port, Enhanced port = CAT)
    // Yaesu FT-891 built-in USB (CP2105 dual-port, Enhanced port = CAT)
    CableHint {
        vid: 0x10C4,
        pid: 0xEA70,
        name: "CP2105",
        bauds: &[38400, 4800, 19200, 9600],
    },
    CableHint {
        vid: 0x1A86,
        pid: 0x7523,
        name: "CH340",
        bauds: &[9600, 19200, 38400],
    },
    // QRP Labs QMX/QMX+ — STM32 CDC-ACM virtual COM port (baud rate ignored)
    CableHint {
        vid: 0x0483,
        pid: 0x5740,
        name: "STM32 CDC",
        bauds: &[38400],
    },
    // Quansheng UV-K1 / UV-K5 V3 (F4HWN CAT build) — native CDC-ACM, 38400 8N1.
    // Has no `ID;` command; detected via the `FA;` fallback probe.
    CableHint {
        vid: QUANSHENG_VID,
        pid: QUANSHENG_PID,
        name: "Quansheng UV-K5 CAT",
        bauds: &[38400],
    },
];

/// Quansheng UV-K1 / UV-K5 V3 USB-C CDC-ACM identifiers (F4HWN firmware).
pub const QUANSHENG_VID: u16 = 0x36B7;
pub const QUANSHENG_PID: u16 = 0xFFFF;

/// Synthetic Kenwood-style ID reported for a Quansheng UV-K5 CAT radio.
/// The radio has no `ID;` command, so detection fabricates this string
/// after a successful `FA;` probe. The app's `RigProtocolDetector` mirrors it.
pub const QUANSHENG_ID: &str = "IDQSK5";

fn is_quansheng(vid: u16, pid: u16) -> bool {
    vid == QUANSHENG_VID && pid == QUANSHENG_PID
}

const DEFAULT_BAUDS: &[u32] = &[38400, 9600, 19200, 4800, 115200];

/// Result of radio auto-detection.
#[derive(Clone, Debug)]
pub struct DetectResult {
    pub protocol: RadioProtocol,
    pub baud_rate: u32,
    pub id_string: String,
    pub civ_address: Option<u8>,
    /// QRP Labs radio variant, if detected.
    pub qrp_variant: QrpLabsVariant,
    /// Number of digits in the FA/FB frequency command (9 = Yaesu, 11 = Kenwood/Elecraft).
    pub freq_digits: u8,
}

impl DetectResult {
    /// Human-readable radio name, or None if unrecognized.
    pub fn radio_name(&self) -> Option<&'static str> {
        match self.protocol {
            RadioProtocol::Kenwood => match self.qrp_variant {
                QrpLabsVariant::Qcx => Some("QRP Labs QCX"),
                QrpLabsVariant::Qmx => Some("QRP Labs QMX"),
                QrpLabsVariant::None => kenwood_id_name(&self.id_string),
            },
            RadioProtocol::Civ => civ_addr_name(self.civ_address.unwrap_or(0)),
            _ => None,
        }
    }
}

/// Yaesu Kenwood-compatible rigs respond to `ID;` with `ID0xxxx` (4 digits)
/// and use 9-digit FA/FB frequency commands. Kenwood/Elecraft respond with
/// `IDxxx` (3 digits) and use 11-digit FA/FB.
fn is_yaesu_id(id: &str) -> bool {
    // "ID" + 4 digits = Yaesu; "ID" + 3 digits = Kenwood/Elecraft.
    id.len() == 6 && id.starts_with("ID") && id[2..].chars().all(|c| c.is_ascii_digit())
}

fn kenwood_id_name(id: &str) -> Option<&'static str> {
    match id {
        "ID017" => Some("Elecraft K3/KX"),
        "ID019" => Some("Kenwood TS-990"),
        "ID020" => Some("Kenwood TS-480"),
        "ID029" => Some("Kenwood TS-890"),
        "ID0650" => Some("Yaesu FT-891"),
        "ID0840" => Some("Yaesu FTX-1"),
        QUANSHENG_ID => Some("Quansheng UV-K5"),
        _ => None,
    }
}

fn civ_addr_name(addr: u8) -> Option<&'static str> {
    match addr {
        0x70 => Some("Xiegu G90"),
        0x76 => Some("Xiegu G106"),
        0x94 => Some("Icom IC-705"),
        0x98 => Some("Icom IC-905"),
        0xA4 => Some("Icom IC-7300"),
        _ => None,
    }
}

/// Get candidate baud rates for a USB VID/PID.
fn candidate_bauds(vid: u16, pid: u16) -> &'static [u32] {
    for hint in CABLE_HINTS {
        if hint.vid == vid && hint.pid == pid {
            info!("Cable: {}", hint.name);
            return hint.bauds;
        }
    }
    DEFAULT_BAUDS
}

/// Shared buffer for the RX intercept callback.
///
/// The `fn` pointer constraint on `set_detect_rx` prevents closures, so we
/// use a global Mutex to bridge the callback to the local Arc<Mutex<Vec<u8>>>.
static DETECT_BUF: Mutex<Option<Arc<Mutex<Vec<u8>>>>> = Mutex::new(None);

fn detect_rx_cb(data: &[u8]) {
    if let Ok(guard) = DETECT_BUF.lock() {
        if let Some(ref buf) = *guard {
            if let Ok(mut inner) = buf.lock() {
                inner.extend_from_slice(data);
            }
        }
    }
}

/// Run radio detection. Blocking — call from a dedicated thread.
///
/// Temporarily intercepts USB RX via `usb.set_detect_rx()`.
/// Restores normal RX on return.
pub fn detect(usb: &UsbHost, vid: u16, pid: u16) -> Option<DetectResult> {
    let bauds = candidate_bauds(vid, pid);

    info!("Detection started for VID=0x{vid:04X} PID=0x{pid:04X}");

    // Wait for USB IN transfers to settle
    rtos::delay_ticks(500);

    // Set up RX intercept buffer
    let rx_buf: Arc<Mutex<Vec<u8>>> = Arc::new(Mutex::new(Vec::new()));
    *DETECT_BUF.lock().unwrap() = Some(rx_buf.clone());

    usb.set_detect_rx(Some(detect_rx_cb));

    let mut result = None;
    let mut last_baud = bauds[0];

    for &baud in bauds {
        info!("Trying baud {baud}");

        // Reinitialize the FTDI port at this baud — tears down IN polling,
        // does all CTRL transfers with no bus contention, then restarts IN.
        // This avoids the FT232 bug where CTRL transfers stall when bulk IN
        // is active.
        usb.reinit_port(baud);
        last_baud = baud;

        // Settle time + drain stale data
        rtos::delay_ticks(200);
        rx_buf.lock().unwrap().clear();

        // Try CI-V identify first — CI-V frames (FE FE ... FD) are
        // unambiguous, while Kenwood "ID;" can false-positive from echoes.
        let _ = usb.send(&[0xFE, 0xFE, 0x00, 0xE0, 0x19, 0x00, 0xFD]);
        if let Some((addr, id)) = wait_for_civ_id(&rx_buf, 500) {
            result = Some(DetectResult {
                protocol: RadioProtocol::Civ,
                baud_rate: baud,
                id_string: id,
                civ_address: Some(addr),
                qrp_variant: QrpLabsVariant::None,
                freq_digits: 11, // CI-V uses BCD, not relevant here
            });
            break;
        }

        // Try Kenwood "ID;"
        rx_buf.lock().unwrap().clear();
        let _ = usb.send(b"ID;");
        if let Some(id) = wait_for_kenwood_id(&rx_buf, 500) {
            // Check for QRP Labs radios (both respond to ID; with ID020)
            let mut qrp_variant = QrpLabsVariant::None;
            let mut id_str = id.clone();
            if id == "ID020" {
                // Try OM; first — QCX returns "OMQC;"
                rtos::delay_ticks(50);
                rx_buf.lock().unwrap().clear();
                let _ = usb.send(b"OM;");
                if let Some(om) = wait_for_kenwood_response(&rx_buf, b"OM", 500) {
                    if om.contains("QC") {
                        qrp_variant = QrpLabsVariant::Qcx;
                        id_str = format!("OM{om}");
                        info!("QCX detected via OM response: {}", id_str);
                    }
                }

                // If not QCX, try VN; — QMX returns "VN1_02_000QMX;"
                if qrp_variant == QrpLabsVariant::None {
                    rtos::delay_ticks(50);
                    rx_buf.lock().unwrap().clear();
                    let _ = usb.send(b"VN;");
                    if let Some(vn) = wait_for_kenwood_response(&rx_buf, b"VN", 500) {
                        if vn.contains("QMX") {
                            qrp_variant = QrpLabsVariant::Qmx;
                            id_str = format!("VN{vn}");
                            info!("QMX detected via VN response: {}", id_str);
                        }
                    }
                }
            }

            // Yaesu radios use a 4-digit ID (e.g. ID0650 FT-891, ID0840 FTX-1)
            // and 9-digit FA/FB commands. Kenwood/Elecraft use a 3-digit ID
            // (e.g. ID020 TS-480, ID017 K3) and 11-digit FA/FB.
            let freq_digits = if is_yaesu_id(&id) { 9 } else { 11 };

            result = Some(DetectResult {
                protocol: RadioProtocol::Kenwood,
                baud_rate: baud,
                id_string: id_str,
                civ_address: None,
                qrp_variant,
                freq_digits,
            });
            break;
        }

        // Quansheng UV-K5 CAT (F4HWN build): Kenwood dialect but no `ID;`.
        // Only probed when the USB IDs say it's a Quansheng so other rigs
        // don't pay the extra 500 ms per baud.
        if is_quansheng(vid, pid) {
            rx_buf.lock().unwrap().clear();
            let _ = usb.send(b"FA;");
            if let Some(freq) = wait_for_kenwood_freq(&rx_buf, 500) {
                info!("Quansheng detected via FA response: {freq}");
                result = Some(DetectResult {
                    protocol: RadioProtocol::Kenwood,
                    baud_rate: baud,
                    id_string: QUANSHENG_ID.to_string(),
                    civ_address: None,
                    qrp_variant: QrpLabsVariant::None,
                    freq_digits: 11,
                });
                break;
            }
        }
    }

    // Restore normal operation
    usb.set_detect_rx(None);
    *DETECT_BUF.lock().unwrap() = None;

    if let Some(ref res) = result {
        info!(
            "Radio detected: {} ({})",
            res.id_string,
            res.protocol.as_str_name()
        );
    } else {
        if last_baud != bauds[0] {
            usb.reinit_port(bauds[0]);
        }
        warn!("Detection failed, defaulting to {} baud", bauds[0]);
    }

    result
}

/// Wait for a Kenwood ID response (e.g., "ID020;") in the RX buffer.
fn wait_for_kenwood_id(buf: &Arc<Mutex<Vec<u8>>>, timeout_ms: u32) -> Option<String> {
    let deadline = rtos::tick_count() + timeout_ms;

    loop {
        if rtos::tick_count() >= deadline {
            return None;
        }

        rtos::delay_ticks(10);

        let data = buf.lock().unwrap();
        // Look for "IDnnn;" pattern — must have digits between ID and ;
        // (bare "ID;" is our own echo, not a valid radio response)
        if let Some(start) = data.windows(2).position(|w| w == b"ID") {
            if let Some(end) = data[start..].iter().position(|&b| b == b';') {
                if end > 2 {
                    let id = String::from_utf8_lossy(&data[start..start + end]).to_string();
                    return Some(id);
                }
            }
        }
    }
}

/// Wait for a Kenwood `FAnnnnnnnnnnn;` frequency report (exactly 11 ASCII
/// digits) in the RX buffer. A bare `FA;` (our own echo on loopback cables)
/// or any shorter/non-numeric body is ignored, and every `FA` occurrence is
/// examined so an echo ahead of the real reply doesn't mask it.
fn wait_for_kenwood_freq(buf: &Arc<Mutex<Vec<u8>>>, timeout_ms: u32) -> Option<String> {
    let deadline = rtos::tick_count() + timeout_ms;

    loop {
        if rtos::tick_count() >= deadline {
            return None;
        }

        rtos::delay_ticks(10);

        let data = buf.lock().unwrap();
        for start in 0..data.len().saturating_sub(1) {
            if &data[start..start + 2] != b"FA" {
                continue;
            }
            let body = &data[start + 2..];
            let Some(end) = body.iter().position(|&b| b == b';') else {
                continue;
            };
            if end == 11 && body[..end].iter().all(|b| b.is_ascii_digit()) {
                return Some(String::from_utf8_lossy(&body[..end]).to_string());
            }
        }
    }
}

/// Wait for a Kenwood response with a given prefix (e.g., b"OM") in the RX buffer.
/// Returns the value between the prefix and the terminating ';'.
fn wait_for_kenwood_response(
    buf: &Arc<Mutex<Vec<u8>>>,
    prefix: &[u8],
    timeout_ms: u32,
) -> Option<String> {
    let deadline = rtos::tick_count() + timeout_ms;

    loop {
        if rtos::tick_count() >= deadline {
            return None;
        }

        rtos::delay_ticks(10);

        let data = buf.lock().unwrap();
        if let Some(start) = data.windows(prefix.len()).position(|w| w == prefix) {
            let after = start + prefix.len();
            if let Some(end) = data[after..].iter().position(|&b| b == b';') {
                if end > 0 {
                    let val = String::from_utf8_lossy(&data[after..after + end]).to_string();
                    return Some(val);
                }
            }
        }
    }
}

/// Wait for a CI-V identify response in the RX buffer.
fn wait_for_civ_id(buf: &Arc<Mutex<Vec<u8>>>, timeout_ms: u32) -> Option<(u8, String)> {
    let deadline = rtos::tick_count() + timeout_ms;

    loop {
        if rtos::tick_count() >= deadline {
            return None;
        }

        rtos::delay_ticks(10);

        let data = buf.lock().unwrap();
        // Look for a valid CI-V response: FE FE <to> <from> ... FD
        // The response to our identify (cmd 0x19) is:
        //   FE FE E0 <radio_addr> 19 00 <id_data...> FD
        // We extract <radio_addr> (the "from" field, byte[3]).
        for idx in 0..data.len().saturating_sub(7) {
            if data[idx] != 0xFE || data[idx + 1] != 0xFE {
                continue;
            }
            let to_addr = data[idx + 2];
            let from_addr = data[idx + 3];

            // Skip our own echo (we sent to 0x00 from 0xE0)
            if to_addr == 0x00 || from_addr == 0xE0 {
                continue;
            }

            // Must be addressed to us (0xE0) and terminated by FD
            if to_addr != 0xE0 {
                continue;
            }
            if !data[idx + 4..].contains(&0xFD) {
                continue;
            }

            let id = format!("{from_addr:02X}");
            return Some((from_addr, id));
        }
    }
}
