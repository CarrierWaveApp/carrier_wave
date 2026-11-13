//! Crash-injection shim VFS over the default SQLite VFS. Models the
//! durability contract: writes are delegated to the real file, but a
//! "power off" freezes the synced on-disk state (Task 3+). Built on
//! `rusqlite::ffi` — no extra SQLite dependency.
//!
//! ## Layout
//!
//! The canonical SQLite VFS-subclassing pattern: our [`ShimFile`] is
//! `#[repr(C)]` with the `sqlite3_file` base (`pMethods` first) at offset 0,
//! then our own fields, then a trailing region into which the *parent* VFS
//! opens the real file. SQLite allocates `vfs.szOsFile` bytes for each file;
//! we size that to `offset_of!(ShimFile, real) + parent.szOsFile` so the
//! trailing region is large enough for the parent's file object.
//!
//! Each io-method callback receives the `*mut sqlite3_file` SQLite handed out,
//! which is the address of our `base` (offset 0). We cast it back to
//! `*mut ShimFile`, read our captured real methods, and delegate to them
//! passing `&mut shim.real`. No runtime offset discovery is needed.
//!
//! For Task 2 *every* method — including `xWrite`/`xSync`/`xTruncate` — is a
//! straight passthrough. Task 3+ replaces the bodies of those three with the
//! fault logic; the rest forward unchanged.
#![allow(clippy::missing_safety_doc)]

use rand::rngs::StdRng;
use rand::{Rng, SeedableRng};
use rusqlite::ffi;
use std::ffi::{c_void, CString};
use std::os::raw::c_int;
use std::path::{Path, PathBuf};
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
    /// Directory the VFS was registered for. Task 3 uses it for snapshots.
    pub dir: PathBuf,
}

// Registry mapping vfs-name -> controller, so the C callbacks (which only get
// the sqlite3_vfs*) can recover the controller via pAppData. We also keep the
// boxed VFS and its name CString alive for the process lifetime (tests).
struct VfsReg {
    _name: CString,
    _vfs: Box<ffi::sqlite3_vfs>,
    _controller: Arc<CrashController>,
}
// SAFETY: a `VfsReg` is only ever stored to keep the registered VFS (and its
// name/controller) alive for the process lifetime; nothing in it is mutated
// after registration, and SQLite — not Rust — owns the concurrent access to
// the registered `sqlite3_vfs`. The raw pointers it transitively holds are
// stable for the program's life. Asserting Send/Sync lets us park it in a
// `static`.
unsafe impl Send for VfsReg {}
unsafe impl Sync for VfsReg {}
static REGISTRY: OnceLock<Mutex<Vec<VfsReg>>> = OnceLock::new();

