# Log Write Durability Torture Test — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the QSO logbook's write path honors `ack ⇒ durable` under power loss, torn pages, disk-full, app crash, and concurrent writers — across `cw-store` (Rust) and `FieldStore` (Swift) — and harden the store where the suite exposes a gap.

**Architecture:** A raw-FFI SQLite shim VFS (`CrashVFS`) registered via `rusqlite::ffi`, layered under SQLCipher, models the durability contract: writes buffer until `xSync`; a simulated power-off freezes the on-disk (synced) state and drops the rest. A torture loop walks crash points across a commit's I/O ops and asserts every QSO acked before the crash survives intact. App-crash uses a real subprocess that `abort()`s after ack (no VFS). The Swift layer re-verifies the ack boundary + app-crash + concurrency through the UniFFI bindings.

**Tech Stack:** Rust, `rusqlite` 0.32 (`bundled-sqlcipher-vendored-openssl`), `libsqlite3-sys` 0.30.1 (via `rusqlite::ffi`), Swift Package Manager, swift-testing, UniFFI.

## Global Constraints

- **No `cargo fmt`** in `rust/cw-core` — the crate is hand-formatted; formatting churns the tree. Gate is build + clippy + test. (Match surrounding style by hand.)
- **Clippy is `-D warnings` on `--all-targets`** in CI. All new code (including feature-gated and test code) must be clippy-clean. Add a `--features testing` clippy step since the default workspace clippy won't lint the gated module.
- **`cargo test --workspace` does NOT enable the `testing` feature.** The torture tests live behind `feature = "testing"`; CI needs an explicit `cargo test -p cw-store --features testing --locked` step.
- **No new crate dependencies for the VFS.** Use `rusqlite::ffi` only (verified to export `sqlite3_vfs`, `sqlite3_io_methods`, `sqlite3_vfs_register`, `sqlite3_vfs_find`). `tempfile` and `rand` may be added as **dev-dependencies / `testing`-feature deps** only.
- **`fullfsync` is Apple-only** — the pragma is a harmless no-op elsewhere; do not gate behavior on it.
- **Swift tests run on macOS only** (host, via `swift test`), wired into the existing `macos-15` `xcframework` job in `.github/workflows/cw-core-rust.yml`. The Rust suite runs on Linux CI.
- **Invariant under test:** once `upsert_qso` returns `Ok` / returns without throwing, that QSO is present and field-for-field intact in every post-disruption image; un-acked writes may vanish but must never corrupt the DB or an acked row. Every reopen also asserts `PRAGMA cipher_integrity_check` = `ok`.
- **Update the nearest `FILE_INDEX.md`** when adding files (`rust/cw-core/FILE_INDEX.md`).

---

## File Structure

| File | Responsibility |
|---|---|
| `rust/cw-core/cw-store/src/lib.rs` (modify) | Add `open_with_vfs`, `apply_durability_pragmas`; declare `#[cfg(feature="testing")] pub mod testing`. |
| `rust/cw-core/cw-store/Cargo.toml` (modify) | Add `testing` feature; `rand` as optional/dev dep; `[[bin]]` for the crasher. |
| `rust/cw-core/cw-store/src/testing/mod.rs` (create) | Re-export `crash_vfs`. |
| `rust/cw-core/cw-store/src/testing/crash_vfs.rs` (create) | The shim VFS + `CrashController` + image builder. |
| `rust/cw-core/cw-store/src/bin/durability_crasher.rs` (create) | Real-process app-crash child. |
| `rust/cw-core/cw-store/tests/durability.rs` (create) | Torture loop: power-loss, torn-page, ENOSPC, concurrency, app-crash. |
| `swift/packages/CarrierWaveCore/Package.swift` (modify) | Add `LogDurabilityCrasher` executable target + product. |
| `swift/packages/CarrierWaveCore/Sources/LogDurabilityCrasher/main.swift` (create) | Swift app-crash child. |
| `swift/packages/CarrierWaveCore/Tests/CarrierWaveCoreTests/LogDurabilityTests.swift` (create) | Swift app-crash + concurrency tests. |
| `.github/workflows/cw-core-rust.yml` (modify) | Add `--features testing` test+clippy steps; add Swift `--filter LogDurabilityTests`. |
| `rust/cw-core/FILE_INDEX.md` (modify) | Index the new files. |

**Shared interfaces (defined once, referenced by every task):**

```rust
// cw-store/src/lib.rs
impl Store {
    pub fn open(path: impl AsRef<Path>, key: &str) -> Result<Self>;            // existing signature; now delegates
    pub fn open_with_vfs(path: impl AsRef<Path>, key: &str, vfs: Option<&str>) -> Result<Self>;
}

// cw-store/src/testing/crash_vfs.rs  (feature = "testing")
pub struct CrashController { /* opaque */ }
impl CrashController {
    /// Register a VFS under `vfs_name` whose files live under `dir`. Idempotent per name.
    pub fn register(vfs_name: &str, dir: std::path::PathBuf) -> std::sync::Arc<CrashController>;
    pub fn reset(&self);                       // re-arm for a fresh scenario; clears counters/flags
    pub fn arm_power_off_after(&self, io_ops: u64);   // power off after N write/sync ops from now
    pub fn arm_torn_power_off_after(&self, io_ops: u64, seed: u64); // as above, garble the tripping write
    pub fn set_full_after_bytes(&self, bytes: u64);   // xWrite returns SQLITE_FULL past this budget
    pub fn io_ops(&self) -> u64;               // ops observed so far (for ack/crash correlation)
    pub fn powered(&self) -> bool;
}
```

---

## Task 1: Store durability hardening + VFS open seam

**Files:**
- Modify: `rust/cw-core/cw-store/src/lib.rs`

