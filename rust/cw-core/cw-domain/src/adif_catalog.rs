//! ADIF 3.1.7 catalog: band codes, mode codes, submode→parent map.
//! Port of `ADIFCatalog.swift` + `ADIFCatalog+Submodes.swift`.
//!
//! Scope: just the data the validator (`adif_validator`) needs — bands with
//! min/max MHz, recognized mode codes, submode parent mapping. The Swift
//! catalog also enumerates US states + Canadian provinces for the
//! `Primary_Administrative_Subdivision` field; that's not yet a validator
//! input on either side, so it's deferred.

use std::collections::HashMap;
use std::sync::OnceLock;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ModeCategory {
    Phone,
    Cw,
    Digital,
    Image,
}

#[derive(Debug, Clone)]
pub struct AdifMode {
    pub code: &'static str,
    pub category: ModeCategory,
    pub description: &'static str,
}

#[derive(Debug, Clone)]
pub struct AdifBand {
    pub code: &'static str,
    pub description: &'static str,
    pub min_mhz: f64,
    pub max_mhz: f64,
}

/// ADIF 3.1.7 modes. List mirrors the Swift catalog (~80 modes).
pub const MODES: &[AdifMode] = &[
    // Phone
    AdifMode { code: "SSB", category: ModeCategory::Phone, description: "Single Sideband" },
    AdifMode { code: "USB", category: ModeCategory::Phone, description: "Upper Sideband" },
    AdifMode { code: "LSB", category: ModeCategory::Phone, description: "Lower Sideband" },
    AdifMode { code: "AM", category: ModeCategory::Phone, description: "Amplitude Modulation" },
    AdifMode { code: "FM", category: ModeCategory::Phone, description: "Frequency Modulation" },
    AdifMode { code: "DIGITALVOICE", category: ModeCategory::Phone, description: "Digital Voice" },
    AdifMode { code: "DMR", category: ModeCategory::Phone, description: "Digital Mobile Radio" },
    AdifMode { code: "C4FM", category: ModeCategory::Phone, description: "Yaesu System Fusion" },
    AdifMode { code: "DSTAR", category: ModeCategory::Phone, description: "D-STAR" },
    // CW
    AdifMode { code: "CW", category: ModeCategory::Cw, description: "Morse code" },
    AdifMode { code: "PCW", category: ModeCategory::Cw, description: "Packet CW" },
    // Digital — FSK family
    AdifMode { code: "FT8", category: ModeCategory::Digital, description: "Franke-Taylor 8-FSK, 15 s" },
    AdifMode { code: "FT4", category: ModeCategory::Digital, description: "Franke-Taylor 4-FSK, 7.5 s" },
    AdifMode { code: "JT65", category: ModeCategory::Digital, description: "Joe Taylor, 60 s, weak-signal" },
    AdifMode { code: "JT9", category: ModeCategory::Digital, description: "Joe Taylor, 60 s LF/MF" },
    AdifMode { code: "JT4", category: ModeCategory::Digital, description: "Joe Taylor, EME/tropo" },
    AdifMode { code: "JT6M", category: ModeCategory::Digital, description: "Meteor scatter, 6 m" },
    AdifMode { code: "JT44", category: ModeCategory::Digital, description: "Weak-signal QRP" },
    AdifMode { code: "MSK144", category: ModeCategory::Digital, description: "Meteor scatter" },
    AdifMode { code: "FSK441", category: ModeCategory::Digital, description: "High-speed meteor scatter" },
    AdifMode { code: "Q65", category: ModeCategory::Digital, description: "EME / ionospheric scatter" },
    AdifMode { code: "QRA64", category: ModeCategory::Digital, description: "EME Q-ary Repeat Accumulate" },
    AdifMode { code: "WSPR", category: ModeCategory::Digital, description: "Weak Signal Propagation Reporter" },
    AdifMode { code: "MFSK", category: ModeCategory::Digital, description: "Multi-FSK" },
    AdifMode { code: "JS8", category: ModeCategory::Digital, description: "JS8Call (keyboard-to-keyboard MFSK)" },
    // Not an ADIF 3.1.7 code yet: WSJT-X 3.2 logs its new keyboard/contest
    // mode as plain `<MODE:4>JTTY`, so accept and emit it the same way.
    AdifMode { code: "JTTY", category: ModeCategory::Digital, description: "WSJT-X JTTY (keyboard/contest 4-GFSK)" },
    AdifMode { code: "OLIVIA", category: ModeCategory::Digital, description: "MFSK-based chat mode" },
    AdifMode { code: "CONTESTI", category: ModeCategory::Digital, description: "Contestia chat mode" },
    AdifMode { code: "DOMINO", category: ModeCategory::Digital, description: "DominoEX" },
    AdifMode { code: "THOR", category: ModeCategory::Digital, description: "MFSK with IFK+" },
    AdifMode { code: "THRB", category: ModeCategory::Digital, description: "Throb" },
    AdifMode { code: "MT63", category: ModeCategory::Digital, description: "Wide-band chat mode" },
    AdifMode { code: "OPERA", category: ModeCategory::Digital, description: "Weak-signal beacon" },
    AdifMode { code: "ROS", category: ModeCategory::Digital, description: "Spread-spectrum" },
    AdifMode { code: "CLO", category: ModeCategory::Digital, description: "CLOVER" },
    AdifMode { code: "CHIP", category: ModeCategory::Digital, description: "Chip64/Chip128" },
    AdifMode { code: "ISCAT", category: ModeCategory::Digital, description: "Ionospheric Scatter" },
    // Digital — PSK family
    AdifMode { code: "PSK", category: ModeCategory::Digital, description: "Phase Shift Keying" },
    AdifMode { code: "PSK31", category: ModeCategory::Digital, description: "PSK at 31.25 baud" },
    AdifMode { code: "PSK63", category: ModeCategory::Digital, description: "PSK at 62.5 baud" },
    AdifMode { code: "PSK125", category: ModeCategory::Digital, description: "PSK at 125 baud" },
    AdifMode { code: "PSK250", category: ModeCategory::Digital, description: "PSK at 250 baud" },
    AdifMode { code: "QPSK31", category: ModeCategory::Digital, description: "Quadrature PSK at 31.25 baud" },
    // Digital — RTTY
    AdifMode { code: "RTTY", category: ModeCategory::Digital, description: "Radioteletype" },
    AdifMode { code: "RTTYM", category: ModeCategory::Digital, description: "MFSK RTTY" },
    // Digital — link protocols
    AdifMode { code: "ARDOP", category: ModeCategory::Digital, description: "Amateur Radio Digital Open Protocol" },
    AdifMode { code: "WINMOR", category: ModeCategory::Digital, description: "Winlink OFDM" },
    AdifMode { code: "PACTOR", category: ModeCategory::Digital, description: "PACTOR (TOR)" },
    AdifMode { code: "PACKET", category: ModeCategory::Digital, description: "AX.25 packet" },
    AdifMode { code: "PAX", category: ModeCategory::Digital, description: "PAX / PAX2" },
    AdifMode { code: "PAC", category: ModeCategory::Digital, description: "PACTOR (legacy code)" },
    AdifMode { code: "VARA", category: ModeCategory::Digital, description: "VARA HF" },
    AdifMode { code: "VARAFM", category: ModeCategory::Digital, description: "VARA FM" },
    AdifMode { code: "VARAC", category: ModeCategory::Digital, description: "VARA-C" },
    AdifMode { code: "HELL", category: ModeCategory::Digital, description: "Hellschreiber" },
    // Digital — Dynamic / OFDM (ADIF 3.1.7)
    AdifMode { code: "DYNAMIC", category: ModeCategory::Digital, description: "Dynamic protocol" },
    AdifMode { code: "OFDM", category: ModeCategory::Digital, description: "Orthogonal FDM" },
    // Image
    AdifMode { code: "SSTV", category: ModeCategory::Image, description: "Slow-Scan TV" },
    AdifMode { code: "ATV", category: ModeCategory::Image, description: "Amateur TV" },
    AdifMode { code: "FAX", category: ModeCategory::Image, description: "Facsimile" },
];

