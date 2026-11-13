//! Unified search across the three reference-data tables (`pota_park`,
//! `sota_summit`, `wwff_reference`) for the map's "jump to a park/summit"
//! search box. Builds a `UNION ALL` across the requested tables so ranking
//! and the `LIMIT` are enforced in SQL, not by collecting everything into
//! Rust first.

use crate::error::Result;
use crate::query::sql::escape_like;
use crate::Store;

/// One search hit, normalized across the three source tables.
#[derive(Debug, Clone, PartialEq)]
pub struct RefSearchHit {
    /// `"park"` | `"summit"` | `"wwff"`.
    pub kind: String,
    /// The reference/code, e.g. "US-1234", "W4C/CM-001", "KFF-0059".
    pub reference: String,
    pub name: String,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
}

/// Which reference table(s) to search.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RefKind {
    Park,
    Summit,
    Wwff,
}

impl RefKind {
    fn label(self) -> &'static str {
        match self {
            RefKind::Park => "park",
            RefKind::Summit => "summit",
            RefKind::Wwff => "wwff",
        }
    }

    /// `(table, reference_column, kind_label)` for building the UNION arm.
    fn table_info(self) -> (&'static str, &'static str) {
        match self {
            RefKind::Park => ("pota_park", "reference"),
            RefKind::Summit => ("sota_summit", "code"),
            RefKind::Wwff => ("wwff_reference", "reference"),
        }
    }
}

