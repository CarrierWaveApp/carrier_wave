pub mod request;
pub mod session;

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{info, warn};
use uuid::Uuid;

use crate::error::CaptureError;
use crate::sdr::discovery::SdrRegistry;
use crate::sdr::{SdrDevice, StreamConfig};
use crate::types::{FrequencyRange, GainSetting, SdrId};
use request::CaptureRequest;
use session::{CaptureSession, ConsumerHandle};

/// Manages capture sessions across multiple SDRs.
///
/// Routes capture requests to existing sessions (if compatible) or creates
/// new ones. Handles session lifecycle including grace periods.
pub struct CaptureMultiplexer {
    sessions: Arc<Mutex<HashMap<Uuid, SessionState>>>,
    registry: Arc<SdrRegistry>,
    /// Grace period in seconds before stopping a session with 0 consumers.
    grace_period_secs: u64,
}

struct SessionState {
    session: Arc<CaptureSession>,
    sdr_device: Option<Box<dyn SdrDevice>>,
    broadcast_handle: Option<tokio::task::JoinHandle<()>>,
}

impl CaptureMultiplexer {
    pub fn new(registry: Arc<SdrRegistry>, grace_period_secs: u64) -> Self {
        Self {
            sessions: Arc::new(Mutex::new(HashMap::new())),
            registry,
            grace_period_secs,
        }
    }

    /// Request a capture. Returns a consumer handle for the IQ data.
    ///
    /// If an existing session covers the requested range, subscribes there.
    /// Otherwise creates a new session.
    pub async fn request_capture(
        &self,
        request: CaptureRequest,
    ) -> Result<ConsumerHandle, CaptureError> {
        let req_range = request.frequency_range();

        // 1. Check existing sessions for a compatible one
        {
            let sessions = self.sessions.lock().await;
            for state in sessions.values() {
                let session = &state.session;
                if session.is_running() && session.covers(&req_range) {
                    // Check SDR matches if specified
                    if let Some(ref req_sdr) = request.sdr_id {
                        if &session.sdr_id != req_sdr {
                            continue;
                        }
                    }
                    info!(
                        session = %session.id,
                        "Reusing existing capture session"
                    );
                    return Ok(session.subscribe());
                }
            }
        }

        // 2. No existing session covers this — create a new one
        self.create_session(request).await
    }

    async fn create_session(
        &self,
        request: CaptureRequest,
    ) -> Result<ConsumerHandle, CaptureError> {
        let req_range = request.frequency_range();

        // Find an SDR to use
        let sdr_id = if let Some(id) = request.sdr_id.clone() {
            id
        } else {
            // Auto-select: find any available SDR
            let devices = self.registry.list().await;
            devices
                .into_iter()
                .next()
                .map(|d| d.id)
                .ok_or_else(|| CaptureError::NoSdrAvailable("no SDRs discovered".into()))?
        };

        // Create the device
        let mut device = self.registry.create_device(&sdr_id).await.ok_or_else(|| {
            CaptureError::NoSdrAvailable(format!("cannot create device for {sdr_id}"))
        })?;

        let sample_rate = request::pick_sample_rate(request.bandwidth);

        // Configure and start the SDR
        let stream_config = StreamConfig {
            center_frequency: req_range.center(),
            sample_rate,
            bandwidth: request.bandwidth,
            gain: GainSetting::Auto,
            antenna: None,
        };

        let sdr_rx = device
            .start_streaming(stream_config)
            .map_err(|e| CaptureError::SessionError(e.to_string()))?;

        // Get command sender from the device (for retune support)
        let cmd_tx = device.command_sender();

        // Create session and start broadcast
        let session = Arc::new(CaptureSession::new(
            sdr_id.clone(),
            req_range,
            sample_rate,
            cmd_tx,
        ));
        let broadcast_handle = session.start_broadcast(sdr_rx);
        let consumer = session.subscribe();

        info!(
            session = %session.id,
            sdr = %sdr_id,
            range = %req_range,
            sample_rate,
            "Created new capture session"
        );

        let mut sessions = self.sessions.lock().await;
        sessions.insert(
            session.id,
            SessionState {
                session,
                sdr_device: Some(device),
                broadcast_handle: Some(broadcast_handle),
            },
        );

        Ok(consumer)
    }

    /// Retune a capture session to a new center frequency.
    pub async fn retune_session(
        &self,
        session_id: Uuid,
        new_freq: u64,
    ) -> Result<(), CaptureError> {
        let sessions = self.sessions.lock().await;
        if let Some(state) = sessions.get(&session_id) {
            state
                .session
                .retune(new_freq)
                .await
                .map_err(CaptureError::SessionError)?;
            info!(session = %session_id, new_freq, "Capture session retuned");
            Ok(())
        } else {
            Err(CaptureError::SessionError(format!(
                "session {session_id} not found"
            )))
        }
    }

    /// Stop a specific capture session.
    pub async fn stop_session(&self, session_id: Uuid) -> Result<(), CaptureError> {
        let mut sessions = self.sessions.lock().await;
        if let Some(mut state) = sessions.remove(&session_id) {
            state.session.stop();
            if let Some(mut device) = state.sdr_device.take() {
                let _ = device.stop_streaming();
            }
            if let Some(handle) = state.broadcast_handle.take() {
                handle.abort();
            }
            info!(session = %session_id, "Stopped capture session");
            Ok(())
        } else {
            Err(CaptureError::SessionError(format!(
                "session {session_id} not found"
            )))
        }
    }

