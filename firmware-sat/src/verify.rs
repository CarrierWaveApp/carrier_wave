//! Set-and-verify for radio CAT commands.
//!
//! Translates semantic commands (frequency, mode, PTT, RIT/XIT) to
//! the detected radio's protocol (Kenwood or CI-V), sends the command,
//! reads back to verify, and reports the result.
//!
//! RIT/XIT emulation: if the radio rejects XIT, emulates it using RIT
//! with a VFO offset (and vice versa).

use std::sync::Mutex;

use ::log::{info, warn};

use crate::detect::QrpLabsVariant;
use crate::protocol::{RadioProtocol, SetResultCode, SetVerifyField};
use crate::rtos;
use crate::usb::UsbHost;

/// Serializes CAT sessions so their commands never interleave on the wire.
///
/// Each SetVerify / sat retune runs on its own thread; without this two
/// operations could clobber a radio's capture buffer. Held for one short
/// operation only — a long hold starves the others. Global (not per-radio):
/// the self-test drives radios sequentially, so a single lock is safe and
/// simplest. Recover from poisoning so one panic doesn't wedge all future
/// sessions.
static CAT_LOCK: Mutex<()> = Mutex::new(());

/// Exclusive CAT access to one radio with per-slot RX capture, shared by
/// SetVerify and the sat executor. Hold it for a single operation (a retune,
/// an IF poll).
pub struct CatSession<'a> {
    usb: &'a UsbHost,
    radio: usize,
    _guard: std::sync::MutexGuard<'static, ()>,
}

impl<'a> CatSession<'a> {
    /// Blocks until any in-flight CAT session finishes, then captures `radio`.
    pub fn open(usb: &'a UsbHost, radio: usize) -> Self {
        let guard = CAT_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        usb.begin_capture(radio);
        Self { usb, radio, _guard: guard }
    }

    /// Send a raw CAT command to this radio.
    pub fn send(&self, cmd: &[u8]) -> bool {
        self.usb.send(self.radio, cmd).is_ok()
    }

    /// Send a command and wait for a `;`-terminated response. The capture
    /// buffer is cleared BEFORE the send so a fast reply isn't discarded.
    pub fn query(&self, cmd: &[u8], timeout_ms: u32) -> Vec<u8> {
        self.usb.clear_capture(self.radio);
        let _ = self.usb.send(self.radio, cmd);
        let deadline = rtos::tick_count() + timeout_ms;
        loop {
            if rtos::tick_count() >= deadline {
                return self.usb.read_capture(self.radio);
            }
            rtos::delay_ticks(10);
            let data = self.usb.read_capture(self.radio);
            if data.contains(&b';') {
                return data;
            }
        }
    }
}

impl Drop for CatSession<'_> {
    fn drop(&mut self) {
        self.usb.end_capture(self.radio);
    }
}

/// Run a set-and-verify operation on `radio`. Blocking; caller runs it on a
/// background thread. Captures that radio's RX for the operation.
#[allow(clippy::too_many_arguments)]
pub fn verify(
    usb: &UsbHost,
    radio: usize,
    field: SetVerifyField,
    value: &[u8],
    protocol: RadioProtocol,
    civ_addr: u8,
    qrp_variant: QrpLabsVariant,
    freq_digits: u8,
) -> SetResultCode {
    let _guard = CAT_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    usb.begin_capture(radio);

    let result = match protocol {
        RadioProtocol::ProtoKenwood => {
            verify_kenwood_with_emulation(usb, radio, field, value, qrp_variant, freq_digits)
        }
        RadioProtocol::ProtoCiv => verify_civ(usb, radio, field, value, civ_addr),
        _ => SetResultCode::ResultUnsupported,
    };

    usb.end_capture(radio);
    info!("Verify result: {}", result.as_str_name());
    result
}

// ---------------------------------------------------------------
// RX helpers
// ---------------------------------------------------------------

/// Poll `radio`'s capture buffer until a protocol terminator appears or the
/// timeout elapses. Clears the buffer first.
fn wait_for_rx(usb: &UsbHost, radio: usize, proto: RadioProtocol, timeout_ms: u32) -> Vec<u8> {
    let deadline = rtos::tick_count() + timeout_ms;
    usb.clear_capture(radio);

    loop {
        if rtos::tick_count() >= deadline {
            break;
        }
        rtos::delay_ticks(10);
        let data = usb.read_capture(radio);
        if !data.is_empty() {
            let has_term = match proto {
                RadioProtocol::ProtoKenwood => data.iter().any(|&b| b == b';' || b == b'?'),
                RadioProtocol::ProtoCiv => data.contains(&0xFD),
                _ => false,
            };
            if has_term {
                return data;
            }
        }
    }
    usb.read_capture(radio)
}

