# Android: spot monitoring + callsign enrichment

_Started 2026-06-28. Adds two iOS feature areas to the Android Compose app by
extending the shared Rust core (the chosen path over Kotlin-side HTTP), keeping
Android's "all networking through Rust" invariant._

## Decisions (confirmed with user)
- **Fetch path:** new Rust `SpotsApi` (FFI), wrapping the existing `cw-net`
  spot clients — not Kotlin HTTP. Mirrors `ClubsApi`.
- **Spot sources:** POTA, RBN, SOTA, WWFF (not PSKReporter for v1).
- **Enrichment:** DXCC entity (CTY), Polo notes, SKCC/club membership, **and**
  QRZ name/QTH. QRZ has no Rust client → build one in `cw-net`, creds via the
  existing `SecureStore` foreign trait.

## Key facts established
- `cw-net` already has async `PotaClient` / `SotaClient` / `WwffClient`
  (`clients.rs`); only the FFI wrapper is missing. PSKReporter client also exists.
- RBN has **no** direct client; iOS hits the activities-server proxy at
  `{activities_base}/v1/rbn/spots?call&since&limit&band&mode` (no auth), then
  decodes via `cw_net::rbn::RbnSpot::parse_response`. → add a small `RbnClient`.
- FFI spot decoders + `Ffi*Spot` records already exist
  (`decode_pota_response` etc., `FfiPotaSpot` / `FfiRbnSpot` / `FfiSotaSpot` /
  `FfiWwffSpot`). The `SpotsApi` methods return these same records.
- Enrichment primitives in core: `CtyDatabase` (object, `parse(content)`),
  `ScpDatabase`, `parse_skcc_roster`, `parse_polo_notes`. They take **content
  bytes** — host/core must fetch the data files. Club membership already
  queryable via `store.clubs_for_callsign`.
- Patterns to copy: `cw-ffi/src/clubs_api.rs` (async object, lock discipline:
  network with no lock held), `auth_api.rs` (`SecureStore` foreign trait,
  in-memory single-flight cache).
- Android wiring: `CwApp` holds singletons (`store`, `authApi`, `clubsApi`);
  ViewModels use `MutableStateFlow` + factory + `Dispatchers.IO`; tabs are a
  `Tab` enum in `MainActivity`; enrichment badge precedent is
  `ui/clubs/ClubBadges.kt` (`produceState`), attached in `ui/common/QsoRow.kt`.

## Phases
1. **Rust `SpotsApi`** — `cw-net` `RbnClient`; `cw-ffi/spots_api.rs` with async
   `fetch_pota/fetch_rbn/fetch_sota/fetch_wwff`. (task #1)
2. **Rust QRZ** — `cw-net/qrz.rs` (session auth + XML parse), `cw-ffi/qrz_api.rs`
   `QrzApi` (creds via `SecureStore`, cached session key). (task #2)
3. **Rust enrichment data** — `EnrichmentApi`: fetch+cache CTY.dat/Polo/SKCC,
   `lookup(callsign) -> FfiCallsignEnrichment`. Needs source-URL discovery from
   iOS `SCPService` / `CallsignNotesCache` / `CallsignEnrichmentCache`. (task #3)
4. **Android wiring** — regen bindings (`build-rust.sh`), add API singletons to
   `CwApp`, QRZ credential entry UI. (task #4)
5. **Android Spots tab** — `SpotsViewModel` + `SpotsScreen`, source filter,
   ~60 s poll, tap-to-log. (task #5)
6. **Android enrichment badges** — `EnrichmentBadges` composable on QSO rows /
   spot rows / logger. (task #6)
7. **Verify** — rust build/clippy/test, `:app:assembleDebug`; changelog +
   remaining-ports doc; commit when asked. (task #7)

## Gates
- Rust: `cargo build`, `cargo clippy --workspace --all-targets -- -D warnings`,
  `cargo test --workspace` (do NOT `cargo fmt` — hand-formatted core).
- Android: `:app:assembleDebug` (regen Rust bindings first).

## Status — COMPLETE (2026-06-28)
All seven phases landed and verified:
- ✅ Phases 1–3 (Rust): `SpotsApi` (+`cw_net::RbnClient`), `QrzApi`
  (+`cw_net::qrz`), `EnrichmentApi` (+`cw_domain::cty`/`skcc` reuse). Workspace
  clippy `-D warnings` clean; `cargo test --workspace` green (306+; new parity
  tests for QRZ XML parse, SKCC index, enrichment wiring).
- ✅ Phase 4: `CwApp` exposes `spotsApi`/`qrzApi`/`enrichmentApi`; startup
  best-effort `enrichmentApi.refresh()`; QRZ credential card on the Account tab.
- ✅ Phase 5: `ui/spots/` — `Spot` model + per-source mappers, `SpotsViewModel`
  (source filter, 60 s poll), `SpotsScreen` (source chips, rows, tap-to-log
  prefilling the Logger via a one-shot seed).
- ✅ Phase 6: `ui/common/EnrichmentBadges.kt` — DXCC + SKCC (local, instant) on
  every QSO row; QRZ name additionally on Spots rows (`includeQrz`).
- ✅ Phase 7: `:app:assembleDebug` green; CHANGELOG updated.

### Deferred / follow-ups
- **Polo notes** — not implemented (no global source; club-config-driven —
  belongs with the clubs surface).
- iOS could later drop its Swift spot HTTP + QRZ client onto these same
  `SpotsApi`/`QrzApi` cores (shared-path payoff), but that's a separate cutover.
- On-device smoke test not run here (build-verified only).
