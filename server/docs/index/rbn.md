# RBN Proxy Index

In-memory RBN (Reverse Beacon Network) proxy. Connects to the RBN telnet stream, stores spots for 1 hour, and serves them via REST API.

## Files

### `src/rbn/mod.rs`
Module declarations and re-exports.

**Exports:**
- Re-exports `spawn_rbn_ingester` from `ingester`
- Re-exports `RbnSpot`, `SpotStore` from `store`

### `src/rbn/store.rs`
In-memory spot storage with query, stats, and skimmer aggregation.

**Exports:**
- `struct RbnSpot` - Single spot (id, callsign, frequency, mode, snr, wpm, spotter, band, timestamp)
- `struct SpotStore` - Thread-safe in-memory store (`Arc<RwLock<VecDeque<RbnSpot>>>`)
- `struct SpotFilter` - Query filter parameters
- `struct StatsResult` - Aggregate stats response (total, rate, band/mode counts)
- `struct SkimmersResult` - Skimmer list response
- `struct SkimmerInfo` - Single skimmer info (callsign, count, last_spot, bands)
- `fn freq_to_band()` - Frequency (kHz) to band string lookup

### `src/rbn/ingester.rs`
Telnet connection, line parsing, and background ingestion task.

**Exports:**
- `fn spawn_rbn_ingester()` - Spawn background tokio task for telnet ingestion

**Internal:**
- `async fn ingester_loop()` - Reconnect loop with exponential backoff (1s–60s)
- `async fn run_connection()` - Single telnet session: login, read lines, batch-push spots
- `fn parse_spot_line()` - Parse `DX de ...` telnet lines into `RbnSpot`

**Tests:**
- `test_parse_cw_spot` - CW spot with WPM
- `test_parse_ft8_spot` - FT8 spot without WPM
- `test_parse_beacon_filtered` - BEACON type filtered out
- `test_parse_non_spot_line` - Non-spot lines ignored
