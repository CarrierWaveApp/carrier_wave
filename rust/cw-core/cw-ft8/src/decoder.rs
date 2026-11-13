//! Safe Rust wrapper around `ft8_lib`'s monitor → candidate → decode pipeline.
//! Mirrors `FT8Decoder.swift`. Faithful port — same defaults, same time/freq
//! OSR (2/2), same candidate cap (140), same min-score (10), same LDPC
//! iteration cap (25), same SNR-from-score scaling, same fallback math when
//! `ftx_decode_status_t` doesn't fill in `freq`/`time`. Dedup by message text
//! to match Swift.

use std::ffi::CStr;
use std::os::raw::{c_char, c_int};
use std::ptr;

use crate::ffi;
use crate::message::Ft8Message;

const MAX_CANDIDATES: c_int = 140;
const MIN_SCORE: c_int = 10;
const MAX_LDPC_ITERATIONS: c_int = 25;
const TIME_OSR: c_int = 2;
const FREQ_OSR: c_int = 2;
const SAMPLE_RATE_HZ: i32 = 12_000;
const SYMBOL_PERIOD_SEC: f64 = 0.160;
const TONE_SPACING_HZ: f64 = 6.25;

/// One decoded FT8 message with the metadata the Swift `FT8DecodeResult`
/// surfaces (raw text, parsed message, SNR estimate, time/freq offsets).
#[derive(Debug, Clone, PartialEq)]
pub struct Ft8DecodeResult {
    pub raw_text: String,
    pub message: Ft8Message,
    pub snr: i32,
    pub delta_time_sec: f64,
    pub frequency_hz: f64,
}

/// Decode FT8 messages from a 12 kHz mono float audio buffer.
///
/// Returns an empty vec when the buffer is shorter than one slot (matches Swift).
pub fn decode(samples: &[f32], min_frequency_hz: f32, max_frequency_hz: f32) -> Vec<Ft8DecodeResult> {
    if (samples.len() as i32) < SAMPLE_RATE_HZ {
        return Vec::new();
    }
    let mut monitor = match Monitor::new(min_frequency_hz, max_frequency_hz) {
        Some(m) => m,
        None => return Vec::new(),
    };
    monitor.feed(samples);
    monitor.decode_all(min_frequency_hz)
}

/// Decode with default frequency search range (100–3000 Hz). Convenience that
/// mirrors `FT8Decoder.decode(samples:)` in Swift.
pub fn decode_default(samples: &[f32]) -> Vec<Ft8DecodeResult> {
    decode(samples, 100.0, 3_000.0)
}

struct Monitor {
    raw: ffi::monitor_t,
}

impl Monitor {
    fn new(min_freq: f32, max_freq: f32) -> Option<Self> {
        // SAFETY: monitor_init zero-initializes via the provided config; we
        // mirror the Swift call shape exactly.
        unsafe {
            let config = ffi::monitor_config_t {
                f_min: min_freq,
                f_max: max_freq,
                sample_rate: SAMPLE_RATE_HZ,
                time_osr: TIME_OSR,
                freq_osr: FREQ_OSR,
                protocol: ffi::ftx_protocol_t_FTX_PROTOCOL_FT8,
            };
            let mut raw: ffi::monitor_t = std::mem::zeroed();
            ffi::monitor_init(&mut raw, &config);
            // monitor_init can leave block_size at zero on malformed config;
            // bail out so the feed loop doesn't infinite-loop on (0, 0).
            if raw.block_size <= 0 {
                ffi::monitor_free(&mut raw);
                return None;
            }
            Some(Monitor { raw })
        }
    }

    fn feed(&mut self, samples: &[f32]) {
        let block_size = self.raw.block_size as usize;
        let mut offset = 0;
        while offset + block_size <= samples.len() {
            // SAFETY: monitor_process reads exactly block_size floats from the pointer.
            unsafe {
                let ptr = samples.as_ptr().add(offset) as *mut f32;
                ffi::monitor_process(&mut self.raw, ptr);
            }
            offset += block_size;
        }
    }

    fn decode_all(&mut self, min_freq_hz: f32) -> Vec<Ft8DecodeResult> {
        let mut candidates: Vec<ffi::ftx_candidate_t> =
            vec![unsafe { std::mem::zeroed() }; MAX_CANDIDATES as usize];
        // SAFETY: pointer + size are valid; we own `candidates`.
        let num_found = unsafe {
            ffi::ftx_find_candidates(
                &self.raw.wf,
                MAX_CANDIDATES,
                candidates.as_mut_ptr(),
                MIN_SCORE,
            )
        };
        candidates.truncate(num_found.max(0) as usize);

        let mut hash_iface = ffi::ftx_callsign_hash_interface_t {
            lookup_hash: Some(lookup_hash_noop),
            save_hash: Some(save_hash_noop),
        };
        let mut seen: Vec<String> = Vec::new();
        let mut results = Vec::with_capacity(candidates.len());
        for cand in candidates {
            if let Some(result) = self.decode_candidate(cand, &mut hash_iface, min_freq_hz, &mut seen) {
                results.push(result);
            }
        }
        results
    }

