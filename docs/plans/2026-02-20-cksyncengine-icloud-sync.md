# CKSyncEngine iCloud Sync

## Problem

Carrier Wave stores all QSO data locally in SwiftData. Users with multiple devices (iPhone + iPad) have no way to access the same log on both. The existing iCloud infrastructure is limited to:

- **iCloud KVS** (`SettingsSyncService`) — syncs user preferences
- **iCloud Drive** (`ICloudMonitor`) — watches for manually-dropped ADIF files
- **WebSDR Favorites** — synced via iCloud KVS

None of these sync the core data: QSOs, sessions, or service upload status.

## Approach: CKSyncEngine (iOS 17+)

`CKSyncEngine` (introduced iOS 17) is Apple's recommended replacement for custom CloudKit sync. It handles:

- **Scheduling** — batches changes, respects system throttling
- **Push notifications** — wakes the app on remote changes
- **State serialization** — persists sync tokens between launches
- **Error recovery** — retries transient failures, surfaces permanent errors

We implement `CKSyncEngineDelegate` and provide the mapping between SwiftData models and `CKRecord`s. The engine handles everything else.

### Why not NSPersistentCloudKitContainer?

SwiftData's built-in CloudKit sync (`cloudKitDatabase:` on `ModelConfiguration`) uses `NSPersistentCloudKitContainer` under the hood. While simpler to adopt, it has well-documented issues:

- **No conflict resolution control** — last-writer-wins at the record level, no field-level merge
- **No visibility into sync state** — no API to show "syncing...", pending count, or errors
- **Opaque deduplication** — can't integrate with our existing `deduplicationKey` logic
- **Relationship bugs** — known issues with SwiftData relationships and CloudKit mirroring
- **No selective sync** — all-or-nothing, can't exclude metadata pseudo-modes

CKSyncEngine gives us full control over all of these.

## What Syncs

### Synced models

| Model | Record Type | Notes |
|-------|-------------|-------|
| **QSO** | `QSO` | Core contact data. ~30 fields. Excludes metadata pseudo-modes (WEATHER, SOLAR, NOTE). |
| **ServicePresence** | `ServicePresence` | Upload status per service per QSO. Parent reference to QSO record. |
| **LoggingSession** | `LoggingSession` | Session metadata, equipment, conditions. Linked to QSOs via `loggingSessionId` UUID. |
| **ActivationMetadata** | `ActivationMetadata` | Per-activation solar/weather conditions. Keyed by park+date. |

### Not synced

| Model | Reason |
|-------|--------|
| SolarSnapshot | Ephemeral polling cache, regenerated hourly |
| SessionSpot | Ephemeral spot data from a specific session |
| ActiveStation | Transient spot data |
| POTAJob, POTAUploadAttempt | Transient upload tracking, device-specific workflow |
| LeaderboardCache | Server-owned cache |
| ChallengeDefinition/Participation/Source | Server-owned, synced via Activities API |
| Club, Friendship, ActivityItem | Server-owned social data |
| DismissedSuggestion | Local UI state |
| TourState | Local UI state (UserDefaults) |
| WebSDRRecording | Large binary files, device-local |
| WebSDRFavorite | Already syncs via iCloud KVS |
| CallsignNotesSource | Could sync later; low priority since URLs are manually entered |
| ActivityLog | Could sync later; current usage is single-device focused |
| UploadDestination | Per-device service configuration |

### Metadata pseudo-modes

QSOs with mode in `{WEATHER, SOLAR, NOTE}` are **never synced** — consistent with the existing rule that these are never uploaded, counted, or displayed on map. The sync layer checks the same `metadataModes` set used by `ImportService`, `SyncService+Upload`, `QSOStatistics`, etc.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  SwiftData Models (QSO, LoggingSession, etc.)       │
└──────────────────┬──────────────────────────────────┘
                   │ dirty flag + notification
                   ▼
┌─────────────────────────────────────────────────────┐
│  CloudSyncService (@MainActor)                      │
│  - Observes local changes via Notification          │
│  - Exposes sync status to UI                        │
│  - Owns the CKSyncEngine instance                   │
└──────────────────┬──────────────────────────────────┘
                   │ delegates to
                   ▼
