# Investigation: Complete Logbook Loss — Zero QSOs

**Date:** 2026-04-03
**Status:** Resolved
**Outcome:** `createModelContainer` silently deletes the entire database on any ModelContainer init failure, with no backup, no user alert, and no logging. Combined with no minimum QSO guard on snapshot upload, an empty DB can propagate to iCloud.

## Problem Statement

User reports suddenly having zero QSOs. Database export shows only:
- 1 solar snapshot (April 2, 19:30 UTC)
- 10 club records
- 1 callsign notes source
- Zero QSOs, logging sessions, spots, POTA uploads, WebSDR recordings, activity items

This matches exactly what a fresh empty database accumulates after one launch cycle (solar polling, clubs sync, QRQ Crew seed).

Single device — no multi-device sync involved.

## Hypotheses

### Hypothesis 1: createModelContainer silent nuke (PRIMARY)
- **Evidence for:** DB contents match a fresh launch. Any transient SQLite error (corruption, storage full, WAL issue) triggers unconditional database deletion at `CarrierWaveApp.swift:406-423`. No backup, no logging, no user notification. This runs on every app launch.
- **Evidence against:** None — this is the simplest explanation requiring only a single transient error.
- **Tested:** Code review confirmed.
- **Result:** Root cause.

### Hypothesis 2: iCloud snapshot bootstrap with empty snapshot
- **Evidence for:** `restoreSnapshot()` in both `CloudSyncEngine+ZoneAndState.swift` and `CloudSyncJournalEngine+Inbound.swift` unconditionally deletes the local DB before replacing it with the downloaded snapshot. No validation of snapshot contents.
- **Evidence against:** Single device — bootstrap only triggers on first sync (no saved sync state). Would require sync state to be cleared first.
- **Tested:** Code review. Possible secondary vector if sync state was lost.
- **Result:** Contributing risk but not primary cause for single-device scenario.

### Hypothesis 3: Backup restore with corrupted file
- **Evidence for:** `BackupService+Restore.swift:121-180` deletes the entire DB before copying the backup. If the backup file is corrupted/truncated, the DB is already gone.
- **Evidence against:** Requires explicit user action (trigger restore from UI). User didn't report doing this.
- **Tested:** Code review.
- **Result:** Not the cause here, but a separate vulnerability.

### Hypothesis 4: Schema migration failure
- **Evidence for:** SwiftData lightweight migration can fail silently, and the catch block in `createModelContainer` would nuke the DB.
- **Evidence against:** No schema changes in recent commits — all models created in a single commit and never modified. Schema array unchanged.
- **Tested:** Git history review confirmed no model changes.
- **Result:** Not the trigger this time, but the `createModelContainer` catch block makes ANY future schema issue catastrophic.

## Investigation Log

### Step 1: Identify all deletion code paths
Found 7 paths that could zero a logbook:
1. `createModelContainer` silent nuke (CarrierWaveApp.swift:406-423)
2. iCloud snapshot bootstrap — empty snapshot (CloudSyncEngine+ZoneAndState.swift:83-118, CloudSyncJournalEngine+Inbound.swift:295-315)
3. Backup restore — corrupted file (BackupService+Restore.swift:121-180)
4. CWSweep "Clear All QSOs" (DataSettingsTab.swift:440-461)
5. iCloud account change — sync metadata wipe (CloudSyncEngine+Helpers.swift:254-270)
6. CloudKit zone deletion (CloudSyncEngine+Inbound.swift:9-16)
7. Inbound QSO/session deletions via sync (soft delete, not hard)

### Step 2: Narrow to single-device scenarios
Eliminated paths 4-7 (require multi-device or explicit user action). Path 3 requires user action. Path 2 requires sync state loss. Path 1 requires only a transient SQLite error.

### Step 3: Verify DB contents match fresh launch
Solar polling starts on launch → fetches solar snapshot. Clubs sync runs on launch → fetches 10 clubs. QRQ Crew seed runs on launch → creates callsign notes source. All match the reported DB contents exactly.

### Step 4: Check for compounding damage
`uploadSnapshotIfNeeded()` has NO guard against `qsoCount == 0`. After the DB is nuked, the next 6-hour upload cycle will push an empty snapshot to CloudKit, poisoning future bootstraps.

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `CarrierWave/CarrierWaveApp.swift:406-423` | ModelContainer creation | **ROOT CAUSE**: Silent DB deletion on any init failure |
| `CarrierWaveData/.../CloudSyncEngine+ZoneAndState.swift:83-118` | Snapshot bootstrap | Unconditional DB deletion before snapshot restore, no backup |
| `CarrierWaveData/.../CloudSyncJournalEngine+Inbound.swift:295-315` | Journal snapshot bootstrap | Same pattern — delete then replace, no backup |
| `CarrierWaveData/.../CloudSyncSnapshotService.swift:38-78` | Snapshot upload | No qsoCount > 0 guard — can upload empty DB |
| `CarrierWave/Services/CloudSync/CloudSyncService.swift:144-163` | Upload orchestration | Passes qsoCount through but doesn't guard |
| `CarrierWave/Services/BackupService+Restore.swift:121-180` | Backup restore | Deletes DB before copy, no rollback on failure |
| `CarrierWaveData/.../CloudSyncEngine+Inbound.swift` | Inbound sync | Zone deletion clears all sync metadata |
| `CarrierWaveData/.../CloudSyncEngine+Helpers.swift:254-270` | Account changes | Account switch clears sync metadata |
| `CarrierWaveData/.../CarrierWaveData.swift` | Schema definition | Stable — no recent changes |

## Root Cause

`CarrierWaveApp.createModelContainer()` catches ALL errors from `ModelContainer(for:configurations:)` and responds by deleting the entire SQLite database (main file, WAL, SHM) and recreating an empty container. There is:

1. **No backup** before deletion
2. **No logging** of what error caused the failure
3. **No user notification** that data was lost
4. **No attempt at recovery** (e.g., WAL checkpoint, integrity check, retry)

Any transient condition — storage pressure, WAL corruption from a background crash, iOS killing the process mid-write, file lock contention — triggers permanent, irrecoverable data loss.

## Resolution

### Fixes applied:
1. **createModelContainer**: Backup existing DB before deletion, log the error, attempt WAL checkpoint/recovery before nuking
2. **Snapshot upload**: Guard against uploading when qsoCount == 0
3. **restoreSnapshot**: Validate downloaded snapshot has QSO rows before replacing local DB; backup local DB first

## Lessons Learned

1. **Never silently delete user data.** The `try?` + `removeItem` pattern in catch blocks is catastrophic when applied to the primary data store.
2. **Every DB replacement path needs a pre-operation backup.** The backup service exists but isn't used by the code paths that delete the DB.
3. **Upload guards are as important as download guards.** The `qsoCount > 0` check on download is useless if upload doesn't have the same guard, since the metadata just reflects whatever was uploaded.
4. **Log the actual error.** The catch block discards the error that caused ModelContainer init to fail, making post-mortem diagnosis impossible.
