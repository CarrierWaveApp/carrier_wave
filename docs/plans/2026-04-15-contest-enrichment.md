# Contest calendar enrichment

**Linear:** (TBD — track under On-Air / Contests area)
**Branch:** `claude/enhance-contest-calendar-zkFUB`
**Status:** Phase 1 in progress

## Motivation

The existing contest section in `OnAirSheet` shows each contest as a flat row
with a title and a start-time string. No mode/band context, no countdown, no
way to start logging from the card, and no way to see the whole month. The
screenshot in the original request looked like a bookmark list, not a
dashboard.

## Data sources surveyed

| Source | Status | Planned use |
|---|---|---|
| **WA7BNM RSS** (in use) | `calendar.rss` — structured-enough | Phase 1 baseline |
| **WA7BNM ICS** | Per-contest ICS links | Phase 2 "Add to Calendar" |
| **WA7BNM JSON/XML** | Requires written agreement with Bruce Horn | Reach out; would give us bands/modes/exchange directly |
| **ARRL contests.arrl.org** | HTML only | Skip; WA7BNM already mirrors rules links |
| **POTA scheduled activations** (unofficial API under `api.pota.app`) | Already consumed for live spots elsewhere in the app | Phase 2: blend into On-Air "events" calendar |
| **SOTA alerts** (`api2.sota.org.uk`) | Planned SOTA activations | Phase 2 |
| **WWFF Spotline** (`spots.wwff.co/agenda`, API on request) | | Phase 3 |
| **NG3K ADXO** | HTML only | Phase 3 (server-side scrape) |
| **eham.net/calendar** | HTML only, hamfests | Phase 3 (server-side scrape) |
| **daily.hamweekly.com/events/** | HTML only, curated | Phase 3 (server-side scrape) |
| **ARRL special-event / W1AW** | HTML only | Phase 3 |
| **3830scores** | Post-contest submissions — popularity signal | Phase 2 (static tier table) |
| **NG3K / ClubLog DXpeditions** | Partial JSON | Already covered by `DXpeditionsCard` |

HTML-only sources should be aggregated **server-side** through a new
`GET /v1/activity-events` endpoint in `server/` so the iOS client speaks a
single normalized `ActivityEvent` schema. Avoids shipping N brittle HTML
parsers to devices and lets us cache/rate-limit centrally.

## Phased implementation

### Phase 1 — this PR
- Enrich `Contest` model with bands, modes, duration, exchange preview,
  template match, popularity tier.
- `ContestEnrichment` service that parses WA7BNM description/title and
  matches against shipped templates in `CarrierWaveData/ContestTemplates/`.
- Richer row in `OnAirSheet` contests section: countdown, mode/band chips,
  duration chip, popularity dots, "Log Now" pill when a template exists.
- `ContestDetailSheet` for inline expand (rules link, exchange preview,
  "Log Now", "Remind me 30 min before", "Add to Calendar").
- `ContestCalendarView` (month grid + agenda list) with "See all" link from
  the contest section header.
- Local-notification reminders for starred contests (starred state in
  `UserDefaults`).
- Tests for `ContestEnrichment`.

### Phase 2 — follow-up PRs
- 3830-derived popularity weights (static JSON bundled in app, refreshed by
  server).
- `ActivityEvent` unified model and `ActivityEventsClient` hitting the new
  server endpoint.
- Blend POTA scheduled activations and SOTA alerts into the calendar view.
- VOACAP/N0NBH-derived "conditions at start" line on each row.
- Grayline badge for DX contests.
- Widget surface (upcoming-contest countdown).

### Phase 3 — server-side aggregation
- `server/src/aggregators/` modules for NG3K, eham, hamweekly, ARRL special
  events, W1AW schedule.
- Normalize → `ActivityEvent` schema with type (contest/dxped/hamfest/sota/
  pota/special/net), title, start/end, region, modes, bands, source URL,
  and hash for dedup across sources.
- Serve `/v1/activity-events?from=&to=&type=&region=` with etag + cache.

## Out of scope for this PR
- RBN-derived live-activity heatmap (needs RBN ingest in `server/`).
- "Your last score" lookup against past `LoggingSession`s (needs
  `contestId` field on session — tracked separately).
- Personalization based on license class / geographic relevance (needs
  country/region metadata in templates).

## Open questions
- Should `Contest` be promoted to `CarrierWaveData`? Leaving in
  `CarrierWave/Models/` for now since it's still RSS-only; move when the
  unified `ActivityEvent` lands.
- Popularity tier source — hard-code by contest ID for the known major
  contests, or derive from a bundled 3830 submission count snapshot?
  Going with hard-coded for Phase 1.
