//! Doppler schedule builder for the CW Sat Bridge.
//!
//! Converts one predicted pass into the expanded step table the bridge
//! firmware executes (`cw-sat-core` wire format): sampled doppler-corrected
//! uplink/downlink frequencies, quantized to per-link tuning steps, emitted
//! only when a quantized value changes (plus ≤60 s keepalives so the packed
//! `dt` never overflows and the executor keeps pushing status).
//!
//! Doppler model matches `tracker.rs`: slant-range finite difference over
//! `RATE_STEP_SECS`, factor = −ṙ/c, downlink × (1 + f), uplink × (1 − f).

use chrono::{DateTime, Duration, Utc};
use cw_sat_core::{Step, StartFreqs, MAX_STEPS, MAX_STEP_GAP_MS};

use super::propagator::SatPropagator;
use super::Observer;

/// Speed of light, km/s (same constant as `satellite_api::look`).
const C_KM_PER_SEC: f64 = 299_792.458;
/// Finite-difference step for the range-rate, matching `tracker.rs`.
const RATE_STEP_SECS: f64 = 10.0;
/// Doppler sampling cadence along the pass.
const SAMPLE_SECS: i64 = 1;

/// Default per-link tuning steps: FM birds retune in 2.5 kHz hops; linear
/// downlink RX tracks at 100 Hz.
pub const FM_STEP_HZ: u32 = 2_500;
pub const LINEAR_RX_STEP_HZ: u32 = 100;

#[derive(Debug, Clone, Copy)]
pub struct DopplerScheduleParams {
    /// Transponder downlink center (Hz).
    pub downlink_hz: u64,
    /// Transponder uplink center (Hz); `None` for downlink-only tracking.
    pub uplink_hz: Option<u64>,
    /// Downlink retune quantum (Hz). Must be a multiple of 10.
    pub downlink_step_hz: u32,
    /// Uplink retune quantum (Hz). Must be a multiple of 10.
    pub uplink_step_hz: u32,
}

#[derive(Debug, Clone)]
pub struct DopplerSchedule {
    /// Quantized frequencies at AOS — `SatScheduleBegin.*_start_hz` and the
    /// firmware's initial radio setup values.
    pub start: StartFreqs,
    pub steps: Vec<Step>,
    pub duration_ms: u64,
}

/// Quantize a corrected frequency to the link's tuning step (round to
/// nearest). Steps are multiples of 10 Hz, so the result always satisfies
/// the wire format's 10 Hz constraint.
fn quantize(hz: f64, step_hz: u32) -> u64 {
    let step = f64::from(step_hz.max(10));
    ((hz / step).round() * step).max(0.0) as u64
}

/// Doppler factor −ṙ/c at `t`, from a slant-range finite difference.
fn doppler_factor(
    propagator: &SatPropagator,
    observer: Observer,
    t: DateTime<Utc>,
) -> Option<f64> {
    let here = propagator.look(t, observer)?;
    let ahead = propagator.look(t + Duration::seconds(RATE_STEP_SECS as i64), observer)?;
    let range_rate = (ahead.range_km - here.range_km) / RATE_STEP_SECS;
    Some(-range_rate / C_KM_PER_SEC)
}

