//! ADIF-file import policy shared by every host (CAR-216 lineage).
//!
//! Port of the non-UI half of the iOS `ImportService.importADIF(content:
//! source:myCallsign:)` (`swift/ios/CarrierWave/Services/ImportService.swift`):
//! the multi-operator record filter and the "which QSOs do I already have"
//! identity scan the importer compares each parsed record against. The
//! record→`Qso` mapping itself is [`crate::qso_from_adif_record`] (already a
//! port of `ImportService.createQSO`); the orchestration — parse, filter, map,
//! dedup, insert in one transaction, report — lives in `cw-ffi::adif_api`
//! so Swift and Kotlin get one importer.
//!
//! # Dedup identity
//!
//! A record is a duplicate when its [`deduplication_key`] (`CALL|BAND|MODE|
//! 2-minute bucket`, `cw_domain::dedup`) is already present in the store or
//! earlier in the same file. That is exactly what iOS does: it builds
//! `Set<QSO.deduplicationKey>` over every stored QSO (`fetchExistingDeduplicationKeys`,
//! hidden rows included) and skips a record whose key is in the set, adding
//! each imported record's key as it goes. [`Store::deduplication_keys`] is
//! that set, built from a four-column scan instead of hydrating every row.

use std::collections::HashSet;

use cw_domain::adif::AdifRecord;
use cw_domain::dedup::deduplication_key;

use crate::error::Result;
use crate::Store;

/// `import_source_raw_value` stamped on QSOs imported from an ADIF file —
/// the raw value of the Swift `ImportSource.adifFile` case.
pub const ADIF_FILE_IMPORT_SOURCE: &str = "adifFile";

/// Strip a short portable suffix (`/P`, `/M`, `/4`, `/QRP`-length and
/// shorter) from an uppercased callsign for operator matching. Port of
/// `ImportService.stripPortableSuffix`: only the text after the *last* slash
/// is considered, and only when it is at most two characters, so a prefix
/// like `VP2E/W1AW` and a long suffix like `W1AW/QRP` are left intact.
pub fn strip_portable_suffix(callsign: &str) -> &str {
    match callsign.rfind('/') {
        Some(idx) if callsign.len() - idx - 1 <= 2 => &callsign[..idx],
        _ => callsign,
    }
}

/// Multi-operator filter — port of `ImportService.filterForMultiOp`.
///
/// If any record carries an `OPERATOR` or `STATION_CALLSIGN` that (uppercased,
/// portable suffix stripped) differs from `my_callsign`, the file is a
/// multi-op log: keep only the records whose operator *or* station callsign
/// matches, plus records that carry neither field. Otherwise every record is
/// kept unchanged. Returns references in file order.
pub fn filter_for_multi_op<'a>(records: &'a [AdifRecord], my_callsign: &str) -> Vec<&'a AdifRecord> {
    let mine = my_callsign.trim().to_uppercase();
    let normalized_my = strip_portable_suffix(&mine).to_string();
    let norm = |call: Option<&String>| -> Option<String> {
        call.map(|c| strip_portable_suffix(&c.to_uppercase()).to_string())
    };

    let has_multi_op = records.iter().any(|r| {
        let op = norm(r.operator_call.as_ref());
        let st = norm(r.station_callsign.as_ref());
        op.as_deref().is_some_and(|c| c != normalized_my)
            || st.as_deref().is_some_and(|c| c != normalized_my)
    });
    if !has_multi_op {
        return records.iter().collect();
    }

    records
        .iter()
        .filter(|r| {
            let op = norm(r.operator_call.as_ref());
            let st = norm(r.station_callsign.as_ref());
            op.as_deref() == Some(normalized_my.as_str())
                || st.as_deref() == Some(normalized_my.as_str())
                || (op.is_none() && st.is_none())
        })
        .collect()
}

