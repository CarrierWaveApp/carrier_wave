use chrono::{DateTime, TimeDelta, Utc};
use std::sync::{Arc, RwLock};
use tracing::{info, warn};

use crate::error::TimeError;

/// Provides NTP-corrected timestamps.
///
/// Periodically syncs with an NTP server and applies the measured offset
/// to local system time.
#[derive(Clone)]
pub struct TimestampProvider {
    state: Arc<RwLock<TimeState>>,
    ntp_server: String,
}

struct TimeState {
    /// Offset to apply to local time (NTP time - local time).
    offset: TimeDelta,
    /// When we last synced.
    last_sync: Option<DateTime<Utc>>,
}

impl TimestampProvider {
    pub fn new(ntp_server: &str) -> Self {
        Self {
            state: Arc::new(RwLock::new(TimeState {
                offset: TimeDelta::zero(),
                last_sync: None,
            })),
            ntp_server: ntp_server.to_string(),
        }
    }

    /// Get the current corrected UTC time.
    pub fn now(&self) -> DateTime<Utc> {
        let offset = self.state.read().unwrap().offset;
        Utc::now() + offset
    }

    /// Attempt NTP sync. Updates the internal offset on success.
    pub fn sync(&self) -> Result<TimeDelta, TimeError> {
        let result = rsntp::SntpClient::new()
            .synchronize(&self.ntp_server)
            .map_err(|e| TimeError::NtpSyncFailed(e.to_string()))?;

        let clock_offset = result.clock_offset();
        let abs_secs = clock_offset
            .abs_as_std_duration()
            .map_err(|e| TimeError::NtpSyncFailed(e.to_string()))?
            .as_secs_f64();
        let signed_secs = abs_secs * clock_offset.signum() as f64;
        let offset_us = (signed_secs * 1_000_000.0) as i64;
        let offset = TimeDelta::microseconds(offset_us);

        let mut state = self.state.write().unwrap();
        state.offset = offset;
        state.last_sync = Some(Utc::now());

        info!(offset_us = offset_us, "NTP sync complete");

        Ok(offset)
    }

    /// Start a background sync loop.
    pub fn start_sync_loop(self, interval_secs: u64) -> tokio::task::JoinHandle<()> {
        tokio::spawn(async move {
            loop {
                match self.sync() {
                    Ok(offset) => {
                        info!(offset_ms = offset.num_milliseconds(), "NTP synced");
                    }
                    Err(e) => {
                        warn!(error = %e, "NTP sync failed, will retry");
                    }
                }
                tokio::time::sleep(std::time::Duration::from_secs(interval_secs)).await;
            }
        })
    }

    /// Get the current offset (for diagnostics).
    pub fn offset(&self) -> TimeDelta {
        self.state.read().unwrap().offset
    }

    /// Get the last sync time (for diagnostics).
    pub fn last_sync(&self) -> Option<DateTime<Utc>> {
        self.state.read().unwrap().last_sync
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn provider_default_offset_is_zero() {
        let provider = TimestampProvider::new("pool.ntp.org");
        let offset = provider.offset();
        assert_eq!(offset, TimeDelta::zero());
        assert!(provider.last_sync().is_none());
    }

    #[test]
    fn provider_now_close_to_system_time() {
        let provider = TimestampProvider::new("pool.ntp.org");
        let system = Utc::now();
        let corrected = provider.now();
        let diff = (corrected - system).num_milliseconds().unsigned_abs();
        // With zero offset, should be within 10ms of system time
        assert!(diff < 10, "diff was {diff}ms");
    }
}