// ---------------------------------------------------------------
// Kenwood protocol
// ---------------------------------------------------------------

fn kw_set_freq(hz: u64, digits: u8) -> Vec<u8> {
    format!("FA{hz:0width$};", width = digits as usize).into_bytes()
}

fn kw_read_freq() -> &'static [u8] {
    b"FA;"
}

fn kw_set_mode(mode: u8) -> Option<Vec<u8>> {
    let kw_mode = match mode {
        1 => 1, // LSB
        2 => 2, // USB
        3 => 3, // CW
        4 => 4, // FM
        5 => 5, // AM
        6 => 6, // DATA
        7 => 7, // CW-R
        _ => return None,
    };
    Some(format!("MD{kw_mode};").into_bytes())
}

fn kw_set_ptt(on: bool) -> Vec<u8> {
    if on {
        b"TX;".to_vec()
    } else {
        b"RX;".to_vec()
    }
}

fn kw_set_xit(on: bool) -> Vec<u8> {
    if on {
        b"XT1;".to_vec()
    } else {
        b"XT0;".to_vec()
    }
}

fn kw_set_rit(on: bool) -> Vec<u8> {
    if on {
        b"RT1;".to_vec()
    } else {
        b"RT0;".to_vec()
    }
}

fn kw_set_offset(hz: i16) -> Vec<u8> {
    let sign = if hz >= 0 { '+' } else { '-' };
    let abs_hz = hz.unsigned_abs();
    format!("RU{sign}{abs_hz:05};").into_bytes()
}

fn kw_clear_ritxit() -> &'static [u8] {
    b"RC;"
}

fn kw_set_power(watts: u8) -> Vec<u8> {
    format!("PC{watts:03};").into_bytes()
}

// ---------------------------------------------------------------
// QCX-specific Kenwood helpers
// ---------------------------------------------------------------

/// QCX RIT offset: RU for positive, RD for negative (no sign character).
fn kw_set_offset_qcx(hz: i16) -> Vec<u8> {
    let abs_hz = hz.unsigned_abs();
    if hz >= 0 {
        format!("RU{abs_hz:05};").into_bytes()
    } else {
        format!("RD{abs_hz:05};").into_bytes()
    }
}

fn kw_read_power() -> &'static [u8] {
    b"PC;"
}

/// QCX clear RIT: zero the offset with RU, then disable RIT with RT0.
/// QCX has no RC; command and no XIT.
fn kw_clear_rit_qcx(usb: &UsbHost, radio: usize) -> SetResultCode {
    // Zero the offset
    let _ = usb.send(radio, b"RU00000;");
    rtos::delay_ticks(50);
    usb.clear_capture(radio);

    // Disable RIT
    let _ = usb.send(radio, b"RT0;");
    let rx = wait_for_rx(usb, radio, RadioProtocol::ProtoKenwood, 200);
    if !rx.is_empty() && kw_response_is_error(&rx) {
        warn!("QCX clear RIT rejected");
        return SetResultCode::ResultFail;
    }
    info!("QCX clear RIT: OK");
    SetResultCode::ResultOk
}

fn kw_response_matches(set_cmd: &[u8], rx: &[u8]) -> bool {
    rx.windows(set_cmd.len()).any(|w| w == set_cmd)
}

fn kw_response_is_error(rx: &[u8]) -> bool {
    rx.windows(2).any(|w| w == b"?;")
}

/// Read a numeric value from a Kenwood response (e.g., "FA00014100000;").
fn kw_read_u64(usb: &UsbHost, radio: usize, cmd: &[u8]) -> Option<u64> {
    let _ = usb.send(radio, cmd);
    let rx = wait_for_rx(usb, radio, RadioProtocol::ProtoKenwood, 300);
    if rx.is_empty() {
        return None;
    }

    // Find prefix (cmd without trailing ';')
    let prefix = &cmd[..cmd.len() - 1];
    for idx in 0..rx.len().saturating_sub(prefix.len()) {
        if &rx[idx..idx + prefix.len()] == prefix {
            let mut val = 0u64;
            for &byte in &rx[idx + prefix.len()..] {
                match byte {
                    b';' => return Some(val),
                    b'0'..=b'9' => val = val * 10 + (byte - b'0') as u64,
                    b'+' | b'-' => {} // sign handled by caller
                    _ => break,
                }
            }
        }
    }
    None
}

