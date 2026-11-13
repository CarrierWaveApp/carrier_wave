# Challenges Server Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a self-hostable Rust/Axum HTTP API server for ham radio challenge tracking with PostgreSQL storage.

**Architecture:** Stateless HTTP server with PostgreSQL backend. Device token authentication tied to callsigns. Leaderboards via polling with efficient ranking queries. Admin API for challenge management.

**Tech Stack:** Rust, Axum 0.7, sqlx 0.8, PostgreSQL 16, tokio, serde

---

## Task 1: Database Migrations

**Files:**
- Create: `migrations/001_initial_schema.sql`

**Step 1: Write the initial schema migration**

```sql
-- migrations/001_initial_schema.sql

-- Challenge definitions
CREATE TABLE challenges (
    id              UUID PRIMARY KEY,
    version         INT NOT NULL DEFAULT 1,
    name            TEXT NOT NULL,
    description     TEXT NOT NULL,
    author          TEXT,
    category        TEXT NOT NULL CHECK (category IN ('award', 'event', 'club', 'personal', 'other')),
    challenge_type  TEXT NOT NULL CHECK (challenge_type IN ('collection', 'cumulative', 'timeBounded')),
    configuration   JSONB NOT NULL,
    invite_config   JSONB,
    hamalert_config JSONB,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Participants and their device tokens
CREATE TABLE participants (
    id              UUID PRIMARY KEY,
    callsign        TEXT NOT NULL,
    device_token    TEXT NOT NULL UNIQUE,
    device_name     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_participants_callsign ON participants(callsign);
CREATE INDEX idx_participants_device_token ON participants(device_token);

-- Challenge participation
CREATE TABLE challenge_participants (
    id              UUID PRIMARY KEY,
    challenge_id    UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    callsign        TEXT NOT NULL,
    invite_token    TEXT,
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'left', 'completed')),
    UNIQUE(challenge_id, callsign)
);
CREATE INDEX idx_challenge_participants_challenge ON challenge_participants(challenge_id);
CREATE INDEX idx_challenge_participants_callsign ON challenge_participants(callsign);

-- Progress tracking
CREATE TABLE progress (
    id              UUID PRIMARY KEY,
    challenge_id    UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    callsign        TEXT NOT NULL,
    completed_goals JSONB NOT NULL DEFAULT '[]',
    current_value   INT NOT NULL DEFAULT 0,
    score           INT NOT NULL DEFAULT 0,
    current_tier    TEXT,
    last_qso_date   TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(challenge_id, callsign)
);
CREATE INDEX idx_progress_leaderboard ON progress(challenge_id, score DESC, updated_at ASC);

-- Badges
CREATE TABLE badges (
    id              UUID PRIMARY KEY,
    challenge_id    UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    tier_id         TEXT,
    image_data      BYTEA NOT NULL,
    content_type    TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Earned badges
CREATE TABLE earned_badges (
    id              UUID PRIMARY KEY,
    badge_id        UUID NOT NULL REFERENCES badges(id) ON DELETE CASCADE,
    callsign        TEXT NOT NULL,
    earned_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(badge_id, callsign)
);

-- Challenge snapshots (frozen leaderboards)
CREATE TABLE challenge_snapshots (
    id              UUID PRIMARY KEY,
    challenge_id    UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    ended_at        TIMESTAMPTZ NOT NULL,
    final_standings JSONB NOT NULL,
    statistics      JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Invite tokens
CREATE TABLE invite_tokens (
    token           TEXT PRIMARY KEY,
    challenge_id    UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    max_uses        INT,
    use_count       INT NOT NULL DEFAULT 0,
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_invite_tokens_challenge ON invite_tokens(challenge_id);
```

**Step 2: Commit**

```bash
git add migrations/001_initial_schema.sql
git commit -m "feat: add initial database schema migration"
```

---

## Task 2: Configuration Module

**Files:**
- Create: `src/config.rs`
- Modify: `src/main.rs`

**Step 1: Create config module**

```rust
// src/config.rs
use std::env;

#[derive(Debug, Clone)]
pub struct Config {
    pub database_url: String,
    pub admin_token: String,
    pub port: u16,
    pub base_url: Option<String>,
}

impl Config {
    pub fn from_env() -> Result<Self, ConfigError> {
        let database_url = env::var("DATABASE_URL")
            .map_err(|_| ConfigError::Missing("DATABASE_URL"))?;

        let admin_token = env::var("ADMIN_TOKEN")
            .map_err(|_| ConfigError::Missing("ADMIN_TOKEN"))?;

        let port = env::var("PORT")
            .unwrap_or_else(|_| "8080".to_string())
            .parse()
            .map_err(|_| ConfigError::Invalid("PORT must be a number"))?;

        let base_url = env::var("BASE_URL").ok();

        Ok(Self {
            database_url,
            admin_token,
            port,
            base_url,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("Missing required environment variable: {0}")]
    Missing(&'static str),
    #[error("Invalid configuration: {0}")]
    Invalid(&'static str),
}
```

**Step 2: Update main.rs with module declaration**

```rust
// src/main.rs
mod config;

use config::Config;

fn main() {
    dotenvy::dotenv().ok();

    match Config::from_env() {
        Ok(config) => println!("Config loaded: port={}", config.port),
        Err(e) => eprintln!("Config error: {}", e),
    }
}
```

**Step 3: Verify it compiles**

Run: `cargo build`
Expected: Compiles successfully

**Step 4: Commit**

```bash
git add src/config.rs src/main.rs
git commit -m "feat: add configuration module with env var parsing"
```

---

## Task 3: Error Types

**Files:**
- Create: `src/error.rs`
- Modify: `src/main.rs`

**Step 1: Create error module**

