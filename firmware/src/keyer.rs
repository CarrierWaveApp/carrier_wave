//! CW keyer module: CAT encoding, template expansion, and send engine.
//!
//! Three components:
//! 1. CW Driver — per-protocol CAT encoding (Kenwood/Elecraft and CI-V)
//! 2. Template Expansion — `{KEY}` placeholder replacement with prosign support
//! 3. CwEngine — state machine driving the blocking send loop

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use esp_idf_svc::nvs::{EspNvs, EspNvsPartition, NvsDefault};
use log::{info, warn};

use crate::generated::cwbp::CwAckResult;
use crate::protocol::RadioProtocol;
use crate::rtos;
use crate::usb::UsbHost;

/// Log the ASCII content of a CAT command buffer.
fn log_cat_cmd(cmd: &[u8]) {
    let ascii = String::from_utf8_lossy(cmd);
    info!("CAT TX: {}", ascii);
}

// ---------------------------------------------------------------
// CW progress flags (bitmask)
// ---------------------------------------------------------------

pub const FLAG_TX_ACTIVE: u32 = 1;
pub const FLAG_DRAINING: u32 = 2;
pub const FLAG_COMPLETE: u32 = 4;

// ---------------------------------------------------------------
// CW Driver — Kenwood/Elecraft
// ---------------------------------------------------------------

mod kenwood {
    /// Max characters per KY; chunk.
    pub const MAX_CHUNK: usize = 24;

    /// Encode a KY send command into `buf`. Returns bytes written, or None if text
    /// doesn't fit. `text` must be ≤ MAX_CHUNK chars.
    pub fn encode_send(text: &str, buf: &mut Vec<u8>) {
        // "KY <text>;" — leading space before text per spec
        buf.extend_from_slice(b"KY ");
        buf.extend_from_slice(text.as_bytes());
        buf.push(b';');
    }

    /// Encode a stop command ("RX;") into buf.
    pub fn encode_stop(buf: &mut Vec<u8>) {
        buf.extend_from_slice(b"RX;");
    }

    /// Encode a speed command ("KS028;" style) into buf.
    pub fn encode_speed(wpm: u32, buf: &mut Vec<u8>) {
        let s = format!("KS{:03};", wpm.clamp(5, 100));
        buf.extend_from_slice(s.as_bytes());
    }

    /// Encode a TX buffer poll command ("TB;") into buf.
    pub fn encode_poll(buf: &mut Vec<u8>) {
        buf.extend_from_slice(b"TB;");
    }

    /// Parse a "TBxNN;" response and return the number of characters remaining.
    ///
    /// Elecraft format: TB + x (buffer-has-data flag, 0 or 1) + NN (2-digit count) + ';'
    /// When idle: TB000; → 0 chars remaining
    /// When keying: TB108; → 8 chars remaining
    pub fn parse_poll(rx: &[u8]) -> u32 {
        // Find "TB" prefix in the response
        let window = rx.windows(2).position(|w| w == b"TB");
        let start = match window {
            Some(pos) => pos + 2,
            None => return 0,
        };

        // payload[0] = x (has-data flag), payload[1..2] = NN (2-digit count)
        let payload = &rx[start..];
        if payload.len() < 3 {
            return 0;
        }
        let d0 = payload.get(1).copied().unwrap_or(b'0');
        let d1 = payload.get(2).copied().unwrap_or(b'0');
        if d0.is_ascii_digit() && d1.is_ascii_digit() {
            ((d0 - b'0') as u32) * 10 + (d1 - b'0') as u32
        } else {
            0
        }
    }

    pub const fn has_native_poll() -> bool {
        true
    }
}

// ---------------------------------------------------------------
// CW Driver — Yaesu (FT-891 etc.)
// ---------------------------------------------------------------

mod yaesu {
    /// Max characters per `KY0` direct-send chunk. The FTX-1 CW keying buffer
    /// (`KY` with P1=0) accepts up to 24 characters per command.
    pub const MAX_CHUNK: usize = 24;

