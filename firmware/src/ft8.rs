//! FT8 encode/decode bridged to the shared CFT8 C library.
//!
//! The firmware links the same C sources used by the iOS/macOS app so that
//! encoded/decoded messages are bit-for-bit identical on all three sides.
//!
//! ## Encoder
//!
//! [`encode_message`] packs a text message (e.g. `"CQ K1ABC FN42"`) into the
//! 79-tone FT8 symbol sequence. [`synthesize_tones`] turns that sequence into
//! 16-bit PCM at 12 kHz suitable for writing to [`crate::audio::AudioOut`].
//!
//! ## Decoder
//!
//! [`Decoder`] owns a heap-allocated `monitor_t` from `common/monitor.c`
//! (created by our small C shim, `src/ft8_shim.c`). Call [`Decoder::feed`] with
//! successive blocks of `f32` audio samples (12 kHz) to accumulate the
//! waterfall, then [`Decoder::decode`] at the end of a slot to pull out every
//! successfully-decoded message with SNR, frequency offset and time offset.

use std::collections::HashSet;
use std::ffi::{CStr, CString};

// ---------------------------------------------------------------
// Constants (mirrored from CFT8 headers)
// ---------------------------------------------------------------

pub const FT8_NN: usize = 79;
pub const FTX_PAYLOAD_LENGTH_BYTES: usize = 10;
pub const FTX_MAX_MESSAGE_LENGTH: usize = 35;
pub const FTX_PROTOCOL_FT8: i32 = 1;
pub const FTX_MESSAGE_RC_OK: i32 = 0;

// ---------------------------------------------------------------
// FFI types
// ---------------------------------------------------------------

#[repr(C)]
#[derive(Copy, Clone)]
pub struct FtxMessage {
    pub payload: [u8; FTX_PAYLOAD_LENGTH_BYTES],
    pub hash: u16,
}

impl FtxMessage {
    pub fn zeroed() -> Self {
        Self {
            payload: [0; FTX_PAYLOAD_LENGTH_BYTES],
            hash: 0,
        }
    }
}

#[repr(C)]
#[derive(Copy, Clone, Default)]
pub struct FtxCandidate {
    pub score: i16,
    pub time_offset: i16,
    pub freq_offset: i16,
    pub time_sub: u8,
    pub freq_sub: u8,
}

#[repr(C)]
#[derive(Copy, Clone, Default)]
pub struct FtxDecodeStatus {
    pub freq: f32,
    pub time: f32,
    pub ldpc_errors: i32,
    pub crc_extracted: u16,
    pub crc_calculated: u16,
}

#[repr(C)]
#[derive(Copy, Clone, Default)]
pub struct FtxMessageOffsets {
    pub field_offsets: [u16; 3],
    pub field_lengths: [u16; 3],
}

#[repr(C)]
pub struct FtxCallsignHashInterface {
    pub lookup_hash: Option<unsafe extern "C" fn(hash_type: i32, hash: u32, c11: *mut u8) -> bool>,
    pub save_hash: Option<unsafe extern "C" fn(c11: *const u8, n22: u32)>,
}

#[repr(C)]
pub struct MonitorConfig {
    pub f_min: f32,
    pub f_max: f32,
    pub sample_rate: i32,
    pub time_osr: i32,
    pub freq_osr: i32,
    pub protocol: i32,
}

/// Opaque C `monitor_t` allocated on the heap by our shim.
#[repr(C)]
pub struct Monitor {
    _private: [u8; 0],
}

/// Opaque `ftx_waterfall_t` pointer handed to the candidate/decode APIs.
#[repr(C)]
pub struct Waterfall {
    _private: [u8; 0],
}

#[allow(non_camel_case_types)]
mod c_types {
    pub type c_char = std::os::raw::c_char;
}

extern "C" {
    fn ftx_message_init(msg: *mut FtxMessage);
    fn ftx_message_encode(
        msg: *mut FtxMessage,
        hash_if: *mut FtxCallsignHashInterface,
        text: *const c_types::c_char,
    ) -> i32;
    fn ftx_message_decode(
        msg: *mut FtxMessage,
        hash_if: *mut FtxCallsignHashInterface,
        text: *mut c_types::c_char,
        offsets: *mut FtxMessageOffsets,
    );

    fn ft8_encode(payload: *const u8, tones: *mut u8);

    fn ftx_find_candidates(
        power: *const Waterfall,
        num_candidates: i32,
        heap: *mut FtxCandidate,
        min_score: i32,
    ) -> i32;
    fn ftx_decode_candidate(
        power: *const Waterfall,
        cand: *const FtxCandidate,
        max_iterations: i32,
        message: *mut FtxMessage,
        status: *mut FtxDecodeStatus,
    ) -> bool;

    fn ft8_shim_monitor_new(cfg: *const MonitorConfig) -> *mut Monitor;
    fn ft8_shim_monitor_free(mon: *mut Monitor);
    fn ft8_shim_monitor_block_size(mon: *const Monitor) -> i32;
    fn ft8_shim_monitor_process(mon: *mut Monitor, frame: *const f32);
    fn ft8_shim_monitor_waterfall(mon: *mut Monitor) -> *mut Waterfall;
}

