//! Operator-facing transmitter mode buckets. Port of
//! `SatelliteModeCategory` (`SatelliteTypes.swift`).

use super::SatTransmitter;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ModeCategory {
    VoiceFm,
    Linear,
    Morse,
    Digital,
}

impl ModeCategory {
    pub const ALL: [ModeCategory; 4] =
        [ModeCategory::VoiceFm, ModeCategory::Linear, ModeCategory::Morse, ModeCategory::Digital];

    /// Raw values match the Swift enum ("FM"/"SSB"/"CW"/"DIGI") so persisted
    /// host preferences stay compatible.
    pub fn raw_value(&self) -> &'static str {
        match self {
            ModeCategory::VoiceFm => "FM",
            ModeCategory::Linear => "SSB",
            ModeCategory::Morse => "CW",
            ModeCategory::Digital => "DIGI",
        }
    }

    /// Bucket a raw SatNOGS mode string (e.g. "FM", "USB", "AFSK1k2",
    /// "GMSK", "SSTV"). Anything that isn't voice or CW counts as digital.
    pub fn for_mode(mode: Option<&str>) -> ModeCategory {
        let Some(mode) = mode.map(str::to_uppercase).filter(|m| !m.is_empty()) else {
            return ModeCategory::Digital;
        };
        if mode.starts_with("FM") {
            return ModeCategory::VoiceFm;
        }
        const SSB_MARKERS: [&str; 5] = ["SSB", "USB", "LSB", "TRANSPONDER", "LINEAR"];
        if SSB_MARKERS.iter().any(|marker| mode.contains(marker)) {
            return ModeCategory::Linear;
        }
        if mode.starts_with("CW") {
            return ModeCategory::Morse;
        }
        ModeCategory::Digital
    }

    /// Bucket a whole transmitter: the mode string decides, but a
    /// transponder whose mode didn't parse as voice/CW is a linear bird
    /// (SatNOGS records some linear transponders with sparse mode fields).
    pub fn for_transmitter(transmitter: &SatTransmitter) -> ModeCategory {
        let by_mode = ModeCategory::for_mode(transmitter.mode.as_deref());
        if by_mode == ModeCategory::Digital
            && transmitter.transmitter_type.to_uppercase().contains("TRANSPONDER")
        {
            return ModeCategory::Linear;
        }
        by_mode
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn transmitter(mode: Option<&str>, ttype: &str) -> SatTransmitter {
        SatTransmitter {
            description: String::new(),
            transmitter_type: ttype.to_string(),
            alive: true,
            status: "active".to_string(),
            service: "Amateur".to_string(),
            mode: mode.map(str::to_string),
            uplink_low_hz: None,
            downlink_low_hz: None,
            uplink_high_hz: None,
            downlink_high_hz: None,
            invert: false,
            norad_id: Some(1),
        }
    }

    #[test]
    fn buckets_mode_strings_like_swift() {
        assert_eq!(ModeCategory::for_mode(Some("FM")), ModeCategory::VoiceFm);
        assert_eq!(ModeCategory::for_mode(Some("FMN")), ModeCategory::VoiceFm);
        assert_eq!(ModeCategory::for_mode(Some("USB")), ModeCategory::Linear);
        assert_eq!(ModeCategory::for_mode(Some("LSB")), ModeCategory::Linear);
        assert_eq!(ModeCategory::for_mode(Some("CW")), ModeCategory::Morse);
        assert_eq!(ModeCategory::for_mode(Some("AFSK1k2")), ModeCategory::Digital);
        assert_eq!(ModeCategory::for_mode(Some("GMSK")), ModeCategory::Digital);
        assert_eq!(ModeCategory::for_mode(Some("SSTV")), ModeCategory::Digital);
        assert_eq!(ModeCategory::for_mode(None), ModeCategory::Digital);
        assert_eq!(ModeCategory::for_mode(Some("")), ModeCategory::Digital);
    }

    #[test]
    fn sparse_mode_transponder_counts_as_linear() {
        let sparse = transmitter(Some("PSK31"), "Transponder");
        assert_eq!(ModeCategory::for_transmitter(&sparse), ModeCategory::Linear);
        let plain = transmitter(Some("PSK31"), "Transmitter");
        assert_eq!(ModeCategory::for_transmitter(&plain), ModeCategory::Digital);
        let fm = transmitter(Some("FM"), "Transponder");
        assert_eq!(ModeCategory::for_transmitter(&fm), ModeCategory::VoiceFm);
    }
}
