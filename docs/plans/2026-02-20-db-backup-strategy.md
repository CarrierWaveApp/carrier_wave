# Database Backup Strategy

## Problem

No automated backups exist. A data loss event has no recovery path beyond re-downloading from cloud services (QRZ, POTA, LoFi), which loses local-only data like logging sessions, activation metadata, equipment, challenge participation, and hidden QSOs.

## Current State

| What exists | Details |
|---|---|
| **SwiftData store** | Single SQLite file + WAL/SHM at the default `ModelConfiguration` path |
| **DatabaseExporter** | `SettingsHelperTypes.swift` — copies `.sqlite` + `.wal` + `.shm` to temp dir for share sheet. Manual, one-shot, no scheduling |
| **CKSyncEngine** | `CloudSyncService` syncs QSO, ServicePresence, LoggingSession, ActivationMetadata to iCloud via CloudKit. Not a backup — it propagates deletes and corruption too |
| **iCloud device backup** | iOS includes the app's data container in whole-device iCloud backups, but the user has no control over granularity or retention |
| **ADIF export** | Per-activation and full-log ADIF export exist, but ADIF doesn't capture sessions, metadata, sync state, etc. |

## Proposed Design

Three complementary layers, each protecting against different failure modes:

### Layer 1: On-Device Rolling Snapshots

**What:** Periodic SQLite copies stored in the app's `Library/Backups/` directory.

**When:**
- **App launch** — snapshot before any sync/import runs (protects against sync corruption)
- **Pre-sync** — snapshot before each full sync cycle starts
- **Pre-import** — snapshot before external ADIF file import
- **Manual** — user taps "Back Up Now" in Settings

