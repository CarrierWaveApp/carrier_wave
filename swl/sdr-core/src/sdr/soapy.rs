use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use chrono::Utc;
use num_complex::Complex;
use soapysdr::{Device, Direction, RxStream};
use tokio::sync::mpsc;
use tracing::{error, info};

use crate::error::SdrError;
use crate::sdr::{SdrCapabilities, SdrDevice, SdrInfo, StreamConfig};
use crate::types::{SdrId, TimestampedIqBuffer};

/// SDR backend using SoapySDR for local USB devices.
pub struct SoapySdrDevice {
    info: SdrInfo,
    args: soapysdr::Args,
    streaming: Arc<AtomicBool>,
    read_thread: Option<std::thread::JoinHandle<()>>,
}

impl SoapySdrDevice {
    /// Create from SoapySDR device arguments (as returned by enumerate).
    pub fn from_args(args: soapysdr::Args) -> Result<Self, SdrError> {
        let device =
            Device::new(args.clone()).map_err(|e| SdrError::ConnectionFailed(e.to_string()))?;

        let driver = args.get("driver").unwrap_or_default().to_string();
        let serial = args.get("serial").map(|s| s.to_string());
        let id = serial
            .clone()
            .unwrap_or_else(|| args.get("label").unwrap_or(&driver).to_string());

        let freq_ranges = device
            .frequency_range(Direction::Rx, 0)
            .map_err(|e| SdrError::ConnectionFailed(e.to_string()))?;
        let (freq_lo, freq_hi) = if let Some(r) = freq_ranges.first() {
            (r.minimum as u64, r.maximum as u64)
        } else {
            (0, 6_000_000_000)
        };

        let sample_rates_raw = device
            .get_sample_rate_range(Direction::Rx, 0)
            .map_err(|e| SdrError::ConnectionFailed(e.to_string()))?;
        let sample_rates: Vec<u32> = sample_rates_raw
            .iter()
            .flat_map(|r| {
                if (r.maximum - r.minimum).abs() < 1.0 {
                    vec![r.minimum as u32]
                } else {
                    // Provide some representative rates
                    vec![
                        r.minimum as u32,
                        ((r.minimum + r.maximum) / 2.0) as u32,
                        r.maximum as u32,
                    ]
                }
            })
            .collect();

        let antennas = device.antennas(Direction::Rx, 0).unwrap_or_default();
        let has_agc = device.has_gain_mode(Direction::Rx, 0).unwrap_or(false);

        let max_bandwidth = sample_rates.iter().copied().max().unwrap_or(2_400_000);

        let info = SdrInfo {
            id: SdrId::from(id),
            driver,
            label: args.get("label").map(|s| s.to_string()),
            serial,
            capabilities: SdrCapabilities {
                sample_rates,
                freq_range: (freq_lo, freq_hi),
                max_bandwidth,
                antennas,
                has_agc,
            },
            kiwi_status: None,
        };

        Ok(Self {
            info,
            args,
            streaming: Arc::new(AtomicBool::new(false)),
            read_thread: None,
        })
    }
}

impl SdrDevice for SoapySdrDevice {
    fn info(&self) -> &SdrInfo {
        &self.info
    }

    fn start_streaming(
        &mut self,
        config: StreamConfig,
    ) -> Result<mpsc::Receiver<TimestampedIqBuffer>, SdrError> {
        if self.streaming.load(Ordering::Relaxed) {
            return Err(SdrError::DeviceBusy("already streaming".into()));
        }

        let device = Device::new(self.args.clone())
            .map_err(|e| SdrError::ConnectionFailed(e.to_string()))?;

        device
            .set_frequency(Direction::Rx, 0, config.center_frequency as f64, ())
            .map_err(|e| SdrError::ConfigurationError(format!("set frequency: {e}")))?;
        device
            .set_sample_rate(Direction::Rx, 0, config.sample_rate as f64)
            .map_err(|e| SdrError::ConfigurationError(format!("set sample rate: {e}")))?;

        if let Some(ref ant) = config.antenna {
            device
                .set_antenna(Direction::Rx, 0, ant)
                .map_err(|e| SdrError::ConfigurationError(format!("set antenna: {e}")))?;
        }

        match &config.gain {
            crate::types::GainSetting::Auto => {
                let _ = device.set_gain_mode(Direction::Rx, 0, true);
            }
            crate::types::GainSetting::Manual(g) => {
                let _ = device.set_gain_mode(Direction::Rx, 0, false);
                device
                    .set_gain(Direction::Rx, 0, *g)
                    .map_err(|e| SdrError::ConfigurationError(format!("set gain: {e}")))?;
            }
        }

        let mut stream: RxStream<Complex<f32>> = device
            .rx_stream(&[0])
            .map_err(|e| SdrError::StreamingError(format!("create rx stream: {e}")))?;
        stream
            .activate(None)
            .map_err(|e| SdrError::StreamingError(format!("activate stream: {e}")))?;

        let (tx, rx) = mpsc::channel(32);
        self.streaming.store(true, Ordering::Relaxed);
        let streaming = self.streaming.clone();
        let center_freq = config.center_frequency;
        let sample_rate = config.sample_rate;

        info!(
            id = %self.info.id,
            center_freq,
            sample_rate,
            "SoapySDR starting stream"
        );

        let buf_size = 16384;
        let handle = std::thread::spawn(move || {
            let mut buf = vec![Complex::new(0.0f32, 0.0f32); buf_size];

            while streaming.load(Ordering::Relaxed) {
                match stream.read(&mut [&mut buf], 1_000_000) {
                    Ok(n) => {
                        let samples = buf[..n].to_vec();
                        let buffer = TimestampedIqBuffer {
                            timestamp: Utc::now(),
                            center_frequency: center_freq,
                            sample_rate,
                            samples: Arc::new(samples),
                        };
                        if tx.blocking_send(buffer).is_err() {
                            break;
                        }
                    }
                    Err(e) => {
                        error!(error = %e, "SoapySDR read error");
                        // Brief sleep to avoid spin on persistent errors
                        std::thread::sleep(std::time::Duration::from_millis(10));
                    }
                }
            }

            let _ = stream.deactivate(None);
            // device dropped here, releasing hardware
        });

        self.read_thread = Some(handle);
        Ok(rx)
    }

    fn stop_streaming(&mut self) -> Result<(), SdrError> {
        self.streaming.store(false, Ordering::Relaxed);
        if let Some(handle) = self.read_thread.take() {
            handle
                .join()
                .map_err(|_| SdrError::StreamingError("thread panicked".into()))?;
        }
        info!(id = %self.info.id, "SoapySDR stopped");
        Ok(())
    }

    fn is_streaming(&self) -> bool {
        self.streaming.load(Ordering::Relaxed)
    }
}

/// Enumerate all SoapySDR devices currently connected.
pub fn enumerate_devices() -> Result<Vec<soapysdr::Args>, SdrError> {
    soapysdr::enumerate("").map_err(|e| SdrError::DeviceNotFound(format!("enumerate failed: {e}")))
}
