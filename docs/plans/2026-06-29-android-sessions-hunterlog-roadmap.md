# Sessions + Hunter Log → shared Rust core — roadmap

Branch: `feat/android-sessions-hunterlog-rust` (2026-06-29).

Goal: move the Sessions (activation) and Hunter Log (chaser) **behavior** into the
shared Rust core (`cw-ffi`) so iOS and Android run identical logic, then build the
Android UI on it. The data models + persistence were already in `cw-store`; this
work added the behavior layer and the Android screens.

## Done

**Rust core (`cw-ffi`), 611 tests pass, clippy clean, no contests:**
- `ActivityLogApi` — hunter lifecycle, `log_qso` enrichment + upload routing
  (QRZ only, never POTA, skip metadata), today stats + daily goal, `worked_today`
  dedup map.
- `SessionApi` — activation lifecycle (`pause`/`resume`/`end`/`reopen`),
  session-stamped `log_qso` (band-from-freq, operator park, WWFF ref, `sotaRef`
  nil, count increment, QRZ+POTA routing), `merge_sessions`, `delete_session`.
- `cw-domain::hunter_log` (`band_mode_park_key`, `derive_dxcc`) +
  `quick_entry::extract_primary`; shared `mark_needs_upload`.

**iOS bindings:** `CwFfi.xcframework` regenerated + staged into
`CarrierWaveCore/Vendored`; new types present in `CwFfi+Generated.swift`. The
Rust APIs are reachable from Swift exactly like the existing `RustStore/` read
sources (`ActivityLogApi(store: fieldStore)`).

**Android UI (this step):**
- `CwApp` exposes `activityLogApi` + `sessionApi`.
- **Hunter tab** (new) — `ui/hunter/HunterLog{ViewModel,Screen}`: start log,
  shared quick-entry command bar, live today stats, worked-today dupe badge,
  today's contacts list. Fully on `ActivityLogApi`.
- **Sessions tab** (rewired) — `ui/activation/Activation{ViewModel,Screen}`:
  start a casual/POTA activation, quick-log, pause/resume/end, session QSO list.
  Fully on `SessionApi`. (The old client-side QSO-grouping `ui/session/*` is
  superseded but left in the tree; its detail-nav block in `MainActivity` is now
  unreachable and can be removed in a cleanup pass.)
- `ui/common/CoreQsoRow` renders API QSOs (whose `qsoDate` is Unix **seconds**,
  the cw-store contract) — see the units note below.

## Next — (1) wire the iOS Swift managers to delegate

`ActivityLogManager` (`swift/ios/.../Services/ActivityLogManager*.swift`) and
`LoggingSessionManager` (`LoggingSessionManager*.swift`, 19 files) should delegate
their now-ported logic to `ActivityLogApi` / `SessionApi` instead of duplicating
it in Swift over SwiftData. This is a behavior-changing refactor of two live
managers (it touches real logging paths), so it gets its own branch + careful
verification (parity against the existing Swift behavior, then device test). The
`SessionLifecycleAPI` protocol in `CarrierWaveData` is already the right seam.

## After — (3) the deferred algorithms

Self-contained follow-ups, each documented in `session_api.rs`:
1. **POTA UTC-midnight split** (`LoggingSessionManager+POTASplit`, ~14 KB) —
   per-date session cloning + rove-stop handling.
2. **NOAA conditions fill-only-if-nil merge** (`+Conditions`).
3. **End-of-session WPM averaging** into `ActivationMetadata` (`saveAverageWPM`).
4. **`sortedSpots` ordering + unread divider** — the cosmetic spot-list sort
   (the dedup *kernel* it needs, `band_mode_park_key`, is already ported; the
   sort is coupled to the not-yet-ported `EnrichedSpot`/needs enrichment).

## Cross-cutting cleanup (not blocking)

- **Android `qsoDate` units:** the older Android logger path stores `qsoDate` in
  **milliseconds**, but the shared cw-store contract (and iOS, and the new APIs)
  use **seconds**. The new screens use `CoreQsoRow` (seconds) to stay correct;
  the app should migrate the logger path + `Format.kt`/`QsoRow` to seconds so all
  QSOs render consistently and Android-written QSOs aren't future-dated to iOS.
