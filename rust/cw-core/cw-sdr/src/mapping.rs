//! SDR-frequency ↔ RF mapping driven by the rig's CAT state.
//!
//! Both supported topologies reduce to one affine map:
//!
//! ```text
//! rf(f_sdr) = anchor_rf + sign · (f_sdr − anchor_sdr)
//! ```
//!
//! * **IF tap** — the SDR watches the rig's IF output (Elecraft K3 IF OUT at
//!   8.215 MHz). The receive frequency sits at `if_hz + cal_hz[mode]` in the
//!   SDR spectrum, and `sign` is −1 when the rig's mixing inverts the
//!   spectrum. The SDR stays parked at `if_hz + lo_offset_hz`; the offset
//!   keeps the SDR's own DC spike away from the signal under the VFO.
//! * **Direct RF** — the SDR hears the antenna directly (`sign` +1, anchors
//!   0) and is retuned to `vfo + lo_offset_hz` whenever the display window
//!   would fall outside the SDR's usable bandwidth.

use std::collections::HashMap;

/// Fraction of the sample rate treated as usable (the rest is filter skirt).
pub const USABLE_FRACTION: f64 = 0.9;

/// Calibration map key that applies to any mode without its own entry.
pub const ANY_MODE_KEY: &str = "*";

/// Snapshot of the rig's CAT state.
#[derive(Debug, Clone, PartialEq)]
pub struct RigTuning {
    pub vfo_hz: f64,
    pub mode: String,
    pub rit_hz: f64,
    pub rit_enabled: bool,
    pub transmitting: bool,
}

