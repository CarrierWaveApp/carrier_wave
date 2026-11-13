# Investigation: Complete QSO loss for AC9M (ex-KE9DQQ)

## Symptom
User reports complete loss of active QSOs from the SwiftData store.
Diagnostic bundle: `carrier-wave-diagnostics-2026-04-26-203149`.
- App version `1.83.0` build `2`, iOS 26.3.1, iPhone 17 (`iPhone18,3`)
- iCloud sync **Disabled**, all upload services not_configured
- `database.sqlite` (in bundle): every entity table has 0 rows
- `Z_PRIMARYKEY.Z_MAX = 0` for every entity → fresh-init store, not a delete-all
- `recent-qsos.json` empty, `upload-diagnostics.json` empty
- Backup manifest healthy: 94 snapshots, latest `carrierwave_2026-04-26_184159.cwbackup` with **qsoCount=1626**
- Safety ledger holds 114 QSOs from 2026-04-11 → 2026-04-26 18:49:48 EDT

## Timeline (all UTC; user is UTC-4 / EDT)

| UTC | EDT | Event |
|---|---|---|
| 2026-04-26 22:39 | 18:39 | POTA audit ran, profile=1526 QSOs, activations=1359 |
| 2026-04-26 22:41:59 | 18:41:59 | Last preSync backup taken: **qsoCount=1626** |
| 2026-04-26 22:49:48 | 18:49:48 | **Last QSO logged** (callsign N2EI, station AC9M) — appears in ledger |
| 2026-04-26 23:21:04 | 19:21:04 | Last sync-debug-log entry; app then idle/closed |
| 2026-04-27 00:31:14 | 20:31:14 | **Cold launch.** `ModelContainer.init` failed → store wiped |
| 2026-04-27 00:31:53 | 20:31:53 | User opened Send Diagnostics, ~39s into the broken launch |

## Root cause

`swift/ios/CarrierWave/CarrierWaveApp+ContainerSetup.swift:41-80`
(`ContainerSetup.createModelContainer`).

```swift
do {
    return try ModelContainer(for: schema, configurations: [configuration])
} catch {
    let storeURL = configuration.url
    logger.fault("ModelContainer init failed, will reset: \(error.localizedDescription)")

    emergencyBackup(storeURL: storeURL, logger: logger)   // copy to Library/EmergencyBackup/

    try? FileManager.default.removeItem(at: storeURL)
    try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
    try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))

    return try ModelContainer(for: schema, configurations: [configuration])
}
```

When the first `ModelContainer.init` throws on launch, the recovery path
**deletes `default.store`, `.wal`, `.shm`** and creates a fresh empty
container. The app then proceeds normally with an empty database.

Every observable matches:
- ✅ All `ZQSO`/`ZLOGGINGSESSION`/`Z*` tables have 0 rows
- ✅ `Z_PRIMARYKEY.Z_MAX = 0` for every entity (PK counters reset → fresh init)
- ✅ `Z_METADATA` UUID `754428F6-...` is a new identity
- ✅ Schema is present and complete (the fresh init created it from `Schema`)
- ✅ No `preRestore` snapshot in backup manifest (this code path bypasses BackupService)
- ✅ Wipe happened *during* a cold launch (last sync activity 23:21 UTC,
  next sync activity 00:31 UTC, no backup in between)

The catch path is silent to the user — no alert, no in-app log entry. The
only signal was a `logger.fault` to subsystem `com.carrierwave` /
category `ModelContainer`. By the time the diagnostic was collected
(39 seconds into the recovered launch), `OSLogStore(scope: .currentProcessIdentifier)`
could only see the new process's log — the prior process's fault entry
is unreachable.

## What the user can recover and how

**On-device, in this order:**

1. **Settings → Backups → Restore from `carrierwave_2026-04-26_184159.cwbackup`**
   → restores 1626 QSOs (everything through 18:42 EDT).

2. **Files app → On My iPhone → Carrier Wave → `EmergencyBackup/`**
   → there *should* be a `database-2026-04-27T00:31:14Z.sqlite`
   (and possibly `.wal`) saved by `emergencyBackup()` immediately
   before the wipe. **Ask the user to send this file** — it is the
   actual broken store and is the only artifact that can tell us *why*
   `ModelContainer.init` threw.

3. **Settings → Import → ADIF**, point at
   `Documents/QSOLedger/2026-04.adi`
   → covers the ~11 QSOs logged between 18:42 and 18:49 EDT that are
   in the ledger but not in the 18:42 backup. Dedupe on
   `callsign + timestamp` will collapse the overlap with the backup.

   The ledger file is reachable via Files app → On My iPhone →
   Carrier Wave → `QSOLedger/2026-04.adi`.

This recovers everything except QSOs older than 2026-04-11 that aren't
in `carrierwave_2026-04-26_184159.cwbackup` — and since that backup has
1626 QSOs (their full history), the recovery is complete.

## What we do not know yet

- **Why `ModelContainer.init` threw.** This is the actual bug. We have
  zero evidence about it because the fault log is gone. The
  EmergencyBackup file (if it exists on device) is the only path to
  finding out.
- **Whether `emergencyBackup()` actually succeeded.** It is `try?`-soft
  on the copy, and the iOS file-protection class on `Library/...` could
  fail the copy if the device was locked at launch. Worth confirming
  the file exists before assuming it does.

## Bugs to fix (separate PRs, not this one)

1. **Make `ContainerSetup.createModelContainer` louder.**
   - Persist the error to a file before wiping (e.g.
     `Library/ContainerInitFailure.json` with the error description,
     timestamp, app version, schema hash, and store stat info).
   - Surface a one-time alert on the next launch:
     "We had to recover your database. A copy of the broken file is
     in EmergencyBackup. Restore from your backup if needed."
   - Refuse to recover silently if the broken store has > N rows or
     was last modified < N minutes ago — present a recovery UI instead.
2. **`OSLogStore(scope: .currentProcessIdentifier)` is wrong for this
   class of bug.** `DiagnosticsCollector.collectOSLog` should also try
   `.system` scope (or fall back to it) so we can see the prior
   process's fault logs when the user reports issues that just happened.
3. **Bundle `Library/EmergencyBackup/` in the diagnostic zip.** Right
   now it lives only on the device and the user has to find it via the
   Files app. It is the most important artifact for any data-loss case.
4. **Bundle the most recent N entries of `Library/Backups/manifest`
   *plus a count of available `.cwbackup` files*** so we know whether
   the user can self-recover before asking them to.
5. **Suspect: equipment-system migration.** `EquipmentMigrationSheet`
   appears in the SwiftUI scene tree of the recovered launch. The
   project memory notes equipment-system migration is incomplete (old
   KVS pickers + new SwiftData/server catalog). Check whether the
   equipment migration code does any work in `ModelConfiguration`
   creation or in a `MigrationStage` that could fail-init the container.

## Asks back to user

1. Open Files app → On My iPhone → Carrier Wave → `EmergencyBackup/` →
   AirDrop or email any `database-*.sqlite` (and `.wal`) files there.
   These are the broken stores — without them we can't fix the underlying
   bug.
2. Open in-app Backups settings → restore the 18:41 EDT (`184159`)
   backup. Confirm it brings back ~1626 QSOs.
3. Then import `Documents/QSOLedger/2026-04.adi` to backfill the ~11
   QSOs logged after that backup.
4. Note whether the device was locked when the app crashed/launched
   (file-protection-related migration failures only manifest in this
   state).
