use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use chrono::Utc;
use num_complex::Complex;
use tokio::sync::mpsc;
use tracing::{error, info, warn};

use crate::error::SdrError;
use crate::sdr::{SdrCapabilities, SdrCommand, SdrDevice, SdrInfo, StreamConfig};
use crate::types::{SdrId, TimestampedIqBuffer};

/// SDR backend for KiwiSDR network receivers via WebSocket.
///
/// KiwiSDR protocol reference: the KiwiSDR server speaks a custom binary
/// WebSocket protocol. This implementation connects, sends SET commands
/// to configure frequency/mode, and receives IQ data frames.
pub struct KiwiSdrDevice {
    info: SdrInfo,
    url: String,
    streaming: Arc<AtomicBool>,
    read_task: Option<tokio::task::JoinHandle<()>>,
    /// Command sender for mid-stream commands (retune, etc.).
    cmd_tx: Option<mpsc::Sender<SdrCommand>>,
}

impl KiwiSdrDevice {
    pub fn new(url: &str, label: Option<String>) -> Self {
        let id = url
            .trim_start_matches("http://")
            .trim_start_matches("https://")
            .split(':')
            .next()
            .unwrap_or("kiwi")
            .to_string();

        Self {
            info: SdrInfo {
                id: SdrId::from(id),
                driver: "kiwisdr".into(),
                label,
                serial: None,
                capabilities: SdrCapabilities {
                    sample_rates: vec![12_000],
                    freq_range: (10_000, 30_000_000),
                    max_bandwidth: 12_000,
                    antennas: vec!["default".into()],
                    has_agc: true,
                },
                kiwi_status: None,
            },
            url: url.to_string(),
            streaming: Arc::new(AtomicBool::new(false)),
            read_task: None,
            cmd_tx: None,
        }
    }

    /// Build the WebSocket URL for the KiwiSDR.
    fn ws_url(&self) -> String {
        let base = self
            .url
            .trim_end_matches('/')
            .replace("http://", "ws://")
            .replace("https://", "wss://");
        format!("{base}/kiwi/{}/SND", chrono::Utc::now().timestamp_millis())
    }
}

impl SdrDevice for KiwiSdrDevice {
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
        let ws_url = self.ws_url();
        let center_freq = config.center_frequency;
        let sample_rate = 12_000u32; // KiwiSDR fixed rate
        let id = self.info.id.clone();

        info!(
            id = %id,
            url = %self.url,
            center_freq,
            "KiwiSDR starting stream"
        );

        let handle = tokio::spawn(async move {
            use futures_util::{SinkExt, StreamExt};
            use tokio_tungstenite::tungstenite::Message;

            let connect_result = tokio_tungstenite::connect_async(&ws_url).await;
            let (mut ws, _response) = match connect_result {
                Ok(pair) => pair,
                Err(e) => {
                    error!(error = %e, "KiwiSDR WebSocket connection failed");
                    return;
                }
            };

            // Send initial KiwiSDR setup commands
            let freq_khz = center_freq as f64 / 1000.0;
            let setup_cmds = [
                "SET auth t=kiwi p=#".to_string(),
                format!("SET mod=iq low_cut=-5000 high_cut=5000 freq={freq_khz:.3}"),
                "SET agc=1 hang=0 thresh=-100 slope=6 decay=1000 manGain=50".to_string(),
                "SET AR OK in=12000 out=12000".to_string(),
                "SET gen=0 mix=-1".to_string(),
            ];
            for cmd in &setup_cmds {
                if let Err(e) = ws.send(Message::Text(cmd.clone())).await {
                    error!(error = %e, "KiwiSDR send failed");
                    return;
                }
            }

            let mut current_center_freq = center_freq;

            while streaming.load(Ordering::Relaxed) {
                tokio::select! {
                    cmd = cmd_rx.recv() => {
                        match cmd {
                            Some(SdrCommand::SetFrequency(new_freq)) => {
                                let new_freq_khz = new_freq as f64 / 1000.0;
                                let retune_cmd = format!(
                                    "SET mod=iq low_cut=-5000 high_cut=5000 freq={new_freq_khz:.3}"
                                );
                                info!(
                                    id = %id,
                                    old_freq = current_center_freq,
                                    new_freq,
                                    "KiwiSDR retuning"
                                );
                                if let Err(e) = ws.send(Message::Text(retune_cmd)).await {
                                    error!(error = %e, "KiwiSDR retune send failed");
                                    break;
                                }
                                current_center_freq = new_freq;
                            }
                            None => {
                                // Command channel closed — stop
                                break;
                            }
                        }
                    }
                    msg = ws.next() => {
                        match msg {
                            Some(Ok(Message::Binary(data))) => {
                                // KiwiSDR binary frames: first 3 bytes are header "SND"
                                if data.len() < 7 || &data[0..3] != b"SND" {
                                    continue;
                                }

                                // Bytes 3..7: flags/sequence (skip for now)
                                // Rest: interleaved I/Q 16-bit signed little-endian samples
                                let iq_data = &data[7..];
                                if iq_data.len() < 4 {
                                    continue;
                                }

                                let num_samples = iq_data.len() / 4; // 2 bytes I + 2 bytes Q
                                let mut samples = Vec::with_capacity(num_samples);
                                for chunk in iq_data.chunks_exact(4) {
                                    let i = i16::from_le_bytes([chunk[0], chunk[1]]) as f32
                                        / 32768.0;
                                    let q = i16::from_le_bytes([chunk[2], chunk[3]]) as f32
                                        / 32768.0;
                                    samples.push(Complex::new(i, q));
                                }

                                if samples.is_empty() {
                                    continue;
                                }

                                let buffer = TimestampedIqBuffer {
                                    timestamp: Utc::now(),
                                    center_frequency: current_center_freq,
                                    sample_rate,
                                    samples: Arc::new(samples),
                                };

                                if tx.send(buffer).await.is_err() {
                                    break;
                                }
                            }
                            Some(Ok(Message::Text(_))) => {
                                // KiwiSDR sends text status messages — ignore
                            }
                            Some(Ok(Message::Close(_))) => {
                                warn!(id = %id, "KiwiSDR connection closed by server");
                                break;
                            }
                            Some(Err(e)) => {
                                error!(error = %e, "KiwiSDR WebSocket error");
                                break;
                            }
                            None => break,
                            _ => {}
                        }
                    }
                }
            }

            let _ = ws.close(None).await;
        });

        self.read_task = Some(handle);
        Ok(rx)
    }

    fn stop_streaming(&mut self) -> Result<(), SdrError> {
        self.streaming.store(false, Ordering::Relaxed);
        self.cmd_tx = None;
        if let Some(handle) = self.read_task.take() {
            handle.abort();
        }
        info!(id = %self.info.id, "KiwiSDR stopped");
        Ok(())
    }

    fn is_streaming(&self) -> bool {
        self.streaming.load(Ordering::Relaxed)
    }

    fn command_sender(&self) -> Option<mpsc::Sender<SdrCommand>> {
        self.cmd_tx.clone()
    }
}