```rust
// src/error.rs
use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::Serialize;
use uuid::Uuid;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("Challenge not found")]
    ChallengeNotFound { challenge_id: Uuid },

    #[error("Already joined this challenge")]
    AlreadyJoined,

    #[error("Not participating in this challenge")]
    NotParticipating,

    #[error("Invite token required")]
    InviteRequired,

    #[error("Invite token expired")]
    InviteExpired,

    #[error("Invite token exhausted")]
    InviteExhausted,

    #[error("Challenge at maximum participants")]
    MaxParticipants,

    #[error("Challenge has ended")]
    ChallengeEnded,

    #[error("Invalid or revoked token")]
    InvalidToken,

    #[error("Rate limit exceeded")]
    RateLimited,

    #[error("Validation error: {message}")]
    Validation { message: String },

    #[error("Database error")]
    Database(#[from] sqlx::Error),

    #[error("Internal server error")]
    Internal(String),
}

#[derive(Serialize)]
struct ErrorResponse {
    error: ErrorBody,
}

#[derive(Serialize)]
struct ErrorBody {
    code: &'static str,
    message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    details: Option<serde_json::Value>,
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, code, details) = match &self {
            Self::ChallengeNotFound { challenge_id } => (
                StatusCode::NOT_FOUND,
                "CHALLENGE_NOT_FOUND",
                Some(serde_json::json!({ "challengeId": challenge_id })),
            ),
            Self::AlreadyJoined => (StatusCode::CONFLICT, "ALREADY_JOINED", None),
            Self::NotParticipating => (StatusCode::FORBIDDEN, "NOT_PARTICIPATING", None),
            Self::InviteRequired => (StatusCode::FORBIDDEN, "INVITE_REQUIRED", None),
            Self::InviteExpired => (StatusCode::FORBIDDEN, "INVITE_EXPIRED", None),
            Self::InviteExhausted => (StatusCode::FORBIDDEN, "INVITE_EXHAUSTED", None),
            Self::MaxParticipants => (StatusCode::FORBIDDEN, "MAX_PARTICIPANTS", None),
            Self::ChallengeEnded => (StatusCode::BAD_REQUEST, "CHALLENGE_ENDED", None),
            Self::InvalidToken => (StatusCode::UNAUTHORIZED, "INVALID_TOKEN", None),
            Self::RateLimited => (StatusCode::TOO_MANY_REQUESTS, "RATE_LIMITED", None),
            Self::Validation { .. } => (StatusCode::BAD_REQUEST, "VALIDATION_ERROR", None),
            Self::Database(_) => (StatusCode::INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", None),
            Self::Internal(_) => (StatusCode::INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", None),
        };

        let body = ErrorResponse {
            error: ErrorBody {
                code,
                message: self.to_string(),
                details,
            },
        };

        (status, Json(body)).into_response()
    }
}
```

**Step 2: Add module to main.rs**

```rust
// src/main.rs
mod config;
mod error;

use config::Config;

fn main() {
    dotenvy::dotenv().ok();

    match Config::from_env() {
        Ok(config) => println!("Config loaded: port={}", config.port),
        Err(e) => eprintln!("Config error: {}", e),
    }
}
```

**Step 3: Verify it compiles**

Run: `cargo build`
Expected: Compiles successfully

**Step 4: Commit**

```bash
git add src/error.rs src/main.rs
git commit -m "feat: add AppError type with IntoResponse for JSON errors"
```

---

## Task 4: Database Models

**Files:**
- Create: `src/models/mod.rs`
- Create: `src/models/challenge.rs`
- Create: `src/models/participant.rs`
- Create: `src/models/progress.rs`
- Modify: `src/main.rs`

**Step 1: Create models directory and mod.rs**

```rust
// src/models/mod.rs
pub mod challenge;
pub mod participant;
pub mod progress;

pub use challenge::*;
pub use participant::*;
pub use progress::*;
```

**Step 2: Create challenge model**

```rust
// src/models/challenge.rs
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, FromRow)]
pub struct Challenge {
    pub id: Uuid,
    pub version: i32,
    pub name: String,
    pub description: String,
    pub author: Option<String>,
    pub category: String,
    pub challenge_type: String,
    pub configuration: serde_json::Value,
    pub invite_config: Option<serde_json::Value>,
    pub hamalert_config: Option<serde_json::Value>,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChallengeResponse {
    pub id: Uuid,
    pub version: i32,
    pub name: String,
    pub description: String,
    pub author: Option<String>,
    pub category: String,
    #[serde(rename = "type")]
    pub challenge_type: String,
    pub configuration: serde_json::Value,
    pub invite_config: Option<serde_json::Value>,
    pub hamalert_config: Option<serde_json::Value>,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl From<Challenge> for ChallengeResponse {
    fn from(c: Challenge) -> Self {
        Self {
            id: c.id,
            version: c.version,
            name: c.name,
            description: c.description,
            author: c.author,
            category: c.category,
            challenge_type: c.challenge_type,
            configuration: c.configuration,
            invite_config: c.invite_config,
            hamalert_config: c.hamalert_config,
            is_active: c.is_active,
            created_at: c.created_at,
            updated_at: c.updated_at,
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChallengeListItem {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub category: String,
    #[serde(rename = "type")]
    pub challenge_type: String,
    pub participant_count: i64,
    pub is_active: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateChallengeRequest {
    pub name: String,
    pub description: String,
    pub author: Option<String>,
    pub category: String,
    #[serde(rename = "type")]
    pub challenge_type: String,
    pub configuration: serde_json::Value,
    pub invite_config: Option<serde_json::Value>,
    pub hamalert_config: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ListChallengesQuery {
    pub category: Option<String>,
    #[serde(rename = "type")]
    pub challenge_type: Option<String>,
    pub active: Option<bool>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}
```

**Step 3: Create participant model**

```rust
// src/models/participant.rs
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, FromRow)]
pub struct Participant {
    pub id: Uuid,
    pub callsign: String,
    pub device_token: String,
    pub device_name: Option<String>,
    pub created_at: DateTime<Utc>,
    pub last_seen_at: DateTime<Utc>,
}

#[derive(Debug, Clone, FromRow)]
pub struct ChallengeParticipant {
    pub id: Uuid,
    pub challenge_id: Uuid,
    pub callsign: String,
    pub invite_token: Option<String>,
    pub joined_at: DateTime<Utc>,
    pub status: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct JoinChallengeRequest {
    pub callsign: String,
    pub device_name: Option<String>,
    pub invite_token: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JoinChallengeResponse {
    pub participation_id: Uuid,
    pub device_token: String,
    pub joined_at: DateTime<Utc>,
    pub status: String,
    pub historical_allowed: bool,
}
```

**Step 4: Create progress model**

```rust
// src/models/progress.rs
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, FromRow)]
pub struct Progress {
    pub id: Uuid,
    pub challenge_id: Uuid,
    pub callsign: String,
    pub completed_goals: serde_json::Value,
    pub current_value: i32,
    pub score: i32,
    pub current_tier: Option<String>,
    pub last_qso_date: Option<DateTime<Utc>>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReportProgressRequest {
    pub completed_goals: Vec<String>,
    pub current_value: i32,
    pub qualifying_qso_count: i32,
    pub last_qso_date: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProgressResponse {
    pub completed_goals: Vec<String>,
    pub current_value: i32,
    pub percentage: f64,
    pub score: i32,
    pub rank: i64,
    pub current_tier: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReportProgressResponse {
    pub accepted: bool,
    pub server_progress: ProgressResponse,
    pub new_badges: Vec<Uuid>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LeaderboardEntry {
    pub rank: i64,
    pub callsign: String,
    pub score: i32,
    pub current_tier: Option<String>,
    pub completed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LeaderboardResponse {
    pub leaderboard: Vec<LeaderboardEntry>,
    pub total: i64,
    pub user_position: Option<LeaderboardEntry>,
    pub last_updated: DateTime<Utc>,
}

#[derive(Debug, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct LeaderboardQuery {
    pub limit: Option<i64>,
    pub offset: Option<i64>,
    pub around: Option<String>,
}
```

**Step 5: Update main.rs**

