//! Free-frequency planner — port of iOS `FreeFrequencyPlanner` (+ the
//! `ModeFilter` it borrows from `SpotFilters`).
//!
//! Picks a clear frequency on a band by nestling among the currently-active
//! stations with enough clearance to avoid interference, honouring the
//! operator's license privileges and the band's conventional usage zones. The
//! **network fetch** of live spots (`ActiveSpotsLoader`: POTA/RBN/SOTA) stays
//! host-side; this owns the pure filter + recommend algorithm so the iOS wizard
//! auto-pick and the Android wizard produce the same frequency from the same
//! on-air picture.

use crate::band_plan::{self, BandSegment, LicenseClass, UsageZone, ViolationType};

/// Minimum spacing from the nearest active station (2 kHz).
pub const MIN_CLEARANCE_MHZ: f64 = 0.002;

/// Spots older than this (seconds) are ignored when judging what's on-air.
pub const MAX_SPOT_AGE_SEC: i64 = 12 * 60;

/// One currently-active station, de-duplicated by the host across POTA/RBN/SOTA.
#[derive(Debug, Clone, PartialEq)]
pub struct ActiveStation {
    pub callsign: String,
    pub band: String,
    pub mode: String,
    pub frequency_mhz: f64,
    /// Unix-seconds timestamp of the spot.
    pub timestamp: i64,
}

/// Mode grouping used to decide which stations are relevant (`ModeFilter`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ModeFilter {
    All,
    Cw,
    Ssb,
    Ft8,
    Ft4,
    Digital,
}

impl ModeFilter {
    /// `ModeFilter.from(modeName:)`.
    pub fn from_mode(mode: &str) -> ModeFilter {
        match mode.to_uppercase().as_str() {
            "CW" => ModeFilter::Cw,
            "SSB" | "USB" | "LSB" => ModeFilter::Ssb,
            "FT8" => ModeFilter::Ft8,
            "FT4" => ModeFilter::Ft4,
            _ => ModeFilter::All,
        }
    }

    /// Whether a station's mode belongs to this filter (`matches`).
    pub fn matches(self, mode: &str) -> bool {
        let upper = mode.to_uppercase();
        match self {
            ModeFilter::All => true,
            ModeFilter::Cw => upper == "CW",
            ModeFilter::Ssb => ["SSB", "USB", "LSB", "AM", "FM"].contains(&upper.as_str()),
            ModeFilter::Ft8 => upper == "FT8",
            ModeFilter::Ft4 => upper == "FT4",
            ModeFilter::Digital => [
                "FT8", "FT4", "RTTY", "PSK31", "PSK", "JT65", "JT9", "JTTY", "DATA", "DIGITAL",
            ]
            .contains(&upper.as_str()),
        }
    }
}

/// The planner: a `mode` + operator `license`.
#[derive(Debug, Clone, Copy)]
pub struct FreeFrequencyPlanner<'a> {
    pub mode: &'a str,
    pub license: LicenseClass,
}

impl<'a> FreeFrequencyPlanner<'a> {
    pub fn new(mode: &'a str, license: LicenseClass) -> Self {
        FreeFrequencyPlanner { mode, license }
    }

    /// Stations relevant to `mode` and legal for `license` — the exact filter
    /// the band suggestions list applies (`relevantStations`). Out-of-band /
    /// no-privileges / wrong-mode stations are dropped; "unusual" ones are kept.
    pub fn relevant_stations(&self, stations: &[ActiveStation]) -> Vec<ActiveStation> {
        let filter = ModeFilter::from_mode(self.mode);
        stations
            .iter()
            .filter(|station| {
                if !filter.matches(&station.mode) {
                    return false;
                }
                match band_plan::validate(station.frequency_mhz, &station.mode, self.license) {
                    Some(ViolationType::OutOfBand)
                    | Some(ViolationType::NoPrivileges)
                    | Some(ViolationType::WrongMode) => false,
                    Some(ViolationType::UnusualFrequency) | None => true,
                }
            })
            .cloned()
            .collect()
    }

