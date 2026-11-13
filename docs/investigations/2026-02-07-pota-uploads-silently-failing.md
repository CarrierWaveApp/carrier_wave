# Investigation: POTA uploads silently failing for N9HO

**Date:** 2026-02-07
**Status:** Resolved
**Outcome:** Root cause was wrong `location` form field — `deriveLocation` mapped EM63 (Alabama) to Texas via coarse grid fallback. Fixed in v1.25.2 to use POTAParksCache for accurate park location lookup. Supplementary fixes in v1.25.1: detect empty adif_files, reset orphaned submitted QSOs, mark invalid park references as rejected.

## Problem Statement

N9HO reports that POTA log uploads have not been working since approximately 1/19/2026. Force reupload appears to succeed (HTTP 200 from POTA) but QSOs never appear on pota.app. User provided Sync Debug log screenshots showing the upload flow.

## Investigation Log

### Phase 1: Initial code review

Examined the upload pipeline: `SyncService+Upload.swift` → `POTAClient.uploadActivationWithRecording` → `buildUploadRequest` → `buildMultipartRequest` → `POST /adif`. Found three code-level issues (Issues 1-3 below). Shipped fixes as v1.25.1.

### Phase 2: v1.25.1 deployed, still failing

User confirmed the empty `adif_files` detection was working ("POTA returned empty adif_files for US-12740 - upload was silently rejected") but uploads were still being rejected. The ADIF content, multipart format, and auth token all appeared correct in the logs.

### Phase 3: SQLite export analysis

User provided N9HO's database export (`CarrierWave_QSO_Export_2026-02-07_212255.sqlite`). Queried the `ZPOTAUPLOADATTEMPT` table — **every single upload attempt since Feb 1 returned `{"adif_files": []}`**, across all parks (US-12740, US-0189, US-4571, US-1037, US-3528, US-0647, US-3791, US-5493, US-0661, US-3603), all dates, and QSO counts ranging from 1 to 278.

This ruled out data quality issues and pointed to an account-level or request-level problem.

### Phase 4: Import source analysis (key breakthrough)

Queried import sources:

| Source | QSO Count | Date Range |
|--------|-----------|------------|
| `pota` | 2,885 | 2024-06-30 to 2026-01-19 |
| `qrz` | 718 | 2024-10-13 to 2026-01-14 |
| `logger` | 24 | 2026-02-04 to 2026-02-05 |
| `hamrs` | 1 | 2025-10-07 |

The 2,885 QSOs with source `pota` were **downloaded FROM POTA**, not uploaded by Carrier Wave. Their `isPresent=1` status was set during import, not as confirmation of an upload. N9HO had **never successfully uploaded to POTA via Carrier Wave**. The "started failing around 1/19" was a misperception — those earlier QSOs were imported, not uploaded.

### Phase 5: Location field mismatch (root cause)

Checked the `ZPOTAUPLOADATTEMPT` records — every upload used `ZLOCATION = "US-TX"` (Texas). Then checked the actual parks via the POTA API:

| Park | Actual Location | Sent Location |
|------|----------------|---------------|
| US-12740 | US-AL (Alabama) | US-TX |
| US-1037 | US-AL (Alabama) | US-TX |
| US-0189 | US-CA (California) | US-TX |
| US-4571 | US-AZ,US-CA | US-TX |
| US-3528 | US-CA (California) | US-TX |
| US-0647 | US-CA (California) | US-TX |

Every park was being uploaded with the wrong state. The `deriveLocation` function used `gridToUSState` which maps operator grid `EM63XW` → `fieldToState("EM")` → `"TX"`. But EM63 is central Alabama, not Texas. The `fieldToState` fallback maps the entire EM Maidenhead field to Texas, which only covers the western portion.

N9HO's POTA profile confirms: callsign N9HO, location Alabama.

POTA silently rejects uploads where the `location` form field doesn't match the park's actual state, returning `{"adif_files": []}` with HTTP 200.

## Findings

### Issue 1: Empty `adif_files` treated as success

Upload to `POST /adif` returns HTTP 200, body `{"adif_files": []}`. Our `parseSuccessResponse` saw no `qsosAccepted` key and assumed all QSOs were accepted. The empty array should be treated as a rejection.

**Fix (v1.25.1):** Check for empty `adif_files` array and return `success: false`.

### Issue 2: Submitted QSOs stuck in limbo

Reconciliation handled confirmed jobs and failed jobs, but NOT the case where `isSubmitted=true` and no matching job exists at all. QSOs got stuck permanently.

