//! Curated downlink polarization for well-documented amateur satellites.
//! Port of `SatellitePolarization` (`SatellitePolarization.swift`) —
//! SatNOGS carries no polarization field and the ground-arrival angle is
//! uncomputable (Faraday rotation + tumbling), so this is a small curated
//! table; absent entries mean unknown, never guessed.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Polarization {
    Rhcp,
    Lhcp,
    Circular,
    Linear,
}

impl Polarization {
    pub fn label(&self) -> &'static str {
        match self {
            Polarization::Rhcp => "RHCP",
            Polarization::Lhcp => "LHCP",
            Polarization::Circular => "Circular",
            Polarization::Linear => "Linear",
        }
    }

    pub fn is_circular(&self) -> bool {
        !matches!(self, Polarization::Linear)
    }

    /// One-line operating hint for the pointing lock line (verbatim iOS copy).
    pub fn pointing_hint(&self) -> &'static str {
        if self.is_circular() {
            "Circular downlink — twist won't matter (~3 dB loss on a linear whip)"
        } else {
            "Linear downlink — twist to peak, flip 90° if it fades"
        }
    }

    /// NORAD ID → downlink polarization; entries limited to birds with
    /// documented antennas.
    pub fn lookup(norad_id: u32) -> Option<Polarization> {
        match norad_id {
            7_530 => Some(Polarization::Circular), // AO-7 — canted turnstile, 2 m downlink
            22_825 => Some(Polarization::Linear),  // AO-27 — quarter-wave whip
            25_544 => Some(Polarization::Linear),  // ISS — ARISS linear antennas
            27_607 => Some(Polarization::Linear),  // SO-50 — quarter-wave whips
            39_444 => Some(Polarization::Linear),  // AO-73 (FUNcube-1) — deployable whips
            43_017 => Some(Polarization::Linear),  // AO-91 (Fox-1B) — whip antennas
            43_137 => Some(Polarization::Linear),  // AO-92 (Fox-1D) — whip antennas
            43_700 => Some(Polarization::Linear),  // QO-100 (Es'hail-2) — NB, vertical linear
            43_803 => Some(Polarization::Linear),  // JO-97 (JY1Sat) — whip antennas
            44_909 => Some(Polarization::Linear),  // RS-44 — whip antennas
            53_106 => Some(Polarization::Linear),  // IO-117 (GreenCube) — whip antenna
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn table_matches_ios() {
        assert_eq!(Polarization::lookup(7_530), Some(Polarization::Circular));
        assert_eq!(Polarization::lookup(27_607), Some(Polarization::Linear));
        assert_eq!(Polarization::lookup(99_999), None);
        assert!(Polarization::Rhcp.is_circular());
        assert!(!Polarization::Linear.is_circular());
    }
}