    /// A free frequency nestled among `stations` on `band`, plus a short human
    /// reason (e.g. `"3 kHz clear"`) (`recommend`). `frequency` is `None` when
    /// there's no live activity to nestle against or no clear slot exists.
    pub fn recommend(
        &self,
        band: &str,
        stations: &[ActiveStation],
        now: i64,
    ) -> (Option<f64>, String) {
        let mut occupied: Vec<f64> = stations
            .iter()
            .filter(|station| now - station.timestamp <= MAX_SPOT_AGE_SEC)
            .map(|station| station.frequency_mhz)
            .collect();
        occupied.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        if occupied.is_empty() {
            return (None, String::new());
        }

        let privileged: Vec<&BandSegment> = band_plan::privileged_segments(self.license)
            .into_iter()
            .filter(|seg| seg.band == band)
            .collect();
        let wide: Vec<&BandSegment> = privileged
            .iter()
            .filter(|seg| seg.minimum_license != LicenseClass::Extra)
            .copied()
            .collect();
        let prefer_wide = !wide.is_empty();

        let all_zones = band_plan::usage_zones_for(band, self.mode);
        let primary: Vec<&UsageZone> =
            all_zones.iter().filter(|zone| zone.is_primary_zone(self.mode)).copied().collect();
        let secondary: Vec<&UsageZone> =
            all_zones.iter().filter(|zone| !zone.is_primary_zone(self.mode)).copied().collect();

        let wide_or_all: &[&BandSegment] = if prefer_wide { &wide } else { &privileged };
        let attempts: [(&[&UsageZone], &[&BandSegment]); 4] = [
            (&primary, wide_or_all),
            (&primary, &privileged),
            (&secondary, wide_or_all),
            (&secondary, &privileged),
        ];

        for (zones, segs) in attempts {
            if zones.is_empty() || segs.is_empty() {
                continue;
            }
            let result = nestled_frequency(zones, segs, &occupied);
            if result.0.is_some() {
                return result;
            }
        }
        (None, String::new())
    }
}

/// Scan the zones kHz-by-kHz for licensed slots with enough clearance, then pick
/// the candidate closest to the centre of activity (`nestledFrequency`).
fn nestled_frequency(
    zones: &[&UsageZone],
    privileged: &[&BandSegment],
    occupied: &[f64],
) -> (Option<f64>, String) {
    let mut candidates: Vec<(f64, f64)> = Vec::new();
    for zone in zones {
        let start_khz = (zone.start_mhz * 1_000.0) as i64;
        let end_khz = (zone.end_mhz * 1_000.0) as i64;
        let mut khz = start_khz;
        while khz < end_khz {
            let mhz = khz as f64 / 1_000.0;
            if privileged.iter().any(|seg| seg.contains(mhz)) {
                let clearance = occupied
                    .iter()
                    .map(|freq| (mhz - freq).abs())
                    .fold(f64::INFINITY, f64::min);
                if clearance >= MIN_CLEARANCE_MHZ {
                    candidates.push((mhz, clearance));
                }
            }
            khz += 1;
        }
    }

    if candidates.is_empty() {
        return (None, "No clear frequency found".to_string());
    }

    let center = occupied.iter().sum::<f64>() / occupied.len() as f64;
    // First candidate minimizing distance to centre (matches Swift `min(by:)`).
    let best = candidates
        .iter()
        .copied()
        .reduce(|acc, cand| {
            if (cand.0 - center).abs() < (acc.0 - center).abs() {
                cand
            } else {
                acc
            }
        })
        .expect("candidates is non-empty");
    (Some(best.0), format!("{} kHz clear", (best.1 * 1_000.0) as i64))
}

