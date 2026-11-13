//! Satellite doppler schedule: wire step format + executor cursor.
//!
//! Single source of truth shared by the CW Sat Bridge firmware (unpack +
//! execute) and the app-side schedule builder in `cw-domain` (build + pack),
//! so the byte layout can never drift between the two ends of the BLE link.
//!
//! Wire format — 6 bytes per step, little-endian:
//!   dt_ms:          u16  offset from the previous step (first step: from AOS)
//!   down_delta_dhz: i16  downlink change from the previous step, 10 Hz units
//!   up_delta_dhz:   i16  uplink change from the previous step, 10 Hz units
//!
//! The first step's deltas are relative to the absolute start frequencies
//! carried in `SatScheduleBegin`. All frequencies are multiples of 10 Hz —
//! the UV-K1's internal resolution. Downlink-only schedules carry
//! `uplink_hz == 0` throughout and a zero up-delta in every packed step.

pub const STEP_BYTES: usize = 6;
/// Hard cap on schedule size (12 KiB packed). A linear pass at 100 Hz
/// granularity needs a few hundred steps; this is generous headroom.
pub const MAX_STEPS: usize = 2048;
/// Packed steps per SatScheduleChunk — fits one 240-byte BLE notification
/// with protobuf overhead to spare.
pub const STEPS_PER_CHUNK: usize = 30;
/// The builder inserts keepalive steps so no dt exceeds this (fits u16 and
/// keeps the executor's status pushes flowing during slow-doppler phases).
pub const MAX_STEP_GAP_MS: u64 = 60_000;

/// One absolute schedule entry: at `t_ms` after AOS, the radio should be on
/// these frequencies.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Step {
    pub t_ms: u64,
    pub downlink_hz: u64,
    /// 0 for downlink-only (linear RX) schedules.
    pub uplink_hz: u64,
}