    /// Encode a CW send via `KY0<text>;` — direct keying.
    ///
    /// On the FTX-1, `KY` with P1=0 transmits the literal text that follows
    /// (up to 24 chars), rather than playing a stored memory. Earlier attempts
    /// used `KM1<text>;KY6;` (store to keyer memory 1, then trigger "Message
    /// Keyer 1" — the wrong bank) and `KM5<text>;KY5;` (`KY5` is not a valid
    /// playback code); neither keys reliably. Direct `KY0` send matches
    /// Hamlib's FTX-1 backend (`ftx1_cw.c`, sourced from FTX-1_CAT_OM_ENG_2508)
    /// and clobbers none of the radio's keyer-memory slots. `KM1`–`KM5` remain
    /// for storing the radio's own message memories but are unused for ad-hoc
    /// sends.
    pub fn encode_send(text: &str, buf: &mut Vec<u8>) {
        buf.extend_from_slice(b"KY0");
        buf.extend_from_slice(text.as_bytes());
        buf.push(b';');
    }

    /// Stop keying: `KY0;` with no text aborts an in-progress direct send on
    /// the FTX-1 (matches Hamlib `ftx1_stop_morse`).
    pub fn encode_stop(buf: &mut Vec<u8>) {
        buf.extend_from_slice(b"KY0;");
    }

    /// Encode a speed command ("KS028;" style) into buf.
    pub fn encode_speed(wpm: u32, buf: &mut Vec<u8>) {
        let s = format!("KS{:03};", wpm.clamp(5, 100));
        buf.extend_from_slice(s.as_bytes());
    }

    /// No TB; on Yaesu — uses time-based drain.
    pub const fn has_native_poll() -> bool {
        false
    }
}

// ---------------------------------------------------------------
// CW Driver — CI-V (Icom)
// ---------------------------------------------------------------

mod civ {
    const PREAMBLE: u8 = 0xFE;
    const CTRL_ADDR: u8 = 0xE0;
    const TERM: u8 = 0xFD;

    /// Max characters per CI-V keyer chunk.
    pub const MAX_CHUNK: usize = 30;

    fn frame(addr: u8, cmd: u8, data: &[u8], buf: &mut Vec<u8>) {
        buf.push(PREAMBLE);
        buf.push(PREAMBLE);
        buf.push(addr);
        buf.push(CTRL_ADDR);
        buf.push(cmd);
        buf.extend_from_slice(data);
        buf.push(TERM);
    }

    /// Encode a CW send command for CI-V.
    pub fn encode_send(text: &str, civ_addr: u8, buf: &mut Vec<u8>) {
        frame(civ_addr, 0x17, text.as_bytes(), buf);
    }

    /// Encode a CW stop command for CI-V (TX off + PTT).
    pub fn encode_stop(civ_addr: u8, buf: &mut Vec<u8>) {
        frame(civ_addr, 0x1C, &[0x00, 0x00], buf);
    }

    /// Encode a CW speed command for CI-V.
    ///
    /// Speed mapping: value = (wpm - 6) * 255 / 42, clamped to 6–48 WPM.
    /// BCD encode: bcd_lo = ((val/10)<<4)|(val%10), bcd_hi = ((val/1000)<<4)|((val/100)%10)
    pub fn encode_speed(wpm: u32, civ_addr: u8, buf: &mut Vec<u8>) {
        let wpm_clamped = wpm.clamp(6, 48);
        let val = ((wpm_clamped - 6) * 255 / 42).min(255);
        let bcd_lo = (((val / 10) % 10) << 4) | (val % 10);
        let bcd_hi = (((val / 1000) % 10) << 4) | ((val / 100) % 10);
        frame(civ_addr, 0x14, &[0x0C, bcd_hi as u8, bcd_lo as u8], buf);
    }

    /// CI-V has no native poll; no-op.
    #[allow(dead_code)]
    pub fn encode_poll(_buf: &mut Vec<u8>) {}

    pub const fn has_native_poll() -> bool {
        false
    }

    #[allow(dead_code)]
    pub const fn max_chunk() -> usize {
        MAX_CHUNK
    }
}

// ---------------------------------------------------------------
// Template expansion
// ---------------------------------------------------------------

/// Prosign substitutions for Kenwood-style CW.
const PROSIGNS: &[(&str, char)] = &[
    ("BT", '='),
    ("AR", '+'),
    ("KN", '('),
    ("AS", '%'),
    ("SK", '*'),
    ("VE", '!'),
];

