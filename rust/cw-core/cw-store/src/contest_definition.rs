//! Contest-definition cache — the portable replacement for the iOS
//! `ContestDefinitionsStore` (Application Support JSON files).
//!
//! Rows mirror the `GET /v1/contests/:id` envelope: summary metadata columns
//! for list rendering plus the full v0.3 contest body cached verbatim in
//! `definition_json` (`cw_domain::contest` owns parsing). Reference data,
//! not a synced entity.

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::{params, OptionalExtension};

/// One cached contest definition.
#[derive(Debug, Clone, PartialEq)]
pub struct ContestDefinitionRow {
    /// Contest id (e.g. `cwops-cwt`). Primary key.
    pub id: String,
    pub name: String,
    pub short_name: Option<String>,
    pub sponsor_name: Option<String>,
    pub sponsor_url: Option<String>,
    pub format_version: String,
    pub is_active: bool,
    /// Unix seconds, UTC. Server-side `updatedAt` of the definition.
    pub updated_at: i64,
    /// The raw v0.3 contest body, verbatim from the server.
    pub definition_json: String,
    /// Unix seconds, UTC. When this row was last refreshed from the server.
    pub last_synced_at: i64,
}

impl ContestDefinitionRow {
    /// Display short name if set, otherwise full name.
    pub fn display_name(&self) -> &str {
        self.short_name.as_deref().unwrap_or(&self.name)
    }
}

/// DDL for `contest_definition`. Registered by the migration runner.
pub(crate) const CONTEST_DEFINITION_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS contest_definition (
    id               TEXT    PRIMARY KEY NOT NULL,
    name             TEXT    NOT NULL,
    short_name       TEXT,
    sponsor_name     TEXT,
    sponsor_url      TEXT,
    format_version   TEXT    NOT NULL,
    is_active        INTEGER NOT NULL DEFAULT 1,
    updated_at       INTEGER NOT NULL,   -- unix seconds, UTC
    definition_json  TEXT    NOT NULL,
    last_synced_at   INTEGER NOT NULL    -- unix seconds, UTC
);

CREATE INDEX IF NOT EXISTS idx_contest_definition_name ON contest_definition(name);
"#;

