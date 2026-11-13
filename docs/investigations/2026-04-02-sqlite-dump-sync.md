# Investigation: iCloud Sync via SQLite Dumps

**Date:** 2026-04-02
**Status:** Exploration
**Problem:** Per-record CKSyncEngine sync doesn't scale to 200K QSOs

## Current Approach: Per-Record CKSyncEngine

Each QSO is an individual CKRecord. At 200K QSOs:

| Metric | Value | Problem |
|--------|-------|---------|
| CloudSyncMetadata rows | 200,000 | ~80 MB RAM just for bookkeeping |
| Initial sync batches | 2,000 (100/batch) | Minutes to hours of network round-trips |
| Dirty flag scan | Full table scan per collect cycle | O(n) per sync trigger |
| CKRecord mapping | 200K field extractions + CK builds | CPU-intensive serialization |
| Sync implementation | 15+ files, ~3K lines | High maintenance burden |

The system works at 10K–50K QSOs but becomes untenable at 200K:
- Initial sync on a new device takes forever
- CloudSyncMetadata alone consumes ~80 MB
- Every "mark all dirty" (account change) touches 200K rows

## Alternative: SQLite File-Level Sync

Instead of syncing individual records, sync the database file itself.

### Option A: iCloud Drive File Sync (DON'T DO THIS)

Put the SQLite file in the ubiquity container and let Apple sync it.

**Why not:** Apple explicitly warns against this. iCloud Drive syncs files as opaque blobs — it cannot merge concurrent WAL writes from two devices. Result: silent corruption. The [Apple docs](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/DesigningForDocumentsIniCloud.html) say "do not store SQLite databases in iCloud Drive."

### Option B: CKAsset Snapshot + Change Journal (RECOMMENDED)

Two-tier sync: a periodic full SQLite snapshot for bootstrap, plus a lightweight change journal for incremental updates.

#### How It Works

```
Device A                          CloudKit                        Device B
────────                          ────────                        ────────
                                  ┌─────────────────────┐
  Periodic snapshot ──────────────│ CKAsset: full .sqlite│
  (every N hours or               │ (single CKRecord)    │
   on significant change)         ├─────────────────────┤
                                  │                     │
  Per-change journal entries ─────│ CKRecords: small    │────── Apply journal
  (JSON, one per mutation batch)  │ change patches      │       entries in order
                                  └─────────────────────┘
                                                                 New device?
                                                          ┌──── Download snapshot
                                                          │     Apply journal tail
                                                          └──── Ready in seconds
```

#### Snapshot Tier

- Reuse the existing `BackupService.checkpointWAL()` + copy mechanism
- Upload as a `CKAsset` on a single `CKRecord` in the sync zone
- One snapshot per device, updated periodically (e.g., every 6 hours, or after 1,000 changes)
- New devices download the latest snapshot → instant bootstrap
- Snapshot record includes: `deviceId`, `timestamp`, `qsoCount`, `schemaVersion`

**Size estimate at 200K QSOs:** ~150–200 MB (with rawADIF). Without rawADIF: ~60 MB. CKAsset max is 250 MB, so this fits but is tight. If rawADIF is eliminated (already a P2 item), this is very comfortable.

#### Change Journal Tier

Instead of one CKRecord per QSO, batch changes into journal entries:

```swift
// One CKRecord per change batch (not per QSO)
struct ChangeJournalEntry: Codable {
    let id: UUID
    let deviceId: String
    let timestamp: Date
    let sequenceNumber: Int64
    let changes: [ChangeOperation]
}

enum ChangeOperation: Codable {
    case upsert(entityType: String, id: UUID, fields: [String: CodableValue])
    case delete(entityType: String, id: UUID)
}
```

- Each journal entry contains a batch of mutations (up to 100 QSOs per entry)
- 200K QSOs with 100 changes/entry = 2,000 journal records (same count as current, but simpler)
- Journal entries are append-only, immutable once written
- After a new snapshot is uploaded, old journal entries before the snapshot timestamp can be pruned

#### Conflict Resolution

**Snapshot conflicts:** Last-writer-wins at the snapshot level. Snapshots are periodic checkpoints, not the source of truth for individual fields.

**Journal conflicts:** Journal entries are append-only — there are no conflicts in the journal itself. When two devices edit the same QSO, both journal entries are applied in timestamp order. The same field-level merge logic from the current `CloudSyncConflictResolver` applies, but it runs locally when applying journal entries rather than in CKSyncEngine callbacks.

**Divergence recovery:** If devices diverge too far (journal gap > snapshot), the receiving device downloads the latest snapshot and replays only the journal tail after it.

#### What This Eliminates

| Current Component | Status with SQLite Sync |
|-------------------|------------------------|
| `CloudSyncMetadata` model (200K rows) | **Gone.** No per-record CK system fields needed |
| `cloudDirtyFlag` on every model | **Gone.** Changes go to the journal |
| `CKRecordMapper` (field ↔ CKRecord mapping) | **Gone.** Journal uses Codable directly |
| `encodedSystemFields` archival | **Gone.** No CKRecord system fields to track |
| Per-record conflict resolution callbacks | **Simplified.** Local-only merge when applying journal |
| 15+ CloudSync files | **~3–4 files** |

