# Investigation: Wrong Park Attribution (US-0189 vs US-12740)

**Date:** 2026-02-05
**Status:** Resolved
**Outcome:** Upstream data issue - QRZ logbook contains incorrect park references

## Problem Statement

TestFlight feedback from jkeithrogers@charter.net:
> "Something is up with this. I've never been there. These should all be my us-12740 hinds road park"

User reports QSOs appearing under a park (US-0189) they have never activated from. Expected park is US-12740 (Hinds Road).

## Hypotheses

### Hypothesis 1: LoFi import two-fer bug
- **Evidence for:** Code only checks first `potaActivation` ref from operation
- **Evidence against:** User's US-0189 QSOs don't come from LoFi
- **Tested:** Yes
- **Result:** Not the cause - all US-0189 QSOs imported from QRZ

### Hypothesis 2: Deduplication merging wrong parks
- **Evidence for:** Deduplication can absorb park references from "loser" QSO
- **Evidence against:** Config uses `requireParkMatch: true`
- **Tested:** Yes
- **Result:** Not the cause - deduplication won't merge QSOs with different parks

### Hypothesis 3: QRZ import data already contains wrong park
- **Evidence for:** All 290 US-0189 QSOs have `importSource = 'qrz'`
- **Evidence against:** None
- **Tested:** Yes
- **Result:** **Confirmed - this is the root cause**

## Investigation Log

### Step 1: Database analysis
Queried user's exported SQLite database to find park distribution:

```sql
SELECT DISTINCT ZPARKREFERENCE, COUNT(*) FROM ZQSO 
WHERE ZPARKREFERENCE IS NOT NULL GROUP BY ZPARKREFERENCE ORDER BY cnt DESC
```

Results:
- US-12740: 1084 QSOs
- US-0636: 984 QSOs
- **US-0189: 290 QSOs** (the problematic park)

### Step 2: Check import sources
```sql
SELECT ZPARKREFERENCE, ZIMPORTSOURCE, COUNT(*) FROM ZQSO 
WHERE ZPARKREFERENCE IN ('US-0189', 'US-12740') 
GROUP BY ZPARKREFERENCE, ZIMPORTSOURCE
```

Results:
| Park | Import Source | Count |
|------|---------------|-------|
| US-0189 | qrz | 290 |
| US-12740 | logger | 60 |
| US-12740 | pota | 992 |
| US-12740 | qrz | 32 |

**Key finding:** All US-0189 QSOs came exclusively from QRZ import.

### Step 3: Check date overlap
Both parks have QSOs on the same dates (e.g., Nov 3, 4, 5, Dec 1, 2, 4), suggesting these were single activations that got split.

### Step 4: Examine raw ADIF
```sql
SELECT ZRAWADIF FROM ZQSO WHERE ZPARKREFERENCE = 'US-0189' LIMIT 1
```

Raw ADIF from QRZ contains:
```
<my_pota_ref:7>US-0189
<my_sig:4>POTA
<my_sig_info:7>US-0189
```

The QRZ logbook itself has incorrect park references baked into the ADIF data.

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `ImportService.swift` | LoFi import logic | Correctly passes park ref from operation |
| `LoFiModels.swift` | `myPotaRef` function | Only checks operation refs (minor issue, not cause) |
| `QRZClient+ADIF.swift` | QRZ ADIF parsing | Correctly parses MY_SIG_INFO for park ref |
| `DeduplicationMatcher.swift` | Merge logic | Won't merge different parks |
| User's SQLite export | Actual data | US-0189 QSOs all from QRZ with wrong ADIF |

## Root Cause

The QRZ logbook contains QSOs with incorrect `MY_SIG_INFO` and `MY_POTA_REF` fields set to `US-0189` when they should be `US-12740`. This is **upstream data corruption** - either:
1. User uploaded to QRZ with wrong park reference originally
2. QRZ data was edited/corrupted
3. Another logging app uploaded incorrect data

Carrier Wave correctly imports what QRZ provides. The bug is in the source data, not the import logic.

## Resolution

**For this user:**
1. Fix the park references in QRZ logbook directly
2. Clear Carrier Wave data and re-sync from QRZ
3. Or: Manually edit the 290 affected QSOs in Carrier Wave

**Feature consideration:**
- Add bulk park reference editing to make fixing this easier
- Add a "repair" feature to re-assign park refs for a date range

## Lessons Learned

1. When users report wrong data, check `importSource` first to identify the data origin
2. Raw ADIF examination is essential for debugging import issues
3. "I've never been there" strongly suggests upstream data issue rather than app bug
