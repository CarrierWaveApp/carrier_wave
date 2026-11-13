use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::Arc;

use tokio::sync::broadcast;
use tracing::{info, warn};
use uuid::Uuid;

use crate::sdr::SdrCommand;
use crate::types::{FrequencyRange, SdrId, TimestampedIqBuffer};

/// A handle returned to consumers to receive IQ data from a capture session.
pub struct ConsumerHandle {
    pub session_id: Uuid,
    pub rx: broadcast::Receiver<Arc<TimestampedIqBuffer>>,
    consumer_count: Arc<AtomicI64>,
}

impl ConsumerHandle {
    /// Receive the next IQ buffer.
    pub async fn recv(&mut self) -> Option<Arc<TimestampedIqBuffer>> {
        loop {
            match self.rx.recv().await {
                Ok(buf) => return Some(buf),
                Err(broadcast::error::RecvError::Lagged(n)) => {
                    warn!(
                        session = %self.session_id,
                        lagged = n,
                        "Consumer lagged, skipping buffers"
                    );
                    // Continue to next message
                }
                Err(broadcast::error::RecvError::Closed) => return None,
            }
        }
    }
}

impl Drop for ConsumerHandle {
    fn drop(&mut self) {
        self.consumer_count.fetch_sub(1, Ordering::Relaxed);
    }
}

/// An active capture session: one SDR tuning shared by N consumers.
pub struct CaptureSession {
    pub id: Uuid,
    pub sdr_id: SdrId,
    pub frequency_range: FrequencyRange,
    pub sample_rate: u32,
    tx: broadcast::Sender<Arc<TimestampedIqBuffer>>,
    consumer_count: Arc<AtomicI64>,
    running: Arc<AtomicBool>,
    /// Command sender to the underlying SDR device (for retune, etc.).
    cmd_tx: Option<tokio::sync::mpsc::Sender<SdrCommand>>,
}

impl CaptureSession {
    /// Create a new capture session.
    pub fn new(
        sdr_id: SdrId,
        frequency_range: FrequencyRange,
        sample_rate: u32,
        cmd_tx: Option<tokio::sync::mpsc::Sender<SdrCommand>>,
    ) -> Self {
        let (tx, _) = broadcast::channel(64);
        Self {
            id: Uuid::new_v4(),
            sdr_id,
            frequency_range,
            sample_rate,
            tx,
            consumer_count: Arc::new(AtomicI64::new(0)),
            running: Arc::new(AtomicBool::new(false)),
            cmd_tx,
        }
    }

    /// Subscribe a new consumer to this session.
    pub fn subscribe(&self) -> ConsumerHandle {
        self.consumer_count.fetch_add(1, Ordering::Relaxed);
        ConsumerHandle {
            session_id: self.id,
            rx: self.tx.subscribe(),
            consumer_count: self.consumer_count.clone(),
        }
    }

    /// Number of active consumers.
    pub fn consumer_count(&self) -> i64 {
        self.consumer_count.load(Ordering::Relaxed)
    }