```rust
// src/main.rs
mod config;
mod error;
mod models;

use config::Config;

fn main() {
    dotenvy::dotenv().ok();

    match Config::from_env() {
        Ok(config) => println!("Config loaded: port={}", config.port),
        Err(e) => eprintln!("Config error: {}", e),
    }
}
```

**Step 6: Verify it compiles**

Run: `cargo build`
Expected: Compiles successfully

**Step 7: Commit**

```bash
git add src/models src/main.rs
git commit -m "feat: add database models for challenges, participants, progress"
```

---

## Task 5: Auth Module - Token Generation

**Files:**
- Create: `src/auth/mod.rs`
- Create: `src/auth/token.rs`
- Modify: `src/main.rs`

**Step 1: Create auth mod.rs**

```rust
// src/auth/mod.rs
pub mod token;

pub use token::*;
```

**Step 2: Create token module**

```rust
// src/auth/token.rs
use rand::Rng;

const TOKEN_PREFIX: &str = "fd_";
const TOKEN_LENGTH: usize = 32;
const TOKEN_CHARS: &[u8] = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

pub fn generate_device_token() -> String {
    let mut rng = rand::thread_rng();
    let token: String = (0..TOKEN_LENGTH)
        .map(|_| {
            let idx = rng.gen_range(0..TOKEN_CHARS.len());
            TOKEN_CHARS[idx] as char
        })
        .collect();
    format!("{}{}", TOKEN_PREFIX, token)
}

pub fn is_valid_token_format(token: &str) -> bool {
    if !token.starts_with(TOKEN_PREFIX) {
        return false;
    }
    let suffix = &token[TOKEN_PREFIX.len()..];
    suffix.len() == TOKEN_LENGTH && suffix.chars().all(|c| c.is_ascii_alphanumeric())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_token_format() {
        let token = generate_device_token();
        assert!(token.starts_with("fd_"));
        assert_eq!(token.len(), 3 + TOKEN_LENGTH); // "fd_" + 32 chars
    }

    #[test]
    fn test_generate_token_uniqueness() {
        let token1 = generate_device_token();
        let token2 = generate_device_token();
        assert_ne!(token1, token2);
    }

    #[test]
    fn test_is_valid_token_format() {
        assert!(is_valid_token_format("fd_abcdefghijklmnopqrstuvwxyz123456"));
        assert!(!is_valid_token_format("abc"));
        assert!(!is_valid_token_format("fd_short"));
        assert!(!is_valid_token_format("xx_abcdefghijklmnopqrstuvwxyz123456"));
    }
}
```

**Step 3: Update main.rs**

```rust
// src/main.rs
mod auth;
mod config;
mod error;
mod models;

use config::Config;

fn main() {
    dotenvy::dotenv().ok();

    match Config::from_env() {
        Ok(config) => println!("Config loaded: port={}", config.port),
        Err(e) => eprintln!("Config error: {}", e),
    }
}
```

**Step 4: Run tests**

Run: `cargo test`
Expected: All tests pass

**Step 5: Commit**

```bash
git add src/auth src/main.rs
git commit -m "feat: add device token generation and validation"
```

---

## Task 6: Auth Middleware

**Files:**
- Create: `src/auth/middleware.rs`
- Modify: `src/auth/mod.rs`

**Step 1: Create auth middleware**

```rust
// src/auth/middleware.rs
use axum::{
    extract::{Request, State},
    middleware::Next,
    response::Response,
};
use sqlx::PgPool;

use crate::error::AppError;

#[derive(Debug, Clone)]
pub struct AuthContext {
    pub callsign: String,
    pub participant_id: uuid::Uuid,
}

pub async fn optional_auth(
    State(pool): State<PgPool>,
    mut req: Request,
    next: Next,
) -> Result<Response, AppError> {
    if let Some(auth_header) = req.headers().get("authorization") {
        if let Ok(auth_str) = auth_header.to_str() {
            if let Some(token) = auth_str.strip_prefix("Bearer ") {
                if let Some(ctx) = validate_token(&pool, token).await? {
                    req.extensions_mut().insert(ctx);
                }
            }
        }
    }
    Ok(next.run(req).await)
}

pub async fn require_auth(
    State(pool): State<PgPool>,
    mut req: Request,
    next: Next,
) -> Result<Response, AppError> {
    let auth_header = req
        .headers()
        .get("authorization")
        .ok_or(AppError::InvalidToken)?;

    let auth_str = auth_header.to_str().map_err(|_| AppError::InvalidToken)?;

    let token = auth_str
        .strip_prefix("Bearer ")
        .ok_or(AppError::InvalidToken)?;

    let ctx = validate_token(&pool, token)
        .await?
        .ok_or(AppError::InvalidToken)?;

    req.extensions_mut().insert(ctx);
    Ok(next.run(req).await)
}

async fn validate_token(pool: &PgPool, token: &str) -> Result<Option<AuthContext>, AppError> {
    let participant = sqlx::query!(
        r#"
        UPDATE participants
        SET last_seen_at = now()
        WHERE device_token = $1
        RETURNING id, callsign
        "#,
        token
    )
    .fetch_optional(pool)
    .await?;

    Ok(participant.map(|p| AuthContext {
        callsign: p.callsign,
        participant_id: p.id,
    }))
}

pub async fn require_admin(
    State(admin_token): State<String>,
    req: Request,
    next: Next,
) -> Result<Response, AppError> {
    let auth_header = req
        .headers()
        .get("authorization")
        .ok_or(AppError::InvalidToken)?;

    let auth_str = auth_header.to_str().map_err(|_| AppError::InvalidToken)?;

    let token = auth_str
        .strip_prefix("Bearer ")
        .ok_or(AppError::InvalidToken)?;

    if token != admin_token {
        return Err(AppError::InvalidToken);
    }

    Ok(next.run(req).await)
}
```

**Step 2: Update auth mod.rs**

```rust
// src/auth/mod.rs
pub mod middleware;
pub mod token;

pub use middleware::*;
pub use token::*;
```

**Step 3: Verify it compiles**

Run: `cargo build`
Expected: Compiles successfully

**Step 4: Commit**

```bash
git add src/auth
git commit -m "feat: add auth middleware for optional, required, and admin auth"
```

---

## Task 7: Database Layer - Challenges

**Files:**
- Create: `src/db/mod.rs`
- Create: `src/db/challenges.rs`
- Modify: `src/main.rs`

**Step 1: Create db mod.rs**

```rust
// src/db/mod.rs
pub mod challenges;

pub use challenges::*;
```

**Step 2: Create challenges database module**

