//! Error type for SDR sources and the panadapter pipeline.

#[derive(Debug, thiserror::Error)]
pub enum SdrError {
    #[error("SoapySDR not available: {0}")]
    SoapyUnavailable(String),
    #[error("SDR device error: {0}")]
    Device(String),
    #[error("SDR I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid SDR configuration: {0}")]
    Config(String),
}