**Interfaces:**
- Produces: `Store::open_with_vfs(path, key, vfs: Option<&str>)`, `Store::open` (delegates), `apply_durability_pragmas` (private).

- [ ] **Step 1: Write failing tests** — append to `mod tests` in `lib.rs`:

```rust
#[test]
fn durability_pragmas_are_set() {
    let store = Store::open_in_memory("k").unwrap();
    let sync: i64 = store.conn.query_row("PRAGMA synchronous", [], |r| r.get(0)).unwrap();
    assert_eq!(sync, 2, "synchronous must be FULL (2)");
    let busy: i64 = store.conn.query_row("PRAGMA busy_timeout", [], |r| r.get(0)).unwrap();
    assert_eq!(busy, 5000, "busy_timeout must be 5000ms");
    // In-memory journal_mode reports "memory"; on disk it must be "delete".
}

#[test]
fn journal_mode_is_delete_on_disk() {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::open(dir.path().join("log.db"), "k").unwrap();
    let mode: String = store.conn.query_row("PRAGMA journal_mode", [], |r| r.get(0)).unwrap();
    assert_eq!(mode.to_lowercase(), "delete");
}

#[test]
fn concurrent_writers_serialize_without_busy() {
    use std::sync::Arc;
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("log.db");
    Store::open(&path, "k").unwrap(); // create
    let path = Arc::new(path);
    let handles: Vec<_> = (0..4).map(|t| {
        let path = Arc::clone(&path);
        std::thread::spawn(move || {
            let store = Store::open(&*path, "k").unwrap();
            for i in 0..50 {
                store.upsert_qso(&super::tests::sample_qso(&format!("{t}-{i}"), "W1AW", "20m", 1000)).unwrap();
            }
        })
    }).collect();
    for h in handles { h.join().unwrap(); }
    let store = Store::open(&*path, "k").unwrap();
    assert_eq!(store.qso_count().unwrap(), 200);
}
```

(If `sample_qso` is not visible cross-module, mark it `pub(crate)` in this step.)

- [ ] **Step 2: Run, verify failure**

Run: `cargo test -p cw-store durability_pragmas_are_set concurrent_writers_serialize_without_busy journal_mode_is_delete_on_disk`
Expected: FAIL — `busy_timeout` is 0; concurrent test hits `SQLITE_BUSY` (`Err` unwrap panic).

- [ ] **Step 3: Implement** — in `lib.rs`, replace `open` and add the seam + pragmas:

```rust
/// Open (or create) an encrypted database at `path` with the given key.
pub fn open(path: impl AsRef<Path>, key: &str) -> Result<Self> {
    Self::open_with_vfs(path, key, None)
}

/// Open through an explicit VFS (test fault-injection); `None` = default VFS.
pub fn open_with_vfs(path: impl AsRef<Path>, key: &str, vfs: Option<&str>) -> Result<Self> {
    use rusqlite::OpenFlags;
    let flags = OpenFlags::SQLITE_OPEN_READ_WRITE | OpenFlags::SQLITE_OPEN_CREATE
        | OpenFlags::SQLITE_OPEN_URI | OpenFlags::SQLITE_OPEN_NO_MUTEX;
    let conn = match vfs {
        Some(name) => Connection::open_with_flags_and_vfs(path, flags, name)?,
        None => Connection::open_with_flags(path, flags)?,
    };
    Self::key_and_migrate(conn, key)
}
```

In `key_and_migrate`, after `pragma_update(None, "key", key)` and the wrong-key probe, before `migrate`, call `Self::apply_durability_pragmas(&conn)?;`. Add:

```rust
/// Durability-critical pragmas, set explicitly so the guarantee is
/// regression-proof rather than riding on SQLite defaults.
///
/// `journal_mode = DELETE` (rollback journal) + `synchronous = FULL` is
/// power-loss durable: a returned COMMIT has fsync'd journal then db.
/// Do NOT switch to WAL without `synchronous = FULL` + checkpoint
/// discipline, or the last commit is silently lost on power loss.
/// `fullfsync` makes fsync issue F_FULLFSYNC on Apple platforms (flush the
/// drive write cache); it is a harmless no-op elsewhere.
fn apply_durability_pragmas(conn: &Connection) -> Result<()> {
    conn.busy_timeout(std::time::Duration::from_millis(5000))?;
    conn.pragma_update(None, "synchronous", "FULL")?;
    conn.pragma_update(None, "fullfsync", "ON")?;
    // In-memory dbs reject journal_mode=DELETE; only set it for file-backed.
    let is_memory: bool = conn
        .query_row("PRAGMA journal_mode", [], |r| r.get::<_, String>(0))
        .map(|m| m.eq_ignore_ascii_case("memory"))
        .unwrap_or(false);
    if !is_memory {
        conn.pragma_update(None, "journal_mode", "DELETE")?;
    }
    Ok(())
}
```

- [ ] **Step 4: Run, verify pass**

Run: `cargo test -p cw-store`
Expected: PASS (all prior 86 + 3 new).

- [ ] **Step 5: Commit**

```bash
git add rust/cw-core/cw-store/src/lib.rs
git commit -m "feat(cw-store): explicit durability pragmas + open_with_vfs seam"
```

---

## Task 2: CrashVFS — passthrough shim, CRUD through it

This task delivers a registered shim VFS that delegates everything to the default VFS, proving the FFI plumbing before any fault logic. **Hard gate: a Store must open and round-trip QSOs through the named VFS.**

**Files:**
- Modify: `rust/cw-core/cw-store/Cargo.toml`
- Create: `rust/cw-core/cw-store/src/testing/mod.rs`
- Create: `rust/cw-core/cw-store/src/testing/crash_vfs.rs`
- Modify: `rust/cw-core/cw-store/src/lib.rs` (declare the module)

