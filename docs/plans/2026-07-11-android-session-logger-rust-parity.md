# Android Session Logger — Rust-first parity

**Date:** 2026-07-11
**Goal:** Starting a session on Android should open a live QSO-entry logger window matching iOS
(core scope), with the logger's business logic living in shared Rust and iOS rerouted onto it
(Swift equivalents deleted).

Linear: (create CAR-XXX) — continues the `feat/android-session-wizard-parity` line of work.

## Decisions (confirmed)
- **Android scope:** Core QSO-entry logger — callsign, RST, band/mode/freq, notes, Log button,
  running list of this session's QSOs, dupe warning, pause/end session. No radio/FT8/SDR/GPS.
- **Replace Swift:** Rust becomes canonical for active-session state + logger logic; iOS rerouted,
  Swift equivalents deleted; Android built on the same API.

## Current state (from exploration)
- **iOS:** `SessionsTabView` shows `LoggerContainerView`→`LoggerView` when
  `sessionManager.hasActiveSession`. Active session is Swift-canonical (`LoggingSessionManager.activeSession`
  + UserDefaults `"activeLoggingSessionId"` + SwiftData restoration/healing). Rust `SessionApi` mirrors mutations.
- **Android:** Wizard calls `SessionWizardApi.createSession()` then `onDismiss()` → drops back to the tab.
  **No logger screen exists** (deleted 2026-07-04, commit d892c910). `SessionApi` present in Kotlin FFI but unwired.
- **Rust:** `SessionApi` has pause/resume/end/reopen/delete/logQso/sessionQsos/merge/conditions/wpm/split.
  Dupe detection exists (`FieldStore.duplicate_status`, `hunter_log::band_mode_park_key`). Band derivation,
  notes-combine, upload routing exist. **No** active-session concept, **no** RST-by-mode defaults, **no** validation.

## Phase 1 — Rust: active-session ownership + logger defaults (shared, tested)
- `cw-store` (`logging_session.rs`): add `current_session()` query returning the single non-completed
  `status = "active"` session (endedAt nil); most-recent wins. Confirm `create` + wizard path enforce the
  single-active invariant (reuse `pause_other_active`). No new column unless the invariant needs it.
- `cw-domain`: add `default_rst(mode) -> RstDefaults { sent, received }` ported from iOS `defaultRST`.
  Add `normalize_callsign` + `validate_log_input` helpers (reuse `callsign_detector` / `quick_entry`).
