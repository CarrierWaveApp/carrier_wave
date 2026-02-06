# Investigation: POTA Uploads Showing Success But Not Sent

**Date:** 2026-02-06
**Status:** Resolved
**Outcome:** Two bugs found: (1) redundant park reference re-filtering in `uploadActivationWithRecording` uses exact match that drops multi-park QSOs, (2) legacy `needsUpload` flag never cleared after per-park upload.

## Problem Statement

User reports POTA uploads appear successful in the app but QSOs don't actually appear on pota.app.

## Root Cause

### Bug 1: Exact-match re-filtering drops multi-park QSOs

In `POTAClient.uploadActivationWithRecording` (line 296) and `POTAClient.buildUploadRequest` (line 46-49), QSOs are re-filtered by exact park reference match:

```swift
let parkQSOs = qsos.filter { $0.parkReference?.uppercased() == normalizedParkRef }
```

For two-fer activations, QSOs have `parkReference = "US-1044, US-3791"`. When uploading to park "US-1044", the comparison `"US-1044, US-3791" == "US-1044"` fails, producing an empty array.

The code then returns `POTAUploadResult(success: true, qsosAccepted: 0)` — reporting success despite sending nothing. The caller (`uploadParkToPOTA` / `uploadPark`) sees `result.success == true` and marks QSOs as uploaded via `markUploadedToPark`.

**Affected paths:**
- `SyncService+Upload.uploadParkToPOTA` → `POTAClient.uploadActivationWithRecording`
- `POTAActivationsContentView.uploadPark` → `POTAClient.uploadActivationWithRecording`

**Both callers already filter QSOs to the correct set before calling.** The re-filtering is redundant and broken for multi-park references.

### Bug 2: Legacy needsUpload never cleared

When a QSO is logged, `markNeedsUpload(to: .pota)` creates a ServicePresence with `parkReference = nil` (legacy format) and `needsUpload = true`.

After upload, `markUploadedToPark("US-1044")` creates/updates a per-park ServicePresence with `parkReference = "US-1044"`. But the legacy record's `needsUpload = true` is **never cleared**.

This means `fetchQSOsNeedingUpload()` (which checks `servicePresence.contains(where: \.needsUpload)`) keeps finding the QSO, causing repeated failed upload attempts.

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `SyncService+Upload.swift` | Upload orchestration | Expands multi-park QSOs correctly, but downstream re-filters break it |
| `POTAClient.swift:279-329` | `uploadActivationWithRecording` | Re-filters by exact park match at line 296, drops multi-park QSOs |
| `POTAClient+Upload.swift:37-80` | `buildUploadRequest` | Also re-filters by exact park match at line 46-49 |
| `QSO+POTAPresence.swift` | Per-park tracking | `markUploadedToPark` creates per-park record but doesn't clear legacy |
| `POTAActivation.swift` | View model | `pendingQSOs(forPark:)` correctly returns QSOs for view-initiated uploads |
| `ParkReference.swift` | Park splitting | `split()` correctly handles "US-1044, US-3791" → ["US-1044", "US-3791"] |

## Resolution

1. **Fix re-filtering**: Change exact match to use `ParkReference.hasOverlap` so multi-park QSOs are included when any of their parks matches the target.
2. **Fix legacy cleanup**: After successful per-park upload, clear the legacy `needsUpload` flag when all parks have been uploaded.