/// Build the expanded step table for one pass. Returns `None` when the pass
/// window is empty, propagation fails at AOS, or the table would exceed the
/// wire format's `MAX_STEPS`.
pub fn build(
    propagator: &SatPropagator,
    observer: Observer,
    aos: DateTime<Utc>,
    los: DateTime<Utc>,
    params: &DopplerScheduleParams,
) -> Option<DopplerSchedule> {
    let duration_ms = (los - aos).num_milliseconds();
    if duration_ms <= 0 {
        return None;
    }
    let duration_ms = duration_ms as u64;
    let uplink_hz = params.uplink_hz.unwrap_or(0);

    let factor0 = doppler_factor(propagator, observer, aos)?;
    let start = StartFreqs {
        downlink_hz: quantize(params.downlink_hz as f64 * (1.0 + factor0), params.downlink_step_hz),
        uplink_hz: if uplink_hz > 0 {
            quantize(uplink_hz as f64 * (1.0 - factor0), params.uplink_step_hz)
        } else {
            0
        },
    };

    let mut steps = Vec::new();
    steps.push(Step { t_ms: 0, downlink_hz: start.downlink_hz, uplink_hz: start.uplink_hz });
    let mut last = *steps.last().expect("just pushed");

    let duration_secs = (duration_ms / 1_000) as i64;
    let mut t_secs = SAMPLE_SECS;
    while t_secs <= duration_secs {
        let t_ms = t_secs as u64 * 1_000;
        let at = aos + Duration::seconds(t_secs);
        t_secs += SAMPLE_SECS;
        // A failed sample mid-pass (decayed propagation edge) is skipped —
        // the previous commanded frequencies simply persist.
        let Some(factor) = doppler_factor(propagator, observer, at) else {
            continue;
        };
        let down = quantize(params.downlink_hz as f64 * (1.0 + factor), params.downlink_step_hz);
        let up = if uplink_hz > 0 {
            quantize(uplink_hz as f64 * (1.0 - factor), params.uplink_step_hz)
        } else {
            0
        };
        let changed = down != last.downlink_hz || up != last.uplink_hz;
        let keepalive_due = t_ms - last.t_ms >= MAX_STEP_GAP_MS;
        if changed || keepalive_due {
            let step = Step { t_ms, downlink_hz: down, uplink_hz: up };
            steps.push(step);
            last = step;
        }
        if steps.len() > MAX_STEPS {
            return None;
        }
    }

    Some(DopplerSchedule { start, steps, duration_ms })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::satellite::pass_predictor;
    use crate::satellite::propagator::iss_propagator;
    use chrono::TimeZone;
    use cw_sat_core::{pack_steps, unpack_steps};

    fn iss_pass() -> (SatPropagator, Observer, DateTime<Utc>, DateTime<Utc>) {
        let sat = iss_propagator();
        let observer = Observer::new(37.7749, -122.4194);
        let start = Utc.with_ymd_and_hms(2026, 9, 19, 12, 0, 0).unwrap();
        let forecast = pass_predictor::forecast(&sat, observer, start, 48.0, 12);
        // The 43.5° pass from the SatelliteKit fixture set.
        let pass = forecast.passes[1].clone();
        (sat, observer, pass.aos, pass.los)
    }

    fn fm_params() -> DopplerScheduleParams {
        // ISS FM crossband repeater: V/U (uplink 145.990, downlink 437.800).
        DopplerScheduleParams {
            downlink_hz: 437_800_000,
            uplink_hz: Some(145_990_000),
            downlink_step_hz: FM_STEP_HZ,
            uplink_step_hz: FM_STEP_HZ,
        }
    }

    #[test]
    fn fm_pass_schedule_shape() {
        let (sat, observer, aos, los) = iss_pass();
        let schedule = build(&sat, observer, aos, los, &fm_params()).expect("schedule");

        // First step mirrors the header start values at t=0.
        assert_eq!(schedule.steps[0].t_ms, 0);
        assert_eq!(schedule.steps[0].downlink_hz, schedule.start.downlink_hz);
        assert_eq!(schedule.steps[0].uplink_hz, schedule.start.uplink_hz);

        // Approaching at AOS: downlink observed HIGH, uplink commanded LOW.
        assert!(schedule.start.downlink_hz > 437_800_000);
        assert!(schedule.start.uplink_hz < 145_990_000);

        // Receding at LOS: signs flip.
        let last = schedule.steps.last().unwrap();
        assert!(last.downlink_hz < 437_800_000);
        assert!(last.uplink_hz > 145_990_000);

        // ISS 70cm doppler swing is ±~9–10 kHz → a handful of 2.5 kHz hops.
        let count = schedule.steps.len();
        assert!((4..=40).contains(&count), "unexpected step count {count}");

        // Monotonic, quantized, gap-bounded.
        let mut prev_t = 0;
        for step in &schedule.steps {
            assert!(step.t_ms >= prev_t);
            assert!(step.t_ms - prev_t <= MAX_STEP_GAP_MS);
            assert_eq!(step.downlink_hz % u64::from(FM_STEP_HZ), 0);
            assert_eq!(step.uplink_hz % u64::from(FM_STEP_HZ), 0);
            prev_t = step.t_ms;
        }

        // Downlink is monotonically non-increasing across an overhead pass.
        let downs: Vec<u64> = schedule.steps.iter().map(|s| s.downlink_hz).collect();
        assert!(downs.windows(2).all(|w| w[1] <= w[0]), "downlink not monotone: {downs:?}");
    }

    #[test]
    fn schedule_packs_round_trip() {
        let (sat, observer, aos, los) = iss_pass();
        let schedule = build(&sat, observer, aos, los, &fm_params()).expect("schedule");
        let packed = pack_steps(schedule.start, &schedule.steps).expect("pack");
        let unpacked = unpack_steps(schedule.start, &packed).expect("unpack");
        assert_eq!(unpacked, schedule.steps);
    }

    #[test]
    fn linear_downlink_only_tracks_finely() {
        let (sat, observer, aos, los) = iss_pass();
        let params = DopplerScheduleParams {
            downlink_hz: 145_960_000,
            uplink_hz: None,
            downlink_step_hz: LINEAR_RX_STEP_HZ,
            uplink_step_hz: LINEAR_RX_STEP_HZ,
        };
        let schedule = build(&sat, observer, aos, los, &params).expect("schedule");
        assert!(schedule.steps.iter().all(|s| s.uplink_hz == 0));
        assert_eq!(schedule.start.uplink_hz, 0);
        // 2m doppler swing ±~3.3 kHz at 100 Hz steps → dozens of steps.
        assert!(schedule.steps.len() > 20, "steps {}", schedule.steps.len());
        assert!(schedule.steps.iter().all(|s| s.downlink_hz % 100 == 0));
        // Round-trips through the wire format.
        let packed = pack_steps(schedule.start, &schedule.steps).expect("pack");
        assert_eq!(unpack_steps(schedule.start, &packed).expect("unpack"), schedule.steps);
    }

    #[test]
    fn rejects_empty_window() {
        let (sat, observer, aos, _) = iss_pass();
        assert!(build(&sat, observer, aos, aos, &fm_params()).is_none());
    }
}
