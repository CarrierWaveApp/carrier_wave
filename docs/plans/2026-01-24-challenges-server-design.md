# Challenges Server Design

## Overview

A self-hostable Rust/Axum HTTP API server for the FullDuplex challenges feature. Enables ham radio operators to track progress toward awards (DXCC, WAS, POTA milestones) with leaderboards and optional time-limited competitions.

The official FullDuplex challenges server is just one deployment of this codebase - clubs and community authors can run their own instances.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  FullDuplex     │     │  Challenges     │     │  PostgreSQL     │
│  iOS App        │────▶│  Server (Axum)  │────▶│  Database       │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌─────────────────┐
                        │  Web            │
                        │  Configurator   │
                        │  (separate)     │
                        └─────────────────┘
```

### Key Decisions

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Database | PostgreSQL | Concurrent leaderboard queries, window functions for ranking |
| Auth | Callsign + device token | Low friction, no account creation, matches LoFi pattern |
| Real-time | Polling | Simpler than WebSockets, 30s refresh is sufficient |
| Challenge storage | Database only | API-first, supports badge uploads, versioning |
| Deployment | Docker + env vars | Standard 12-factor, works everywhere |

### Dependencies

| Crate | Purpose |
|-------|---------|
| `axum` | HTTP framework |
| `sqlx` | Async PostgreSQL with compile-time query checking |
| `tokio` | Async runtime |
| `serde` / `serde_json` | JSON serialization |
| `tower-http` | CORS, tracing, rate limiting middleware |
| `uuid` | ID generation |
| `chrono` | Timestamp handling |
| `thiserror` | Error types |
| `tracing` | Structured logging |

---

## Database Schema

```sql
-- Challenge definitions (created by admins/authors)
CREATE TABLE challenges (
    id              UUID PRIMARY KEY,
    version         INT NOT NULL DEFAULT 1,
    name            TEXT NOT NULL,
    description     TEXT NOT NULL,
    author          TEXT,
    category        TEXT NOT NULL,  -- 'award', 'event', 'club', 'personal', 'other'
    challenge_type  TEXT NOT NULL,  -- 'collection', 'cumulative', 'timeBounded'
    configuration   JSONB NOT NULL, -- goals, tiers, criteria, scoring, time constraints
    invite_config   JSONB,          -- max participants, expiry, requires token
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
    last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(callsign, device_token)
);
CREATE INDEX idx_participants_callsign ON participants(callsign);

-- Challenge participation (join table)
CREATE TABLE challenge_participants (
    id              UUID PRIMARY KEY,
    challenge_id    UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    callsign        TEXT NOT NULL,
    invite_token    TEXT,
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    status          TEXT NOT NULL DEFAULT 'active',  -- 'active', 'left', 'completed'
    UNIQUE(challenge_id, callsign)
);

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
CREATE INDEX idx_progress_leaderboard ON progress(challenge_id, score DESC);

-- Badges (uploaded images)
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

