# LoggingSession Sync Plumbing (E2E journal) — Implementation Note

Date: 2026-07-15
Status: Implemented, outbound push gated OFF (pending tolerant-decoder floor)

## Problem

Sessions did not render across devices. The Rust sync driver
(`cw-ffi/sync_transport.rs`, the path iOS + Android use against the E2E server)
only modeled `UpsertQso` and `UpsertSyncedConfig` journal ops. A
`LoggingSession` created on one device never reached another: peers received the
session's QSOs (which carry `loggingSessionId`) but not the session record
itself, so there was nothing to render.

The Swift CloudKit engine (`CloudSyncJournalEngine`) already handled
`.upsertLoggingSession`; this brings the **Rust** journal to parity so the
server-sync path carries sessions too.

## What changed (all in `rust/cw-core/`)

- **`cw-sync/src/conflict.rs`** — added `LoggingSessionPayload`, the wire struct
  that is a field-for-field port of Swift `LoggingSessionFields` (~45 of the 76
  store columns; camelCase keys; `.secondsSince1970` dates; base64
  `spotCommentsData`/`roveStopsData`; `photoFilenames` as a JSON array). Added
  `merge_logging_session` — LWW keyed on `ended_at ?? started_at` (sessions have
  no `modified_at`), `qso_count` takes the max, and "completed" status is
  terminal (port of `CloudSyncConflictResolver.mergeLoggingSession` +
  `mergeSessionStatus`). Swift's `Date()` fallback for the both-`ended_at`-nil
  completed edge is replaced by a deterministic caller-supplied timestamp (the
  payload timestamp).
- **`cw-sync/src/journal.rs`** — added the `UpsertLoggingSession(Box<…>)`
  variant + `entity_type()`/`entity_id()` arms + `upsert_logging_session`
  constructor.
- **`cw-sync/src/lib.rs`** — re-exports.
- **`cw-ffi/src/sync_transport.rs`** — outbound `gather_dirty_logging_session_payload`
  + `push_logging_sessions` drain loop (clears the `loggingSession` dirty flag,
  content-addressed entry id); inbound `apply_logging_session_upsert` (merge onto
  an existing row preserving the non-wire columns, else insert a fresh clean
  row); a `Delete { LoggingSession }` arm (hard delete, mirroring Swift); and a
  `FfiStoreTable::LoggingSession` notify on inbound.

The store, dirty-flag resolver, `FfiLoggingSession` CRUD, and `session_api`
(which already sets `cloud_dirty_flag` on every write) were already in place, so
**no new FFI surface** was added — iOS/Android need no Swift/Kotlin or binding
changes; synced session rows render through the existing read paths.

Non-wire columns (`programs_raw_value`, `mission_reference`, `radio_item_id`,
`cloud_dirty_flag`, all `contest_*`, all TOTA / activation-geometry / track /
tile fields) have no wire slot and are preserved across an inbound merge. A fresh
inbound session seeds `programs_raw_value` from the activation type
(`["pota"]`, …), matching Swift `LoggingSession.fromFields`.

## The gate — `SESSION_SYNC_PUSH_ENABLED`

Outbound **push** is gated OFF (`const SESSION_SYNC_PUSH_ENABLED: bool = false`
in `sync_transport.rs`), exactly like `CONFIG_SYNC_PUSH_ENABLED`. Rationale:
a released client without `JournalOperation::Unknown` tolerance aborts its
*entire* pull batch (QSO ops included) on meeting an unknown `"op"` tag. Until a
tolerant client is the floor version across **all** of a user's devices, putting
`UpsertLoggingSession` ops on the shared wire risks breaking QSO sync on an older
device.

**Inbound apply is NOT gated** — applying a session op a peer already put on the
wire is always safe — so everything downstream is live and tested.

### To enable cross-device session publishing

1. Confirm the tolerant-decoder floor is met (same precondition as flipping
   `CONFIG_SYNC_PUSH_ENABLED`).
2. Flip `SESSION_SYNC_PUSH_ENABLED` to `true`. That is the only change; the
   gather/push loop is already wired and covered by tests.

## Tests

- `cw-sync/conflict.rs` — wire round-trip (identical key set + values vs the
  Swift fixture), nil-optional omission, merge (newer-wins, `qso_count` max,
  completed-is-terminal, both-nil fallback).
- `cw-sync/journal.rs` — session op payload round-trip, `loggingSession`
  camelCase entity-type.
- `cw-ffi/sync_transport.rs` — inbound insert (clean, programs seeded), inbound
  merge (newer wire field wins, non-wire columns + dirty flag preserved), inbound
  hard delete, store round-trip, dirty gather, and the gated-off no-outbound
  guard.
