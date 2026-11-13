# Stale callsign after a user changes their call

**Date:** 2026-08-27
**Symptom:** Another operator changed their callsign days ago; the old call is still displayed.
**Status:** FIXED (same day) — see "Fixes applied" at the bottom.

## TL;DR

- The server has **no QRZ/callbook result cache**. Server-side staleness comes from
  denormalized callsign columns that `change_callsign()` misses, plus the callsign
  baked into JWTs.
- Two findings do not self-heal:
  1. **Server:** `accounts.primary_callsign` / `account_callsigns` are never updated on a
     callsign change, and the JWT `cs` claim is re-minted from them, so the old identity
     is *permanently re-asserted* (participants row recreated under the old call).
  2. **iOS:** the `operator_profiles` GRDB table has no TTL and no delete path; the disk
     fast path serves it with zero freshness check.
- A third: the `/v1/clubs` ETag fingerprint doesn't move after `change_callsign`, so
  clients get `304` forever and keep the old call in club rosters.

## Server (`server/`)

### Critical: JWT `cs` + OAuth account tables never updated

- `server/src/db/users.rs:139-249` — `change_callsign()` updates `participants`,
  `challenge_participants`, `progress`, `earned_badges`, `activities`, `club_members`,
  `events.submitted_by`, `spots`, `upload_error_telemetry`, `users` — and nothing else.
- Nothing anywhere does `UPDATE accounts SET primary_callsign` or touches
  `account_callsigns` after creation (`server/src/db/auth.rs:145` is insert-only).
- `server/src/auth/jwt.rs:212` stamps `cs: primary_callsign` into every access token;
  every re-mint (`handlers/auth.rs:383,548`, `handlers/oauth.rs:651,732,748`) re-reads
  the same stale `accounts.primary_callsign`. Token TTLs (15 min access / 60 day refresh)
  don't help because the source stays stale.
- `server/src/auth/middleware.rs:161` — `get_or_create_participant(&claims.cs, None)`
  **recreates a participants row under the OLD call** on the next authenticated request
  after a successful `PUT /v1/account/callsign`. `jwt.rs:44` explicitly warns against
  trusting `cs`; the middleware does it anyway. This is the self-resurrecting bug.

### Tables `change_callsign` misses (denormalized, no invalidation)

| Table | Where | Effect |
|---|---|---|
| `accounts.primary_callsign`, `account_callsigns` | `migrations/044_oauth_accounts.sql` | See above |
| `user_achievements.callsign` | `migrations/034_achievements.sql`, read `db/achievements.rs:44-56` | Awards orphaned under old call |
| `spot_markers.callsign` | `migrations/025_spot_markers.sql`, `db/spot_markers.rs` | SMS self-spot posts old call |
| `macros.author_callsign` | `migrations/041_macros_registry.sql`; slug ownership check `macros/slug.rs:53,77` | Old author call; ownership check breaks |
| `email_verifications.callsign` | `migrations/044_oauth_accounts.sql:49` | Pending verifications pinned to old call |
| `pota_activations` / `pota_hunter_qsos` | deliberately excluded (`db/users.rs:138`) — external POTA data | Park stats keep old call |

`merge_previous_account` (`db/users.rs:255-397`) covers an even smaller set.

### Club roster ETag never moves

- `server/src/db/clubs.rs:447-470` — fingerprint is
  `GREATEST(MAX(clubs.updated_at), MAX(club_members.joined_at))`.
- `change_callsign` updates `club_members.callsign` but bumps neither column →
  `/v1/clubs` and `/v1/clubs/membership` (`handlers/clubs.rs:93-150,399-433`) return
  `304 Not Modified` indefinitely → clients keep the old call in rosters.

### Aggregators / other

- Callsign enrichment (CWops/SKCC/BKG): 24 h cycle (`config.rs:263`), rows keyed
  `(callsign, source)`; new call appears only when the *upstream list* publishes it.
- POTA stats aggregator snapshots callsigns from the POTA API; disk snapshots
  (`snapshots.rs:53-70`) can re-import old calls on restart.
- `/link/call/:callsign` pages: `public, max-age=3600, s-maxage=86400` (shell only;
  callsign is client-rendered).
- In-memory: QRZ *session key* only (`auth/directory.rs`) — no lookup-result caching.
  No nginx proxy_cache.

## iOS (`swift/`)

### Primary suspect: `operator_profiles` GRDB table — permanent, no invalidation

- Table: `CarrierWaveData/Query/Models/OperatorProfileRow.swift:42`, schema
  `Query/Schema/Migrations.swift:93`. Keyed by uppercased callsign; stores name, QTH,
  grid, license class, source (`"qso"`/`"qrz"`), `enrichedAt`.
- `QueryStore` (`Query/QueryStore.swift:120-146`) exposes get/upsert/count only —
  **no delete, no prune, no age filter**.
- `OperatorProfileService.cachedInfoSync` (`Services/OperatorProfileService.swift:72`)
  returns any row with meaningful data, no age check; in-memory snapshot never evicted.