-- Frozen snapshots for ended time-bounded challenges
CREATE TABLE challenge_snapshots (
    id              UUID PRIMARY KEY,
    challenge_id    UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    ended_at        TIMESTAMPTZ NOT NULL,
    final_standings JSONB NOT NULL,
    statistics      JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Invite tokens for private challenges
CREATE TABLE invite_tokens (
    token           TEXT PRIMARY KEY,
    challenge_id    UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    max_uses        INT,
    use_count       INT NOT NULL DEFAULT 0,
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

---

## API Endpoints

### Public Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/v1/challenges` | None | List challenges with filters |
| `GET` | `/v1/challenges/{id}` | None | Get challenge definition |
| `POST` | `/v1/challenges/{id}/join` | None* | Join challenge, receive device token |
| `POST` | `/v1/challenges/{id}/progress` | Token | Report progress |
| `GET` | `/v1/challenges/{id}/progress` | Token | Get own progress |
| `GET` | `/v1/challenges/{id}/leaderboard` | None | Get leaderboard |
| `DELETE` | `/v1/challenges/{id}/leave` | Token | Leave challenge |
| `GET` | `/v1/challenges/{id}/snapshot` | None | Get frozen standings |
| `GET` | `/v1/badges/{id}/image` | None | Get badge image |
| `GET` | `/v1/health` | None | Health check |

*Join returns a new device token if callsign doesn't have one.

### Admin Endpoints

Require `Authorization: Bearer {ADMIN_TOKEN}`:

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/admin/challenges` | Create challenge |
| `PUT` | `/v1/admin/challenges/{id}` | Update challenge |
| `DELETE` | `/v1/admin/challenges/{id}` | Delete challenge |
| `POST` | `/v1/admin/challenges/{id}/badges` | Upload badge |
| `DELETE` | `/v1/admin/badges/{id}` | Delete badge |
| `POST` | `/v1/admin/challenges/{id}/invites` | Generate invite token |
| `DELETE` | `/v1/admin/participants/{callsign}/tokens` | Revoke device tokens |
| `POST` | `/v1/admin/challenges/{id}/end` | End challenge, create snapshot |

### Rate Limits

| Endpoint Pattern | Limit |
|------------------|-------|
| `GET /challenges` | 60/min |
| `GET /challenges/{id}` | 120/min |
| `POST /progress` | 30/min |
| `GET /leaderboard` | 60/min |
| Admin endpoints | 30/min |

Headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`

---

## Authentication Flow

### Device Token Lifecycle

1. **First join**: Client sends callsign + device name, server generates token `fd_{32 random chars}`, stores in DB, returns to client
2. **Subsequent requests**: Client includes `Authorization: Bearer fd_xxx` header
3. **Multiple devices**: Each device gets its own token, all tied to same callsign
4. **Token validation**: Middleware extracts callsign from token, attaches to request context
5. **Revocation**: Admin can revoke all tokens for a callsign

### Token Format

```
fd_{32 alphanumeric characters}
```

Prefix `fd_` identifies FullDuplex challenge tokens.

---

## Progress & Scoring

### Client Reports Progress

```json
POST /v1/challenges/{id}/progress
{
  "completedGoals": ["US-CA", "US-NY", "US-TX"],
  "currentValue": 47,
  "qualifyingQsoCount": 52,
  "lastQsoDate": "2025-01-15T18:30:00Z"
}
```

### Server Calculates Score

```rust
fn calculate_score(challenge: &Challenge, progress: &Progress) -> i32 {
    match challenge.scoring.method {
        ScoringMethod::Percentage => {
            let total = challenge.goals.items.len();
            (progress.completed_goals.len() * 100 / total) as i32
        }
        ScoringMethod::Count => progress.current_value,
        ScoringMethod::Points => {
            progress.completed_goals.iter()
                .map(|g| challenge.scoring.weight_for(g))
                .sum()
        }
    }
}
```

### Leaderboard Query

```sql
SELECT
    callsign,
    score,
    current_tier,
    completed_goals,
    RANK() OVER (ORDER BY score DESC, updated_at ASC) as rank
FROM progress
WHERE challenge_id = $1
ORDER BY rank
LIMIT $2 OFFSET $3
```

---

## Error Handling

### Error Response Format

```json
{
  "error": {
    "code": "CHALLENGE_NOT_FOUND",
    "message": "The requested challenge does not exist",
    "details": { "challengeId": "abc-123" }
  }
}
```

### Error Codes

| Code | HTTP | Description |
|------|------|-------------|
| `CHALLENGE_NOT_FOUND` | 404 | Challenge ID doesn't exist |
| `ALREADY_JOINED` | 409 | Callsign already in this challenge |
| `NOT_PARTICIPATING` | 403 | Must join before reporting progress |
| `INVITE_REQUIRED` | 403 | Challenge requires invite token |
| `INVITE_EXPIRED` | 403 | Invite token past expiry date |
| `INVITE_EXHAUSTED` | 403 | Invite token max uses reached |
| `MAX_PARTICIPANTS` | 403 | Challenge at participant limit |
| `CHALLENGE_ENDED` | 400 | Cannot join/report on ended challenge |
| `INVALID_TOKEN` | 401 | Device token invalid or revoked |
| `RATE_LIMITED` | 429 | Too many requests |
| `VALIDATION_ERROR` | 400 | Invalid request body |
| `INTERNAL_ERROR` | 500 | Server error |

---

## Project Structure

```
fullduplex-challenges/
├── Cargo.toml
├── Cargo.lock
├── .env.example
├── docker-compose.yml
├── Dockerfile
├── README.md
├── migrations/
│   ├── 001_initial_schema.sql
│   └── ...
└── src/
    ├── main.rs
    ├── config.rs
    ├── error.rs
    ├── auth/
    │   ├── mod.rs
    │   ├── middleware.rs
    │   └── token.rs
    ├── db/
    │   ├── mod.rs
    │   ├── challenges.rs
    │   ├── participants.rs
    │   ├── progress.rs
    │   ├── badges.rs
    │   └── snapshots.rs
    ├── models/
    │   ├── mod.rs
    │   ├── challenge.rs
    │   ├── participant.rs
    │   ├── progress.rs
    │   └── badge.rs
    ├── handlers/
    │   ├── mod.rs
    │   ├── challenges.rs
    │   ├── join.rs
    │   ├── progress.rs
    │   ├── leaderboard.rs
    │   └── admin.rs
    ├── scoring/
    │   ├── mod.rs
    │   └── calculator.rs
    └── middleware/
        ├── mod.rs
        ├── rate_limit.rs
        └── admin_auth.rs
```

---

## Configuration

### Environment Variables

```bash
# Required
DATABASE_URL=postgres://user:pass@localhost:5432/challenges
ADMIN_TOKEN=your-secret-admin-token-here

# Optional
PORT=8080
BASE_URL=https://challenges.example.com
RUST_LOG=info
```

### Docker Compose (Development)

```yaml
version: "3.8"
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: challenges
      POSTGRES_PASSWORD: challenges
      POSTGRES_DB: challenges
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data

  server:
    build: .
    ports:
      - "8080:8080"
    environment:
      DATABASE_URL: postgres://challenges:challenges@db:5432/challenges
      ADMIN_TOKEN: dev-admin-token
      RUST_LOG: debug
    depends_on:
      - db

volumes:
  pgdata:
```

### Dockerfile

```dockerfile
FROM rust:1.75-alpine AS builder
WORKDIR /app
RUN apk add --no-cache musl-dev
COPY . .
RUN cargo build --release

FROM alpine:3.19
RUN apk add --no-cache ca-certificates
COPY --from=builder /app/target/release/fullduplex-challenges /usr/local/bin/
EXPOSE 8080
CMD ["fullduplex-challenges"]
```

---

## Scope

### In Scope (v1)

- All 3 challenge types (collection, cumulative, time-bounded)
- Tiers and badges
- Leaderboards with ranking
- Invite tokens for private challenges
- Historical snapshots for ended challenges
- Admin API for challenge management
- Rate limiting
- Docker deployment

### Out of Scope (v1)

- WebSocket real-time updates (polling is sufficient)
- HamAlert integration (handled app-side)
- Federation/discovery between servers
- Web configurator (separate project)
- LoTW/QSL confirmation requirements