    /// Whether this session is currently running.
    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Relaxed)
    }

    /// Check if this session's frequency range fully covers the given request.
    pub fn covers(&self, range: &FrequencyRange) -> bool {
        self.frequency_range.contains(range)
    }

    /// Send a retune command to the underlying SDR device.
    pub async fn retune(&self, new_freq: u64) -> Result<(), String> {
        if let Some(ref cmd_tx) = self.cmd_tx {
            cmd_tx
                .send(SdrCommand::SetFrequency(new_freq))
                .await
                .map_err(|e| format!("failed to send retune command: {e}"))?;
            info!(session = %self.id, new_freq, "Session retune command sent");
            Ok(())
        } else {
            Err("session does not support retune (no command channel)".into())
        }
    }

    /// Start the broadcast loop: receives IQ from the SDR mpsc channel and
    /// fans out to all broadcast subscribers.
    pub fn start_broadcast(
        &self,
        mut sdr_rx: tokio::sync::mpsc::Receiver<TimestampedIqBuffer>,
    ) -> tokio::task::JoinHandle<()> {
        let tx = self.tx.clone();
        let running = self.running.clone();
        let session_id = self.id;

        running.store(true, Ordering::Relaxed);

        tokio::spawn(async move {
            info!(session = %session_id, "Capture session broadcast started");

            while let Some(buf) = sdr_rx.recv().await {
                let arc_buf = Arc::new(buf);
                // broadcast::send returns Err if no receivers — that's fine
                let _ = tx.send(arc_buf);
            }

            running.store(false, Ordering::Relaxed);
            info!(session = %session_id, "Capture session broadcast ended");
        })
    }

    /// Signal the session to stop.
    pub fn stop(&self) {
        self.running.store(false, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::SdrId;
    use chrono::Utc;
    use num_complex::Complex;

    fn make_buffer(center: u64) -> TimestampedIqBuffer {
        TimestampedIqBuffer {
            timestamp: Utc::now(),
            center_frequency: center,
            sample_rate: 48_000,
            samples: Arc::new(vec![Complex::new(1.0, 0.0); 1024]),
        }
    }

    #[tokio::test]
    async fn session_subscribe_and_receive() {
        let range = FrequencyRange::new(7_028_800, 7_031_200);
        let session = CaptureSession::new(SdrId::from("test"), range, 48_000, None);

        let (sdr_tx, sdr_rx) = tokio::sync::mpsc::channel(16);
        let broadcast_handle = session.start_broadcast(sdr_rx);

        let mut consumer = session.subscribe();
        assert_eq!(session.consumer_count(), 1);

        // Send a buffer
        sdr_tx.send(make_buffer(7_030_000)).await.unwrap();

        let received = consumer.recv().await.unwrap();
        assert_eq!(received.center_frequency, 7_030_000);
        assert_eq!(received.samples.len(), 1024);

        // Drop sender to end broadcast
        drop(sdr_tx);
        broadcast_handle.await.unwrap();
    }

    #[tokio::test]
    async fn session_multiple_consumers() {
        let range = FrequencyRange::new(7_028_800, 7_031_200);
        let session = CaptureSession::new(SdrId::from("test"), range, 48_000, None);

        let (sdr_tx, sdr_rx) = tokio::sync::mpsc::channel(16);
        let broadcast_handle = session.start_broadcast(sdr_rx);

        let mut c1 = session.subscribe();
        let mut c2 = session.subscribe();
        assert_eq!(session.consumer_count(), 2);

        sdr_tx.send(make_buffer(7_030_000)).await.unwrap();

        let r1 = c1.recv().await.unwrap();
        let r2 = c2.recv().await.unwrap();
        assert_eq!(r1.center_frequency, r2.center_frequency);

        // Drop one consumer
        drop(c2);
        assert_eq!(session.consumer_count(), 1);

        drop(sdr_tx);
        broadcast_handle.await.unwrap();
    }

    #[tokio::test]
    async fn session_consumer_count_tracks_drops() {
        let range = FrequencyRange::new(7_000_000, 7_100_000);
        let session = CaptureSession::new(SdrId::from("test"), range, 240_000, None);

        let c1 = session.subscribe();
        let c2 = session.subscribe();
        let c3 = session.subscribe();
        assert_eq!(session.consumer_count(), 3);

        drop(c1);
        assert_eq!(session.consumer_count(), 2);

        drop(c2);
        drop(c3);
        assert_eq!(session.consumer_count(), 0);
    }

    #[tokio::test]
    async fn session_covers_check() {
        let range = FrequencyRange::new(7_000_000, 7_100_000);
        let session = CaptureSession::new(SdrId::from("test"), range, 240_000, None);

        let narrow = FrequencyRange::new(7_028_800, 7_031_200);
        assert!(session.covers(&narrow));

        let outside = FrequencyRange::new(14_000_000, 14_002_400);
        assert!(!session.covers(&outside));
    }

    #[tokio::test]
    async fn session_lagged_consumer_recovers() {
        let range = FrequencyRange::new(7_000_000, 7_100_000);
        let session = CaptureSession::new(SdrId::from("test"), range, 48_000, None);

        let (sdr_tx, sdr_rx) = tokio::sync::mpsc::channel(256);
        let broadcast_handle = session.start_broadcast(sdr_rx);

        let mut consumer = session.subscribe();

        // Flood the broadcast channel (capacity 64) without reading
        for i in 0..100 {
            sdr_tx.send(make_buffer(7_030_000 + i)).await.unwrap();
        }
        // Give broadcast loop time to process
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;

        // Consumer should still be able to receive (skipping lagged messages)
        let received = consumer.recv().await.unwrap();
        assert!(received.center_frequency >= 7_030_000);

        drop(sdr_tx);
        broadcast_handle.await.unwrap();
    }
}