**Fix (v1.25.1):** Added orphan reset handler — submitted QSOs with no matching job are reset to `needsUpload=true`.

### Issue 3: Corrupted park references cause infinite retries

Some QSOs had `parkReference = "US"` (missing the numeric part). These failed validation every sync cycle but were never marked as rejected.

**Fix (v1.25.1):** Catch `POTAError.invalidParkReference` and mark QSOs as `uploadRejected=true`.

### Issue 4 (ROOT CAUSE): Wrong `location` form field

`deriveLocation()` mapped N9HO's grid `EM63XW` → `US-TX` via the coarse `fieldToState` fallback that maps all `EM` grids to Texas. N9HO is in Alabama. POTA silently rejects uploads with location/park mismatch.

**Fix (v1.25.2):** `deriveLocation` now consults `POTAParksCache.shared.parkSync(for:)` first to get the park's real `locationDesc`. Falls back to grid derivation only on cache miss. Added warning log when grid-derived state doesn't match the park's known location(s).

## Files Modified

| File | Change | Version |
|------|--------|---------|
| `POTAClient+Upload.swift` | `deriveLocation` uses parks cache; `parseSuccessResponse` detects empty adif_files; `warnIfLocationMismatch` added | v1.25.1, v1.25.2 |
| `QSOProcessingActor+POTAReconcile.swift` | Orphan reset for submitted QSOs with no matching job | v1.25.1 |
| `SyncService+Upload.swift` | Catch `invalidParkReference` and mark as rejected | v1.25.1 |
| `SyncService+Process.swift` | Log orphan reset count in reconciliation results | v1.25.1 |

## Files Examined (Read Only)

| File | Relevance | Finding |
|------|-----------|---------|
| `POTAClient.swift` | Upload orchestration | `uploadActivationWithRecording` flow is correct |
| `POTAClient+ADIF.swift` | ADIF generation | Generated ADIF has all required fields |
| `POTAClient+GridLookup.swift` | Grid-to-state mapping | `fieldToState("EM")` returns `"TX"` — wrong for eastern EM grids |
| `POTAParksCache.swift` | Park metadata cache | Has `locationDesc` for every park — the authoritative source |
| `QSO+POTAPresence.swift` | Presence state machine | Correct, relies on reconciliation |
| `POTAJob.swift` | Job matching | Correct activation key matching |
| `POTAAuthService.swift` | Authentication | Token flow is correct, token has `pota:callsign` claim |

## Hypotheses Explored

### Hypothesis 1: POTA API changed around 1/19/2026
- **Evidence for:** User reported uploads stopped working around that date
- **Evidence against:** SQLite analysis showed N9HO never successfully uploaded via Carrier Wave — earlier QSOs were imported from POTA, not uploaded
- **Result:** Disproved. No API change; uploads never worked for this user.

### Hypothesis 2: ADIF content has invalid fields
- **Evidence for:** Some QSOs have `MODE=PHONE` (not a standard ADIF mode)
- **Evidence against:** CW-only uploads (valid mode) also fail; the rejection is systematic across all parks/modes
- **Result:** Not the root cause. PHONE mode is a separate data quality issue.

### Hypothesis 3: Auth token or callsign mismatch
- **Evidence for:** Token has `pota:callsign` claim that could be validated server-side
- **Evidence against:** Callsign `N9HO` in form field matches the POTA account
- **Result:** Not the issue.

### Hypothesis 4: Location field mismatch (CONFIRMED)
- **Evidence for:** Every upload sends `US-TX`, parks are in `US-AL`/`US-CA`; grid `EM63` is Alabama not Texas; POTA profile shows Alabama
- **Tested:** Yes — fixed `deriveLocation` to use parks cache
- **Result:** Root cause confirmed.

## Lessons Learned

- **POTA API returns HTTP 200 for queued uploads, not for successful processing.** Must treat `{"adif_files": []}` as a rejection signal, not success.
- **Reconciliation must handle the "no matching job" case** for submitted QSOs, not just confirmed/failed matches.
- **Invalid park references should be permanently rejected** rather than retried on every sync.
- **Grid-to-state derivation is unreliable.** Maidenhead grid fields span many states. Always use authoritative park data (POTAParksCache) instead of approximating from the operator's grid square.
- **When ALL uploads fail for a user, suspect request-level issues** (auth, callsign, location), not data quality. The SQLite export was the key to confirming this was systematic.
- **Check import sources before assuming uploads worked previously.** `isPresent=1` from a POTA import is not evidence that Carrier Wave uploaded successfully.
