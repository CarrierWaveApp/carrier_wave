# API Reference

Base URL: `https://challenges.example.com/v1`

## Authentication

### Device Token

Most endpoints require a device token in the Authorization header:

```
Authorization: Bearer fd_abc123...
```

Tokens are issued when joining a challenge and tied to a callsign.

### Third-party OAuth 2.0 / OIDC

Applications written by someone else authorize against the account holder and
receive a scoped bearer token. Those tokens are **default-denied** on every
route not explicitly listed in `src/auth/scope_map.rs` — today that means the
sync journal and OIDC UserInfo only, so most endpoints documented below are
first-party-only.

See [features/oauth-api.md](features/oauth-api.md) for the flows, scopes, and
the encrypted-log protocol.

### Admin Token

Admin endpoints require the server's admin token:

```
Authorization: Bearer {ADMIN_TOKEN}
```

## Response Format

### Success

```json
{
  "data": { ... }
}
```

### Error

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message",
    "details": { ... }
  }
}
```

## Rate Limiting

All responses include rate limit headers:

- `X-RateLimit-Limit`: Requests allowed per window
- `X-RateLimit-Remaining`: Requests remaining
- `X-RateLimit-Reset`: Unix timestamp when window resets

---

## Public Endpoints

### List Challenges

```
GET /v1/challenges
```

**Query Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `category` | string | Filter by category (award, event, club, personal, other) |
| `type` | string | Filter by type (collection, cumulative, timeBounded) |
| `active` | bool | Filter by active status |
| `limit` | int | Max results (default 50, max 100) |
| `offset` | int | Pagination offset |

**Response:**

```json
{
  "data": {
    "challenges": [
      {
        "id": "uuid",
        "name": "Worked All States",
        "description": "Work all 50 US states",
        "category": "award",
        "type": "collection",
        "participantCount": 1234,
        "isActive": true
      }
    ],
    "total": 45,
    "limit": 50,
    "offset": 0
  }
}
```

### Get Challenge

```
GET /v1/challenges/{id}
```

**Response Headers:**

- `ETag`: Version hash for caching
- `X-Challenge-Version`: Integer version number

**Response:**

```json
{
  "data": {
    "id": "uuid",
    "version": 1,
    "name": "Worked All States",
    "description": "...",
    "author": "FullDuplex",
    "category": "award",
    "type": "collection",
    "configuration": {
      "goals": {
        "type": "collection",
        "items": [
          { "id": "US-AL", "name": "Alabama" },
          { "id": "US-AK", "name": "Alaska" }
        ]
      },
      "tiers": [
        { "id": "tier-25", "name": "25 States", "threshold": 25 },
        { "id": "tier-50", "name": "All States", "threshold": 50 }
      ],
      "qualificationCriteria": {
        "bands": null,
        "modes": null,
        "requiredFields": [],
        "dateRange": null,
        "matchRules": [
          { "qsoField": "state", "goalField": "id" }
        ]
      },
      "scoring": {
        "method": "count",
        "displayFormat": "{value}/50 states"
      },
      "historicalQsosAllowed": true
    },
    "badges": [
      { "id": "badge-uuid", "name": "WAS", "tierId": "tier-50" }
    ],
    "isActive": true,
    "createdAt": "2025-01-01T00:00:00Z",
    "updatedAt": "2025-01-01T00:00:00Z"
  }
}
```

### Join Challenge

```
POST /v1/challenges/{id}/join
```

**Request:**

```json
{
  "callsign": "W1ABC",
  "deviceName": "iPhone",
  "inviteToken": "xyz789"
}
```

`inviteToken` only required for invite-only challenges.

**Response:**

```json
{
  "data": {
    "participationId": "uuid",
    "deviceToken": "fd_abc123...",
    "joinedAt": "2025-01-15T12:00:00Z",
    "status": "active",
    "historicalAllowed": true
  }
}
```

**Note:** If the callsign already exists in the system, a new device token is generated and returned. This allows token recovery for users who have lost their token.

**Errors:**

| Code | HTTP | Description |
|------|------|-------------|
| `ALREADY_JOINED` | 409 | Callsign already in challenge |
| `INVITE_REQUIRED` | 403 | Challenge requires invite |
| `INVITE_EXPIRED` | 403 | Invite token expired |
| `INVITE_EXHAUSTED` | 403 | Invite max uses reached |
| `MAX_PARTICIPANTS` | 403 | Challenge full |
| `CHALLENGE_ENDED` | 400 | Time-bounded challenge ended |

### Report Progress

```
POST /v1/challenges/{id}/progress
Authorization: Bearer fd_xxx
```

**Request:**

```json
{
  "completedGoals": ["US-CA", "US-NY", "US-TX"],
  "currentValue": 47,
  "qualifyingQsoCount": 52,
  "lastQsoDate": "2025-01-15T18:30:00Z"
}
```

**Response:**

```json
{
  "data": {
    "accepted": true,
    "serverProgress": {
      "completedGoals": ["US-CA", "US-NY", "US-TX"],
      "currentValue": 47,
      "percentage": 94.0,
      "score": 47,
      "rank": 23,
      "currentTier": "tier-40"
    },
    "newBadges": ["badge-uuid"]
  }
}
```

### Get Progress

```
GET /v1/challenges/{id}/progress
Authorization: Bearer fd_xxx
```

Returns current progress for the authenticated callsign.

### Get Leaderboard

```
GET /v1/challenges/{id}/leaderboard
```

**Query Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `limit` | int | Max results (default 100) |
| `offset` | int | Pagination offset |
| `around` | string | Callsign to center results around |

**Response:**

```json
{
  "data": {
    "leaderboard": [
      {
        "rank": 1,
        "callsign": "K1ABC",
        "score": 50,
        "currentTier": "tier-50",
        "completedAt": "2025-01-10T00:00:00Z"
      }
    ],
    "total": 1234,
    "userPosition": {
      "rank": 23,
      "callsign": "W1ABC",
      "score": 47
    },
    "lastUpdated": "2025-01-15T19:00:00Z"
  }
}
```

### Get Participation Status

```
GET /v1/challenges/{id}/participants/{callsign}
Authorization: Bearer fd_xxx
```

Returns participation status for a callsign in a specific challenge. The authenticated callsign must match the requested callsign.

**Response:**

```json
{
  "data": {
    "participationId": "uuid",
    "challengeId": "uuid",
    "joinedAt": "2025-01-15T12:00:00Z",
    "status": "active"
  }
}
```

**Errors:**

| Code | HTTP | Description |
|------|------|-------------|
| `FORBIDDEN` | 403 | Authenticated callsign doesn't match requested callsign |
| `NOT_PARTICIPATING` | 403 | Callsign is not a participant in this challenge |

### List Challenges for Callsign

```
GET /v1/participants/{callsign}/challenges
Authorization: Bearer fd_xxx
```

Returns all challenges a callsign has joined. The authenticated callsign must match the requested callsign.

**Response:**

```json
{
  "data": [
    {
      "participationId": "uuid",
      "challengeId": "uuid",
      "challengeName": "Worked All States",
      "joinedAt": "2025-01-15T12:00:00Z",
      "status": "active"
    }
  ]
}
```

**Errors:**

| Code | HTTP | Description |
|------|------|-------------|
| `FORBIDDEN` | 403 | Authenticated callsign doesn't match requested callsign |

### Leave Challenge

```
DELETE /v1/challenges/{id}/leave
Authorization: Bearer fd_xxx
```

Removes participation and progress. Cannot be undone.

### Get Snapshot

```
GET /v1/challenges/{id}/snapshot
```

For ended time-bounded challenges, returns frozen final standings.

**Response:**

```json
{
  "data": {
    "challengeId": "uuid",
    "endedAt": "2025-01-31T23:59:59Z",
    "finalStandings": [
      { "rank": 1, "callsign": "K1ABC", "score": 127 }
    ],
    "totalParticipants": 50,
    "statistics": {
      "averageScore": 45.2,
      "completionRate": 0.12
    }
  }
}
```

### Get Badge Image

```
GET /v1/badges/{id}/image
```

Returns badge image with appropriate `Content-Type` header.

### List Programs

```
GET /v1/programs
```

Returns all active activity programs with a version for cache invalidation.

**Response:**

```json
{
  "data": {
    "programs": [
      {
        "slug": "pota",
        "name": "Parks on the Air",
        "shortName": "POTA",
        "icon": "tree",
        "website": "https://pota.app",
        "referenceLabel": "Park Reference",
        "referenceFormat": "^[A-Z]+-[0-9]{4,5}$",
        "referenceExample": "K-0001",
        "multiRefAllowed": true,
        "activationThreshold": 10,
        "supportsRove": true,
        "capabilities": ["referenceField", "adifUpload", "browseSpots", "selfSpot", "hunter", "locationLookup", "progressTracking"],
        "adifFields": {
          "mySig": "POTA",
          "mySigInfo": "MY_POTA_REF",
          "sigField": "SIG",
          "sigInfoField": "SIG_INFO"
        }
      }
    ],
    "version": 1737900000
  }
}
```

### Get Program

```
GET /v1/programs/{slug}
```

Returns a single program by slug.

**Errors:**

| Code | HTTP | Description |
|------|------|-------------|
| `PROGRAM_NOT_FOUND` | 404 | Program slug doesn't exist |

### Delete Activity

```
DELETE /v1/activities/{id}
Authorization: Bearer fd_xxx
```

Deletes an activity. The authenticated user must own the activity.

**Response:** 204 No Content

**Errors:**

| Code | HTTP | Description |
|------|------|-------------|
| `ACTIVITY_NOT_FOUND` | 404 | Activity doesn't exist or not owned |

### Health Check

```
GET /v1/health
```

Verifies the process is up **and** PostgreSQL answers a trivial query
(`SELECT 1`, 2 s timeout). Returns `200` when the database check passes,
`503 Service Unavailable` when it fails or times out, so load balancers and
the monitoring probe treat a dead database as an unhealthy service.

**Response (200):**

```json
{
  "status": "ok",
  "version": "1.0.0",
  "database": "ok",
  "rbn": { "connected": true, "spots_in_store": 1234, "spots_per_minute": 42.0 }
}
```

`rbn` is informational, only present when the RBN proxy has data, and never
affects the status code.

**Response (503):**

```json
{
  "status": "error",
  "version": "1.0.0",
  "database": "error",
  "error": "database check failed"
}
```

---

## Event Endpoints

### List Events (Proximity)

```
GET /v1/events
```

Returns approved upcoming events near a location.

**Query Parameters (required):**

| Param | Type | Description |
|-------|------|-------------|
| `lat` | float | Latitude (-90 to 90) |
| `lon` | float | Longitude (-180 to 180) |
| `radiusKm` | float | Search radius in km (1 to 500) |

**Query Parameters (optional):**

| Param | Type | Description |
|-------|------|-------------|
| `eventType` | string | Filter by type |
| `fromDate` | datetime | Events starting on or after |
| `toDate` | datetime | Events starting on or before |
| `includePast` | bool | Include past events (default false) |
| `limit` | int | Max results (default 50, max 100) |
| `offset` | int | Pagination offset |

**Response:**

```json
{
  "data": {
    "events": [
      {
        "id": "uuid",
        "name": "Monthly Club Meeting",
        "eventType": "club_meeting",
        "startDate": "2026-04-01T19:00:00Z",
        "endDate": "2026-04-01T21:00:00Z",
        "timezone": "America/New_York",
        "venueName": "VFW Hall",
        "city": "Springfield",
        "state": "MA",
        "country": "US",
        "latitude": 42.1015,
        "longitude": -72.5898,
        "cost": "Free",
        "submittedBy": "W1ABC",
        "status": "approved",
        "createdAt": "2026-03-14T12:00:00Z",
        "distanceMeters": 1234.56
      }
    ],
    "total": 5,
    "limit": 50,
    "offset": 0
  }
}
```

### Get Event

```
GET /v1/events/{id}
```

Returns a single approved event with full details.

### Submit Event

```
POST /v1/events
Authorization: Bearer fd_xxx
```

Submit a new event for admin review. Max 10 pending events per callsign.

**Request:**

```json
{
  "name": "Monthly Club Meeting",
  "eventType": "club_meeting",
  "startDate": "2026-04-01T19:00:00Z",
  "endDate": "2026-04-01T21:00:00Z",
  "timezone": "America/New_York",
  "venueName": "VFW Hall",
  "address": "123 Main St",
  "city": "Springfield",
  "state": "MA",
  "country": "US",
  "latitude": 42.1015,
  "longitude": -72.5898,
  "cost": "Free",
  "url": "https://example.com/meeting",
  "description": "Monthly meeting of the Springfield ARC",
  "days": [
    {
      "date": "2026-04-01",
      "startTime": "2026-04-01T19:00:00Z",
      "endTime": "2026-04-01T21:00:00Z"
    }
  ]
}
```

The `days` field is optional. When provided, each entry represents a specific day of a multi-day event with its own schedule. The `startDate`/`endDate` fields remain as the overall event span for backward compatibility.

**Response:** 201 Created with the event (status = "pending"). If days were provided, the response includes a `days` array.

**Errors:**

| Code | HTTP | Description |
|------|------|-------------|
| `MAX_PENDING_EVENTS` | 429 | Already have 10 pending events |
| `VALIDATION_ERROR` | 400 | Invalid fields |

### Update Own Event

```
PUT /v1/events/{id}
Authorization: Bearer fd_xxx
```

Edit own event. Partial update — only provided fields change. If the event was approved and key fields (name, description, address, venueName, latitude, longitude) change, status resets to "pending".

### Delete Own Event

```
DELETE /v1/events/{id}
Authorization: Bearer fd_xxx
```

**Response:** 204 No Content

### List My Events

```
GET /v1/events/mine
Authorization: Bearer fd_xxx
```

Returns all events submitted by the authenticated callsign, across all statuses.

---

## Propagation Endpoints

Served when the activities-server is built with the propagation sidecar
enabled (`PROPAGATION_ENABLED=true`). Both endpoints proxy to an internal
Python service wrapping
[`dvoacap-python`](https://github.com/skyelaird/dvoacap-python) and cache
responses in Postgres for 24h.

See [features/propagation.md](features/propagation.md) for the full
architecture; request and response schemas live in
`server/src/models/propagation.rs` and `server/propagation/app/schemas.py`.

### Point-to-Point Prediction

```
POST /v1/propagation/p2p
```

Body: `{ tx_lat, tx_lon, rx_lat, rx_lon, month, utc_hour, ssn, tx_power_w?, frequencies_mhz? }`

Returns MUF, great-circle geometry, and a per-frequency row with hop count,
SNR, reliability, and service probability.

### Propagation Wheel

```
POST /v1/propagation/wheel
```

Body: `{ lat, lon, month, utc_hour, ssn, tx_power_w?, radius_km?, azimuth_step_deg?, frequencies_mhz? }`

Returns one prediction spoke per azimuth (step defaults to 15°) at
`radius_km` from the centre. Intended for polar "CAP wheel" UIs.

---

## Telemetry Endpoints

### Report Upload Errors

```
POST /v1/telemetry/upload-errors
Authorization: Bearer fd_xxx
```

Report anonymized, aggregated upload error data. Used to identify systemic issues (e.g., a service rejecting everyone's uploads). No callsigns, QSO data, or raw error messages are included — only category, hashed message, and counts.

**Request:**

```json
{
  "errors": [
    {
      "service": "pota",
      "category": "authentication",
      "message_hash": "a1b2c3",
      "affected_count": 5,
      "is_transient": false,
      "app_version": "1.8.0",
      "os_version": "18.4"
    }
  ]
}
```

**Valid services:** `pota`, `qrz`, `clublog`, `eqsl`, `lotw`, `hamqth`

**Valid categories:** `authentication`, `validation`, `rate_limited`, `maintenance`, `network_timeout`, `network_offline`, `server_error`, `rejected`, `subscription_required`

**Limits:** Max 50 errors per report.

**Response:**

```json
{
  "accepted": 1
}
```

**Errors:**

| Code | HTTP | Description |
|------|------|-------------|
| `VALIDATION_ERROR` | 400 | Unknown service/category, too many errors, or invalid field lengths |

### Get Upload Error Telemetry Summary (Admin)

```
GET /v1/admin/telemetry/upload-errors
Authorization: Bearer {ADMIN_TOKEN}
```

Returns aggregated upload error telemetry for identifying systemic issues.

**Query Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `days` | int | Lookback period (default 7, max 90) |
| `service` | string | Filter by service (e.g., `pota`) |
| `category` | string | Filter by category (e.g., `authentication`) |

**Response:**

```json
{
  "data": {
    "totalErrors": 42,
    "totalAffectedQsos": 128,
    "uniqueCallsigns": 15,
    "byService": [
      { "service": "pota", "errorCount": 25, "affectedQsos": 80 }
    ],
    "byCategory": [
      { "category": "authentication", "errorCount": 18, "affectedQsos": 50 }
    ],
    "dailyTrend": [
      { "date": "2026-03-15", "errorCount": 10, "affectedQsos": 30 }
    ],
    "recentErrors": [
      {
        "service": "pota",
        "category": "authentication",
        "messageHash": "a1b2c3",
        "affectedCount": 5,
        "isTransient": false,
        "appVersion": "1.8.0",
        "osVersion": "18.4",
        "callsign": "W1ABC",
        "createdAt": "2026-03-15T14:30:00Z"
      }
    ]
  }
}
```

---

## Admin Endpoints

All require `Authorization: Bearer {ADMIN_TOKEN}`.

### List Events (Admin)

```
GET /v1/admin/events
```

**Query Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `status` | string | Filter by status (pending, approved, rejected) |
| `limit` | int | Max results (default 50, max 100) |
| `offset` | int | Pagination offset |

### Get Event (Admin)

```
GET /v1/admin/events/{id}
```

Returns any event regardless of status.

### Edit Event (Admin)

```
PUT /v1/admin/events/{id}
```

Admin can edit any event fields (fix typos, adjust coordinates before approving).

### Review Event

```
PUT /v1/admin/events/{id}/review
```

**Request:**

```json
{
  "action": "approve",
  "reason": null
}
```

or

```json
{
  "action": "reject",
  "reason": "Not ham radio related"
}
```

Reason is required when rejecting.

### Delete Event (Admin)

```
DELETE /v1/admin/events/{id}
```

Hard deletes the event.

### Get Submitter History

```
GET /v1/admin/events/submitter/{callsign}
```

Returns submission stats for a callsign.

```json
{
  "data": {
    "totalSubmitted": 12,
    "totalApproved": 9,
    "totalRejected": 2,
    "totalPending": 1
  }
}
```

### Create Challenge

```
POST /v1/admin/challenges
```

**Request:** Full challenge object (see Get Challenge response format).

### Update Challenge

```
PUT /v1/admin/challenges/{id}
```

Increments version number automatically.

### Delete Challenge

```
DELETE /v1/admin/challenges/{id}
```

Cascades to participants, progress, badges.

### Upload Badge

```
POST /v1/admin/challenges/{id}/badges
Content-Type: multipart/form-data
```

**Form Fields:**

- `name`: Badge name
- `tierId`: Associated tier (optional)
- `image`: Image file (PNG, SVG)

### Delete Badge

```
DELETE /v1/admin/badges/{id}
```

### Generate Invite

```
POST /v1/admin/challenges/{id}/invites
```

**Request:**

```json
{
  "maxUses": 50,
  "expiresAt": "2025-12-31T23:59:59Z"
}
```

**Response:**

```json
{
  "data": {
    "token": "invite_abc123",
    "url": "https://challenges.example.com/join/invite_abc123"
  }
}
```

### Revoke Tokens

```
DELETE /v1/admin/participants/{callsign}/tokens
```

Revokes all device tokens for a callsign (abuse handling).

### End Challenge

```
POST /v1/admin/challenges/{id}/end
```

Manually ends a challenge and creates a snapshot.

### List All Programs (Admin)

```
GET /v1/admin/programs
```

Returns all programs including inactive ones.

### Get Program (Admin)

```
GET /v1/admin/programs/{slug}
```

Returns a program by slug, including inactive programs.

### Create Program

```
POST /v1/admin/programs
```

**Request:**

```json
{
  "slug": "my-program",
  "name": "My Program",
  "shortName": "MP",
  "icon": "radio",
  "website": "https://example.com",
  "referenceLabel": "Reference",
  "referenceFormat": "^[A-Z]+-[0-9]{4}$",
  "referenceExample": "K-0001",
  "multiRefAllowed": false,
  "activationThreshold": null,
  "supportsRove": false,
  "capabilities": ["referenceField"],
  "adifMySig": null,
  "adifMySigInfo": null,
  "adifSigField": null,
  "adifSigInfoField": null,
  "dataEntryLabel": null,
  "dataEntryPlaceholder": null,
  "dataEntryFormat": null,
  "sortOrder": 10
}
```

**Response:** 201 Created with the created program.

### Update Program

```
PUT /v1/admin/programs/{slug}
```

Partial update — only provided fields are changed. For nullable fields, send `null` to clear or omit to leave unchanged.

**Request:** Any subset of fields from the create request, plus `isActive`.

### Delete Program

```
DELETE /v1/admin/programs/{slug}
```

Permanently deletes a program. Use `PUT` with `{"isActive": false}` for soft-deactivation.

---

## AMSAT Satellite Status

Community satellite status aggregated from AMSAT's status API
([status.amsat.org/api/v1](https://status.amsat.org/api/v1/)) so clients hit
this server instead of AMSAT's volunteer-run service. Each cycle (default
30 min, `AMSAT_STATUS_CYCLE_MINUTES`; disable with
`AMSAT_STATUS_AGGREGATOR_ENABLED=false`) the aggregator reads the catalog
(`catalog.php`) and every report newer than its cursor in one request
(`reports.php?since=…&limit=500`, re-read per satellite only when that page
is full), accumulates them in `amsat_report`, and replaces the `amsat_status`
table. `AMSAT_STATUS_API_BASE` overrides the API base; an empty catalog on
the configured host falls back to the legacy `www.amsat.org/status/api/v1`
(AMSAT's data moves hosts on 2026-11-04). Public — no auth required.

Report data is AMSAT's, licensed CC BY 4.0. Anything that displays it must
carry the attribution *Satellite status data: AMSAT, https://status.amsat.org*.

### Get AMSAT Status

```
GET /v1/satellites/amsat-status
```

Response (camelCase; null-ish fields omitted):

```json
{
  "satellites": [
    {
      "name": "SO-50_[FM]",
      "noradId": 27607,
      "lastHeardAt": "2026-09-20T13:30:00Z",
      "lastReportedAt": "2026-09-20T14:30:00Z",
      "lastReport": "Heard",
      "lastCallsign": "ON7VQ",
      "lastGrid": "JO20gv",
      "heardReports24h": 7,
      "totalReports24h": 9
    }
  ],
  "updatedAt": "2026-09-20T15:00:12.412Z"
}
```

Report window is 7 days: `last*` fields span the window; the `*24h` counts use a 24-hour cutoff. `name` is AMSAT's internal name (one row per transmitter, e.g. `AO-7_[A]`
and `AO-7_[B]`). `noradId` comes from a curated mapping in the aggregator
and is omitted for satellites we haven't mapped.

### Get AMSAT Activity

```
GET /v1/satellites/amsat-status/activity?hours=168
```

The hour-by-hour report histogram behind amsat.org's status grid, for every
satellite in the list above. The aggregator keeps each raw report it sees
(`amsat_report`, deduplicated on satellite + hour + callsign + verdict — a
report the same callsign re-files for the same 15-minute period replaces the
earlier verdict, as it does on AMSAT's side — and pruned after 8 days), so the
history is complete even for busy birds where one AMSAT API page caps at 500
rows. `hours` is clamped to 1–168
(default 168). Public — no auth required.

Response (camelCase; buckets with no reports are omitted; `start` is the
bucket's inclusive start, aligned to the hour):

```json
{
  "bucketSeconds": 3600,
  "windowStart": "2026-10-06T14:00:00Z",
  "windowEnd": "2026-10-13T14:12:08.112Z",
  "updatedAt": "2026-10-13T14:05:41.901Z",
  "satellites": [
    {
      "name": "SO-50_[FM]",
      "noradId": 27607,
      "buckets": [
        { "start": "2026-10-13T12:00:00Z", "heard": 2, "notHeard": 0, "telemetry": 0, "crew": 0, "other": 0 },
        { "start": "2026-10-13T13:00:00Z", "heard": 1, "notHeard": 1, "telemetry": 0, "crew": 0, "other": 0 }
      ]
    }
  ]
}
```

Verdicts map to counters as `Heard` → `heard`, `Not Heard` → `notHeard`,
`Telemetry Only` → `telemetry`, `Crew Active` (ISS) → `crew`; anything new
AMSAT adds lands in `other` rather than being dropped. Satellites are in the
same order as `/satellites/amsat-status`; names that only exist in the report
table (dropped from AMSAT's list since) follow with no `noradId`.

### Get AMSAT Reports

```
GET /v1/satellites/amsat-status/reports?norad=27607&hours=24
GET /v1/satellites/amsat-status/reports?name=SO-50_[FM]&hours=24
```

The raw community reports behind one bird's cells, newest first (at most
500). `norad` resolves to every AMSAT capability row mapped to that id;
`name` is an exact AMSAT internal name; either or both may be given (400
when neither resolves). `hours` is clamped to 1–168 (default 24). Public.

```json
{
  "windowStart": "2026-10-12T14:12:08Z",
  "windowEnd": "2026-10-13T14:12:08Z",
  "names": ["SO-50_[FM]"],
  "reports": [
    { "name": "SO-50_[FM]", "reportedAt": "2026-10-13T13:30:00Z", "callsign": "EI6FZ", "report": "Heard", "grid": "IO63" }
  ]
}
```

`reportedAt` is AMSAT's hour-quantised stamp (hh:30Z); `grid` is the
reporter's Maidenhead locator when they gave one.

## Club Rosters

Clubs are admin-managed (`/v1/admin/clubs/*`). A club with a `notes_url`
pointing at a Ham2K PoLo callsign-notes file (e.g.
`https://www.bkg.club/members.txt`) has its roster reconciled against that
file by the `club_rosters` aggregator every `CLUB_ROSTER_SYNC_CYCLE_HOURS`
(default 6; `CLUB_ROSTER_SYNC_ENABLED=false` turns it off). Callsigns new to
the file are added as `member`, `member`-role rows that left the file are
removed, and `admin` rows are never touched. A file that yields zero
callsigns is treated as an upstream failure and the roster is left alone.
Every mutation bumps `clubs.updated_at`, so the `/v1/clubs/sync` and
`/v1/clubs/membership` ETags move and clients pick up removals as well as
additions.

`POST /v1/admin/clubs/{id}/import-notes` runs the same reconciliation on
demand and returns `{ imported, skipped, removed, callsigns,
removed_callsigns }`. The admin club list (`GET /v1/admin/clubs`) exposes
`rosterSyncedAt` and `rosterSyncStatus` (`ok` / `error: …`) from the last
attempt.

## Callsign Enrichment

Per-callsign membership data pulled from public organisation lists (CWops
today, with SKCC and others to follow). Sources are configured in the
`callsign_enrichment_sources` table; the aggregator polls each enabled source
roughly daily, parses it according to its `format` (currently `polo` for Ham2K
PoLo callsign-notes files), and replaces all rows for that source on each
refresh. The endpoints are public — no auth required.

### Get Dataset

```
GET /v1/callsign-enrichment/dataset
```

Returns the entire enrichment table for client-side caching. Response uses
compact field names (`c`/`m`/`s`/`#`/`n`/`e`/`t`) so it stays small even
with thousands of callsigns. Supports `If-None-Match` against the ETag for
conditional requests.

**Response:**

```json
{
  "sources": [
    { "slug": "cwops", "name": "CWops", "emoji": "🎹", "last_fetched_at": "2026-05-06T12:00:00Z" }
  ],
  "callsigns": [
    {
      "c": "AA0FO",
      "m": [{ "s": "cwops", "n": "MARSHALL R", "#": "1532" }]
    }
  ],
  "generated_at": "2026-05-06T12:00:00Z"
}
```

Headers: `ETag` for cache revalidation, `Cache-Control: public, max-age=3600`.

### Get Single Callsign

```
GET /v1/callsign-enrichment/{callsign}
```

Convenience endpoint for ad-hoc / debug lookups; production clients should
use the dataset endpoint and look up locally.

**Response:**

```json
{
  "callsign": "AA0FO",
  "memberships": [
    { "source_slug": "cwops", "source_name": "CWops", "emoji": "🎹",
      "name": "MARSHALL R", "member_number": "1532", "note": null }
  ]
}
```

---

## Radio Macros (CAR-271)

Phase 1 public reads filter to `status='approved'`. Withdrawn slugs are
never re-used; clients poll `/v1/macros/tombstones?since=` to discover
removed slugs. Per-slug versions monotonically increase via the admin
upsert path (POST is idempotent — slug-conflict bumps version and writes
a `macro_versions` row).

### Public reads

```http
GET /v1/macros?tag=&applies_to=&search=&max_format=&limit=&offset=
GET /v1/macros/:slug
GET /v1/macros/:slug/versions
GET /v1/macros/versions?slugs=a,b,c
GET /v1/macros/tombstones?since=<RFC3339>
```

`max_format` lets a v2 client suppress v3-only macros up front. The
versions endpoint returns `{ slug: { version, format } }` so both
"update available?" and "can I decode?" checks happen in one trip.

### Authenticated telemetry

```http
POST /v1/macros/:slug/run-event
Authorization: Bearer <device_token>
Content-Type: application/json

{ "success": true, "failed_step_index": null, "error_code": null, "occurred_at": null }
```

`device_hash` is computed server-side as
`HMAC-SHA256(TELEMETRY_HMAC_KEY_<YYYY-MM-DD>_<MACROS_TELEMETRY_SECRET>,
"<participant_id>:<slug>")` — daily+per-slug rotation, never reversible
to a user. Per-token rate limit 60/min; excess returns 429. Raw events
are deleted after 90 days; daily roll-ups live in `macro_run_aggregates`.

### Admin

All admin endpoints sit behind the existing `Authorization: Bearer
<ADMIN_TOKEN>` middleware. Reserved-prefix slug rules are relaxed for
admin sync.

```http
POST   /v1/admin/macros            # create-or-bump
GET    /v1/admin/macros?status=    # every status (limit/offset)
PUT    /v1/admin/macros/:slug      # replace spec; path/body slug must match
PATCH  /v1/admin/macros/:slug      # { "status": "withdrawn", "moderator_notes": "..." }
DELETE /v1/admin/macros/:slug      # hard delete (prefer PATCH withdrawn)
```

Every write runs the slug + tag + band-plan validators and the Rust
verifier. Errors return 400 with the verifier issues serialized.

The starter catalog lives at [`server/seed_macros/`](../seed_macros/) and
ships via the Ansible deploy (`roles/activities_server/tasks/seed_macros.yml`).

---

## Sync (E2E-encrypted journal)

The `/v1/sync/*` routes are the server side of Carrier Wave Sync: a per-account
append-only log of ciphertext blobs. The server assigns sequence numbers, hands
out presigned upload/download URLs, and never sees plaintext. All routes
require an account-backed session (`403 ACCOUNT_REQUIRED` for legacy `fd_`
tokens). Third-party OAuth tokens may reach them with `sync:read` /
`sync:write` — see [features/oauth-api.md](features/oauth-api.md).

```http
POST /v1/sync/push               # reserve seqs + presigned PUT per entry
GET  /v1/sync/changes?since=&limit=
GET  /v1/sync/bootstrap          # live snapshot pointer + post-snapshot entries
POST /v1/sync/snapshot           # begin a snapshot (phase 1)
POST /v1/sync/snapshot/commit    # confirm a snapshot (phase 2)
PUT  /v1/sync/key                # passphrase-escrow key blob
GET  /v1/sync/key
```

### Snapshots (two-phase, CAR-334)

A snapshot folds the journal up to `seq` into one blob so a fresh device can
bootstrap from it instead of replaying the whole log. Because the server cannot
read or rebuild anything, a snapshot is only allowed to replace journal entries
once the server has confirmed the snapshot object really exists. The flow is:

1. `POST /v1/sync/snapshot` — declare intent. Nothing becomes live and nothing
   is deleted.
2. `PUT` the ciphertext to the returned `uploadUrl` (valid ~15 minutes).
3. `POST /v1/sync/snapshot/commit` — the server `HEAD`s the object, then moves
   the live pointer forward and garbage-collects entries strictly below `seq`.

A snapshot that is begun but never committed is inert: `bootstrap`/`changes`
never reference it, its id stops being accepted after 30 minutes, and the row
(plus any bytes that were uploaded) is purged on the tenant's next snapshot
request.

#### Begin Snapshot

```http
POST /v1/sync/snapshot
Authorization: Bearer <token>
Content-Type: application/json

{ "seq": 120, "byteSize": 48211, "contentHash": "sha256-hex" }
```

`seq` must satisfy `currentSnapshotSeq < seq <= highWater`; anything else is
`409 SYNC_SEQUENCE_CONFLICT` (this is what stops a stray or hostile
`{"seq": 9223372036854775807}` from ever touching the journal). `byteSize`
and `contentHash` are optional; if given, `byteSize` is checked against the
stored object at commit and both must be repeated identically if the commit
supplies them.

```json
{
  "snapshotId": "8b0a…",
  "seq": 120,
  "snapshotBlobKey": "<tenant>/snapshots/120-8b0a….bin",
  "uploadUrl": "https://…",
  "expiresAt": "2026-09-26T18:30:00Z"
}
```

#### Commit Snapshot

```http
POST /v1/sync/snapshot/commit
Authorization: Bearer <token>
Content-Type: application/json

{ "snapshotId": "8b0a…", "byteSize": 48211, "contentHash": "sha256-hex" }
```

On success (200) the pointer is live and GC has run:

```json
{ "snapshotSeq": 120, "snapshotBlobKey": "<tenant>/snapshots/120-8b0a….bin", "highWater": 124 }
```

The pointer only ever moves forward. Failures leave the journal untouched:

| Status | Code | Meaning |
|---|---|---|
| 404 | `SYNC_SNAPSHOT_NOT_FOUND` | Unknown id, already committed, expired, or superseded by a later snapshot |
| 409 | `SYNC_SNAPSHOT_NOT_UPLOADED` | No object at the presigned key yet — finish the `PUT` and retry the commit |
| 409 | `SYNC_SNAPSHOT_MISMATCH` | Stored size differs from the declared `byteSize`, or size/hash disagree with phase 1 |
| 409 | `SYNC_SEQUENCE_CONFLICT` | The live pointer is already at or past this `seq` (a newer snapshot won) |

---

## Error Codes

| Code | HTTP | Description |
|------|------|-------------|
| `ACCOUNT_REQUIRED` | 403 | Sync routes need an email-verified account session |
| `SYNC_SEQUENCE_CONFLICT` | 409 | Snapshot `seq` outside `(currentSnapshotSeq, highWater]`, or a stale commit |
| `SYNC_SNAPSHOT_NOT_FOUND` | 404 | Pending snapshot id unknown, expired, committed, or superseded |
| `SYNC_SNAPSHOT_NOT_UPLOADED` | 409 | Snapshot commit before the blob was uploaded |
| `SYNC_SNAPSHOT_MISMATCH` | 409 | Snapshot blob size/hash does not match what was declared |
| `ACTIVITY_NOT_FOUND` | 404 | Activity doesn't exist or not owned |
| `CHALLENGE_NOT_FOUND` | 404 | Challenge doesn't exist |
| `PROGRAM_NOT_FOUND` | 404 | Program slug doesn't exist |
| `ALREADY_JOINED` | 409 | Already participating |
| `NOT_PARTICIPATING` | 403 | Must join first |
| `INVITE_REQUIRED` | 403 | Invite-only challenge |
| `INVITE_EXPIRED` | 403 | Invite past expiry |
| `INVITE_EXHAUSTED` | 403 | Invite max uses reached |
| `MAX_PARTICIPANTS` | 403 | Challenge at capacity |
| `CHALLENGE_ENDED` | 400 | Challenge has ended |
| `INVALID_TOKEN` | 401 | Bad or revoked token |
| `FORBIDDEN` | 403 | Access denied (e.g., callsign mismatch) |
| `RATE_LIMITED` | 429 | Too many requests |
| `EVENT_NOT_FOUND` | 404 | Event doesn't exist or not approved |
| `EVENT_NOT_OWNED` | 403 | Cannot modify another user's event |
| `MAX_PENDING_EVENTS` | 429 | Already have 10 pending events |
| `INVALID_EVENT_REVIEW` | 400 | Invalid review action |
| `VALIDATION_ERROR` | 400 | Invalid request body |
| `INTERNAL_ERROR` | 500 | Server error |