/// Expand `{KEY}` placeholders in `template` using `context`.
///
/// Also handles prosigns: `{BT}` → `=`, `{AR}` → `+`, etc.
/// Unknown keys are left as-is.
pub fn expand_template(template: &str, context: &HashMap<String, String>) -> String {
    let mut result = String::with_capacity(template.len());
    let mut chars = template.char_indices().peekable();

    while let Some((i, ch)) = chars.next() {
        if ch == '{' {
            // Find the closing brace
            let rest = &template[i + 1..];
            if let Some(end) = rest.find('}') {
                let key = &rest[..end];

                // Advance the iterator past the key and closing brace
                let skip_to = i + 1 + end + 1;
                while chars.peek().map(|(j, _)| *j).unwrap_or(skip_to) < skip_to {
                    chars.next();
                }

                // Check prosigns first
                let mut found_prosign = false;
                for (ps, sub) in PROSIGNS {
                    if key == *ps {
                        result.push(*sub);
                        found_prosign = true;
                        break;
                    }
                }

                if !found_prosign {
                    // Check context
                    if let Some(val) = context.get(key) {
                        result.push_str(val);
                    } else {
                        // Leave unknown placeholder as-is
                        result.push('{');
                        result.push_str(key);
                        result.push('}');
                    }
                }
            } else {
                // No closing brace — emit literal
                result.push(ch);
            }
        } else {
            result.push(ch);
        }
    }

    result
}

// ---------------------------------------------------------------
// RX intercept for Kenwood poll responses
// ---------------------------------------------------------------

static KEYER_BUF: Mutex<Option<Arc<Mutex<Vec<u8>>>>> = Mutex::new(None);

fn keyer_rx_cb(data: &[u8]) {
    if let Ok(guard) = KEYER_BUF.lock() {
        if let Some(ref buf) = *guard {
            if let Ok(mut inner) = buf.lock() {
                inner.extend_from_slice(data);
            }
        }
    }
}

// ---------------------------------------------------------------
// CW Engine state machine
// ---------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CwState {
    Idle,
    Sending,
    Draining,
}

pub const MAX_SLOTS: usize = 8;
const MAX_SLOT_TEXT: usize = 120;

#[derive(Default)]
pub struct CwSlot {
    pub text: String,
}

pub struct CwEngine {
    state: CwState,
    pub wpm: u32,
    pub slots: [CwSlot; MAX_SLOTS],
    nvs: Option<EspNvs<NvsDefault>>,
    send_buf: String,
    send_offset: usize,
    buf_depth: u32,
}

impl CwEngine {
    /// Create a lightweight CwEngine for background send threads.
    /// Skips NVS init — only needs WPM for the send loop.
    pub fn lightweight(wpm: u32) -> Self {
        Self {
            state: CwState::Idle,
            wpm,
            slots: Default::default(),
            nvs: None,
            send_buf: String::new(),
            send_offset: 0,
            buf_depth: 0,
        }
    }

    /// Create a new CwEngine and load slot templates from NVS.
    pub fn new() -> Self {
        let mut slots = [
            CwSlot::default(),
            CwSlot::default(),
            CwSlot::default(),
            CwSlot::default(),
            CwSlot::default(),
            CwSlot::default(),
            CwSlot::default(),
            CwSlot::default(),
        ];

        // Try to open NVS and load persisted slots
        let nvs = EspNvsPartition::<NvsDefault>::take()
            .ok()
            .and_then(|partition| EspNvs::new(partition, "cw_slots", true).ok());

        if let Some(ref nvs_handle) = nvs {
            let mut buf = [0u8; MAX_SLOT_TEXT + 1];
            for (idx, slot) in slots.iter_mut().enumerate() {
                let key = format!("slot{}", idx + 1);
                if let Ok(Some(text)) = nvs_handle.get_str(&key, &mut buf) {
                    slot.text = text.to_string();
                    info!("Loaded slot {}: {:?}", idx + 1, text);
                }
            }
        }

        Self {
            state: CwState::Idle,
            wpm: 20,
            slots,
            nvs,
            send_buf: String::new(),
            send_offset: 0,
            buf_depth: 0,
        }
    }

    /// Is the engine currently transmitting or draining?
    #[allow(dead_code)]
    pub fn is_busy(&self) -> bool {
        self.state != CwState::Idle
    }

    /// Return (wpm, buf_depth, flags, slot_count).
    pub fn get_status(&self) -> (u32, u32, u32, u32) {
        let flags = match self.state {
            CwState::Idle => 0,
            CwState::Sending => FLAG_TX_ACTIVE,
            CwState::Draining => FLAG_TX_ACTIVE | FLAG_DRAINING,
        };
        let slot_count = self.slots.iter().filter(|s| !s.text.is_empty()).count() as u32;
        (self.wpm, self.buf_depth, flags, slot_count)
    }

