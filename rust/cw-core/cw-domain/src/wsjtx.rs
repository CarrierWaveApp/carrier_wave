//! WSJT-X logged-QSO data types + pure mapping helpers.
//!
//! The UDP decoder lives in `cw-net::wsjtx` (CAR-277) and the store mapping in
//! `cw-store::wsjtx_import` (CAR-280). Neither of those crates may depend on
//! the other (the store must not pull in the network stack, the network crate
//! must not pull in SQLCipher), so the plain message structs both of them need
//! — [`QsoLogged`] (type 5) and [`LoggedAdif`] (type 12) — are defined here
//! and re-exported by `cw-net` under their original paths. The mapping helpers
//! that need no store (WSJT-X mode string → store mode, Hz → kHz/band) live
//! here too so they are testable without a database.
//!
//! Greenfield (no Swift counterpart).

use chrono::{DateTime, Utc};

use crate::band::BandUtilities;

/// Type 5 QSOLogged — the structured QSO fields, in wire order.
#[derive(Debug, Clone, PartialEq)]
pub struct QsoLogged {
    pub id: String,
    pub date_time_off: Option<DateTime<Utc>>,
    pub dx_call: String,
    pub dx_grid: String,
    pub tx_frequency_hz: u64,
    pub mode: String,
    pub report_sent: String,
    pub report_received: String,
    pub tx_power: String,
    pub comments: String,
    pub name: String,
    pub date_time_on: Option<DateTime<Utc>>,
    pub operator_call: String,
    pub my_call: String,
    pub my_grid: String,
    pub exchange_sent: String,
    pub exchange_received: String,
    pub adif_propagation_mode: String,
}

/// Type 12 LoggedADIF — the QSO as a full ADIF record.
#[derive(Debug, Clone, PartialEq)]
pub struct LoggedAdif {
    pub id: String,
    /// The raw ADIF text WSJT-X logged (header + one `<eor>` record).
    pub adif: String,
}

/// WSJT-X modes that are already the code the store uses. WSJT-X labels its
/// modes with their ADIF names; the store keeps the *specific* mode (`FT4`,
/// not its ADIF parent `MFSK`) — the same thing `cw_domain::adif`'s
/// submode-wins-over-mode rule yields when the LoggedADIF path parses
/// `<mode:4>MFSK <submode:3>FT4`, so both paths land on one spelling.
/// `FT8`/`FT4`/`JT65`/`JT9` are `ModeEquivalence::DIGITAL_MODES`; the rest are
/// ADIF 3.1.7 codes in `adif_catalog::MODES`/`SUBMODE_PARENTS`.
const KNOWN_MODES: [&str; 11] = [
    "FT8", "FT4", "JT65", "JT9", "MSK144", "Q65", "FST4", "FST4W", "JT4", "WSPR", "JTTY",
];

/// Map a WSJT-X mode string to the mode the store records.
///
/// Known modes ([`KNOWN_MODES`]) map to themselves; WSJT-X's JT65 submode
/// spellings (`JT65A`..`JT65C`) fold to `JT65` (the store, like the ADIF
/// spec, keeps the submode letter out of the mode); the dual-decode label
/// `JT9+JT65` is never what WSJT-X logs but is folded to `JT65` defensively.
/// Anything else passes through trimmed + uppercased rather than being
/// dropped, so an unexpected new WSJT-X mode is still logged verbatim.
/// Returns `None` for a blank mode.
pub fn store_mode(wsjtx_mode: &str) -> Option<String> {
    let upper = wsjtx_mode.trim().to_uppercase();
    if upper.is_empty() {
        return None;
    }
    if KNOWN_MODES.contains(&upper.as_str()) {
        return Some(upper);
    }
    Some(match upper.as_str() {
        "JT65A" | "JT65B" | "JT65C" | "JT9+JT65" => "JT65".to_string(),
        "JT9-1" | "JT9-2" | "JT9-5" | "JT9-10" | "JT9-30" => "JT9".to_string(),
        _ => upper,
    })
}

/// WSJT-X `tx_frequency_hz` → the store's `freq_khz`. `0` (no rig / no CAT)
/// is "unknown", not 0 kHz.
pub fn khz_from_hz(hz: u64) -> Option<f64> {
    if hz == 0 {
        None
    } else {
        Some(hz as f64 / 1_000.0)
    }
}

