# Investigation: Comment Park Reference Not Being Extracted

**Date:** 2026-02-15
**Status:** Resolved
**Outcome:** Added comment-to-park extraction fallback in 3 import/sync paths; split QSOProcessingActor for lint compliance

## Problem Statement

User reports that park references are not being properly pulled from ADIF comments. WSJT-X and other loggers often put the park reference (e.g., "POTA K-1234") in the comment field instead of the dedicated MY_SIG_INFO ADIF field. We need to extract these and set them into `parkReference` so they flow correctly to POTA, QRZ, and other service uploads.

## Hypotheses

### Hypothesis 1: Comment-to-park extraction exists but is only wired up in one path
- **Evidence for:** `ParkReference.extractFromFreeText()` exists and is well-tested. The ADIF file import path (`ImportService.createQSO(from record:)`) already uses it as a fallback.
- **Tested:** Yes
- **Result:** Confirmed. Three other import paths were missing the fallback.

## Investigation Log

### Step 1: Traced all QSO creation paths

| Path | Has Comment Fallback? |
|---|---|
| ADIF file import (`ImportService.createQSO(from record:)`) | Yes (line 198-199) |
| QRZ import (`ImportService.createQSOFromQRZ`) | **No** |
| Unified sync create (`QSOProcessingActor.createQSO(from:)`) | **No** |
| Unified sync merge (`QSOProcessingActor.mergeIntoExisting`) | **No** |

### Step 2: Verified upload paths already use parkReference

- `POTAClient+ADIF.swift` line 101: writes `MY_SIG_INFO` from `parkReference`
- `QRZClient+ADIF.swift` line 193: writes `my_sig_info` from `parkReference`
- Both are correct — the issue is only that `parkReference` isn't being populated from comments.

### Step 3: Applied fixes

Added `ParkReference.extractFromFreeText()` fallback to:
1. `QSOProcessingActor.createQSO(from:)` — unified sync path for new QSOs
2. `QSOProcessingActor.mergeIntoExisting` — unified sync merge path (checks both fetched and existing notes)
3. `ImportService.createQSOFromQRZ` — legacy QRZ import path

### Step 4: Split QSOProcessingActor for lint compliance

Extracted merge/creation helpers to `QSOProcessingActor+Merge.swift` to stay under 500-line file limit and 300-line type body limit.

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `CarrierWaveCore/.../ParkReference.swift` | Core extraction logic | `extractFromFreeText()` works correctly |
| `CarrierWaveCore/.../ADIFParser.swift` | ADIF parsing | Parses `comment`, `my_sig_info`, `sig_info` correctly |
| `CarrierWave/Services/ImportService.swift` | ADIF file import | Already has comment fallback at line 198-199 |
| `CarrierWave/Services/ImportService+External.swift` | QRZ/POTA import | `createQSOFromQRZ` was missing fallback |
| `CarrierWave/Services/QSOProcessingActor.swift` | Unified sync processing | `createQSO(from:)` and `mergeIntoExisting` were missing fallback |
| `CarrierWave/Services/QRZClient+ADIF.swift` | QRZ ADIF gen/parse | Parses MY_SIG_INFO but not comment fallback; upload gen is correct |
| `CarrierWave/Services/POTAClient+ADIF.swift` | POTA ADIF generation | Correctly writes MY_SIG_INFO from parkReference |
| `CarrierWave/Services/FetchedQSO.swift` | Unified QSO model | Factory methods pass through parkReference without comment extraction |

## Root Cause

`ParkReference.extractFromFreeText()` was only called in the ADIF file import path. The three other QSO creation/merge paths (QRZ import, unified sync create, unified sync merge) did not fall back to comment extraction when `parkReference`/`MY_SIG_INFO` was missing.

## Resolution

1. **`QSOProcessingActor+Merge.swift:createQSO(from:)`** — Falls back to `ParkReference.extractFromFreeText(notes)` when `parkReference` is nil
2. **`QSOProcessingActor+Merge.swift:mergeIntoExisting`** — Checks fetched notes for park refs during merge, and after all merges checks existing notes if parkReference is still nil
3. **`ImportService+External.swift:createQSOFromQRZ`** — Falls back to `ParkReference.extractFromFreeText(notes)` when explicit park ref is nil
4. **Tests** — Added 5 new test cases in `ImportServiceTests.swift` covering ADIF comment extraction, QRZ comment extraction, and explicit-park-wins-over-comment behavior
5. **File split** — Extracted merge/creation helpers from `QSOProcessingActor.swift` to `QSOProcessingActor+Merge.swift`

## Lessons Learned

- When adding a utility function like `extractFromFreeText`, wire it up at every QSO creation point — not just the first one you encounter
- The unified sync path (`QSOProcessingActor`) is the most important to fix since it handles QRZ, LoFi, POTA, LoTW, and Club Log downloads
