# iCloud Sync & Backup Architecture

Carrier Wave uses Apple's `CKSyncEngine` (iOS 17+) for bidirectional iCloud
sync between Carrier Wave (iOS) and CW Sweep (macOS), via a journal-based
record format and a SQLite snapshot tier for fast device bootstrap. A local
backup system mirrors recent snapshots to iCloud Drive separately.

For service sync (QRZ, POTA, LoFi, etc.) see [sync.md](sync.md).

## Overview

```
┌──────────────────────────────────────────────────────────────┐
│              CloudSyncService  (iOS + macOS)                  │
│  @MainActor, owns the journal engine, publishes UI status     │
│  Singleton: CloudSyncService.shared                           │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│              CloudSyncJournalEngine                           │
│  actor, CKSyncEngineDelegate                                  │
│  Background ModelContext (autosave disabled)                   │
│                                                               │
│  ┌────────────────────────────┬────────────────────────────┐  │
│  │ Snapshot tier              │ Journal tier                │  │
│  │ CKAsset of full SQLite DB  │ ChangeJournal CKRecords     │  │
│  │ (bootstrap + every 6 h)    │ batched JSON ops, 100/entry │  │
│  └────────────────────────────┴────────────────────────────┘  │
│                                                               │
│  CloudSyncSnapshotService — upload/download via CKAsset       │
│  CloudSyncConflictResolver — pure field-level merge logic      │
│  CloudSyncEventLog — JSON activity log surfaced in Settings    │
└───────────────────────────────────────────────────────────────┘
```

The previous per-record engine (one CKRecord per QSO) was removed entirely;
journal sync is the only path. Existing CKRecords from the legacy engine
remain in users' CloudKit zones but are invisible to the journal engine.

## Synced Entity Types

| Entity | Conflict Strategy | Notes |
|--------|-------------------|-------|
| QSO | Field-level merge | Newer `modifiedAt` wins per field; `notes` concatenate; `qrzConfirmed`/`lotwConfirmed` OR; `isHidden` OR (delete wins); metadata modes (`WEATHER`, `SOLAR`, `NOTE`) never sync |
| ServicePresence | Union merge | Once `isPresent`, stays present; `isSubmitted` and `uploadRejected` are sticky |
| LoggingSession | LWW with `qsoCount` max | Newer `endedAt`/`startedAt` wins; `qsoCount` always max of both |
| ActivationMetadata | LWW | Synthetic UUID from `parkReference + date` |
| SessionSpot | Always-accept-remote | Spots are immutable once recorded |
| ActivityLog | Dirty-flag merge | If local `cloudDirtyFlag == true` keep local, else accept remote |

### Entities NOT synced (and why)

| Entity | Reason |
|--------|--------|
| SolarSnapshot | Ephemeral; already captured on session/activation |
| ActivityItem, Challenge, Club, Friendship | Server-authoritative (activities-server) |
| StationProfile | Synced via iCloud KVS (`SettingsSyncService`) |
| WebSDRRecording | Large binary audio files; local-only |
| WebSDRFavorite | Future (not yet implemented) |
| CallsignNotesSource | Config synced via iCloud KVS; transient state device-local |

## Dirty Flag Protocol

Every synced model has a `cloudDirtyFlag: Bool` (default `false`).

### Setting

Any local mutation that should propagate MUST set `cloudDirtyFlag = true`:
create, edit, status change, soft-delete (`isHidden = true`).

### Clearing

Cleared only after the engine confirms the record's journal entry was saved.
`CloudSyncJournalEngine+Outbound.clearDirtyFlagsForJournal(_:)` walks the
sent payload's operations, but skips clearing if the local row's
`modifiedAt` advanced past the snapshot taken when the journal was built —
that means the user edited between snapshot and confirmation, and the next
outbound run must re-pick up the new edit (CAR-245).

### Outbound flow

1. `collectDirtyOperations()` fetches all dirty records (batched per swift/CLAUDE.md performance rules)
2. Each record becomes a `JournalOperation` (insert/update keyed by entity type + UUID)
3. Operations are bundled 100-per-`ChangeJournal` CKRecord (`JournalPayload.maxOperationsPerEntry`)
4. CKRecords are queued via `CKSyncEngine.state.add(pendingRecordZoneChanges:)`
5. On `sentRecordZoneChanges`, dirty flags clear (with the CAR-245 guard above)

### Inbound flow

1. `handleFetchedRecordZoneChanges` decodes each `ChangeJournal` payload
2. Per-operation: fetch existing local row by UUID
3. If found: merge using the type's strategy via `CloudSyncConflictResolver`
4. If not found: build new model via `CloudSyncModelFactories`
5. `isApplyingInbound` flag prevents the `ModelContext.didSave` observer from immediately re-scheduling outbound (the inbound→outbound echo loop, CAR-244)

