# Server File Index

Rust backend (activities API, aggregators, RBN proxy). Per-module deep indexes live in `docs/index/`.

## src/

| file | purpose |
|------|---------|
| `main.rs` | HTTP server setup, routing, middleware |
| `error.rs` | AppError type with HTTP status mapping |
| `config.rs` | Config struct loaded from environment |
| `extractors.rs` | Custom Axum extractors for JSON/Path with error handling |
| `metrics.rs` | Prometheus metric definitions and HTTP timing middleware |
| `observability.rs` | Structured logging (`LOG_FORMAT` json/pretty/compact subscriber) + `X-Request-Id` correlation middleware with per-request span and completion log (CAR-156); see `docs/logging.md` |
| `snapshots.rs` | Periodic disk snapshots of aggregated data for fast startup |
| `sota_az.rs` | SOTA activation-zone computation from Terrarium DEM tiles (slippy math, elevation decode, flood fill, contour, simplify) with unit tests |

## src/handlers/

| file | purpose |
|------|---------|
| `mod.rs` | Module exports |
| `challenges.rs` | GET/POST/DELETE routes for QSO challenges |
| `auth.rs` | Phase 5 `/v1/auth/*` — magic-link verify, token issue/refresh, logout |
| `oauth.rs` | Third-party OAuth2/OIDC provider `/v1/oauth/*` — authorize/token/device/userinfo/revoke, grants, admin client registration |
| `oauth_pages.rs` | Server-rendered consent + device-verification screens (self-contained HTML/JS, inline magic-link sign-in) |
| `activity_feed.rs` | Activity feed and reporting endpoints |
| `users.rs` | User profile and settings endpoints |
| `clubs.rs` | Club management and membership routes |
| `clubs_admin.rs` | Admin-only club deletion/modification |
| `badges.rs` | Challenge badge image upload/list/delete endpoints |
| `achievements.rs` | Profile achievement catalog and award endpoints (manual + auto + signal) |
| `progress.rs` | User progress (challenges, stats) endpoints |
| `leaderboard.rs` | Leaderboard queries and rankings |
| `programs.rs` | Activity program CRUD routes |
| `spots.rs` | RBN/aggregated radio spot endpoints |
| `invites.rs` | Invite token creation and redemption |
| `invite_page.rs` | HTML invite landing page |
| `link_page.rs` | Enriched share link landing pages (`/link/{call,park,sum,qso,act}`) + AASA + `link-card.js` route |
| `friends.rs` | Friend request and friend list endpoints |
| `participants.rs` | Event/contest participant management |
| `events.rs` | Event CRUD and calendar endpoints |
| `events_admin.rs` | Admin event modification |
| `contests.rs` | Contest definition and result endpoints |
| `equipment.rs` | Equipment catalog and user equipment |
| `equipment_usage.rs` | Equipment usage logs |
| `historic_trails.rs` | Historic trail/boundary endpoints |
| `park_boundaries.rs` | POTA/SOTA/park boundary query endpoints |
| `admin_boundaries.rs` | US state/county boundary query endpoint (bbox + kind) |
| `sota_zones.rs` | SOTA activation-zone endpoint (POST codes+coords; returns cached, enqueues bounded background compute) |
| `pota_stats.rs` | POTA activator statistics |
| `rbn.rs` | Reverse Beacon Network WebSocket proxy |
| `websdr.rs` | KiwiSDR proxies for the logbook Spots page: cached directory fetch, /status probe, websocket byte bridge (SSRF-validated) |
| `twilio_webhook.rs` | SMS spotting inbound webhook |
| `metrickit_telemetry.rs` | iOS crash/performance telemetry |
| `upload_error_telemetry.rs` | iOS upload error logs |
| `health.rs` | Health check endpoint — 200/503 with `database: ok|error` (SELECT 1, 2 s timeout) + RBN info |
| `propagation.rs` | VOACAP propagation forecast endpoint — proxies to Python sidecar with cache lookup |
| `callsign_enrichment.rs` | Public read endpoints for per-callsign membership data (CWops, future SKCC, …): dataset (full, ETag) + per-callsign |
| `amsat_status.rs` | Public `GET /satellites/amsat-status` — aggregated AMSAT community satellite status (last heard, 24h counts, curated NORAD ids); `GET /satellites/amsat-status/activity?hours=` — hour-bucketed report histogram per satellite (Heard / Not Heard / Telemetry / Crew / other) folded from `amsat_report`; `GET /satellites/amsat-status/reports?norad=|name=&hours=` — raw reports (callsign, grid, verdict) for one bird, newest first, ≤500 |
| `sync.rs` | `/v1/sync/*` E2E journal endpoints: push (reserve seqs + presign PUT), changes, two-phase snapshot (begin → upload → commit verifies the blob via HEAD before moving the pointer/GC; CAR-334), bootstrap, key escrow. Requires an account tenant — legacy `fd_` tokens get 403 ACCOUNT_REQUIRED |
| `sync_admin.rs` | Admin orphan sync tenants: list legacy participant-tenant data + adopt (re-key) onto the callsign's account |