```rust
// src/db/challenges.rs
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::AppError;
use crate::models::{
    Challenge, ChallengeListItem, CreateChallengeRequest, ListChallengesQuery,
};

pub async fn list_challenges(
    pool: &PgPool,
    query: &ListChallengesQuery,
) -> Result<(Vec<ChallengeListItem>, i64), AppError> {
    let limit = query.limit.unwrap_or(50).min(100);
    let offset = query.offset.unwrap_or(0);

    let challenges = sqlx::query_as!(
        ChallengeListItem,
        r#"
        SELECT
            c.id,
            c.name,
            c.description,
            c.category,
            c.challenge_type,
            c.is_active,
            COALESCE(COUNT(cp.id), 0) as "participant_count!"
        FROM challenges c
        LEFT JOIN challenge_participants cp ON cp.challenge_id = c.id AND cp.status = 'active'
        WHERE ($1::text IS NULL OR c.category = $1)
          AND ($2::text IS NULL OR c.challenge_type = $2)
          AND ($3::bool IS NULL OR c.is_active = $3)
        GROUP BY c.id
        ORDER BY c.created_at DESC
        LIMIT $4 OFFSET $5
        "#,
        query.category,
        query.challenge_type,
        query.active,
        limit,
        offset,
    )
    .fetch_all(pool)
    .await?;

    let total = sqlx::query_scalar!(
        r#"
        SELECT COUNT(*) as "count!"
        FROM challenges c
        WHERE ($1::text IS NULL OR c.category = $1)
          AND ($2::text IS NULL OR c.challenge_type = $2)
          AND ($3::bool IS NULL OR c.is_active = $3)
        "#,
        query.category,
        query.challenge_type,
        query.active,
    )
    .fetch_one(pool)
    .await?;

    Ok((challenges, total))
}

pub async fn get_challenge(pool: &PgPool, id: Uuid) -> Result<Option<Challenge>, AppError> {
    let challenge = sqlx::query_as!(
        Challenge,
        r#"
        SELECT
            id, version, name, description, author, category, challenge_type,
            configuration, invite_config, hamalert_config, is_active,
            created_at, updated_at
        FROM challenges
        WHERE id = $1
        "#,
        id
    )
    .fetch_optional(pool)
    .await?;

    Ok(challenge)
}

pub async fn create_challenge(
    pool: &PgPool,
    req: &CreateChallengeRequest,
) -> Result<Challenge, AppError> {
    let id = Uuid::new_v4();

    let challenge = sqlx::query_as!(
        Challenge,
        r#"
        INSERT INTO challenges (id, name, description, author, category, challenge_type, configuration, invite_config, hamalert_config)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING id, version, name, description, author, category, challenge_type,
                  configuration, invite_config, hamalert_config, is_active,
                  created_at, updated_at
        "#,
        id,
        req.name,
        req.description,
        req.author,
        req.category,
        req.challenge_type,
        req.configuration,
        req.invite_config,
        req.hamalert_config,
    )
    .fetch_one(pool)
    .await?;

    Ok(challenge)
}

pub async fn update_challenge(
    pool: &PgPool,
    id: Uuid,
    req: &CreateChallengeRequest,
) -> Result<Option<Challenge>, AppError> {
    let challenge = sqlx::query_as!(
        Challenge,
        r#"
        UPDATE challenges
        SET name = $2, description = $3, author = $4, category = $5,
            challenge_type = $6, configuration = $7, invite_config = $8,
            hamalert_config = $9, version = version + 1, updated_at = now()
        WHERE id = $1
        RETURNING id, version, name, description, author, category, challenge_type,
                  configuration, invite_config, hamalert_config, is_active,
                  created_at, updated_at
        "#,
        id,
        req.name,
        req.description,
        req.author,
        req.category,
        req.challenge_type,
        req.configuration,
        req.invite_config,
        req.hamalert_config,
    )
    .fetch_optional(pool)
    .await?;

    Ok(challenge)
}

pub async fn delete_challenge(pool: &PgPool, id: Uuid) -> Result<bool, AppError> {
    let result = sqlx::query!("DELETE FROM challenges WHERE id = $1", id)
        .execute(pool)
        .await?;

    Ok(result.rows_affected() > 0)
}
```

**Step 3: Update main.rs**

```rust
// src/main.rs
mod auth;
mod config;
mod db;
mod error;
mod models;

use config::Config;

fn main() {
    dotenvy::dotenv().ok();

    match Config::from_env() {
        Ok(config) => println!("Config loaded: port={}", config.port),
        Err(e) => eprintln!("Config error: {}", e),
    }
}
```

**Step 4: Verify it compiles**

Run: `cargo build`
Expected: Compiles successfully

**Step 5: Commit**

```bash
git add src/db src/main.rs
git commit -m "feat: add database layer for challenge CRUD operations"
```

---

## Task 8: Database Layer - Participants and Progress

**Files:**
- Create: `src/db/participants.rs`
- Create: `src/db/progress.rs`
- Modify: `src/db/mod.rs`

**Step 1: Create participants database module**

```rust
// src/db/participants.rs
use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::generate_device_token;
use crate::error::AppError;
use crate::models::{ChallengeParticipant, JoinChallengeRequest, Participant};

pub async fn get_or_create_participant(
    pool: &PgPool,
    callsign: &str,
    device_name: Option<&str>,
) -> Result<(Participant, bool), AppError> {
    // Check if participant exists with this callsign (any device)
    let existing = sqlx::query_as!(
        Participant,
        r#"
        SELECT id, callsign, device_token, device_name, created_at, last_seen_at
        FROM participants
        WHERE callsign = $1
        LIMIT 1
        "#,
        callsign
    )
    .fetch_optional(pool)
    .await?;

    if let Some(p) = existing {
        return Ok((p, false));
    }

    // Create new participant with device token
    let id = Uuid::new_v4();
    let device_token = generate_device_token();

    let participant = sqlx::query_as!(
        Participant,
        r#"
        INSERT INTO participants (id, callsign, device_token, device_name)
        VALUES ($1, $2, $3, $4)
        RETURNING id, callsign, device_token, device_name, created_at, last_seen_at
        "#,
        id,
        callsign,
        device_token,
        device_name,
    )
    .fetch_one(pool)
    .await?;

    Ok((participant, true))
}

pub async fn get_participant_by_token(
    pool: &PgPool,
    token: &str,
) -> Result<Option<Participant>, AppError> {
    let participant = sqlx::query_as!(
        Participant,
        r#"
        SELECT id, callsign, device_token, device_name, created_at, last_seen_at
        FROM participants
        WHERE device_token = $1
        "#,
        token
    )
    .fetch_optional(pool)
    .await?;

    Ok(participant)
}

pub async fn join_challenge(
    pool: &PgPool,
    challenge_id: Uuid,
    callsign: &str,
    invite_token: Option<&str>,
) -> Result<ChallengeParticipant, AppError> {
    let id = Uuid::new_v4();

    let participation = sqlx::query_as!(
        ChallengeParticipant,
        r#"
        INSERT INTO challenge_participants (id, challenge_id, callsign, invite_token)
        VALUES ($1, $2, $3, $4)
        RETURNING id, challenge_id, callsign, invite_token, joined_at, status
        "#,
        id,
        challenge_id,
        callsign,
        invite_token,
    )
    .fetch_one(pool)
    .await
    .map_err(|e| {
        if let sqlx::Error::Database(ref db_err) = e {
            if db_err.constraint() == Some("challenge_participants_challenge_id_callsign_key") {
                return AppError::AlreadyJoined;
            }
        }
        AppError::Database(e)
    })?;

    Ok(participation)
}

pub async fn get_participation(
    pool: &PgPool,
    challenge_id: Uuid,
    callsign: &str,
) -> Result<Option<ChallengeParticipant>, AppError> {
    let participation = sqlx::query_as!(
        ChallengeParticipant,
        r#"
        SELECT id, challenge_id, callsign, invite_token, joined_at, status
        FROM challenge_participants
        WHERE challenge_id = $1 AND callsign = $2
        "#,
        challenge_id,
        callsign
    )
    .fetch_optional(pool)
    .await?;

    Ok(participation)
}

pub async fn leave_challenge(
    pool: &PgPool,
    challenge_id: Uuid,
    callsign: &str,
) -> Result<bool, AppError> {
    let result = sqlx::query!(
        r#"
        UPDATE challenge_participants
        SET status = 'left'
        WHERE challenge_id = $1 AND callsign = $2 AND status = 'active'
        "#,
        challenge_id,
        callsign
    )
    .execute(pool)
    .await?;

    Ok(result.rows_affected() > 0)
}

pub async fn revoke_tokens(pool: &PgPool, callsign: &str) -> Result<u64, AppError> {
    let result = sqlx::query!("DELETE FROM participants WHERE callsign = $1", callsign)
        .execute(pool)
        .await?;

    Ok(result.rows_affected())
}
```