    /// Store text in a numbered slot (1-based) and persist to NVS.
    pub fn set_slot(&mut self, slot: u32, text: &str) -> CwAckResult {
        let idx = slot as usize;
        if !(1..=MAX_SLOTS).contains(&idx) {
            return CwAckResult::BadSlot;
        }
        if text.len() > MAX_SLOT_TEXT {
            return CwAckResult::Fail;
        }
        self.slots[idx - 1].text = text.to_string();

        // Persist to NVS
        if let Some(ref mut nvs_handle) = self.nvs {
            let key = format!("slot{}", slot);
            if let Err(err) = nvs_handle.set_str(&key, text) {
                warn!("NVS write failed for {}: {:?}", key, err);
            }
        }

        info!("Slot {} set: {:?}", slot, text);
        CwAckResult::Ok
    }

    /// Raw (unexpanded) template stored in `slot` (1-based). `None` when the
    /// slot index is out of range or the slot is empty. Lets the caller pull
    /// the text and key it on a worker thread (see `play_cw_memory` in main)
    /// without holding `&mut self` for the whole multi-second transmission.
    pub fn slot_text(&self, slot: u32) -> Option<String> {
        let idx = slot as usize;
        if !(1..=MAX_SLOTS).contains(&idx) {
            return None;
        }
        let text = &self.slots[idx - 1].text;
        if text.is_empty() {
            None
        } else {
            Some(text.clone())
        }
    }

    /// Expand slot `slot` (1-based) and send via `send`.
    #[allow(dead_code, clippy::too_many_arguments)]
    pub fn play_slot<F>(
        &mut self,
        slot: u32,
        context: &HashMap<String, String>,
        usb: &UsbHost,
        proto: RadioProtocol,
        civ_addr: u8,
        is_yaesu: bool,
        progress_cb: F,
    ) -> CwAckResult
    where
        F: Fn(u32, u32),
    {
        let idx = slot as usize;
        if !(1..=MAX_SLOTS).contains(&idx) {
            return CwAckResult::BadSlot;
        }
        let template = self.slots[idx - 1].text.clone();
        let expanded = expand_template(&template, context);
        info!("Playing slot {}: {:?}", slot, expanded);
        self.send(
            &expanded,
            usb,
            proto,
            civ_addr,
            false,
            is_yaesu,
            progress_cb,
        )
    }

    /// Send speed command immediately (or queue for next chunk boundary if sending).
    pub fn set_speed(
        &mut self,
        wpm: u32,
        usb: &UsbHost,
        proto: RadioProtocol,
        civ_addr: u8,
        is_yaesu: bool,
    ) {
        self.wpm = wpm;
        if self.state == CwState::Idle {
            let mut cmd = Vec::new();
            match proto {
                RadioProtocol::Kenwood if is_yaesu => yaesu::encode_speed(wpm, &mut cmd),
                RadioProtocol::Kenwood => kenwood::encode_speed(wpm, &mut cmd),
                RadioProtocol::Civ => civ::encode_speed(wpm, civ_addr, &mut cmd),
                _ => {}
            }
            if !cmd.is_empty() {
                log_cat_cmd(&cmd);
                let _ = usb.send(&cmd);
                info!("Speed set to {} WPM", wpm);
            }
        }
        // If sending, new speed will be applied at next chunk boundary
    }

    /// Send a stop command to halt keyer output.
    pub fn stop(&mut self, usb: &UsbHost, proto: RadioProtocol, civ_addr: u8, is_yaesu: bool) {
        let mut cmd = Vec::new();
        match proto {
            RadioProtocol::Kenwood if is_yaesu => yaesu::encode_stop(&mut cmd),
            RadioProtocol::Kenwood => kenwood::encode_stop(&mut cmd),
            RadioProtocol::Civ => civ::encode_stop(civ_addr, &mut cmd),
            _ => {}
        }
        if !cmd.is_empty() {
            log_cat_cmd(&cmd);
            let _ = usb.send(&cmd);
        }
        self.state = CwState::Idle;
        self.buf_depth = 0;
        info!("Keyer stopped");
    }