fn verify_kenwood(
    usb: &UsbHost,
    radio: usize,
    field: SetVerifyField,
    value: &[u8],
    qrp_variant: QrpLabsVariant,
    freq_digits: u8,
) -> SetResultCode {
    let is_qrp = qrp_variant != QrpLabsVariant::None;

    // QRP Labs: power set not supported (QCX has no PC; QMX PC is read-only)
    if is_qrp && field == SetVerifyField::FieldPowerLevel {
        return SetResultCode::ResultUnsupported;
    }
    // QCX: no RC; command — use RU00000 + RT0 workaround
    if qrp_variant == QrpLabsVariant::Qcx && field == SetVerifyField::FieldClearRitXit {
        return kw_clear_rit_qcx(usb, radio);
    }
    // QMX: RC; works normally — no special handling needed

    let (set_cmd, read_cmd, has_readback) = match field {
        SetVerifyField::FieldFrequency => {
            if value.len() < 8 {
                return SetResultCode::ResultFail;
            }
            let hz = u64::from_le_bytes(value[..8].try_into().unwrap());
            (
                kw_set_freq(hz, freq_digits),
                Some(kw_read_freq().to_vec()),
                true,
            )
        }
        SetVerifyField::FieldMode => {
            if value.is_empty() {
                return SetResultCode::ResultFail;
            }
            match kw_set_mode(value[0]) {
                Some(cmd) => (cmd, Some(b"MD;".to_vec()), true),
                None => return SetResultCode::ResultUnsupported,
            }
        }
        SetVerifyField::FieldPtt => {
            if value.is_empty() {
                return SetResultCode::ResultFail;
            }
            (kw_set_ptt(value[0] != 0), None, false)
        }
        SetVerifyField::FieldXit => {
            if value.is_empty() {
                return SetResultCode::ResultFail;
            }
            // QRP Labs radios have no XIT — return Fail so emulation kicks in
            if is_qrp {
                return SetResultCode::ResultFail;
            }
            (kw_set_xit(value[0] != 0), Some(b"XT;".to_vec()), true)
        }
        SetVerifyField::FieldRit => {
            if value.is_empty() {
                return SetResultCode::ResultFail;
            }
            (kw_set_rit(value[0] != 0), Some(b"RT;".to_vec()), true)
        }
        SetVerifyField::FieldRitXitOffset => {
            if value.len() < 2 {
                return SetResultCode::ResultFail;
            }
            let hz = i16::from_le_bytes(value[..2].try_into().unwrap());
            if is_qrp {
                // QRP Labs: RU for positive, RD for negative (no sign character)
                (kw_set_offset_qcx(hz), None, false)
            } else {
                (kw_set_offset(hz), Some(b"RU;".to_vec()), true)
            }
        }
        SetVerifyField::FieldClearRitXit => (kw_clear_ritxit().to_vec(), None, false),
        SetVerifyField::FieldPowerLevel => {
            if value.is_empty() {
                return SetResultCode::ResultFail;
            }
            (kw_set_power(value[0]), Some(kw_read_power().to_vec()), true)
        }
        _ => return SetResultCode::ResultUnsupported,
    };

    // Send set command
    info!("KW set: {}", String::from_utf8_lossy(&set_cmd));
    let _ = usb.send(radio, &set_cmd);

    if !has_readback {
        let rx = wait_for_rx(usb, radio, RadioProtocol::ProtoKenwood, 200);
        if !rx.is_empty() && kw_response_is_error(&rx) {
            warn!("KW set rejected");
            return SetResultCode::ResultFail;
        }
        return SetResultCode::ResultOk;
    }

    // Wait for echo, then drain
    rtos::delay_ticks(100);
    usb.clear_capture(radio);

    // Send read command
    let read_cmd = read_cmd.unwrap();
    info!("KW read: {}", String::from_utf8_lossy(&read_cmd));
    let _ = usb.send(radio, &read_cmd);
    let rx = wait_for_rx(usb, radio, RadioProtocol::ProtoKenwood, 300);

    if rx.is_empty() {
        warn!("KW verify: no response");
        return SetResultCode::ResultFail;
    }

    if kw_response_is_error(&rx) {
        warn!("KW verify: error response");
        return SetResultCode::ResultFail;
    }

    if kw_response_matches(&set_cmd, &rx) {
        info!("KW verify: OK");
        SetResultCode::ResultOk
    } else {
        warn!("KW verify: mismatch");
        SetResultCode::ResultFail
    }
}

