//! The ActivityLog entity + its bounded query API.
//! Mirrors CarrierWaveData/Models/ActivityLog.swift.

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

/// A logging session (activation / contest / casual operation).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ActivityLog {
    pub id: String,
    pub name: String,
    pub my_callsign: String,
    /// Unix seconds, UTC.
    pub created_at: i64,
    /// FK to a station profile (stored as UUID string).
    pub station_profile_id: Option<String>,
    pub current_grid: Option<String>,
    pub location_label: Option<String>,
    pub is_active: bool,
    /// Whether this row has un-synced local changes (sync journal flag).
    pub cloud_dirty_flag: bool,
}

/// DDL for the `activity_log` table and its supporting indexes.
pub(crate) const ACTIVITY_LOG_DDL: &str = r#"
    CREATE TABLE IF NOT EXISTS activity_log (
        id                  TEXT PRIMARY KEY NOT NULL,
        name                TEXT NOT NULL,
        my_callsign         TEXT NOT NULL,
        created_at          INTEGER NOT NULL,
        station_profile_id  TEXT,
        current_grid        TEXT,
        location_label      TEXT,
        is_active           INTEGER NOT NULL DEFAULT 1,
        cloud_dirty_flag    INTEGER NOT NULL DEFAULT 0
    );

    CREATE INDEX IF NOT EXISTS idx_al_my_callsign      ON activity_log(my_callsign);
    CREATE INDEX IF NOT EXISTS idx_al_is_active        ON activity_log(is_active);
    CREATE INDEX IF NOT EXISTS idx_al_created_at       ON activity_log(created_at);
    CREATE INDEX IF NOT EXISTS idx_al_cloud_dirty_flag ON activity_log(cloud_dirty_flag);
"#;

/// Bounded query parameters for `activity_log`.
#[derive(Debug, Clone, Default)]
pub struct ActivityLogFilter {
    pub my_callsign: Option<String>,
    /// When `Some(true)`, only active logs; `Some(false)` only inactive.
    pub is_active: Option<bool>,
    /// When `true`, restrict to rows with `cloud_dirty_flag` set — the outbound
    /// sync pass's "records with un-synced local changes" set.
    pub dirty_only: bool,
}