┌─────────────────────────────────────────────────────┐
│  CloudSyncEngine (actor)                            │
│  - CKSyncEngineDelegate implementation              │
│  - CKRecord ↔ SwiftData mapping                     │
│  - Conflict resolution                              │
│  - Background ModelContext for bulk operations       │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  CKSyncEngine (Apple framework)                     │
│  - Scheduling, batching, push notifications         │
│  - State persistence (sync tokens)                  │
│  - Network retry, error classification              │
└─────────────────────────────────────────────────────┘
```

### Key types

| Type | Role |
|------|------|
| `CloudSyncService` | `@MainActor` service. Owns the `CKSyncEngine`. Publishes sync status for UI. Listens for local data changes and feeds pending record IDs to the engine. |
| `CloudSyncEngine` | `actor` implementing `CKSyncEngineDelegate`. Does the heavy lifting: record mapping, conflict resolution, deduplication. Uses a background `ModelContext` per the performance rules. |
| `CloudSyncMetadata` | SwiftData model storing per-record sync state: `entityType`, `localId` (UUID), `recordName`, `encodedSystemFields` (serialized CKRecord metadata for change tags). |
| `CKRecordMapper` | Pure functions for `QSO → CKRecord` and `CKRecord → QSO` (and same for other models). Testable in isolation. |

### Record identity

Each synced model already has a `var id: UUID`. The CKRecord name is derived as `"<EntityType>-<UUID>"` (e.g. `"QSO-A1B2C3D4-..."`). This is deterministic — the same QSO always maps to the same CKRecord ID, which is essential for deduplication across devices.

### Zone design

Single custom `CKRecordZone` named `"CarrierWaveData"` in the private database. All record types live in this zone. Benefits:

- Atomic commits across related records (QSO + its ServicePresence records)
- Single zone subscription for push notifications
- Zone-level change tokens for efficient delta fetches

## Change Tracking

### Local → Cloud (outbound)

**Dirty flag approach.** Add a transient (non-persisted in CloudKit) property to each synced model:

```swift
/// Whether this record has local changes not yet synced to iCloud.
/// Set to true on any local mutation, cleared after successful upload.
var cloudDirtyFlag: Bool = false
```

When a QSO is created, edited, or soft-deleted, the code that performs the mutation also sets `cloudDirtyFlag = true`. `CloudSyncService` observes `ModelContext.didSave` notifications and collects the IDs of dirty records, then calls `CKSyncEngine.state.add(pendingRecordZoneChanges:)`.

When the engine calls `nextRecordZoneChangeBatch`, we query for records with `cloudDirtyFlag == true`, convert to `CKRecord`s, and return them. On successful send, clear the flag.

**Alternative considered: SwiftData history tracking.** Core Data persistent history is available but requires dropping below SwiftData to access `NSPersistentHistoryTransaction`. More complex, less transparent. The dirty flag is simple and fits the existing mutation patterns.

### Cloud → Local (inbound)

When `CKSyncEngine` delivers fetched changes via `handleEvent(.fetchedRecordZoneChanges)`:

1. Extract the `CKRecord` from the event
2. Look up local record by UUID (parsed from record name)
3. If found: merge fields (see Conflict Resolution)
4. If not found: check `deduplicationKey` for QSOs to prevent duplicates from other sync sources (LoFi, QRZ)
5. If truly new: create local record from CKRecord fields
6. Store `encodedSystemFields` in `CloudSyncMetadata` for the next change tag
7. **Do not** set `cloudDirtyFlag` — this came from the cloud, don't echo it back

All inbound processing happens on a background `ModelContext(container)` per performance rules. After processing a batch, post `.didSyncQSOs` notification so views re-fetch.

## Conflict Resolution

### QSO: field-level merge

When the same QSO is edited on two devices simultaneously:

1. Compare each field between the local version, the server version, and the base version (from stored `encodedSystemFields`)
2. For fields changed on only one side: accept that change
3. For fields changed on both sides to different values: prefer the version with the newer `modificationDate`
4. Special cases:
   - `isHidden`: if either version is hidden, the merged result is hidden (delete wins)
   - `notes`: if both changed, concatenate with a separator (user can clean up)
   - `rawADIF`: never overwrite a non-nil value with nil

### ServicePresence: union merge

Upload status should propagate in one direction — once a QSO is marked as present in a service, it stays present:

- `isPresent`: OR (if either device says present, it's present)
- `needsUpload`: AND (only needs upload if both devices agree)
- `uploadRejected`: OR (if either device rejected, respect that)
- `isSubmitted`: OR (if either device submitted, it's submitted)

### LoggingSession: last-writer-wins

Sessions are typically edited on a single device (the one running the session). Field-level merge is unnecessary — last `modificationDate` wins for the entire record. Exception: `qsoCount` takes the maximum of both values.

### ActivationMetadata: last-writer-wins

Same reasoning as LoggingSession. These are typically set once during or after an activation.

## Deduplication

QSOs can arrive from multiple sources: local logging, QRZ download, POTA download, LoFi sync, ADIF import, and now iCloud sync. The existing `deduplicationKey` (callsign + band + mode + 2-minute timestamp bucket) handles this.

When an inbound CKRecord maps to a QSO that doesn't exist by UUID but matches an existing QSO by `deduplicationKey`:

1. Link the existing local QSO to the incoming CKRecord (store UUID mapping in `CloudSyncMetadata`)
2. Merge fields from the CKRecord into the existing QSO (field-level merge)
3. Don't create a duplicate

This means a user can set up sync on a second device that already has QSOs imported from LoFi/QRZ — the overlapping QSOs merge rather than duplicate.

## Infrastructure Changes

### Entitlements

Add to `CarrierWave.entitlements`:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.jsvana.FullDuplex</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
```