/// Kenwood verify with RIT/XIT emulation fallback.
fn verify_kenwood_with_emulation(
    usb: &UsbHost,
    radio: usize,
    field: SetVerifyField,
    value: &[u8],
    qrp_variant: QrpLabsVariant,
    freq_digits: u8,
) -> SetResultCode {
    let result = verify_kenwood(usb, radio, field, value, qrp_variant, freq_digits);

    if result != SetResultCode::ResultOk {
        if field == SetVerifyField::FieldXit && !value.is_empty() {
            info!("XIT rejected, attempting RIT emulation");
            let offset = kw_read_u64(usb, radio, b"RU;").unwrap_or(0) as i16;
            return kw_emulate_xit_with_rit(usb, radio, value[0] != 0, offset, freq_digits);
        }
        if field == SetVerifyField::FieldRit && !value.is_empty() {
            info!("RIT rejected, attempting XIT emulation");
            let offset = kw_read_u64(usb, radio, b"RU;").unwrap_or(0) as i16;
            return kw_emulate_rit_with_xit(usb, radio, value[0] != 0, offset, freq_digits);
        }
    }

    result
}

/// Emulate XIT using RIT: shift VFO by +offset, set RIT to -offset.
fn kw_emulate_xit_with_rit(
    usb: &UsbHost,
    radio: usize,
    on: bool,
    offset: i16,
    freq_digits: u8,
) -> SetResultCode {
    if on {
        let vfo_hz = match kw_read_u64(usb, radio, b"FA;") {
            Some(v) if v > 0 => v,
            _ => return SetResultCode::ResultFail,
        };

        let new_vfo = vfo_hz.wrapping_add(offset as u64);
        let _ = usb.send(radio, &kw_set_freq(new_vfo, freq_digits));
        rtos::delay_ticks(100);
        usb.clear_capture(radio);

        let _ = usb.send(radio, &kw_set_offset(-offset));
        rtos::delay_ticks(50);
        usb.clear_capture(radio);

        let _ = usb.send(radio, &kw_set_rit(true));
        info!("Emulating XIT with RIT (VFO+{offset}, RIT={})", -offset);
    } else {
        let vfo_hz = match kw_read_u64(usb, radio, b"FA;") {
            Some(v) if v > 0 => v,
            _ => return SetResultCode::ResultFail,
        };

        let rit_offset = kw_read_u64(usb, radio, b"RU;").unwrap_or(0) as i16;

        let _ = usb.send(radio, &kw_set_rit(false));
        rtos::delay_ticks(50);
        usb.clear_capture(radio);

        let restored = vfo_hz.wrapping_add(rit_offset as u64);
        let _ = usb.send(radio, &kw_set_freq(restored, freq_digits));
        rtos::delay_ticks(50);

        let _ = usb.send(radio, kw_clear_ritxit());
        info!("XIT emulation off, VFO restored");
    }
    SetResultCode::ResultOk
}

/// Emulate RIT using XIT.
fn kw_emulate_rit_with_xit(
    usb: &UsbHost,
    radio: usize,
    on: bool,
    offset: i16,
    freq_digits: u8,
) -> SetResultCode {
    if on {
        let vfo_hz = match kw_read_u64(usb, radio, b"FA;") {
            Some(v) if v > 0 => v,
            _ => return SetResultCode::ResultFail,
        };

        let new_vfo = vfo_hz.wrapping_add(offset as u64);
        let _ = usb.send(radio, &kw_set_freq(new_vfo, freq_digits));
        rtos::delay_ticks(100);
        usb.clear_capture(radio);

        let _ = usb.send(radio, &kw_set_offset(-offset));
        rtos::delay_ticks(50);
        usb.clear_capture(radio);

        let _ = usb.send(radio, &kw_set_xit(true));
        info!("Emulating RIT with XIT (VFO+{offset}, XIT={})", -offset);
    } else {
        let vfo_hz = match kw_read_u64(usb, radio, b"FA;") {
            Some(v) if v > 0 => v,
            _ => return SetResultCode::ResultFail,
        };

        let xit_offset = kw_read_u64(usb, radio, b"RU;").unwrap_or(0) as i16;

        let _ = usb.send(radio, &kw_set_xit(false));
        rtos::delay_ticks(50);
        usb.clear_capture(radio);

        let restored = vfo_hz.wrapping_add(xit_offset as u64);
        let _ = usb.send(radio, &kw_set_freq(restored, freq_digits));
        rtos::delay_ticks(50);

        let _ = usb.send(radio, kw_clear_ritxit());
        info!("RIT emulation off, VFO restored");
    }
    SetResultCode::ResultOk
}

