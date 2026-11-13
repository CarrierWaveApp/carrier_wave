# Android Callsign-Enrichment Parity with iOS

**Date:** 2026-06-29
**Branch:** feat/android-sessions-hunterlog-rust
**Goal:** Bring Android callsign enrichment to feature parity with the iOS
`LoggerCallsignCard`. New logic lives in shared Rust (cw-ffi). UI keeps Android's
chip style (a richer chip flow), not a literal copy of the iOS card layout.

## Gap (today)

| Surface | iOS `LoggerCallsignCard` | Android `EnrichmentBadges` |
|---------|--------------------------|----------------------------|
| Shown | callsign · emoji · name · country flag · QTH/state/grid · license · **distance+bearing** · NATO · **prev-QSO count + dupe status** · P2P/S2S · **membership chips** (CWops/SKCC/clubs) · Polo note · prev-callsign · source | 🌍 DXCC name · SKCC badge · 👤 QRZ name |

Android already receives (but drops) CQ zone, continent, clubs, and QRZ
qth/state/grid/license/previous_callsign. It never computes distance/bearing
despite the maidenhead FFI existing.

## Decisions (from user)

- **Scope:** all three tiers (full parity).
- **New logic:** shared Rust (cw-ffi), per the rust-swift-parity convention.
- **UI:** Android chip style (extend the chip flow), not the iOS card layout.

## Faithful-port references (iOS sources)

- Flag table: `CallsignFlagHelper.swift` (prefix→flag, ordered 2-char before 1-char).
- Prev-QSO count: `LoggerView+Data.swift fetchPreviousQSOCount` — all-time, exact
  callsign, `!isHidden`, exclude WEATHER/SOLAR/NOTE.
- Dupe status: `LoggerView+Data.swift computeDuplicateStatus` /
  `classifyDuplicateStatus` — UTC-day scoped, POTA additionally park-scoped;
  `firstContact`/`previouslyWorked`/`newBand`/`newMode`/`duplicateBand`.
- Distance/bearing: `LoggerCallsignCard.swift distanceKm`/`bearingDegrees` —
  home grid + station grid → maidenhead (already in Rust).
- Server memberships: `ActivitiesClient+CallsignEnrichment.swift` +
  `CallsignEnrichmentCache.swift` — `GET /v1/callsign-enrichment/dataset`, ETag,
  12h TTL, single-char JSON keys.
- Polo notes: `CallsignNotesCache.swift` (club-configured note sources).
- HamDB: `HamDBClient.swift` (US fill-nil fallback).

## Staging

### Stage 1 — surface data + distance/bearing + prev-QSO count  ← THIS PASS

Rust (one Kotlin regen via Gradle `buildRustCore`):
1. `cw-domain/src/callsign_flag.rs` — verbatim port of `CallsignFlagHelper`;
   `flag_for_callsign(&str) -> Option<String>` + parity test. Re-export in `lib.rs`.
2. `cw-ffi/src/lib.rs` — free fn `callsign_flag(callsign) -> Option<String>`.
3. `cw-store/src/qso.rs` — `Store::worked_before_count(callsign) -> i64`
   (exact uppercased callsign, `is_hidden=0`, exclude WEATHER/SOLAR/NOTE) + test.
4. `cw-ffi/src/lib.rs` — `FieldStore::worked_before_count(callsign) -> i64`.

Android (`EnrichmentBadges.kt`):
- Keep the signature `(callsign, modifier, includeQrz)`; **history rows
  (`includeQrz=false`) render exactly as today** (DXCC + SKCC) — no regression,
  no club double-render with `ClubBadges`.
- When `includeQrz=true` (Logger / HunterLog / Spots live surfaces), render the
  full chip flow with `FlowRow`:
  flag · 🌍 DXCC · 👤 name · QTH · state · grid · license · CQ zone · continent ·
  distance · bearing · SKCC · club chips · ×N prev · prev-callsign.
- Distance/bearing from `CwApp.HOME_GRID` + `qrz.grid` via `maidenheadDistanceKm`/
  `maidenheadBearing`; format km + `bearingArrow` (existing `Format.kt`).
- `worked_before_count` and clubs gated behind `includeQrz` (store calls on
  `Dispatchers.IO`).

Verify: `./gradlew :app:assembleDebug` (regens bindings + builds) + `cargo test`
in cw-core for the new Rust units.

### Stage 2 — full day-scoped dupe status  ✅ DONE

`FieldStore.duplicate_status(callsign, band, mode, park, is_pota, day_start)` →
`FfiDuplicateStatus` (FirstContact / PreviouslyWorked / NewBand / NewMode /
DuplicateBand) — port of iOS `classifyDuplicateStatus`, reusing
`cw_domain::ModeEquivalence`; candidates from `Store::dupe_candidates`. 6 Rust
unit tests cover all states + POTA park-scoping. Wired into the Hunter log
command bar: `HunterLogViewModel` now computes status via the FFI (replacing the
binary `workedToday` map), and `DupeBadge` renders the 5 states (green =
new band/mode, amber = dupe/worked-today).

### Stage 3 — networked sources

- **HamDB fallback**  ✅ DONE — `cw_net::HamdbClient` + `QrzApi.lookup_callbook`
  merges QRZ over HamDB (QRZ-priority, HamDB fill-nil, credential-free). Android
  calls `lookupCallbook` so US calls resolve name/grid/QTH even without QRZ creds.
- **Server CWops memberships**  ✅ DONE — `cw_net::EnrichmentClient` for
  `/v1/callsign-enrichment/dataset` (ETag-conditional, compact keys) +
  `EnrichmentApi.refresh_memberships` (store kv cache, 12h TTL) +
  `FfiMembership` rows in `FfiCallsignEnrichment`, rendered as chips. Warmed in
  `CwApp`.
- **Polo callsign notes**  ⏸️ DEFERRED — intentionally skipped: Android has no
  configured note source (iOS feeds these from club-configured `CallsignNotesCache`
  URLs), so the plumbing would surface nothing. Revisit when a note source exists.

### Fix — dupe badge clipped off-screen (layout regression)

Symptom: dupe badge never showed even when `duplicate_status` correctly returned
`PreviouslyWorked`. Root cause (found via on-device `CWdupe` logging): Stage 1
turned `EnrichmentBadges` into a full-width wrapping `FlowRow`, and the
`DupeBadge` was a horizontal sibling in a `Row` — so the badge was pushed off the
right edge. Fix: stack them in a `Column` (badge on its own line above the
chips). Verified live: "worked today" now renders for a callsign worked today.

## Status: Stages 1–3 complete (Polo deferred). Verified live on the emulator —
the Logger/Hunter command bars render the full chip set (flag · DXCC · name ·
state · grid · license · CQ zone · continent · distance+bearing · SKCC · clubs ·
server memberships · ×N prev). 638 Rust tests + clippy clean; Gradle build green.

## Acceptance

Stage 1: Rust unit + parity tests pass; Gradle debug build succeeds; the three
live surfaces show the richer chip flow; history QSO rows are visually unchanged.