/// Full wizard pipeline: band-filter the loaded stations, keep the relevant
/// ones, then recommend a frequency (mirrors `SessionStartSheet+FrequencySuggestion`:
/// `load(mode).filter(band) → relevantStations → recommend`).
pub fn plan_frequency(
    band: &str,
    mode: &str,
    license: LicenseClass,
    stations: &[ActiveStation],
    now: i64,
) -> (Option<f64>, String) {
    let planner = FreeFrequencyPlanner::new(mode, license);
    let on_band: Vec<ActiveStation> =
        stations.iter().filter(|station| station.band == band).cloned().collect();
    let relevant = planner.relevant_stations(&on_band);
    planner.recommend(band, &relevant, now)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn station(callsign: &str, band: &str, mode: &str, freq: f64, ts: i64) -> ActiveStation {
        ActiveStation {
            callsign: callsign.to_string(),
            band: band.to_string(),
            mode: mode.to_string(),
            frequency_mhz: freq,
            timestamp: ts,
        }
    }

    #[test]
    fn mode_filter_from_and_matches() {
        assert_eq!(ModeFilter::from_mode("usb"), ModeFilter::Ssb);
        assert!(ModeFilter::Ssb.matches("LSB"));
        assert!(ModeFilter::Cw.matches("cw"));
        assert!(!ModeFilter::Cw.matches("SSB"));
        assert!(ModeFilter::All.matches("anything"));
    }

    #[test]
    fn relevant_drops_wrong_mode_and_out_of_band() {
        let planner = FreeFrequencyPlanner::new("CW", LicenseClass::General);
        let stations = vec![
            station("A", "20m", "CW", 14.030, 100),   // kept
            station("B", "20m", "SSB", 14.250, 100),  // dropped: mode filter
            station("C", "20m", "CW", 99.999, 100),   // dropped: out of band
        ];
        let relevant = planner.relevant_stations(&stations);
        assert_eq!(relevant.len(), 1);
        assert_eq!(relevant[0].callsign, "A");
    }

    #[test]
    fn no_activity_returns_none() {
        let planner = FreeFrequencyPlanner::new("CW", LicenseClass::General);
        assert_eq!(planner.recommend("20m", &[], 1000), (None, String::new()));
    }

    #[test]
    fn stale_spots_are_ignored() {
        let planner = FreeFrequencyPlanner::new("CW", LicenseClass::General);
        // Spot is older than MAX_SPOT_AGE_SEC → treated as no activity.
        let stations = vec![station("A", "20m", "CW", 14.030, 0)];
        let now = MAX_SPOT_AGE_SEC + 10;
        assert_eq!(planner.recommend("20m", &stations, now), (None, String::new()));
    }

    #[test]
    fn recommends_clear_frequency_near_activity() {
        let planner = FreeFrequencyPlanner::new("CW", LicenseClass::General);
        // Two CW ops near 14.030 / 14.035; expect a licensed clear slot nearby.
        let stations = vec![
            station("A", "20m", "CW", 14.030, 1000),
            station("B", "20m", "CW", 14.035, 1000),
        ];
        let (freq, reason) = planner.recommend("20m", &stations, 1000);
        let freq = freq.expect("a clear frequency");
        // Within the General CW zone (14.025–14.150) and cleared by >= 2 kHz.
        assert!((14.025..14.070).contains(&freq), "freq {freq} in CW zone");
        assert!(reason.ends_with("kHz clear"), "reason was {reason}");
        // At least 2 kHz from both occupants.
        assert!((freq - 14.030).abs() >= MIN_CLEARANCE_MHZ - 1e-9);
        assert!((freq - 14.035).abs() >= MIN_CLEARANCE_MHZ - 1e-9);
    }

    #[test]
    fn full_pipeline_filters_band_and_mode() {
        // Off-band + wrong-mode stations must not influence the pick.
        let stations = vec![
            station("A", "20m", "CW", 14.030, 1000),
            station("B", "40m", "CW", 7.030, 1000),   // other band
            station("C", "20m", "SSB", 14.250, 1000), // wrong mode
        ];
        let (freq, _) = plan_frequency("20m", "CW", LicenseClass::General, &stations, 1000);
        let freq = freq.expect("a clear frequency");
        assert!((14.025..14.070).contains(&freq));
    }
}
