# Android parity batch: profile, epochs, heatmap, Carrier Wave sync

Four iOS→Android parity features, designed together because they interlock
(profile unblocks correct logging; the epoch fix must land before more code
grows on mixed units; heatmap + sync both read `qso_date`).

## 1. User profile settings (callsign + home grid)

**Problem:** `CwApp.MY_CALLSIGN`/`HOME_GRID` were compile-time constants
("W6JY"/"CM87") — unusable for any other operator, stamped on every QSO.

**Design:**
- `data/UserProfile.kt` — SharedPreferences-backed (same `cw` prefs file as
  `ServerConfig`), keys `user_callsign` / `user_home_grid`, normalized
  (callsign uppercased; grid in CM87xj Maidenhead case convention).
- `CwApp.userCallsign` / `userHomeGrid` — `@Volatile var`, loaded in
  `onCreate`, written via `CwApp.updateProfile()` which also updates
  `repository.homeGrid` and re-emits the QSO snapshot so grid-derived stats
  (Best DX, distances) recompute.
- **Seed-on-upgrade:** if the profile was never set, seed it from the newest
  QSO's `myCallsign`/`myGrid` (async at startup) so existing logbooks keep
  their identity with zero re-entry.
- "Operator profile" card at the top of the Account screen (callsign +
  grid fields, grid validated via `maidenheadIsValid`, error hint when
  callsign is blank).
- Read sites repointed (6): MainActivity club detail, Hunter/Activation VM
  factories, LoggerViewModel (read at log time, blank → null), Logger myGrid,
  EnrichmentBadges distance/bearing.

## 2. qsoDate epoch migration (millis → seconds)

**Problem:** the standalone Logger wrote `qsoDate`/`importedAt`/`modifiedAt`
in Unix **milliseconds**; the cw-store contract is Unix **seconds**
(`cw-store/src/qso.rs:24` DDL comment; `SessionApi`/`ActivityLogApi` stamp
`Utc::now().timestamp()`; iOS `SwiftDataStoreImporter.unix()` truncates to
seconds). `CoreQsoRow` papered over it with a `×1000`.

**Design — canonical unit is seconds everywhere:**
- All `Format.kt` timestamp helpers take epoch **seconds** (×1000 internally
  at the `SimpleDateFormat` boundary).
- Logger write path stamps seconds (`System.currentTimeMillis() / 1000`,
  `zuluToEpochSeconds`).
- `CoreQsoRow` drops its ×1000; `FriendsScreen` feed row drops its ×1000.
- **One-time data fixup** (`CwApp.fixLegacyEpochsIfNeeded`, guarded by prefs
  flag `epoch_fixup_done`): page through all QSOs (1000/page); any of the
  three timestamps `> 100_000_000_000` (year ~5138 as seconds, 1973 as
  millis — unambiguous) is divided by 1000 and the row upserted back.

## 3. Activity heatmap (Home)

iOS has a GitHub-style 52-week activity grid. The FFI has **no per-day
aggregation** (`FfiAggregateDimension` = BAND / MODE_FAMILY / DXCC / MONTH
only), so:

- `LogbookRepository.dayCounts()` — paged `fetchQsos` with
  `FfiQsoFilter(since = now − 371 days)` (53 weeks, covers partial first
  column), grouped client-side by `utcDayKey` → `Map<String, Int>`. Runs on
  `Dispatchers.IO`; recomputed when the shared snapshot changes.
- `HeatmapCard` on Home (below the Today card): 7-row × 53-column grid of
  small rounded cells, GitHub-style; 5-level intensity scale from
  `surfaceVariant` to `primary` (quantile thresholds 1/25%/50%/75% of max);
  horizontally scrollable, auto-scrolled to the current week; month labels
  above; "N QSOs in the last year" footer.
- Deliberately not ported: tap-through day summary (iOS drill-down) — later.

## 4. Carrier Wave sync (E2E sync server)

The Rust sync core landed 2026-06-30 (`cw-crypto` escrow, `cw-sync`
`HttpSyncTransport`, `cw-ffi` `create_sync_escrow`/`open_sync_escrow`/
`sync_run_once`/`_push`/`_pull`). Server deployed to **staging only** —
prod has no `/v1/sync/*` routes yet, so Android testing points the
server-URL setting at `https://staging.carrierwave.app`.

**Verified semantics** (code, not the stale docstring): `high_water` in the
run results is the real server cursor (tracked from push + pull responses in
`HttpSyncTransport::last_high_water`) — the host persists it and passes it
as `since_seq` next run. The stale "echoes since_seq" module note gets fixed.

**Gap — no client for the escrow envelope endpoints.** The server has
`PUT/GET /v1/sync/key` but nothing calls it. Escrow fetch must work
*without* the data key (that's what you're recovering), so it can't hang off
`HttpSyncTransport::new(…, data_key)`:

- `cw-sync/src/http_transport.rs`: free functions
  `put_key_blob(base_url, bearer, wrapped_key_b64, kdf_params_json)` and
  `get_key_blob(base_url, bearer) → Option<(wrapped_key_b64, kdf_params_json)>`
  (404 → `None`), same `HttpClient` + owned-runtime idiom as the transport.
  Wiremock round-trip test.
- `cw-ffi/src/sync_transport.rs`: `SyncKeyEnvelope` record +
  `sync_put_key` / `sync_get_key` exports.
- Gate: build + clippy + test (NO `cargo fmt` — cw-core is hand-formatted).
- Kotlin bindings regenerate automatically via the gradle `buildRustCore`
  task; the regen also picks up the already-landed sync surface (note:
  `FfiQsoFilter` gains `dirtyOnly`, breaking existing Kotlin constructors —
  fixed as part of this).

**Android integration:**
- `data/SyncConfig.kt` — prefs: `sync_last_seq` (cursor), last-sync time;
  the 32-byte data key lives base64'd in `AndroidSecureStore` (Keystore).
- "Carrier Wave Sync" card in Account (own `SyncViewModel`), three states:
  1. Not signed in → hint (sync needs the OAuth bearer).
  2. Signed in, no key → passphrase field + "Enable sync":
     `sync_get_key` → envelope exists ⇒ `open_sync_escrow` (recover; wrong
     passphrase surfaces `CwError::Crypto`); no envelope ⇒
     `create_sync_escrow` + `sync_put_key`, then `markAllDirty("qso")` so
     the first push uploads the whole logbook.
  3. Enabled → "Sync now" (`sync_run_once(store, baseUrl, bearer, dataKey,
     cursor)`), pushed/pulled counts, last-sync line, "Turn off" (clears the
     local key only; the server escrow stays for re-enable).
- Bearer from the shared `AuthApi` token accessor; every FFI sync call on
  `Dispatchers.IO` (ANR guard — same rule as clubs/friends).
- Auto-sync: one best-effort `sync_run_once` at app start when enabled;
  everything else manual. Background scheduling deferred.

**Out of scope / notes:** iOS Phase 7 remains separate; authority stays
CloudKit on iOS. Two-device verification of Android↔Android (or
Android↔logbook-web) sync happens against staging. Non-QSO entities ride
the same journal later.