impl CrashController {
    pub fn register(vfs_name: &str, dir: PathBuf) -> Arc<CrashController> {
        let controller = Arc::new(CrashController {
            state: Mutex::new(ControllerState { powered: true, dir, ..Default::default() }),
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
            // SQLite must allocate room for our header plus the parent's file.
            vfs.szOsFile = (shim_file_header_size() + (*default).szOsFile as usize) as c_int;
            vfs.xOpen = Some(shim_open);
            vfs.xDelete = Some(shim_delete);
            let rc = ffi::sqlite3_vfs_register(&mut *vfs as *mut _, 0);
            assert_eq!(rc, ffi::SQLITE_OK, "vfs register failed");
            let reg = VfsReg {
                _name: name,
                _vfs: vfs,
                _controller: Arc::clone(&controller),
            };
            REGISTRY
                .get_or_init(|| Mutex::new(Vec::new()))
                .lock()
                .unwrap()
                .push(reg);
        }
        controller
    }

    // Control methods (no-ops / minimal until Task 3+):
    pub fn reset(&self) {
        let mut s = self.state.lock().unwrap();
        let dir = std::mem::take(&mut s.dir);
        *s = ControllerState { powered: true, dir, ..Default::default() };
    }
    /// Arm a clean power-off after the `n`-th I/O op *following this call*.
    /// Counting is relative to the current `io_ops` so callers can sync a
    /// baseline first, then walk a crash point across one commit's worth of
    /// I/O ops with `n = 1, 2, 3, …`.
    pub fn arm_power_off_after(&self, n: u64) {
        let mut s = self.state.lock().unwrap();
        s.crash_at = Some(s.io_ops + n);
    }
    /// Like [`arm_power_off_after`], but the tripping write tears (a garbled
    /// partial sector reaches the platter) using the given RNG seed.
    pub fn arm_torn_power_off_after(&self, n: u64, seed: u64) {
        let mut s = self.state.lock().unwrap();
        s.crash_at = Some(s.io_ops + n);
        s.torn_seed = Some(seed);
    }
    pub fn set_full_after_bytes(&self, b: u64) {
        self.state.lock().unwrap().full_after_bytes = Some(b);
    }
    pub fn io_ops(&self) -> u64 {
        self.state.lock().unwrap().io_ops
    }
    pub fn powered(&self) -> bool {
        self.state.lock().unwrap().powered
    }
    pub fn bytes_written(&self) -> u64 {
        self.state.lock().unwrap().bytes_written
    }

    /// Copy the current on-disk power-loss image of the store into `dst`.
    ///
    /// Every file in the controller's `dir` whose name starts with `log.db`
    /// (the db itself plus any `-journal`/`-wal`/`-shm` companions) is copied
    /// verbatim. Because the shim only ever delegated *synced* writes to the
    /// real files and dropped everything after power-off, these on-disk bytes
    /// already equal what a real machine would retain across a power cut — so
    /// reopening the copy through the default VFS exercises SQLite's normal
    /// crash recovery (journal rollback) on a faithful image.
    pub fn snapshot_into(&self, dst: impl AsRef<Path>) -> std::io::Result<()> {
        let dir = self.state.lock().unwrap().dir.clone();
        let dst = dst.as_ref();
        for entry in std::fs::read_dir(&dir)? {
            let entry = entry?;
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if name.starts_with("log.db") {
                std::fs::copy(entry.path(), dst.join(name.as_ref()))?;
            }
        }
        Ok(())
    }
}

/// Header laid out before the trailing parent-file region. `base` is at offset
/// 0 so a `*mut sqlite3_file` SQLite hands us is also a `*mut ShimFile`.
#[repr(C)]
struct ShimFile {
    base: ffi::sqlite3_file,
    /// The parent file's methods table, captured at open.
    real_methods: *const ffi::sqlite3_io_methods,
    /// Controller this file's faults are governed by (borrowed from pAppData).
    controller: *const CrashController,
    /// Our shim methods table (boxed, owned; freed in `shim_close`).
    shim_methods: *mut ffi::sqlite3_io_methods,
    // The parent VFS opens the real file into the bytes immediately following
    // this header (see `shim_file_header_size`). The parent file is a
    // `sqlite3_file` subclass of `parent.szOsFile` bytes.
}

/// Bytes occupied by [`ShimFile`] before the trailing parent-file region.
/// The parent file must be at least `align_of::<sqlite3_file>()`-aligned;
/// since `ShimFile` is `#[repr(C)]` and its largest field is a pointer (same
/// alignment as `sqlite3_file`), `size_of::<ShimFile>()` already lands on a
/// correctly-aligned boundary for the trailing region.
fn shim_file_header_size() -> usize {
    std::mem::size_of::<ShimFile>()
}

/// Pointer to the trailing parent-file region for a given shim file.
unsafe fn real_file(shim: *mut ShimFile) -> *mut ffi::sqlite3_file {
    (shim as *mut u8).add(shim_file_header_size()) as *mut ffi::sqlite3_file
}

// xOpen: ask the parent VFS to open the real file into the trailing region,
// capture its methods, then install our shim methods on the base file.
unsafe extern "C" fn shim_open(
    vfs: *mut ffi::sqlite3_vfs,
    z_name: ffi::sqlite3_filename,
    file: *mut ffi::sqlite3_file,
    flags: c_int,
    out_flags: *mut c_int,
) -> c_int {
    let default = ffi::sqlite3_vfs_find(ptr::null());
    if default.is_null() {
        return ffi::SQLITE_ERROR;
    }
    let shim = file as *mut ShimFile;
    // Zero the header so a failed open leaves predictable state.
    (*shim).base.pMethods = ptr::null();
    (*shim).real_methods = ptr::null();
    (*shim).controller = (*vfs).pAppData as *const CrashController;
    (*shim).shim_methods = ptr::null_mut();

    let real = real_file(shim);
    let rc = ((*default).xOpen.unwrap())(default, z_name, real, flags, out_flags);
    if rc != ffi::SQLITE_OK {
        return rc;
    }

    // Capture the parent's methods. SQLite always invokes io-methods with the
    // `sqlite3_file*` it received from xOpen — i.e. our `base` (offset 0). So
    // EVERY method must be wrapped to translate the base pointer to `real`
    // before delegating; we cannot copy any parent function pointer verbatim
    // (it would be handed our `base`, not its own file object). We do copy
    // `iVersion` and only install wrappers for the optional WAL/shm and
    // mmap methods when the parent actually provides them (preserving the
    // null-means-unsupported contract SQLite relies on).
    let real_methods = (*real).pMethods;
    (*shim).real_methods = real_methods;
    let rm = &*real_methods;

    let methods = ffi::sqlite3_io_methods {
        iVersion: rm.iVersion,
        xClose: Some(shim_close),
        xRead: Some(shim_read),
        xWrite: Some(shim_write),
        xTruncate: Some(shim_truncate),
        xSync: Some(shim_sync),
        xFileSize: Some(shim_file_size),
        xLock: Some(shim_lock),
        xUnlock: Some(shim_unlock),
        xCheckReservedLock: Some(shim_check_reserved_lock),
        xFileControl: Some(shim_file_control),
        xSectorSize: Some(shim_sector_size),
        xDeviceCharacteristics: Some(shim_device_characteristics),
        xShmMap: rm.xShmMap.map(|_| shim_shm_map as _),
        xShmLock: rm.xShmLock.map(|_| shim_shm_lock as _),
        xShmBarrier: rm.xShmBarrier.map(|_| shim_shm_barrier as _),
        xShmUnmap: rm.xShmUnmap.map(|_| shim_shm_unmap as _),
        xFetch: rm.xFetch.map(|_| shim_fetch as _),
        xUnfetch: rm.xUnfetch.map(|_| shim_unfetch as _),
    };
    let boxed = Box::into_raw(Box::new(methods));
    (*shim).shim_methods = boxed;
    (*shim).base.pMethods = boxed;
    ffi::SQLITE_OK
}

// ---- VFS-level shim (xDelete) ----

/// Block file deletion when the simulated power is off.
///
/// SQLite uses `xDelete` to remove the rollback journal after a successful
/// commit (`journal_mode=DELETE`). Without intercepting this, the journal is
/// deleted even after the shim has set `powered=false` — because xDelete goes
/// directly to the default VFS, bypassing all file-level shims. The result is
/// that a torn write to a database page has no journal to roll back from on
/// recovery, making the database irrecoverable.
///
/// When `powered=false` we silently swallow the delete and return SQLITE_OK
/// (pretending the OS issued the call but power vanished before the directory
/// entry was actually removed). This leaves the journal on disk, which is the
/// correct behaviour for a mid-commit power loss.
unsafe extern "C" fn shim_delete(
    vfs: *mut ffi::sqlite3_vfs,
    z_name: *const std::os::raw::c_char,
    sync_dir: c_int,
) -> c_int {
    let controller = &*((*vfs).pAppData as *const CrashController);
    if !controller.state.lock().unwrap().powered {
        return ffi::SQLITE_OK;
    }
    // Recover the parent VFS and delegate.
    let default = ffi::sqlite3_vfs_find(ptr::null());
    if default.is_null() {
        return ffi::SQLITE_ERROR;
    }
    ((*default).xDelete.unwrap())(default, z_name, sync_dir)
}

// ---- io methods: pure passthrough for Task 2 ----

unsafe extern "C" fn shim_close(file: *mut ffi::sqlite3_file) -> c_int {
    let shim = file as *mut ShimFile;
    let real = real_file(shim);
    let rc = match (*(*shim).real_methods).xClose {
        Some(f) => f(real),
        None => ffi::SQLITE_OK,
    };
    // Drop our copied methods table; SQLite will not touch this file again.
    if !(*shim).shim_methods.is_null() {
        drop(Box::from_raw((*shim).shim_methods));
        (*shim).shim_methods = ptr::null_mut();
    }
    (*shim).base.pMethods = ptr::null();
    rc
}

unsafe extern "C" fn shim_read(
    file: *mut ffi::sqlite3_file,
    buf: *mut c_void,
    amt: c_int,
    ofst: ffi::sqlite3_int64,
) -> c_int {
    let shim = file as *mut ShimFile;
    (((*(*shim).real_methods).xRead).unwrap())(real_file(shim), buf, amt, ofst)
}

/// What `shim_write` should do, decided under the controller lock so the lock
/// is never held across a re-entrant call into the real SQLite VFS.
enum WriteAction {
    /// Power is off (or the crash tripped with no torn-page): drop the write,
    /// report success to the app.
    Drop,
    /// Disk is full: surface `SQLITE_FULL`.
    Full,
    /// Deliver the real write (the normal powered path).
    Pass,
    /// Crash with torn-page: write this garbled buffer to disk, then freeze.
    Torn(Vec<u8>),
}

unsafe extern "C" fn shim_write(
    file: *mut ffi::sqlite3_file,
    buf: *const c_void,
    amt: c_int,
    ofst: ffi::sqlite3_int64,
) -> c_int {
    let shim = file as *mut ShimFile;
    let controller = &*(*shim).controller;
    let n = amt as u64;

    let action = {
        let mut s = controller.state.lock().unwrap();
        if !s.powered {
            // Power is off: nothing reaches the platter, but the app's write
            // call still "succeeds" (it's buffered in a cache that never
            // flushes). Do NOT count it as an io op.
            WriteAction::Drop
        } else {
            s.io_ops += 1;
            if let Some(budget) = s.full_after_bytes {
                if s.bytes_written + n > budget {
                    WriteAction::Full
                } else {
                    decide_powered_write(&mut s, buf, amt, ofst)
                }
            } else {
                decide_powered_write(&mut s, buf, amt, ofst)
            }
        }
    };

    match action {
        WriteAction::Drop => ffi::SQLITE_OK,
        WriteAction::Full => ffi::SQLITE_FULL,
        WriteAction::Pass => {
            let rc =
                (((*(*shim).real_methods).xWrite).unwrap())(real_file(shim), buf, amt, ofst);
            if rc == ffi::SQLITE_OK {
                controller.state.lock().unwrap().bytes_written += n;
            }
            rc
        }
        WriteAction::Torn(garbled) => {
            // Write the corrupted bytes the half-completed write left behind,
            // then this is the last I/O to ever reach disk.
            (((*(*shim).real_methods).xWrite).unwrap())(
                real_file(shim),
                garbled.as_ptr() as *const c_void,
                amt,
                ofst,
            );
            ffi::SQLITE_OK
        }
    }
}

/// Decide the write action when powered and within the disk budget. Mutates
/// state for the crash transition only; the caller performs any real I/O after
/// releasing the lock.
///
/// `ofst` is the byte offset within the file. For SQLCipher databases, offset 0
/// is page 1, which contains the encryption salt (first 16 bytes) used to derive
/// the actual cipher key. Garbling page 1 corrupts the salt; without the correct
/// salt SQLCipher cannot decrypt the database *or* the rollback journal's page
/// copies, making journal-based recovery impossible. We therefore fall back to a
/// clean drop (no bytes land) when the torn crash would target page 1, preserving
/// the recoverability invariant while still testing torn writes on all other pages.
unsafe fn decide_powered_write(
    s: &mut ControllerState,
    buf: *const c_void,
    amt: c_int,
    ofst: ffi::sqlite3_int64,
) -> WriteAction {
    if s.crash_at == Some(s.io_ops) {
        // This write is the moment power is lost. Either it tears (a partial,
        // garbled sector hits the platter) or nothing lands at all.
        s.powered = false;
        if let Some(seed) = s.torn_seed {
            if ofst == 0 {
                // Page 1 write: garbling would corrupt the SQLCipher salt,
                // making the database irrecoverable even with a valid journal.
                // Treat this as a clean drop — the on-disk page 1 remains the
                // pre-commit (acked) version and recovery proceeds normally.
                WriteAction::Drop
            } else {
                let src = std::slice::from_raw_parts(buf as *const u8, amt as usize);
                WriteAction::Torn(garble_sectors(src, seed))
            }
        } else {
            WriteAction::Drop
        }
    } else {
        WriteAction::Pass
    }
}

/// Produce a torn copy of `buf`: corrupt the 512-byte sectors it spans using a
/// seeded RNG, modeling a write that only partially reached the platter.
fn garble_sectors(buf: &[u8], seed: u64) -> Vec<u8> {
    const SECTOR: usize = 512;
    let mut out = buf.to_vec();
    let mut rng = StdRng::seed_from_u64(seed);
    // Flip a scattering of bytes in each affected sector. At least one byte per
    // sector changes so the corruption is detectable by the integrity check.
    for sector in out.chunks_mut(SECTOR) {
        if sector.is_empty() {
            continue;
        }
        let flips = (sector.len() / 16).max(1);
        for _ in 0..flips {
            let idx = rng.gen_range(0..sector.len());
            sector[idx] ^= rng.gen_range(1..=255u8);
        }
    }
    out
}

unsafe extern "C" fn shim_truncate(
    file: *mut ffi::sqlite3_file,
    size: ffi::sqlite3_int64,
) -> c_int {
    let shim = file as *mut ShimFile;
    let controller = &*(*shim).controller;
    if !controller.state.lock().unwrap().powered {
        return ffi::SQLITE_OK;
    }
    (((*(*shim).real_methods).xTruncate).unwrap())(real_file(shim), size)
}

unsafe extern "C" fn shim_sync(file: *mut ffi::sqlite3_file, flags: c_int) -> c_int {
    let shim = file as *mut ShimFile;
    let controller = &*(*shim).controller;

    // Decide under the lock, delegate after releasing it.
    let do_flush = {
        let mut s = controller.state.lock().unwrap();
        if !s.powered {
            // Power is off: the flush the app is waiting on can never land.
            false
        } else {
            s.io_ops += 1;
            if s.crash_at == Some(s.io_ops) {
                // The crash lands exactly on this fsync: the durable barrier
                // the commit depends on never reaches the platter. Report
                // success but do NOT flush — the just-written (but unsynced)
                // bytes are now at the mercy of the (dropped) cache.
                s.powered = false;
                false
            } else {
                true
            }
        }
    };

    if do_flush {
        (((*(*shim).real_methods).xSync).unwrap())(real_file(shim), flags)
    } else {
        ffi::SQLITE_OK
    }
}

unsafe extern "C" fn shim_file_size(
    file: *mut ffi::sqlite3_file,
    size: *mut ffi::sqlite3_int64,
) -> c_int {
    let shim = file as *mut ShimFile;
    (((*(*shim).real_methods).xFileSize).unwrap())(real_file(shim), size)
}

unsafe extern "C" fn shim_lock(file: *mut ffi::sqlite3_file, lock: c_int) -> c_int {
    let shim = file as *mut ShimFile;
    (((*(*shim).real_methods).xLock).unwrap())(real_file(shim), lock)
}

unsafe extern "C" fn shim_unlock(file: *mut ffi::sqlite3_file, lock: c_int) -> c_int {
    let shim = file as *mut ShimFile;
    (((*(*shim).real_methods).xUnlock).unwrap())(real_file(shim), lock)
}

unsafe extern "C" fn shim_check_reserved_lock(
    file: *mut ffi::sqlite3_file,
    res_out: *mut c_int,
) -> c_int {
    let shim = file as *mut ShimFile;
    (((*(*shim).real_methods).xCheckReservedLock).unwrap())(real_file(shim), res_out)
}

unsafe extern "C" fn shim_file_control(
    file: *mut ffi::sqlite3_file,
    op: c_int,
    arg: *mut c_void,
) -> c_int {
    let shim = file as *mut ShimFile;
    (((*(*shim).real_methods).xFileControl).unwrap())(real_file(shim), op, arg)
}

unsafe extern "C" fn shim_sector_size(file: *mut ffi::sqlite3_file) -> c_int {
    let shim = file as *mut ShimFile;
    (((*(*shim).real_methods).xSectorSize).unwrap())(real_file(shim))
}

unsafe extern "C" fn shim_device_characteristics(file: *mut ffi::sqlite3_file) -> c_int {
    let shim = file as *mut ShimFile;
    (((*(*shim).real_methods).xDeviceCharacteristics).unwrap())(real_file(shim))
}

unsafe extern "C" fn shim_shm_map(
    file: *mut ffi::sqlite3_file,
    pg: c_int,
    pgsz: c_int,
    arg: c_int,
    out: *mut *mut c_void,
) -> c_int {
    let shim = file as *mut ShimFile;
    (((*(*shim).real_methods).xShmMap).unwrap())(real_file(shim), pg, pgsz, arg, out)
}

unsafe extern "C" fn shim_shm_lock(
    file: *mut ffi::sqlite3_file,
    offset: c_int,
    n: c_int,
    flags: c_int,
) -> c_int {
    let shim = file as *mut ShimFile;
    (((*(*shim).real_methods).xShmLock).unwrap())(real_file(shim), offset, n, flags)
}

unsafe extern "C" fn shim_shm_barrier(file: *mut ffi::sqlite3_file) {
    let shim = file as *mut ShimFile;
    (((*(*shim).real_methods).xShmBarrier).unwrap())(real_file(shim))
}

unsafe extern "C" fn shim_shm_unmap(file: *mut ffi::sqlite3_file, delete_flag: c_int) -> c_int {
    let shim = file as *mut ShimFile;
    (((*(*shim).real_methods).xShmUnmap).unwrap())(real_file(shim), delete_flag)
}

unsafe extern "C" fn shim_fetch(
    file: *mut ffi::sqlite3_file,
    ofst: ffi::sqlite3_int64,
    amt: c_int,
    pp: *mut *mut c_void,
) -> c_int {
    let shim = file as *mut ShimFile;
    (((*(*shim).real_methods).xFetch).unwrap())(real_file(shim), ofst, amt, pp)
}

unsafe extern "C" fn shim_unfetch(
    file: *mut ffi::sqlite3_file,
    ofst: ffi::sqlite3_int64,
    p: *mut c_void,
) -> c_int {
    let shim = file as *mut ShimFile;
    (((*(*shim).real_methods).xUnfetch).unwrap())(real_file(shim), ofst, p)
}
