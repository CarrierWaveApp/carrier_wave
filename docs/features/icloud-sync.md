# iCloud Sync & Backup Architecture

Carrier Wave uses Apple's CKSyncEngine (iOS 17+) for bidirectional iCloud sync across
devices, plus a local backup system with iCloud Drive mirroring.

This document covers the sync approach, entity mapping, conflict resolution, dirty flag
protocol, and backup format. For service sync (QRZ, POTA, LoFi, etc.), see [sync.md](sync.md).

## Overview

```
┌─────────────────────────────────────────────────────┐
│                  CloudSyncService                    │
│  @MainActor, owns engine, publishes UI status        │
│  Singleton: CloudSyncService.shared                  │
├──────────────────────┬──────────────────────────────┤
│                      │                               │
│              CloudSyncEngine                         │
│  actor, CKSyncEngineDelegate                         │
│  Background ModelContext (autosave disabled)          │
│                      │                               │
│  ┌───────────────────┼───────────────────────┐       │
│  │ Inbound           │ Outbound              │       │
│  │ fetchedChanges →  │ collectDirty →         │       │
│  │ processRecord →   │ buildCKRecord →        │       │
│  │ merge/insert      │ schedule pending       │       │
│  └───────────────────┼───────────────────────┘       │
│                      │                               │
│              CKRecordMapper                          │
│  Pure functions: Model ↔ CKRecord                    │
│  via Sendable field structs                          │
└──────────────────────┴──────────────────────────────┘
```

## Synced Entity Types

| Entity | Record Type | Conflict Strategy | Notes |
|--------|-------------|-------------------|-------|
| QSO | `QSO` | Field-level merge | Newer modifiedAt wins per field; notes concatenated; confirmations use OR |
| ServicePresence | `ServicePresence` | Union merge | Upload status propagates forward (once present, stays present) |
| LoggingSession | `LoggingSession` | LWW with qsoCount max | Newer endedAt/startedAt wins; qsoCount always takes max of both |
| ActivationMetadata | `ActivationMetadata` | LWW | Synthetic UUID from parkReference + date |
| SessionSpot | `SessionSpot` | LWW (always accept remote) | Spots are immutable once recorded |
| ActivityLog | `ActivityLog` | Dirty-flag semantics | No modifiedAt field; if local has unsent changes, keep them; otherwise accept remote |

### Entities NOT synced (and why)

| Entity | Reason |
|--------|--------|
| SolarSnapshot | Ephemeral conditions data; already captured on LoggingSession/ActivationMetadata |
| ActivityItem | Server-backed via ActivityFeedSyncService; not user data |
| Challenge, Club, Friendship | Server-authoritative social data from activities-server |
| StationProfile | Stored locally; synced via iCloud KVS (SettingsSyncService) |
| WebSDRRecording | Large binary audio files; local-only |
| WebSDRFavorite | Future: claims iCloud sync but not yet implemented |
| CallsignNotesSource | Future: user-configured notes sources |

## Record Identity

CKRecord names are deterministic: `{EntityType}-{UUID}`.

```
QSO-A1B2C3D4-E5F6-7890-ABCD-EF1234567890
ServicePresence-11111111-2222-3333-4444-555555555555
```

ActivationMetadata uses a synthetic UUID derived from `parkReference + date` since
the model doesn't have a natural UUID primary key.

All records live in a single custom zone: `CarrierWaveData`.

## Dirty Flag Protocol

Every synced model has a `cloudDirtyFlag: Bool` property (default `false`).

### Setting the flag

Any local mutation that should propagate to other devices MUST set `cloudDirtyFlag = true`.
This includes:
- Creating a new record
- Editing fields
- Changing status (e.g., deactivating an ActivityLog)
- Hiding a QSO (soft delete)

### Clearing the flag

The flag is cleared ONLY after CKSyncEngine confirms the record was successfully sent:
`CloudSyncEngine+Helpers.swift: clearDirtyFlag(entityType:id:)`.

### Outbound flow

1. `CloudSyncEngine.collectDirtyRecordIDs()` fetches all records with `cloudDirtyFlag == true`
2. Each dirty record becomes a `CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID)`
3. `nextRecordZoneChangeBatch()` builds CKRecords from the pending list
4. On `sentRecordZoneChanges` success, `clearDirtyFlag` is called

### Inbound flow

1. `handleFetchedRecordZoneChanges` dispatches to per-type processors
2. Each processor fetches the local record by UUID
3. If found: merge using the type's conflict strategy
4. If not found: insert a new record
5. `upsertSyncMetadata` records the CKRecord system fields for future conflict resolution

### Safety constraints

- **Never set `cloudDirtyFlag = true` after accepting a server version.** This causes
  sync ping-pong: device A uploads → device B receives and re-marks dirty → device B
  uploads the same data → device A receives and re-marks dirty → infinite loop.
- **Metadata modes (`WEATHER`, `SOLAR`, `NOTE`) are never synced.** They are filtered
  out in `collectDirtyQSOChanges` and rejected in `processInboundQSO`.
- **Conflict resolution runs on the engine's background actor**, not `@MainActor`.
  All field access goes through Sendable field structs, never direct model references
  across actor boundaries.

## Conflict Resolution

### Field-level merge (QSO)