/// ADIF 3.1.7 bands, low → high frequency.
pub const BANDS: &[AdifBand] = &[
    AdifBand { code: "2190m", description: "136 kHz", min_mhz: 0.1357, max_mhz: 0.1378 },
    AdifBand { code: "630m", description: "472 kHz", min_mhz: 0.472, max_mhz: 0.479 },
    AdifBand { code: "560m", description: "501 kHz (experimental)", min_mhz: 0.501, max_mhz: 0.504 },
    AdifBand { code: "160m", description: "1.8 MHz", min_mhz: 1.8, max_mhz: 2.0 },
    AdifBand { code: "80m", description: "3.5 MHz", min_mhz: 3.5, max_mhz: 4.0 },
    AdifBand { code: "60m", description: "5 MHz (channelized)", min_mhz: 5.06, max_mhz: 5.45 },
    AdifBand { code: "40m", description: "7 MHz", min_mhz: 7.0, max_mhz: 7.3 },
    AdifBand { code: "30m", description: "10 MHz (WARC)", min_mhz: 10.1, max_mhz: 10.15 },
    AdifBand { code: "20m", description: "14 MHz", min_mhz: 14.0, max_mhz: 14.35 },
    AdifBand { code: "17m", description: "18 MHz (WARC)", min_mhz: 18.068, max_mhz: 18.168 },
    AdifBand { code: "15m", description: "21 MHz", min_mhz: 21.0, max_mhz: 21.45 },
    AdifBand { code: "12m", description: "24 MHz (WARC)", min_mhz: 24.89, max_mhz: 24.99 },
    AdifBand { code: "10m", description: "28 MHz", min_mhz: 28.0, max_mhz: 29.7 },
    AdifBand { code: "8m", description: "40 MHz", min_mhz: 40.0, max_mhz: 45.0 },
    AdifBand { code: "6m", description: "50 MHz", min_mhz: 50.0, max_mhz: 54.0 },
    AdifBand { code: "5m", description: "54 MHz", min_mhz: 54.0, max_mhz: 69.9 },
    AdifBand { code: "4m", description: "70 MHz (Region 1)", min_mhz: 70.0, max_mhz: 71.0 },
    AdifBand { code: "2m", description: "144 MHz", min_mhz: 144.0, max_mhz: 148.0 },
    AdifBand { code: "1.25m", description: "222 MHz", min_mhz: 222.0, max_mhz: 225.0 },
    AdifBand { code: "70cm", description: "430 MHz", min_mhz: 420.0, max_mhz: 450.0 },
    AdifBand { code: "33cm", description: "902 MHz", min_mhz: 902.0, max_mhz: 928.0 },
    AdifBand { code: "23cm", description: "1.2 GHz", min_mhz: 1_240.0, max_mhz: 1_300.0 },
    AdifBand { code: "13cm", description: "2.3 GHz", min_mhz: 2_300.0, max_mhz: 2_450.0 },
    AdifBand { code: "9cm", description: "3.4 GHz", min_mhz: 3_300.0, max_mhz: 3_500.0 },
    AdifBand { code: "6cm", description: "5.7 GHz", min_mhz: 5_650.0, max_mhz: 5_925.0 },
    AdifBand { code: "3cm", description: "10 GHz", min_mhz: 10_000.0, max_mhz: 10_500.0 },
    AdifBand { code: "1.25cm", description: "24 GHz", min_mhz: 24_000.0, max_mhz: 24_250.0 },
    AdifBand { code: "6mm", description: "47 GHz", min_mhz: 47_000.0, max_mhz: 47_200.0 },
    AdifBand { code: "4mm", description: "76 GHz", min_mhz: 75_500.0, max_mhz: 81_000.0 },
    AdifBand { code: "2.5mm", description: "120 GHz", min_mhz: 119_980.0, max_mhz: 123_000.0 },
    AdifBand { code: "2mm", description: "134 GHz", min_mhz: 134_000.0, max_mhz: 149_000.0 },
    AdifBand { code: "1mm", description: "241 GHz", min_mhz: 241_000.0, max_mhz: 250_000.0 },
    AdifBand { code: "submm", description: "Submillimeter", min_mhz: 300_000.0, max_mhz: 7_500_000.0 },
];