/// Absolute frequencies the first packed step is relative to (from
/// `SatScheduleBegin.downlink_start_hz` / `uplink_start_hz`).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct StartFreqs {
    pub downlink_hz: u64,
    pub uplink_hz: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PackError {
    TooManySteps,
    /// dt between consecutive steps exceeds MAX_STEP_GAP_MS.
    GapTooLarge { index: usize },
    /// Steps must be in non-decreasing time order.
    NotMonotonic { index: usize },
    /// A frequency delta exceeds ±327.67 kHz (i16 range in 10 Hz units).
    DeltaOverflow { index: usize },
    /// A frequency is not a multiple of 10 Hz.
    NotTenHz { index: usize },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UnpackError {
    /// Byte length is not a multiple of STEP_BYTES.
    BadLength,
    TooManySteps,
}

/// Pack absolute steps into the delta wire format.
pub fn pack_steps(start: StartFreqs, steps: &[Step]) -> Result<Vec<u8>, PackError> {
    if steps.len() > MAX_STEPS {
        return Err(PackError::TooManySteps);
    }
    let mut out = Vec::with_capacity(steps.len() * STEP_BYTES);
    let mut prev_t: u64 = 0;
    let mut prev_down = start.downlink_hz;
    let mut prev_up = start.uplink_hz;
    for (index, step) in steps.iter().enumerate() {
        if step.downlink_hz % 10 != 0 || step.uplink_hz % 10 != 0 {
            return Err(PackError::NotTenHz { index });
        }
        if step.t_ms < prev_t {
            return Err(PackError::NotMonotonic { index });
        }
        let dt = step.t_ms - prev_t;
        if dt > MAX_STEP_GAP_MS {
            return Err(PackError::GapTooLarge { index });
        }
        let down_delta = delta_dhz(prev_down, step.downlink_hz)
            .ok_or(PackError::DeltaOverflow { index })?;
        let up_delta =
            delta_dhz(prev_up, step.uplink_hz).ok_or(PackError::DeltaOverflow { index })?;
        out.extend_from_slice(&(dt as u16).to_le_bytes());
        out.extend_from_slice(&down_delta.to_le_bytes());
        out.extend_from_slice(&up_delta.to_le_bytes());
        prev_t = step.t_ms;
        prev_down = step.downlink_hz;
        prev_up = step.uplink_hz;
    }
    Ok(out)
}

/// Unpack the delta wire format back into absolute steps.
pub fn unpack_steps(start: StartFreqs, bytes: &[u8]) -> Result<Vec<Step>, UnpackError> {
    if bytes.len() % STEP_BYTES != 0 {
        return Err(UnpackError::BadLength);
    }
    let count = bytes.len() / STEP_BYTES;
    if count > MAX_STEPS {
        return Err(UnpackError::TooManySteps);
    }
    let mut steps = Vec::with_capacity(count);
    let mut t: u64 = 0;
    let mut down = start.downlink_hz as i64;
    let mut up = start.uplink_hz as i64;
    for chunk in bytes.chunks_exact(STEP_BYTES) {
        let dt = u16::from_le_bytes([chunk[0], chunk[1]]) as u64;
        let down_delta = i16::from_le_bytes([chunk[2], chunk[3]]) as i64;
        let up_delta = i16::from_le_bytes([chunk[4], chunk[5]]) as i64;
        t += dt;
        down += down_delta * 10;
        up += up_delta * 10;
        steps.push(Step {
            t_ms: t,
            downlink_hz: down.max(0) as u64,
            uplink_hz: up.max(0) as u64,
        });
    }
    Ok(steps)
}

fn delta_dhz(prev_hz: u64, curr_hz: u64) -> Option<i16> {
    let delta = (curr_hz as i64 - prev_hz as i64) / 10;
    i16::try_from(delta).ok()
}

/// Walks the step table against an elapsed-ms clock. Missed steps coalesce:
/// `due` skips past every step whose time has arrived and returns only the
/// latest one, so a stalled executor (e.g. TX guard) lands on current values
/// rather than replaying stale ones.
#[derive(Clone, Copy, Debug, Default)]
pub struct Cursor {
    next: usize,
}

impl Cursor {
    pub fn new() -> Self {
        Self::default()
    }

    /// Index of the next unexecuted step.
    pub fn next_index(&self) -> usize {
        self.next
    }

    /// Position the cursor for a mid-pass start: every step at or before
    /// `elapsed_ms` is considered already due (the caller applies the last
    /// one via `due`).
    pub fn seek(&mut self, _steps: &[Step], _elapsed_ms: u64) {
        // `due` already coalesces from the current position; seeking is just
        // starting from 0 and letting the first `due` call swallow the past.
        self.next = 0;
    }

    /// The latest step due at `elapsed_ms`, advancing past all earlier ones.
    /// Returns `None` when no new step is due yet.
    pub fn due<'a>(&mut self, steps: &'a [Step], elapsed_ms: u64) -> Option<&'a Step> {
        let mut latest = None;
        while let Some(step) = steps.get(self.next) {
            if step.t_ms > elapsed_ms {
                break;
            }
            latest = Some(step);
            self.next += 1;
        }
        latest
    }

    /// Milliseconds until the next step is due, or `None` at end of table.
    pub fn next_due_in(&self, steps: &[Step], elapsed_ms: u64) -> Option<u64> {
        steps
            .get(self.next)
            .map(|step| step.t_ms.saturating_sub(elapsed_ms))
    }

    pub fn finished(&self, steps: &[Step]) -> bool {
        self.next >= steps.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn start() -> StartFreqs {
        StartFreqs { downlink_hz: 436_795_000, uplink_hz: 145_850_000 }
    }

    #[test]
    fn round_trip() {
        let steps = vec![
            Step { t_ms: 0, downlink_hz: 436_804_500, uplink_hz: 145_846_800 },
            Step { t_ms: 12_000, downlink_hz: 436_802_000, uplink_hz: 145_847_600 },
            Step { t_ms: 71_500, downlink_hz: 436_795_000, uplink_hz: 145_850_000 },
            Step { t_ms: 130_000, downlink_hz: 436_787_500, uplink_hz: 145_852_500 },
        ];
        let packed = pack_steps(start(), &steps).unwrap();
        assert_eq!(packed.len(), steps.len() * STEP_BYTES);
        let unpacked = unpack_steps(start(), &packed).unwrap();
        assert_eq!(unpacked, steps);
    }

    #[test]
    fn round_trip_downlink_only() {
        let start = StartFreqs { downlink_hz: 145_960_000, uplink_hz: 0 };
        let steps = vec![
            Step { t_ms: 0, downlink_hz: 145_963_300, uplink_hz: 0 },
            Step { t_ms: 5_000, downlink_hz: 145_963_200, uplink_hz: 0 },
        ];
        let packed = pack_steps(start, &steps).unwrap();
        assert_eq!(unpack_steps(start, &packed).unwrap(), steps);
    }

    #[test]
    fn rejects_gap_over_limit() {
        let steps = vec![
            Step { t_ms: 0, downlink_hz: 436_795_000, uplink_hz: 145_850_000 },
            Step { t_ms: MAX_STEP_GAP_MS + 1, downlink_hz: 436_795_000, uplink_hz: 145_850_000 },
        ];
        assert_eq!(pack_steps(start(), &steps), Err(PackError::GapTooLarge { index: 1 }));
    }

    #[test]
    fn rejects_non_monotonic() {
        let steps = vec![
            Step { t_ms: 5_000, downlink_hz: 436_795_000, uplink_hz: 145_850_000 },
            Step { t_ms: 4_000, downlink_hz: 436_795_000, uplink_hz: 145_850_000 },
        ];
        assert_eq!(pack_steps(start(), &steps), Err(PackError::NotMonotonic { index: 1 }));
    }

    #[test]
    fn rejects_delta_overflow() {
        let steps = vec![Step { t_ms: 0, downlink_hz: 437_795_000, uplink_hz: 145_850_000 }];
        // 1 MHz jump = 100_000 dhz > i16::MAX.
        assert_eq!(pack_steps(start(), &steps), Err(PackError::DeltaOverflow { index: 0 }));
    }

    #[test]
    fn rejects_non_ten_hz() {
        let steps = vec![Step { t_ms: 0, downlink_hz: 436_795_005, uplink_hz: 145_850_000 }];
        assert_eq!(pack_steps(start(), &steps), Err(PackError::NotTenHz { index: 0 }));
    }

    #[test]
    fn rejects_bad_length() {
        assert_eq!(unpack_steps(start(), &[0u8; 7]), Err(UnpackError::BadLength));
    }

    #[test]
    fn cursor_coalesces_missed_steps() {
        let steps = vec![
            Step { t_ms: 0, downlink_hz: 436_804_500, uplink_hz: 145_846_800 },
            Step { t_ms: 10_000, downlink_hz: 436_802_000, uplink_hz: 145_847_600 },
            Step { t_ms: 20_000, downlink_hz: 436_799_500, uplink_hz: 145_848_400 },
            Step { t_ms: 30_000, downlink_hz: 436_797_000, uplink_hz: 145_849_200 },
        ];
        let mut cursor = Cursor::new();
        // Executor stalled (TX guard) until t=25s: gets only the t=20s step.
        let due = cursor.due(&steps, 25_000).unwrap();
        assert_eq!(due.t_ms, 20_000);
        assert_eq!(cursor.next_index(), 3);
        assert!(cursor.due(&steps, 25_000).is_none());
        assert_eq!(cursor.next_due_in(&steps, 25_000), Some(5_000));
        let due = cursor.due(&steps, 30_000).unwrap();
        assert_eq!(due.t_ms, 30_000);
        assert!(cursor.finished(&steps));
        assert_eq!(cursor.next_due_in(&steps, 30_000), None);
    }

    #[test]
    fn cursor_mid_pass_seek_lands_on_latest() {
        let steps = vec![
            Step { t_ms: 0, downlink_hz: 436_804_500, uplink_hz: 145_846_800 },
            Step { t_ms: 10_000, downlink_hz: 436_802_000, uplink_hz: 145_847_600 },
            Step { t_ms: 20_000, downlink_hz: 436_799_500, uplink_hz: 145_848_400 },
        ];
        let mut cursor = Cursor::new();
        cursor.seek(&steps, 15_000);
        let due = cursor.due(&steps, 15_000).unwrap();
        assert_eq!(due.t_ms, 10_000);
    }
}