/// WSJT-X `tx_frequency_hz` → amateur band via [`BandUtilities::derive_band`]
/// (`None` for 0 Hz or a frequency outside the band table).
pub fn band_from_hz(hz: u64) -> Option<&'static str> {
    BandUtilities::derive_band(khz_from_hz(hz))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::adif_catalog;
    use crate::mode::{ModeEquivalence, ModeFamily};

    #[test]
    fn mode_map_table() {
        let cases: &[(&str, Option<&str>)] = &[
            ("FT8", Some("FT8")),
            ("FT4", Some("FT4")),
            ("JT65", Some("JT65")),
            ("JT9", Some("JT9")),
            ("MSK144", Some("MSK144")),
            ("Q65", Some("Q65")),
            ("FST4", Some("FST4")),
            ("FST4W", Some("FST4W")),
            ("JT4", Some("JT4")),
            ("WSPR", Some("WSPR")),
            // WSJT-X 3.2 keyboard/contest mode, logged as plain MODE=JTTY.
            ("JTTY", Some("JTTY")),
            ("jtty", Some("JTTY")),
            // Case / whitespace normalisation.
            ("ft8", Some("FT8")),
            (" ft4 ", Some("FT4")),
            // JT65 submode letters + the dual-decode label fold to JT65.
            ("JT65A", Some("JT65")),
            ("JT65B", Some("JT65")),
            ("JT9+JT65", Some("JT65")),
            ("JT9-2", Some("JT9")),
            // Unknown modes pass through uppercased rather than vanishing.
            ("Echo", Some("ECHO")),
            ("FreqCal", Some("FREQCAL")),
            // Blank is None.
            ("", None),
            ("   ", None),
        ];
        for (input, expected) in cases {
            assert_eq!(
                store_mode(input).as_deref(),
                *expected,
                "store_mode({input:?})"
            );
        }
    }

    #[test]
    fn mapped_modes_are_known_to_the_existing_mode_tables() {
        // The four WSJT-X modes ModeEquivalence already classifies stay Digital…
        for mode in ["FT8", "FT4", "JT65", "JT9"] {
            let mapped = store_mode(mode).unwrap();
            assert_eq!(ModeEquivalence::family(&mapped), ModeFamily::Digital, "{mode}");
        }
        // …and every known WSJT-X mode is an ADIF 3.1.7 mode or submode code,
        // so the ADIF writer/validator accept what we store.
        for mode in KNOWN_MODES {
            let mapped = store_mode(mode).unwrap();
            assert!(
                adif_catalog::mode_for_code(&mapped).is_some()
                    || adif_catalog::is_submode(&mapped),
                "{mode} is not an ADIF mode/submode"
            );
        }
    }

    #[test]
    fn frequency_and_band_table() {
        let cases: &[(u64, Option<f64>, Option<&str>)] = &[
            (14_074_000, Some(14_074.0), Some("20m")),
            (14_075_245, Some(14_075.245), Some("20m")),
            (7_074_000, Some(7_074.0), Some("40m")),
            (3_573_000, Some(3_573.0), Some("80m")),
            (1_840_000, Some(1_840.0), Some("160m")),
            (10_136_000, Some(10_136.0), Some("30m")),
            (18_100_000, Some(18_100.0), Some("17m")),
            (21_074_000, Some(21_074.0), Some("15m")),
            (24_915_000, Some(24_915.0), Some("12m")),
            (28_074_000, Some(28_074.0), Some("10m")),
            (50_313_000, Some(50_313.0), Some("6m")),
            (144_174_000, Some(144_174.0), Some("2m")),
            (432_065_000, Some(432_065.0), Some("70cm")),
            // Outside the band table: kHz still known, band not.
            (222_065_000, Some(222_065.0), None),
            // No rig → unknown, not 0 kHz.
            (0, None, None),
        ];
        for (hz, khz, band) in cases {
            assert_eq!(khz_from_hz(*hz), *khz, "khz_from_hz({hz})");
            assert_eq!(band_from_hz(*hz), *band, "band_from_hz({hz})");
        }
    }
}
