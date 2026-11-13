# Log Write Durability Torture Test — Design

- **Date:** 2026-06-20
- **Branch:** `worktree-log-write-durability-torture` (off `origin/main` @ c99129ef)
- **Status:** Approved design, pending spec review → implementation plan

## Goal

Build a torture-test suite that proves the QSO logbook's write path honors a single
durability invariant under every realistic disruption, across both the Rust data
layer (`cw-store` / SQLCipher) and the Swift binding layer (`FieldStore` via UniFFI).
Where the test exposes a durability gap, harden the store in the same branch.

## The Invariant (acceptance bar)

> **ack ⇒ durable.** Once `upsert_qso` returns `Ok` (Rust) / returns without throwing
> (Swift), that QSO must be present and field-for-field intact in *every* subsequent
> post-disruption image of the database. A write that has **not** yet been acked may be
> lost — but must never corrupt the database or any acked row.

Corollary checks on every reopen: `PRAGMA cipher_integrity_check` reports OK, and the
database opens with the correct key.

## Scope (locked decisions)

- **Fault model:** full spectrum — power loss, torn page, disk-full (ENOSPC), app crash,
  concurrent-writer contention.
- **Entity:** QSO only. The harness is generic over the `Store`, but the acceptance
  assertions target `qso` upsert/fetch.
- **Fix scope:** test **and** harden. Durability hardening the test motivates ships in
  this branch so the suite is green against a hardened store.
- **Layers:** Rust (`cw-store`) and Swift (`CarrierWaveCore` package). Per a known issue,
  the full app target build hangs on `actool`, so the Swift suite runs against the
  package, not the app.

## Current state (as found)

- `Store::open` (`cw-store/src/lib.rs`) sets **no** `journal_mode`, `synchronous`, or
  `busy_timeout` pragma. Durability rides on SQLite/SQLCipher defaults: rollback (DELETE)
  journal + `synchronous=FULL`. That default *is* power-loss durable, but is implicit and
  unguarded against regression.
- No `busy_timeout` → concurrent writers get immediate `SQLITE_BUSY`.
- `upsert_qso` (`cw-store/src/qso.rs`) is a single `INSERT … ON CONFLICT` in autocommit —
  each ack is its own implicit, synced transaction.
- `FieldStore.upsert_qso` (`cw-ffi`) wraps the store call and fires an observer `notify`
  after the DB lock is released.

## Architecture

```
                       ┌─────────────────────────────┐
   Swift layer  ──────▶│ FieldStore.upsertQso (UniFFI)│
   (app-crash,         └───────────────┬─────────────┘
    concurrency,                       │
    ack-boundary)                      ▼
                       ┌─────────────────────────────┐
   Rust layer   ──────▶│ cw-store: upsert_qso         │
   (power-loss,        │   INSERT…ON CONFLICT (commit)│
    torn-page,         └───────────────┬─────────────┘
    ENOSPC,                            ▼
    app-crash,         ┌─────────────────────────────┐
    concurrency)       │ SQLCipher  (ciphertext pages)│
                       └───────────────┬─────────────┘
                                       ▼
                       ┌─────────────────────────────┐
                       │ CrashVFS  (fault injection)  │ ◀── torture engine
                       └───────────────┬─────────────┘
                                       ▼  (real file, sync-tracked)
```

## Components

### 1. CrashVFS (Rust fault-injection engine)

A custom SQLite VFS backing onto a real file, modeling the durability contract:

- `write(offset, bytes)` → buffered into an *unsynced* set; reads merge buffer-over-file
  so the live connection sees its own writes.
- `sync()` → flush the unsynced buffer to the real file + real `fsync`, then clear it.
  This is the only point data becomes durable.
- **Crash image** = the real file's last-synced state plus a per-fault treatment of the
  unsynced buffer:
  - **power-loss:** drop the entire unsynced buffer.
  - **torn-page:** for each unsynced 512-byte sector, randomly keep-old / apply-new /
    write-garbage (seeded RNG → reproducible).
  - **ENOSPC:** `write` returns `SQLITE_FULL` after a configured byte budget.

SQLCipher encrypts pages *above* the VFS, so the engine only ever sees ciphertext — no
interaction with encryption. Crash images are reopened with the key.

**Implementation (verified):** a raw-FFI **shim VFS over the default VFS**, accessed via
`rusqlite::ffi` (which re-exports the resolved `libsqlite3-sys 0.30.1`). No new crate
dependency, builds offline, no version-conflict risk. Verified against this build:
`libsqlite3-sys 0.30.1` ships `sqlite3_vfs`, `sqlite3_io_methods`, `sqlite3_vfs_register`,
`sqlite3_vfs_find`; `rusqlite::Connection::open_with_flags_and_vfs` opens through a named
VFS. The shim's VFS methods delegate to the parent (real) VFS; `xOpen` wraps the real file
with custom `sqlite3_io_methods` that intercept `xWrite`/`xSync`/`xTruncate` (buffer +
sync-tracking) and delegate everything else to the real file's methods (the SQLite
`test6.c` crash-test pattern).

