# Investigation: DX Spotting Site APIs

**Date:** 2026-03-20
**Status:** Resolved
**Outcome:** All three sources have usable JSON APIs suitable for aggregation in CW Sweep's SpotAggregator.

## Problem Statement

Research DX spotting site APIs to aggregate multiple sources into CW Sweep's SpotAggregator. Need structured data (JSON) with spot info including split/listening frequency data from comments.

## Source Comparison

| Feature | DX Summit | DXHeat | DXWatch |
|---------|-----------|--------|---------|
| **Endpoint** | `dxsummit.fi/api/v1/spots` | `dxheat.com/source/spots/` | `dxwatch.com/dxsd1/s.php` |
| **Method** | GET (JSON) | GET (JSON) | GET (JSON) |
| **Auth** | None | None | None (login for filters) |
| **CORS** | `Access-Control-Allow-Origin: *` | Untested | Untested |
| **Real-time** | Polling only | Socket.IO (`spots.dxheat.com`) | Polling only |
| **Comment field** | `info` | `Comment` | Index `[3]` in spot array |
| **Mode detection** | Not in response | `Mode` field (CW/USB/DIGITAL) | Not in response (derived from freq) |
| **Band** | Not in response | `Band` field (numeric: 10, 15, 20...) | Not in response |
| **Continent** | Not in response | `Continent_dx`, `Continent_spotter` | In `ci` lookup (index `[2]`) |
| **Grid locator** | Not in response | `DXLocator` | In `ci` lookup (index `[9]`) |
| **Country flag** | Not in response | `Flag` (2-char ISO) | In `ci` lookup (index `[3]`) |
| **LoTW status** | Not in response | `LOTW` (bool), `LOTW_Date` | Not in response |
| **eQSL status** | Not in response | `EQSL` (bool) | Not in response |
| **DX lat/lon** | `dx_latitude`, `dx_longitude` | Not in response (in `ci` for DXWatch) | In `ci` lookup (indices `[6]`, `[7]`) |
| **Spotter lat/lon** | `de_latitude`, `de_longitude` | Not in response | In `ci` lookup |
| **Default spots** | 20 | ~50 | 50 |

## DX Summit (dxsummit.fi) — JSON REST API

### Endpoint
```
GET http://www.dxsummit.fi/api/v1/spots
```

### Parameters
| Param | Type | Description | Example |
|-------|------|-------------|---------|
| `limit` | int | Max spots to return | `50` |
| `limit_time` | int | Max age in minutes | `10` |
| `include` | string | Band filter | `20` (for 20m) |
| `include_modes` | string | Mode filter (comma-separated) | `CW,PHONE` |

### Response Headers
```
Content-Type: application/json
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: DELETE, GET, POST, PUT
```

### JSON Schema
```json
{
  "id": 66418537,           // Unique spot ID (monotonically increasing)
  "dx_call": "PU2XLC",      // DX station callsign
  "de_call": "PD5SAP",      // Spotter callsign
  "frequency": 28074.0,     // Frequency in kHz (float)
  "time": "2026-03-20T14:19:15",  // ISO 8601 timestamp
  "info": "73's FT8 tnx",   // Free-text comment (nullable)
  "dx_country": "Brazil",   // DX station DXCC country name
  "dx_latitude": -23.55,    // DX station latitude
  "dx_longitude": 46.63,    // DX station longitude
  "de_latitude": 52.28,     // Spotter latitude
  "de_longitude": -5.47     // Spotter longitude
}
```

### Notable
- Simplest API, fewest fields
- Has CORS enabled — can be called from browser/macOS app
- No mode/band in response (must derive from frequency)
- No grid locator, no LoTW status
- `include` band filter doesn't actually filter (returned all-band spots when tested with `include=20`)
- `include_modes` works: `CW` returns CW spots, `PHONE` returns SSB

### Comment Field Examples (split/QSX info)
```
"TNX 579 GD UP1+"          → listening up 1 kHz
"up 5"                     → listening up 5 kHz
"QSX 14215"                → listening on 14215 kHz
"listening up 5-10"        → listening 5-10 kHz up
"BB-0038 POTA 90w"         → POTA reference
"FT8 -15dB 2280Hz"         → FT8 signal report
```

---

## DXHeat (dxheat.com) — JSON REST + Socket.IO

### Polling Endpoint
```
GET https://dxheat.com/source/spots/
```

