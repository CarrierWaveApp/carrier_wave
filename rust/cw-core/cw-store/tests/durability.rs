#![cfg(feature = "testing")]
use cw_store::testing::CrashController;
use cw_store::{QsoFilter, Store};

mod common;

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

/// Walk a crash point across the I/O ops of the final (un-acked) commit and
/// assert every QSO acked *before* the crash survives intact, with integrity.
///
/// Modeling: the crash VFS delegates writes/syncs to disk eagerly while
/// powered and *drops* everything after power-off. A QSO whose `upsert_qso`
/// returned `Ok` before the crash therefore had all its writes + journal sync
/// completed to disk and MUST survive; the in-flight (un-acked) commit's
/// post-crash I/O is dropped and may be absent.
#[test]
fn power_loss_preserves_all_acked_qsos() {
    let exhaustive = std::env::var("CW_DURABILITY_EXHAUSTIVE").is_ok();
    let cap: u64 = if exhaustive { u64::MAX } else { 200 };
    let mut tripped = false;

    for crash_after in 1..=cap {
        let dir = tempfile::tempdir().unwrap();
        let vfs_name = format!("crashvfs-pl-{crash_after}");
        let ctrl = CrashController::register(&vfs_name, dir.path().to_path_buf());
        let db = dir.path().join("log.db");

        // Acked baseline: 5 QSOs, each fully synced BEFORE arming.
        {
            let store = Store::open_with_vfs(&db, "k", Some(&vfs_name)).unwrap();
            for i in 0..5 {
                store
                    .upsert_qso(&common::sample_qso(&format!("acked-{i}"), 1000 + i as i64))
                    .unwrap();
            }

            // Arm power-off, then attempt one more upsert mid-commit.
            ctrl.arm_power_off_after(crash_after);
            let _ = store.upsert_qso(&common::sample_qso("inflight", 9999)); // not acked
        }

        if !ctrl.powered() {
            // Crash actually tripped — snapshot the frozen on-disk state and
            // recover it through the DEFAULT VFS.
            tripped = true;
            let snap = tempfile::tempdir().unwrap();
            ctrl.snapshot_into(snap.path()).unwrap();
            let store = Store::open(snap.path().join("log.db"), "k").unwrap();
            let integ = store.integrity_check().unwrap();
            assert_eq!(integ, "ok", "crash_after={crash_after}: integrity check failed");

            let rows = store
                .fetch_qsos(&QsoFilter::default(), cw_store::MAX_FETCH_LIMIT, 0)
                .unwrap();
            for i in 0..5 {
                let id = format!("acked-{i}");
                let row = rows
                    .iter()
                    .find(|q| q.id == id)
                    .unwrap_or_else(|| panic!("crash_after={crash_after}: lost acked {id}"));
                assert_eq!(
                    row.callsign, "W1AW",
                    "crash_after={crash_after}: {id} callsign corrupted"
                );
                assert_eq!(
                    row.qso_date,
                    1000 + i as i64,
                    "crash_after={crash_after}: {id} qso_date corrupted"
                );
                assert_eq!(
                    row.band.as_deref(),
                    Some("20m"),
                    "crash_after={crash_after}: {id} band corrupted"
                );
            }
        } else {
            // Workload finished before reaching the crash point — past the
            // I/O-op count of one commit. Stop scanning.
            break;
        }
    }
    assert!(tripped, "no power-loss crash ever tripped — test is vacuous");
}

/// Even when the crash garbles the in-flight write's sectors, acked rows stay
/// intact and the DB recovers to a consistent state (integrity = ok).
///
/// For each (seed, crash_after) pair we write 5 acked QSOs, then arm a
/// torn-page power-off and attempt one more upsert.  If the crash tripped we
/// snapshot the frozen image, reopen it through the default VFS, and assert
/// integrity + all 5 acked ids present.  The un-acked "inflight" row may or
/// may not be present — either is fine.
#[test]
fn torn_page_never_corrupts_acked_rows() {
    let mut tripped = false;

    for (seed, crash_after) in (0u64..50).map(|s| (s, 1 + s % 30)) {
        let name = format!("crashvfs-torn-{seed}");
        let dir = tempfile::tempdir().unwrap();
        let ctrl = CrashController::register(&name, dir.path().to_path_buf());
        let db = dir.path().join("log.db");
        {
            let store = Store::open_with_vfs(&db, "k", Some(&name)).unwrap();
            for i in 0..5 {
                store
                    .upsert_qso(&common::sample_qso(&format!("acked-{i}"), 1000 + i as i64))
                    .unwrap();
            }
            ctrl.arm_torn_power_off_after(crash_after, seed);
            let _ = store.upsert_qso(&common::sample_qso("inflight", 9999));
        }

        if !ctrl.powered() {
            tripped = true;
            let snap = tempfile::tempdir().unwrap();
            ctrl.snapshot_into(snap.path()).unwrap();
            let store = Store::open(snap.path().join("log.db"), "k")
                .unwrap_or_else(|e| panic!("seed={seed} crash_after={crash_after}: open failed: {e:?}"));
            assert_eq!(
                store.integrity_check().unwrap(),
                "ok",
                "seed={seed} crash_after={crash_after}"
            );
            let rows = store
                .fetch_qsos(&QsoFilter::default(), cw_store::MAX_FETCH_LIMIT, 0)
                .unwrap();
            for i in 0..5 {
                let id = format!("acked-{i}");
                let row = rows
                    .iter()
                    .find(|q| q.id == id)
                    .unwrap_or_else(|| panic!("seed={seed}: lost {id}"));
                assert_eq!(
                    row.callsign, "W1AW",
                    "seed={seed} crash_after={crash_after}: {id} callsign corrupted"
                );
                assert_eq!(
                    row.qso_date,
                    1000 + i as i64,
                    "seed={seed} crash_after={crash_after}: {id} qso_date corrupted"
                );
                assert_eq!(
                    row.band.as_deref(),
                    Some("20m"),
                    "seed={seed} crash_after={crash_after}: {id} band corrupted"
                );
            }
        }
    }

    assert!(tripped, "no torn crash ever tripped — test is vacuous");
}