**Torture loop** (canonical SQLite crash-test methodology): for `crash_point` in
`0..total_io_ops`, replay the QSO workload, trigger the chosen fault after exactly
`crash_point` I/O ops, build the crash image, reopen, run `cipher_integrity_check`, and
assert every QSO acked *before* that crash point is intact. Walks every crash position
rather than spot-checking. Exhaustive by default but **capped at a few hundred crash
points**, with an `--exhaustive` (env var) override for nightly/manual deep runs.

### 2. App-crash subprocess harness

The *real* syscall path (no VFS model): `cw-store/src/bin/durability_crasher.rs` opens the
on-disk DB, upserts, prints `ACK <id>` and flushes stdout, then `std::process::abort()` —
no unwinding, no clean close. The integration test spawns it via
`CARGO_BIN_EXE_durability_crasher`, reads the ACK, confirms abnormal exit, reopens, and
asserts presence. Mirrored on the Swift side.

### 3. Hardening (cw-store, same branch)

In `Store::key_and_migrate`, made explicit + commented so they are regression-proof:

- `PRAGMA busy_timeout = 5000` — concurrent writers serialize instead of immediate
  `SQLITE_BUSY`.
- `PRAGMA synchronous = FULL` — lock the durable default explicitly.
- `PRAGMA fullfsync = ON` — Apple only: makes `fsync` issue `F_FULLFSYNC` (flush the drive
  write cache), the actual basis for power-loss durability on macOS/iOS. Harmless else.
- Keep `journal_mode = DELETE` explicitly, with a comment that switching to WAL requires
  `synchronous=FULL` + checkpoint discipline or it silently loses the last commit on power
  loss.
- Add `Store::open_with_vfs(path, key, vfs_name)` seam; `open` delegates with the default
  VFS name.

### 4. Swift layer (CarrierWaveCore package)

A swift-testing suite covering the boundary properties, honestly scoped:

- **App-crash:** an executable target (`LogDurabilityCrasher`) does upsert → `ACK` →
  `abort()` through the generated UniFFI bindings; the test reopens `FieldStore` and
  asserts presence — proving the Swift surface does not buffer or drop the write.
- **Concurrency:** N concurrent `Task`s upsert distinct ids on a shared `FieldStore`;
  assert all present.
- **Honest scope note:** power-loss/torn/ENOSPC are properties *below* the FFI and are
  proven once at the Rust layer; the Swift suite does **not** re-plumb the CrashVFS
  through UniFFI.

## Fault → mechanism → assertion matrix

| Fault | Mechanism | Layer(s) | Assertion |
|---|---|---|---|
| Power loss | CrashVFS drop-unsynced | Rust | acked rows all present; integrity ok |
| Torn page | CrashVFS sector garble (seeded) | Rust | acked rows intact; integrity ok; only un-acked may vanish |
| Disk full | CrashVFS `SQLITE_FULL` | Rust | upsert errors cleanly OR commits; never partial; db reopens clean |
| App crash | subprocess `abort()` after ack (real fsync path, no VFS) | Rust **and** Swift | acked row present on reopen |
| Concurrency | N threads/Tasks upserting distinct ids | Rust **and** Swift | all acked ids present; no spurious `SQLITE_BUSY` (post-harden) |

## Honest limitation

No software test can prove durability against true bare-metal power loss (that depends on
the drive honoring `F_FULLFSYNC`/FUA). The CrashVFS proves the code honors SQLite's
durability *contract* — acked data is never lost unless it was genuinely un-synced — which
is what catches real regressions (a switch to WAL or `synchronous=OFF`). The
`fullfsync=ON` hardening closes the Apple-hardware side of the gap as far as software can.
Torn-page coverage excludes page 1 (offset 0): corrupting the SQLCipher salt stored there
is unrecoverable by any code, so page-1 torn writes are modeled as dropped (equivalent to
power-loss) rather than garbled.

## File layout

- `cw-store/src/testing/crash_vfs.rs` — CrashVFS, behind a `testing` cargo feature (kept
  out of release builds).
- `cw-store/tests/durability.rs` — in-process torture loop (power-loss, torn, ENOSPC,
  concurrency), seeded RNG for reproducibility.
- `cw-store/src/bin/durability_crasher.rs` — app-crash child.
- `swift/packages/CarrierWaveCore/Tests/CarrierWaveCoreTests/LogDurabilityTests.swift` +
  `LogDurabilityCrasher` executable target.

## CI / running

- Rust: `cargo test -p cw-store --features testing`. Seeded RNG for reproducibility.
- Swift: via the existing package-test seam (`swift test` / Makefile). Implementation will
  verify the package links `CwFfi.xcframework` under that path.
- Concurrency tests get explicit timeouts to avoid hangs.

## Defaults adopted

1. `busy_timeout` = **5000 ms**.
2. Torture loop exhaustive but **capped at ~a few hundred crash points**; `--exhaustive`
   env override for nightly.
3. Swift suite runs via `swift test` on the package (verified during implementation).