/// ADIF 3.1.7 submode → required parent mode mapping.
pub const SUBMODE_PARENTS: &[(&str, &str)] = &[
    ("LSB", "SSB"), ("USB", "SSB"),
    ("PCW", "CW"),
    ("ASCI", "RTTY"),
    // MFSK family
    ("FT4", "MFSK"), ("FSQCALL", "MFSK"), ("FST4", "MFSK"), ("FST4W", "MFSK"),
    ("JS8", "MFSK"), ("JTMS", "MFSK"), ("Q65", "MFSK"),
    ("MFSK4", "MFSK"), ("MFSK8", "MFSK"), ("MFSK11", "MFSK"), ("MFSK16", "MFSK"),
    ("MFSK22", "MFSK"), ("MFSK31", "MFSK"), ("MFSK32", "MFSK"), ("MFSK64", "MFSK"),
    ("MFSK64L", "MFSK"), ("MFSK128", "MFSK"), ("MFSK128L", "MFSK"),
    // PSK family
    ("PSK31", "PSK"), ("PSK63", "PSK"), ("PSK63F", "PSK"),
    ("PSK125", "PSK"), ("PSK250", "PSK"), ("PSK500", "PSK"), ("PSK1000", "PSK"),
    ("QPSK31", "PSK"), ("QPSK63", "PSK"), ("QPSK125", "PSK"), ("QPSK250", "PSK"),
    ("QPSK500", "PSK"),
    ("SIM31", "PSK"), ("PSK10", "PSK"),
    // JT65 family
    ("JT65A", "JT65"), ("JT65B", "JT65"), ("JT65B2", "JT65"),
    ("JT65C", "JT65"), ("JT65C2", "JT65"),
    // JT9 family
    ("JT9-1", "JT9"), ("JT9-2", "JT9"), ("JT9-5", "JT9"), ("JT9-10", "JT9"),
    ("JT9-30", "JT9"), ("JT9A", "JT9"), ("JT9B", "JT9"), ("JT9C", "JT9"),
    ("JT9D", "JT9"), ("JT9E", "JT9"), ("JT9E FAST", "JT9"),
    ("JT9F", "JT9"), ("JT9F FAST", "JT9"), ("JT9G", "JT9"), ("JT9G FAST", "JT9"),
    ("JT9H", "JT9"), ("JT9H FAST", "JT9"),
    // OLIVIA family
    ("OLIVIA 4/125", "OLIVIA"), ("OLIVIA 4/250", "OLIVIA"),
    ("OLIVIA 8/250", "OLIVIA"), ("OLIVIA 8/500", "OLIVIA"),
    ("OLIVIA 16/500", "OLIVIA"), ("OLIVIA 16/1000", "OLIVIA"),
    ("OLIVIA 32/1000", "OLIVIA"),
    // DIGITALVOICE family
    ("C4FM", "DIGITALVOICE"), ("DMR", "DIGITALVOICE"), ("DSTAR", "DIGITALVOICE"),
    ("FREEDV", "DIGITALVOICE"), ("M17", "DIGITALVOICE"),
    // HELL family
    ("FMHELL", "HELL"), ("FSKHELL", "HELL"), ("HELL80", "HELL"),
    ("HELLX5", "HELL"), ("HELLX9", "HELL"), ("HFSK", "HELL"),
    ("PSKHELL", "HELL"), ("SLOWHELL", "HELL"),
    // DYNAMIC family (ADIF 3.1.7)
    ("FREEDATA", "DYNAMIC"), ("VARA FM", "DYNAMIC"),
    ("VARA HF", "DYNAMIC"), ("VARA SAT", "DYNAMIC"),
    // OFDM family (ADIF 3.1.7)
    ("RIBBIT_PIX", "OFDM"), ("RIBBIT_SMS", "OFDM"),
];

