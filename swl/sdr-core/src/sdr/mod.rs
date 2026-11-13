pub mod discovery;
pub mod kiwi;
pub mod kiwi_directory;
pub mod mock;
#[cfg(feature = "soapy")]
pub mod soapy;

use crate::error::SdrError;
use crate::types::{GainSetting, SdrId, TimestampedIqBuffer};
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;

/// Commands that can be sent to an active SDR stream.
#[derive(Debug, Clone)]
pub enum SdrCommand {
    /// Retune the SDR to a new center frequency (Hz).
    SetFrequency(u64),
}

/// Capabilities reported by an SDR device.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SdrCapabilities {
    /// Supported sample rates.
    pub sample_rates: Vec<u32>,
    /// Frequency range the device supports (Hz).
    pub freq_range: (u64, u64),
    /// Maximum instantaneous bandwidth (Hz).
    pub max_bandwidth: u32,
    /// Available antenna ports.
    pub antennas: Vec<String>,
    /// Whether the device supports AGC.
    pub has_agc: bool,
}

/// Live status data from the KiwiSDR directory.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KiwiStatus {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub users: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub users_max: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub grid: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub snr: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub antenna: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub location: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lat: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lon: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offline: Option<bool>,
}

/// Static info about a discovered SDR.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SdrInfo {
    pub id: SdrId,
    pub driver: String,
    pub label: Option<String>,
    pub serial: Option<String>,
    pub capabilities: SdrCapabilities,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kiwi_status: Option<KiwiStatus>,
}

/// Configuration to apply when starting a stream.
#[derive(Debug, Clone)]
pub struct StreamConfig {
    pub center_frequency: u64,
    pub sample_rate: u32,
    pub bandwidth: u32,
    pub gain: GainSetting,
    pub antenna: Option<String>,
}

/// Trait abstracting over different SDR hardware backends.
///
/// Implementations are expected to perform blocking I/O on a dedicated
/// thread and send buffers via the returned channel.
pub trait SdrDevice: Send + Sync {
    /// Get static info about this device.
    fn info(&self) -> &SdrInfo;

    /// Configure and start streaming IQ data.
    ///
    /// Returns a receiver that yields timestamped IQ buffers.
    /// The implementation should spawn its own read thread.
    fn start_streaming(
        &mut self,
        config: StreamConfig,
    ) -> Result<mpsc::Receiver<TimestampedIqBuffer>, SdrError>;

    /// Stop streaming and release hardware resources.
    fn stop_streaming(&mut self) -> Result<(), SdrError>;

    /// Check if the device is currently streaming.
    fn is_streaming(&self) -> bool;

    /// Get a command sender for sending commands to the active stream.
    /// Returns `None` if the device doesn't support mid-stream commands
    /// or is not currently streaming.
    fn command_sender(&self) -> Option<mpsc::Sender<SdrCommand>> {
        None
    }
}