/// A subprocess opens the real on-disk DB, upserts a QSO, prints an ACK, then
/// `abort()`s with no clean shutdown. The parent reopens and confirms the acked
/// row survived and the database is still integral.
#[test]
fn app_crash_after_ack_preserves_qso() {
    let dir = tempfile::tempdir().unwrap();
    let db = dir.path().join("log.db");
    let exe = env!("CARGO_BIN_EXE_durability_crasher");
    let out = std::process::Command::new(exe)
        .args([db.to_str().unwrap(), "k", "crashy"])
        .output()
        .unwrap();
    assert!(
        String::from_utf8_lossy(&out.stdout).contains("ACK crashy"),
        "no ack printed"
    );
    assert!(!out.status.success(), "process must abort abnormally");
    let store = Store::open(&db, "k").unwrap();
    assert_eq!(store.integrity_check().unwrap(), "ok");
    let rows = store.fetch_qsos(&QsoFilter::default(), 10, 0).unwrap();
    assert!(rows.iter().any(|q| q.id == "crashy"), "acked QSO lost across process abort");
}

/// 8 writer threads each open their own `Store` and upsert 100 distinct-id QSOs
/// (800 total) concurrently.  A concurrent reader repeatedly fetches rows.
/// Asserts: no data loss, no corruption, and the whole run completes in < 60 s.
///
/// Stores are opened sequentially in the main thread (avoiding concurrent-open
/// init contention during SQLCipher key verification and pragma writes), then
/// each pre-opened Store is moved into its thread for concurrent writes/reads.
#[test]
fn concurrent_writers_and_reader_no_loss_no_corruption() {
    use std::time::{Duration, Instant};
    let dir = tempfile::tempdir().unwrap();
    let db = dir.path().join("log.db");
    // Create schema first.
    Store::open(&db, "k").unwrap();

    // Open all writer stores sequentially; set extended busy timeout on each.
    let mut writer_stores: Vec<Store> = (0..8)
        .map(|_| {
            let store = Store::open(&db, "k").unwrap();
            store.set_busy_timeout(30_000).unwrap();
            store
        })
        .collect();

    // Open reader store sequentially.
    let reader_store = Store::open(&db, "k").unwrap();
    reader_store.set_busy_timeout(30_000).unwrap();

    let started = Instant::now();

    // Spawn writer threads — each takes ownership of its pre-opened Store.
    let writers: Vec<_> = writer_stores
        .drain(..)
        .enumerate()
        .map(|(t, store)| {
            std::thread::spawn(move || {
                for i in 0..100 {
                    store
                        .upsert_qso(&common::sample_qso(&format!("{t}-{i}"), 1000))
                        .unwrap();
                }
            })
        })
        .collect();

    // Concurrent reader must never observe corruption.
    let reader = std::thread::spawn(move || {
        for _ in 0..50 {
            let _ = reader_store.fetch_qsos(&QsoFilter::default(), 1000, 0).unwrap();
        }
    });

    for w in writers {
        w.join().unwrap();
    }
    reader.join().unwrap();

    assert!(
        started.elapsed() < Duration::from_secs(60),
        "concurrency test exceeded timeout"
    );
    let store = Store::open(&db, "k").unwrap();
    assert_eq!(store.integrity_check().unwrap(), "ok");
    assert_eq!(store.qso_count().unwrap(), 800);
}

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
        for i in 0..5 {
            store
                .upsert_qso(&common::sample_qso(&format!("acked-{i}"), 1000 + i as i64))
                .unwrap();
        }
        // Budget that allows the above but starves further growth.
        ctrl.set_full_after_bytes(ctrl.bytes_written());
        let mut hit_full = false;
        for i in 0..500 {
            match store.upsert_qso(&common::sample_qso(&format!("overflow-{i}"), 2000 + i as i64)) {
                Ok(_) => {}
                Err(cw_store::StoreError::Sqlite(rusqlite::Error::SqliteFailure(e, _)))
                    if e.code == rusqlite::ErrorCode::DiskFull =>
                {
                    hit_full = true;
                    break;
                }
                Err(e) => panic!("unexpected error (expected SQLITE_FULL): {e:?}"),
            }
        }
        assert!(hit_full, "expected an SQLITE_FULL error under starved disk");
    }
    let store = Store::open(&db, "k").unwrap();
    assert_eq!(store.integrity_check().unwrap(), "ok");
    let rows = store
        .fetch_qsos(&QsoFilter::default(), cw_store::MAX_FETCH_LIMIT, 0)
        .unwrap();
    for i in 0..5 {
        assert!(
            rows.iter().any(|q| q.id == format!("acked-{i}")),
            "lost acked-{i}"
        );
    }
}
