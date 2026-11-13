//! Map view source rows + filter options (map port Phase A, Task 3).
//!
//! Mirrors the iOS `MapDataLoadingActor` query surface: the raw QSO rows the map
//! pins itself (`qso_map_rows`) and the filter-sheet option lists (bands/modes/
//! parks/earliest/total) it populates from (`qso_map_filter_options`). Both
//! restrict to "visible" QSOs (not hidden, not a metadata pseudo-mode) via the
//! shared `VISIBLE_QSO` fragment and, for rows, a non-empty `their_grid` — a QSO
//! without a worked-station grid has nothing to plot.

use crate::analytics::VISIBLE_QSO;
use crate::query::compile_where;
use crate::Result;
use crate::Store;
use cw_domain::mode::is_metadata_mode;
use cw_domain::query::ParsedQuery;
use rusqlite::params;

/// Display order for the band filter list. Mirrors the Swift `Band.allCases`
/// ordering used by `MapDataLoadingActor`'s filter sheet. Bands not in this list
/// sort after, alphabetically.
const BAND_ORDER: [&str; 13] = [
    "160M", "80M", "60M", "40M", "30M", "20M", "17M", "15M", "12M", "10M", "6M", "2M", "70CM",
];

/// A single mappable QSO: a visible contact with a non-empty `their_grid`.
#[derive(Debug, Clone, PartialEq)]
pub struct MapQsoRow {
    pub id: String,
    pub callsign: String,
    pub band: Option<String>,
    pub mode: Option<String>,
    /// Unix seconds, UTC.
    pub qso_date: i64,
    pub my_grid: Option<String>,
    /// Guaranteed non-empty by the `WHERE` clause.
    pub their_grid: String,
    pub park: Option<String>,
    pub state: Option<String>,
    pub dxcc: Option<i64>,
    pub qrz_confirmed: bool,
    pub lotw_confirmed: bool,
    pub power: Option<i64>,
    pub logging_session_id: Option<String>,
    pub my_rig: Option<String>,
}

/// A slim timeline QSO event row for the session-timeline window query. Unlike
/// [`MapQsoRow`] (whose `their_grid` is contractually non-empty because the QSO
/// map has nothing to pin without one), timeline events legitimately lack a
/// grid — they still appear on the timeline, just without a resolved
/// coordinate. Hence `their_grid: Option<String>` and no non-empty filter.
#[derive(Debug, Clone, PartialEq)]
pub struct TimelineQsoRow {
    pub id: String,
    pub callsign: String,
    pub band: Option<String>,
    pub mode: Option<String>,
    /// Unix seconds, UTC.
    pub qso_date: i64,
    pub their_grid: Option<String>,
}

/// Filter-sheet option lists + headline counts, over ALL visible QSOs
/// (unfiltered — the map's filter sheet always shows every available option,
/// not just those matching the current filter).
#[derive(Debug, Clone, PartialEq)]
pub struct MapFilterOptions {
    /// Display order (`BAND_ORDER`); EVENT/UNKNOWN excluded; unknown bands last,
    /// alphabetically.
    pub bands: Vec<String>,
    /// Sorted ascending; metadata pseudo-modes excluded.
    pub modes: Vec<String>,
    /// Sorted ascending.
    pub parks: Vec<String>,
    pub earliest: Option<i64>,
    /// All visible QSOs, unfiltered.
    pub total: i64,
}

