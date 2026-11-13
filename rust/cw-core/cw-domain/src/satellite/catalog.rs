//! Catalog build: keep only workable satellites carrying at least one
//! amateur-service transmitter, index their transmitters (active first,
//! capabilities the AMSAT community no longer hears dropped), and resolve
//! display names. Port of `SatelliteTrackerModel.buildHamSatellites`.

use std::collections::HashMap;

use chrono::{DateTime, Utc};

use super::amsat::{freshest, AmsatStatus};
use super::display_name;
use super::propagator::SatPropagator;
use super::workability;
use super::{SatTle, SatTransmitter};

/// One tracked satellite: identity + its SGP4 propagator. Port of
/// `SatelliteTrackerModel.TrackedSatellite`.
pub struct HamSatellite {
    pub norad_id: u32,
    /// Short display name — the OSCAR designator when derivable.
    pub name: String,
    /// De-emphasized long mission name, when it differs.
    pub detail_name: Option<String>,
    pub propagator: SatPropagator,
}

pub struct Catalog {
    pub satellites: Vec<HamSatellite>,
    pub transmitters_by_norad: HashMap<u32, Vec<SatTransmitter>>,
}

pub fn build_ham_satellites(
    tles: &[SatTle],
    transmitters: &[SatTransmitter],
    amsat_rows: &HashMap<u32, Vec<AmsatStatus>>,
    catalog_names: &HashMap<u32, String>,
    now: DateTime<Utc>,
) -> Catalog {
    let mut by_norad: HashMap<u32, Vec<SatTransmitter>> = HashMap::new();
    for transmitter in transmitters.iter().filter(|t| t.is_amateur()) {
        let Some(norad) = transmitter.norad_id else {
            continue;
        };
        by_norad.entry(norad).or_default().push(transmitter.clone());
    }
    // AMSAT-tracked rescue: SatNOGS mislabels some amateur birds' service
    // ("Unknown" on every FO-29 transmitter), which would drop them here
    // entirely. AMSAT tracking *is* the amateur signal, so a tracked bird
    // with zero amateur-service transmitters gets its full transmitter list
    // admitted instead (birds with any amateur row keep the strict filter).
    for norad in amsat_rows.keys() {
        if by_norad.contains_key(norad) {
            continue;
        }
        let rescued: Vec<SatTransmitter> = transmitters
            .iter()
            .filter(|t| t.norad_id == Some(*norad))
            .cloned()
            .collect();
        if !rescued.is_empty() {
            by_norad.insert(*norad, rescued);
        }
    }
    for (norad, list) in by_norad.iter_mut() {
        let rows = amsat_rows.get(norad).map(Vec::as_slice).unwrap_or(&[]);
        let mut active = workability::active_transmitters(list, rows, now);
        active.sort_by(|lhs, rhs| {
            if lhs.is_active() != rhs.is_active() {
                return rhs.is_active().cmp(&lhs.is_active());
            }
            lhs.downlink_low_hz.unwrap_or(0).cmp(&rhs.downlink_low_hz.unwrap_or(0))
        });
        *list = active;
    }
    let satellites = tles
        .iter()
        .filter_map(|tle| {
            let rows = amsat_rows.get(&tle.norad_id).map(Vec::as_slice).unwrap_or(&[]);
            let fresh = freshest(rows);
            if !by_norad.contains_key(&tle.norad_id)
                || !workability::is_workable(tle.norad_id, rows, now)
            {
                return None;
            }
            let propagator = SatPropagator::from_tle(tle)?;
            // Canonical SatNOGS catalog name (already alias-composed) beats
            // the TLE line-zero name; the AMSAT designator still wins inside
            // `split`.
            let base_name =
                catalog_names.get(&tle.norad_id).map(String::as_str).unwrap_or(&tle.name);
            let (name, detail_name) =
                display_name::split(base_name, fresh.map(|row| row.name.as_str()));
            Some(HamSatellite { norad_id: tle.norad_id, name, detail_name, propagator })
        })
        .collect();
    Catalog { satellites, transmitters_by_norad: by_norad }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{Duration, TimeZone};

    fn now() -> DateTime<Utc> {
        Utc.timestamp_opt(1_790_000_000, 0).unwrap()
    }

    fn tle(norad_id: u32, name: &str) -> SatTle {
        // Orbital elements don't matter here; the ISS lines parse everywhere.
        SatTle {
            name: name.to_string(),
            norad_id,
            line1: "1 25544U 98067A   26262.30395647  .00006211  00000-0  12007-3 0  9998"
                .to_string(),
            line2: "2 25544  51.6308 194.2901 0004815 157.3949 202.7252 15.49175317586346"
                .to_string(),
        }
    }

    fn transmitter(norad_id: u32, mode: &str, service: &str) -> SatTransmitter {
        SatTransmitter {
            description: mode.to_string(),
            transmitter_type: "Transponder".to_string(),
            alive: true,
            status: "active".to_string(),
            service: service.to_string(),
            mode: Some(mode.to_string()),
            uplink_low_hz: Some(145_900_000),
            downlink_low_hz: Some(435_800_000),
            uplink_high_hz: None,
            downlink_high_hz: None,
            invert: false,
            norad_id: Some(norad_id),
        }
    }

    fn amsat(name: &str) -> AmsatStatus {
        AmsatStatus {
            name: name.to_string(),
            norad_id: Some(24_278),
            last_heard_at: Some(now() - Duration::seconds(1_800)),
            last_reported_at: None,
            last_report: None,
            last_callsign: None,
            last_grid: None,
            heard_reports_24h: 32,
            total_reports_24h: 33,
        }
    }

    #[test]
    fn amsat_tracked_bird_with_unknown_service_is_rescued() {
        // FO-29: every SatNOGS transmitter says service "Unknown", but AMSAT
        // hears it — the bird and its transmitters must survive.
        let tles = [tle(24_278, "JAS 2")];
        let transmitters = [transmitter(24_278, "USB", "Unknown")];
        let amsat_rows: HashMap<u32, Vec<AmsatStatus>> =
            [(24_278, vec![amsat("FO-29_[V/u]")])].into();
        let catalog =
            build_ham_satellites(&tles, &transmitters, &amsat_rows, &HashMap::new(), now());
        assert_eq!(catalog.satellites.len(), 1);
        assert_eq!(catalog.satellites[0].name, "FO-29");
        assert_eq!(catalog.transmitters_by_norad[&24_278].len(), 1);

        // Without the AMSAT signal the strict amateur filter still applies.
        let dropped =
            build_ham_satellites(&tles, &transmitters, &HashMap::new(), &HashMap::new(), now());
        assert!(dropped.satellites.is_empty());
    }

    #[test]
    fn catalog_names_override_tle_placeholders() {
        let tles = [tle(44_881, "OBJECT C")];
        let transmitters = [transmitter(44_881, "USB", "Amateur")];
        let names: HashMap<u32, String> = [(44_881, "CAS-6 (TO-108)".to_string())].into();
        let catalog =
            build_ham_satellites(&tles, &transmitters, &HashMap::new(), &names, now());
        assert_eq!(catalog.satellites.len(), 1);
        assert_eq!(catalog.satellites[0].name, "TO-108");
        assert_eq!(catalog.satellites[0].detail_name.as_deref(), Some("CAS-6"));
        // No catalog entry → TLE name passes through.
        let plain =
            build_ham_satellites(&tles, &transmitters, &HashMap::new(), &HashMap::new(), now());
        assert_eq!(plain.satellites[0].name, "OBJECT C");
    }
}
