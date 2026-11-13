use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use uuid::Uuid;

use crate::recording::flac::FlacWriter;

/// Manages segmented audio file output with automatic rotation.
pub struct SegmentWriter {
    /// Base directory for this recording's segments.
    base_dir: PathBuf,
    /// Recording ID (used in filenames).
    recording_id: Uuid,
    /// Audio sample rate.
    sample_rate: u32,
    /// Maximum segment duration in seconds.
    max_duration_secs: f64,
    /// Current segment number.
    current_segment: u32,
    /// Current active writer.
    writer: Option<FlacWriter>,
    /// When the current segment started.
    segment_start: Option<DateTime<Utc>>,
    /// Completed segments metadata.
    completed: Vec<SegmentMeta>,
}

/// Metadata about a completed segment.
#[derive(Debug, Clone)]
pub struct SegmentMeta {
    pub segment_number: u32,
    pub file_path: PathBuf,
    pub duration_secs: f64,
    pub file_size_bytes: u64,
    pub started_at: DateTime<Utc>,
    pub ended_at: DateTime<Utc>,
}

impl SegmentWriter {
    pub fn new(
        base_dir: &Path,
        recording_id: Uuid,
        sample_rate: u32,
        max_duration_secs: f64,
    ) -> std::io::Result<Self> {
        std::fs::create_dir_all(base_dir)?;
        Ok(Self {
            base_dir: base_dir.to_path_buf(),
            recording_id,
            sample_rate,
            max_duration_secs,
            current_segment: 0,
            writer: None,
            segment_start: None,
            completed: Vec::new(),
        })
    }

    /// Write audio samples, rotating segments as needed.
    pub fn write_samples(&mut self, samples: &[f32]) -> std::io::Result<()> {
        // Open a new segment if needed
        if self.writer.is_none() {
            self.open_new_segment()?;
        }

        let writer = self.writer.as_mut().unwrap();
        writer.write_samples(samples)?;

        // Check if segment duration exceeded
        if writer.duration_secs() >= self.max_duration_secs {
            self.rotate()?;
        }

        Ok(())
    }

    /// Force-close the current segment and return metadata for all completed segments.
    pub fn finalize(mut self) -> std::io::Result<Vec<SegmentMeta>> {
        self.close_current_segment()?;
        Ok(self.completed)
    }

    /// Override the start timestamp of the current (or next) segment.
    /// Used to set the first segment's start to the reference time for alignment.
    pub fn set_segment_start(&mut self, ts: DateTime<Utc>) {
        self.segment_start = Some(ts);
    }

    /// Get metadata for completed segments so far.
    pub fn completed_segments(&self) -> &[SegmentMeta] {
        &self.completed
    }

    fn open_new_segment(&mut self) -> std::io::Result<()> {
        let filename = format!("{}_seg{:04}.wav", self.recording_id, self.current_segment);
        let path = self.base_dir.join(&filename);
        let writer = FlacWriter::create(&path, self.sample_rate)?;
        self.writer = Some(writer);
        self.segment_start = Some(Utc::now());
        Ok(())
    }

    fn close_current_segment(&mut self) -> std::io::Result<()> {
        if let Some(writer) = self.writer.take() {
            let duration = writer.duration_secs();
            let data_bytes = writer.data_bytes();
            let filename = format!("{}_seg{:04}.wav", self.recording_id, self.current_segment);
            let path = self.base_dir.join(&filename);

            writer.finalize()?;

            let file_size = std::fs::metadata(&path)
                .map(|m| m.len())
                .unwrap_or(data_bytes + 44);

            let started = self.segment_start.unwrap_or_else(Utc::now);
            self.completed.push(SegmentMeta {
                segment_number: self.current_segment,
                file_path: path,
                duration_secs: duration,
                file_size_bytes: file_size,
                started_at: started,
                ended_at: Utc::now(),
            });
        }
        Ok(())
    }

    fn rotate(&mut self) -> std::io::Result<()> {
        self.close_current_segment()?;
        self.current_segment += 1;
        self.open_new_segment()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn creates_segments() {
        let dir = tempfile::tempdir().unwrap();
        let rec_id = Uuid::new_v4();
        let mut writer = SegmentWriter::new(dir.path(), rec_id, 8_000, 1.0).unwrap();

        // Write 2.5 seconds of audio at 8kHz → should create 3 segments
        let samples = vec![0.0f32; 8_000]; // 1 second
        writer.write_samples(&samples).unwrap(); // seg 0: 1.0s → rotate
        writer.write_samples(&samples).unwrap(); // seg 1: 1.0s → rotate
        let half = vec![0.0f32; 4_000]; // 0.5 seconds
        writer.write_samples(&half).unwrap(); // seg 2: 0.5s, still open

        let segments = writer.finalize().unwrap();
        assert_eq!(segments.len(), 3);
        assert!((segments[0].duration_secs - 1.0).abs() < 0.01);
        assert!((segments[1].duration_secs - 1.0).abs() < 0.01);
        assert!((segments[2].duration_secs - 0.5).abs() < 0.01);

        // Verify files exist
        for seg in &segments {
            assert!(seg.file_path.exists());
            assert!(seg.file_size_bytes > 44); // at least WAV header
        }
    }

    #[test]
    fn empty_finalize_is_ok() {
        let dir = tempfile::tempdir().unwrap();
        let rec_id = Uuid::new_v4();
        let writer = SegmentWriter::new(dir.path(), rec_id, 48_000, 300.0).unwrap();
        let segments = writer.finalize().unwrap();
        assert!(segments.is_empty());
    }
}