fn modes_by_code() -> &'static HashMap<String, &'static AdifMode> {
    static MAP: OnceLock<HashMap<String, &'static AdifMode>> = OnceLock::new();
    MAP.get_or_init(|| {
        MODES.iter().map(|m| (m.code.to_uppercase(), m)).collect()
    })
}

fn bands_by_code() -> &'static HashMap<String, &'static AdifBand> {
    static MAP: OnceLock<HashMap<String, &'static AdifBand>> = OnceLock::new();
    MAP.get_or_init(|| {
        BANDS.iter().map(|b| (b.code.to_lowercase(), b)).collect()
    })
}

fn submode_parents_map() -> &'static HashMap<String, &'static str> {
    static MAP: OnceLock<HashMap<String, &'static str>> = OnceLock::new();
    MAP.get_or_init(|| SUBMODE_PARENTS.iter().map(|(k, v)| (k.to_uppercase(), *v)).collect())
}

pub fn mode_for_code(code: &str) -> Option<&'static AdifMode> {
    modes_by_code().get(&code.trim().to_uppercase()).copied()
}

pub fn band_for_code(code: &str) -> Option<&'static AdifBand> {
    bands_by_code().get(&code.trim().to_lowercase()).copied()
}

pub fn parent_mode_for_submode(submode: &str) -> Option<&'static str> {
    submode_parents_map()
        .get(&submode.trim().to_uppercase())
        .copied()
}