### Parameters (from HTML data attributes)
| Param | Type | Description | Example |
|-------|------|-------------|---------|
| `limit` | int | Max spots | `50` |
| `b` | int | Band filter (meters) | `20` |
| `m` | string | Mode filter | `CW` |
| Combo | | Both work together | `b=10&m=CW` |

### Other Endpoints (from data attributes)
```
/source/spots/              — Spot data (JSON array)
/source/country/            — Country lookup (?q=CALLSIGN)
/source/checkspot/          — Spot validation
/heatmap/source/heatmap/    — Band activity heatmap
/db/                        — Database lookup (404)
/search/source/autocomplete_call/ — Callsign autocomplete
/wwv/source/                — WWV solar data
/clock/source/              — Server time
/chat/getmsgs               — Chat messages
```

### Real-Time: Socket.IO
```javascript
// Connection
socket = io($("body").data("node_url"))  // → https://spots.dxheat.com

// Events
socket.on("connect", function() { ... })
socket.on("message", function(message) {
    var header = $.parseJSON(message)[0]
    // Same JSON format as polling endpoint
})
socket.on("disconnect", function() { ... })
```

### JSON Schema (richest of all three)
```json
{
  "Nr": 66348825,               // Unique spot ID (monotonically increasing)
  "Spotter": "K2TQC",           // Spotter callsign
  "Frequency": "14074.0",       // Frequency in kHz (STRING, not float!)
  "DXCall": "EP2EAS",           // DX station callsign
  "Time": "14:19",              // Time (HH:MM only)
  "Date": "20/03/26",           // Date (DD/MM/YY)
  "Beacon": false,              // Is beacon
  "MM": false,                  // Maritime mobile
  "AM": false,                  // Aeronautical mobile
  "Valid": true,                // Spot validation status
  "DXHomecall": "EP2EAS",       // Resolved home callsign
  "Comment": "real??  1450Hz odd",  // Free-text comment
  "Flag": "ir",                 // 2-char country code (for flag icon)
  "Band": 20.0,                 // Band in meters (float)
  "Mode": "DIGITAL",            // Mode: CW, USB, DIGITAL
  "Continent_dx": "AS",         // DX continent
  "Continent_spotter": "NA",    // Spotter continent
  "DXLocator": "LM62MA",        // DX Maidenhead grid locator

  // Optional fields (present when available):
  "LOTW": true,                 // LoTW participant
  "LOTW_Date": "02/05/2026",    // Last LoTW upload date
  "EQSL": true                  // eQSL participant
}
```

### Notable
- **Richest data** of all three sources — includes mode, band, continent, grid, LoTW/eQSL
- Socket.IO for real-time push (avoids polling overhead)
- `Frequency` is a STRING (needs parsing)
- HTML entities in Comment field (e.g., `&#x27;` for `'`, `&lt;` for `<`)
- `Valid: false` means spot flagged as potentially invalid (pirate/busted call)
- Combined band+mode filtering works server-side

---

## DXWatch (dxwatch.com) — Compact JSON API

### Endpoint
```
GET https://dxwatch.com/dxsd1/s.php?s=0&r=50&d=1
```

### Parameters
| Param | Type | Description | Example |
|-------|------|-------------|---------|
| `s` | int | Last spot ID (0 for initial load) | `0` |
| `r` | int | Number of rows | `50` |
| `d` | int | Must be `1` for default/all spots | `1` |
| `fid` | int | Saved filter ID (requires login) | `87` |
| Additional | | Filter args appended as `&fargs` | `cdx=CY0S` |

### Other Endpoints
```
/dxsd1/s.php    — DX spots (JSON)
/dxsd1/sk.php   — RBN (skimmer) spots (JSON, same format)
/dxsd1/a.php    — Announcements (JSON)
/dxsd1/post.php — Submit spot (POST)
/dxsd1/c/lastfil.php — User's recent filters
/dxsd1/ck.php   — Cookie/session check (JSONP)
/dxsd1/wl.php   — Watchlist (JSONP)
/t.php          — Callsign tooltip info
/ping.php       — Keepalive
/cont_includes/propdata.php — Propagation data
/prop/e/ptp     — Point-to-point propagation
/cont_includes/status.php — Status (polled every 120s)
```

### JSON Schema
Response is an object with three keys: `s` (spots), `ci` (callsign info), `i18n` (translations).