impl RigTuning {
    /// Frequency actually being received (VFO plus RIT when enabled).
    pub fn receive_hz(&self) -> f64 {
        if self.rit_enabled {
            self.vfo_hz + self.rit_hz
        } else {
            self.vfo_hz
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum TuningMode {
    IfTap {
        if_hz: f64,
        inverted: bool,
        lo_offset_hz: f64,
        /// Per-mode offset (Hz) of the receive frequency from `if_hz`, keyed
        /// by uppercase CAT mode (`"CW"`, `"USB"`, …) or [`ANY_MODE_KEY`].
        cal_hz_by_mode: HashMap<String, f64>,
    },
    DirectRf {
        lo_offset_hz: f64,
    },
}

/// Affine SDR ↔ RF frequency map.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FrequencyMap {
    pub anchor_rf: f64,
    pub anchor_sdr: f64,
    pub sign: f64,
}

impl FrequencyMap {
    pub fn sdr_to_rf(&self, sdr_hz: f64) -> f64 {
        self.anchor_rf + self.sign * (sdr_hz - self.anchor_sdr)
    }

    pub fn rf_to_sdr(&self, rf_hz: f64) -> f64 {
        self.anchor_sdr + self.sign * (rf_hz - self.anchor_rf)
    }
}

impl TuningMode {
    /// Calibration offset for `mode` (exact match, then [`ANY_MODE_KEY`], else 0).
    pub fn cal_hz(&self, mode: &str) -> f64 {
        match self {
            TuningMode::IfTap { cal_hz_by_mode, .. } => {
                let key = mode.trim().to_uppercase();
                cal_hz_by_mode.get(&key).or_else(|| cal_hz_by_mode.get(ANY_MODE_KEY)).copied().unwrap_or(0.0)
            }
            TuningMode::DirectRf { .. } => 0.0,
        }
    }

    pub fn frequency_map(&self, tuning: &RigTuning) -> FrequencyMap {
        match self {
            TuningMode::IfTap { if_hz, inverted, .. } => FrequencyMap {
                anchor_rf: tuning.receive_hz(),
                anchor_sdr: if_hz + self.cal_hz(&tuning.mode),
                sign: if *inverted { -1.0 } else { 1.0 },
            },
            TuningMode::DirectRf { .. } => FrequencyMap { anchor_rf: 0.0, anchor_sdr: 0.0, sign: 1.0 },
        }
    }

    /// Where the SDR should be tuned for `tuning` from scratch.
    pub fn ideal_sdr_center(&self, tuning: &RigTuning) -> f64 {
        match self {
            TuningMode::IfTap { if_hz, lo_offset_hz, .. } => if_hz + lo_offset_hz,
            TuningMode::DirectRf { lo_offset_hz } => tuning.receive_hz() + lo_offset_hz,
        }
    }

    /// New SDR center to tune to, or `None` if the current one still works.
    /// An IF tap never moves once parked; direct RF retunes only when the
    /// VFO-centered display window leaves the SDR's usable bandwidth.
    pub fn retune_target(&self, tuning: &RigTuning, current_center: f64, sample_rate: f64, span_hz: f64) -> Option<f64> {
        let ideal = self.ideal_sdr_center(tuning);
        match self {
            TuningMode::IfTap { .. } => ((ideal - current_center).abs() > 0.5).then_some(ideal),
            TuningMode::DirectRf { .. } => {
                let usable_half = sample_rate * USABLE_FRACTION / 2.0;
                let reach = (tuning.receive_hz() - current_center).abs() + span_hz / 2.0;
                (reach > usable_half && (ideal - current_center).abs() > 0.5).then_some(ideal)
            }
        }
    }
}

/// Project a DC-centered dB spectrum onto `bins` display bins spanning
/// `span_hz` around `display_center_rf`. Each display bin takes the max of
/// the FFT bins it covers (so narrow signals survive decimation); bins outside
/// the SDR's usable bandwidth are `NEG_INFINITY`. Inversion falls out of the
/// map's sign, so the output is always ascending in RF.
pub fn project(
    spectrum_db: &[f32],
    sample_rate: f64,
    sdr_center: f64,
    map: &FrequencyMap,
    display_center_rf: f64,
    span_hz: f64,
    bins: usize,
) -> Vec<f32> {
    let size = spectrum_db.len();
    if size == 0 || bins == 0 {
        return vec![f32::NEG_INFINITY; bins];
    }
    let bin_hz = sample_rate / size as f64;
    let usable_half = sample_rate * USABLE_FRACTION / 2.0;
    let half = (size / 2) as i64;
    let out_bin_hz = span_hz / bins as f64;
    let start_rf = display_center_rf - span_hz / 2.0;

    (0..bins)
        .map(|j| {
            let rf_lo = start_rf + j as f64 * out_bin_hz;
            let edge_a = map.rf_to_sdr(rf_lo) - sdr_center;
            let edge_b = map.rf_to_sdr(rf_lo + out_bin_hz) - sdr_center;
            let (lo, hi) = if edge_a <= edge_b { (edge_a, edge_b) } else { (edge_b, edge_a) };
            if hi < -usable_half || lo > usable_half {
                return f32::NEG_INFINITY;
            }
            let first = ((lo.max(-usable_half) / bin_hz).round() as i64 + half).clamp(0, size as i64 - 1);
            let last = ((hi.min(usable_half) / bin_hz).round() as i64 + half).clamp(first, size as i64 - 1);
            spectrum_db[first as usize..=last as usize].iter().copied().fold(f32::NEG_INFINITY, f32::max)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const K3_IF: f64 = 8_215_000.0;

    fn tuning(vfo: f64, mode: &str) -> RigTuning {
        RigTuning { vfo_hz: vfo, mode: mode.into(), rit_hz: 0.0, rit_enabled: false, transmitting: false }
    }

    fn if_tap(inverted: bool, cal: &[(&str, f64)]) -> TuningMode {
        TuningMode::IfTap {
            if_hz: K3_IF,
            inverted,
            lo_offset_hz: 20_000.0,
            cal_hz_by_mode: cal.iter().map(|(k, v)| (k.to_string(), *v)).collect(),
        }
    }

    #[test]
    fn if_tap_upright_maps_offsets_directly() {
        let map = if_tap(false, &[]).frequency_map(&tuning(14_030_000.0, "CW"));
        assert_eq!(map.sdr_to_rf(K3_IF + 1_000.0), 14_031_000.0);
        assert_eq!(map.rf_to_sdr(14_029_000.0), K3_IF - 1_000.0);
    }

    #[test]
    fn if_tap_inverted_flips_offsets() {
        let map = if_tap(true, &[]).frequency_map(&tuning(7_025_000.0, "CW"));
        assert_eq!(map.sdr_to_rf(K3_IF + 1_000.0), 7_024_000.0);
        assert_eq!(map.rf_to_sdr(7_026_500.0), K3_IF - 1_500.0);
    }

    #[test]
    fn cal_offset_is_per_mode_with_fallback() {
        let mode = if_tap(false, &[("CW", 600.0), (ANY_MODE_KEY, -100.0)]);
        assert_eq!(mode.cal_hz("cw"), 600.0);
        assert_eq!(mode.cal_hz("USB"), -100.0);
        let map = mode.frequency_map(&tuning(14_030_000.0, "CW"));
        assert_eq!(map.sdr_to_rf(K3_IF + 600.0), 14_030_000.0);
        assert_eq!(if_tap(false, &[]).cal_hz("CW"), 0.0);
    }

    #[test]
    fn rit_shifts_receive_anchor() {
        let mut rig = tuning(14_030_000.0, "CW");
        rig.rit_hz = 250.0;
        assert_eq!(rig.receive_hz(), 14_030_000.0);
        rig.rit_enabled = true;
        let map = if_tap(false, &[]).frequency_map(&rig);
        assert_eq!(map.sdr_to_rf(K3_IF), 14_030_250.0);
    }

    #[test]
    fn if_tap_parks_once() {
        let mode = if_tap(true, &[]);
        let rig = tuning(14_030_000.0, "CW");
        assert_eq!(mode.retune_target(&rig, 0.0, 2e6, 96e3), Some(K3_IF + 20_000.0));
        assert_eq!(mode.retune_target(&rig, K3_IF + 20_000.0, 2e6, 96e3), None);
        assert_eq!(mode.retune_target(&tuning(3_530_000.0, "LSB"), K3_IF + 20_000.0, 2e6, 96e3), None);
    }

    #[test]
    fn direct_rf_retunes_with_hysteresis() {
        let mode = TuningMode::DirectRf { lo_offset_hz: 20_000.0 };
        let sdr_center = 14_050_000.0;
        // 192 kS/s → usable ±86.4 kHz; 48 kHz span needs 24 kHz of room.
        assert_eq!(mode.retune_target(&tuning(14_030_000.0, "CW"), sdr_center, 192e3, 48e3), None);
        assert_eq!(mode.retune_target(&tuning(14_100_000.0, "CW"), sdr_center, 192e3, 48e3), None);
        assert_eq!(
            mode.retune_target(&tuning(14_120_000.0, "CW"), sdr_center, 192e3, 48e3),
            Some(14_140_000.0)
        );
        let map = mode.frequency_map(&tuning(14_120_000.0, "CW"));
        assert_eq!(map.sdr_to_rf(14_000_123.0), 14_000_123.0);
    }

    /// Spectrum of `size` bins at -100 dB with a -20 dB peak at `offset_hz`.
    fn spectrum_with_peak(size: usize, rate: f64, offset_hz: f64) -> Vec<f32> {
        let mut line = vec![-100.0f32; size];
        let idx = (offset_hz / (rate / size as f64)).round() as i64 + (size / 2) as i64;
        line[idx as usize] = -20.0;
        line
    }

    fn peak_index(line: &[f32]) -> usize {
        line.iter().enumerate().fold(0, |best, (i, v)| if *v > line[best] { i } else { best })
    }

    #[test]
    fn project_places_inverted_if_signal_by_rf() {
        let rate = 192_000.0;
        let sdr_center = K3_IF + 20_000.0;
        // Signal 1.5 kHz below IF center in the SDR → 1.5 kHz above VFO (inverted).
        let spectrum = spectrum_with_peak(8192, rate, (K3_IF - 1_500.0) - sdr_center);
        let rig = tuning(14_030_000.0, "CW");
        let map = if_tap(true, &[]).frequency_map(&rig);
        let line = project(&spectrum, rate, sdr_center, &map, rig.receive_hz(), 48_000.0, 480);
        // 100 Hz display bins: +1.5 kHz → bin 240 + 15.
        assert!(peak_index(&line).abs_diff(255) <= 1, "peak at {}", peak_index(&line));
    }

    #[test]
    fn project_upright_and_out_of_band() {
        let rate = 192_000.0;
        let sdr_center = K3_IF + 20_000.0;
        let spectrum = spectrum_with_peak(8192, rate, (K3_IF - 1_500.0) - sdr_center);
        let rig = tuning(14_030_000.0, "CW");
        let map = if_tap(false, &[]).frequency_map(&rig);
        let line = project(&spectrum, rate, sdr_center, &map, rig.receive_hz(), 48_000.0, 480);
        assert!(peak_index(&line).abs_diff(225) <= 1);
        assert!(line.iter().all(|v| v.is_finite()));

        // A 300 kHz span reaches past the ±86.4 kHz usable edge.
        let wide = project(&spectrum, rate, sdr_center, &map, rig.receive_hz(), 300_000.0, 300);
        assert_eq!(wide[0], f32::NEG_INFINITY);
        assert_eq!(wide[299], f32::NEG_INFINITY);
        assert!(wide[150].is_finite());
    }

    #[test]
    fn project_max_pools_when_decimating() {
        let rate = 192_000.0;
        let spectrum = spectrum_with_peak(65_536, rate, 1_234.0);
        let map = FrequencyMap { anchor_rf: 0.0, anchor_sdr: 0.0, sign: 1.0 };
        let line = project(&spectrum, rate, 7_000_000.0, &map, 7_000_000.0, 96_000.0, 64);
        assert_eq!(line.iter().copied().fold(f32::NEG_INFINITY, f32::max), -20.0);
    }
}
