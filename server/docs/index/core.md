# Core Index

Entry point, configuration, and error handling.

## Files

### `src/main.rs`
Application entry point and router setup.

**Exports:**
- `async fn main()` - Initialize tracing, load config, connect to database, run migrations, start server
- `fn create_router()` - Build Axum router with all routes and middleware

**Route Groups:**
- Public routes (optional auth): `/v1/challenges`, `/v1/challenges/:id`, `/v1/challenges/:id/join`, `/v1/challenges/:id/leaderboard`, `/v1/badges/:id/image`, `/v1/programs`, `/v1/programs/:slug`, `/v1/health`
- Authenticated routes (require auth): `/v1/challenges/:id/progress`, `/v1/challenges/:id/leave`, `/v1/friends/invite-link`, `/v1/friends/requests`
- Admin routes (require admin token): `/v1/admin/challenges`, `/v1/admin/challenges/:id`, `/v1/admin/challenges/:id/badges`, `/v1/admin/badges/:id`, `/v1/admin/challenges/:id/invites`, `/v1/admin/invites/:token`
- Static files: Fallback to `web/dist/` with SPA routing support

### `src/config.rs`
Environment variable configuration.

**Exports:**
- `struct Config` - Application configuration with database_url, admin_token, port, base_url, invite_base_url, invite_expiry_days, polish_park_boundaries_*, snapshot_* fields
- `impl Config::from_env()` - Load config from environment variables
- `enum ConfigError` - Configuration errors (Missing, Invalid)
- `enum LogFormat` (Json default | Pretty | Compact) - `LogFormat::from_env()` reads `LOG_FORMAT` independently of `Config` (needed before the subscriber exists); returns the raw value too when unrecognised so `observability::init_tracing` can warn

**Environment Variables:**
- `DATABASE_URL` - Required, Postgres connection string
- `ADMIN_TOKEN` - Required, admin API authentication
- `PORT` - Optional, default 8080
- `BASE_URL` - Optional, for generating URLs
- `INVITE_BASE_URL` - Optional, default "https://activities.carrierwave.app", base URL for friend invite links
- `INVITE_EXPIRY_DAYS` - Optional, default 7, how long friend invite links are valid
- `LOG_FORMAT` - Optional, default `json`; `pretty`/`compact` for local dev (see `docs/logging.md`)

### `src/observability.rs`
Structured logging + request correlation (CAR-156).

**Exports:**
- `fn init_tracing(format, unrecognized)` - Install the global subscriber (`RUST_LOG` filter, default `info,activities_server=debug`); warns on bad `LOG_FORMAT`
- `fn subscriber(format, filter, writer)` - Build the subscriber with a custom `MakeWriter` (tests capture JSON into a buffer). JSON = `.json().flatten_event(true).with_current_span(true)`
- `fn instrument(router)` - Wrap the outermost router: `SetRequestIdLayer(MakeRequestUuid)` → `PropagateRequestIdLayer` → `request_log`
- `async fn request_log()` - Middleware opening `info_span!("request", request_id, method, path, route)` and emitting one `"request completed"` line with `status`, `latency_ms` (DEBUG for `/v1/health` and `/metrics`, INFO otherwise)
- `REQUEST_ID_HEADER` - `x-request-id`

### `src/metrics.rs`
Prometheus metrics constants, middleware, and background tasks.

**Exports:**
- `fn install()` - Install Prometheus recorder, return render handle
- `async fn http_metrics()` - Axum middleware recording request count, duration, in-flight gauge
- `fn spawn_pool_metrics()` - Background task recording DB pool metrics every 15s
- `fn spawn_rbn_metrics()` - Background task recording RBN buffer size every 15s