    /// List all active capture sessions.
    pub async fn list_sessions(&self) -> Vec<CaptureSessionInfo> {
        let sessions = self.sessions.lock().await;
        sessions
            .values()
            .map(|state| CaptureSessionInfo {
                id: state.session.id,
                sdr_id: state.session.sdr_id.clone(),
                frequency_range: state.session.frequency_range,
                sample_rate: state.session.sample_rate,
                consumer_count: state.session.consumer_count(),
                running: state.session.is_running(),
            })
            .collect()
    }

    /// Clean up sessions with no consumers (after grace period).
    pub async fn cleanup_idle_sessions(&self) {
        let mut sessions = self.sessions.lock().await;
        let to_remove: Vec<Uuid> = sessions
            .iter()
            .filter(|(_, state)| state.session.consumer_count() == 0)
            .map(|(id, _)| *id)
            .collect();

        for id in to_remove {
            if let Some(mut state) = sessions.remove(&id) {
                state.session.stop();
                if let Some(mut device) = state.sdr_device.take() {
                    let _ = device.stop_streaming();
                }
                if let Some(handle) = state.broadcast_handle.take() {
                    handle.abort();
                }
                warn!(session = %id, "Cleaned up idle capture session");
            }
        }
    }

    /// Start a background task that periodically cleans up idle sessions.
    pub fn start_cleanup_loop(self: Arc<Self>) -> tokio::task::JoinHandle<()> {
        let grace = self.grace_period_secs;
        tokio::spawn(async move {
            loop {
                tokio::time::sleep(std::time::Duration::from_secs(grace)).await;
                self.cleanup_idle_sessions().await;
            }
        })
    }
}

/// Summary info about a capture session (for API responses).
#[derive(Debug, Clone, serde::Serialize)]
pub struct CaptureSessionInfo {
    pub id: Uuid,
    pub sdr_id: SdrId,
    pub frequency_range: FrequencyRange,
    pub sample_rate: u32,
    pub consumer_count: i64,
    pub running: bool,
}

// Re-export for convenience
pub use request::pick_sample_rate;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::DiscoverySection;
    use crate::sdr::mock::MockConfig;
    use crate::types::{CapturePriority, DemodMode};

    async fn test_mux() -> (Arc<CaptureMultiplexer>, Arc<SdrRegistry>) {
        let config = DiscoverySection::default();
        let registry = Arc::new(SdrRegistry::new(config));
        registry
            .add_mock(
                "mock-1",
                MockConfig {
                    buffer_interval_ms: 10,
                    buffer_size: 1024,
                    ..Default::default()
                },
            )
            .await;
        let mux = Arc::new(CaptureMultiplexer::new(registry.clone(), 5));
        (mux, registry)
    }

    fn make_request(freq: u64, bw: u32) -> CaptureRequest {
        CaptureRequest {
            sdr_id: Some(SdrId::from("mock-1")),
            frequency: freq,
            bandwidth: bw,
            priority: CapturePriority::Recording,
            mode: DemodMode::Cw,
        }
    }

    #[tokio::test]
    async fn single_request_creates_session() {
        let (mux, _) = test_mux().await;
        let mut handle = mux
            .request_capture(make_request(7_030_000, 2_400))
            .await
            .unwrap();

        let sessions = mux.list_sessions().await;
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].consumer_count, 1);

        // Should receive data
        let buf = handle.recv().await.unwrap();
        assert!(!buf.samples.is_empty());

        drop(handle);
    }

    #[tokio::test]
    async fn overlapping_request_reuses_session() {
        let (mux, _) = test_mux().await;

        // First request: wide enough to cover both
        let req1 = CaptureRequest {
            sdr_id: Some(SdrId::from("mock-1")),
            frequency: 7_030_000,
            bandwidth: 20_000, // 20kHz — covers 7020000-7040000
            priority: CapturePriority::Recording,
            mode: DemodMode::Cw,
        };
        let _h1 = mux.request_capture(req1).await.unwrap();

        // Second request within the first's range
        let _h2 = mux
            .request_capture(make_request(7_035_000, 2_400))
            .await
            .unwrap();

        let sessions = mux.list_sessions().await;
        assert_eq!(sessions.len(), 1, "Should reuse the same session");
        assert_eq!(sessions[0].consumer_count, 2);

        drop(_h1);
        drop(_h2);
    }

    #[tokio::test]
    async fn cleanup_removes_idle_sessions() {
        let (mux, _) = test_mux().await;
        let handle = mux
            .request_capture(make_request(7_030_000, 2_400))
            .await
            .unwrap();

        assert_eq!(mux.list_sessions().await.len(), 1);

        // Drop the consumer
        drop(handle);

        // Clean up
        mux.cleanup_idle_sessions().await;
        assert_eq!(mux.list_sessions().await.len(), 0);
    }

    #[tokio::test]
    async fn stop_session_works() {
        let (mux, _) = test_mux().await;
        let _handle = mux
            .request_capture(make_request(7_030_000, 2_400))
            .await
            .unwrap();

        let sessions = mux.list_sessions().await;
        let session_id = sessions[0].id;

        mux.stop_session(session_id).await.unwrap();
        assert_eq!(mux.list_sessions().await.len(), 0);
    }
}
