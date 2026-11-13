use std::f32::consts::PI;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use chrono::Utc;
use num_complex::Complex;
use tokio::sync::mpsc;
use tracing::info;

use crate::error::SdrError;
use crate::sdr::{SdrCapabilities, SdrCommand, SdrDevice, SdrInfo, StreamConfig};
use crate::types::{SdrId, TimestampedIqBuffer};

/// Configuration for the mock SDR signal generator.
#[derive(Debug, Clone)]
pub struct MockConfig {
    /// Tones to generate, as (offset_hz, amplitude) pairs.
    /// Offset is relative to center frequency.
    pub tones: Vec<(f64, f32)>,
    /// RMS noise amplitude.
    pub noise_amplitude: f32,
    /// Number of samples per buffer.
    pub buffer_size: usize,
    /// Simulated delay between buffers (ms).
    pub buffer_interval_ms: u64,
}

impl Default for MockConfig {
    fn default() -> Self {
        Self {
            tones: vec![(1000.0, 0.5)], // 1 kHz tone at 0.5 amplitude
            noise_amplitude: 0.01,
            buffer_size: 4096,
            buffer_interval_ms: 50,
        }
    }
}

pub struct MockSdrDevice {
    info: SdrInfo,
    mock_config: MockConfig,
    streaming: Arc<AtomicBool>,
    read_thread: Option<std::thread::JoinHandle<()>>,
    /// Command sender for mid-stream commands (retune, etc.).
    /// Uses std::sync::mpsc because the read thread is a std::thread, not tokio.
    cmd_tx: Option<tokio::sync::mpsc::Sender<SdrCommand>>,
}

impl MockSdrDevice {
    pub fn new(id: &str, mock_config: MockConfig) -> Self {
        Self {
            info: SdrInfo {
                id: SdrId::from(id),
                driver: "mock".into(),
                label: Some(format!("Mock SDR ({id})")),
                serial: Some(id.to_string()),
                capabilities: SdrCapabilities {
                    sample_rates: vec![48_000, 240_000, 1_000_000, 2_400_000],
                    freq_range: (100_000, 1_800_000_000),
                    max_bandwidth: 2_400_000,
                    antennas: vec!["default".into()],
                    has_agc: true,
                },
                kiwi_status: None,
            },
            mock_config,
            streaming: Arc::new(AtomicBool::new(false)),
            read_thread: None,
            cmd_tx: None,
        }
    }
}

impl SdrDevice for MockSdrDevice {
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

        let (tx, rx) = mpsc::channel(32);
        let (cmd_tx, mut cmd_rx) = mpsc::channel::<SdrCommand>(8);
        self.streaming.store(true, Ordering::Relaxed);
        self.cmd_tx = Some(cmd_tx);
        let streaming = self.streaming.clone();
        let mock_config = self.mock_config.clone();
        let center_freq = config.center_frequency;
        let sample_rate = config.sample_rate;

        info!(
            id = %self.info.id,
            center_freq,
            sample_rate,
            "Mock SDR starting stream"
        );

        let handle = std::thread::spawn(move || {
            let mut sample_index: u64 = 0;
            let mut rng_state: u32 = 42;
            let mut current_center_freq = center_freq;

            while streaming.load(Ordering::Relaxed) {
                // Check for commands (non-blocking)
                while let Ok(cmd) = cmd_rx.try_recv() {
                    match cmd {
                        SdrCommand::SetFrequency(new_freq) => {
                            info!(
                                old_freq = current_center_freq,
                                new_freq, "Mock SDR retuning"
                            );
                            current_center_freq = new_freq;
                        }
                    }
                }

                let mut samples = Vec::with_capacity(mock_config.buffer_size);

                for _ in 0..mock_config.buffer_size {
                    let t = sample_index as f64 / sample_rate as f64;

                    // Sum tones
                    let mut re = 0.0f32;
                    let mut im = 0.0f32;
                    for &(freq_offset, amplitude) in &mock_config.tones {
                        let phase = 2.0 * PI as f64 * freq_offset * t;
                        re += amplitude * phase.cos() as f32;
                        im += amplitude * phase.sin() as f32;
                    }

                    // Add noise (simple xorshift PRNG)
                    rng_state ^= rng_state << 13;
                    rng_state ^= rng_state >> 17;
                    rng_state ^= rng_state << 5;
                    let noise_re = (rng_state as f32 / u32::MAX as f32 - 0.5)
                        * 2.0
                        * mock_config.noise_amplitude;
                    rng_state ^= rng_state << 13;
                    rng_state ^= rng_state >> 17;
                    rng_state ^= rng_state << 5;
                    let noise_im = (rng_state as f32 / u32::MAX as f32 - 0.5)
                        * 2.0
                        * mock_config.noise_amplitude;

                    samples.push(Complex::new(re + noise_re, im + noise_im));
                    sample_index += 1;
                }

                let buffer = TimestampedIqBuffer {
                    timestamp: Utc::now(),
                    center_frequency: current_center_freq,
                    sample_rate,
                    samples: Arc::new(samples),
                };

                if tx.blocking_send(buffer).is_err() {
                    break; // Receiver dropped
                }

                std::thread::sleep(std::time::Duration::from_millis(
                    mock_config.buffer_interval_ms,
                ));
            }
        });

