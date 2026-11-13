//! Multi-format audio decoding using symphonia.
//!
//! Accepts CAF (iOS native), M4A/AAC, WAV, and AIFF files and decodes them
//! to mono f32 PCM samples.

use std::path::Path;

use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

use crate::error::RecordingError;

/// Decode any supported audio file to mono f32 PCM.
///
/// Returns `(sample_rate, samples)`.
pub fn decode_to_pcm(input_path: &Path) -> Result<(u32, Vec<f32>), RecordingError> {
    let file = std::fs::File::open(input_path)?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());

    // Provide format hint from file extension
    let mut hint = Hint::new();
    if let Some(ext) = input_path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let probed = symphonia::default::get_probe()
        .format(
            &hint,
            mss,
            &FormatOptions::default(),
            &MetadataOptions::default(),
        )
        .map_err(|e| RecordingError::DspError(format!("failed to probe audio format: {e}")))?;

    let mut format = probed.format;

    // Find the first audio track
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
        .ok_or_else(|| RecordingError::DspError("no audio track found".into()))?;

    let track_id = track.id;
    let sample_rate = track
        .codec_params
        .sample_rate
        .ok_or_else(|| RecordingError::DspError("no sample rate in track".into()))?;
    let channels = track.codec_params.channels.map(|c| c.count()).unwrap_or(1);

    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &DecoderOptions::default())
        .map_err(|e| RecordingError::DspError(format!("failed to create decoder: {e}")))?;

    let mut all_samples: Vec<f32> = Vec::new();

    loop {
        let packet = match format.next_packet() {
            Ok(packet) => packet,
            Err(symphonia::core::errors::Error::IoError(ref e))
                if e.kind() == std::io::ErrorKind::UnexpectedEof =>
            {
                break;
            }
            Err(e) => {
                return Err(RecordingError::DspError(format!(
                    "failed to read packet: {e}"
                )));
            }
        };

        if packet.track_id() != track_id {
            continue;
        }

        let decoded = match decoder.decode(&packet) {
            Ok(buf) => buf,
            Err(symphonia::core::errors::Error::DecodeError(e)) => {
                tracing::warn!(error = %e, "decode error, skipping packet");
                continue;
            }
            Err(e) => {
                return Err(RecordingError::DspError(format!(
                    "failed to decode packet: {e}"
                )));
            }
        };

        let spec = *decoded.spec();
        let num_frames = decoded.frames();
        let mut sample_buf = SampleBuffer::<f32>::new(num_frames as u64, spec);
        sample_buf.copy_interleaved_ref(decoded);

        let interleaved = sample_buf.samples();

        if channels == 1 {
            all_samples.extend_from_slice(interleaved);
        } else {
            // Downmix to mono by averaging channels
            for chunk in interleaved.chunks(channels) {
                let sum: f32 = chunk.iter().sum();
                all_samples.push(sum / channels as f32);
            }
        }
    }

    if all_samples.is_empty() {
        return Err(RecordingError::DspError("decoded audio is empty".into()));
    }

    tracing::info!(
        path = %input_path.display(),
        sample_rate = sample_rate,
        samples = all_samples.len(),
        duration_secs = format!("{:.1}", all_samples.len() as f64 / sample_rate as f64),
        "Decoded audio file"
    );

    Ok((sample_rate, all_samples))
}

/// Write mono f32 PCM samples to a WAV file.
pub fn write_wav(path: &Path, sample_rate: u32, samples: &[f32]) -> Result<(), RecordingError> {
    use std::io::Write;

    let num_samples = samples.len() as u32;
    let byte_rate = sample_rate * 2; // 16-bit mono
    let data_size = num_samples * 2;
    let file_size = 36 + data_size;

    let mut file = std::fs::File::create(path)?;

    // RIFF header
    file.write_all(b"RIFF")?;
    file.write_all(&file_size.to_le_bytes())?;
    file.write_all(b"WAVE")?;

    // fmt chunk
    file.write_all(b"fmt ")?;
    file.write_all(&16u32.to_le_bytes())?; // chunk size
    file.write_all(&1u16.to_le_bytes())?; // PCM format
    file.write_all(&1u16.to_le_bytes())?; // mono
    file.write_all(&sample_rate.to_le_bytes())?;
    file.write_all(&byte_rate.to_le_bytes())?;
    file.write_all(&2u16.to_le_bytes())?; // block align
    file.write_all(&16u16.to_le_bytes())?; // bits per sample

    // data chunk
    file.write_all(b"data")?;
    file.write_all(&data_size.to_le_bytes())?;

    for &s in samples {
        let clamped = s.clamp(-1.0, 1.0);
        let i16_val = (clamped * 32767.0) as i16;
        file.write_all(&i16_val.to_le_bytes())?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_wav() {
        let dir = tempfile::tempdir().unwrap();
        let wav_path = dir.path().join("test.wav");

        // Generate a simple sine wave
        let sample_rate = 8000u32;
        let samples: Vec<f32> = (0..8000)
            .map(|i| (2.0 * std::f32::consts::PI * 440.0 * i as f32 / sample_rate as f32).sin())
            .collect();

        write_wav(&wav_path, sample_rate, &samples).unwrap();
        let (decoded_sr, decoded) = decode_to_pcm(&wav_path).unwrap();

        assert_eq!(decoded_sr, sample_rate);
        assert_eq!(decoded.len(), samples.len());

        // Check first few samples are close (16-bit quantization adds noise)
        for i in 0..100 {
            assert!(
                (decoded[i] - samples[i]).abs() < 0.001,
                "sample {} differs: {} vs {}",
                i,
                decoded[i],
                samples[i]
            );
        }
    }
}