For each field, if the values differ, the version with the newer `modifiedAt` wins.
Special cases:
- `notes`: Concatenated with `\n---\n` separator if both sides changed, deduped by block
- `qrzConfirmed`, `lotwConfirmed`: OR (once confirmed, stays confirmed)
- `isHidden`: OR (delete wins — if either device hid it, it stays hidden)
- `rawADIF`: Never overwrite non-nil with nil
- `importedAt`: Takes the earliest (first import wins)

### Union merge (ServicePresence)

Upload status propagates forward:
- `isPresent`: OR (once present, stays present)
- `needsUpload`: AND (both must agree it needs upload)
- `uploadRejected`: OR (rejection is permanent)
- `isSubmitted`: OR (submission happened)
- `lastConfirmedAt`: Latest date wins

### LWW (LoggingSession, ActivationMetadata)

Compares CKRecord modification dates. Winner takes all fields, with one exception:
LoggingSession `qsoCount` always takes the maximum of both versions.

### Dirty-flag merge (ActivityLog)

ActivityLog has no `modifiedAt` field, so date-based LWW would always pick remote
(since `createdAt` is immutable). Instead:
- If local `cloudDirtyFlag == true` (has unsent changes): keep local, skip remote
- If local `cloudDirtyFlag == false` (in sync): accept remote version

### Always-accept-remote (SessionSpot)

Spots are immutable once recorded. On conflict, always take the server version.
Do NOT set `cloudDirtyFlag` after accepting — the local copy now matches the server.

## Sync Metadata

`CloudSyncMetadata` (SwiftData model) tracks per-record sync state:

| Field | Purpose |
|-------|---------|
| `entityType` | Record type string (e.g., "QSO") |
| `localId` | UUID of the local SwiftData record |
| `recordName` | CKRecord name for CloudKit identity |
| `encodedSystemFields` | Archived CKRecord system fields (change tags, etc.) |
| `lastSyncedAt` | Timestamp of last successful sync |

This metadata enables CKSyncEngine to detect conflicts (via change tags in the
encoded system fields) and resume from where it left off.

## Inbound Deletion Handling

When a record is deleted on another device:

| Entity | Behavior |
|--------|----------|
| QSO | Soft delete: sets `isHidden = true` (QSO data preserved) |
| ServicePresence | Hard delete from SwiftData |
| LoggingSession | Hides all session QSOs (`isHidden = true`, `cloudDirtyFlag = true`), then hard deletes session |
| ActivationMetadata | Deletes sync metadata only |
| SessionSpot | Hard delete from SwiftData |
| ActivityLog | Clears `activeActivityLogId` from UserDefaults if active, then hard deletes |

## Account Changes

| Event | Action |
|-------|--------|
| Sign in | Mark all records dirty, schedule pending changes |
| Sign out | Clear all sync metadata |
| Switch accounts | Clear all sync metadata, mark all records dirty, schedule pending |

## Backup System

### Format

`.cwbackup` is a directory bundle:

```
carrierwave_2026-02-20_143000.cwbackup/
  database.sqlite        # WAL-checkpointed SwiftData database
  SessionPhotos/          # Mirror of Documents/SessionPhotos/
    <sessionUUID>/
      <filename>.jpg
```

Legacy `.sqlite` backups (pre-bundle format) are still accepted for restore.

### Snapshot triggers

| Trigger | When |
|---------|------|
| `launch` | Every app launch |
| `preSync` | Before service sync |
| `preImport` | Before ADIF import |
| `manual` | User-initiated from Settings |
| `preRestore` | Safety snapshot before restoring a backup |

### Retention

- Local: 5 most recent snapshots
- iCloud Drive: 2 most recent, mirrored to `iCloud Drive/Documents/Backups/`

### Restore safety protocol

1. Create a `preRestore` safety backup
2. Validate the backup (SQLite integrity check)
3. Write a `pendingRestore.json` marker to Library/
4. On next app launch (before ModelContainer creation):
   - Read the marker
   - Replace the database file
   - Restore photos using copy-to-temp-then-move (atomic swap)
   - Clear the marker
   - Disable iCloud sync and set `restoredFromBackup` flag

### Photo restore safety

Photos use a copy-to-temp-then-move pattern to prevent data loss:

1. Copy bundle photos to `SessionPhotos_restoring` (temp directory)
2. If copy succeeds: remove existing `SessionPhotos`, move temp to final location
3. If copy fails: clean up temp, existing photos are preserved

This ensures existing photos are never deleted unless the replacement copy is complete.

### What's NOT in backups

| Data | Location | Recovery |
|------|----------|----------|
| Credentials (QRZ, POTA, LoFi tokens) | Keychain | Re-authenticate after restore |
| WebSDR recordings | Documents/WebSDRRecordings/ | Not backed up (large audio files) |
| iCloud sync metadata | SwiftData (CloudSyncMetadata) | Rebuilt on next sync |
| App settings | UserDefaults + iCloud KVS | Restored via SettingsSyncService |

## Related Documents

- [Service Sync](sync.md) — QRZ, POTA, LoFi, Club Log, LoTW sync
- [Architecture](../architecture.md) — Overall app architecture
- [Performance](../PERFORMANCE.md) — Performance rules including `@Query` ban
