//! Radio auto-detection via USB CAT probing.
//!
//! Detection flow:
//!   1. USB device enumerates — caller provides VID/PID
//!   2. VID/PID lookup gives candidate baud rates to try
//!   3. At each baud: send Kenwood "ID;", wait 500ms for response
//!   4. If no Kenwood response: send CI-V identify, wait 500ms
//!   5. Report result via event channel

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
    // Quansheng UV-K1 native USB-C (CDC-ACM VCP; baud nominal). The CAT fork
    // runs 38400 8N1 and only answers IF; (no ID;), so detection lands via
    // the IF; probe below.
    CableHint {
        vid: 0x36B7,
        pid: 0xFFFF,
        name: "UV-K1 USB",
        bauds: &[38400],
    },
];

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
            RadioProtocol::ProtoKenwood => match self.qrp_variant {
                QrpLabsVariant::Qcx => Some("QRP Labs QCX"),
                QrpLabsVariant::Qmx => Some("QRP Labs QMX"),
                QrpLabsVariant::None => kenwood_id_name(&self.id_string),
            },
            RadioProtocol::ProtoCiv => civ_addr_name(self.civ_address.unwrap_or(0)),
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
        "UVK1CAT" => Some("Quansheng UV-K1 (CAT)"),
        "ID017" => Some("Elecraft K3/KX"),
        "ID019" => Some("Kenwood TS-990"),
        "ID020" => Some("Kenwood TS-480"),
        "ID029" => Some("Kenwood TS-890"),
        "ID0650" => Some("Yaesu FT-891"),
        "ID0840" => Some("Yaesu FTX-1"),
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

/// Run auto-detection on `radio`. Blocking — call from a dedicated thread.
///
/// Captures that radio's inbound bytes (per-slot capture) for the probe
/// window, restoring normal RX flow on return.
pub fn detect(usb: &UsbHost, radio: usize, vid: u16, pid: u16) -> Option<DetectResult> {
    let bauds = candidate_bauds(vid, pid);
    info!("Detection started (radio {radio}) for VID=0x{vid:04X} PID=0x{pid:04X}");

    rtos::delay_ticks(500);
    usb.begin_capture(radio);

    let mut result = None;
    let mut last_baud = bauds[0];

    for &baud in bauds {
        info!("Trying baud {baud} (radio {radio})");
        // Reinit at this baud with IN polling paused, then settle + drain.
        usb.reinit_port(radio, baud);
        last_baud = baud;
        rtos::delay_ticks(200);
        usb.clear_capture(radio);

        // CI-V identify first — its framing is unambiguous.
        let _ = usb.send(radio, &[0xFE, 0xFE, 0x00, 0xE0, 0x19, 0x00, 0xFD]);
        if let Some((addr, id)) = wait_for_civ_id(usb, radio, 500) {
            result = Some(DetectResult {
                protocol: RadioProtocol::ProtoCiv,
                baud_rate: baud,
                id_string: id,
                civ_address: Some(addr),
                qrp_variant: QrpLabsVariant::None,
                freq_digits: 11,
            });
            break;
        }

        // Kenwood "ID;"
        usb.clear_capture(radio);
        let _ = usb.send(radio, b"ID;");
        if let Some(id) = wait_for_kenwood_id(usb, radio, 500) {
            let mut qrp_variant = QrpLabsVariant::None;
            let mut id_str = id.clone();
            if id == "ID020" {
                rtos::delay_ticks(50);
                usb.clear_capture(radio);
                let _ = usb.send(radio, b"OM;");
                if let Some(om) = wait_for_kenwood_response(usb, radio, b"OM", 500) {
                    if om.contains("QC") {
                        qrp_variant = QrpLabsVariant::Qcx;
                        id_str = format!("OM{om}");
                        info!("QCX detected via OM response: {id_str}");
                    }
                }
                if qrp_variant == QrpLabsVariant::None {
                    rtos::delay_ticks(50);
                    usb.clear_capture(radio);
                    let _ = usb.send(radio, b"VN;");
                    if let Some(vn) = wait_for_kenwood_response(usb, radio, b"VN", 500) {
                        if vn.contains("QMX") {
                            qrp_variant = QrpLabsVariant::Qmx;
                            id_str = format!("VN{vn}");
                            info!("QMX detected via VN response: {id_str}");
                        }
                    }
                }
            }
            let freq_digits = if is_yaesu_id(&id) { 9 } else { 11 };
            result = Some(DetectResult {
                protocol: RadioProtocol::ProtoKenwood,
                baud_rate: baud,
                id_string: id_str,
                civ_address: None,
                qrp_variant,
                freq_digits,
            });
            break;
        }

        // Quansheng UV-K1/K5 CAT fork: it ignores unknown commands (incl.
        // `ID;`) but answers `IF;` with `IF<11-digit freq>00000…<mod><tx>;`.
        usb.clear_capture(radio);
        let _ = usb.send(radio, b"IF;");
        if let Some(if_rsp) = wait_for_kenwood_response(usb, radio, b"IF", 500) {
            let digits_lead =
                if_rsp.len() >= 28 && if_rsp.chars().take(11).all(|c| c.is_ascii_digit());
            if digits_lead {
                info!("UV-K1 CAT detected via IF response ({} chars, radio {radio})", if_rsp.len());
                result = Some(DetectResult {
                    protocol: RadioProtocol::ProtoKenwood,
                    baud_rate: baud,
                    id_string: "UVK1CAT".to_string(),
                    civ_address: None,
                    qrp_variant: QrpLabsVariant::None,
                    freq_digits: 11,
                });
                break;
            }
        }
    }

    usb.end_capture(radio);

    if let Some(ref res) = result {
        info!("Radio {radio} detected: {} ({})", res.id_string, res.protocol.as_str_name());
    } else {
        if last_baud != bauds[0] {
            usb.reinit_port(radio, bauds[0]);
        }
        warn!("Detection failed (radio {radio}), defaulting to {} baud", bauds[0]);
    }
    result
}

