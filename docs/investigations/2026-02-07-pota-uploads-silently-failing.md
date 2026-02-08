# Investigation: POTA uploads silently failing for N9HO after ~1/19/2026

**Date:** 2026-02-07
**Status:** Resolved
**Outcome:** Root cause was wrong `location` form field — `deriveLocation` mapped EM63 (Alabama) to Texas via coarse grid fallback. Fixed to use POTAParksCache for accurate park location lookup. Also: detect empty adif_files, reset orphaned submitted QSOs, mark invalid park references as rejected.

## Problem Statement

N9HO reports that POTA log uploads have not been working since ~1/19/2026. Force reupload shows HTTP 200 from POTA but QSOs never appear on pota.app.

## Findings

### Issue 1: POTA returns `{"adif_files": []}` — empty array

Upload to `POST /adif` returns HTTP 200, body `{"adif_files": []}`. Our `parseSuccessResponse` sees no `qsosAccepted` key and assumes all QSOs were accepted. The empty `adif_files` array strongly suggests POTA accepted the HTTP request but silently rejected the ADIF at the ingestion layer — no job is ever created.

**Root cause in our code:** `parseSuccessResponse` in `POTAClient+Upload.swift` treats any 200 response as success and doesn't check whether `adif_files` is empty. An empty array should be treated as a failure/rejection, not success.

### Issue 2: Submitted QSOs stuck in limbo — reconciliation gap

`reconcilePresenceRecord` in `QSOProcessingActor+POTAReconcile.swift` handles:
- `isPresent=true` + no confirmed job → reset to needsUpload
- `isSubmitted=true` + confirmed job → confirm
- `isSubmitted=true` + failed job → reset to needsUpload

But it does NOT handle:
- `isSubmitted=true` + **no matching job at all** → stuck forever

If POTA silently drops the upload (no job created), the QSO stays `isSubmitted=true, needsUpload=false` permanently. Force reupload resets it, but the cycle repeats.

### Issue 3: Some QSOs have corrupted park reference "US"

8 QSOs have `parkReference = "US"` instead of e.g. `"US-12740"`. This causes validation failure in `validateAndNormalizePark`. Likely from malformed LoFi/Ham2K import. Separate from the main upload issue.

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `POTAClient+Upload.swift` | Upload response handling | `parseSuccessResponse` doesn't check for empty `adif_files` |
| `QSOProcessingActor+POTAReconcile.swift` | Reconciliation logic | Missing handler for "submitted but no job exists" |
| `QSO+POTAPresence.swift` | Presence state management | `markSubmittedToPark` correctly sets state but relies on reconciliation |
| `SyncService+Upload.swift` | Upload orchestration | Park splitting and upload flow work correctly |
| `POTAClient+ADIF.swift` | ADIF generation | Generated ADIF looks correct with all required fields |

## Resolution

Three fixes applied:

1. **`POTAClient+Upload.swift` — `parseSuccessResponse`**: Check for empty `adif_files` array in the HTTP 200 response. When POTA returns `{"adif_files": []}` with no `qsosAccepted` key, return `success: false` instead of assuming all QSOs were accepted. This prevents marking QSOs as submitted when POTA silently rejects the upload.

2. **`QSOProcessingActor+POTAReconcile.swift` — `applyReconciliation`**: Added handler for `isSubmitted=true` when the activation key is NOT in confirmedKeys AND NOT in failedKeys. These orphaned submitted records are reset to `needsUpload=true`. Added `orphanResetCount` to `POTAReconcileResult` and logging in `SyncService+Process.swift`.

3. **`SyncService+Upload.swift` — `uploadParkToPOTA`**: Catch `POTAError.invalidParkReference` specifically and mark affected QSOs' service presence as `uploadRejected=true` to stop infinite retry loops for QSOs with corrupted park references like bare "US".

### Issue 4 (ROOT CAUSE): Wrong `location` form field — grid-to-state derivation error

After v1.25.1 deployment confirmed the empty `adif_files` detection was working but uploads were STILL being rejected, investigated the actual upload data from N9HO's SQLite export.

**Key discovery:** Every single upload for N9HO returns `{"adif_files": []}` — for ALL parks, ALL dates. This is account/request-level, not data-level.

**N9HO's QSOs imported from POTA (source=pota) have `isPresent=1`** — meaning they were never uploaded by Carrier Wave, just downloaded. N9HO has NEVER successfully uploaded via Carrier Wave.

**Root cause:** `deriveLocation()` in `POTAClient+Upload.swift` maps N9HO's grid `EM63XW` to `US-TX` (Texas). But N9HO is in **Alabama** — EM63 is central Alabama. The `fieldToState` fallback maps ALL `EM` grids to Texas, which is wildly wrong for the eastern half of the EM field.

Every upload sends `location=US-TX` for parks that are actually in Alabama, California, etc. POTA silently rejects uploads where the `location` form field doesn't match the park's actual state.

**Fix:** `deriveLocation` now consults `POTAParksCache.shared.parkSync(for:)` first to get the park's real `locationDesc`. Falls back to grid derivation only if the cache misses.

## Lessons Learned

- POTA API returns HTTP 200 for queued uploads, not for successful processing. Must treat `{"adif_files": []}` as a rejection signal.
- Reconciliation must handle the "no matching job" case for submitted QSOs, not just confirmed/failed matches.
- Invalid park references should be permanently rejected rather than retried on every sync.
- **Grid-to-state derivation is unreliable** — Maidenhead grid fields span many states. Always use authoritative park data (POTAParksCache) instead of approximating from the operator's grid square.
- When ALL uploads fail for a user, suspect account-level or request-level issues (auth, callsign, location), not data quality.
