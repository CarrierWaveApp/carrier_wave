use thiserror::Error;

#[derive(Debug, Error)]
pub enum SdrError {
    #[error("SDR device not found: {0}")]
    DeviceNotFound(String),

    #[error("SDR connection failed: {0}")]
    ConnectionFailed(String),

    #[error("SDR configuration error: {0}")]
    ConfigurationError(String),

    #[error("SDR streaming error: {0}")]
    StreamingError(String),

    #[error("device busy: {0}")]
    DeviceBusy(String),
}

#[derive(Debug, Error)]
pub enum CaptureError {
    #[error("capture conflict: {0}")]
    Conflict(String),

    #[error("no SDR available for request: {0}")]
    NoSdrAvailable(String),

    #[error("capture session error: {0}")]
    SessionError(String),
}

#[derive(Debug, Error)]
pub enum RecordingError {
    #[error("recording not found: {0}")]
    NotFound(uuid::Uuid),

    #[error("DSP error: {0}")]
    DspError(String),

    #[error("FLAC encoding error: {0}")]
    FlacError(String),

    #[error("file I/O error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("incompatible recordings: {0}")]
    Incompatible(String),
}

#[derive(Debug, Error)]
pub enum DbError {
    #[error("database error: {0}")]
    Sqlite(#[from] rusqlite::Error),

    #[error("migration failed: {0}")]
    MigrationFailed(String),

    #[error("record not found: {0}")]
    NotFound(String),
}

#[derive(Debug, Error)]
pub enum TranscriptionError {
    #[error("transcription not found: {0}")]
    NotFound(uuid::Uuid),

    #[error("invalid recording for transcription: {0}")]
    InvalidRecording(String),

    #[error("transcription processing failed: {0}")]
    ProcessingFailed(String),

    #[error("database error: {0}")]
    DbError(#[from] DbError),

    #[error("recording error: {0}")]
    RecordingError(#[from] RecordingError),
}

#[derive(Debug, Error)]
pub enum UploadError {
    #[error("no file in upload")]
    NoFile,

    #[error("unsupported format: {0}")]
    UnsupportedFormat(String),

    #[error("file I/O error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("decode error: {0}")]
    DecodeError(String),

    #[error("database error: {0}")]
    DbError(#[from] DbError),
}

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("config file error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("config parse error: {0}")]
    ParseError(#[from] toml::de::Error),

    #[error("invalid configuration: {0}")]
    Invalid(String),
}

#[derive(Debug, Error)]
pub enum TimeError {
    #[error("NTP sync failed: {0}")]
    NtpSyncFailed(String),

    #[error("no time source available")]
    NoTimeSource,
}
