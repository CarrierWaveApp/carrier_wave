//! IQ source abstraction: a blocking, pull-based reader driven by the
//! pipeline's worker thread.

use num_complex::Complex32;

use crate::error::SdrError;

/// Which backend to open.
#[derive(Debug, Clone, PartialEq)]
pub enum SourceSpec {
    /// rtl_tcp protocol server (`rtl_tcp`, SDRplay `rsp_tcp`, …).
    RtlTcp { host: String, port: u16 },
    /// SoapySDR device, by Soapy args string (e.g. `driver=sdrplay`).
    Soapy { args: String },
    /// Synthetic tones at the given offsets (Hz) from the initial center,
    /// plus noise. For development and tests without hardware.
    Tone { offsets_hz: Vec<f64> },
}

/// Device settings applied when the source opens.
#[derive(Debug, Clone, PartialEq)]
pub struct SourceConfig {
    pub sample_rate: u32,
    /// Hardware center frequency (Hz) to tune to on open.
    pub center_hz: f64,
    /// Manual gain in dB; `None` selects AGC / automatic gain.
    pub gain_db: Option<f64>,
    /// rtl_tcp direct-sampling mode: 0 off, 1 I branch, 2 Q branch.
    pub direct_sampling: u8,
}

/// A blocking IQ reader. Implementations own their device/socket and are
/// used from a single worker thread.
pub trait IqSource: Send {
    /// Read the next block of samples. Returns `Ok(None)` when the stream has
    /// ended. Implementations should time out within ~0.5 s so the caller can
    /// observe a stop request; a timeout yields `Ok(Some(empty))`.
    fn read_block(&mut self) -> Result<Option<Vec<Complex32>>, SdrError>;

    /// Retune the hardware center frequency (Hz).
    fn set_center_hz(&mut self, hz: f64) -> Result<(), SdrError>;

    /// Actual sample rate in samples/second.
    fn sample_rate(&self) -> f64;
}

/// Open a source for `spec` with `config`.
pub fn open(spec: &SourceSpec, config: &SourceConfig) -> Result<Box<dyn IqSource>, SdrError> {
    if config.sample_rate == 0 {
        return Err(SdrError::Config("sample rate must be > 0".into()));
    }
    match spec {
        SourceSpec::RtlTcp { host, port } => {
            Ok(Box::new(crate::rtl_tcp::RtlTcpSource::connect(host, *port, config)?))
        }
        SourceSpec::Soapy { args } => open_soapy(args, config),
        SourceSpec::Tone { offsets_hz } => {
            let tones: Vec<f64> = offsets_hz.iter().map(|off| config.center_hz + off).collect();
            Ok(Box::new(crate::tone::ToneSource::new(config.sample_rate, config.center_hz, tones, true)))
        }
    }
}

#[cfg(target_os = "macos")]
fn open_soapy(args: &str, config: &SourceConfig) -> Result<Box<dyn IqSource>, SdrError> {
    Ok(Box::new(crate::soapy::SoapySource::open(args, config)?))
}

#[cfg(not(target_os = "macos"))]
fn open_soapy(_args: &str, _config: &SourceConfig) -> Result<Box<dyn IqSource>, SdrError> {
    Err(SdrError::SoapyUnavailable("SoapySDR is only supported on macOS".into()))
}