## src/models/

| file | purpose |
|------|---------|
| `mod.rs` | Module exports |
| `achievement.rs` | Profile achievement catalog and award response types |
| `activity.rs` | Activity request/response types |
| `badge.rs` | Challenge badge definition types |
| `challenge.rs` | Challenge request/response types |
| `contest_definition.rs` | Contest format types |
| `equipment.rs` | Equipment catalog and user equipment types |
| `event.rs` | Event request/response types |
| `club.rs` | Club types and responses |
| `friend_invite.rs` | Friend invite types |
| `friend_request.rs` | Friend request types |
| `historic_trail.rs` | Historic trail types |
| `invite.rs` | Invite token types |
| `park_boundary.rs` | Park boundary GeoJSON types |
| `admin_boundary.rs` | US state/county boundary GeoJSON types |
| `sota_zone.rs` | SOTA activation-zone request/response (FeatureCollection) types |
| `participant.rs` | Event/contest participant types |
| `pota_stats.rs` | POTA statistics types |
| `program.rs` | Activity program types |
| `progress.rs` | User progress and stat types |
| `spot.rs` | Radio spot types (RBN, aggregated) |
| `spot_marker.rs` | Spot marker/annotation types |
| `metrickit_telemetry.rs` | iOS telemetry types |
| `upload_error_telemetry.rs` | Upload error telemetry types |
| `user.rs` | User profile types |
| `propagation.rs` | VOACAP propagation request/response types (path, frequency, hour, signal strength) |
| `callsign_enrichment.rs` | Wire types for `/callsign-enrichment/*` endpoints: dataset, per-callsign response, compact membership row |
| `amsat_status.rs` | Wire types for `/satellites/amsat-status` and `/activity` (camelCase, None fields omitted); `AmsatReportKind::classify` maps AMSAT verdict strings to bucket counters |
| `sync.rs` | Sync journal row + request/response types (push/changes/snapshot begin+commit/bootstrap/key) and the `sync_snapshot_pending` row, camelCase wire |

## src/db/

| file | purpose |
|------|---------|
| `mod.rs` | Module exports |
| `achievements.rs` | Profile achievement catalog and award queries |
| `activities.rs` | Insert/query activity log |
| `auth.rs` | Phase 5 OAuth persistence — accounts/devices/refresh rotation, `assert_account_owns_callsign`, email verifications |
| `oauth.rs` | Third-party OAuth persistence — clients, authorization codes, device codes, consent grants, client-owned device installs |
| `badges.rs` | Challenge badge image queries |
| `challenges.rs` | Challenge CRUD queries |
| `clubs.rs` | Club CRUD queries |
| `contest_definitions.rs` | Contest definition CRUD |
| `equipment.rs` | Equipment catalog queries |
| `equipment_usage.rs` | Equipment usage log queries |
| `events.rs` | Event CRUD queries |
| `friend_invites.rs` | Friend invite queries |
| `friend_requests.rs` | Friend request queries |
| `historic_trails.rs` | Historic trail queries |
| `invites.rs` | Invite token CRUD |
| `park_boundaries.rs` | Park boundary fetch/cache queries |
| `admin_boundaries.rs` | US state/county boundary bbox queries (QueryBuilder) |
| `sota_zones.rs` | SOTA activation-zone cache queries (by codes, pending sentinel, upsert/mark-none) |
| `participants.rs` | Event/contest participant queries |
| `pota_stats.rs` | POTA stats upsert queries |
| `programs.rs` | Activity program queries |
| `progress.rs` | User progress aggregate queries |
| `spot_markers.rs` | Spot marker CRUD |
| `spots.rs` | Aggregated spot upsert queries |
| `metrickit_telemetry.rs` | Telemetry insert/query |
| `upload_error_telemetry.rs` | Error telemetry insert/query |
| `users.rs` | User profile queries |
| `propagation_cache.rs` | VOACAP forecast cache lookup/insert keyed by path + month + SSN |
| `callsign_enrichment.rs` | Persistence layer for callsign enrichment: list/replace per-source rows, single + dataset reads |
| `amsat_status.rs` | AMSAT status rows: transactional replace-all + list; raw `amsat_report` accumulation (dedup insert that evicts a superseded verdict for the same callsign/hour/period, `latest_reported_at` poll cursor, per-satellite window read, multi-name capped read for the reports feed, prune, hourly `activity_counts` GROUP BY) |
| `sync.rs` | Sync journal persistence: atomic per-tenant seq reservation, entry insert (idempotent), changes/cursor/key-blob, pending snapshots + forward-only guarded `commit_snapshot` |