#### Memory Profile at 200K QSOs

| Component | Current | With SQLite Sync |
|-----------|---------|------------------|
| CloudSyncMetadata | ~80 MB | 0 MB |
| Dirty flag scanning | O(n) | O(1) — just check journal |
| Initial sync | 200K records over network | 1 file download (~60–200 MB) |
| Incremental sync | Per-record CKRecord build | Append to journal (tiny) |

### Option C: sqldiff-Based Patches

Use SQLite's `sqldiff` to compute the delta between two database versions and ship the delta as SQL statements.

```
Device A: snapshot v1 → make changes → snapshot v2
          sqldiff(v1, v2) → patch.sql (small)
          Upload patch.sql as CKAsset
Device B: Download patch.sql → apply to local v1 → now at v2
```

**Pros:**
- Truly incremental — only changed rows are transmitted
- No application-level change tracking needed
- Binary-accurate sync

**Cons:**
- `sqldiff` is a CLI tool, not available as a C API in iOS
- Would need to bundle the sqldiff logic or use the session extension
- Two snapshots must be kept locally to compute diffs
- Ordering and merging patches from multiple devices is complex
- SwiftData schema migrations could break patch application

**Verdict:** Interesting but too complex for the benefit. The change journal approach is simpler and nearly as efficient.

### Option D: Pure Snapshot (No Journal)

Just upload the full SQLite periodically. No change tracking.

**Pros:** Dead simple. Could be implemented in < 200 lines.

**Cons:**
- 60–200 MB upload for every sync cycle
- Last-writer-wins at the database level — concurrent edits on two devices means one device's changes are lost
- No real-time sync — changes appear only on the next snapshot interval
- CloudKit upload bandwidth becomes a bottleneck

**Verdict:** Only viable as a "backup sync" — acceptable for disaster recovery but not for multi-device workflows. Could be a useful stepping stone though.

## Recommended Approach: Phased Migration

### Phase 1: Snapshot Bootstrap (Low Risk, High Impact)

Keep the existing CKSyncEngine for incremental sync but add a CKAsset snapshot for initial device setup.

- New device downloads the snapshot instead of syncing 200K individual records
- After snapshot restore, CKSyncEngine catches up with changes since the snapshot
- Uses existing `BackupService` infrastructure for snapshot creation
- **Eliminates the biggest pain point (initial sync) with minimal code change**

Implementation:
1. Add a `DatabaseSnapshot` CKRecord type with a CKAsset field
2. After each backup, optionally upload as a CKAsset (throttled to every 6 hours)
3. On first sync, check for an existing snapshot — if found, download and restore, then start CKSyncEngine from that point
4. CKSyncEngine's `fetchChanges` picks up anything after the snapshot

**Estimated effort:** ~300 lines of new code, no changes to existing sync.

### Phase 2: Change Journal (Medium Risk, Replaces CKSyncEngine)

Replace CKSyncEngine with the change journal approach.

1. Intercept `ModelContext.didSave` → write `ChangeJournalEntry` to CloudKit
2. On remote change notification → fetch and apply journal entries
3. Periodic snapshot upload for bootstrap/recovery
4. Remove `CloudSyncMetadata`, `cloudDirtyFlag`, `CKRecordMapper`

**Estimated effort:** ~800 lines new, ~2,500 lines removed.

### Phase 3: Optimize

- Compress journal entries (gzip the JSON)
- Batch journal entries more aggressively during active sessions
- Add journal compaction (merge old entries into snapshots)
- Add integrity verification (hash-based checksums on snapshots)

## Key Risks

| Risk | Mitigation |
|------|------------|
| CKAsset 250 MB limit | Eliminate rawADIF (P2 item); compress snapshot |
| Journal ordering across devices | Sequence numbers + device IDs; timestamp tiebreaker |
| Schema migration breaks snapshot restore | Include schemaVersion; reject incompatible snapshots |
| Snapshot upload bandwidth | Throttle to every 6 hours; only upload if changes exist |
| Loss of field-level merge | Journal approach preserves it — merge runs locally |
| CloudKit rate limits on CKAsset upload | 250 MB assets are within limits; throttling prevents abuse |

## Decision Needed

**Phase 1 alone** solves the biggest scaling problem (initial sync) with minimal risk and can be built incrementally on top of the existing system.

**Phase 1 + 2** is a full replacement that dramatically simplifies the codebase and eliminates the ~80 MB CloudSyncMetadata overhead, but requires more careful migration planning.

Recommendation: **Start with Phase 1.** It's backwards-compatible, low-risk, and immediately solves the "new device with 200K QSOs" problem. Evaluate Phase 2 after seeing real-world performance data.
