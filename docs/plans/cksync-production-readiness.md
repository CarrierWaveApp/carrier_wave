# CKSync Production-Readiness Plan

Status: Draft
Created: 2026-02-20

This document outlines what is needed to make iCloud QSO sync (CKSync) trustworthy enough to remove the "Experimental" label.

## 1. Known Bugs

### 1.1 `importedAt` used as modification date

`mergeInboundQSO` in `CloudSyncConflictResolver` uses `importedAt` (a write-once timestamp set when the QSO is first created) as the local modification date. This means remote records always win for QSOs that were imported long ago, even if the user edited them locally after import.

**Impact:** Local edits silently overwritten by stale remote data.

**Files:** `CloudSyncEngine+Inbound.swift:100`, `CloudSyncConflictResolver.swift:50`

### 1.2 Notes merge grows unboundedly

`mergeNotes` concatenates conflicting notes with a `\n---\n` separator. On repeated syncs with the same conflict, notes grow indefinitely.

**Impact:** Notes field becomes unreadable with duplicated content.

**File:** `CloudSyncConflictResolver.swift:218-230`

### 1.3 No `modifiedAt` property on QSO model

The QSO model has no `modifiedAt` field, so there is no reliable way to determine when a QSO was last edited locally. This is the root cause of bug 1.1.

### 1.4 Wrong UserDefaults key in backup restore (FIXED)

`BackupService+Restore.swift` was using `"iCloudQSOSyncEnabled"` instead of the actual key `"cloudSyncEnabled"`, so restoring from backup failed to disable iCloud sync. Fixed in this changeset.

## 2. Required Test Coverage

### 2.1 Unit tests for `CloudSyncConflictResolver`

- All merge strategies (field-level QSO merge, union ServicePresence, LWW session)
- Edge cases: nil fields, identical records, one-sided changes
- Notes merge: same content, different content, nil handling
- `importedAt` / future `modifiedAt` ordering

### 2.2 Unit tests for `CKRecordMapper`

- Round-trip field mapping (QSO -> CKRecord -> QSOFields)
- All field types (String, Date, Int, Double, Bool, optional)
- Missing/extra fields in CKRecord (forward compatibility)

### 2.3 Unit tests for field extraction/application

- `extractQSOFields` completeness (every QSO property mapped)
- `applyQSOFields` completeness (every field applied back)
- ServicePresence, LoggingSession, ActivationMetadata mapping

### 2.4 Integration tests for inbound processing

- New record creates QSO + CloudSyncMetadata
- Updated record merges correctly with local state
- Deleted record removes QSO and metadata
- Conflict resolution picks correct winner

### 2.5 Integration tests for outbound batching

- Dirty records collected and batched
- Sent changes clear dirty flags
- Failed sends retain dirty state for retry

### 2.6 Schema migration + sync interaction

- Adding new fields doesn't break existing CKRecords
- Old-format records still parse correctly

## 3. Safety Guardrails

### 3.1 Pre-enable backup (DONE)

A backup is created automatically when the user enables iCloud sync. Implemented in `CloudSyncSettingsView`.

### 3.2 Post-sync validation

After each sync cycle, compare:
- Local QSO count before and after (flag if >5% drop)
- Spot-check 10 random QSOs for field completeness (no unexpected nil fields)
- Log warnings if validation fails; pause sync if QSO count drops significantly

### 3.3 Sync diff log

Record what fields changed during each merge operation:
- QSO identifier, field name, old value, new value, resolution (local/remote/merged)
- Store in a rolling log (last 1000 entries) for debugging
- Surface in SyncDebugView

### 3.4 Kill switch and rollback

- Disabling sync should immediately stop all CKSyncEngine operations
- Offer to restore the pre-enable backup when disabling sync
- Show backup age/QSO count so user can make an informed choice

## 4. Architecture Improvements

### 4.1 Add `modifiedAt` to QSO model

- New `Date?` property, updated on every local edit
- SwiftData lightweight migration (new optional field, no data loss)
- Backfill: set `modifiedAt = importedAt` for existing QSOs

### 4.2 Use `modifiedAt` in conflict resolution

- Replace `importedAt` comparison with `modifiedAt`
- Local edit after import should now win over stale remote data
- Fall back to `importedAt` if `modifiedAt` is nil (migration window)

### 4.3 Cap notes merge

- Before concatenating, check if the remote notes are already a substring of local (or vice versa)
- Deduplicate repeated `---` separated blocks
- Cap total notes length (e.g., 10,000 characters)

### 4.4 Sync state indicators in UI

- Show per-QSO sync state: synced, pending upload, conflict
- Badge on iCloud settings row when there are pending/conflicted records
- Consider a "Sync Issues" section in settings listing conflicted QSOs

## 5. Production-Ready Checklist

- [ ] Bug 1.1 fixed: `modifiedAt` used for conflict resolution
- [ ] Bug 1.2 fixed: notes merge capped and deduplicated
- [ ] Bug 1.3 fixed: `modifiedAt` added to QSO model with migration
- [ ] Bug 1.4 fixed: wrong UserDefaults key in backup restore
- [ ] Unit test coverage >80% for CloudSync code
- [ ] Integration tests for create, update, delete, conflict scenarios
- [ ] Multi-device conflict scenarios tested manually
- [ ] Pre-enable backup working (done)
- [ ] Post-sync validation implemented
- [ ] Sync diff log implemented and visible in debug view
- [ ] Sync can be disabled without data loss (kill switch + rollback)
- [ ] "Experimental" label removed from CloudSyncSettingsView
