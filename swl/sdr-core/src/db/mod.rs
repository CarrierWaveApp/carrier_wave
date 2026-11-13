pub mod models;
pub mod queries;

use crate::error::DbError;
use rusqlite::Connection;

const MIGRATIONS: &[&str] = &[MIGRATION_001, MIGRATION_002, MIGRATION_003];

const MIGRATION_003: &str = r#"
CREATE TABLE IF NOT EXISTS uploaded_recordings (
    id TEXT PRIMARY KEY,
    original_filename TEXT NOT NULL,
    original_format TEXT NOT NULL,
    sample_rate INTEGER,
    duration_secs REAL,
    status TEXT NOT NULL DEFAULT 'processing',
    error_message TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

-- Recreate transcriptions with recording_id nullable (uploads have no server recording)
ALTER TABLE transcriptions RENAME TO transcriptions_old;

CREATE TABLE transcriptions (
    id TEXT PRIMARY KEY,
    recording_id TEXT,
    text TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'in_progress',
    wpm_estimate REAL,
    char_count INTEGER NOT NULL DEFAULT 0,
    error_message TEXT,
    started_at TEXT NOT NULL,
    completed_at TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    structured_transcript TEXT,
    progress REAL DEFAULT 0.0,
    uploaded_recording_id TEXT REFERENCES uploaded_recordings(id),
    FOREIGN KEY (recording_id) REFERENCES recordings(id) ON DELETE CASCADE
);

INSERT INTO transcriptions (id, recording_id, text, status, wpm_estimate, char_count, error_message, started_at, completed_at, created_at)
    SELECT id, recording_id, text, status, wpm_estimate, char_count, error_message, started_at, completed_at, created_at
    FROM transcriptions_old;

DROP TABLE transcriptions_old;

CREATE INDEX IF NOT EXISTS idx_transcriptions_recording ON transcriptions(recording_id);
CREATE INDEX IF NOT EXISTS idx_transcriptions_status ON transcriptions(status);
"#;

const MIGRATION_002: &str = r#"
CREATE TABLE IF NOT EXISTS transcriptions (
    id TEXT PRIMARY KEY,
    recording_id TEXT NOT NULL,
    text TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'in_progress',
    wpm_estimate REAL,
    char_count INTEGER NOT NULL DEFAULT 0,
    error_message TEXT,
    started_at TEXT NOT NULL,
    completed_at TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    FOREIGN KEY (recording_id) REFERENCES recordings(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_transcriptions_recording ON transcriptions(recording_id);
CREATE INDEX IF NOT EXISTS idx_transcriptions_status ON transcriptions(status);
"#;

const MIGRATION_001: &str = r#"
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS sdrs (
    id TEXT PRIMARY KEY,
    driver TEXT NOT NULL,
    label TEXT,
    serial TEXT,
    url TEXT,
    sample_rate INTEGER,
    antenna TEXT,
    last_seen TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS captures (
    id TEXT PRIMARY KEY,
    sdr_id TEXT NOT NULL REFERENCES sdrs(id),
    center_frequency INTEGER NOT NULL,
    bandwidth INTEGER NOT NULL,
    sample_rate INTEGER NOT NULL,
    consumer_count INTEGER NOT NULL DEFAULT 0,
    started_at TEXT NOT NULL,
    stopped_at TEXT,
    FOREIGN KEY (sdr_id) REFERENCES sdrs(id)
);

CREATE TABLE IF NOT EXISTS recordings (
    id TEXT PRIMARY KEY,
    capture_id TEXT REFERENCES captures(id),
    sdr_id TEXT NOT NULL,
    frequency INTEGER NOT NULL,
    bandwidth INTEGER NOT NULL,
    mode TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    started_at TEXT NOT NULL,
    stopped_at TEXT,
    retention_days INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS segments (
    id TEXT PRIMARY KEY,
    recording_id TEXT NOT NULL REFERENCES recordings(id),
    segment_number INTEGER NOT NULL,
    file_path TEXT NOT NULL,
    duration_secs REAL NOT NULL,
    file_size_bytes INTEGER NOT NULL,
    sample_rate INTEGER NOT NULL,
    started_at TEXT NOT NULL,
    ended_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    UNIQUE(recording_id, segment_number)
);

CREATE INDEX IF NOT EXISTS idx_recordings_sdr ON recordings(sdr_id);
CREATE INDEX IF NOT EXISTS idx_recordings_status ON recordings(status);
CREATE INDEX IF NOT EXISTS idx_segments_recording ON segments(recording_id);
"#;

/// Database handle wrapping a SQLite connection.
pub struct Database {
    conn: Connection,
}

impl Database {
    /// Open (or create) the database at the given path and run migrations.
    pub fn open(path: &str) -> Result<Self, DbError> {
        let conn = Connection::open(path)?;
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")?;
        let db = Self { conn };
        db.migrate()?;
        Ok(db)
    }

    /// Create an in-memory database (for testing).
    pub fn open_in_memory() -> Result<Self, DbError> {
        let conn = Connection::open_in_memory()?;
        conn.execute_batch("PRAGMA foreign_keys=ON;")?;
        let db = Self { conn };
        db.migrate()?;
        Ok(db)
    }

    /// Run all pending migrations.
    fn migrate(&self) -> Result<(), DbError> {
        let current = self.schema_version();
        for (i, migration) in MIGRATIONS.iter().enumerate() {
            let version = (i + 1) as i64;
            if version > current {
                self.conn
                    .execute_batch(migration)
                    .map_err(|e| DbError::MigrationFailed(format!("v{version}: {e}")))?;
                self.conn.execute(
                    "INSERT OR REPLACE INTO schema_version (version) VALUES (?1)",
                    [version],
                )?;
            }
        }
        Ok(())
    }

    fn schema_version(&self) -> i64 {
        self.conn
            .query_row(
                "SELECT COALESCE(MAX(version), 0) FROM schema_version",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0)
    }

    /// Borrow the underlying connection (for queries module).
    pub fn conn(&self) -> &Connection {
        &self.conn
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn open_in_memory_and_migrate() {
        let db = Database::open_in_memory().unwrap();
        assert_eq!(db.schema_version(), 3);
    }

    #[test]
    fn migration_is_idempotent() {
        let db = Database::open_in_memory().unwrap();
        db.migrate().unwrap();
        db.migrate().unwrap();
        assert_eq!(db.schema_version(), 3);
    }
}
