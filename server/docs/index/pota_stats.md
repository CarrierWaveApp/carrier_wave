# POTA Stats Index

POTA park statistics: park catalog, activation records, hunter QSOs, and rankings.

## Files

### `migrations/009_pota_park_stats.sql`
Database schema for POTA park stats caching.

**Tables:**
- `pota_parks` - Park catalog from CSV (reference, name, location, aggregate stats)
- `pota_activations` - Per-activation records (callsign, date, QSOs by mode)
- `pota_hunter_qsos` - Hunter QSO totals from leaderboard
- `pota_fetch_status` - Per-park fetch tracking timestamps

### `src/models/pota_stats.rs`
Data structures for POTA stats feature.

**POTA API types (upstream JSON):**
- `struct PotaApiStats` - Response from GET /park/stats/{ref}
- `struct PotaApiActivation` - Single activation from /park/activations/{ref}
- `struct PotaApiHunterQso` - Hunter entry from leaderboard
- `struct PotaApiLeaderboard` - Response from /park/leaderboard/{ref}
- `struct PotaCsvPark` - Row from all_parks_ext.csv

**DB row types:**
- `struct PotaParkRow` - pota_parks table row
- `struct PotaActivationRow` - pota_activations table row
- `struct PotaHunterQsoRow` - pota_hunter_qsos table row
- `struct RankedActivatorRow` - Activator with rank from window function
- `struct RankedActivatorByModeRow` - Activator ranked by single mode
- `struct RankedHunterRow` - Hunter with rank from window function
- `struct StateAggregateRow` - Aggregate state-level stats
- `struct TopCallsignRow` - Callsign + count for top lists
- `struct FreshnessRow` - Fetch freshness metadata
- `struct StaleParkRow` - Park reference for batch fetching

**Query params:**
- `struct ActivatorStatsQuery` - callsign, state, mode
- `struct HunterStatsQuery` - callsign, state
- `struct RankingsQuery` - state, limit, offset

**API responses:**
- `struct FreshnessInfo` - Oldest/newest fetch, pending count
- `struct QsosByMode` - CW, data, phone breakdown
- `struct RankedCallsignResponse` - Callsign + count
- `struct ActivatorStatsResponse` - Activator stats with rank and freshness
- `struct HunterStatsResponse` - Hunter stats with rank and freshness
- `struct StateStatsResponse` - State totals with top activators/hunters
- `struct ParkStatsResponse` - Park detail with top activators/hunters
- `struct ActivatorRankingEntry` - Single entry in rankings list
- `struct ActivatorRankingsResponse` - Paginated activator leaderboard
- `struct PotaSyncStatusResponse` - Sync progress with completion percentage

### `src/db/pota_stats.rs`
Database queries for POTA stats.

**Aggregator support:**
- `async fn upsert_park()` - Upsert park from CSV catalog
- `async fn ensure_fetch_status()` - Ensure fetch_status row exists
- `async fn get_stalest_parks()` - Get parks with oldest fetch timestamp (skips 3+ consecutive errors)
- `async fn count_parks()` - Count all imported parks
- `async fn count_unfetched_parks()` - Count never-fetched parks
- `async fn update_park_stats()` - Update park aggregate stats
- `async fn upsert_activation()` - Upsert single activation record
- `async fn upsert_hunter_qsos()` - Upsert hunter QSO record
- `async fn update_fetch_status()` - Mark park as fetched
- `async fn record_fetch_error()` - Record fetch error for park (increments consecutive_errors)
- `async fn reset_consecutive_errors()` - Reset error counters for all parks (called on catalog re-sync)

**API support:**
- `async fn get_activator_stats()` - Activator stats with rank (optional state filter)
- `async fn get_activator_stats_by_mode()` - Activator stats ranked by specific mode
- `async fn get_activator_rankings()` - Paginated activator leaderboard
- `async fn get_hunter_stats()` - Hunter stats with rank
- `async fn get_state_stats()` - Aggregate state-level stats
- `async fn get_state_top_activators()` - Top activators for a state
- `async fn get_state_top_hunters()` - Top hunters for a state
- `async fn get_state_freshness()` - Freshness info for a state
- `async fn get_park_detail()` - Single park row by reference
- `async fn get_park_top_activators()` - Top activators for a park
- `async fn get_park_top_hunters()` - Top hunters for a park
- `async fn get_park_freshness()` - Freshness info for a park
- `async fn get_activator_freshness()` - Freshness info (optional state scope)

### `src/aggregators/pota_stats.rs`
Background aggregator that fetches POTA park data.

**Exports:**
- `struct PotaStatsConfig` - Concurrency, batch size, cycle hours
- `async fn poll_loop()` - Main loop: sync catalog, fetch batches, sleep

**Internal functions:**
- `async fn sync_park_catalog()` - Fetch CSV, upsert parks for supported countries (US, UK, IT, PL)
- `async fn fetch_park_data()` - Fetch stats + activations + leaderboard for one park
- `async fn fetch_park_stats()` - GET /park/stats/{ref}
- `async fn fetch_park_activations()` - GET /park/activations/{ref}?count=all
- `async fn fetch_park_leaderboard()` - GET /park/leaderboard/{ref}?count=all

### `src/handlers/pota_stats.rs`
HTTP handlers for POTA stats API endpoints.

**Exports:**
- `async fn get_activator_stats()` - GET /v1/pota/stats/activator
- `async fn get_hunter_stats()` - GET /v1/pota/stats/hunter
- `async fn get_state_stats()` - GET /v1/pota/stats/state/:state
- `async fn get_park_stats()` - GET /v1/pota/stats/park/:reference
- `async fn get_activator_rankings()` - GET /v1/pota/stats/rankings/activators
- `async fn get_sync_status()` - GET /v1/pota/stats/status