### Bootstrap

On a new device's first journal-engine run, before fetching journals:
1. If the local DB has zero QSOs, attempt to download the latest snapshot CKAsset
2. Validate it (`SnapshotValidator`)
3. Replace the local store, then fetch journal-tail changes since the snapshot's timestamp

### Safety constraints

- **Never set `cloudDirtyFlag = true` after accepting a server version** — that causes ping-pong between devices
- **Metadata modes** (`WEATHER`, `SOLAR`, `NOTE`) are filtered in `collectDirtyQSOs` and rejected in inbound apply
- **All field access goes through `Sendable` field structs** so the actor boundary stays clean

## Cross-Device Sync Triggers

`CloudSyncService` uses multiple triggers so changes on Device A appear on Device B within seconds:

| Trigger | When | Mechanism |
|---------|------|-----------|
| App launch | Engine starts | `CKSyncEngine.fetchChanges()` on initial start |
| Local change | 500ms after save | `ModelContext.didSave` → `schedulePendingChanges()` |
| Push notification | Remote change | `AppDelegate.didReceiveRemoteNotification` → `handleRemoteNotification()` → `fetchChanges()` |
| Foreground re-entry (iOS) | App becomes active | `scenePhase == .active` → `fetchChangesFromCloud()` |
| Foreground re-entry (macOS) | App becomes active | `NSApplication.didBecomeActiveNotification` → `fetchChangesFromCloud()` |
| Network recovery | Connectivity restored | `NWPathMonitor` detects path → `fetchChangesFromCloud()` |
| Active session poll (iOS) | Every 30s during a session | `KVO` observation of `activeLoggingSessionId` |
| Manual | User taps "Sync Now" / "Force Full Sync" | `syncPending()` / `forceFullSync()` |

## Account Changes

| Event | Action |
|-------|--------|
| Sign in / switch | Schedule pending changes; the engine re-uploads on next outbound run |
| Sign out | Engine stops; local data preserved |

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

Legacy `.sqlite` backups (pre-bundle format) still restore.

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
3. Write a `pendingRestore.json` marker to `Library/`
4. On next app launch (before `ModelContainer` creation):
   - Read the marker
   - Replace the database file
   - Restore photos via copy-to-temp-then-move (atomic swap)
   - Clear the marker
   - Disable iCloud sync and set `restoredFromBackup` flag

### Photo restore safety

Photos use a copy-to-temp-then-move pattern so existing photos are never deleted unless the replacement copy is complete.

### What's NOT in backups

| Data | Location | Recovery |
|------|----------|----------|
| Credentials (QRZ, POTA, LoFi tokens) | Keychain | Re-authenticate after restore |
| WebSDR recordings | `Documents/WebSDRRecordings/` | Not backed up (large audio files) |
| App settings | UserDefaults + iCloud KVS | Restored via `SettingsSyncService` |

## Key Files

| File | Purpose |
|------|---------|
| `CloudSyncJournalEngine.swift` | Main `CKSyncEngine` actor |
| `CloudSyncJournalEngine+Outbound.swift` | Dirty record collection → journal entries |
| `CloudSyncJournalEngine+Inbound.swift` | Journal application + snapshot bootstrap |
| `CloudSyncJournalEngine+Fields.swift` | Field extract / apply for journal engine |
| `CloudSyncJournalEngine+MarkAllDirty.swift` | Batched force-full-sync helper |
| `CloudSyncJournalEntry.swift` | `JournalPayload` + `JournalOperation` types and CKRecord coding |
| `CloudSyncModelFactories.swift` | Build new models from inbound field structs |
| `CloudSyncConflictResolver.swift` | Pure field-level merge logic |
| `CloudSyncSnapshotService.swift` | SQLite snapshot upload/download via `CKAsset` |
| `SnapshotValidator.swift` | Validate downloaded snapshots before swap-in |
| `CloudSyncZone.swift` | Shared `CKRecordZone.ID` constant |
| `CloudSyncEvent.swift` / `CloudSyncEventLog.swift` | Activity-log events |
| `CloudSyncSummary.swift` | Aggregated event-log summary |
| `CloudSyncRecordCounts.swift` | Snapshot of per-table dirty counts |
| `swift/ios/.../CloudSync/CloudSyncService.swift` | iOS `@MainActor` wrapper |
| `swift/macos/.../CloudSync/CloudSyncService.swift` | macOS `@MainActor` wrapper |

## Related Documents

- [Service Sync](sync.md) — QRZ, POTA, LoFi, Club Log, LoTW sync
- [Architecture](../architecture.md) — Overall app architecture
- [Performance](../PERFORMANCE.md) — Performance rules including `@Query` ban
- [SQLite Sync Investigation](../investigations/2026-04-02-sqlite-dump-sync.md) — Original journal design exploration