impl Store {
    /// Insert or replace an `ActivityLog` record.
    pub fn upsert_activity_log(&self, log: &ActivityLog) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO activity_log (
                id, name, my_callsign, created_at, station_profile_id,
                current_grid, location_label, is_active, cloud_dirty_flag
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
            ON CONFLICT(id) DO UPDATE SET
                name=excluded.name,
                my_callsign=excluded.my_callsign,
                created_at=excluded.created_at,
                station_profile_id=excluded.station_profile_id,
                current_grid=excluded.current_grid,
                location_label=excluded.location_label,
                is_active=excluded.is_active,
                cloud_dirty_flag=excluded.cloud_dirty_flag
            "#,
            params![
                log.id,
                log.name,
                log.my_callsign,
                log.created_at,
                log.station_profile_id,
                log.current_grid,
                log.location_label,
                log.is_active as i64,
                log.cloud_dirty_flag as i64,
            ],
        )?;
        Ok(())
    }

    /// Total count of `activity_log` rows.
    pub fn activity_log_count(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM activity_log", [], |row| row.get(0))?)
    }

    /// Fetch a single `ActivityLog` by `id`, or `None` if absent.
    /// Delete an `activity_log` row by id. Idempotent — a missing id succeeds.
    pub fn delete_activity_log(&self, id: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM activity_log WHERE id = ?1", params![id])?;
        Ok(())
    }

    pub fn fetch_activity_log(&self, id: &str) -> Result<Option<ActivityLog>> {
        let sql = "SELECT id, name, my_callsign, created_at, station_profile_id, \
            current_grid, location_label, is_active, cloud_dirty_flag \
            FROM activity_log WHERE id = ?";
        Ok(self
            .conn
            .query_row(sql, params![id], Self::row_to_activity_log)
            .optional()?)
    }

    /// Bounded, paginated fetch with optional filters.
    /// `limit` must be ≤ [`MAX_FETCH_LIMIT`].
    pub fn fetch_activity_logs(
        &self,
        filter: &ActivityLogFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<ActivityLog>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded {
                requested: limit,
                max: MAX_FETCH_LIMIT,
            });
        }

        let mut sql = String::from(
            "SELECT id, name, my_callsign, created_at, station_profile_id, \
            current_grid, location_label, is_active, cloud_dirty_flag \
            FROM activity_log WHERE 1=1",
        );
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

        if let Some(callsign) = &filter.my_callsign {
            sql.push_str(" AND my_callsign = ?");
            args.push(Box::new(callsign.clone()));
        }
        if let Some(active) = filter.is_active {
            sql.push_str(" AND is_active = ?");
            args.push(Box::new(active as i64));
        }
        if filter.dirty_only {
            sql.push_str(" AND cloud_dirty_flag = 1");
        }
        sql.push_str(" ORDER BY created_at DESC LIMIT ? OFFSET ?");
        args.push(Box::new(limit));
        args.push(Box::new(offset));

        let mut stmt = self.conn.prepare(&sql)?;
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
        let rows = stmt.query_map(arg_refs.as_slice(), Self::row_to_activity_log)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    fn row_to_activity_log(row: &rusqlite::Row<'_>) -> rusqlite::Result<ActivityLog> {
        Ok(ActivityLog {
            id: row.get(0)?,
            name: row.get(1)?,
            my_callsign: row.get(2)?,
            created_at: row.get(3)?,
            station_profile_id: row.get(4)?,
            current_grid: row.get(5)?,
            location_label: row.get(6)?,
            is_active: row.get::<_, i64>(7)? != 0,
            cloud_dirty_flag: row.get::<_, i64>(8)? != 0,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample(id: &str, callsign: &str, when: i64, active: bool) -> ActivityLog {
        ActivityLog {
            id: id.to_string(),
            name: format!("Log {id}"),
            my_callsign: callsign.to_string(),
            created_at: when,
            station_profile_id: None,
            current_grid: Some("DM04".to_string()),
            location_label: Some("Summit".to_string()),
            is_active: active,
            cloud_dirty_flag: false,
        }
    }

    #[test]
    fn upsert_count_and_fetch() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_activity_log(&sample("l1", "W6JY", 1000, true))
            .unwrap();
        store
            .upsert_activity_log(&sample("l2", "W6JY", 2000, false))
            .unwrap();
        store
            .upsert_activity_log(&sample("l3", "K2ABC", 3000, true))
            .unwrap();
        assert_eq!(store.activity_log_count().unwrap(), 3);

        let log = store.fetch_activity_log("l1").unwrap().unwrap();
        assert_eq!(log.my_callsign, "W6JY");
        assert!(log.is_active);
    }

    #[test]
    fn fetch_by_callsign() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_activity_log(&sample("l1", "W6JY", 1000, true))
            .unwrap();
        store
            .upsert_activity_log(&sample("l2", "W6JY", 2000, false))
            .unwrap();
        store
            .upsert_activity_log(&sample("l3", "K2ABC", 3000, true))
            .unwrap();

        let filter = ActivityLogFilter {
            my_callsign: Some("W6JY".into()),
            is_active: None,
            dirty_only: false,
        };
        let rows = store.fetch_activity_logs(&filter, 100, 0).unwrap();
        assert_eq!(rows.len(), 2);
        // Newest first.
        assert_eq!(rows[0].id, "l2");
    }

    #[test]
    fn fetch_active_only() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_activity_log(&sample("l1", "W6JY", 1000, true))
            .unwrap();
        store
            .upsert_activity_log(&sample("l2", "W6JY", 2000, false))
            .unwrap();
        store
            .upsert_activity_log(&sample("l3", "K2ABC", 3000, true))
            .unwrap();

        let filter = ActivityLogFilter {
            is_active: Some(true),
            ..Default::default()
        };
        let rows = store.fetch_activity_logs(&filter, 100, 0).unwrap();
        assert_eq!(rows.len(), 2);
        assert!(rows.iter().all(|r| r.is_active));
    }

    #[test]
    fn upsert_replaces() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_activity_log(&sample("l1", "W6JY", 1000, true))
            .unwrap();
        let mut updated = sample("l1", "W6JY", 1000, false);
        updated.location_label = Some("Valley".into());
        updated.cloud_dirty_flag = true;
        store.upsert_activity_log(&updated).unwrap();
        assert_eq!(store.activity_log_count().unwrap(), 1);
        let log = store.fetch_activity_log("l1").unwrap().unwrap();
        assert!(!log.is_active);
        assert_eq!(log.location_label.as_deref(), Some("Valley"));
        assert!(log.cloud_dirty_flag);
    }

    #[test]
    fn dirty_only_restricts_to_dirty_rows() {
        let store = Store::open_in_memory("k").unwrap();
        let clean = sample("l1", "W6JY", 1000, true); // cloud_dirty_flag = false
        let mut dirty = sample("l2", "W6JY", 2000, true);
        dirty.cloud_dirty_flag = true;
        store.upsert_activity_log(&clean).unwrap();
        store.upsert_activity_log(&dirty).unwrap();

        let filter = ActivityLogFilter { dirty_only: true, ..Default::default() };
        let rows = store.fetch_activity_logs(&filter, 100, 0).unwrap();
        assert_eq!(rows.iter().map(|l| l.id.clone()).collect::<Vec<_>>(), vec!["l2"]);
    }

    #[test]
    fn missing_id_returns_none() {
        let store = Store::open_in_memory("k").unwrap();
        assert!(store.fetch_activity_log("no-such-id").unwrap().is_none());
    }

    #[test]
    fn fetch_limit_enforced() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store
            .fetch_activity_logs(&ActivityLogFilter::default(), MAX_FETCH_LIMIT + 1, 0)
            .unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }
}