**Metric Constants:**
- `GIS_FETCH_TOTAL` - Counter: GIS fetch attempts (labels: source, result)
- `GIS_FETCH_DURATION_SECONDS` - Histogram: GIS fetch latency (labels: source)
- `GIS_BOUNDARIES_CACHED_TOTAL` - Gauge: park boundaries cached
- `GIS_TRAILS_CACHED_TOTAL` - Gauge: historic trails cached
- `GIS_BATCH_DURATION_SECONDS` - Histogram: batch sync duration (labels: aggregator)
- `SYNC_LAST_COMPLETED_TIMESTAMP` - Gauge: Unix timestamp of last completed sync cycle (labels: aggregator)
- `SYNC_ERRORS_TOTAL` - Counter: sync errors across all background processes (labels: aggregator)
- `HTTP_REQUESTS_TOTAL` - Counter: HTTP requests (labels: method, path, status)
- `HTTP_REQUEST_DURATION_SECONDS` - Histogram: HTTP request latency (labels: method, path, status)
- `HTTP_REQUESTS_IN_FLIGHT` - Gauge: current in-flight HTTP requests (labels: method, path)
- `DB_POOL_CONNECTIONS` - Gauge: total DB connections
- `DB_POOL_IDLE_CONNECTIONS` - Gauge: idle DB connections
- `DB_POOL_SIZE` - Gauge: DB pool size
- `RBN_SPOTS_BUFFERED` - Gauge: RBN spots in buffer
- `RBN_SPOTS_INGESTED_TOTAL` - Counter: spots ingested from RBN telnet stream (labels: mode, band)
- `RBN_SPOT_SNR` - Histogram: signal-to-noise ratio distribution (labels: mode)
- `RBN_SPOT_WPM` - Histogram: CW speed (words per minute) distribution

### `src/snapshots.rs`
Periodic disk snapshots of aggregated data (parks, GIS, statistics).

**Exports:**
- `struct SnapshotManifest` - Envelope with version, timestamp, and row counts (Serialize, Deserialize)
- `struct ParkSnapshot` - Serializable POTA park row (Serialize, Deserialize, FromRow)
- `struct ActivationSnapshot` - Serializable activation row (Serialize, Deserialize, FromRow)
- `struct HunterQsoSnapshot` - Serializable hunter QSO row (Serialize, Deserialize, FromRow)
- `struct FetchStatusSnapshot` - Serializable fetch status row (Serialize, Deserialize, FromRow)
- `struct BoundarySnapshot` - Serializable park boundary row with GeoJSON geometry (Serialize, Deserialize, FromRow)
- `struct TrailSnapshot` - Serializable historic trail row with GeoJSON geometry (Serialize, Deserialize, FromRow)
- `async fn save_snapshot()` - Export all aggregated tables to JSON files in a directory
- `async fn try_restore()` - Restore from snapshot if tables are empty and snapshot is within max age
- `async fn snapshot_loop()` - Background task that saves snapshots at a configurable interval

**Environment Variables:**
- `SNAPSHOT_ENABLED` - Optional, default true
- `SNAPSHOT_DIR` - Optional, default "data/snapshots"
- `SNAPSHOT_INTERVAL_HOURS` - Optional, default 1
- `SNAPSHOT_MAX_AGE_HOURS` - Optional, default 24

### `src/error.rs`
Application error types with HTTP responses.

**Exports:**
- `enum AppError` - All application error variants
- `impl IntoResponse for AppError` - Convert errors to JSON HTTP responses

**Error Variants:**
- `ProgramNotFound` - 404, slug in details
- `ChallengeNotFound` - 404, challenge_id in details
- `BadgeNotFound` - 404, badge_id in details
- `InviteNotFound` - 404, token in details
- `UserNotFound` - 404, user_id in details
- `FriendInviteNotFound` - 404, token in details (expired or not found)
- `FriendInviteUsed` - 410 Gone, token in details
- `AlreadyJoined` - 409 Conflict
- `AlreadyFriends` - 409 Conflict
- `FriendRequestExists` - 409 Conflict
- `CannotFriendSelf` - 422 Unprocessable Entity
- `NotParticipating` - 403 Forbidden
- `InviteRequired` - 403 Forbidden
- `InviteExpired` - 403 Forbidden
- `InviteExhausted` - 403 Forbidden
- `MaxParticipants` - 403 Forbidden
- `ChallengeEnded` - 400 Bad Request
- `InvalidToken` - 401 Unauthorized
- `RateLimited` - 429 Too Many Requests
- `Validation` - 400 Bad Request with message
- `Database` - 500 Internal (from sqlx::Error)
- `Internal` - 500 Internal with message