impl Store {
    /// Case-insensitive search across `name` and the reference/code column of
    /// the tables named in `kinds`. An empty `kinds` slice searches nothing
    /// and returns an empty result — the filter is explicit, not a wildcard,
    /// so a caller that forgets to populate it fails closed instead of
    /// silently scanning every table.
    ///
    /// Ranking, most to least relevant, with a deterministic tiebreak:
    /// 1. Exact match on the reference/code (case-insensitive)
    /// 2. `name` or reference/code starts with `query`
    /// 3. `name` or reference/code contains `query`
    ///
    /// Ties within the same rank sort alphabetically by reference/code.
    ///
    /// `limit` is enforced in SQL and must be ≤ [`crate::MAX_FETCH_LIMIT`].
    pub fn search_references(
        &self,
        query: &str,
        kinds: &[RefKind],
        limit: i64,
    ) -> Result<Vec<RefSearchHit>> {
        if limit > crate::MAX_FETCH_LIMIT {
            return Err(crate::StoreError::FetchLimitExceeded {
                requested: limit,
                max: crate::MAX_FETCH_LIMIT,
            });
        }
        if kinds.is_empty() {
            return Ok(Vec::new());
        }

        let needle = escape_like(query);
        let prefix_pattern = format!("{needle}%");
        let contains_pattern = format!("%{needle}%");

        let mut arms = Vec::new();
        // Four bound params per arm: exact match, then two LIKE patterns
        // (prefix, contains) each used twice (name OR reference).
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();
        for kind in kinds {
            let (table, ref_col) = kind.table_info();
            let label = kind.label();
            arms.push(format!(
                "SELECT '{label}' AS kind, {ref_col} AS reference, name, latitude, longitude, \
                        CASE \
                            WHEN cw_lower({ref_col}) = cw_lower(?) THEN 0 \
                            WHEN cw_lower(name) LIKE cw_lower(?) ESCAPE '\\' \
                                 OR cw_lower({ref_col}) LIKE cw_lower(?) ESCAPE '\\' THEN 1 \
                            ELSE 2 \
                        END AS rank_tier \
                 FROM {table} \
                 WHERE cw_lower(name) LIKE cw_lower(?) ESCAPE '\\' \
                    OR cw_lower({ref_col}) LIKE cw_lower(?) ESCAPE '\\'"
            ));
            args.push(Box::new(query.to_string()));
            args.push(Box::new(prefix_pattern.clone()));
            args.push(Box::new(prefix_pattern.clone()));
            args.push(Box::new(contains_pattern.clone()));
            args.push(Box::new(contains_pattern.clone()));
        }

        let sql = format!(
            "SELECT kind, reference, name, latitude, longitude FROM ({}) \
             ORDER BY rank_tier ASC, reference ASC LIMIT ?",
            arms.join(" UNION ALL ")
        );
        args.push(Box::new(limit));

        let mut stmt = self.conn.prepare(&sql)?;
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
        let rows = stmt.query_map(arg_refs.as_slice(), |row| {
            Ok(RefSearchHit {
                kind: row.get(0)?,
                reference: row.get(1)?,
                name: row.get(2)?,
                latitude: row.get(3)?,
                longitude: row.get(4)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pota_park::PotaPark;
    use crate::Store;
    use cw_domain::reference_csv::{SotaSummitRow, WwffReferenceRow};

    fn park(reference: &str, name: &str) -> PotaPark {
        PotaPark {
            reference: reference.to_string(),
            name: name.to_string(),
            location_desc: "US-WY".to_string(),
            latitude: Some(44.5),
            longitude: Some(-110.5),
            grid: Some("DN44".to_string()),
            entity_id: 291,
            is_active: true,
        }
    }

    fn summit(code: &str, name: &str) -> SotaSummitRow {
        SotaSummitRow {
            code: code.to_string(),
            name: name.to_string(),
            association_name: "USA - North Carolina".to_string(),
            region_name: "Western NC Mountains".to_string(),
            altitude_m: 2_037,
            altitude_ft: 6_684,
            latitude: Some(35.76),
            longitude: Some(-82.27),
            points: 10,
            bonus_points: 3,
            activation_count: 120,
            last_activation_date: None,
            last_activation_call: None,
            grid: None,
        }
    }

    fn wwff(reference: &str, name: &str) -> WwffReferenceRow {
        WwffReferenceRow {
            reference: reference.to_string(),
            name: name.to_string(),
            program: "KFF".to_string(),
            status: "active".to_string(),
            continent: Some("NA".to_string()),
            iota: None,
            grid: Some("DN44".to_string()),
            latitude: Some(44.6),
            longitude: Some(-110.5),
            iucn_category: None,
            country: Some("United States".to_string()),
            region: Some("Wyoming".to_string()),
            dxcc_entity: Some(291),
        }
    }

    #[test]
    fn empty_kinds_returns_empty() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_pota_parks(&[park("US-0001", "Yellowstone NP")]).unwrap();
        let hits = store.search_references("yellowstone", &[], 10).unwrap();
        assert!(hits.is_empty());
    }

    #[test]
    fn kind_filter_limits_which_tables_are_searched() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_pota_parks(&[park("US-0001", "Grand Teton NP")]).unwrap();
        store.replace_sota_summits(&[summit("W4C/CM-001", "Grand Peak")]).unwrap();

        let summit_only = store.search_references("grand", &[RefKind::Summit], 10).unwrap();
        assert_eq!(summit_only.len(), 1);
        assert_eq!(summit_only[0].kind, "summit");

        let both = store
            .search_references("grand", &[RefKind::Park, RefKind::Summit], 10)
            .unwrap();
        assert_eq!(both.len(), 2);
    }

    #[test]
    fn ranking_exact_beats_prefix_beats_substring_with_deterministic_tiebreak() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .replace_wwff_references(&[
                // Substring only (query appears mid-name/reference).
                wwff("KFF-0002", "Big Yellowstone Overlook"),
                // Exact reference match.
                wwff("YELLOW", "Some Unrelated Name"),
                // Prefix match on name.
                wwff("KFF-0003", "Yellowstone West Unit"),
                // Prefix match on name, alphabetically after KFF-0003 by reference.
                wwff("KFF-0004", "Yellowstone East Unit"),
            ])
            .unwrap();

        let hits = store.search_references("yellow", &[RefKind::Wwff], 10).unwrap();
        let refs: Vec<&str> = hits.iter().map(|h| h.reference.as_str()).collect();
        assert_eq!(refs, vec!["YELLOW", "KFF-0003", "KFF-0004", "KFF-0002"]);
    }

    #[test]
    fn limit_is_enforced_in_sql() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .replace_sota_summits(&[
                summit("W4C/CM-001", "Peak One"),
                summit("W4C/CM-002", "Peak Two"),
                summit("W4C/CM-003", "Peak Three"),
            ])
            .unwrap();
        let hits = store.search_references("peak", &[RefKind::Summit], 2).unwrap();
        assert_eq!(hits.len(), 2);
    }

    #[test]
    fn limit_above_max_is_rejected() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store
            .search_references("x", &[RefKind::Park], crate::MAX_FETCH_LIMIT + 1)
            .unwrap_err();
        assert!(matches!(err, crate::StoreError::FetchLimitExceeded { .. }));
    }

    #[test]
    fn like_wildcards_in_query_are_escaped() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_pota_parks(&[park("US-0001", "50% Off Park")]).unwrap();
        store.upsert_pota_parks(&[park("US-0002", "Fifty Off Park")]).unwrap();
        let hits = store.search_references("50%", &[RefKind::Park], 10).unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].reference, "US-0001");
    }
}