    /// Blocking send loop. Chunks `text`, sends via driver, polls buffer,
    /// and calls `progress_cb(buf_depth, flags)` at 25%/50%/75%/empty thresholds.
    ///
    /// Set `disable_poll` to true for radios that use Kenwood protocol but
    /// don't support the TB; buffer poll command (e.g., QMX).
    ///
    /// Intended to run on a background thread spawned by `main.rs`.
    #[allow(clippy::too_many_arguments)]
    pub fn send<F>(
        &mut self,
        text: &str,
        usb: &UsbHost,
        proto: RadioProtocol,
        civ_addr: u8,
        disable_poll: bool,
        is_yaesu: bool,
        progress_cb: F,
    ) -> CwAckResult
    where
        F: Fn(u32, u32),
    {
        if text.is_empty() {
            return CwAckResult::Ok;
        }

        self.send_buf = text.to_string();
        self.send_offset = 0;
        self.state = CwState::Sending;

        let total_len = text.len() as u32;
        let chunk_size = match proto {
            RadioProtocol::Kenwood if is_yaesu => yaesu::MAX_CHUNK,
            RadioProtocol::Kenwood => kenwood::MAX_CHUNK,
            RadioProtocol::Civ => civ::MAX_CHUNK,
            _ => kenwood::MAX_CHUNK,
        };
        let has_poll = if disable_poll {
            false
        } else {
            match proto {
                RadioProtocol::Kenwood if is_yaesu => yaesu::has_native_poll(),
                RadioProtocol::Kenwood => kenwood::has_native_poll(),
                RadioProtocol::Civ => civ::has_native_poll(),
                _ => false,
            }
        };

        // Set up RX intercept for Kenwood poll responses
        let rx_buf: Arc<Mutex<Vec<u8>>> = Arc::new(Mutex::new(Vec::new()));
        if has_poll {
            *KEYER_BUF.lock().unwrap() = Some(rx_buf.clone());
            usb.set_detect_rx(Some(keyer_rx_cb));
        }

        // Send speed + first chunk immediately (no poll needed — buffer is empty)
        {
            let remaining_text = &self.send_buf[self.send_offset..];
            let chunk_end = find_char_boundary(remaining_text, chunk_size);
            let chunk = &remaining_text[..chunk_end];

            let mut cmd = Vec::new();
            match proto {
                RadioProtocol::Kenwood if is_yaesu => {
                    yaesu::encode_speed(self.wpm, &mut cmd);
                    yaesu::encode_send(chunk, &mut cmd);
                }
                RadioProtocol::Kenwood => {
                    kenwood::encode_speed(self.wpm, &mut cmd);
                    kenwood::encode_send(chunk, &mut cmd);
                }
                RadioProtocol::Civ => {
                    civ::encode_speed(self.wpm, civ_addr, &mut cmd);
                    civ::encode_send(chunk, civ_addr, &mut cmd);
                }
                _ => {
                    kenwood::encode_send(chunk, &mut cmd);
                }
            }

            log_cat_cmd(&cmd);
            if let Err(e) = usb.send(&cmd) {
                warn!("Keyer send error: {}", e);
                self.cleanup_rx(usb, has_poll);
                self.state = CwState::Idle;
                return CwAckResult::Fail;
            }
            self.send_offset += chunk_end;
            info!("First chunk sent ({} bytes)", chunk_end);
        }

        // Progress thresholds (25%, 50%, 75%, empty)
        let mut reported_75 = false;
        let mut reported_50 = false;
        let mut reported_25 = false;

        // Send remaining chunks (poll before each)
        loop {
            let remaining_text = &self.send_buf[self.send_offset..];

            if remaining_text.is_empty() {
                break;
            }

            if has_poll {
                // Poll the radio buffer
                let mut poll_cmd = Vec::new();
                kenwood::encode_poll(&mut poll_cmd);
                let _ = usb.send(&poll_cmd);

                rtos::delay_ticks(50);
                let poll_data = rx_buf.lock().unwrap().clone();
                rx_buf.lock().unwrap().clear();

                let depth = kenwood::parse_poll(&poll_data);
                self.buf_depth = depth;

                // Only send more if buffer has room (< half chunk)
                if depth > (chunk_size as u32 / 2) {
                    let sent = (self.send_offset as u32).min(total_len);
                    let pct = (sent * 100).checked_div(total_len).unwrap_or(100);
                    let flags = FLAG_TX_ACTIVE;

                    if pct >= 75 && !reported_75 {
                        reported_75 = true;
                        progress_cb(depth, flags);
                    } else if pct >= 50 && !reported_50 {
                        reported_50 = true;
                        progress_cb(depth, flags);
                    } else if pct >= 25 && !reported_25 {
                        reported_25 = true;
                        progress_cb(depth, flags);
                    }
                    continue;
                }
            }

            // Take the next chunk
            let chunk_end = find_char_boundary(remaining_text, chunk_size);
            let chunk = &remaining_text[..chunk_end];
            self.send_offset += chunk_end;

            let mut cmd = Vec::new();
            match proto {
                RadioProtocol::Kenwood if is_yaesu => yaesu::encode_send(chunk, &mut cmd),
                RadioProtocol::Kenwood => kenwood::encode_send(chunk, &mut cmd),
                RadioProtocol::Civ => civ::encode_send(chunk, civ_addr, &mut cmd),
                _ => kenwood::encode_send(chunk, &mut cmd),
            }
            log_cat_cmd(&cmd);
            if let Err(e) = usb.send(&cmd) {
                warn!("Keyer send error: {}", e);
                self.cleanup_rx(usb, has_poll);
                self.state = CwState::Idle;
                return CwAckResult::Fail;
            }

            // CI-V: estimate drain time and sleep
            if !has_poll {
                let sleep_ms = (1200 / self.wpm.max(1)) * (chunk_end as u32 / 2).max(1);
                rtos::delay_ticks(sleep_ms);
                self.buf_depth = (remaining_text.len() - chunk_end) as u32;

                let sent = self.send_offset as u32;
                let pct = (sent * 100).checked_div(total_len).unwrap_or(100);
                let flags = FLAG_TX_ACTIVE;

                if pct >= 75 && !reported_75 {
                    reported_75 = true;
                    progress_cb(self.buf_depth, flags);
                } else if pct >= 50 && !reported_50 {
                    reported_50 = true;
                    progress_cb(self.buf_depth, flags);
                } else if pct >= 25 && !reported_25 {
                    reported_25 = true;
                    progress_cb(self.buf_depth, flags);
                }
            }
        }

        // Drain phase: wait for the radio buffer to empty
        self.state = CwState::Draining;

        if has_poll {
            // Max drain time: generous estimate based on full buffer at current WPM
            let max_drain_ms = (1200 / self.wpm.max(1)) * total_len * 2;
            let drain_start = rtos::tick_count();

            loop {
                let mut poll_cmd = Vec::new();
                kenwood::encode_poll(&mut poll_cmd);
                let _ = usb.send(&poll_cmd);

                rtos::delay_ticks(50);
                let poll_data = rx_buf.lock().unwrap().clone();
                rx_buf.lock().unwrap().clear();

                let depth = kenwood::parse_poll(&poll_data);
                self.buf_depth = depth;

                progress_cb(depth, FLAG_TX_ACTIVE | FLAG_DRAINING);

                if depth == 0 {
                    break;
                }

                // Safety valve: don't spin longer than the message could possibly take
                let elapsed = rtos::tick_count().wrapping_sub(drain_start);
                if elapsed > max_drain_ms {
                    warn!("Drain timeout after {}ms (depth={})", elapsed, depth);
                    break;
                }
            }
        } else {
            // CI-V: estimate total drain time for remaining chars
            let drain_ms = (1200 / self.wpm.max(1)) * (chunk_size as u32);
            rtos::delay_ticks(drain_ms);
            self.buf_depth = 0;
        }

        // Cleanup
        self.cleanup_rx(usb, has_poll);
        self.state = CwState::Idle;

        progress_cb(0, FLAG_COMPLETE);
        info!("Keyer send complete");

        CwAckResult::Ok
    }

    /// Remove the RX intercept if it was installed.
    fn cleanup_rx(&self, usb: &UsbHost, has_poll: bool) {
        if has_poll {
            usb.set_detect_rx(None);
            *KEYER_BUF.lock().unwrap() = None;
        }
    }
}

// ---------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------

/// Find the largest byte offset ≤ `max_chars` that lands on a UTF-8 char boundary.
fn find_char_boundary(s: &str, max_chars: usize) -> usize {
    if s.len() <= max_chars {
        return s.len();
    }
    // Walk back from max_chars until we find a valid boundary
    let mut end = max_chars;
    while end > 0 && !s.is_char_boundary(end) {
        end -= 1;
    }
    end
}
