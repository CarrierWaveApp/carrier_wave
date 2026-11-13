use thiserror::Error;

#[derive(Debug, Error)]
pub enum StoreError {
    #[error("database error: {0}")]
    Sqlite(#[from] rusqlite::Error),

    #[error("fetch limit {requested} exceeds maximum {max}")]
    FetchLimitExceeded { requested: i64, max: i64 },

    #[error("invalid migration state: db at version {found}, code supports {supported}")]
    MigrationMismatch { found: i64, supported: i64 },

    #[error("unknown sync entity type: {entity_type}")]
    UnknownSyncEntity { entity_type: String },
}

pub type Result<T> = std::result::Result<T, StoreError>;