**Step 2: Create progress database module**

```rust
// src/db/progress.rs
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::AppError;
use crate::models::{LeaderboardEntry, LeaderboardQuery, Progress, ReportProgressRequest};

pub async fn get_progress(
    pool: &PgPool,
    challenge_id: Uuid,
    callsign: &str,
) -> Result<Option<Progress>, AppError> {
    let progress = sqlx::query_as!(
        Progress,
        r#"
        SELECT id, challenge_id, callsign, completed_goals, current_value,
               score, current_tier, last_qso_date, updated_at
        FROM progress
        WHERE challenge_id = $1 AND callsign = $2
        "#,
        challenge_id,
        callsign
    )
    .fetch_optional(pool)
    .await?;

    Ok(progress)
}

pub async fn upsert_progress(
    pool: &PgPool,
    challenge_id: Uuid,
    callsign: &str,
    req: &ReportProgressRequest,
    score: i32,
    current_tier: Option<&str>,
) -> Result<Progress, AppError> {
    let id = Uuid::new_v4();
    let completed_goals = serde_json::to_value(&req.completed_goals)?;

    let progress = sqlx::query_as!(
        Progress,
        r#"
        INSERT INTO progress (id, challenge_id, callsign, completed_goals, current_value, score, current_tier, last_qso_date)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (challenge_id, callsign) DO UPDATE
        SET completed_goals = $4, current_value = $5, score = $6,
            current_tier = $7, last_qso_date = $8, updated_at = now()
        RETURNING id, challenge_id, callsign, completed_goals, current_value,
                  score, current_tier, last_qso_date, updated_at
        "#,
        id,
        challenge_id,
        callsign,
        completed_goals,
        req.current_value,
        score,
        current_tier,
        req.last_qso_date,
    )
    .fetch_one(pool)
    .await?;

    Ok(progress)
}

pub async fn get_rank(
    pool: &PgPool,
    challenge_id: Uuid,
    callsign: &str,
) -> Result<Option<i64>, AppError> {
    let rank = sqlx::query_scalar!(
        r#"
        SELECT rank FROM (
            SELECT callsign, RANK() OVER (ORDER BY score DESC, updated_at ASC) as rank
            FROM progress
            WHERE challenge_id = $1
        ) ranked
        WHERE callsign = $2
        "#,
        challenge_id,
        callsign
    )
    .fetch_optional(pool)
    .await?;

    Ok(rank.flatten())
}

pub async fn get_leaderboard(
    pool: &PgPool,
    challenge_id: Uuid,
    query: &LeaderboardQuery,
) -> Result<(Vec<LeaderboardEntry>, i64), AppError> {
    let limit = query.limit.unwrap_or(100).min(100);
    let offset = query.offset.unwrap_or(0);

    let entries = sqlx::query_as!(
        LeaderboardEntry,
        r#"
        SELECT
            RANK() OVER (ORDER BY score DESC, updated_at ASC) as "rank!",
            callsign,
            score,
            current_tier,
            CASE WHEN score > 0 THEN updated_at ELSE NULL END as completed_at
        FROM progress
        WHERE challenge_id = $1
        ORDER BY score DESC, updated_at ASC
        LIMIT $2 OFFSET $3
        "#,
        challenge_id,
        limit,
        offset,
    )
    .fetch_all(pool)
    .await?;

    let total = sqlx::query_scalar!(
        r#"SELECT COUNT(*) as "count!" FROM progress WHERE challenge_id = $1"#,
        challenge_id
    )
    .fetch_one(pool)
    .await?;

    Ok((entries, total))
}

pub async fn get_leaderboard_around(
    pool: &PgPool,
    challenge_id: Uuid,
    callsign: &str,
    range: i64,
) -> Result<Vec<LeaderboardEntry>, AppError> {
    let entries = sqlx::query_as!(
        LeaderboardEntry,
        r#"
        WITH ranked AS (
            SELECT
                RANK() OVER (ORDER BY score DESC, updated_at ASC) as rank,
                callsign,
                score,
                current_tier,
                CASE WHEN score > 0 THEN updated_at ELSE NULL END as completed_at
            FROM progress
            WHERE challenge_id = $1
        )
        SELECT
            rank as "rank!",
            callsign,
            score,
            current_tier,
            completed_at
        FROM ranked
        WHERE rank BETWEEN
            (SELECT rank FROM ranked WHERE callsign = $2) - $3
            AND
            (SELECT rank FROM ranked WHERE callsign = $2) + $3
        ORDER BY rank
        "#,
        challenge_id,
        callsign,
        range,
    )
    .fetch_all(pool)
    .await?;

    Ok(entries)
}

impl From<serde_json::Error> for AppError {
    fn from(e: serde_json::Error) -> Self {
        AppError::Internal(e.to_string())
    }
}
```

**Step 3: Update db mod.rs**

```rust
// src/db/mod.rs
pub mod challenges;
pub mod participants;
pub mod progress;

pub use challenges::*;
pub use participants::*;
pub use progress::*;
```

**Step 4: Verify it compiles**

Run: `cargo build`
Expected: Compiles successfully

**Step 5: Commit**

```bash
git add src/db
git commit -m "feat: add database layer for participants and progress"
```

---

## Task 9: HTTP Handlers - Challenges

**Files:**
- Create: `src/handlers/mod.rs`
- Create: `src/handlers/challenges.rs`
- Modify: `src/main.rs`

**Step 1: Create handlers mod.rs**

```rust
// src/handlers/mod.rs
pub mod challenges;

pub use challenges::*;
```

**Step 2: Create challenges handlers**