## src/storage/

| file | purpose |
|------|---------|
| `mod.rs` | `BlobStore` trait (presign PUT/GET, head, delete) + `BlobMeta` + `from_config` selecting memory vs S3 |
| `memory.rs` | In-memory `BlobStore` for tests + dev blob PUT/GET routes (infra-free) |
| `s3.rs` | Production `S3Store` over `object_store` (S3/R2/MinIO); real presigned URLs |

## src/achievements/

| file | purpose |
|------|---------|
| `mod.rs` | Evaluator engine: inline/batch dispatchers, EvalCtx, idempotent award writer, cross-platform check |
| `firsts.rs` | Inline: first-qso, first-cw, first-ssb, first-ft8, mode-polyglot |
| `counts.rs` | Batch: qso-100/1k/10k from sessionCompleted qsoCount; dxcc-10/100 |
| `coverage.rs` | Batch: all-hf bands seen via newBand/sessionCompleted/newDXCCEntity |
| `streaks.rs` | Batch: streak-7/30/365 from dailyStreak/potaDailyStreak streakDays |
| `anniversary.rs` | Batch: one-year-on milestone via users.created_at |
| `quirky.rs` | Inline: night-owl (UTC 02-04 hour), eyeball (worked friend = registered user) |

## src/aggregators/

| file | purpose |
|------|---------|
| `mod.rs` | Task spawner for all background aggregators |
| `pota.rs` | Fetch POTA activator spots from pota.app API |
| `pota_stats.rs` | Fetch POTA park activation statistics |
| `sota.rs` | Fetch SOTA peak activation spots |
| `park_boundaries.rs` | Fetch park GIS boundaries from ArcGIS/PADUS |
| `historic_trails.rs` | Fetch historic trail boundaries |
| `polish_park_boundaries.rs` | Polish park-specific boundary sources |
| `state_park_sources.rs` | US state park data source mapping |
| `achievements.rs` | Periodic batch evaluator sweep (recently-active callsigns + idempotent awards) |
| `callsign_enrichment.rs` | Daily poll loop for callsign membership sources (CWops PoLo today; pluggable formats); ETag-aware refresh + replace-on-success |
| `club_rosters.rs` | Scheduled roster reconciliation for clubs with a `notes_url` (PoLo notes file): adds new callsigns, drops departed `member` rows, never touches admins; also backs the admin import-notes endpoint |
| `amsat_status.rs` | AMSAT community status poll loop against AMSAT's status API (`status.amsat.org/api/v1`, legacy-host fallback while its catalog is empty pre-migration, descriptive User-Agent): `catalog.php` for the satellite list (`SO-50_[FM]`-style API names), one `reports.php?since=<newest stored − 2 h>&limit=500` for new reports (per-satellite paced re-read only when the page is full), accumulates raw reports in `amsat_report` (8 d retention, period-aware verdict replacement) and summarizes last-heard + counts from the stored window with curated NORAD mapping, replaces `amsat_status` wholesale |

## src/auth/