The existing `com.apple.developer.ubiquity-kvstore-identifier` stays for settings sync.

### Background modes

Add remote notification background mode so `CKSyncEngine` push notifications wake the app:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

(The app may already have this for other features — check Info.plist.)

### App delegate

Forward push notification tokens and silent push payloads to `CKSyncEngine`:

```swift
// In app delegate or SwiftUI equivalent
func application(_ application: UIApplication,
                 didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
    // Forward to CloudSyncService
    await CloudSyncService.shared.handleRemoteNotification(userInfo)
    return .newData
}
```

### SwiftData schema

Add `CloudSyncMetadata` to the `ModelContainer` schema. Add `cloudDirtyFlag: Bool` to QSO, LoggingSession, ActivationMetadata (lightweight migration — new field with default value `false`).

## New Files

| File | Purpose |
|------|---------|
| `Services/CloudSync/CloudSyncService.swift` | `@MainActor` service owning the engine, publishing status |
| `Services/CloudSync/CloudSyncEngine.swift` | `actor` with `CKSyncEngineDelegate`, core sync logic |
| `Services/CloudSync/CKRecordMapper.swift` | `QSO ↔ CKRecord` mapping (and other models) |
| `Services/CloudSync/CloudSyncMetadata.swift` | SwiftData model for per-record sync state |
| `Services/CloudSync/CloudSyncConflictResolver.swift` | Conflict resolution strategies |
| `Views/Settings/CloudSyncSettingsView.swift` | Enable/disable toggle, status display, error log |

## UI

### Settings

Replace the current `ICloudSettingsView` (which only shows the ADIF import folder) with a richer `CloudSyncSettingsView`:

- **Sync toggle** — enable/disable iCloud QSO sync (separate from the existing ADIF folder monitoring)
- **Status** — "Up to date", "Syncing (3 pending)", "Error: ..."
- **Last sync time** — "Last synced 2 minutes ago"
- **iCloud account** — show account status, handle signed-out state
- **ADIF folder** — keep existing folder monitoring UI as a sub-section

### Dashboard

Add a subtle sync status indicator near the existing service status section. Show pending upload count if > 0. Tap to navigate to sync settings.

### Error handling

- Transient errors (network, throttle): silent retry by CKSyncEngine, no UI noise
- Account errors (signed out, quota full): persistent banner in settings
- Conflict resolution: silent merge, no user interaction needed (log conflicts for debug view)

## Phases

### Phase 0: Infrastructure (1 week)

- [ ] Add CloudKit entitlement and container identifier
- [ ] Add remote notification background mode
- [ ] Create `CloudSyncMetadata` SwiftData model
- [ ] Add `cloudDirtyFlag` to QSO, LoggingSession, ActivationMetadata
- [ ] Set up CKSyncEngine initialization and state persistence
- [ ] Forward push notifications to engine
- [ ] Update `ModelContainer` schema

### Phase 1: QSO sync — outbound (1 week)

- [ ] Implement `CKRecordMapper` for QSO → CKRecord (all ~30 fields)
- [ ] Set dirty flag on QSO create/edit/hide in `LoggingSessionManager`, `ImportService`
- [ ] Implement `nextRecordZoneChangeBatch` — query dirty QSOs, map to CKRecords
- [ ] Handle sent-record-zone-changes event — clear dirty flags
- [ ] Filter out metadata pseudo-modes
- [ ] Test: create QSO locally, verify it appears in CloudKit Dashboard