```rust
// src/handlers/challenges.rs
use axum::{
    extract::{Path, Query, State},
    http::{header, HeaderMap, StatusCode},
    Json,
};
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::db;
use crate::error::AppError;
use crate::models::{
    ChallengeListItem, ChallengeResponse, CreateChallengeRequest, ListChallengesQuery,
};

#[derive(Serialize)]
pub struct DataResponse<T> {
    pub data: T,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ListChallengesResponse {
    pub challenges: Vec<ChallengeListItem>,
    pub total: i64,
    pub limit: i64,
    pub offset: i64,
}

pub async fn list_challenges(
    State(pool): State<PgPool>,
    Query(query): Query<ListChallengesQuery>,
) -> Result<Json<DataResponse<ListChallengesResponse>>, AppError> {
    let limit = query.limit.unwrap_or(50).min(100);
    let offset = query.offset.unwrap_or(0);

    let (challenges, total) = db::list_challenges(&pool, &query).await?;

    Ok(Json(DataResponse {
        data: ListChallengesResponse {
            challenges,
            total,
            limit,
            offset,
        },
    }))
}

pub async fn get_challenge(
    State(pool): State<PgPool>,
    Path(id): Path<Uuid>,
) -> Result<(HeaderMap, Json<DataResponse<ChallengeResponse>>), AppError> {
    let challenge = db::get_challenge(&pool, id)
        .await?
        .ok_or(AppError::ChallengeNotFound { challenge_id: id })?;

    let mut headers = HeaderMap::new();
    headers.insert(
        "X-Challenge-Version",
        challenge.version.to_string().parse().unwrap(),
    );

    // Simple ETag based on version and updated_at
    let etag = format!(
        "\"{}:{}\"",
        challenge.version,
        challenge.updated_at.timestamp()
    );
    headers.insert(header::ETAG, etag.parse().unwrap());

    Ok((
        headers,
        Json(DataResponse {
            data: challenge.into(),
        }),
    ))
}

// Admin handlers
pub async fn create_challenge(
    State(pool): State<PgPool>,
    Json(req): Json<CreateChallengeRequest>,
) -> Result<(StatusCode, Json<DataResponse<ChallengeResponse>>), AppError> {
    let challenge = db::create_challenge(&pool, &req).await?;

    Ok((
        StatusCode::CREATED,
        Json(DataResponse {
            data: challenge.into(),
        }),
    ))
}

pub async fn update_challenge(
    State(pool): State<PgPool>,
    Path(id): Path<Uuid>,
    Json(req): Json<CreateChallengeRequest>,
) -> Result<Json<DataResponse<ChallengeResponse>>, AppError> {
    let challenge = db::update_challenge(&pool, id, &req)
        .await?
        .ok_or(AppError::ChallengeNotFound { challenge_id: id })?;

    Ok(Json(DataResponse {
        data: challenge.into(),
    }))
}

pub async fn delete_challenge(
    State(pool): State<PgPool>,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let deleted = db::delete_challenge(&pool, id).await?;

    if deleted {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::ChallengeNotFound { challenge_id: id })
    }
}
```

**Step 3: Update main.rs**

```rust
// src/main.rs
mod auth;
mod config;
mod db;
mod error;
mod handlers;
mod models;

use config::Config;

fn main() {
    dotenvy::dotenv().ok();

    match Config::from_env() {
        Ok(config) => println!("Config loaded: port={}", config.port),
        Err(e) => eprintln!("Config error: {}", e),
    }
}
```

**Step 4: Verify it compiles**

Run: `cargo build`
Expected: Compiles successfully

**Step 5: Commit**

```bash
git add src/handlers src/main.rs
git commit -m "feat: add HTTP handlers for challenge endpoints"
```

---

## Task 10: HTTP Handlers - Join, Progress, Leaderboard

**Files:**
- Create: `src/handlers/join.rs`
- Create: `src/handlers/progress.rs`
- Create: `src/handlers/leaderboard.rs`
- Modify: `src/handlers/mod.rs`

**Step 1: Create join handler**

```rust
// src/handlers/join.rs
use axum::{
    extract::{Extension, Path, State},
    http::StatusCode,
    Json,
};
use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::AuthContext;
use crate::db;
use crate::error::AppError;
use crate::models::{JoinChallengeRequest, JoinChallengeResponse};

use super::DataResponse;

pub async fn join_challenge(
    State(pool): State<PgPool>,
    Path(challenge_id): Path<Uuid>,
    auth: Option<Extension<AuthContext>>,
    Json(req): Json<JoinChallengeRequest>,
) -> Result<(StatusCode, Json<DataResponse<JoinChallengeResponse>>), AppError> {
    // Verify challenge exists and is active
    let challenge = db::get_challenge(&pool, challenge_id)
        .await?
        .ok_or(AppError::ChallengeNotFound { challenge_id })?;

    if !challenge.is_active {
        return Err(AppError::ChallengeEnded);
    }

    // Check invite requirements
    if let Some(invite_config) = &challenge.invite_config {
        let requires_token = invite_config
            .get("requiresToken")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);

        if requires_token && req.invite_token.is_none() {
            return Err(AppError::InviteRequired);
        }
    }

    // Get or create participant
    let (participant, _is_new) = db::get_or_create_participant(
        &pool,
        &req.callsign,
        req.device_name.as_deref(),
    )
    .await?;

    // Join the challenge
    let participation = db::join_challenge(
        &pool,
        challenge_id,
        &req.callsign,
        req.invite_token.as_deref(),
    )
    .await?;

    // Check if historical QSOs are allowed
    let historical_allowed = challenge
        .configuration
        .get("historicalQsosAllowed")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    Ok((
        StatusCode::CREATED,
        Json(DataResponse {
            data: JoinChallengeResponse {
                participation_id: participation.id,
                device_token: participant.device_token,
                joined_at: participation.joined_at,
                status: participation.status,
                historical_allowed,
            },
        }),
    ))
}

pub async fn leave_challenge(
    State(pool): State<PgPool>,
    Path(challenge_id): Path<Uuid>,
    Extension(auth): Extension<AuthContext>,
) -> Result<StatusCode, AppError> {
    // Also delete progress
    sqlx::query!(
        "DELETE FROM progress WHERE challenge_id = $1 AND callsign = $2",
        challenge_id,
        auth.callsign
    )
    .execute(&pool)
    .await?;

    let left = db::leave_challenge(&pool, challenge_id, &auth.callsign).await?;

    if left {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::NotParticipating)
    }
}
```

**Step 2: Create progress handler**