        self.read_thread = Some(handle);
        Ok(rx)
    }

    fn stop_streaming(&mut self) -> Result<(), SdrError> {
        self.streaming.store(false, Ordering::Relaxed);
        self.cmd_tx = None;
        if let Some(handle) = self.read_thread.take() {
            handle
                .join()
                .map_err(|_| SdrError::StreamingError("thread panicked".into()))?;
        }
        info!(id = %self.info.id, "Mock SDR stopped");
        Ok(())
    }

    fn is_streaming(&self) -> bool {
        self.streaming.load(Ordering::Relaxed)
    }

    fn command_sender(&self) -> Option<mpsc::Sender<SdrCommand>> {
        self.cmd_tx.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rustfft::FftPlanner;

    #[tokio::test]
    async fn mock_streams_buffers() {
        let config = MockConfig {
            buffer_interval_ms: 10,
            buffer_size: 1024,
            ..Default::default()
        };
        let mut sdr = MockSdrDevice::new("test-mock", config);
        let stream_config = StreamConfig {
            center_frequency: 7_030_000,
            sample_rate: 48_000,
            bandwidth: 48_000,
            gain: crate::types::GainSetting::Auto,
            antenna: None,
        };

        let mut rx = sdr.start_streaming(stream_config).unwrap();
        assert!(sdr.is_streaming());

        // Receive a few buffers
        for _ in 0..3 {
            let buf = rx.recv().await.unwrap();
            assert_eq!(buf.samples.len(), 1024);
            assert_eq!(buf.center_frequency, 7_030_000);
            assert_eq!(buf.sample_rate, 48_000);
        }

        sdr.stop_streaming().unwrap();
        assert!(!sdr.is_streaming());
    }

    #[tokio::test]
    async fn mock_cannot_double_start() {
        let mut sdr = MockSdrDevice::new("test-mock", MockConfig::default());
        let config = StreamConfig {
            center_frequency: 7_030_000,
            sample_rate: 48_000,
            bandwidth: 48_000,
            gain: crate::types::GainSetting::Auto,
            antenna: None,
        };

        let _rx = sdr.start_streaming(config.clone()).unwrap();
        let result = sdr.start_streaming(config);
        assert!(result.is_err());

        sdr.stop_streaming().unwrap();
    }

    #[tokio::test]
    async fn mock_tone_detectable_via_fft() {
        let tone_freq = 1000.0;
        let sample_rate = 48_000u32;
        let fft_size = 4096;

        let config = MockConfig {
            tones: vec![(tone_freq, 1.0)],
            noise_amplitude: 0.001,
            buffer_size: fft_size,
            buffer_interval_ms: 10,
        };
        let mut sdr = MockSdrDevice::new("fft-test", config);

        let stream_config = StreamConfig {
            center_frequency: 7_030_000,
            sample_rate,
            bandwidth: sample_rate,
            gain: crate::types::GainSetting::Auto,
            antenna: None,
        };
        let mut rx = sdr.start_streaming(stream_config).unwrap();

        // Skip first buffer (might have transient), use second
        let _first = rx.recv().await.unwrap();
        let buf = rx.recv().await.unwrap();

        // Run FFT
        let mut planner = FftPlanner::new();
        let fft = planner.plan_fft_forward(fft_size);
        let mut data: Vec<Complex<f32>> = buf.samples.as_ref().clone();
        fft.process(&mut data);

        // Find the peak bin
        let magnitudes: Vec<f32> = data.iter().map(|c| c.norm()).collect();
        let peak_bin = magnitudes[..fft_size / 2]
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.partial_cmp(b.1).unwrap())
            .map(|(i, _)| i)
            .unwrap();

        let peak_freq = peak_bin as f64 * sample_rate as f64 / fft_size as f64;

        // Allow 1 bin of tolerance
        let bin_resolution = sample_rate as f64 / fft_size as f64;
        let error = (peak_freq - tone_freq).abs();
        assert!(
            error <= bin_resolution,
            "Peak at {peak_freq} Hz, expected {tone_freq} Hz (error {error} Hz, bin res {bin_resolution} Hz)"
        );

        sdr.stop_streaming().unwrap();
    }

    #[tokio::test]
    async fn mock_retune_updates_center_frequency() {
        let config = MockConfig {
            buffer_interval_ms: 10,
            buffer_size: 1024,
            ..Default::default()
        };
        let mut sdr = MockSdrDevice::new("retune-test", config);
        let stream_config = StreamConfig {
            center_frequency: 7_030_000,
            sample_rate: 48_000,
            bandwidth: 48_000,
            gain: crate::types::GainSetting::Auto,
            antenna: None,
        };

        let mut rx = sdr.start_streaming(stream_config).unwrap();

        // Verify initial frequency
        let buf = rx.recv().await.unwrap();
        assert_eq!(buf.center_frequency, 7_030_000);

        // Retune via command channel
        let cmd_tx = sdr
            .command_sender()
            .expect("mock should have command sender");
        cmd_tx
            .send(SdrCommand::SetFrequency(14_060_000))
            .await
            .unwrap();

        // Give the thread time to process the command
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;

        // Drain any buffered messages at old frequency
        while let Ok(buf) = rx.try_recv() {
            if buf.center_frequency == 14_060_000 {
                // Found a buffer at the new frequency — success
                sdr.stop_streaming().unwrap();
                return;
            }
        }

        // Wait for a new buffer at the new frequency
        let buf = rx.recv().await.unwrap();
        assert_eq!(
            buf.center_frequency, 14_060_000,
            "Buffer should reflect new center frequency after retune"
        );

        sdr.stop_streaming().unwrap();
    }
}