| file | purpose |
|------|---------|
| `mod.rs` | Module exports |
| `middleware.rs` | Dual-auth social-API middleware: accepts a Phase 5 JWT (with participants bridge) OR a legacy `fd_` token; `AuthContext`, `ApiAuthState`, `require_admin` |
| `token.rs` | Device token generation and validation (legacy `fd_` path) |
| `jwt.rs` | Phase 5 EdDSA JWT access tokens — mint/verify, key loading |
| `jwt_middleware.rs` | Phase 5 `require_jwt_auth` bearer middleware + `JwtAuthContext` (account-management routes) |
| `directory.rs` | Phase 5 callsign→on-file email resolver (QRZ XML; Null/Fixed variants) for the directory-email tier (D6/F1) |
| `tokens.rs` | Phase 5 opaque `cwr_` refresh tokens — gen/hash, PKCE S256 helpers |
| `mailer.rs` | Phase 5 transactional email (Resend + dev NullMailer) for magic links |
| `revocation.rs` | Phase 5 in-process revocation cache + Postgres LISTEN/NOTIFY listener (D10/F3) |
| `scope_map.rs` | **Default-deny policy for third-party tokens** — which routes a `cid` token may reach and under what scope; drift test forces every `main.rs` route to be classified |

## src/contest/

| file | purpose |
|------|---------|
| `types.rs` | Contest definition data types and enums |
| `validation.rs` | Semantic validation pass for contest definitions |
| `engine.rs` | Scoring engine and Cabrillo export |

## src/rbn/

| file | purpose |
|------|---------|
| `mod.rs` | Module exports |
| `ingester.rs` | WebSocket client that injects RBN spots into SpotStore |
| `store.rs` | In-memory spot cache with TTL eviction |

## migrations/

