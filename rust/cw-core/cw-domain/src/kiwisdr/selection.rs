//! Tune-In receiver selection and smart-feature decision logic. Port of the
//! pure halves of `TuneInManager+ReceiverSelection.swift` and
//! `TuneInManager+SmartFeatures.swift`. The async orchestration (RBN / HamDB
//! lookups, `/status` fetches) lives in `cw-ffi`'s `SdrApi`; everything here
//! is deterministic and unit-testable.

use super::directory::KiwiSdrReceiver;

/// How the user wants to select a KiwiSDR receiver for Tune In.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TuneInStrategy {
    /// Find an SDR near the strongest RBN spotter (best signal quality).
    NearStrongRbn,
    /// Find an SDR near the activator's location (hear what they hear).
    NearActivator,
    /// Find an SDR near the user's own QTH.
    NearMyQth,
}

/// Lightweight snapshot of a spot being tuned into. Coordinates for the park /
/// summit / spot are resolved by the host (it owns those caches) and passed in
/// pre-resolved, in the same precedence order the Swift port used.
#[derive(Debug, Clone, PartialEq)]
pub struct TuneInSpot {
    pub callsign: String,
    pub frequency_mhz: f64,
    pub mode: String,
    pub band: String,
    pub park_ref: Option<String>,
    pub summit_code: Option<String>,
    /// Spot's own location (e.g. from the RBN spotter grid).
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub grid: Option<String>,
    /// Resolved park coordinates (host-side POTA cache).
    pub park_coordinate: Option<(f64, f64)>,
    /// Resolved summit coordinates (host-side SOTA cache).
    pub summit_coordinate: Option<(f64, f64)>,
}

/// Order-preserving, id-deduplicating candidate accumulator — the `seen` /
/// `candidates` pattern every strategy in the Swift port shared.
#[derive(Debug, Default)]
pub struct CandidateAccumulator {
    seen: std::collections::HashSet<String>,
    candidates: Vec<KiwiSdrReceiver>,
}

impl CandidateAccumulator {
    pub fn new() -> Self {
        Self::default()
    }

    /// Append receivers not yet seen, preserving insertion order.
    pub fn extend(&mut self, receivers: impl IntoIterator<Item = KiwiSdrReceiver>) {
        for receiver in receivers {
            if self.seen.insert(receiver.id.clone()) {
                self.candidates.push(receiver);
            }
        }
    }

    pub fn into_candidates(self) -> Vec<KiwiSdrReceiver> {
        self.candidates
    }

    pub fn is_empty(&self) -> bool {
        self.candidates.is_empty()
    }
}

/// Keep only receivers with a free channel (`users < users_max`).
pub fn filter_available(receivers: Vec<KiwiSdrReceiver>) -> Vec<KiwiSdrReceiver> {
    receivers.into_iter().filter(KiwiSdrReceiver::is_available).collect()
}

// ---------------------------------------------------------------------------
// QSY detection
// ---------------------------------------------------------------------------

/// One RBN observation of the tuned activator, reduced to what QSY detection
/// needs (kept transport-agnostic so cw-domain stays free of cw-net types).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct QsyObservation {
    /// Unix epoch seconds of the spot.
    pub epoch_seconds: f64,
    /// Spot frequency in kHz.
    pub frequency_khz: f64,
}

/// How recent a spot must be to count as a QSY (5 minutes).
pub const QSY_RECENT_WINDOW_SECONDS: f64 = 300.0;

/// Minimum frequency delta in kHz to count as a QSY (matches the Swift
/// `abs(freq - current*1000) > 1.0` check).
pub const QSY_MIN_DELTA_KHZ: f64 = 1.0;

/// Detect a QSY: the most recent observation within the 5-minute window whose
/// frequency differs from the current one by more than 1 kHz. Returns the new
/// frequency in MHz. Port of the decision inside `startQSYMonitor`.
pub fn detect_qsy(
    observations: &[QsyObservation],
    current_frequency_mhz: f64,
    now_epoch_seconds: f64,
) -> Option<f64> {
    let cutoff = now_epoch_seconds - QSY_RECENT_WINDOW_SECONDS;
    let current_khz = current_frequency_mhz * 1_000.0;

    let mut recent: Vec<&QsyObservation> =
        observations.iter().filter(|obs| obs.epoch_seconds > cutoff).collect();
    recent.sort_by(|a, b| {
        b.epoch_seconds.partial_cmp(&a.epoch_seconds).unwrap_or(std::cmp::Ordering::Equal)
    });

    recent
        .iter()
        .find(|obs| (obs.frequency_khz - current_khz).abs() > QSY_MIN_DELTA_KHZ)
        .map(|obs| obs.frequency_khz / 1_000.0)
}

// ---------------------------------------------------------------------------
// Receiver quality
// ---------------------------------------------------------------------------

/// Below this SNR (dB) the quality monitor starts looking for alternatives.
pub const POOR_SNR_THRESHOLD_DB: i32 = 10;

/// An alternative must beat the current receiver by more than this margin.
pub const BETTER_SNR_MARGIN_DB: i32 = 5;