**Spot array** (`s` key — keyed by spot ID):
```json
{
  "60152111": [
    "DL1HBT",      // [0] Spotter callsign
    18080.9,        // [1] Frequency in kHz (float)
    "CY0S",         // [2] DX callsign
    "up4.4",        // [3] Comment
    "1409z 20 Mar", // [4] Time string
    771,            // [5] Unknown (possibly age in seconds or spot source ID)
    27,             // [6] Band code (maps to g_b table in JS)
    1               // [7] Unknown flag (0 or 1)
  ]
}
```

**Band codes** (from JS `g_b` table):
```
3→160m, 7→80m, 12→40m, 17→30m, 22→20m, 27→17m,
32→15m, 37→12m, 42→10m, 50→6m, 62→2m
```

**Callsign info** (`ci` key — rich lookup data):
```json
{
  "CY0S": [
    "CY0",          // [0] DXCC prefix
    "Sable I.",     // [1] DXCC entity name
    "NA",           // [2] Continent
    "ca",           // [3] Country flag code
    9,              // [4] CQ zone
    5,              // [5] ITU zone
    43.9375,        // [6] Latitude
    -60.0417,       // [7] Longitude
    "",             // [8] State/region (for US/etc)
    "FN93XW",       // [9] Grid locator
    "",             // [10] Unknown
    "89",           // [11] DXCC entity number
    "NA-063"        // [12] IOTA reference (optional)
  ]
}
```

### Notable
- Compact array format (not named keys) — efficient but fragile
- Separate `ci` lookup provides rich DXCC/geo data per callsign
- Includes IOTA reference, CQ zone, ITU zone (unique to DXWatch)
- Band code requires mapping table (not direct meters value)
- No mode in response
- RBN spots available via parallel endpoint (`sk.php`)
- Initial load requires `d=1`; subsequent polls use `s=LASTID` for incremental updates
- JSONP support via `ck.php` callback

### Comment Field Examples
```
"up4.4"                     → listening 4.4 kHz up
"up1-4  nice sig"           → listening 1-4 kHz up
"QSX 7025.00"               → listening on 7025 kHz
"listening up"              → listening up (unspecified offset)
"simplx"                    → simplex (no split)
"FT8  F/H"                  → FT8 Fox/Hound mode
"USB GF25mc -> JJ16fj"      → USB with grid squares
"POTA GB-5157 POTA GB-1379" → Multiple POTA references
```

---

## Unified Spot Model

Proposed mapping from all three sources to a common `DXSpot` struct:

```swift
struct DXSpot: Identifiable, Sendable {
    let id: String              // Source-prefixed: "dxs:66418537", "dxh:66348825", "dxw:60152111"
    let source: SpotSource      // .dxSummit, .dxHeat, .dxWatch
    let dxCall: String          // All: dx_call / DXCall / s[2]
    let spotterCall: String     // All: de_call / Spotter / s[0]
    let frequency: Double       // All: frequency / Double(Frequency) / s[1]  (kHz)
    let timestamp: Date         // dxs: ISO 8601 / dxh: Date+Time / dxw: s[4] parsed
    let comment: String?        // All: info / Comment / s[3]

    // Enrichment (available from some sources, nil from others)
    let mode: String?           // dxh: Mode / others: derived from freq
    let band: Int?              // dxh: Band / dxw: g_b[s[6]] / dxs: derived from freq
    let dxCountry: String?      // dxs: dx_country / dxw: ci[2] entity name
    let dxContinent: String?    // dxh: Continent_dx / dxw: ci[2]
    let spotterContinent: String? // dxh: Continent_spotter
    let dxGrid: String?         // dxh: DXLocator / dxw: ci[9]
    let dxLatitude: Double?     // dxs: dx_latitude / dxw: ci[6]
    let dxLongitude: Double?    // dxs: dx_longitude / dxw: ci[7]
    let spotterLatitude: Double?  // dxs: de_latitude / dxw: ci[6] for spotter
    let spotterLongitude: Double? // dxs: de_longitude / dxw: ci[7] for spotter
    let flagCode: String?       // dxh: Flag / dxw: ci[3]
    let dxccPrefix: String?     // dxw: ci[0]
    let dxccNumber: String?     // dxw: ci[11]
    let cqZone: Int?            // dxw: ci[4]
    let ituZone: Int?           // dxw: ci[5]
    let iotaRef: String?        // dxw: ci[12]
    let lotwUser: Bool?         // dxh: LOTW
    let eqslUser: Bool?         // dxh: EQSL
    let isValid: Bool           // dxh: Valid / others: true
}
```

