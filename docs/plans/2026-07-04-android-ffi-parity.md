# Android FFI Feature Parity Plan

2026-07-04. Goal: close the iOS↔Android feature gap by consuming the shared Rust
core (`cw-ffi`) on Android. Ordered by (Rust already exists) × (user value).

## Current Android surface

> **2026-07-04 scope change: Android is a hunting app for now.** Activation
> (session start) + the bare Logger tab were REMOVED; Hunter is a top-level
> tab with the live spot feed as its body (iOS ActivityLogView shape). The
> Phase-3 session-lifecycle work lives in git history for when sessions
> return. Bottom nav: Home · Hunter · Logbook · Map · Friends · More.

Home · Sessions (Session/Logger/Hunter/Spots) · Logbook · Map · Friends (Friends/Clubs) · More.
Consumes: `FieldStore`, `AuthApi`, `ClubsApi`, `FriendsApi`, `SpotsApi` (one-shot),
`QrzApi`, `EnrichmentApi`, `ActivityLogApi`, `SessionApi`, sync free-fns, quick-entry/
maidenhead/query free-fns.

Unused-but-bound: `SpotEngineApi`, `SdrApi`, `ScpDatabase`, `CtyDatabase`, `StoreObserver`,
`ContestApi`/`ContestEngineApi`.

## Phases

### Phase 1 — Spot engine (no Rust changes) ✅ DONE (a0ae5b18, 2026-07-04)
Replace the Spots tab's one-shot `SpotsApi` fetchers with the full `SpotEngineApi`:
poll loop, merged sources, enrichment, worked-before/needs matching, freshness.
- Construct `SpotEngineApi` in `CwApp` with `FfiSpotEngineConfig`; feed
  `set_user_context` (profile grid/callsign), `set_cty_database` (CTY content the
  `EnrichmentApi` already caches), `set_worked_context` from `FieldStore`.
- `SpotEngineListener` → Kotlin `StateFlow` of snapshots (mirror iOS
  `SpotEngineProvider`).
- Rewrite `SpotsViewModel`/`SpotsScreen`: engine snapshot, band/mode/source filters,
  worked-before + club badges, pause/resume with lifecycle.
- Hunter tab spot list moves to the same snapshot source (iOS parity: hunter log
  spots come from the engine). **Deferred — Hunter tab has no spot list yet.**
- Deferred from Phase 1: needs snapshot (no Android needs engine yet), cluster
  connection UI, worked-context feed, DX-web trio + PSKR source toggles.

### Phase 2 — Logger/Hunter completeness ✅ DONE (74cd8dbd, 2026-07-04)
- ✅ `duplicate_status` badge in Logger + Activation quick-entry (Hunter had it).
- ✅ SCP suggestions in all three command bars via new Rust `ScpApi`
  (MASTER.SCP download, ETag + 7-day TTL, kv-cached — NOT files dir).
- ❌ Routing Logger through `ActivityLogApi.logQso` dropped: that API requires
  an active hunter log; attaching bare Logger QSOs to one would change
  semantics. Logger keeps `FieldStore.upsertQso` + now shows dupe status.

### Phase 3 — Session lifecycle ✅ DONE (2026-07-04)
- ✅ `end` now runs `split_at_utc_midnight` after `endSession` for POTA
  sessions (multi-day activations split per UTC day, Rust-tested).
- ✅ Delete session (with confirm dialog) on paused rows via `delete_session`.
- ❌ `record_conditions` deferred: needs a NOAA fetch, which is still
  Swift-only (`cw-net` has no exposed solar client yet).
- ❌ `save_average_wpm` deferred: WPM values come from the CW keyer (iOS
  hardware path) — nothing to average on Android.
- ❌ Merge/reopen deferred: no Android surface lists completed sessions yet.

### Phase 4 — Home dashboard stats parity ✅ FIRST SLICE DONE (2026-07-04)
- ✅ "Awards & Streaks" card: on-air streak current/longest (`brag_streaks`),
  WAS x/50 (`was_summary`), DXCC worked count (`dxcc_worked`).
- Remaining candidates: `brag_records`, `pota_awards`, `brag_distance_stats`,
  per-mode streaks — add cards as needed.

### Phase 5 — Contests (no Rust changes)
`ContestApi.refresh`/`summaries` + `ContestEngineApi` session mode: exchange
prefill, dupe status, serials, live score, Cabrillo export
(`contest_generate_cabrillo`).

### Phase 6 — ADIF import/export (small Rust check)
Import: `adif_parse` → `upsert_qsos` with dedup. Export: verify FFI has an ADIF
writer; if not, expose one from cw-domain (iOS export is Swift-side today).

### Phase 7 — Upload pipeline (NEW Rust required)
QRZ Logbook + POTA upload clients live in Swift only. Port to `cw-net` + FFI, then
flip the hardcoded `uploadQrz=false`/`uploadPota=false` in
`HunterLogViewModel`/`ActivationViewModel`. `ServicePresence` rows already flow.

### Later / stretch
- `SdrApi` WebSDR listening on Android (audio callback → AudioTrack).
- Band Scope (`compile_profile_queries` + scope SQL) once Phase 1 engine is in.
- Map overlays, needs management UI, WorkManager background sync.

## Out of scope (platform/hardware-bound)
Radio CAT control (BLE/USB/WiFi), CW keyer, FT8 audio engine, Pebble/Watch/widgets,
Live Activities, video export, log-scan OCR, Spotlight, NEXRAD overlay.
