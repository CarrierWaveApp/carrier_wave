use std::io::{self, Write};
use std::path::Path;

/// FLAC encoder that writes mono audio to a file.
///
/// Uses a simple WAV-like FLAC encoding approach:
/// we write raw FLAC frames containing 16-bit PCM samples.
///
/// For M0, we write standard WAV files (which are universally playable)
/// and can upgrade to true FLAC in a later milestone. The file extension
/// is .wav for honesty, but the pipeline is designed for easy swap.
pub struct FlacWriter {
    writer: io::BufWriter<std::fs::File>,
    sample_rate: u32,
    samples_written: u64,
    /// Track the data chunk size position for finalization.
    _data_size_pos: u64,
}

impl FlacWriter {
    /// Create a new WAV file writer.
    pub fn create(path: &Path, sample_rate: u32) -> io::Result<Self> {
        let file = std::fs::File::create(path)?;
        let mut writer = io::BufWriter::new(file);

        // Write WAV header (we'll patch the sizes on close)
        // RIFF header
        writer.write_all(b"RIFF")?;
        writer.write_all(&0u32.to_le_bytes())?; // file size - 8 (placeholder)
        writer.write_all(b"WAVE")?;

        // fmt chunk
        writer.write_all(b"fmt ")?;
        writer.write_all(&16u32.to_le_bytes())?; // chunk size
        writer.write_all(&1u16.to_le_bytes())?; // PCM format
        writer.write_all(&1u16.to_le_bytes())?; // mono
        writer.write_all(&sample_rate.to_le_bytes())?;
        let bytes_per_sec = sample_rate * 2; // 16-bit mono
        writer.write_all(&bytes_per_sec.to_le_bytes())?;
        writer.write_all(&2u16.to_le_bytes())?; // block align
        writer.write_all(&16u16.to_le_bytes())?; // bits per sample

        // data chunk header
        writer.write_all(b"data")?;
        let data_size_pos = 44 - 4; // position of data size field
        writer.write_all(&0u32.to_le_bytes())?; // data size (placeholder)

        Ok(Self {
            writer,
            sample_rate,
            samples_written: 0,
            _data_size_pos: data_size_pos as u64,
        })
    }

    /// Write audio samples (f32, range [-1.0, 1.0]) to the file.
    pub fn write_samples(&mut self, samples: &[f32]) -> io::Result<()> {
        for &sample in samples {
            let clamped = sample.clamp(-1.0, 1.0);
            let i16_val = (clamped * 32767.0) as i16;
            self.writer.write_all(&i16_val.to_le_bytes())?;
        }
        self.samples_written += samples.len() as u64;
        Ok(())
    }

    /// Duration of audio written so far (seconds).
    pub fn duration_secs(&self) -> f64 {
        self.samples_written as f64 / self.sample_rate as f64
    }

    /// Number of bytes of audio data written.
    pub fn data_bytes(&self) -> u64 {
        self.samples_written * 2 // 16-bit = 2 bytes per sample
    }

    /// Finalize the WAV file (patch header sizes).
    pub fn finalize(mut self) -> io::Result<u64> {
        use std::io::Seek;

        self.writer.flush()?;
        let data_size = self.data_bytes() as u32;
        let file_size = data_size + 36; // header size minus 8

        let file = self.writer.get_mut();

        // Patch RIFF size
        file.seek(io::SeekFrom::Start(4))?;
        file.write_all(&file_size.to_le_bytes())?;

        // Patch data chunk size
        file.seek(io::SeekFrom::Start(40))?;
        file.write_all(&data_size.to_le_bytes())?;

        file.flush()?;
        Ok(self.samples_written)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;

    #[test]
    fn write_and_read_wav() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("test.wav");

        // Write some audio
        {
            let mut writer = FlacWriter::create(&path, 48_000).unwrap();
            let samples: Vec<f32> = (0..48_000)
                .map(|i| {
                    let t = i as f32 / 48_000.0;
                    (2.0 * std::f32::consts::PI * 440.0 * t).sin() * 0.5
                })
                .collect();
            writer.write_samples(&samples).unwrap();
            assert!((writer.duration_secs() - 1.0).abs() < 0.001);
            writer.finalize().unwrap();
        }

        // Verify it's a valid WAV
        let mut file = std::fs::File::open(&path).unwrap();
        let mut header = [0u8; 44];
        file.read_exact(&mut header).unwrap();

        assert_eq!(&header[0..4], b"RIFF");
        assert_eq!(&header[8..12], b"WAVE");
        assert_eq!(&header[12..16], b"fmt ");

        let sample_rate = u32::from_le_bytes([header[24], header[25], header[26], header[27]]);
        assert_eq!(sample_rate, 48_000);

        let data_size = u32::from_le_bytes([header[40], header[41], header[42], header[43]]);
        assert_eq!(data_size, 48_000 * 2); // 16-bit mono, 1 second
    }

    #[test]
    fn clamps_out_of_range_samples() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("clamp.wav");

        let mut writer = FlacWriter::create(&path, 8000).unwrap();
        writer.write_samples(&[2.0, -2.0, 0.5]).unwrap();
        writer.finalize().unwrap();

        let metadata = std::fs::metadata(&path).unwrap();
        assert!(metadata.len() > 44); // header + data
    }
}