**Interfaces:**
- Produces: `CrashController::register(name, dir) -> Arc<CrashController>` and the no-op control methods (bodies filled in Task 3+). For this task the VFS purely delegates.

- [ ] **Step 1: Cargo feature + deps.** In `cw-store/Cargo.toml`:

```toml
[features]
testing = ["dep:rand"]

[dependencies.rand]
version = "0.8"
optional = true

[dev-dependencies]
serde_json = "1"
tempfile = "3"
rand = "0.8"

[[bin]]
name = "durability_crasher"
required-features = ["testing"]
```

In `lib.rs` add near the other `pub mod` lines:

```rust
#[cfg(feature = "testing")]
pub mod testing;
```

- [ ] **Step 2: Write the failing test** — `tests/durability.rs`:

```rust
#![cfg(feature = "testing")]
use cw_store::testing::CrashController;
use cw_store::{QsoFilter, Store};

mod common; // see Step 3 of Task 3 for sample_qso helper; for now inline a minimal one

#[test]
fn crud_round_trips_through_crash_vfs() {
    let dir = tempfile::tempdir().unwrap();
    let _ctrl = CrashController::register("crashvfs-crud", dir.path().to_path_buf());
    let store = Store::open_with_vfs(dir.path().join("log.db"), "k", Some("crashvfs-crud")).unwrap();
    store.upsert_qso(&common::sample_qso("1", 1000)).unwrap();
    assert_eq!(store.qso_count().unwrap(), 1);
    let rows = store.fetch_qsos(&QsoFilter::default(), 10, 0).unwrap();
    assert_eq!(rows[0].id, "1");
}
```