impl Store {
    /// Insert or replace a `contest_definition` row.
    pub fn upsert_contest_definition(&self, row: &ContestDefinitionRow) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO contest_definition (
                id, name, short_name, sponsor_name, sponsor_url, format_version,
                is_active, updated_at, definition_json, last_synced_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
            ON CONFLICT(id) DO UPDATE SET
                name            = excluded.name,
                short_name      = excluded.short_name,
                sponsor_name    = excluded.sponsor_name,
                sponsor_url     = excluded.sponsor_url,
                format_version  = excluded.format_version,
                is_active       = excluded.is_active,
                updated_at      = excluded.updated_at,
                definition_json = excluded.definition_json,
                last_synced_at  = excluded.last_synced_at
            "#,
            params![
                row.id,
                row.name,
                row.short_name,
                row.sponsor_name,
                row.sponsor_url,
                row.format_version,
                row.is_active as i64,
                row.updated_at,
                row.definition_json,
                row.last_synced_at,
            ],
        )?;
        Ok(())
    }

    /// Total cached definition count.
    pub fn contest_definition_count(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM contest_definition", [], |row| row.get(0))?)
    }

    /// Bounded fetch ordered by name. `limit` must be ≤ [`MAX_FETCH_LIMIT`].
    pub fn fetch_contest_definitions(
        &self,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<ContestDefinitionRow>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }
        let mut stmt = self.conn.prepare(
            "SELECT id, name, short_name, sponsor_name, sponsor_url, format_version, \
                    is_active, updated_at, definition_json, last_synced_at \
             FROM contest_definition ORDER BY name ASC LIMIT ?1 OFFSET ?2",
        )?;
        let rows = stmt.query_map(params![limit, offset], Self::row_to_contest_definition)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Fetch a single definition by contest id. Returns `None` if not cached.
    pub fn fetch_contest_definition(&self, id: &str) -> Result<Option<ContestDefinitionRow>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, name, short_name, sponsor_name, sponsor_url, format_version, \
                    is_active, updated_at, definition_json, last_synced_at \
             FROM contest_definition WHERE id = ?1",
        )?;
        Ok(stmt
            .query_row(params![id], Self::row_to_contest_definition)
            .optional()?)
    }

    /// Delete every definition whose id is **not** in `keep_ids` — reconciling
    /// the cache to the authoritative server list after a full refresh. An
    /// empty `keep_ids` clears the cache.
    pub fn retain_contest_definitions(&self, keep_ids: &[String]) -> Result<()> {
        if keep_ids.is_empty() {
            self.conn.execute("DELETE FROM contest_definition", [])?;
            return Ok(());
        }
        let placeholders = vec!["?"; keep_ids.len()].join(",");
        let args: Vec<&dyn rusqlite::types::ToSql> =
            keep_ids.iter().map(|id| id as &dyn rusqlite::types::ToSql).collect();
        self.conn.execute(
            &format!("DELETE FROM contest_definition WHERE id NOT IN ({placeholders})"),
            args.as_slice(),
        )?;
        Ok(())
    }

    fn row_to_contest_definition(row: &rusqlite::Row<'_>) -> rusqlite::Result<ContestDefinitionRow> {
        Ok(ContestDefinitionRow {
            id: row.get(0)?,
            name: row.get(1)?,
            short_name: row.get(2)?,
            sponsor_name: row.get(3)?,
            sponsor_url: row.get(4)?,
            format_version: row.get(5)?,
            is_active: row.get::<_, i64>(6)? != 0,
            updated_at: row.get(7)?,
            definition_json: row.get(8)?,
            last_synced_at: row.get(9)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(id: &str, name: &str) -> ContestDefinitionRow {
        ContestDefinitionRow {
            id: id.to_string(),
            name: name.to_string(),
            short_name: Some("SST".to_string()),
            sponsor_name: Some("K1USN".to_string()),
            sponsor_url: None,
            format_version: "0.3.0".to_string(),
            is_active: true,
            updated_at: 1_700_000_000,
            definition_json: r#"{"id":"x"}"#.to_string(),
            last_synced_at: 1_700_000_100,
        }
    }

    #[test]
    fn upsert_and_fetch_roundtrip() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_contest_definition(&sample("k1usn-sst", "Slow Speed Test")).unwrap();

        let row = store.fetch_contest_definition("k1usn-sst").unwrap().expect("row");
        assert_eq!(row.display_name(), "SST");
        assert_eq!(row.definition_json, r#"{"id":"x"}"#);
        assert!(row.is_active);
        assert_eq!(store.contest_definition_count().unwrap(), 1);
    }

    #[test]
    fn upsert_replaces() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_contest_definition(&sample("c", "Old")).unwrap();
        let mut updated = sample("c", "New");
        updated.definition_json = r#"{"id":"new"}"#.to_string();
        store.upsert_contest_definition(&updated).unwrap();

        assert_eq!(store.contest_definition_count().unwrap(), 1);
        let row = store.fetch_contest_definition("c").unwrap().unwrap();
        assert_eq!(row.name, "New");
        assert_eq!(row.definition_json, r#"{"id":"new"}"#);
    }

    #[test]
    fn fetch_orders_by_name_and_enforces_limit() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_contest_definition(&sample("b", "Zeta")).unwrap();
        store.upsert_contest_definition(&sample("a", "Alpha")).unwrap();

        let rows = store.fetch_contest_definitions(10, 0).unwrap();
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].name, "Alpha");

        let err = store.fetch_contest_definitions(MAX_FETCH_LIMIT + 1, 0).unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }

    #[test]
    fn retain_reconciles_deletes() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_contest_definition(&sample("keep", "Keep")).unwrap();
        store.upsert_contest_definition(&sample("drop", "Drop")).unwrap();

        store.retain_contest_definitions(&["keep".to_string()]).unwrap();
        assert!(store.fetch_contest_definition("keep").unwrap().is_some());
        assert!(store.fetch_contest_definition("drop").unwrap().is_none());

        store.retain_contest_definitions(&[]).unwrap();
        assert_eq!(store.contest_definition_count().unwrap(), 0);
    }
}