/// Poll `radio`'s capture buffer for a `;`-terminated "IDnnn;" (digits
/// required — bare "ID;" is our own command, not a radio reply).
fn wait_for_kenwood_id(usb: &UsbHost, radio: usize, timeout_ms: u32) -> Option<String> {
    let deadline = rtos::tick_count() + timeout_ms;
    loop {
        if rtos::tick_count() >= deadline {
            return None;
        }
        rtos::delay_ticks(10);
        let data = usb.read_capture(radio);
        if let Some(start) = data.windows(2).position(|w| w == b"ID") {
            if let Some(end) = data[start..].iter().position(|&b| b == b';') {
                if end > 2 {
                    return Some(String::from_utf8_lossy(&data[start..start + end]).to_string());
                }
            }
        }
    }
}

/// Poll `radio`'s capture buffer for a `prefix`…`;` response; returns the
/// value between the prefix and the terminator.
fn wait_for_kenwood_response(
    usb: &UsbHost,
    radio: usize,
    prefix: &[u8],
    timeout_ms: u32,
) -> Option<String> {
    let deadline = rtos::tick_count() + timeout_ms;
    loop {
        if rtos::tick_count() >= deadline {
            return None;
        }
        rtos::delay_ticks(10);
        let data = usb.read_capture(radio);
        if let Some(start) = data.windows(prefix.len()).position(|w| w == prefix) {
            let after = start + prefix.len();
            if let Some(end) = data[after..].iter().position(|&b| b == b';') {
                if end > 0 {
                    return Some(String::from_utf8_lossy(&data[after..after + end]).to_string());
                }
            }
        }
    }
}

/// Poll `radio`'s capture buffer for a CI-V identify reply, returning the
/// radio's CI-V address.
fn wait_for_civ_id(usb: &UsbHost, radio: usize, timeout_ms: u32) -> Option<(u8, String)> {
    let deadline = rtos::tick_count() + timeout_ms;
    loop {
        if rtos::tick_count() >= deadline {
            return None;
        }
        rtos::delay_ticks(10);
        let data = usb.read_capture(radio);
        for idx in 0..data.len().saturating_sub(7) {
            if data[idx] != 0xFE || data[idx + 1] != 0xFE {
                continue;
            }
            let to_addr = data[idx + 2];
            let from_addr = data[idx + 3];
            if to_addr == 0x00 || from_addr == 0xE0 || to_addr != 0xE0 {
                continue;
            }
            if !data[idx + 4..].contains(&0xFD) {
                continue;
            }
            return Some((from_addr, format!("{from_addr:02X}")));
        }
    }
}