### Phase 2: QSO sync — inbound (1-2 weeks)

- [ ] Implement CKRecord → QSO mapping
- [ ] Handle fetched-record-zone-changes event — create/update local QSOs
- [ ] Deduplication: check `deduplicationKey` before creating
- [ ] Conflict resolution: field-level merge with timestamp tiebreaker
- [ ] Background ModelContext processing, post `.didSyncQSOs` notification
- [ ] Handle fetched-database-changes and zone deletions
- [ ] Test: create QSO in CloudKit Dashboard, verify it appears locally

### Phase 3: ServicePresence sync (1 week)

- [ ] CKRecord mapping for ServicePresence (with parent reference to QSO)
- [ ] Union merge conflict resolution
- [ ] Ensure ServicePresence records arrive and link correctly even if QSO arrives later (queue orphaned presence records, retry linking on next QSO fetch)
- [ ] Test: upload QSO to QRZ on device A, verify presence shows on device B

### Phase 4: LoggingSession + ActivationMetadata sync (1 week)

- [ ] CKRecord mapping for LoggingSession (including JSON-encoded roveStopsData, spotCommentsData)
- [ ] CKRecord mapping for ActivationMetadata
- [ ] Set dirty flag on session lifecycle events (start, end, edit equipment/notes)
- [ ] Last-writer-wins conflict resolution
- [ ] Test: complete session on device A, verify it appears on device B

### Phase 5: UI + settings (1 week)

- [ ] Build `CloudSyncSettingsView`
- [ ] Dashboard sync status indicator
- [ ] Handle iCloud account changes (signed out → clear metadata, signed in → initial sync)
- [ ] First-run: when enabling sync on a device with existing data, mark all records dirty for initial upload
- [ ] Error surfacing in settings (persistent errors only)

### Phase 6: Testing + hardening (1-2 weeks)

- [ ] Unit tests for CKRecordMapper (both directions, all models)
- [ ] Unit tests for conflict resolution (each strategy)
- [ ] Unit tests for deduplication with iCloud source
- [ ] Unit tests for metadata mode filtering
- [ ] Two-device integration testing
- [ ] Edge cases: offline edits on both devices, delete on one / edit on other
- [ ] Large initial sync (1000+ QSOs)
- [ ] CloudKit quota handling (graceful degradation)

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| SwiftData `@ModelActor` writes don't trigger SwiftUI `@Query` updates | Views show stale data after sync | We already avoid `@Query` — views use `@State` + `.task` + notification-driven re-fetch. Post `.didSyncQSOs` on inbound changes. |
| Large initial sync hits CloudKit rate limits | First sync on second device is slow | CKSyncEngine handles throttling internally. Show progress UI ("Syncing 142/1,847 QSOs"). |
| ServicePresence orphaning | Presence records arrive before their parent QSO | Queue unlinked presence records in `CloudSyncMetadata`, retry linking when QSOs are processed. |
| Existing ICloudMonitor interference | Two iCloud systems could confuse users | Keep them separate with clear UI labels. ADIF folder monitoring is "Import from Files"; CKSyncEngine is "iCloud Sync". |
| Photo sync | Session photos are JPEG files on disk, not in SwiftData | Phase 1 does NOT sync photos. Future: use CKAsset for photos, but that's a separate scope. |
| Watch app | Watch has its own data via App Group | Watch continues reading from `WidgetDataWriter` shared data. CKSyncEngine runs on iPhone/iPad only. |

## Open Questions

1. **Should we sync `rawADIF`?** It's often large (the full ADIF record text). Pros: complete data on all devices. Cons: increases CloudKit storage. Recommendation: sync it — it's important for reproducibility and re-export.

2. **Should `ActivityLog` sync?** Currently excluded because it's hunter-workflow focused and single-device. If users want to hunt from iPad sometimes, we'd add it in a later phase.

3. **Should we support shared databases?** CKSyncEngine can use `CKDatabase.Scope.shared` for club logging scenarios (multiple operators sharing a log). This is out of scope for v1 but the architecture doesn't preclude it.

4. **Migration from NSPersistentCloudKitContainer?** If we ever shipped the built-in sync and need to migrate, the data would be in a different CloudKit schema. Since we haven't shipped any CloudKit sync yet, this isn't a concern.