impl Store {
    /// Visible QSOs with a non-empty `their_grid`, matching `query`, newest
    /// first. `confirmed_only` additionally restricts to QRZ- or LoTW-confirmed
    /// rows. `limit` caps the result count (no cap when `None`).
    pub fn qso_map_rows(
        &self,
        query: &ParsedQuery,
        confirmed_only: bool,
        limit: Option<i64>,
    ) -> Result<Vec<MapQsoRow>> {
        let (where_sql, values) = compile_where(query);
        let mut sql = format!(
            "SELECT id, callsign, band, mode, qso_date, my_grid, their_grid, park, state, \
             dxcc, qrz_confirmed, lotw_confirmed, power, logging_session_id, my_rig \
             FROM qso WHERE {VISIBLE_QSO} \
             AND their_grid IS NOT NULL AND their_grid != '' \
             AND ({where_sql})"
        );
        if confirmed_only {
            sql.push_str(" AND (qrz_confirmed = 1 OR lotw_confirmed = 1)");
        }
        sql.push_str(" ORDER BY qso_date DESC");
        if limit.is_some() {
            sql.push_str(" LIMIT ?");
        }

        let mut bound: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        if let Some(limit) = limit {
            bound.push(Box::new(limit));
        }
        let refs: Vec<&dyn rusqlite::types::ToSql> = bound.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| {
            Ok(MapQsoRow {
                id: row.get(0)?,
                callsign: row.get(1)?,
                band: row.get(2)?,
                mode: row.get(3)?,
                qso_date: row.get(4)?,
                my_grid: row.get(5)?,
                their_grid: row.get(6)?,
                park: row.get(7)?,
                state: row.get(8)?,
                dxcc: row.get(9)?,
                qrz_confirmed: row.get(10)?,
                lotw_confirmed: row.get(11)?,
                power: row.get(12)?,
                logging_session_id: row.get(13)?,
                my_rig: row.get(14)?,
            })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Mappable QSOs of one logging session, oldest first. Reuses [`MapQsoRow`]
    /// (so its non-empty `their_grid` WHERE clause still applies — gridless
    /// session QSOs have nothing to pin, matching iOS `mappableQSOs`). Ordered
    /// ascending by `qso_date` — the session map draws pins in log order.
    pub fn session_map_rows(&self, session_id: &str) -> Result<Vec<MapQsoRow>> {
        let sql = format!(
            "SELECT id, callsign, band, mode, qso_date, my_grid, their_grid, park, state, \
             dxcc, qrz_confirmed, lotw_confirmed, power, logging_session_id, my_rig \
             FROM qso WHERE {VISIBLE_QSO} \
             AND their_grid IS NOT NULL AND their_grid != '' \
             AND logging_session_id = ? \
             ORDER BY qso_date ASC"
        );
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map([session_id], |row| {
            Ok(MapQsoRow {
                id: row.get(0)?,
                callsign: row.get(1)?,
                band: row.get(2)?,
                mode: row.get(3)?,
                qso_date: row.get(4)?,
                my_grid: row.get(5)?,
                their_grid: row.get(6)?,
                park: row.get(7)?,
                state: row.get(8)?,
                dxcc: row.get(9)?,
                qrz_confirmed: row.get(10)?,
                lotw_confirmed: row.get(11)?,
                power: row.get(12)?,
                logging_session_id: row.get(13)?,
                my_rig: row.get(14)?,
            })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Visible QSOs whose `qso_date` falls in `[start, end]`, oldest first,
    /// capped at `limit`. This is a **window** query across ALL QSOs — it is
    /// deliberately NOT session-scoped, faithful to iOS
    /// `TimelineMapDataActor.fetchQSOEvents` (which fetches every QSO in the
    /// session's time window, not only its own logged contacts). Unlike the map
    /// row query, it does not require a `their_grid` — timeline events without a
    /// grid still appear (just off-map).
    pub fn timeline_window_qsos(&self, start: i64, end: i64, limit: i64) -> Result<Vec<TimelineQsoRow>> {
        let sql = format!(
            "SELECT id, callsign, band, mode, qso_date, their_grid \
             FROM qso WHERE {VISIBLE_QSO} \
             AND qso_date >= ? AND qso_date <= ? \
             ORDER BY qso_date ASC LIMIT ?"
        );
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(params![start, end, limit], |row| {
            Ok(TimelineQsoRow {
                id: row.get(0)?,
                callsign: row.get(1)?,
                band: row.get(2)?,
                mode: row.get(3)?,
                qso_date: row.get(4)?,
                their_grid: row.get(5)?,
            })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Filter-sheet option lists + headline counts over ALL visible QSOs
    /// (unfiltered by any DSL query — the map's filter sheet always offers every
    /// available band/mode/park, not just those matching the current filter).
    pub fn qso_map_filter_options(&self) -> Result<MapFilterOptions> {
        let mut bands: Vec<String> = self
            .conn
            .prepare(&format!(
                "SELECT DISTINCT UPPER(band) FROM qso WHERE {VISIBLE_QSO} AND band IS NOT NULL"
            ))?
            .query_map([], |row| row.get::<_, String>(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?
            .into_iter()
            .filter(|b| b != "EVENT" && b != "UNKNOWN")
            .collect();
        bands.sort_by(|a, b| {
            let rank = |band: &str| BAND_ORDER.iter().position(|&x| x == band).unwrap_or(usize::MAX);
            rank(a).cmp(&rank(b)).then_with(|| a.cmp(b))
        });

        let mut modes: Vec<String> = self
            .conn
            .prepare(&format!(
                "SELECT DISTINCT UPPER(mode) FROM qso WHERE {VISIBLE_QSO} AND mode IS NOT NULL"
            ))?
            .query_map([], |row| row.get::<_, String>(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?
            .into_iter()
            .filter(|m| !is_metadata_mode(m))
            .collect();
        modes.sort();

        let mut parks: Vec<String> = self
            .conn
            .prepare(&format!(
                "SELECT DISTINCT park FROM qso WHERE {VISIBLE_QSO} AND park IS NOT NULL"
            ))?
            .query_map([], |row| row.get::<_, String>(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        parks.sort();

        let (earliest, total): (Option<i64>, i64) = self.conn.query_row(
            &format!("SELECT MIN(qso_date), COUNT(*) FROM qso WHERE {VISIBLE_QSO}"),
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )?;

        Ok(MapFilterOptions {
            bands,
            modes,
            parks,
            earliest,
            total,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::qso::Qso;
    use crate::Store;

    fn base_qso(id: &str) -> Qso {
        Qso {
            id: id.to_string(),
            callsign: "W1AW".to_string(),
            band: Some("20m".to_string()),
            mode: Some("FT8".to_string()),
            freq_khz: Some(14_074.0),
            qso_date: 1_700_000_000,
            my_grid: Some("FN31".to_string()),
            their_grid: Some("EM12".to_string()),
            rst_sent: None,
            rst_rcvd: None,
            my_callsign: Some("W6JY".to_string()),
            park: None,
            their_park: None,
            notes: None,
            notes_user_authored: false,
            spot_comments_data: None,
            callsign_change_note: None,
            original_callsign: None,
            import_source_raw_value: "logger".to_string(),
            imported_at: 1_700_000_000,
            modified_at: None,
            raw_adif: None,
            name: None,
            qth: None,
            state: None,
            country: None,
            power: None,
            my_rig: None,
            station_profile_name: None,
            sota_ref: None,
            wwff_ref: None,
            aoa_code: None,
            qrz_log_id: None,
            qrz_confirmed: false,
            lotw_confirmed_date: None,
            lotw_confirmed: false,
            dxcc: Some(291),
            their_license_class: None,
            contest_name: None,
            contest_serial_sent: None,
            contest_serial_received: None,
            contest_exchange_sent: None,
            contest_exchange_received: None,
            is_hidden: false,
            is_activity_log_qso: false,
            station_callsign: None,
            logging_session_id: None,
            dirty: true,
            sat_name: None,
            prop_mode: None,
        }
    }

    fn parse(query: &str) -> ParsedQuery {
        cw_domain::query::parse(query).unwrap()
    }

    #[test]
    fn map_rows_require_their_grid_and_sort_desc() {
        let store = Store::open_in_memory("k").unwrap();
        // No their_grid — excluded regardless of visibility.
        let mut no_grid = base_qso("no-grid");
        no_grid.their_grid = None;
        no_grid.qso_date = 1_700_000_000;
        store.upsert_qso(&no_grid).unwrap();
        // Two with grids, different dates.
        let mut older = base_qso("older");
        older.their_grid = Some("EM12".to_string());
        older.qso_date = 1_700_100_000;
        store.upsert_qso(&older).unwrap();
        let mut newer = base_qso("newer");
        newer.their_grid = Some("DM79".to_string());
        newer.qso_date = 1_700_200_000;
        store.upsert_qso(&newer).unwrap();

        let rows = store.qso_map_rows(&parse(""), false, None).unwrap();
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].id, "newer");
        assert_eq!(rows[0].their_grid, "DM79");
        assert_eq!(rows[1].id, "older");
        assert_eq!(rows[1].their_grid, "EM12");
        assert!(rows.iter().all(|r| !r.their_grid.is_empty()));
    }

    #[test]
    fn map_rows_confirmed_only_filters() {
        let store = Store::open_in_memory("k").unwrap();
        let mut confirmed = base_qso("confirmed");
        confirmed.lotw_confirmed = true;
        store.upsert_qso(&confirmed).unwrap();
        let mut unconfirmed = base_qso("unconfirmed");
        unconfirmed.their_grid = Some("DM79".to_string());
        store.upsert_qso(&unconfirmed).unwrap();

        let all = store.qso_map_rows(&parse(""), false, None).unwrap();
        assert_eq!(all.len(), 2);

        let confirmed_only = store.qso_map_rows(&parse(""), true, None).unwrap();
        assert_eq!(confirmed_only.len(), 1);
        assert_eq!(confirmed_only[0].id, "confirmed");
    }

    #[test]
    fn map_rows_respect_query_and_limit() {
        let store = Store::open_in_memory("k").unwrap();
        let mut twenty_a = base_qso("20m-a");
        twenty_a.band = Some("20m".to_string());
        twenty_a.qso_date = 1_700_000_000;
        store.upsert_qso(&twenty_a).unwrap();
        let mut twenty_b = base_qso("20m-b");
        twenty_b.band = Some("20m".to_string());
        twenty_b.their_grid = Some("DM79".to_string());
        twenty_b.qso_date = 1_700_100_000;
        store.upsert_qso(&twenty_b).unwrap();
        let mut forty = base_qso("40m-a");
        forty.band = Some("40m".to_string());
        forty.their_grid = Some("CN87".to_string());
        forty.qso_date = 1_700_200_000;
        store.upsert_qso(&forty).unwrap();

        let twenty_only = store.qso_map_rows(&parse("band:20m"), false, None).unwrap();
        assert_eq!(twenty_only.len(), 2);
        assert!(twenty_only.iter().all(|r| r.band.as_deref() == Some("20m")));

        let limited = store.qso_map_rows(&parse(""), false, Some(1)).unwrap();
        assert_eq!(limited.len(), 1);
        assert_eq!(limited[0].id, "40m-a"); // newest first
    }

    #[test]
    fn filter_options_ordering_and_exclusions() {
        let store = Store::open_in_memory("k").unwrap();
        let mut forty = base_qso("forty");
        forty.band = Some("40M".to_string());
        forty.mode = Some("CW".to_string());
        forty.qso_date = 1_700_000_000;
        store.upsert_qso(&forty).unwrap();
        let mut twenty = base_qso("twenty");
        twenty.band = Some("20M".to_string());
        twenty.mode = Some("SSB".to_string());
        twenty.their_grid = Some("DM79".to_string());
        twenty.park = Some("US-0001".to_string());
        twenty.qso_date = 1_700_100_000;
        store.upsert_qso(&twenty).unwrap();
        let mut event = base_qso("event");
        event.band = Some("EVENT".to_string());
        event.mode = None;
        event.their_grid = Some("CN87".to_string());
        event.qso_date = 1_699_900_000;
        store.upsert_qso(&event).unwrap();
        // Hidden and metadata rows must not contribute to the filter options.
        let mut hidden = base_qso("hidden");
        hidden.is_hidden = true;
        hidden.band = Some("15M".to_string());
        store.upsert_qso(&hidden).unwrap();
        let mut meta = base_qso("meta");
        meta.mode = Some("WEATHER".to_string());
        meta.band = Some("10M".to_string());
        store.upsert_qso(&meta).unwrap();

        let options = store.qso_map_filter_options().unwrap();
        assert_eq!(options.bands, vec!["40M".to_string(), "20M".to_string()]);
        assert_eq!(options.modes, vec!["CW".to_string(), "SSB".to_string()]);
        assert_eq!(options.parks, vec!["US-0001".to_string()]);
        assert_eq!(options.earliest, Some(1_699_900_000));
        assert_eq!(options.total, 3); // forty, twenty, event (not hidden/meta)
    }
}