/// Whether the current receiver's SNR is poor enough to scan for alternatives.
pub fn snr_is_poor(current_snr: i32) -> bool {
    current_snr < POOR_SNR_THRESHOLD_DB
}

/// Suggestion to switch to a better receiver.
#[derive(Debug, Clone, PartialEq)]
pub struct ReceiverSuggestion {
    pub current_name: String,
    pub suggested: KiwiSdrReceiver,
    pub reason: String,
}

/// Decide whether `alternative` (with `alternative_snr`) is enough of an
/// improvement over the current receiver to suggest a switch.
pub fn suggest_better_receiver(
    current: &KiwiSdrReceiver,
    current_snr: i32,
    alternative: &KiwiSdrReceiver,
    alternative_snr: i32,
) -> Option<ReceiverSuggestion> {
    if alternative.id == current.id || !alternative.is_available() {
        return None;
    }
    if alternative_snr <= current_snr + BETTER_SNR_MARGIN_DB {
        return None;
    }
    Some(ReceiverSuggestion {
        current_name: current.name.clone(),
        reason: format!(
            "{} has better reception (SNR {alternative_snr} dB vs {current_snr} dB)",
            alternative.name
        ),
        suggested: alternative.clone(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn receiver(id: &str, users: i32, max_users: i32) -> KiwiSdrReceiver {
        KiwiSdrReceiver {
            id: id.into(),
            name: id.into(),
            host: id.into(),
            port: 8_073,
            latitude: 0.0,
            longitude: 0.0,
            bands: String::new(),
            users,
            max_users,
            location: String::new(),
            antenna: String::new(),
            distance_km: None,
            snr_all: None,
            snr_hf: None,
            ant_connected: None,
            grid: None,
            asl: None,
            enriched_antenna: None,
        }
    }

    #[test]
    fn accumulator_dedups_and_preserves_order() {
        let mut acc = CandidateAccumulator::new();
        acc.extend([receiver("a", 0, 4), receiver("b", 0, 4)]);
        acc.extend([receiver("b", 1, 4), receiver("c", 0, 4)]);
        let out = acc.into_candidates();
        assert_eq!(out.iter().map(|r| r.id.as_str()).collect::<Vec<_>>(), ["a", "b", "c"]);
        // First-seen wins: "b" keeps users=0 from the first batch.
        assert_eq!(out[1].users, 0);
    }

    #[test]
    fn availability_filter() {
        let out = filter_available(vec![receiver("free", 1, 4), receiver("full", 4, 4)]);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].id, "free");
    }

    #[test]
    fn qsy_detects_recent_move() {
        let now = 1_000_000.0;
        let obs = [
            // Stale big move — outside the 5-minute window, ignored.
            QsyObservation { epoch_seconds: now - 400.0, frequency_khz: 7_030.0 },
            // Recent same-frequency spot — not a QSY (within 1 kHz).
            QsyObservation { epoch_seconds: now - 100.0, frequency_khz: 14_060.4 },
            // Recent move — this is the QSY.
            QsyObservation { epoch_seconds: now - 50.0, frequency_khz: 14_063.5 },
        ];
        let new_mhz = detect_qsy(&obs, 14.060, now).unwrap();
        assert!((new_mhz - 14.0635).abs() < 1e-9);
    }

    #[test]
    fn qsy_prefers_most_recent_qualifying_spot() {
        let now = 1_000_000.0;
        let obs = [
            QsyObservation { epoch_seconds: now - 200.0, frequency_khz: 14_070.0 },
            QsyObservation { epoch_seconds: now - 10.0, frequency_khz: 14_065.0 },
        ];
        let new_mhz = detect_qsy(&obs, 14.060, now).unwrap();
        assert!((new_mhz - 14.065).abs() < 1e-9);
    }

    #[test]
    fn qsy_none_when_no_recent_move() {
        let now = 1_000_000.0;
        let obs = [QsyObservation { epoch_seconds: now - 100.0, frequency_khz: 14_060.5 }];
        assert_eq!(detect_qsy(&obs, 14.060, now), None);
        assert_eq!(detect_qsy(&[], 14.060, now), None);
    }

    #[test]
    fn snr_thresholds() {
        assert!(snr_is_poor(9));
        assert!(!snr_is_poor(10));
    }

    #[test]
    fn better_receiver_requires_margin_and_availability() {
        let current = receiver("current", 1, 4);
        let good = receiver("good", 0, 4);
        let full = receiver("full", 4, 4);

        // Needs strictly more than +5 dB.
        assert!(suggest_better_receiver(&current, 8, &good, 13).is_none());
        let suggestion = suggest_better_receiver(&current, 8, &good, 14).unwrap();
        assert_eq!(suggestion.suggested.id, "good");
        assert_eq!(suggestion.reason, "good has better reception (SNR 14 dB vs 8 dB)");

        assert!(suggest_better_receiver(&current, 8, &full, 30).is_none(), "full receiver");
        assert!(suggest_better_receiver(&current, 8, &current, 30).is_none(), "same receiver");
    }
}