| file | purpose |
|------|---------|
| `001_initial_schema.sql` | Users, challenges, leaderboard tables |
| `002_seed_challenges.sql` | Default challenge seed data |
| `003_friend_system.sql` | Friends and friend requests tables |
| `004_seed_friends.sql` | Demo friend data |
| `005_activities.sql` | Activity log table |
| `006_programs.sql` | Activity program definitions |
| `007_spots.sql` | Aggregated radio spot table |
| `008_clubs.sql` | Clubs and membership tables |
| `009_pota_park_stats.sql` | POTA stats table |
| `010_club_notes.sql` | Club notes column |
| `011_park_boundaries.sql` | Park boundary GeoJSON table |
| `042_admin_boundaries.sql` | US state/county boundary PostGIS table (loaded via scripts/import-admin-boundaries.sh) |
| `043_sota_activation_zones.sql` | SOTA activation-zone PostGIS table (computed on demand from DEM, keyed by summit code) |
| `012_historic_trails.sql` | Historic trail GeoJSON table |
| `013_reset_park_boundaries.sql` | Park boundaries schema reset |
| `014_pota_fetch_consecutive_errors.sql` | Error tracking for POTA fetcher |
| `015_trail_fetch_consecutive_errors.sql` | Error tracking for trail fetcher |
| `016_add_anza_trail.sql` | Add Anza Borrego Desert State Park trail |
| `017_ntir_trail_sources.sql` | National Trails source configuration |
| `018_reset_exact_match_boundaries.sql` | Boundary matching reset |
| `019_events.sql` | Event definition and participation tables |
| `020_event_days.sql` | Event day/schedule table |
| `021_upload_error_telemetry.sql` | iOS upload error log table |
| `022_metrickit_telemetry.sql` | iOS crash/perf telemetry table |
| `023_participants_upper_callsign_index.sql` | Participant callsign search index |
| `024_club_logos.sql` | Club logo URLs column |
| `025_spot_markers.sql` | Spot annotation/marker table |
| `026_callsign_history.sql` | Callsign history tracking |
| `027_equipment_catalog.sql` | Equipment database table |
| `028_equipment_seed_data.sql` | Default equipment records |
| `029_equipment_connectors.sql` | Equipment connector types |
| `030_equipment_submissions.sql` | User-submitted equipment data |
| `031_equipment_usage.sql` | Equipment usage log table |
| `032_contest_definitions.sql` | Contest definition storage |
| `033_propagation_cache.sql` | VOACAP propagation forecast cache table |
| `034_achievements.sql` | Profile achievements catalog + user_achievements awards + seed catalog |
| `035_beta_tester_awards.sql` | Beta tester achievement seed |
| `036_founding_supporters_and_contributors.sql` | Founding supporter and contributor achievement seeds |
| `037_callsign_enrichment.sql` | Callsign enrichment sources + per-callsign membership rows (CWops seeded) |
| `038_callsign_enrichment_bkg.sql` | Seed Brass Knuckle Gang (BKG) callsign enrichment source |
| `039_callsign_enrichment_skcc.sql` | Seed Straight Key Century Club (SKCC) callsign enrichment source |
| `049_club_roster_sync.sql` | `clubs.roster_synced_at` / `roster_sync_status` bookkeeping for the club roster aggregator |
| `040_hamstick_hustler_equipment.sql` | Seed Hamstick mono-band whips and Hustler RM resonator modules into equipment catalog |
| `046_sync.sql` | Sync journal schema: `sync_entry` (per-tenant seq), `sync_cursor` (allocator + snapshot ptr), `sync_key_blob` (escrow) |
| `047_oauth_provider.sql` | Third-party OAuth: `oauth_clients`, `oauth_authorization_codes` (PKCE), `oauth_device_codes` (RFC 8628), `oauth_grants` (consent), `devices.oauth_client_id` |
| `050_sync_snapshot_pending.sql` | `sync_snapshot_pending`: presigned-but-uncommitted snapshots for the two-phase snapshot protocol (CAR-334); only `sync_cursor` holds the live pointer |
| `051_amsat_report.sql` | `amsat_report`: raw AMSAT community reports accumulated across aggregator cycles (PK name + hour + callsign + verdict), the source of the `/satellites/amsat-status/activity` grid |
| `052_amsat_report_period.sql` | `amsat_report.period` (AMSAT's 15-minute slot, 0–3) so a re-filed report replaces the earlier verdict instead of sitting beside it |

## server/web/src/pages/

(See `server/web/` — admin React UI). New: `AchievementsAdmin.tsx` — catalog viewer, single award/revoke, batch award, backfill trigger.

## tests/

| file | purpose |
|------|---------|
| `e2e.sh` | End-to-end bash integration tests |
| `integration_test.rs` | Rust integration test entry |
| `sync_db.rs` | Sync seq-reservation DB tests (gap-free/monotonic/concurrent); skips without `TEST_DATABASE_URL` |
| `sync_endpoints.rs` | Sync HTTP round-trip tests (push/upload/changes/download, idempotency, bootstrap, two-phase snapshot: commit-without-upload, out-of-range seq, forward-only pointer, abandoned snapshot); skips without DB |
| `sync_s3_smoke.rs` | Live S3/R2 presigned round-trip smoke test; runs only when `SYNC_S3_*` set |
| `request_id.rs` | `X-Request-Id` echo/generation/propagation through `observability::instrument` + JSON completion-line field assertions via a captured subscriber; no DB |

## Other

| path | purpose |
|------|---------|
| `web/` | React/TypeScript admin UI (Vite). `src/pages/`, `src/components/`, `src/api/` |
| `logbook-web/` | Logbook viewer for the E2E sync server (Vite/React/TS), served at `/logbook`. `src/auth/` (magic-link+PKCE), `src/sync/` (client+ADIF; `writeClient.ts` delete write-back with parked/resumable blob uploads, `retry.ts` + `retry.test.ts` backoff policy, vitest), `src/wasm.ts` (cw-web-crypto WASM), `src/pages/`, `src/spots/` (Spots page: spots client, KiwiSDR listener, AudioWorklet player). `vendor/cw-web-crypto/` = committed wasm pkg. See `docs/features/logbook-web.md`. |
| `propagation/` | Python VOACAP sidecar (FastAPI) — `app/main.py`, `app/engine.py`, `app/schemas.py`, Dockerfile, tests |
| `ios-admin/` | ChallengesAdmin iOS app (Xcode project) |
| `scripts/` | Helper scripts (`import-equipment-tsv.py`, `ingest_club_logos.sh`, `import-admin-boundaries.sh`, `programs`, etc.) |
| `docs/api.md` | REST API reference |
| `docs/cicd.md` | CI/CD pipeline documentation |
| `docs/features/` | Feature specs (auth, oauth-api, challenges, contest-definitions, events, leaderboards, logbook-web, propagation) |
| `examples/oauth-log-client/` | Runnable reference client for the third-party OAuth log API (Node/TS): device flow, escrow unlock, journal fold, push. See `docs/features/oauth-api.md`. |
| `docs/index/` | Deep per-module code indexes (auth, contest, core, db, handlers, historic_trails, migrations, models, park_boundaries, pota_stats, rbn, tests) |
| `docs/plans/` | RFCs and implementation plans |
