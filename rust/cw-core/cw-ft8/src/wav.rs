//! Minimal 12 kHz / mono / 16-bit PCM WAV loader. Port of the WAV-loading half
//! of `FT8Decoder.swift` (the rest is the decode pipeline in `decoder.rs`).
//!
//! Faithful to Swift: same chunk scan (data chunk may follow extra chunks),
//! same format gate, same i16→f32 scaling by 32768.0.

use std::fs;
use std::path::Path;

const RIFF_MARKER: u32 = 0x4646_4952; // "RIFF" LE
const WAVE_MARKER: u32 = 0x4556_4157; // "WAVE" LE
const DATA_MARKER: u32 = 0x6174_6164; // "data" LE

#[derive(Debug, thiserror::Error)]
pub enum WavError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid WAV: {0}")]
    Invalid(&'static str),
}

/// Load a 12 kHz mono 16-bit PCM WAV into f32 samples in [-1.0, 1.0).
pub fn load(path: impl AsRef<Path>) -> Result<Vec<f32>, WavError> {
    let bytes = fs::read(path)?;
    load_from_bytes(&bytes)
}

pub fn load_from_bytes(bytes: &[u8]) -> Result<Vec<f32>, WavError> {
    if bytes.len() < 44 {
        return Err(WavError::Invalid("file too small for WAV header"));
    }
    if read_u32(bytes, 0) != RIFF_MARKER {
        return Err(WavError::Invalid("not a RIFF file"));
    }
    if read_u32(bytes, 8) != WAVE_MARKER {
        return Err(WavError::Invalid("not a WAVE file"));
    }
    let audio_format = read_u16(bytes, 20);
    let num_channels = read_u16(bytes, 22);
    let sample_rate = read_u32(bytes, 24);
    let bits_per_sample = read_u16(bytes, 34);
    if audio_format != 1 {
        return Err(WavError::Invalid("expected PCM format"));
    }
    if sample_rate != 12_000 {
        return Err(WavError::Invalid("expected 12000 Hz"));
    }
    if bits_per_sample != 16 {
        return Err(WavError::Invalid("expected 16-bit samples"));
    }
    if num_channels != 1 {
        return Err(WavError::Invalid("expected mono"));
    }

    let data_offset = find_data_chunk(bytes)?;
    let audio = &bytes[data_offset..];
    let sample_count = audio.len() / 2;
    let mut samples = Vec::with_capacity(sample_count);
    for idx in 0..sample_count {
        let lo = audio[idx * 2] as i16;
        let hi = audio[idx * 2 + 1] as i16;
        let raw = (hi << 8) | (lo & 0xFF);
        samples.push(raw as f32 / 32_768.0);
    }
    Ok(samples)
}

fn find_data_chunk(bytes: &[u8]) -> Result<usize, WavError> {
    let mut offset = 12usize; // past RIFF + size + WAVE
    while offset + 8 <= bytes.len() {
        let chunk_id = read_u32(bytes, offset);
        let chunk_size = read_u32(bytes, offset + 4) as usize;
        if chunk_id == DATA_MARKER {
            return Ok(offset + 8);
        }
        offset += 8 + chunk_size;
    }
    Err(WavError::Invalid("no data chunk found"))
}

fn read_u32(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap())
}

fn read_u16(bytes: &[u8], offset: usize) -> u16 {
    u16::from_le_bytes(bytes[offset..offset + 2].try_into().unwrap())
}