**How:**
1. Flush WAL with `PRAGMA wal_checkpoint(TRUNCATE)` via a raw SQLite connection (SwiftData doesn't expose this, so use `sqlite3_open` on the store URL directly)
2. Copy the `.sqlite` file (WAL is empty after checkpoint) to `Library/Backups/carrierwave_YYYY-MM-dd_HHmmss.sqlite`
3. Store a `backups.json` manifest alongside with metadata: `{timestamp, trigger, qsoCount, sizeBytes, appVersion}`

**Retention:**
- Keep the **5 most recent** snapshots (configurable)
- Always keep the **most recent snapshot per trigger type** (so you always have at least one pre-sync, one pre-import, one launch backup even if the other slots are filled by manual backups)
- Prune after each new snapshot

**Size estimate:** A 10k QSO database is ~5-10 MB. Five copies = 25-50 MB. Acceptable for on-device storage.

### Layer 2: iCloud Drive Backup Export

**What:** Copy snapshots to the app's iCloud Drive container (`Documents/Backups/`) so they survive device loss/replacement.

**When:**
- After each on-device snapshot, if iCloud Drive is available
- Only the **2 most recent** snapshots are synced to iCloud Drive (to conserve iCloud quota)

**How:**
1. After a local snapshot is written, copy it to the ubiquity container `Documents/Backups/`
2. Prune remote backups beyond the retention limit
3. Use `NSFileCoordinator` for safe iCloud Drive writes

**Why not just rely on CKSyncEngine?**
CKSyncEngine syncs individual records — it propagates deletes and corruption. A SQLite snapshot is a point-in-time freeze that can restore even if CloudKit data is damaged.

### Layer 3: Restore Mechanism

**What:** Ability to browse and restore from any available backup (local or iCloud Drive).

**UI location:** Settings > Data & Tools > Backups

**Restore flow (every step requires explicit user interaction):**
1. Show list of available backups with metadata (date, trigger, QSO count, size)
2. User selects a backup → show a **confirmation alert** explaining:
   - What will happen ("Replace your current database with the backup from [date]")
   - That a safety backup of the current state will be created first
   - That the app **must restart** to complete the restore
   - A destructive-style "Restore" button and a "Cancel" button
3. On confirm: **pre-restore safety snapshot** — create a backup of the current state tagged `.preRestore`
4. Validate the backup file: open with `sqlite3_open`, run `PRAGMA integrity_check`, verify the schema version matches (or is migratable). If validation fails, show an error alert and abort — no store changes made.
5. Stage the restore:
   - Write a `pendingRestore.json` marker file with the backup path
   - Show a **"Restart Required"** screen explaining the app needs to restart, with a single "Restart Now" button (no automatic `exit(0)`)
   - The user taps "Restart Now" to trigger `exit(0)`
6. On next launch, `CarrierWaveApp` checks for `pendingRestore.json`:
   - If present, swap the `.sqlite` file **before** creating the `ModelContainer`
   - Remove the marker file
   - Show a **post-restore banner/alert**: "Database restored from backup ([date]). iCloud sync has been paused — review your data before re-enabling."
7. **iCloud sync is paused after restore** — the user must explicitly re-enable it from Settings. This prevents CloudKit from silently re-applying the changes that led to the data loss. The post-restore alert links directly to the iCloud sync settings.

**No automatic merges or reconciliation.** After a restore, the user is in full control of when (and whether) to reconnect cloud sync.

**Edge cases:**
- If the backup is from an older schema version, SwiftData lightweight migration handles it (same as fresh app update)
- If integrity check fails, show an error alert and abort — the user's current database is untouched
- If the app crashes before the user taps "Restart Now", `pendingRestore.json` is still on disk and the restore completes on next launch (the user already confirmed)
- If the marker file is present but the backup file is missing/corrupt, clear the marker and show an error on launch

## Backup Service Architecture

```
BackupService (actor)
├── snapshot(trigger:) → BackupEntry     // Create snapshot
├── availableBackups() → [BackupEntry]   // List local + iCloud
├── restore(entry:) async throws         // Restore from backup
├── pruneLocal()                          // Enforce retention
└── syncToICloud()                        // Push latest to iCloud Drive

BackupEntry (Sendable struct)
├── id: UUID
├── timestamp: Date
├── trigger: BackupTrigger (.launch, .preSync, .preImport, .manual)
├── qsoCount: Int
├── sizeBytes: Int64
├── appVersion: String
├── location: BackupLocation (.local, .icloud)
└── filePath: String
```

## Settings UI

Under **Settings > Data & Tools**, add a **Backups** section:

```
┌─────────────────────────────────────┐
│ Backups                             │
├─────────────────────────────────────┤
│ Back Up Now                     [→] │
│ Last backup: 2 hours ago            │
│                                     │
│ Auto-backup                      ON │
│ Keep backups                  5 max │
│ iCloud backup                    ON │
│                                     │
│ Restore from Backup...          [→] │
│   Lists all available backups       │
│   with date, size, trigger          │
└─────────────────────────────────────┘

Tapping "Restore from Backup..." → backup list → tap a backup →

┌─────────────────────────────────────┐
│ ⚠️ Restore Database?               │
│                                     │
│ This will replace your current      │
│ database with the backup from       │
│ Feb 18, 2026 at 3:42 PM.           │
│                                     │
│ A safety backup of your current     │
│ data will be created first.         │
│                                     │
│ The app must restart to complete    │
│ the restore. iCloud sync will be    │
│ paused until you re-enable it.      │
│                                     │
│        [ Cancel ]  [ Restore ]      │
└─────────────────────────────────────┘

After confirming → validation → staging →

┌─────────────────────────────────────┐
│ Restart Required                    │
│                                     │
│ Your database restore is ready.     │
│ Tap below to restart the app and    │
│ complete the restore.               │
│                                     │
│        [ Restart Now ]              │
└─────────────────────────────────────┘
```

## Testing Strategy

### Unit Tests

| Test | What it verifies |
|---|---|
| **Snapshot creation** | File exists at expected path, manifest updated, WAL checkpointed |
| **Retention pruning** | Correct files deleted when over limit, trigger-type preservation works |
| **Manifest round-trip** | Encode/decode `BackupEntry` JSON |
| **Integrity validation** | Rejects corrupt files, accepts valid ones |

### Integration Tests

| Test | What it verifies |
|---|---|
| **Snapshot → restore round-trip** | Insert QSOs, snapshot, delete QSOs, restore, verify QSOs are back |
| **Schema migration on restore** | Backup from older schema version restores successfully |
| **Pre-restore safety backup** | Restoring creates a safety snapshot first |

### Manual Test Checklist

- [ ] Create backup, verify it appears in the list
- [ ] Delete some QSOs, restore from backup, verify they return
- [ ] Force-quit during restore — app recovers on next launch
- [ ] Backup with iCloud enabled — verify file appears in iCloud Drive
- [ ] Restore on a new device from iCloud Drive backup
- [ ] Backup size is reasonable (not growing unbounded)

## Retention Policy Summary

| Location | Retention | Rationale |
|---|---|---|
| On-device | 5 most recent (configurable) | Covers ~1 week of daily use; ~50 MB max |
| iCloud Drive | 2 most recent | Conserves iCloud quota; protects against device loss |
| Pre-restore safety | Always kept (counts toward on-device limit) | Undo a bad restore |

## Integration Points

| Trigger site | When to call `BackupService.snapshot()` |
|---|---|
| `CarrierWaveApp.body.task` | `.launch` — on app startup, before sync starts |
| `SyncService.sync()` | `.preSync` — at the top of the main sync method |
| `ImportService.importADIF()` | `.preImport` — before processing the file |
| Settings UI button | `.manual` — user-initiated |

## Implementation Order

1. `BackupService` actor with snapshot + manifest + pruning (no iCloud yet)
2. Hook into app launch and sync triggers
3. Settings UI: backup list, manual backup, restore
4. Restore mechanism with integrity validation
5. iCloud Drive sync layer
6. Unit + integration tests

## Resolved Decisions

1. **App restart on restore:** User-initiated `exit(0)`. The restore is staged via a marker file, and the user explicitly taps "Restart Now". No silent restarts. If the app crashes or is force-quit before the tap, the marker file persists and the restore completes on next launch (which is safe — the user already confirmed).
2. **CloudKit reconciliation after restore:** Cloud sync is **paused after restore**. The user must explicitly re-enable it from Settings. This prevents CloudKit from silently re-applying deletes or corruption. A post-restore alert explains this and links to the sync settings.

## Open Questions

1. **Backup encryption:** The SQLite file contains callsigns and grid squares (PII-adjacent). Should backups in iCloud Drive be encrypted? iCloud Drive is already encrypted at rest, so this may be unnecessary complexity.