- `record(_:)` (`:139`) writes QRZ results keyed by the **new canonical call** — the
  old-call row is never touched. Old call keeps rendering its old profile forever.
- Settings "rebuild" (`Views/Settings/OperatorProfileCacheView.swift:53-56,104`)
  **does not fix this**: `persistBackfill` skips rows where
  `source == "qrz" && enrichedAt != nil` (`OperatorProfileService.swift:359-366`).

### `CallsignLookupService`

- In-memory LRU: 100 entries, 1 h TTL (`Services/CallsignLookupService.swift:141-155`).
  `clearCache()` (`:232`) has **no callers** — dead code.
- `lookupWithResult` disk fast path
  (`Services/CallsignLookupService+Lookup.swift:32`) returns the disk row immediately
  with **zero age check**, then schedules background enrichment — so the current render
  is stale; only the next lookup is fresh. Callers: `LoggerView+MultiLookup.swift:101`,
  `QuickLogSection+Lookup.swift:146`.
- `lookupStream` (`+Lookup.swift:102-142`) always re-queries QRZ after the cached first
  emission → self-heals. (Dashboard card, logger, operators sheet, peek sheet, etc.)
- No legacy Swift XML callbook path remains; lookups go through `QrzCallbookClient` →
  Rust `QrzApi`.

### Rust core (`rust/cw-core/`)

- `QrzApi::lookup` does **not** cache results — live QRZ round trip each call; only the
  session key is cached (`cw-ffi/src/qrz_api.rs:97`).
- `callbook_location` SQLite cache (`cw-store/src/callbook_location.rs:27`): 30-day TTL
  applied at read time; location-only, can't display a wrong call.
- **Spot engine enrichment cache** (`cw-ffi/src/spot_engine/api.rs:100`): callsign →
  `{state, country, operator_name, grid}`, nominal 30-day TTL — but the TTL is only
  applied on disk load (`:926-935`); in-session reads (`:509-512`, `:872-877`) do no age
  check. Persisted to `spot-enrichment-cache.json`. Can render a stale `operator_name`
  next to a spot. No clear path exposed.

### Low risk

- `CallsignEnrichmentCache` (12 h + ETag), `CallsignNotesCache` (24 h),
  `ClubsSyncService` in-memory map (rebuilt per sync but poisoned by the server ETag bug
  above), friends table (`friend_callsign` overwritten every sync).
- User's *own* callsign: `UserProfileService` is canonical (CAR-287); Keychain/
  UserDefaults are reconciled derived caches — working as designed.

## Fixes applied (2026-08-27)

Server (`server/`):
- `db/users.rs` `change_callsign()` now also (in the same transaction): updates
  `user_achievements`, `spot_markers`, `macros.author_callsign`; touches
  `clubs.updated_at` for the member's clubs so the `/v1/clubs` ETag moves;
  re-points `account_callsigns` (unique-violation → `CallsignTaken`, so a call
  claimed by another account still can't be stolen) and
  `accounts.primary_callsign`; bumps `tokens_valid_after` + `pg_notify` on the
  revocation channel so outstanding old-`cs` access JWTs die immediately while
  refresh tokens keep working (devices re-mint under the new call silently).
- `auth/middleware.rs`: the OAuth path resolves the acting callsign via
  `SELECT primary_callsign FROM accounts WHERE id = claims.sub` instead of
  trusting `claims.cs`; a missing account rejects the token.
- Deliberately NOT updated: `email_verifications` (15-min TTL rows whose
  callsign is the thing being verified — rewriting them would corrupt the
  verification), POTA tables (external data, per existing policy).

iOS (`swift/`):
- `OperatorProfileService.enrichmentStaleness` (7 days): the disk fast path in
  `CallsignLookupService+Lookup.swift` only short-circuits when the row's
  `lookupDate` is within it; stale rows fall through to a live lookup (the
  merge still uses the cached row as offline fallback).
- New `OperatorProfileService.forget(_:)` + `QueryStore.deleteOperatorProfile`:
  when QRZ forward-resolves a queried call to a different canonical call
  (`dropStaleAlias`), the old-call row and its LRU entry are dropped — in both
  `runFullLookup` and `lookupStream`.
- `persistBackfill` now only preserves QRZ rows enriched within the staleness
  window, so the Settings rebuild refreshes stale enrichment instead of
  keeping it forever.

Rust core (`rust/cw-core/cw-ffi/src/spot_engine/api.rs`):
- `ENRICH_CACHE_TTL_SECS` now gates in-session reads: expired entries count as
  absent in `enrich_callsign_batch` (re-fetched + overwritten) and in the
  spotter-grid fast path, not just in `load_enrich_cache`.

Verified: `cargo build` + `cargo clippy --all-targets` clean on the server,
`cargo clippy -p cw-ffi --all-targets` clean + 22 spot_engine tests pass, and
the iOS app compiles for `generic/platform=iOS`.

Not addressed (pre-existing, lower priority): callsign-enrichment aggregator
waits on upstream lists by design; `/link/call/:callsign` CDN shell caching;
`merge_previous_account` still covers fewer tables than `change_callsign`;
`CallsignLookupService.clearCache()` remains uncalled.