Create `tests/common/mod.rs` with a `pub fn sample_qso(id: &str, when: i64) -> cw_store::Qso` (copy the field set from `lib.rs`'s test `sample_qso`, made public).

- [ ] **Step 3: Run, verify failure**

Run: `cargo test -p cw-store --features testing --test durability crud_round_trips_through_crash_vfs`
Expected: FAIL to compile — `testing` module / `CrashController` missing.

- [ ] **Step 4: Implement the passthrough shim** — `src/testing/mod.rs`:

```rust
pub mod crash_vfs;
pub use crash_vfs::CrashController;
```

`src/testing/crash_vfs.rs` — register a VFS by **cloning the default VFS struct** and overriding `xOpen` to wrap the opened file with our `sqlite3_io_methods` whose `xWrite`/`xSync`/`xTruncate` (initially) just delegate to the real file. Use this structure (real, compile-target code):

```rust
//! Crash-injection shim VFS over the default SQLite VFS. Models the
//! durability contract: writes are delegated to the real file, but a
//! "power off" freezes the synced on-disk state (Task 3+). Built on
//! `rusqlite::ffi` — no extra SQLite dependency.
#![allow(clippy::missing_safety_doc)]

use rusqlite::ffi;
use std::ffi::{c_void, CString};
use std::os::raw::{c_char, c_int};
use std::path::PathBuf;
use std::ptr;
use std::sync::{Arc, Mutex, OnceLock};

pub struct CrashController {
    pub(crate) state: Mutex<ControllerState>,
}

#[derive(Default)]
pub(crate) struct ControllerState {
    pub io_ops: u64,
    pub crash_at: Option<u64>,
    pub powered: bool,
    pub torn_seed: Option<u64>,
    pub full_after_bytes: Option<u64>,
    pub bytes_written: u64,
}

// Registry mapping vfs-name -> controller, so the C callbacks (which only
// get the sqlite3_vfs*) can recover the controller via pAppData.
struct VfsReg {
    _name: CString,
    vfs: Box<ffi::sqlite3_vfs>,
    controller: Arc<CrashController>,
}
// Keep registered VFSes alive for process lifetime (tests).
static REGISTRY: OnceLock<Mutex<Vec<Box<VfsReg>>>> = OnceLock::new();

impl CrashController {
    pub fn register(vfs_name: &str, _dir: PathBuf) -> Arc<CrashController> {
        let controller = Arc::new(CrashController {
            state: Mutex::new(ControllerState { powered: true, ..Default::default() }),
        });
        unsafe {
            // Clone the default VFS so we inherit all of its methods, then
            // override xOpen. pAppData carries a raw Arc clone to the controller.
            let default = ffi::sqlite3_vfs_find(ptr::null());
            assert!(!default.is_null(), "no default sqlite vfs");
            let mut vfs: Box<ffi::sqlite3_vfs> = Box::new(*default);
            let name = CString::new(vfs_name).unwrap();
            vfs.zName = name.as_ptr();
            vfs.pAppData = Arc::into_raw(Arc::clone(&controller)) as *mut c_void;
            vfs.szOsFile = (*default).szOsFile + std::mem::size_of::<ShimFileTail>() as c_int;
            vfs.xOpen = Some(shim_open);
            let rc = ffi::sqlite3_vfs_register(&mut *vfs as *mut _, 0);
            assert_eq!(rc, ffi::SQLITE_OK, "vfs register failed");
            let reg = Box::new(VfsReg { _name: name, vfs, controller: Arc::clone(&controller) });
            REGISTRY.get_or_init(|| Mutex::new(Vec::new())).lock().unwrap().push(reg);
        }
        controller
    }
    // Control methods (no-ops until Task 3+):
    pub fn reset(&self) { *self.state.lock().unwrap() = ControllerState { powered: true, ..Default::default() }; }
    pub fn arm_power_off_after(&self, n: u64) { self.state.lock().unwrap().crash_at = Some(n); }
    pub fn arm_torn_power_off_after(&self, n: u64, seed: u64) {
        let mut s = self.state.lock().unwrap(); s.crash_at = Some(n); s.torn_seed = Some(seed);
    }
    pub fn set_full_after_bytes(&self, b: u64) { self.state.lock().unwrap().full_after_bytes = Some(b); }
    pub fn io_ops(&self) -> u64 { self.state.lock().unwrap().io_ops }
    pub fn powered(&self) -> bool { self.state.lock().unwrap().powered }
}

// Our per-file tail appended after the real VFS's file struct. The real
// file occupies the first `default.szOsFile` bytes; ours follows.
#[repr(C)]
struct ShimFileTail {
    real: *mut ffi::sqlite3_file, // pointer to the embedded real file (this+offset)
    controller: *const CrashController,
    methods: *const ffi::sqlite3_io_methods,
}

// xOpen: ask the parent VFS to open into the real-file region, then install
// our io_methods so subsequent calls route through the shim.
unsafe extern "C" fn shim_open(
    vfs: *mut ffi::sqlite3_vfs,
    z_name: *const c_char,
    file: *mut ffi::sqlite3_file,
    flags: c_int,
    out_flags: *mut c_int,
) -> c_int {
    // The default VFS pointer was captured at register time; re-find it.
    let default = ffi::sqlite3_vfs_find(ptr::null());
    // Open via the default VFS into the SAME sqlite3_file buffer SQLite gave
    // us (it sized the allocation using our szOsFile). The real file's
    // methods get installed by the default xOpen; we then wrap them.
    let rc = ((*default).xOpen.unwrap())(default, z_name, file, flags, out_flags);
    if rc != ffi::SQLITE_OK { return rc; }
    install_shim_methods(vfs, file);
    ffi::SQLITE_OK
}
```

`install_shim_methods` builds a `sqlite3_io_methods` whose function pointers, for Task 2, all delegate to the file's *current* (real) methods — capture the real `*pMethods` first, then set our own. The intercepted three are implemented in Task 3; the rest (`xClose`, `xRead`, `xFileSize`, `xLock`, `xUnlock`, `xCheckReservedLock`, `xFileControl`, `xSectorSize`, `xDeviceCharacteristics`, and the optional WAL/shm methods if non-null) forward unchanged to the captured real methods.

> **Implementation note for the executor:** this is the keystone. Build incrementally — first make `install_shim_methods` set our methods table where *every* method (including `xWrite`/`xSync`/`xTruncate`) forwards to the real ones, and get Step 5 green. Only then (Task 3) change the three. Compile early and often; the ABI is unforgiving.

- [ ] **Step 5: Run, verify pass**

Run: `cargo test -p cw-store --features testing --test durability crud_round_trips_through_crash_vfs`
Expected: PASS — CRUD works identically through the shim.

- [ ] **Step 6: clippy + commit**

```bash
cargo clippy -p cw-store --features testing --all-targets -- -D warnings
git add rust/cw-core/cw-store/Cargo.toml rust/cw-core/cw-store/src/lib.rs rust/cw-core/cw-store/src/testing rust/cw-core/cw-store/tests/durability.rs rust/cw-core/cw-store/tests/common
git commit -m "test(cw-store): CrashVFS passthrough shim over default VFS"
```

---

## Task 3: Power-loss fault + the torture loop

**Files:**
- Modify: `rust/cw-core/cw-store/src/testing/crash_vfs.rs` (intercept `xWrite`/`xSync`/`xTruncate`, snapshot helper)
- Modify: `rust/cw-core/cw-store/tests/durability.rs`

**Interfaces:**
- Consumes: `CrashController` control methods from Task 2.
- Produces: `CrashController::snapshot_into(dst_dir)` — copy the current on-disk (synced) files for `db` + journal into `dst_dir`, applying torn-page garbling if armed.

- [ ] **Step 1: Write the failing torture test** — add to `tests/durability.rs`:

```rust
/// Walk a crash point across the I/O ops of the final (un-acked) commit and
/// assert every QSO acked *before* the crash survives intact, with integrity.
#[test]
fn power_loss_preserves_all_acked_qsos() {
    let max_crash_points = std::env::var("CW_DURABILITY_EXHAUSTIVE").is_ok();
    let cap = if max_crash_points { u64::MAX } else { 200 };

    for crash_after in 1..=cap {
        let dir = tempfile::tempdir().unwrap();
        let ctrl = CrashController::register(&format!("crashvfs-pl-{crash_after}"), dir.path().to_path_buf());
        let db = dir.path().join("log.db");

        // Acked baseline: 5 QSOs, each fully synced.
        {
            let store = Store::open_with_vfs(&db, "k", Some(&format!("crashvfs-pl-{crash_after}"))).unwrap();
            for i in 0..5 { store.upsert_qso(&common::sample_qso(&format!("acked-{i}"), 1000 + i as i64)).unwrap(); }

            // Arm power-off, then attempt one more upsert mid-commit.
            ctrl.arm_power_off_after(crash_after);
            let _ = store.upsert_qso(&common::sample_qso("inflight", 9999)); // may Ok or Err; not acked
        }
        if !ctrl.powered() {
            // Crash actually tripped — snapshot the frozen on-disk state.
            let snap = tempfile::tempdir().unwrap();
            ctrl.snapshot_into(snap.path()).unwrap();
            let store = Store::open(snap.path().join("log.db"), "k").unwrap();
            let integ: String = store_integrity(&store);
            assert_eq!(integ, "ok", "crash_after={crash_after}: integrity check failed");
            for i in 0..5 {
                let id = format!("acked-{i}");
                let rows = store.fetch_qsos(&QsoFilter { /* id filter */ ..Default::default() }, 1000, 0).unwrap();
                assert!(rows.iter().any(|q| q.id == id), "crash_after={crash_after}: lost acked {id}");
            }
        } else {
            // Workload finished before reaching the crash point — past the
            // I/O-op count of one commit. Stop scanning.
            break;
        }
    }
}

fn store_integrity(store: &Store) -> String {
    // cipher_integrity_check returns rows; "ok" path for SQLCipher is a single
    // 'ok' row, mirroring PRAGMA integrity_check.
    store.raw_pragma_check()
}
```

Add a small helper on `Store` (in `lib.rs`, behind no feature — harmless) so tests can run the integrity check without exposing `conn`:

```rust
/// Run `PRAGMA cipher_integrity_check` and return the first row (`"ok"` when clean).
pub fn integrity_check(&self) -> Result<String> {
    let mut stmt = self.conn.prepare("PRAGMA cipher_integrity_check")?;
    let mut rows = stmt.query([])?;
    match rows.next()? { Some(r) => Ok(r.get::<_, String>(0)?), None => Ok("ok".into()) }
}
```

(Replace the test's `store_integrity`/`raw_pragma_check` with `store.integrity_check().unwrap()`, and use a `QsoFilter` that fetches all then checks ids, since there is no id filter — fetch up to `MAX_FETCH_LIMIT`.)

- [ ] **Step 2: Run, verify failure**

Run: `cargo test -p cw-store --features testing --test durability power_loss_preserves_all_acked_qsos`
Expected: FAIL — `snapshot_into` / `arm_power_off_after` effect missing (VFS still passes writes straight through; `powered()` never flips).

- [ ] **Step 3: Implement the three intercepts + snapshot.** In `crash_vfs.rs`:

`shim_write(file, buf, n, offset)`:
1. Recover controller from the file tail. Lock state.
2. If `!powered` → return `SQLITE_OK` but write nothing (data lost — power is off).
3. `io_ops += 1`. If `full_after_bytes` set and `bytes_written + n > budget` → return `SQLITE_FULL`.
4. If `crash_at == Some(io_ops)` → set `powered = false`; if `torn_seed` set, write a **garbled** copy of `buf` (seeded RNG flips bytes in the affected 512-byte sectors) to the real file, else write nothing; return `SQLITE_OK`.
5. Otherwise delegate to the real `xWrite`, `bytes_written += n`.

`shim_sync(file, flags)`:
1. Recover controller; lock. `io_ops += 1`.
2. If `!powered` → `SQLITE_OK` (no flush; the would-be-durable bytes are lost).
3. If `crash_at == Some(io_ops)` → `powered = false`, return `SQLITE_OK` **without** delegating (the sync the app is waiting on never reaches the platter).
4. Otherwise delegate to the real `xSync`.

`shim_truncate(file, size)`: if `!powered` → `SQLITE_OK`; else delegate.

`snapshot_into(dst)`: copy every file in the VFS `dir` whose name starts with `log.db` (db, `-journal`, `-wal`, `-shm`) into `dst`. Because the shim only ever delegated *synced* writes to the real files (un-synced writes were buffered-then-dropped at power-off — modeled here by simply not writing them after power-off), the on-disk files already equal the power-loss image. (Store the VFS `dir` on the controller at `register` time — wire the `_dir` param through.)

> **Modeling note:** this design delegates writes to disk eagerly and *drops* writes/syncs only after power-off, rather than buffering all unsynced writes in memory. That is a faithful power-loss model for the assertion we make (acked-before-crash must survive): an acked commit completed all its `xWrite`+`xSync` before `crash_at`, so its bytes + journal are on disk; the in-flight commit's post-crash writes/sync are dropped. Torn-page additionally corrupts the single tripping write. This keeps the unsafe surface small and the invariant exact.

- [ ] **Step 4: Run, verify pass**

Run: `cargo test -p cw-store --features testing --test durability power_loss_preserves_all_acked_qsos`
Expected: PASS across all crash points (≤200 by default).

- [ ] **Step 5: clippy + commit**

```bash
cargo clippy -p cw-store --features testing --all-targets -- -D warnings
git add rust/cw-core/cw-store/src/testing/crash_vfs.rs rust/cw-core/cw-store/tests/durability.rs rust/cw-core/cw-store/src/lib.rs
git commit -m "test(cw-store): power-loss torture loop over commit I/O ops"
```

---

## Task 4: Torn-page fault

**Files:**
- Modify: `rust/cw-core/cw-store/tests/durability.rs`

**Interfaces:**
- Consumes: `arm_torn_power_off_after(n, seed)` + the torn branch in `shim_write` (Task 3).

- [ ] **Step 1: Write the failing test**

```rust
/// Even when the crash garbles the in-flight write's sectors, acked rows stay
/// intact and the DB recovers to a consistent state (integrity = ok).
#[test]
fn torn_page_never_corrupts_acked_rows() {
    for (seed, crash_after) in (0u64..50).map(|s| (s, 1 + s % 30)) {
        let name = format!("crashvfs-torn-{seed}");
        let dir = tempfile::tempdir().unwrap();
        let ctrl = CrashController::register(&name, dir.path().to_path_buf());
        let db = dir.path().join("log.db");
        {
            let store = Store::open_with_vfs(&db, "k", Some(&name)).unwrap();
            for i in 0..5 { store.upsert_qso(&common::sample_qso(&format!("acked-{i}"), 1000 + i as i64)).unwrap(); }
            ctrl.arm_torn_power_off_after(crash_after, seed);
            let _ = store.upsert_qso(&common::sample_qso("inflight", 9999));
        }
        if ctrl.powered() { continue; }
        let snap = tempfile::tempdir().unwrap();
        ctrl.snapshot_into(snap.path()).unwrap();
        let store = Store::open(snap.path().join("log.db"), "k").unwrap();
        assert_eq!(store.integrity_check().unwrap(), "ok", "seed={seed} crash_after={crash_after}");
        let rows = store.fetch_qsos(&QsoFilter::default(), cw_store::MAX_FETCH_LIMIT, 0).unwrap();
        for i in 0..5 {
            assert!(rows.iter().any(|q| q.id == format!("acked-{i}")), "seed={seed}: lost acked-{i}");
        }
    }
}
```

- [ ] **Step 2: Run, verify** — it should already pass if Task 3's torn branch is correct; if it fails, fix `shim_write`'s garble (ensure it only corrupts the *current* write's bytes and still recovers via the rollback journal). Run: `cargo test -p cw-store --features testing --test durability torn_page_never_corrupts_acked_rows`. Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add rust/cw-core/cw-store/tests/durability.rs
git commit -m "test(cw-store): torn-page crash never corrupts acked rows"
```

---

## Task 5: Disk-full (ENOSPC) fault

**Files:**
- Modify: `rust/cw-core/cw-store/tests/durability.rs`

**Interfaces:**
- Consumes: `set_full_after_bytes(budget)` + the `SQLITE_FULL` branch in `shim_write` (Task 3).

- [ ] **Step 1: Write the failing test**

```rust
/// Under ENOSPC the upsert fails cleanly; previously-acked rows remain intact
/// and the DB reopens without corruption.
#[test]
fn disk_full_fails_cleanly_without_data_loss() {
    let name = "crashvfs-enospc";
    let dir = tempfile::tempdir().unwrap();
    let ctrl = CrashController::register(name, dir.path().to_path_buf());
    let db = dir.path().join("log.db");
    {
        let store = Store::open_with_vfs(&db, "k", Some(name)).unwrap();
        for i in 0..5 { store.upsert_qso(&common::sample_qso(&format!("acked-{i}"), 1000 + i as i64)).unwrap(); }
        // Budget that allows the above but starves further growth.
        ctrl.set_full_after_bytes(ctrl_bytes_written_so_far(&ctrl));
        let mut hit_full = false;
        for i in 0..500 {
            if store.upsert_qso(&common::sample_qso(&format!("overflow-{i}"), 2000 + i as i64)).is_err() {
                hit_full = true; break;
            }
        }
        assert!(hit_full, "expected an SQLITE_FULL error under starved disk");
    }
    let store = Store::open(&db, "k").unwrap();
    assert_eq!(store.integrity_check().unwrap(), "ok");
    let rows = store.fetch_qsos(&QsoFilter::default(), cw_store::MAX_FETCH_LIMIT, 0).unwrap();
    for i in 0..5 { assert!(rows.iter().any(|q| q.id == format!("acked-{i}")), "lost acked-{i}"); }
}
```

Add `CrashController::bytes_written(&self) -> u64` (reads `state.bytes_written`); replace `ctrl_bytes_written_so_far(&ctrl)` with `ctrl.bytes_written()`.

- [ ] **Step 2: Run, verify failure then pass.** Run: `cargo test -p cw-store --features testing --test durability disk_full_fails_cleanly_without_data_loss`. If `bytes_written` accessor is missing it fails to compile; add it, then PASS.

- [ ] **Step 3: Commit**

```bash
git add rust/cw-core/cw-store/tests/durability.rs rust/cw-core/cw-store/src/testing/crash_vfs.rs
git commit -m "test(cw-store): disk-full fails cleanly with no acked data loss"
```

---

## Task 6: App-crash subprocess (real syscall path)

**Files:**
- Create: `rust/cw-core/cw-store/src/bin/durability_crasher.rs`
- Modify: `rust/cw-core/cw-store/tests/durability.rs`

**Interfaces:**
- The crasher binary CLI: `durability_crasher <db_path> <key> <qso_id>` → opens the real DB (default VFS), upserts the QSO, prints `ACK <qso_id>\n`, flushes stdout, then `std::process::abort()`.

- [ ] **Step 1: Write the crasher** — `src/bin/durability_crasher.rs`:

```rust
//! Spawned by the durability suite to test app-crash durability on the REAL
//! syscall path: upsert, ack, then abort() with no clean shutdown.
use std::io::Write;
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let (db, key, id) = (&args[1], &args[2], &args[3]);
    let store = cw_store::Store::open(db, key).expect("open");
    let mut qso = cw_store::testing::sample_qso_min(id); // shared minimal builder
    qso.qso_date = 1000;
    store.upsert_qso(&qso).expect("upsert");
    let mut out = std::io::stdout();
    writeln!(out, "ACK {id}").unwrap();
    out.flush().unwrap();
    std::process::abort();
}
```

Add `pub fn sample_qso_min(id: &str) -> Qso` to `src/testing/mod.rs` (a public minimal builder mirroring the test `sample_qso`, so both the bin and tests share it).

- [ ] **Step 2: Write the failing test** — add to `tests/durability.rs`:

```rust
#[test]
fn app_crash_after_ack_preserves_qso() {
    let dir = tempfile::tempdir().unwrap();
    let db = dir.path().join("log.db");
    let exe = env!("CARGO_BIN_EXE_durability_crasher");
    let out = std::process::Command::new(exe)
        .args([db.to_str().unwrap(), "k", "crashy"])
        .output().unwrap();
    assert!(String::from_utf8_lossy(&out.stdout).contains("ACK crashy"), "no ack printed");
    assert!(!out.status.success(), "process must abort abnormally");
    let store = Store::open(&db, "k").unwrap();
    assert_eq!(store.integrity_check().unwrap(), "ok");
    let rows = store.fetch_qsos(&QsoFilter::default(), 10, 0).unwrap();
    assert!(rows.iter().any(|q| q.id == "crashy"), "acked QSO lost across process abort");
}
```

- [ ] **Step 3: Run, verify** — Run: `cargo test -p cw-store --features testing --test durability app_crash_after_ack_preserves_qso`. Expected: PASS (abort after a synced commit cannot lose the row).

- [ ] **Step 4: Commit**

```bash
git add rust/cw-core/cw-store/src/bin/durability_crasher.rs rust/cw-core/cw-store/src/testing/mod.rs rust/cw-core/cw-store/tests/durability.rs
git commit -m "test(cw-store): app-crash subprocess preserves acked QSO"
```

---

## Task 7: Concurrency torture (Rust)

**Files:**
- Modify: `rust/cw-core/cw-store/tests/durability.rs`

- [ ] **Step 1: Write the test** — heavier than Task 1's; many threads, many writes, a read-while-write thread, with a wall-clock timeout guard:

```rust
#[test]
fn concurrent_writers_and_reader_no_loss_no_corruption() {
    use std::sync::Arc;
    use std::time::{Duration, Instant};
    let dir = tempfile::tempdir().unwrap();
    let db = Arc::new(dir.path().join("log.db"));
    Store::open(&*db, "k").unwrap();
    let started = Instant::now();
    let writers: Vec<_> = (0..8).map(|t| {
        let db = Arc::clone(&db);
        std::thread::spawn(move || {
            let store = Store::open(&*db, "k").unwrap();
            for i in 0..100 { store.upsert_qso(&common::sample_qso(&format!("{t}-{i}"), 1000)).unwrap(); }
        })
    }).collect();
    // Concurrent reader must never observe corruption.
    let reader_db = Arc::clone(&db);
    let reader = std::thread::spawn(move || {
        let store = Store::open(&*reader_db, "k").unwrap();
        for _ in 0..50 { let _ = store.fetch_qsos(&QsoFilter::default(), 1000, 0).unwrap(); }
    });
    for w in writers { w.join().unwrap(); }
    reader.join().unwrap();
    assert!(started.elapsed() < Duration::from_secs(60), "concurrency test exceeded timeout");
    let store = Store::open(&*db, "k").unwrap();
    assert_eq!(store.integrity_check().unwrap(), "ok");
    assert_eq!(store.qso_count().unwrap(), 800);
}
```

- [ ] **Step 2: Run, verify pass** — Run: `cargo test -p cw-store --features testing --test durability concurrent_writers_and_reader_no_loss_no_corruption`. Expected: PASS (relies on Task 1's `busy_timeout`). If it ever flakes with `SQLITE_BUSY`, that is a real finding — raise `busy_timeout` and note it.

- [ ] **Step 3: Commit**

```bash
git add rust/cw-core/cw-store/tests/durability.rs
git commit -m "test(cw-store): concurrent writers + reader, no loss or corruption"
```

---

## Task 8: Swift app-crash crasher executable

**Files:**
- Modify: `swift/packages/CarrierWaveCore/Package.swift`
- Create: `swift/packages/CarrierWaveCore/Sources/LogDurabilityCrasher/main.swift`

**Interfaces:**
- CLI: `LogDurabilityCrasher <db_path> <key> <qso_id>` → opens `FieldStore`, upserts a QSO, prints `ACK <id>`, flushes, `abort()`. Uses the same FieldStore API the app uses (`FieldStore(dbPath:key:)`, `upsertQso(_:)`). The executor must confirm the exact generated initializer/method names from `Sources/CarrierWaveCwFfi/CwFfi+Generated.swift` and the `FfiQso` field names before writing this file.

- [ ] **Step 1: Inspect the generated FieldStore API.** Run:

```bash
grep -n "class FieldStore\|func upsertQso\|struct FfiQso\|public init" swift/packages/CarrierWaveCore/Sources/CarrierWaveCwFfi/*.swift | head -40
```

Record the open/init signature and `upsertQso` parameter type. (The Rust `FieldStore` in `cw-ffi/src/lib.rs` exposes a constructor taking a db path + key and a `upsert_qso` method; confirm the Swift spelling.)

- [ ] **Step 2: Add the executable target.** In `Package.swift`, add a product and target mirroring `LoFiCLI`:

```swift
// products:
.executable(name: "LogDurabilityCrasher", targets: ["LogDurabilityCrasher"]),
// targets:
.executableTarget(
    name: "LogDurabilityCrasher",
    dependencies: ["CarrierWaveCore"]
),
```

- [ ] **Step 3: Write `main.swift`** using the API recorded in Step 1 (illustrative — adjust names to the generated surface):

```swift
import CarrierWaveCore
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else { fputs("usage: LogDurabilityCrasher <db> <key> <id>\n", stderr); exit(2) }
let (dbPath, key, id) = (args[1], args[2], args[3])

let store = try! FieldStore(dbPath: dbPath, key: key)
var qso = FfiQso.minimal(id: id)   // build via the generated record initializer
try! store.upsertQso(qso: qso)
print("ACK \(id)")
fflush(stdout)
abort()
```

If there is no `FfiQso.minimal` helper, construct the record inline with all required fields (mirror `cw-store` `sample_qso`); add a small `extension FfiQso` in this target for brevity.

- [ ] **Step 4: Build, verify**

Run: `cd swift/packages/CarrierWaveCore && swift build --product LogDurabilityCrasher`
Expected: builds (requires `Vendored/CwFfi.xcframework` present — build it first via `rust/cw-core/scripts/build-xcframework.sh` if missing).

- [ ] **Step 5: Commit**

```bash
git add swift/packages/CarrierWaveCore/Package.swift swift/packages/CarrierWaveCore/Sources/LogDurabilityCrasher
git commit -m "test(core): Swift LogDurabilityCrasher executable (ack then abort)"
```

---

## Task 9: Swift durability tests (app-crash + concurrency)

**Files:**
- Create: `swift/packages/CarrierWaveCore/Tests/CarrierWaveCoreTests/LogDurabilityTests.swift`

**Interfaces:**
- Consumes: the `LogDurabilityCrasher` executable (Task 8) + `FieldStore` API.

- [ ] **Step 1: Write the tests** (swift-testing; resolve the crasher relative to the package's `.build` products dir via `#filePath`):

```swift
import Testing
import Foundation
@testable import CarrierWaveCore

private func crasherURL() -> URL {
    // <pkg>/Tests/CarrierWaveCoreTests/LogDurabilityTests.swift -> <pkg>
    let pkg = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    // swift test builds products into .build/debug (symlink to arch dir).
    return pkg.appendingPathComponent(".build/debug/LogDurabilityCrasher")
}

@Test func appCrashAfterAckPreservesQso() throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let db = tmp.appendingPathComponent("log.db").path

    let proc = Process()
    proc.executableURL = crasherURL()
    proc.arguments = [db, "k", "swiftcrash"]
    let pipe = Pipe(); proc.standardOutput = pipe
    try proc.run(); proc.waitUntilExit()

    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    #expect(out.contains("ACK swiftcrash"))
    #expect(proc.terminationReason == .uncaughtSignal)  // abort() -> SIGABRT

    let store = try FieldStore(dbPath: db, key: "k")
    let rows = try store.fetchQsos(filter: .init(), limit: 10, offset: 0)
    #expect(rows.contains { $0.id == "swiftcrash" })
}

@Test func concurrentUpsertsAllPersist() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let db = tmp.appendingPathComponent("log.db").path
    let store = try FieldStore(dbPath: db, key: "k")

    await withThrowingTaskGroup(of: Void.self) { group in
        for t in 0..<4 {
            group.addTask {
                for i in 0..<50 { try store.upsertQso(qso: FfiQso.minimal(id: "\(t)-\(i)")) }
            }
        }
    }
    #expect(try store.qsoCount() == 200)
}
```

Adjust `FieldStore`/`FfiQso`/`fetchQsos`/`qsoCount` spellings to the generated surface (confirmed in Task 8 Step 1). If `FieldStore` is not `Sendable`/safe to share across tasks, give each task its own `FieldStore(dbPath:key:)` on the same file (exercising `busy_timeout`) — note which you chose.

- [ ] **Step 2: Run, verify pass**

Run: `cd swift/packages/CarrierWaveCore && swift test --filter LogDurabilityTests`
Expected: PASS (requires the crasher product built; `swift test` builds it).

- [ ] **Step 3: Commit**

```bash
git add swift/packages/CarrierWaveCore/Tests/CarrierWaveCoreTests/LogDurabilityTests.swift
git commit -m "test(core): Swift app-crash + concurrency durability tests"
```

---

## Task 10: CI wiring + FILE_INDEX

**Files:**
- Modify: `.github/workflows/cw-core-rust.yml`
- Modify: `rust/cw-core/FILE_INDEX.md`

- [ ] **Step 1: Add Rust feature steps** to the `test` job (after the existing clippy/test steps):

```yaml
      - name: cargo clippy (testing feature)
        run: cargo clippy -p cw-store --features testing --all-targets -- -D warnings

      - name: cargo test (durability suite)
        run: cargo test -p cw-store --features testing --locked
```

- [ ] **Step 2: Add the Swift filter** to the `xcframework` job, after the existing parity tests (same `working-directory: swift/packages/CarrierWaveCore`):

```yaml
          swift test --filter LogDurabilityTests
```

- [ ] **Step 3: Update `rust/cw-core/FILE_INDEX.md`** — add rows under `cw-store`:

```
| `src/testing/crash_vfs.rs` | Crash-injection shim VFS over the default VFS (feature `testing`); power-loss/torn-page/ENOSPC fault injection + crash-image snapshot |
| `src/bin/durability_crasher.rs` | App-crash child: upsert, ACK, abort() (feature `testing`) |
| `tests/durability.rs` | Write-durability torture suite: power-loss/torn/ENOSPC/app-crash/concurrency |
```

- [ ] **Step 4: Full local gate**

```bash
cd rust/cw-core
cargo clippy --workspace --all-targets -- -D warnings
cargo clippy -p cw-store --features testing --all-targets -- -D warnings
cargo test --workspace --locked
cargo test -p cw-store --features testing --locked
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/cw-core-rust.yml rust/cw-core/FILE_INDEX.md
git commit -m "ci: run durability torture suite (Rust + Swift filter); index new files"
```

---

## Self-Review Notes (coverage vs. spec)

- **Invariant (ack ⇒ durable):** Tasks 3/4/6/9 assert acked rows survive; integrity checked every reopen. ✓
- **Power loss:** Task 3. **Torn page:** Task 4. **ENOSPC:** Task 5. **App crash:** Task 6 (Rust) + Task 8/9 (Swift). **Concurrency:** Task 7 (Rust) + Task 9 (Swift). ✓ (full-spectrum matrix covered)
- **QSO-only scope:** all assertions target `qso`. ✓
- **Test + harden:** Task 1 ships the pragmas + seam the suite depends on. ✓
- **Both layers:** Rust (Tasks 1–7) + Swift (Tasks 8–9). ✓
- **CI honesty:** Rust suite in Linux CI (Task 10 Step 1); Swift suite in the macOS job (Step 2); the `testing` feature is explicitly enabled because `--workspace` won't. ✓
- **Honest limitation:** software cannot prove bare-metal power loss; the VFS proves the SQLite durability *contract*; `fullfsync=ON` closes the Apple side. Documented in the spec. ✓
- **Known executor risks flagged inline:** the unsafe VFS ABI (Task 2 keystone note), generated Swift API spelling (Task 8 Step 1), and `.build` product path resolution (Task 9). These are verify-as-you-go, not placeholders.
```
