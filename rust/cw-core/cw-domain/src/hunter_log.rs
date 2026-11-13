//! Hunter-log pure helpers shared by Swift + Kotlin.
//!
//! These back the "hunter" / chaser workflow's dedup badges and FT8 QSO
//! enrichment, ported from the iOS app's `WorkedBeforeCache` /
//! `ActivityLogManager+FT8QSOLogger`:
//!
//! - [`band_mode_park_key`] — the composite worked-before dedup key
//!   (`"<band>|<MODE-FAMILY>|<PARK>"`); a contact is a *dupe* when today's
//!   worked set for that callsign already contains this key. Port of
//!   `WorkedBeforeCache.bandModeParkKey` + `WorkedBeforeResult.isDupe`.
//! - [`derive_dxcc`] — synchronous DXCC entity + country derivation from a
//!   callsign prefix, with a Maidenhead-grid nearest-neighbour fallback. Port of
//!   the `LocationPrefixLookup.entity(forCallsign:) ?? nearest(grid:)` head of
//!   `ActivityLogManager.logFT8QSO`.
//!
//! Callsign normalization for the lookup path lives next to its algorithm in
//! [`crate::quick_entry::extract_primary`].

use crate::location_prefix;
use crate::mode::{ModeEquivalence, ModeFamily};

/// Composite worked-before key `"<band>|<MODE-FAMILY>|<PARK>"`. The mode is
/// collapsed to its family (`PHONE`/`CW`/`DIGITAL`/`OTHER`) and the park is
/// upper-cased + trimmed; different parks never collide, so they are never dupes
/// of each other. Faithful port of `WorkedBeforeCache.bandModeParkKey`.
pub fn band_mode_park_key(band: &str, mode: &str, park: Option<&str>) -> String {
    let family_key = match ModeEquivalence::family(mode) {
        ModeFamily::Phone => "PHONE",
        ModeFamily::Cw => "CW",
        ModeFamily::Digital => "DIGITAL",
        ModeFamily::Other => "OTHER",
    };
    let park_key = park.map(|p| p.trim().to_uppercase()).unwrap_or_default();
    format!("{band}|{family_key}|{park_key}")
}

/// One worked-before key per *credited* park. A multi-park `their_park` (a POTA
/// n-fer, e.g. `"US-1044, US-3791"`) explodes into one [`band_mode_park_key`]
/// per park so each park deduplicates independently; single-park and no-park
/// QSOs return exactly one key identical to `band_mode_park_key`, so their
/// behavior is unchanged. This is what a logged QSO contributes to today's
/// worked set, whereas a single-park spot row still looks itself up with the
/// scalar `band_mode_park_key`.
pub fn band_mode_park_keys(band: &str, mode: &str, park: Option<&str>) -> Vec<String> {
    match park {
        Some(park_ref) if crate::park_reference::is_multi_park(park_ref) => {
            crate::park_reference::split(park_ref)
                .iter()
                .map(|one| band_mode_park_key(band, mode, Some(one)))
                .collect()
        }
        other => vec![band_mode_park_key(band, mode, other)],
    }
}

/// DXCC entity derived from a callsign (or a fallback grid). `dxcc_id` is the
/// DXCC entity number; `name` doubles as the QSO `country`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DxccDerivation {
    pub dxcc_id: u32,
    pub name: String,
    pub prefix: String,
}

/// Derive the DXCC entity for a contact: try the callsign prefix first, then
/// fall back to the nearest entity for `grid` if the prefix is unknown. Returns
/// `None` when neither resolves. Port of the synchronous head of
/// `ActivityLogManager.logFT8QSO` (`entity(forCallsign:) ?? nearest(grid:)`).
pub fn derive_dxcc(callsign: &str, grid: Option<&str>) -> Option<DxccDerivation> {
    let entity = location_prefix::entity_for_callsign(callsign)
        .or_else(|| grid.and_then(location_prefix::nearest_for_grid))?;
    Some(DxccDerivation {
        dxcc_id: entity.id,
        name: entity.name.to_string(),
        prefix: entity.prefix.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::quick_entry::extract_primary;

    #[test]
    fn band_mode_park_key_collapses_mode_family_and_normalizes_park() {
        assert_eq!(band_mode_park_key("20m", "USB", None), "20m|PHONE|");
        assert_eq!(band_mode_park_key("40m", "CW", None), "40m|CW|");
        assert_eq!(band_mode_park_key("20m", "FT8", None), "20m|DIGITAL|");
        // Park is upper-cased + trimmed; different parks => different keys.
        assert_eq!(band_mode_park_key("20m", "cw", Some(" us-1234 ")), "20m|CW|US-1234");
        assert_ne!(
            band_mode_park_key("20m", "CW", Some("US-1")),
            band_mode_park_key("20m", "CW", Some("US-2"))
        );
    }

    #[test]
    fn band_mode_park_keys_explodes_multi_park() {
        // A 2-fer yields one scalar key per park (order preserved from split).
        assert_eq!(
            band_mode_park_keys("20m", "CW", Some("US-1044, US-3791")),
            vec![
                band_mode_park_key("20m", "CW", Some("US-1044")),
                band_mode_park_key("20m", "CW", Some("US-3791")),
            ]
        );
        // Single park => exactly one key, identical to the scalar helper.
        assert_eq!(
            band_mode_park_keys("20m", "CW", Some("US-1044")),
            vec![band_mode_park_key("20m", "CW", Some("US-1044"))]
        );
        // No park => one empty-park key, unchanged from today.
        assert_eq!(
            band_mode_park_keys("40m", "SSB", None),
            vec![band_mode_park_key("40m", "SSB", None)]
        );
    }

    #[test]
    fn dupe_is_membership_in_todays_keys() {
        // Mirrors WorkedBeforeResult.isDupe: contains() over today's keys.
        let today = [band_mode_park_key("20m", "CW", None)];
        assert!(today.contains(&band_mode_park_key("20m", "CW", None))); // same contact => dupe
        assert!(!today.contains(&band_mode_park_key("40m", "CW", None))); // different band
        assert!(!today.contains(&band_mode_park_key("20m", "SSB", None))); // different mode family
    }

    #[test]
    fn derive_dxcc_prefers_callsign_then_grid() {
        // The table keys US on the representative prefix "K" (one prefix per
        // entity, matching LocationPrefixLookup), so a K-call resolves directly.
        let us = derive_dxcc("K1ABC", None).unwrap();
        assert_eq!(us.dxcc_id, 291);
        assert_eq!(us.name, "United States");

        // A prefix the table doesn't key (e.g. a W-call) falls back to the grid's
        // nearest entity.
        let by_grid = derive_dxcc("123", Some("FN31"));
        assert!(by_grid.is_some());

        // Neither resolves.
        assert!(derive_dxcc("123", None).is_none());
    }

    #[test]
    fn extract_primary_matches_swift_contract() {
        assert_eq!(extract_primary("I/W6JSV/P"), "W6JSV");
        assert_eq!(extract_primary("VE3/W6JSV"), "W6JSV");
        assert_eq!(extract_primary("W6JSV/P"), "W6JSV");
        assert_eq!(extract_primary("W6JSV"), "W6JSV"); // no slash, unchanged
        assert_eq!(extract_primary("W6JSV/"), "W6JSV/"); // single segment, original returned
    }
}
