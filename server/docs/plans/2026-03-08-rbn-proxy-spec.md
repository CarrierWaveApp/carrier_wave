# RBN Proxy API — Design Spec

**Date:** 2026-03-08
**Purpose:** Replace CarrierWave's dependency on Vail ReRBN (vailrerbn.com) with an RBN proxy built into activities-server. Ingests the RBN telnet stream, holds 1 hour of spots in memory, and serves a REST API matching CarrierWave's actual usage patterns.

---

## Architecture

```
┌──────────────────┐       ┌─────────────────────────────────────┐
│  RBN Telnet      │       │  activities-server                  │
│  telnet.reverse  │       │                                     │
│  beacon.net:7000 │──TCP──▶  RbnIngester (background task)      │
└──────────────────┘       │    │                                │
                           │    ▼                                │
                           │  SpotStore (in-memory, 1hr ring)    │
                           │    │                                │
                           │    ▼                                │
                           │  /v1/rbn/* handlers                 │
                           └─────────────────────────────────────┘
```

**Key decisions:**
- **In-memory only.** No database table. Spots older than 1 hour are evicted.
- **Single telnet connection.** Reconnects with exponential backoff on disconnect.
- **No persistence across restarts.** The store refills within seconds from the live stream (~5,000+ spots/minute globally).

---

## RBN Telnet Protocol

### Connection

```
Host: telnet.reversebeacon.net
Port: 7000
```

After connecting, the server sends a login prompt. Send a callsign (any valid call works as a "viewer" login):

```
callsign: → send "N0CALL\n"
```

The server then streams spots as newline-delimited text.

### Spot Line Format

```
DX de KM3T-#:     14039.8  W1AW           CW    18 dB  25 WPM  CQ      1832Z
```

Fields (fixed-width columns):
| Field | Position | Description |
|-------|----------|-------------|
| Spotter | after `DX de ` | Skimmer callsign (e.g. `KM3T-#`) |
| Frequency | next field | kHz with decimal (e.g. `14039.8`) |
| Callsign | next field | Spotted station |
| Mode | next field | CW, RTTY, FT8, FT4, PSK31, etc. |
| SNR | `nn dB` | Signal-to-noise ratio |
| WPM | `nn WPM` | Speed (CW only, absent for digital) |
| Type | next field | CQ, BEACON, NCDXF, DX, etc. |
| Time | `nnnnZ` | UTC time (HHMM) |

### Parsing Strategy

Use a regex or fixed-offset parser. Filter to `CQ` and `DX` spot types (skip `BEACON`, `NCDXF`). The `-#` suffix on spotter callsigns indicates a skimmer (multi-decoder instance number).

### Environment Configuration

| Variable | Required | Description |
|----------|----------|-------------|
| `RBN_ENABLED` | No | `true` to enable ingestion (default `false`) |
| `RBN_CALLSIGN` | If enabled | Callsign to use for telnet login (default: `W6JSV`) |

When `RBN_ENABLED` is false, the `/v1/rbn/*` endpoints return 503 Service Unavailable.

---

## SpotStore Design

### Data Structure

```rust
struct RbnSpot {
    id: u64,                    // Monotonic counter
    callsign: String,           // Spotted station (uppercased)
    frequency: f64,             // kHz
    mode: String,               // CW, FT8, etc.
    snr: i32,                   // dB
    wpm: Option<u16>,           // CW speed
    spotter: String,            // Skimmer callsign
    timestamp: DateTime<Utc>,   // Derived from HHMM + current UTC date
    band: String,               // Derived from frequency (e.g. "20m")
}
```

### Storage

```rust
struct SpotStore {
    spots: RwLock<VecDeque<RbnSpot>>,
    next_id: AtomicU64,
}
```

- **Write path:** Push to back of VecDeque. Evict from front while `front.timestamp < now - 1 hour`.
- **Read path:** RwLock read guard → scan/filter the VecDeque. At ~300K spots/hour peak, linear scan is fast enough (<1ms).
- **Band derivation:** Frequency-to-band lookup table applied at ingestion time.

### Concurrency

- Ingester holds write lock briefly to push batches (~100 spots) and evict stale entries.
- HTTP handlers hold read lock for queries.
- No contention concerns at expected load (few req/s from a handful of app instances).

---

## API Endpoints

**Base path:** `/v1/rbn`

### GET /v1/rbn/spots

Query spots with filters. All parameters optional.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `call` | string | — | Filter by spotted callsign (exact, case-insensitive) |
| `spotter` | string | — | Filter by skimmer callsign |
| `mode` | string | — | Comma-separated modes: `CW,FT8,RTTY` |
| `band` | string | — | Single band: `20m`, `40m`, etc. |
| `min_freq` | f64 | — | Minimum frequency (kHz) |
| `max_freq` | f64 | — | Maximum frequency (kHz) |
| `since` | ISO8601 | 1 hour ago | Only spots after this time |
| `limit` | u32 | 100 | Max results (1–500) |