```rust
// src/handlers/progress.rs
use axum::{
    extract::{Extension, Path, State},
    Json,
};
use chrono::Utc;
use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::AuthContext;
use crate::db;
use crate::error::AppError;
use crate::models::{ProgressResponse, ReportProgressRequest, ReportProgressResponse};

use super::DataResponse;

pub async fn report_progress(
    State(pool): State<PgPool>,
    Path(challenge_id): Path<Uuid>,
    Extension(auth): Extension<AuthContext>,
    Json(req): Json<ReportProgressRequest>,
) -> Result<Json<DataResponse<ReportProgressResponse>>, AppError> {
    // Verify challenge exists
    let challenge = db::get_challenge(&pool, challenge_id)
        .await?
        .ok_or(AppError::ChallengeNotFound { challenge_id })?;

    // Verify participation
    let _participation = db::get_participation(&pool, challenge_id, &auth.callsign)
        .await?
        .ok_or(AppError::NotParticipating)?;

    // Calculate score based on challenge type
    let score = calculate_score(&challenge.configuration, &req);

    // Determine current tier
    let current_tier = determine_tier(&challenge.configuration, score);

    // Upsert progress
    let progress = db::upsert_progress(
        &pool,
        challenge_id,
        &auth.callsign,
        &req,
        score,
        current_tier.as_deref(),
    )
    .await?;

    // Get rank
    let rank = db::get_rank(&pool, challenge_id, &auth.callsign)
        .await?
        .unwrap_or(0);

    // Calculate percentage
    let percentage = calculate_percentage(&challenge.configuration, &req);

    // TODO: Check for new badges earned
    let new_badges = vec![];

    Ok(Json(DataResponse {
        data: ReportProgressResponse {
            accepted: true,
            server_progress: ProgressResponse {
                completed_goals: req.completed_goals,
                current_value: req.current_value,
                percentage,
                score,
                rank,
                current_tier,
            },
            new_badges,
        },
    }))
}

pub async fn get_progress(
    State(pool): State<PgPool>,
    Path(challenge_id): Path<Uuid>,
    Extension(auth): Extension<AuthContext>,
) -> Result<Json<DataResponse<ProgressResponse>>, AppError> {
    let challenge = db::get_challenge(&pool, challenge_id)
        .await?
        .ok_or(AppError::ChallengeNotFound { challenge_id })?;

    let progress = db::get_progress(&pool, challenge_id, &auth.callsign)
        .await?
        .ok_or(AppError::NotParticipating)?;

    let rank = db::get_rank(&pool, challenge_id, &auth.callsign)
        .await?
        .unwrap_or(0);

    let completed_goals: Vec<String> = serde_json::from_value(progress.completed_goals)
        .unwrap_or_default();

    let percentage = calculate_percentage_from_progress(&challenge.configuration, &progress);

    Ok(Json(DataResponse {
        data: ProgressResponse {
            completed_goals,
            current_value: progress.current_value,
            percentage,
            score: progress.score,
            rank,
            current_tier: progress.current_tier,
        },
    }))
}

fn calculate_score(config: &serde_json::Value, req: &ReportProgressRequest) -> i32 {
    let scoring = config.get("scoring");
    let method = scoring
        .and_then(|s| s.get("method"))
        .and_then(|m| m.as_str())
        .unwrap_or("count");

    match method {
        "percentage" => {
            let total = get_total_goals(config);
            if total > 0 {
                (req.completed_goals.len() as f64 / total as f64 * 100.0) as i32
            } else {
                0
            }
        }
        "count" => req.completed_goals.len() as i32,
        "points" => req.current_value,
        _ => req.completed_goals.len() as i32,
    }
}

fn calculate_percentage(config: &serde_json::Value, req: &ReportProgressRequest) -> f64 {
    let goals = config.get("goals");
    let goal_type = goals
        .and_then(|g| g.get("type"))
        .and_then(|t| t.as_str())
        .unwrap_or("collection");

    match goal_type {
        "collection" => {
            let total = get_total_goals(config);
            if total > 0 {
                req.completed_goals.len() as f64 / total as f64 * 100.0
            } else {
                0.0
            }
        }
        "cumulative" => {
            let target = goals
                .and_then(|g| g.get("targetValue"))
                .and_then(|t| t.as_i64())
                .unwrap_or(100) as f64;
            if target > 0.0 {
                req.current_value as f64 / target * 100.0
            } else {
                0.0
            }
        }
        _ => 0.0,
    }
}

fn calculate_percentage_from_progress(config: &serde_json::Value, progress: &db::Progress) -> f64 {
    let goals = config.get("goals");
    let goal_type = goals
        .and_then(|g| g.get("type"))
        .and_then(|t| t.as_str())
        .unwrap_or("collection");

    match goal_type {
        "collection" => {
            let total = get_total_goals(config);
            let completed: Vec<String> = serde_json::from_value(progress.completed_goals.clone())
                .unwrap_or_default();
            if total > 0 {
                completed.len() as f64 / total as f64 * 100.0
            } else {
                0.0
            }
        }
        "cumulative" => {
            let target = goals
                .and_then(|g| g.get("targetValue"))
                .and_then(|t| t.as_i64())
                .unwrap_or(100) as f64;
            if target > 0.0 {
                progress.current_value as f64 / target * 100.0
            } else {
                0.0
            }
        }
        _ => 0.0,
    }
}

fn get_total_goals(config: &serde_json::Value) -> usize {
    config
        .get("goals")
        .and_then(|g| g.get("items"))
        .and_then(|i| i.as_array())
        .map(|a| a.len())
        .unwrap_or(0)
}

fn determine_tier(config: &serde_json::Value, score: i32) -> Option<String> {
    let tiers = config.get("tiers")?.as_array()?;

    let mut current_tier: Option<&serde_json::Value> = None;

    for tier in tiers {
        let threshold = tier.get("threshold")?.as_i64()? as i32;
        if score >= threshold {
            current_tier = Some(tier);
        }
    }

    current_tier
        .and_then(|t| t.get("id"))
        .and_then(|id| id.as_str())
        .map(String::from)
}
```

**Step 3: Create leaderboard handler**

```rust
// src/handlers/leaderboard.rs
use axum::{
    extract::{Path, Query, State},
    Json,
};
use chrono::Utc;
use sqlx::PgPool;
use uuid::Uuid;

use crate::db;
use crate::error::AppError;
use crate::models::{LeaderboardQuery, LeaderboardResponse};

use super::DataResponse;

pub async fn get_leaderboard(
    State(pool): State<PgPool>,
    Path(challenge_id): Path<Uuid>,
    Query(query): Query<LeaderboardQuery>,
) -> Result<Json<DataResponse<LeaderboardResponse>>, AppError> {
    // Verify challenge exists
    let _challenge = db::get_challenge(&pool, challenge_id)
        .await?
        .ok_or(AppError::ChallengeNotFound { challenge_id })?;

    let (leaderboard, total) = if let Some(ref around) = query.around {
        let entries = db::get_leaderboard_around(&pool, challenge_id, around, 5).await?;
        let total = sqlx::query_scalar!(
            r#"SELECT COUNT(*) as "count!" FROM progress WHERE challenge_id = $1"#,
            challenge_id
        )
        .fetch_one(&pool)
        .await?;
        (entries, total)
    } else {
        db::get_leaderboard(&pool, challenge_id, &query).await?
    };

    // Get user position if around was specified
    let user_position = if let Some(ref around) = query.around {
        leaderboard.iter().find(|e| e.callsign == *around).cloned()
    } else {
        None
    };

    Ok(Json(DataResponse {
        data: LeaderboardResponse {
            leaderboard,
            total,
            user_position,
            last_updated: Utc::now(),
        },
    }))
}
```