// ---------------------------------------------------------------
// High-level helpers
// ---------------------------------------------------------------

/// FT8 codec errors surfaced back to the protocol layer.
#[derive(Debug)]
pub enum Ft8Error {
    /// Message text was empty, too long, or otherwise invalid.
    InvalidMessage(#[allow(dead_code)] String),
    /// CFT8 rejected the message (return code from `ftx_message_encode`).
    EncodeFailed(#[allow(dead_code)] i32),
    /// The decoder could not allocate its waterfall buffers.
    AllocFailed,
}

/// Encode an FT8 message text to the 79-symbol tone sequence (tones are 0..7).
pub fn encode_message(text: &str) -> Result<[u8; FT8_NN], Ft8Error> {
    if text.is_empty() {
        return Err(Ft8Error::InvalidMessage("empty message".into()));
    }
    let c_text = CString::new(text).map_err(|err| Ft8Error::InvalidMessage(err.to_string()))?;

    let mut msg = FtxMessage::zeroed();
    // SAFETY: stack-local msg is initialised via ftx_message_init; c_text owns its buffer.
    unsafe {
        ftx_message_init(&mut msg);
        let rc = ftx_message_encode(&mut msg, std::ptr::null_mut(), c_text.as_ptr());
        if rc != FTX_MESSAGE_RC_OK {
            return Err(Ft8Error::EncodeFailed(rc));
        }
    }

    let mut tones = [0u8; FT8_NN];
    // SAFETY: payload holds 10 bytes (encoded), tones is FT8_NN bytes.
    unsafe { ft8_encode(msg.payload.as_ptr(), tones.as_mut_ptr()) };
    Ok(tones)
}

/// 12 kHz / 16-bit PCM synthesis of an FT8 tone sequence using continuous-phase
/// 8-FSK at `base_freq_hz` with 6.25 Hz spacing. Produces exactly
/// `79 × 1920 = 151_680` samples (~12.64 s), ready for [`crate::audio::AudioOut`].
pub fn synthesize_tones(tones: &[u8; FT8_NN], base_freq_hz: f32) -> Vec<i16> {
    const SAMPLE_RATE: f32 = 12_000.0;
    const TONE_SPACING: f32 = 6.25;
    const SYMBOL_PERIOD_S: f32 = 0.160;
    let symbol_samples = (SAMPLE_RATE * SYMBOL_PERIOD_S) as usize; // 1920

    let mut samples = Vec::with_capacity(FT8_NN * symbol_samples);
    let two_pi = std::f32::consts::TAU;
    let mut phase = 0.0f32;

    for &tone in tones.iter() {
        let freq = base_freq_hz + f32::from(tone) * TONE_SPACING;
        let phase_inc = two_pi * freq / SAMPLE_RATE;
        for _ in 0..symbol_samples {
            // 0.8 headroom keeps the signal off the clipping rails.
            let sample = (phase.sin() * i16::MAX as f32 * 0.8) as i16;
            samples.push(sample);
            phase += phase_inc;
            if phase >= two_pi {
                phase -= two_pi;
            }
        }
    }
    samples
}

// ---------------------------------------------------------------
// Decoder
// ---------------------------------------------------------------

/// One successfully decoded FT8 message.
#[derive(Debug, Clone)]
pub struct DecodeResult {
    pub text: String,
    pub snr_db: i32,
    pub frequency_hz: f32,
    pub delta_time_s: f32,
}

/// Streaming FT8 decoder. Samples are 12 kHz `f32` in ±1.0.
pub struct Decoder {
    handle: *mut Monitor,
    block_size: usize,
    sample_buf: Vec<f32>,
    min_freq_hz: f32,
}

// Monitor ownership is single-threaded (we never share the raw handle).
unsafe impl Send for Decoder {}

impl Decoder {
    /// Initialise a decoder watching `min_freq_hz..max_freq_hz` of the audio
    /// spectrum. Typical values for HF FT8: 100 Hz .. 3000 Hz.
    pub fn new(min_freq_hz: f32, max_freq_hz: f32) -> Result<Self, Ft8Error> {
        let cfg = MonitorConfig {
            f_min: min_freq_hz,
            f_max: max_freq_hz,
            sample_rate: 12_000,
            time_osr: 2,
            freq_osr: 2,
            protocol: FTX_PROTOCOL_FT8,
        };
        // SAFETY: cfg is a stack-local; shim mallocs and returns either a valid
        // pointer or NULL on OOM.
        let handle = unsafe { ft8_shim_monitor_new(&cfg) };
        if handle.is_null() {
            return Err(Ft8Error::AllocFailed);
        }
        let block_size = unsafe { ft8_shim_monitor_block_size(handle) } as usize;
        Ok(Self {
            handle,
            block_size,
            sample_buf: Vec::with_capacity(block_size * 4),
            min_freq_hz,
        })
    }

    /// Feed more audio into the waterfall. Safe to call with any chunk size —
    /// the decoder buffers up to one symbol block internally before handing it
    /// to CFT8's `monitor_process`.
    pub fn feed(&mut self, samples: &[f32]) {
        self.sample_buf.extend_from_slice(samples);
        while self.sample_buf.len() >= self.block_size {
            // SAFETY: handle is non-null while self is alive; sample_buf has at least block_size elements.
            unsafe { ft8_shim_monitor_process(self.handle, self.sample_buf.as_ptr()) };
            self.sample_buf.drain(0..self.block_size);
        }
    }

    /// Search the accumulated waterfall for candidate signals and LDPC-decode
    /// each one. Duplicates are filtered by textual message.
    pub fn decode(&mut self) -> Vec<DecodeResult> {
        const MAX_CANDIDATES: i32 = 120;
        const MIN_SCORE: i32 = 10;
        const MAX_LDPC_ITER: i32 = 20;

        let waterfall = unsafe { ft8_shim_monitor_waterfall(self.handle) };
        if waterfall.is_null() {
            return Vec::new();
        }

        let mut candidates = vec![FtxCandidate::default(); MAX_CANDIDATES as usize];
        let n_found = unsafe {
            ftx_find_candidates(
                waterfall,
                MAX_CANDIDATES,
                candidates.as_mut_ptr(),
                MIN_SCORE,
            )
        } as usize;

        let mut hash_if = FtxCallsignHashInterface {
            lookup_hash: Some(noop_lookup),
            save_hash: Some(noop_save),
        };
        let mut out: Vec<DecodeResult> = Vec::new();
        let mut seen: HashSet<String> = HashSet::new();

        for cand in candidates.iter().take(n_found) {
            let mut msg = FtxMessage::zeroed();
            let mut status = FtxDecodeStatus::default();
            let ok = unsafe {
                ftx_decode_candidate(waterfall, cand, MAX_LDPC_ITER, &mut msg, &mut status)
            };
            if !ok {
                continue;
            }
            let mut text_buf = [0i8; FTX_MAX_MESSAGE_LENGTH + 1];
            let mut offsets = FtxMessageOffsets::default();
            unsafe {
                ftx_message_decode(
                    &mut msg,
                    &mut hash_if,
                    text_buf.as_mut_ptr() as *mut c_types::c_char,
                    &mut offsets,
                );
            }
            let text = unsafe { CStr::from_ptr(text_buf.as_ptr() as *const c_types::c_char) }
                .to_string_lossy()
                .into_owned();
            if text.is_empty() || !seen.insert(text.clone()) {
                continue;
            }
            let freq_hz = if status.freq > 0.0 {
                status.freq
            } else {
                f32::from(cand.freq_offset) * 6.25 / 2.0 + self.min_freq_hz
            };
            let delta_time_s = if status.time != 0.0 {
                status.time
            } else {
                f32::from(cand.time_offset) * 0.160 / 2.0
            };
            let snr_db = (f32::from(cand.score) * 0.5).round() as i32;
            out.push(DecodeResult {
                text,
                snr_db,
                frequency_hz: freq_hz,
                delta_time_s,
            });
        }
        out
    }
}

impl Drop for Decoder {
    fn drop(&mut self) {
        // SAFETY: handle was produced by ft8_shim_monitor_new and hasn't been freed.
        unsafe { ft8_shim_monitor_free(self.handle) };
    }
}

unsafe extern "C" fn noop_lookup(_hash_type: i32, _hash: u32, _c11: *mut u8) -> bool {
    false
}
unsafe extern "C" fn noop_save(_c11: *const u8, _n22: u32) {}