**Response:**
```json
{
  "total": 42,
  "spots": [
    {
      "id": 928371,
      "callsign": "W1AW",
      "frequency": 14039.8,
      "mode": "CW",
      "snr": 18,
      "wpm": 25,
      "spotter": "KM3T-#",
      "band": "20m",
      "timestamp": "2026-03-08T18:32:00Z"
    }
  ]
}
```

Spots returned in reverse chronological order (newest first). `total` is the count of matching spots (before `limit` is applied).

**CarrierWave usage mapping:**
- `RBNClient.spots(for: callsign)` → `?call=W1AW&since=...&limit=50`
- `RBNClient.spots(band:mode:since:)` → `?band=40m&mode=CW&since=...`
- `RBNClient.spots(minFreq:maxFreq:)` → `?min_freq=7048&max_freq=7052`
- `RBNClient.spots(spotter:since:)` → `?spotter=KM3T&since=...`

### GET /v1/rbn/stats

Aggregate statistics over a time window.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `minutes` | u32 | 60 | Time window (1–60) |

**Response:**
```json
{
  "minutes": 60,
  "total_spots": 28431,
  "spots_per_minute": 473.8,
  "bands": {
    "20m": 8230,
    "40m": 6102,
    "15m": 4891,
    "10m": 3440,
    "80m": 2901,
    "30m": 1544,
    "17m": 892,
    "160m": 231,
    "12m": 134,
    "6m": 66
  },
  "modes": {
    "CW": 18200,
    "FT8": 7431,
    "RTTY": 1890,
    "FT4": 910
  }
}
```

### GET /v1/rbn/skimmers

Active skimmers in the time window.

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `minutes` | u32 | 60 | Time window (1–60) |
| `limit` | u32 | 100 | Max results (1–500) |

**Response:**
```json
{
  "minutes": 60,
  "count": 87,
  "skimmers": [
    {
      "callsign": "KM3T-#",
      "spot_count": 1243,
      "last_spot": "2026-03-08T18:32:00Z",
      "bands": ["20m", "40m", "15m"]
    }
  ]
}
```

Sorted by `spot_count` descending.

---

## Ingester Design

### Lifecycle

```
1. Server starts
2. If RBN_ENABLED=true, spawn tokio task: rbn_ingester(spot_store)
3. Connect to telnet.reversebeacon.net:7000
4. Send login callsign
5. Read lines in a loop:
   a. Parse spot line → RbnSpot
   b. Push to SpotStore (batch of ~100 or every 500ms, whichever first)
   c. Evict expired spots during push
6. On disconnect: log warning, backoff (1s, 2s, 4s, 8s... max 60s), reconnect
7. On server shutdown: drop the task (tokio cancellation)
```

### Error Handling

| Scenario | Behavior |
|----------|----------|
| Connection refused | Retry with backoff |
| Parse error on a line | Log at debug level, skip line |
| Login prompt not received | Timeout after 10s, reconnect |
| Spot store lock poisoned | Panic (unrecoverable) |

### Health Integration

The existing `GET /v1/health` endpoint should include RBN status:

```json
{
  "status": "ok",
  "rbn": {
    "enabled": true,
    "connected": true,
    "spots_in_store": 142831,
    "oldest_spot": "2026-03-08T17:33:00Z",
    "spots_per_minute": 473.8
  }
}
```

---

## Implementation Plan

### Phase 1: Ingester + SpotStore

1. Add `RbnSpot` struct and `SpotStore` with `RwLock<VecDeque>`
2. Add telnet line parser (regex-based)
3. Add `rbn_ingester` background task with reconnect logic
4. Wire into server startup (gated on `RBN_ENABLED`)
5. Add RBN status to health endpoint

### Phase 2: API Endpoints

6. `GET /v1/rbn/spots` with all filter params
7. `GET /v1/rbn/stats` with aggregation
8. `GET /v1/rbn/skimmers` with grouping
9. Add to router

### Phase 3: Deployment

10. Add `RBN_ENABLED` and `RBN_CALLSIGN` to Ansible env template
11. Deploy and verify

### Phase 4: CarrierWave Migration

12. Update `RBNClient.swift` base URL to `activities.carrierwave.app/v1/rbn`
13. Adjust response model mappings (minor field name differences)
14. Remove ReRBN dependency

---

## Differences from ReRBN

| Feature | ReRBN | This API |
|---------|-------|----------|
| Historical data | Hours/days | 1 hour max |
| `/charts` endpoint | Yes | No (not used) |
| `/bands` endpoint | Yes | No (not used) |
| `offset` pagination | Yes | No (not needed) |
| `after_id` cursor | Yes | No (not needed) |
| `until` parameter | Yes | No (always "up to now") |
| `hours` parameter | Yes | `minutes` (more granular) |
| `spotter_grid` field | Yes | No (CarrierWave gets grids from HamDB) |
| Rate limit headers | Yes | Yes (reuse existing middleware) |

---

## Resolved Questions

1. **Login callsign** — Use `W6JSV`. Configured via `RBN_CALLSIGN` env var.
2. **Spot type filtering** — Keep only `CQ` and `DX` types. BEACON/NCDXF are automated propagation beacons, not workable stations — CarrierWave uses spots to find stations to QSO with.
3. **Memory budget** — ~60MB is acceptable on the Hetzner VPS.