impl Store {
    /// Every stored QSO's [`deduplication_key`], hidden (soft-deleted) rows
    /// included — the `fetchExistingDeduplicationKeys()` set the iOS importer
    /// skips against. Unbounded by design (the key set must be complete to be
    /// useful), but reads only the four key columns, so 100k QSOs is a few MB.
    pub fn deduplication_keys(&self) -> Result<HashSet<String>> {
        let mut stmt = self
            .conn
            .prepare("SELECT callsign, band, mode, qso_date FROM qso")?;
        let rows = stmt.query_map([], |row| {
            let callsign: String = row.get(0)?;
            let band: Option<String> = row.get(1)?;
            let mode: Option<String> = row.get(2)?;
            let qso_date: i64 = row.get(3)?;
            Ok(deduplication_key(
                &callsign,
                band.as_deref().unwrap_or(""),
                mode.as_deref().unwrap_or(""),
                qso_date,
            ))
        })?;
        let mut keys = HashSet::new();
        for key in rows {
            keys.insert(key?);
        }
        Ok(keys)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tests::sample_qso;

    fn record(operator: Option<&str>, station: Option<&str>) -> AdifRecord {
        AdifRecord {
            callsign: "K1JT".to_string(),
            band: "20m".to_string(),
            mode: "FT8".to_string(),
            frequency: None,
            qso_date: Some("20260115".to_string()),
            time_on: Some("1430".to_string()),
            rst_sent: None,
            rst_received: None,
            my_callsign: None,
            my_gridsquare: None,
            gridsquare: None,
            sig_info: None,
            my_sig_info: None,
            my_wwff_ref: None,
            wwff_ref: None,
            comment: None,
            dxcc: None,
            country: None,
            state: None,
            name: None,
            qth: None,
            raw_adif: String::new(),
            operator_call: operator.map(str::to_string),
            station_callsign: station.map(str::to_string),
            sat_name: None,
            prop_mode: None,
        }
    }

    #[test]
    fn strip_portable_suffix_matches_swift() {
        assert_eq!(strip_portable_suffix("W1AW/P"), "W1AW");
        assert_eq!(strip_portable_suffix("W1AW/4"), "W1AW");
        assert_eq!(strip_portable_suffix("W1AW/MM"), "W1AW");
        // Three-character suffixes are kept (Swift: `suffix.count <= 2`).
        assert_eq!(strip_portable_suffix("W1AW/QRP"), "W1AW/QRP");
        // Prefix form: the text after the last slash is the whole callsign.
        assert_eq!(strip_portable_suffix("VP2E/W1AW"), "VP2E/W1AW");
        assert_eq!(strip_portable_suffix("W1AW"), "W1AW");
        assert_eq!(strip_portable_suffix("W1AW/"), "W1AW");
    }

    #[test]
    fn single_op_file_passes_through_unchanged() {
        let records = vec![record(None, None), record(Some("w6jy"), None), record(None, Some("W6JY/P"))];
        let kept = filter_for_multi_op(&records, "W6JY");
        assert_eq!(kept.len(), 3);
    }

    #[test]
    fn multi_op_file_keeps_mine_and_unattributed() {
        let records = vec![
            record(Some("W6JY"), None),      // mine (operator)
            record(Some("N0CALL"), None),    // another op — dropped
            record(None, Some("W6JY/P")),    // mine (station, portable)
            record(None, None),              // unattributed — kept
            record(Some("N0CALL"), Some("W6JY")), // station matches — kept
            record(Some("N0CALL"), Some("K1ABC")), // neither — dropped
        ];
        let kept = filter_for_multi_op(&records, "w6jy");
        assert_eq!(kept.len(), 4);
        assert!(kept.iter().all(|r| {
            r.operator_call.as_deref() != Some("N0CALL") || r.station_callsign.as_deref() == Some("W6JY")
        }));
    }

    #[test]
    fn deduplication_keys_cover_every_row_including_hidden() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_qso(&sample_qso("a", "K1JT", "20m", 1_700_000_050)).unwrap();
        let mut hidden = sample_qso("b", "W1AW", "40m", 1_700_000_200);
        hidden.is_hidden = true;
        store.upsert_qso(&hidden).unwrap();
        let mut bandless = sample_qso("c", "N0CALL", "20m", 1_700_000_300);
        bandless.band = None;
        store.upsert_qso(&bandless).unwrap();

        let keys = store.deduplication_keys().unwrap();
        assert_eq!(keys.len(), 3);
        assert!(keys.contains(&deduplication_key("K1JT", "20m", "FT8", 1_700_000_050)));
        assert!(keys.contains(&deduplication_key("W1AW", "40m", "FT8", 1_700_000_200)));
        assert!(keys.contains(&deduplication_key("N0CALL", "", "FT8", 1_700_000_300)));
    }

    #[test]
    fn deduplication_keys_empty_store() {
        let store = Store::open_in_memory("k").unwrap();
        assert!(store.deduplication_keys().unwrap().is_empty());
    }
}
