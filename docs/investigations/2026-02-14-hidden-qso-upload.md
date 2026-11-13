# Investigation: Hidden/Deleted QSOs Being Uploaded During Sync

**Date:** 2026-02-14
**Status:** Resolved
**Outcome:** Four code paths allowed hidden QSOs to be uploaded or re-queued for upload. All fixed with defense-in-depth approach.

## Problem Statement

User reported that hidden/deleted QSOs were being uploaded during sync operations (QRZ, POTA, LoFi).

## Root Cause

Multiple contributing factors:

### 1. Primary: `fetchQSOsNeedingUpload()` missing `isHidden` filter

`SyncService+Upload.swift:fetchQSOsNeedingUpload()` fetches all QSOs with `needsUpload` ServicePresence records but never checks `isHidden`. Hidden QSOs with pending upload flags are included in upload batches sent to QRZ, POTA, and LoFi.

### 2. `hideQSO()` doesn't clear upload flags

`LoggingSessionManager.hideQSO()` sets `isHidden = true` but doesn't clear `needsUpload` on the QSO's ServicePresence records. The hidden QSO retains its upload markers.

### 3. `deleteCurrentSession()` doesn't clear upload flags

`LoggingSessionManager.deleteCurrentSession()` hides all session QSOs but doesn't clear their `needsUpload` flags, same issue as above.

### 4. POTA reconciliation re-queues hidden QSOs

`QSOProcessingActor+POTAReconcile.swift:reconcilePresenceRecord()` doesn't check `isHidden`. During reconciliation, if a hidden QSO's POTA presence doesn't match the job log, it gets reset to `needsUpload=true`, re-queuing it for upload.

## Code Paths Already Correct

- `repairOrphanedQSOs` — correctly filters `!$0.isHidden` (line 173)
- `loadParkQSOs()` in POTAActivationsView — correctly filters `!$0.isHidden` (line 310)
- `LoggingSessionManager.markForUpload` — only called on new QSOs (never hidden)
- `ImportService.createServicePresenceRecords` — only called on new imports
- `ADIFExportService` — receives pre-filtered snapshots
- `POTAClient+Upload.buildUploadRequest` — filters metadata modes (not hidden, but correct for its purpose)

## Resolution

### Fix 1: Filter hidden QSOs from upload fetch
**File:** `SyncService+Upload.swift`
Added `!qso.isHidden` guard to `fetchQSOsNeedingUpload()`.

### Fix 2: Clear upload flags when hiding QSOs
**File:** `LoggingSessionManager.swift`
Both `hideQSO()` and `deleteCurrentSession()` now clear `needsUpload` on all ServicePresence records when hiding a QSO.

### Fix 3: Skip hidden QSOs in POTA reconciliation
**File:** `QSOProcessingActor+POTAReconcile.swift`
Added `!qso.isHidden` guard to `reconcilePresenceRecord()`.

### Fix 4: Data repair step for existing dirty data
**File:** `QSOProcessingActor+OrphanRepair.swift`
Added `clearHiddenQSOUploadFlags()` method. Called from `performDataRepairs()` during every sync to clean up any pre-existing hidden QSOs with stale upload flags.

### Tests
**File:** `ServicePresenceTests.swift`
Added three tests:
- `testHiddenQSO_NotIncludedInUploadQuery` — verifies hidden QSOs filtered from upload queries
- `testHidingQSO_ClearsUploadFlags` — verifies hiding clears all upload flags
- `testHiddenQSO_ExistingPresenceRecords_ClearedByRepair` — verifies repair step cleans dirty data

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `SyncService+Upload.swift` | Upload fetch | **BUG:** No `isHidden` filter |
| `LoggingSessionManager.swift` | Hide/delete QSOs | **BUG:** Doesn't clear upload flags |
| `QSOProcessingActor+POTAReconcile.swift` | POTA reconciliation | **BUG:** Doesn't skip hidden QSOs |
| `QSOProcessingActor+OrphanRepair.swift` | Data repair | Added new repair step |
| `SyncService+Process.swift` | Async wrappers | Added wrapper for new repair |
| `SyncService+Helpers.swift` | Repair orchestration | Added call to new repair |
| `POTAClient+Upload.swift` | POTA upload building | OK — receives pre-filtered QSOs |
| `QRZClient+ADIF.swift` | QRZ ADIF generation | OK — receives pre-filtered QSOs |
| `POTAActivationsView.swift` | Manual POTA upload | OK — filters `!$0.isHidden` |
| `ImportService.swift` | Service presence creation | OK — only for new imports |
| `ADIFExportService.swift` | ADIF file export | OK — receives snapshots |

## Lessons Learned

- When adding a "soft delete" (`isHidden`), all write paths that set flags (like `needsUpload`) and all read paths that consume those flags must be audited for the new field.
- Defense-in-depth: both the writer (hiding a QSO) and the reader (fetching for upload) should enforce the invariant independently.
- Data repair steps are important for cleaning up pre-existing dirty state that predates the fix.
