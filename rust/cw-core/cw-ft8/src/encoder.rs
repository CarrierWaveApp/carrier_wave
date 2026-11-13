//! Safe Rust wrapper around `ft8_lib`'s `ftx_message_encode` + `ft8_encode`
//! plus the continuous-phase 8-FSK synthesizer. Mirrors `FT8Encoder.swift`.

use std::f64::consts::TAU;
use std::ffi::CString;

use crate::ffi;

const SAMPLE_RATE_HZ: i32 = 12_000;
const SYMBOL_PERIOD_SEC: f64 = 0.160;
const TONE_SPACING_HZ: f64 = 6.25;

#[derive(Debug, thiserror::Error)]
pub enum Ft8EncodeError {
    #[error("empty message")]
    Empty,
    #[error("ft8_lib encode failed (rc={rc}) for: {message}")]
    EncodeFailed { rc: u32, message: String },
    #[error("invalid message text (interior NUL)")]
    InvalidText,
    #[error("ft8_encode produced an empty tone sequence for: {0}")]
    EmptyTones(String),
}

/// Encode an FT8 message into 12 kHz mono float audio samples.
pub fn encode(message: &str, frequency_hz: f64) -> Result<Vec<f32>, Ft8EncodeError> {
    encode_with_sample_rate(message, frequency_hz, SAMPLE_RATE_HZ)
}

pub fn encode_with_sample_rate(
    message: &str,
    frequency_hz: f64,
    sample_rate: i32,
) -> Result<Vec<f32>, Ft8EncodeError> {
    if message.is_empty() {
        return Err(Ft8EncodeError::Empty);
    }
    let tones = pack_and_encode(message)?;
    Ok(synthesize_tones(&tones, frequency_hz, sample_rate))
}

fn pack_and_encode(message: &str) -> Result<Vec<u8>, Ft8EncodeError> {
    let c_message = CString::new(message).map_err(|_| Ft8EncodeError::InvalidText)?;

    let mut ftx_message: ffi::ftx_message_t = unsafe { std::mem::zeroed() };
    // SAFETY: zeroed ftx_message_t is the valid initial state per ft8_lib API.
    unsafe {
        ffi::ftx_message_init(&mut ftx_message);
    }

    let rc = unsafe { ffi::ftx_message_encode(&mut ftx_message, std::ptr::null_mut(), c_message.as_ptr()) };
    if rc != ffi::ftx_message_rc_t_FTX_MESSAGE_RC_OK {
        return Err(Ft8EncodeError::EncodeFailed {
            rc,
            message: message.to_string(),
        });
    }

    let nn = ffi::FT8_NN as usize;
    let mut tones = vec![0u8; nn];
    // SAFETY: payload is a fixed-size array of bytes; we pass its address as a
    // `*const u8`, exactly like the Swift call site does via withUnsafeBytes.
    unsafe {
        ffi::ft8_encode(ftx_message.payload.as_ptr(), tones.as_mut_ptr());
    }
    if tones.iter().all(|t| *t == 0) {
        return Err(Ft8EncodeError::EmptyTones(message.to_string()));
    }
    Ok(tones)
}

fn synthesize_tones(tones: &[u8], frequency_hz: f64, sample_rate: i32) -> Vec<f32> {
    let symbol_samples = (sample_rate as f64 * SYMBOL_PERIOD_SEC) as usize;
    let mut out = vec![0f32; tones.len() * symbol_samples];
    let mut phase = 0f64;

    for (symbol_index, &tone) in tones.iter().enumerate() {
        let tone_freq = frequency_hz + tone as f64 * TONE_SPACING_HZ;
        let phase_inc = TAU * tone_freq / sample_rate as f64;
        for sample_offset in 0..symbol_samples {
            let idx = symbol_index * symbol_samples + sample_offset;
            out[idx] = phase.sin() as f32;
            phase += phase_inc;
            if phase >= TAU {
                phase -= TAU;
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_produces_expected_sample_count() {
        let samples = encode("CQ K1ABC FN42", 1500.0).expect("encode");
        // 79 symbols * 0.160s * 12000Hz = 151,680 samples.
        assert_eq!(samples.len(), 79 * (0.160 * 12_000.0) as usize);
    }

    #[test]
    fn encode_round_trip_decodes_to_same_text() {
        let message = "CQ K1ABC FN42";
        let samples = encode(message, 1500.0).expect("encode");
        let results = crate::decode_default(&samples);
        assert!(
            results.iter().any(|r| r.raw_text == message),
            "round-trip should recover original message; got {:?}",
            results.iter().map(|r| &r.raw_text).collect::<Vec<_>>()
        );
    }

    #[test]
    fn encode_empty_message_errors() {
        assert!(matches!(encode("", 1500.0), Err(Ft8EncodeError::Empty)));
    }
}