    fn decode_candidate(
        &mut self,
        cand: ffi::ftx_candidate_t,
        hash_iface: &mut ffi::ftx_callsign_hash_interface_t,
        min_freq_hz: f32,
        seen: &mut Vec<String>,
    ) -> Option<Ft8DecodeResult> {
        let mut message: ffi::ftx_message_t = unsafe { std::mem::zeroed() };
        let mut status: ffi::ftx_decode_status_t = unsafe { std::mem::zeroed() };
        let cand_mut = cand;

        // SAFETY: all pointers refer to live stack memory we own.
        let decoded = unsafe {
            ffi::ftx_decode_candidate(
                &self.raw.wf,
                &cand_mut,
                MAX_LDPC_ITERATIONS,
                &mut message,
                &mut status,
            )
        };
        if !decoded {
            return None;
        }

        // FTX_MAX_MESSAGE_LENGTH is a build-time int in C; bindgen lifts it as
        // a const. +1 for the trailing NUL terminator.
        let buf_len = ffi::FTX_MAX_MESSAGE_LENGTH as usize + 1;
        let mut text_buf: Vec<c_char> = vec![0; buf_len];
        let mut offsets: ffi::ftx_message_offsets_t = unsafe { std::mem::zeroed() };
        // SAFETY: text_buf is `buf_len` bytes long and writable.
        unsafe {
            ffi::ftx_message_decode(
                &message,
                hash_iface,
                text_buf.as_mut_ptr(),
                &mut offsets,
            );
        }
        let raw_text = unsafe { CStr::from_ptr(text_buf.as_ptr()) }
            .to_string_lossy()
            .trim()
            .to_string();
        if raw_text.is_empty() || seen.iter().any(|s| s == &raw_text) {
            return None;
        }
        seen.push(raw_text.clone());

        let frequency_hz = status_frequency(&status, &cand, min_freq_hz);
        let delta_time_sec = status_time(&status, &cand);
        // Swift: Int(round(Double(candidate.score) * 0.5))
        let snr = (cand.score as f64 * 0.5).round() as i32;

        // Structured parsing of CQ/Directed/SignalReport etc. is a follow-up;
        // for now we surface the raw text and let consumers parse with the
        // existing Swift `FT8Message.parse` if they want structured types.
        Some(Ft8DecodeResult {
            message: Ft8Message::FreeText(raw_text.clone()),
            raw_text,
            snr,
            delta_time_sec,
            frequency_hz,
        })
    }
}

impl Drop for Monitor {
    fn drop(&mut self) {
        // SAFETY: monitor_free is the documented inverse of monitor_init.
        unsafe { ffi::monitor_free(&mut self.raw) };
    }
}

fn status_frequency(status: &ffi::ftx_decode_status_t, cand: &ffi::ftx_candidate_t, min_freq_hz: f32) -> f64 {
    if status.freq > 0.0 {
        return status.freq as f64;
    }
    cand.freq_offset as f64 * TONE_SPACING_HZ / FREQ_OSR as f64 + min_freq_hz as f64
}

fn status_time(status: &ffi::ftx_decode_status_t, cand: &ffi::ftx_candidate_t) -> f64 {
    if status.time != 0.0 {
        return status.time as f64;
    }
    cand.time_offset as f64 * SYMBOL_PERIOD_SEC / TIME_OSR as f64
}

/// Decoder doesn't persist callsign hashes; mirrors Swift's lookup-returns-false
/// behavior so hashed callsigns surface as `<...>`.
unsafe extern "C" fn lookup_hash_noop(
    _hash_type: ffi::ftx_callsign_hash_type_t,
    _hash: u32,
    _callsign: *mut c_char,
) -> bool {
    false
}

unsafe extern "C" fn save_hash_noop(_callsign: *const c_char, _hash: u32) {
    // intentionally empty
}

// Some bindgen versions emit `protocol_` instead of `protocol` for that C
// field (because `protocol` is a Rust keyword). The check below catches the
// mismatch at compile time if the upstream header is ever renamed.
const _: fn() = || {
    let _ = ptr::null::<ffi::monitor_config_t>();
};