### Field Availability Matrix

| Field | DX Summit | DXHeat | DXWatch |
|-------|:---------:|:------:|:-------:|
| dxCall | ✅ | ✅ | ✅ |
| spotterCall | ✅ | ✅ | ✅ |
| frequency | ✅ | ✅ (string) | ✅ |
| timestamp | ✅ (ISO) | ✅ (split) | ✅ (text) |
| comment | ✅ | ✅ (HTML encoded) | ✅ |
| mode | ❌ | ✅ | ❌ |
| band | ❌ | ✅ | ✅ (coded) |
| dxCountry | ✅ | ❌ | ✅ (ci) |
| continent | ❌ | ✅ | ✅ (ci) |
| grid | ❌ | ✅ | ✅ (ci) |
| lat/lon (DX) | ✅ | ❌ | ✅ (ci) |
| lat/lon (spotter) | ✅ | ❌ | ✅ (ci) |
| flag | ❌ | ✅ | ✅ (ci) |
| DXCC prefix | ❌ | ❌ | ✅ (ci) |
| CQ/ITU zone | ❌ | ❌ | ✅ (ci) |
| IOTA | ❌ | ❌ | ✅ (ci) |
| LoTW/eQSL | ❌ | ✅ | ❌ |
| validity | ❌ | ✅ | ❌ |

---

## Split/QSX Frequency Parsing

All three sources encode split/listening frequency in the comment field. Common patterns to parse:

| Pattern | Regex | Example | Meaning |
|---------|-------|---------|---------|
| `up N` | `\bup\s*(\d+\.?\d*)\b` | "up 5", "up4.4" | TX freq + N kHz |
| `up N-M` | `\bup\s*(\d+)-(\d+)\b` | "up1-4" | TX freq + N to M kHz |
| `down N` | `\bdown\s*(\d+\.?\d*)\b` | "down 2" | TX freq - N kHz |
| `QSX FREQ` | `\bQSX\s+(\d{3,6}\.?\d*)\b` | "QSX 7025.00" | Listening on FREQ kHz |
| `listening up` | `\blistening\s+up\b` | "listening up" | Split up (unknown offset) |
| `simplex`/`simplx` | `\bsimpl[ex]+\b` | "simplx" | No split |
| `UP N+` | `\bUP\s*(\d+)\+\b` | "UP1+" | TX freq + N+ kHz |

---

## Polling Strategy Recommendations

| Source | Interval | Rationale |
|--------|----------|-----------|
| DX Summit | 30-60s | Simple REST, no known rate limits, CORS-enabled |
| DXHeat | **Socket.IO preferred** (fallback: 30s polling) | Real-time push avoids polling; polling at `/source/spots/` works |
| DXWatch | 30-60s | JS uses `newspottimeout=5000` (5s) internally; 30s is conservative for external use |

### Deduplication Strategy
Spots appear on all three sources simultaneously (they all aggregate from the same DX cluster network). Deduplicate by:
1. **Primary key:** `(dxCall, spotterCall, frequency, timestamp±30s)`
2. **Merge enrichment:** When a spot matches across sources, merge the richest data (DXHeat for mode/LoTW, DXWatch for DXCC/zone/IOTA, DX Summit for lat/lon)

### Incremental Polling
- **DX Summit:** Use `id` field — request spots newer than last seen ID (no built-in param, filter client-side)
- **DXHeat:** Use `Nr` field — same approach, or use Socket.IO for push
- **DXWatch:** Use `s=LASTID` parameter — built-in incremental support

---

## Raw JSON Samples