- `cw-ffi` `SessionApi`: add
  - `current_session() -> Option<FfiLoggingSession>`
  - `logger_form_config(session_id) -> FfiLoggerFormConfig` (RST defaults + field-visibility flags:
    show_park, show_contest_exchange, show_state_aoa, is_pota, is_contest, band, mode)
  - inside `log_qso`: normalize callsign, apply RST defaults when blank (validation non-fatal — warn, don't reject).
- Rust parity tests: `default_rst`, `current_session` single-active, `log_qso` RST-default fill.
- Regenerate Swift + Kotlin bindings (`scripts/build-xcframework.sh`; Android gradle uniffi task).

## Phase 2 — iOS reroute (replace Swift)
- `LoggingSessionManager`/`+Helpers`: `activeSession` derives from Rust `current_session()`.
  Delete UserDefaults `"activeLoggingSessionId"` persistence + SwiftData-query `loadActiveSession()`
  restoration/healing; replace with: query Rust → reflect into SwiftData `LoggingSession` → `adoptRestoredSession`
  (platform wiring: radio/timers/LiveActivity stays).
- `LoggerView`/`+Data`/`+HelperViews`: delete Swift `defaultRST` and the dupe classification / QSO-assembly
  logic that duplicates Rust; call `logger_form_config` + existing `duplicate_status` + `log_qso`.
- Compile-check (`-destination 'generic/platform=iOS'`), run QueryParity/session tests on Simulator.

## Phase 3 — Android logger screen (new, on shared Rust)
- New `ui/logger/LoggerScreen.kt` + `LoggerViewModel.kt` (core QSO entry).
- ViewModel: reads `SessionApi.currentSession()` + `logger_form_config`; `logQso`, `sessionQsos`,
  `duplicate_status`, `pauseSession`, `endSession`. Runs store-touching FFI on `Dispatchers.IO`
  (per uniffi-async-dispatcher gotcha).
- `MainActivity`: **re-add a `Tab.SESSIONS`** to the bottom nav (between HOME and HUNTER). The tab renders
  a `SessionsContainerScreen`: when `currentSession() == null` show the start/intent grid (launches the
  existing wizard); when `currentSession() != null` show `LoggerScreen`. Observe active-session state so the
  tab content swaps live on start/end (mirrors iOS `SessionsTabView`).
- Build Android (assembleDebug), smoke-test on `cw_test` AVD.

## Phase 4 — polish, tests, docs
- CHANGELOG `[Unreleased]`, memory update (`project_android_session_wizard_parity`), Linear comment/close.

## Status (2026-07-11)
- **Phase 1 — DONE.** `cw-store::fetch_current_session`; `cw_domain::default_rst` + test;
  `SessionApi::current_session` / `logger_form_config` + `FfiLoggerFormConfig`; `log_qso` fills blank
  RST via `default_rst`. cw-domain/cw-ffi tests + clippy green. Swift + Kotlin bindings regenerated
  (xcframework rebuilt; Android gradle regen).
- **Phase 2 — iOS flip DONE (compiles, `xcodebuild` exit 0).** `startSession` projects the new session
  into cw-store; `loadActiveSession` restores from `currentSession()` and reflects, with the old
  SwiftData/UserDefaults path kept as `loadActiveSessionFromSwiftData` — the **`CwStoreQSOMode.off`
  kill-switch fallback**. NOTE: the Swift `defaultRST` / dupe-classification bodies were **not deleted** —
  they double as that `.off` fallback the whole rollout architecture depends on; authority moved to Rust,
  the Swift copies remain the kill-switch path. Flagged to the user.
- **Phase 3 — DONE (`assembleDebug` exit 0).** `Tab.SESSIONS` (bumped `MAX_PRIMARY_TABS` to 6 so Friends
  stays reachable), `SessionsContainerScreen`, `LoggerScreen`, `LoggerViewModel` on `SessionApi`.
- **Phase 4 — in progress.** CHANGELOG done; memory + Linear + on-device smoke pending.

## All-in-on-Rust round (2026-07-11, user: "delete the swift fallbacks")
Scope confirmed: **logger path only** (not the app-wide `CwStoreQSOMode` retirement).
- **Done:** removed the `.off` gate on `sessionApi` (logger uses Rust in `.on`/`.shadow`);
  deleted the Swift QSO-assembly fallback + `insertAndFinalize` in `logQSO` (Rust-only; on
  seam-unavailable/Rust-error it surfaces a `ToastManager.error` instead of a silent SwiftData
  write); deleted `loadActiveSessionFromSwiftData` (restore is Rust-only); deleted dead
  `combineNotes`; exported `default_rst(mode)` FFI and pointed Swift `defaultRST` at it.
- **Activation dupe — DONE (follow-up round).** Added `Store::dupe_candidates_for_activation` (selects
  the operator's own `park` column via a shared `dupe_candidates_scoped` helper; injection-safe hard-coded
  column) + `FieldStore::activation_duplicate_status` (same classifier as hunter, my-park scope). cw-store
  test proves the my-park-vs-their-park column split; classifier already tested. iOS `computeDuplicateStatus`
  now calls `activationDuplicateStatus` + maps `FfiDuplicateStatus`→`CallsignDuplicateStatus`; deleted Swift
  `filterMatchingQSOs`/`classifyDuplicateStatus` (kept `utcDayQSOs`/`refreshUTCDayQSOs` — they feed `previousQSOs`).
  Android `LoggerViewModel` switched from the hunter `duplicateStatus` to `activationDuplicateStatus`.

## Risks
- iOS restoration wires radio/timers/LiveActivity; moving the source-of-truth must keep `adoptRestoredSession`
  running. Verify session survives cold launch on both platforms.
- Single-active invariant must hold across wizard `createSession` + `resume_session`.