pub fn is_submode(code: &str) -> bool {
    parent_mode_for_submode(code).is_some()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mode_lookup_is_case_insensitive_and_trimmed() {
        assert!(mode_for_code("FT8").is_some());
        assert!(mode_for_code("ft8").is_some());
        assert!(mode_for_code("  FT8  ").is_some());
        assert!(mode_for_code("NOPE").is_none());
    }

    #[test]
    fn band_lookup_is_case_insensitive_and_trimmed() {
        let band = band_for_code("20M").unwrap();
        assert_eq!(band.code, "20m");
        assert!((band.min_mhz - 14.0).abs() < 1e-9);
        assert!((band.max_mhz - 14.35).abs() < 1e-9);
        assert!(band_for_code("not-a-band").is_none());
    }

    #[test]
    fn submode_parent_lookups() {
        assert_eq!(parent_mode_for_submode("USB"), Some("SSB"));
        assert_eq!(parent_mode_for_submode("ft4"), Some("MFSK"));
        assert_eq!(parent_mode_for_submode("OLIVIA 8/250"), Some("OLIVIA"));
        assert_eq!(parent_mode_for_submode("BOGUS"), None);
    }

    #[test]
    fn is_submode_helper() {
        assert!(is_submode("USB"));
        assert!(is_submode("JT9A"));
        assert!(!is_submode("CQ"));
    }

    #[test]
    fn catalogs_round_trip_a_known_qso_setup() {
        // 20m + FT8 + Frequency in 14.0–14.35 MHz should all resolve.
        let band = band_for_code("20m").unwrap();
        let mode = mode_for_code("FT8").unwrap();
        let freq = 14.074;
        assert!(freq >= band.min_mhz && freq <= band.max_mhz);
        assert_eq!(mode.category, ModeCategory::Digital);
    }
}