**Step 4: Update handlers mod.rs**

```rust
// src/handlers/mod.rs
pub mod challenges;
pub mod join;
pub mod leaderboard;
pub mod progress;

pub use challenges::*;
pub use join::*;
pub use leaderboard::*;
pub use progress::*;
```

**Step 5: Verify it compiles**

Run: `cargo build`
Expected: Compiles successfully

**Step 6: Commit**

```bash
git add src/handlers
git commit -m "feat: add handlers for join, progress, and leaderboard"
```

---

## Task 11: HTTP Handlers - Health Check

**Files:**
- Create: `src/handlers/health.rs`
- Modify: `src/handlers/mod.rs`

**Step 1: Create health handler**

```rust
// src/handlers/health.rs
use axum::Json;
use serde::Serialize;

#[derive(Serialize)]
pub struct HealthResponse {
    pub status: &'static str,
    pub version: &'static str,
}

pub async fn health_check() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok",
        version: env!("CARGO_PKG_VERSION"),
    })
}
```

**Step 2: Update handlers mod.rs**

```rust
// src/handlers/mod.rs
pub mod challenges;
pub mod health;
pub mod join;
pub mod leaderboard;
pub mod progress;

pub use challenges::*;
pub use health::*;
pub use join::*;
pub use leaderboard::*;
pub use progress::*;
```

**Step 3: Verify it compiles**

Run: `cargo build`
Expected: Compiles successfully

**Step 4: Commit**

```bash
git add src/handlers
git commit -m "feat: add health check endpoint"
```

---

## Task 12: Router and Server Setup

**Files:**
- Modify: `src/main.rs`

**Step 1: Rewrite main.rs with full server setup**

```rust
// src/main.rs
mod auth;
mod config;
mod db;
mod error;
mod handlers;
mod models;

use std::net::SocketAddr;

use axum::{
    middleware,
    routing::{delete, get, post, put},
    Router,
};
use sqlx::postgres::PgPoolOptions;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use config::Config;

#[tokio::main]
async fn main() {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "challenges_server=debug,tower_http=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Load configuration
    dotenvy::dotenv().ok();
    let config = Config::from_env().expect("Failed to load configuration");

    // Create database pool
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&config.database_url)
        .await
        .expect("Failed to connect to database");

    // Run migrations
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("Failed to run migrations");

    tracing::info!("Database connected and migrations complete");

    // Build router
    let app = create_router(pool.clone(), config.admin_token.clone());

    // Start server
    let addr = SocketAddr::from(([0, 0, 0, 0], config.port));
    tracing::info!("Starting server on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

fn create_router(pool: sqlx::PgPool, admin_token: String) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    // Public routes
    let public_routes = Router::new()
        .route("/challenges", get(handlers::list_challenges))
        .route("/challenges/{id}", get(handlers::get_challenge))
        .route("/challenges/{id}/join", post(handlers::join_challenge))
        .route("/challenges/{id}/leaderboard", get(handlers::get_leaderboard))
        .route("/health", get(handlers::health_check))
        .layer(middleware::from_fn_with_state(
            pool.clone(),
            auth::optional_auth,
        ));

    // Authenticated routes
    let auth_routes = Router::new()
        .route("/challenges/{id}/progress", post(handlers::report_progress))
        .route("/challenges/{id}/progress", get(handlers::get_progress))
        .route("/challenges/{id}/leave", delete(handlers::leave_challenge))
        .layer(middleware::from_fn_with_state(
            pool.clone(),
            auth::require_auth,
        ));

    // Admin routes
    let admin_routes = Router::new()
        .route("/admin/challenges", post(handlers::create_challenge))
        .route("/admin/challenges/{id}", put(handlers::update_challenge))
        .route("/admin/challenges/{id}", delete(handlers::delete_challenge))
        .layer(middleware::from_fn_with_state(
            admin_token,
            auth::require_admin,
        ));

    Router::new()
        .nest("/v1", public_routes)
        .nest("/v1", auth_routes)
        .nest("/v1", admin_routes)
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .with_state(pool)
}
```

**Step 2: Verify it compiles**

Run: `cargo build`
Expected: Compiles successfully

**Step 3: Commit**

```bash
git add src/main.rs
git commit -m "feat: add router and server setup with all routes"
```

---

## Task 13: Integration Testing

**Files:**
- Create: `tests/integration_test.rs`

**Step 1: Create basic integration test**

```rust
// tests/integration_test.rs
use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use tower::ServiceExt;

// Integration tests would go here
// For now, just verify the crate compiles with test configuration

#[test]
fn test_placeholder() {
    assert!(true);
}
```

**Step 2: Run tests**

Run: `cargo test`
Expected: Tests pass

**Step 3: Commit**

```bash
git add tests
git commit -m "test: add integration test placeholder"
```

---

## Task 14: Final Documentation Update

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update CLAUDE.md with implementation details**

Add to the end of CLAUDE.md:

```markdown
## Implementation Status

### Completed
- Database schema with migrations
- Configuration from environment variables
- Error types with JSON responses
- Models for challenges, participants, progress
- Device token generation and validation
- Auth middleware (optional, required, admin)
- Database layer for all entities
- HTTP handlers for all public endpoints
- HTTP handlers for admin CRUD
- Router with middleware stack
- Health check endpoint

### Endpoints Implemented
- `GET /v1/challenges` - List challenges
- `GET /v1/challenges/{id}` - Get challenge details
- `POST /v1/challenges/{id}/join` - Join challenge
- `POST /v1/challenges/{id}/progress` - Report progress (auth required)
- `GET /v1/challenges/{id}/progress` - Get own progress (auth required)
- `GET /v1/challenges/{id}/leaderboard` - Get leaderboard
- `DELETE /v1/challenges/{id}/leave` - Leave challenge (auth required)
- `GET /v1/health` - Health check
- `POST /v1/admin/challenges` - Create challenge (admin)
- `PUT /v1/admin/challenges/{id}` - Update challenge (admin)
- `DELETE /v1/admin/challenges/{id}` - Delete challenge (admin)

### Not Yet Implemented
- Badge upload/retrieval
- Invite token generation
- Challenge snapshots
- Rate limiting middleware
- Token revocation endpoint
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with implementation status"
```

---

## Summary

This plan implements the core challenges server with:

1. **Database**: PostgreSQL schema with all tables
2. **Auth**: Device token generation and validation
3. **API**: All public and admin endpoints
4. **Models**: Request/response types with serde
5. **Error handling**: Consistent JSON error responses

**Not included in this plan** (future work):
- Badge image upload/storage
- Invite token generation/validation
- Rate limiting middleware
- Challenge snapshot creation
- Full integration test suite

After completing these tasks, the server will be functional for:
- Creating and managing challenges (admin)
- Joining challenges
- Reporting and viewing progress
- Viewing leaderboards