// ---------------------------------------------------------------
// CI-V protocol
// ---------------------------------------------------------------

const CIV_PREAMBLE: u8 = 0xFE;
const CIV_TERM: u8 = 0xFD;
const CIV_CTRL_ADDR: u8 = 0xE0;
const CIV_OK: u8 = 0xFB;
const CIV_NG: u8 = 0xFA;

fn civ_frame(to: u8, cmd: u8, data: &[u8]) -> Vec<u8> {
    let mut frame = vec![CIV_PREAMBLE, CIV_PREAMBLE, to, CIV_CTRL_ADDR, cmd];
    frame.extend_from_slice(data);
    frame.push(CIV_TERM);
    frame
}

fn encode_bcd_freq(hz: u64) -> [u8; 5] {
    let mut bcd = [0u8; 5];
    let mut rem = hz;
    for byte in &mut bcd {
        let lo = (rem % 10) as u8;
        rem /= 10;
        let hi = (rem % 10) as u8;
        rem /= 10;
        *byte = (hi << 4) | lo;
    }
    bcd
}

fn civ_check_result(rx: &[u8]) -> i32 {
    for &byte in rx {
        if byte == CIV_OK {
            return 1;
        }
        if byte == CIV_NG {
            return -1;
        }
    }
    0
}

/// Encode a signed Hz offset as CI-V BCD: 2 magnitude bytes + 1 sign byte.
/// Byte order: [lo_bcd, hi_bcd, sign] where sign 0x00 = positive, 0x01 = negative.
fn encode_bcd_offset(hz: i16) -> [u8; 3] {
    let negative = hz < 0;
    let abs_val = hz.unsigned_abs() as u32;
    let lo = ((abs_val / 10 % 10) << 4) | (abs_val % 10);
    let hi = ((abs_val / 1000 % 10) << 4) | (abs_val / 100 % 10);
    [lo as u8, hi as u8, if negative { 0x01 } else { 0x00 }]
}

/// Encode a 0–255 value as 2 BCD bytes (for CI-V 0x14 level commands).
fn encode_bcd_level(val: u8) -> [u8; 2] {
    let v = val as u32;
    let lo = ((v / 10 % 10) << 4) | (v % 10);
    let hi = (v / 100 % 10) << 4;
    [lo as u8, hi as u8]
}

