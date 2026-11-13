use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SdrRow {
    pub id: String,
    pub driver: String,
    pub label: Option<String>,
    pub serial: Option<String>,
    pub url: Option<String>,
    pub sample_rate: Option<i64>,
    pub antenna: Option<String>,
    pub last_seen: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CaptureRow {
    pub id: Uuid,
    pub sdr_id: String,
    pub center_frequency: i64,
    pub bandwidth: i64,
    pub sample_rate: i64,
    pub consumer_count: i64,
    pub started_at: DateTime<Utc>,
    pub stopped_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecordingRow {
    pub id: Uuid,
    pub capture_id: Option<Uuid>,
    pub sdr_id: String,
    pub frequency: i64,
    pub bandwidth: i64,
    pub mode: String,
    pub status: String,
    pub started_at: DateTime<Utc>,
    pub stopped_at: Option<DateTime<Utc>>,
    pub retention_days: i64,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptionRow {
    pub id: Uuid,
    /// References the `recordings` table. `None` for uploaded-recording transcriptions.
    pub recording_id: Option<Uuid>,
    pub text: String,
    pub status: String,
    pub wpm_estimate: Option<f64>,
    pub char_count: i64,
    pub error_message: Option<String>,
    pub started_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    /// JSON-serialized StructuredTranscript (from upload-based transcription).
    pub structured_transcript: Option<String>,
    /// 0.0..1.0 progress for async transcription.
    pub progress: Option<f64>,
    /// Links to uploaded_recordings table when transcription is from an upload.
    pub uploaded_recording_id: Option<Uuid>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadedRecordingRow {
    pub id: Uuid,
    pub original_filename: String,
    pub original_format: String,
    pub sample_rate: Option<i64>,
    pub duration_secs: Option<f64>,
    pub status: String,
    pub error_message: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SegmentRow {
    pub id: Uuid,
    pub recording_id: Uuid,
    pub segment_number: i64,
    pub file_path: String,
    pub duration_secs: f64,
    pub file_size_bytes: i64,
    pub sample_rate: i64,
    pub started_at: DateTime<Utc>,
    pub ended_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
}