### DX Summit (3 spots)
```json
[
  {
    "info": "73's FT8 tnx",
    "dx_country": "Brazil",
    "de_latitude": 52.28,
    "dx_latitude": -23.55,
    "dx_longitude": 46.63,
    "de_call": "PD5SAP",
    "frequency": 28074.0,
    "time": "2026-03-20T14:19:15",
    "dx_call": "PU2XLC",
    "de_longitude": -5.47,
    "id": 66418537
  },
  {
    "info": "TNX 579 GD UP1+",
    "dx_country": "Zambia",
    "de_latitude": 59.35,
    "dx_latitude": -14.22,
    "dx_longitude": -26.73,
    "de_call": "ES4QR-@",
    "frequency": 28040.0,
    "time": "2026-03-20T14:16:14",
    "dx_call": "9J2RO",
    "de_longitude": -26.88,
    "id": 66418526
  },
  {
    "info": "lite w/qsb in W3 gud ears tu",
    "dx_country": "Benin",
    "de_latitude": 39.95,
    "dx_latitude": 9.87,
    "dx_longitude": -2.25,
    "de_call": "K3LL",
    "frequency": 28320.0,
    "time": "2026-03-20T14:18:45",
    "dx_call": "TY5FR",
    "de_longitude": 76.85,
    "id": 66418533
  }
]
```

### DXHeat (3 spots)
```json
[
  {
    "Nr": 66348827,
    "Spotter": "NC7M",
    "Frequency": "7022.0",
    "DXCall": "XX9W",
    "Time": "14:20",
    "Date": "20/03/26",
    "Beacon": false,
    "MM": false,
    "AM": false,
    "Valid": true,
    "DXHomecall": "XX9W",
    "Comment": "QSX 7025.00",
    "Flag": "mo",
    "Band": 40.0,
    "Mode": "CW",
    "Continent_dx": "AS",
    "Continent_spotter": "NA",
    "DXLocator": "OL62TE"
  },
  {
    "Nr": 66348780,
    "Spotter": "DL6RY",
    "Frequency": "28040.0",
    "DXCall": "9J2RO",
    "Time": "14:10",
    "Date": "20/03/26",
    "Beacon": false,
    "MM": false,
    "AM": false,
    "Valid": true,
    "DXHomecall": "9J2RO",
    "Comment": "listening up",
    "Flag": "zm",
    "Band": 10.0,
    "Mode": "CW",
    "Continent_dx": "AF",
    "Continent_spotter": "EU",
    "DXLocator": "KH44DO"
  },
  {
    "Nr": 66348796,
    "Spotter": "IZ5CML",
    "Frequency": "28023.0",
    "DXCall": "CY0S",
    "Time": "14:12",
    "Date": "20/03/26",
    "Beacon": false,
    "MM": false,
    "AM": false,
    "Valid": false,
    "LOTW": true,
    "LOTW_Date": "08/26/2024",
    "DXHomecall": "CY0S",
    "Comment": "up1-4  nice sig",
    "Flag": "ca",
    "Band": 10.0,
    "Mode": "CW",
    "Continent_dx": "NA",
    "Continent_spotter": "EU",
    "DXLocator": "GN03BW"
  }
]
```

### DXWatch (3 spots, decoded)
```json
{
  "s": {
    "60152157": ["ES2IPA", 14084, "XX9W", "FT8  F/H", "1421z 20 Mar", 73, 22, 0],
    "60152111": ["DL1HBT", 18080.9, "CY0S", "up4.4", "1409z 20 Mar", 771, 27, 1],
    "60152159": ["WB2ZAB", 21290, "YB2MVD", "", "1422z 20 Mar", 32, 32, 0]
  },
  "ci": {
    "XX9W": ["XX9", "Macao", "AS", "mo", 44, 24, 22.1458, 113.542, "", "OL62SD", "", "308", ""],
    "CY0S": ["CY0", "Sable I.", "NA", "ca", 9, 5, 43.9375, -60.0417, "", "FN93XW", "", "89", "NA-063"],
    "ES2IPA": ["ES", "Estonia", "EU", "ee", 29, 15, 59.5208, 24.7917, "Harju", "KO29JM"]
  }
}
```

---

## Recommendations

1. **Primary source: DXHeat** — Richest data (mode, band, continent, grid, LoTW/eQSL), Socket.IO for real-time push
2. **Secondary source: DXWatch** — Best DXCC metadata (zones, IOTA, entity numbers), good for enrichment
3. **Tertiary source: DX Summit** — Simplest API, CORS-enabled, useful as fallback and for lat/lon data
4. **Merge strategy:** Use DXHeat as primary feed (Socket.IO), merge DXWatch ci data for DXCC/zone/IOTA enrichment, DX Summit for lat/lon
5. **Socket.IO library:** DXHeat uses Socket.IO 1.0.6 — need a compatible Swift client (Starscream + manual Socket.IO 1.x framing, or socket.io-client-swift)