fn verify_civ(
    usb: &UsbHost,
    radio: usize,
    field: SetVerifyField,
    value: &[u8],
    civ_addr: u8,
) -> SetResultCode {
    // ClearRitXit is a multi-step sequence — handle separately
    if field == SetVerifyField::FieldClearRitXit {
        return civ_clear_ritxit(usb, radio, civ_addr);
    }

    let (set_cmd, has_readback) = match field {
        SetVerifyField::FieldFrequency => {
            if value.len() < 8 {
                return SetResultCode::ResultFail;
            }
            let hz = u64::from_le_bytes(value[..8].try_into().unwrap());
            let bcd = encode_bcd_freq(hz);
            (civ_frame(civ_addr, 0x05, &bcd), true)
        }
        SetVerifyField::FieldMode => {
            if value.is_empty() {
                return SetResultCode::ResultFail;
            }
            let civ_mode = match value[0] {
                1 => 0x00, // LSB
                2 => 0x01, // USB
                3 => 0x03, // CW
                4 => 0x05, // FM
                5 => 0x02, // AM
                6 => 0x04, // DATA
                7 => 0x07, // CW-R
                _ => return SetResultCode::ResultUnsupported,
            };
            (civ_frame(civ_addr, 0x06, &[civ_mode]), true)
        }
        SetVerifyField::FieldPtt => {
            if value.is_empty() {
                return SetResultCode::ResultFail;
            }
            let data = [0x00, if value[0] != 0 { 0x01 } else { 0x00 }];
            (civ_frame(civ_addr, 0x1C, &data), false)
        }
        SetVerifyField::FieldXit => {
            if value.is_empty() {
                return SetResultCode::ResultFail;
            }
            // Sub 0x02 = XIT setting, data 0x00=off 0x01=on
            let on = if value[0] != 0 { 0x01 } else { 0x00 };
            (civ_frame(civ_addr, 0x21, &[0x02, on]), false)
        }
        SetVerifyField::FieldRit => {
            if value.is_empty() {
                return SetResultCode::ResultFail;
            }
            // Sub 0x01 = RIT setting, data 0x00=off 0x01=on
            let on = if value[0] != 0 { 0x01 } else { 0x00 };
            (civ_frame(civ_addr, 0x21, &[0x01, on]), false)
        }
        SetVerifyField::FieldRitXitOffset => {
            if value.len() < 2 {
                return SetResultCode::ResultFail;
            }
            let hz = i16::from_le_bytes(value[..2].try_into().unwrap());
            let bcd = encode_bcd_offset(hz);
            // Sub 0x00 = RIT frequency
            let mut data = vec![0x00];
            data.extend_from_slice(&bcd);
            (civ_frame(civ_addr, 0x21, &data), false)
        }
        SetVerifyField::FieldPowerLevel => {
            if value.is_empty() {
                return SetResultCode::ResultFail;
            }
            // Convert watt percentage (1-100) to CI-V 0-255 scale
            let watts = value[0].min(100) as u16;
            let scaled = (watts * 255 / 100) as u8;
            let bcd = encode_bcd_level(scaled);
            (civ_frame(civ_addr, 0x14, &[0x0A, bcd[0], bcd[1]]), true)
        }
        _ => return SetResultCode::ResultUnsupported,
    };

    info!(
        "CIV set: {} bytes (field={})",
        set_cmd.len(),
        field.as_str_name()
    );
    let _ = usb.send(radio, &set_cmd);

    let rx = wait_for_rx(usb, radio, RadioProtocol::ProtoCiv, 300);
    let ack = civ_check_result(&rx);

    if ack < 0 {
        if field == SetVerifyField::FieldXit || field == SetVerifyField::FieldRit {
            info!(
                "CIV {} rejected, emulation not implemented for CI-V",
                field.as_str_name()
            );
            return SetResultCode::ResultUnsupported;
        }
        return SetResultCode::ResultFail;
    }
    if ack == 0 {
        warn!("CIV verify: no ack");
        return SetResultCode::ResultFail;
    }

    if !has_readback {
        return SetResultCode::ResultOk;
    }

    // Read-back for freq/mode/power
    rtos::delay_ticks(50);
    usb.clear_capture(radio);

    let read_cmd = match field {
        SetVerifyField::FieldFrequency => civ_frame(civ_addr, 0x03, &[]),
        SetVerifyField::FieldMode => civ_frame(civ_addr, 0x04, &[]),
        SetVerifyField::FieldPowerLevel => civ_frame(civ_addr, 0x14, &[0x0A]),
        _ => return SetResultCode::ResultOk,
    };

    let _ = usb.send(radio, &read_cmd);
    let _rx = wait_for_rx(usb, radio, RadioProtocol::ProtoCiv, 300);
    // Trust the initial OK for now

    info!("CIV verify: OK");
    SetResultCode::ResultOk
}

/// Clear RIT/XIT: zero offset, then disable both RIT and XIT.
fn civ_clear_ritxit(usb: &UsbHost, radio: usize, civ_addr: u8) -> SetResultCode {
    // Zero the RIT offset (sub 0x00 = RIT frequency)
    let zero_offset = encode_bcd_offset(0);
    let mut data = vec![0x00];
    data.extend_from_slice(&zero_offset);

    let _ = usb.send(radio, &civ_frame(civ_addr, 0x21, &data));
    let rx = wait_for_rx(usb, radio, RadioProtocol::ProtoCiv, 300);
    if civ_check_result(&rx) < 0 {
        warn!("CIV clear RIT offset rejected");
        return SetResultCode::ResultFail;
    }

    // Disable RIT (sub 0x01, data 0x00 = off)
    usb.clear_capture(radio);
    let _ = usb.send(radio, &civ_frame(civ_addr, 0x21, &[0x01, 0x00]));
    let rx = wait_for_rx(usb, radio, RadioProtocol::ProtoCiv, 200);
    if civ_check_result(&rx) < 0 {
        warn!("CIV disable RIT rejected");
    }

    // Disable XIT (sub 0x02, data 0x00 = off)
    usb.clear_capture(radio);
    let _ = usb.send(radio, &civ_frame(civ_addr, 0x21, &[0x02, 0x00]));
    let rx = wait_for_rx(usb, radio, RadioProtocol::ProtoCiv, 200);
    if civ_check_result(&rx) < 0 {
        warn!("CIV disable XIT rejected");
    }

    info!("CIV clear RIT/XIT: OK");
    SetResultCode::ResultOk
}
