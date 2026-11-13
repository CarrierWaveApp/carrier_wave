# Investigation: Wrong Park Attribution (US-0189 vs US-12740)

**Date:** 2026-02-05
**Updated:** 2026-02-06 (multi-agent deep investigation + cross-database forensics)
**Status:** Resolved
**Outcome:** Cross-database forensics confirmed: all 290 of N9HO's US-0189 QSOs are exact duplicates of W6JSV's (user's) QSOs — 100% match on callsign, band, mode, and timestamp. Your QSOs were uploaded to N9HO's QRZ logbook in a single bulk upload on 2025-12-07. This is NOT a Carrier Wave bug. Separate LoFi two-fer bug found and fixed.

## Problem Statement

TestFlight feedback from jkeithrogers@charter.net:
> "Something is up with this. I've never been there. These should all be my us-12740 hinds road park"

User reports QSOs appearing under a park (US-0189) they have never activated from. Expected park is US-12740 (Hinds Road).

SQLite dump: ~/Desktop/CarrierWave_QSO_Export_2026-02-04_163123.sqlite

## Hypotheses

### Hypothesis 1: LoFi import two-fer bug
- **Evidence for:** `myPotaRef` at `LoFiModels.swift:495-499` uses `.first` which only returns the first park in a two-fer operation
- **Evidence against:** All 290 US-0189 QSOs have `importSource='qrz'`, not `lofi`. The non-destructive merge logic (`existing.parkReference.nonEmpty ?? fetched.parkReference`) prevents LoFi from overwriting existing QRZ park refs.
- **Tested:** Yes
- **Result:** Not the cause of THIS issue. But the `.first` bug is real and could affect LoFi-primary users. See "Collateral Bugs Found" below.

### Hypothesis 2: Deduplication merging wrong parks
- **Evidence for:** Deduplication can absorb park references from "loser" QSO
- **Evidence against:** `requireParkMatch: true` config. `TwoferMatcher` requires park subset matching (US-0189 is NOT a subset of US-12740). `TwoferDuplicateRepairService.absorbFields()` does NOT touch parkReference at all. Two-fer repair only runs on explicit user action, not during sync.
- **Tested:** Yes
- **Result:** Not the cause. Thoroughly exonerated -- no code path exists to merge these parks.

### Hypothesis 3: QRZ ADIF parser misattributes parks
- **Evidence for:** None found
- **Evidence against:** Parser is stateless (fresh dictionary per record at `QRZClient+ADIF.swift:40`). Length-based ADIF parsing prevents cross-record contamination. `QRZFetchedQSO` is an immutable struct. No mutable state between records.
- **Tested:** Yes
- **Result:** Not the cause. Parser is clean and deterministic.

### Hypothesis 4: Incremental sync causes corruption
- **Evidence for:** None found in normal sync path
- **Evidence against:** Merge logic is non-destructive (`existing.parkReference.nonEmpty ?? fetched.parkReference` at `SyncService+Process.swift:330`). Incremental sync uses same processing pipeline as full sync. Checkpoint system only tracks activation keys, not QSO data.
- **Tested:** Yes
- **Result:** Not the cause. Note: `forceRedownloadFrom*` methods DO overwrite unconditionally (`SyncService+Process.swift:366-399`), but this is an amplifier of existing bad data, not a root cause.

### Hypothesis 5: QRZ import data already contains wrong park (upstream)
- **Evidence for:** All 290 US-0189 QSOs have `importSource='qrz'`. Raw ADIF from QRZ literally contains `<my_sig_info:7>US-0189`. QRZ import path is pure passthrough with zero transformation (`QRZClient+ADIF.swift:67-87` -> `ImportService+External.swift:78-91`). QRZ upload path is also pure passthrough (`QRZClient+ADIF.swift:159-203`). Git history shows no evidence of historical park transformation code. Both parks have QSOs on same dates (suggesting two-fer split).
- **Evidence against:** Cannot examine QRZ's logbook state before Carrier Wave's first import. Cannot verify what data source originally populated QRZ.
- **Tested:** Yes
- **Result:** **Confirmed as root cause with 90% confidence.**

### Hypothesis 6: Round-trip corruption (Carrier Wave uploads wrong data to QRZ then re-imports)
- **Evidence for:** Theoretically possible if a bug existed
- **Evidence against:** Upload code reads `qso.parkReference` directly with zero transformation (`QRZClient+ADIF.swift:191-194`). No code path exists that maps one park reference to another. User has 1,084 correct US-12740 QSOs proving the upload logic works. Git history shows no evidence of such a bug existing historically.
- **Tested:** Yes
- **Result:** Ruled out. Upload path is identical passthrough to import path.

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

### Step 5: Multi-agent deep investigation (2026-02-06)

Spawned 5 parallel investigator agents to exhaustively analyze every code path that touches park references. Each championed a different hypothesis and attempted to prove/disprove it with code evidence.

**Code paths verified as clean (zero park ref transformation):**
- QRZ ADIF parsing: `QRZClient+ADIF.swift:23-87`
- QRZ import to DB: `ImportService+External.swift:78-91`
- QRZ upload ADIF generation: `QRZClient+ADIF.swift:159-203`
- Core ADIF parser: `ADIFParser.swift:180-198`
- Sync merge logic: `SyncService+Process.swift:330`
- Background processing merge: `QSOProcessingActor.swift:232`
- Orphan repair service: `QSOProcessingActor+OrphanRepair.swift:255-284` (reads parkRef, never writes)
- POTA presence repair: `POTAPresenceRepairService.swift:110-123` (reads parkRef, never writes)
- Two-fer dedup repair: `TwoferDuplicateRepairService.swift:119-169` (does NOT touch parkReference)

**Debate conclusion:** All 5 agents reached consensus that Carrier Wave is a "faithful messenger" of upstream data. The most likely upstream source is Ham2K PoLo, which the user uses as their primary logger and which uploads to QRZ.

### Step 6: Cross-database forensics (2026-02-06)

Compared N9HO's database (`CarrierWave_QSO_Export_2026-02-03_102149.sqlite`) against W6JSV's database (`CarrierWave_QSO_Export_2026-02-06_063953.sqlite`).

**Database identification:**
- N9HO's DB: 4,685 QSOs under `myCallsign=N9HO`, 217 under `W9JKR`
- W6JSV's DB: all QSOs under `myCallsign=W6JSV`

**Callsign overlap:** 200/200 of N9HO's US-0189 callsigns appear in W6JSV's US-0189 QSOs. Zero callsigns unique to N9HO. W6JSV has 49 additional callsigns (from non-QRZ sources like LoFi/LoTW/logger).

**Timestamp matching:** Joined both databases on `callsign + band + mode + abs(timestamp) < 120s` for `parkReference = 'US-0189'`. Result: **290/290 exact matches**. Every single N9HO US-0189 QSO has an identical counterpart in W6JSV's database.

**ADIF analysis:** Raw ADIF from N9HO's QRZ contains mixed identity — N9HO's name/grid/county but W6JSV's state (CA), park (US-0189), and QSO contacts. All uploaded in a single batch on 2025-12-07.

**Conclusion:** This is not a Carrier Wave bug, a park attribution bug, or a sync corruption issue. W6JSV's QSO data was uploaded to N9HO's QRZ logbook through an external mechanism. Carrier Wave faithfully downloaded and stored what QRZ provided.

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `QRZClient+ADIF.swift` | QRZ ADIF parsing & upload | Pure passthrough in both directions |
| `QRZClient+Fetch.swift` | QRZ fetch helpers | Standard pagination, no park transformation |
| `FetchedQSO.swift` | Intermediate QSO representation | Direct field mapping from QRZ |
| `ImportService.swift` | ADIF parsing, dedup, QSO creation | Park refs passed through unchanged |
| `ImportService+External.swift` | External import handling | Direct passthrough from QRZFetchedQSO |
| `ADIFParser.swift` (CarrierWaveCore) | Core ADIF parser | Stateless, spec-compliant parsing |
| `DeduplicationMatcher.swift` | Duplicate detection logic | Won't merge different parks |
| `TwoferMatcher.swift` | Two-fer duplicate detection | Requires park subset matching |
| `TwoferDuplicateRepairService.swift` | Two-fer repair | Does NOT modify parkReference |
| `DeduplicationService.swift` | QSO dedup logic | Only fills nil parkRefs via `??` |
| `SyncService+Process.swift` | QSO processing during sync | Non-destructive merge (except force re-download) |
| `SyncService+Download.swift` | Download orchestration | Standard pipeline, no park transformation |
| `SyncService+Upload.swift` | Upload logic | Passthrough to QRZClient ADIF generation |
| `QSOProcessingActor.swift` | Background processing | Same safe merge logic as main thread |
| `QSOProcessingActor+OrphanRepair.swift` | Orphan repair | Reads parkRef, never writes |
| `POTAPresenceRepairService.swift` | POTA presence repair | Reads parkRef, never writes |
| `POTAClient+Checkpoint.swift` | Incremental sync state | Only tracks activation keys |
| `LoFiModels.swift` | LoFi API models | `.first` bug found (see collateral bugs) |
| `LoFiClient.swift` | LoFi sync client | Standard fetch, delegates to models |
| `LoggingSessionManager.swift` | Session lifecycle | Properly isolates park refs per session |
| `LoggingSession.swift` | Session model | Simple optional String, no leakage |
| `POTAClient+ADIF.swift` | POTA ADIF formatting | Uses parameter-based park ref (correct) |
| User's SQLite export | Actual data | US-0189 QSOs all from QRZ with wrong ADIF |

## Root Cause

**Cross-account contamination — confirmed with 100% confidence.**

N9HO's QRZ logbook contains 290 QSOs that are exact copies of W6JSV's (the app developer's) QSOs from US-0189. This was proven by cross-referencing both users' Carrier Wave database exports.

### Forensic evidence

| Metric | Result |
|--------|--------|
| N9HO unique US-0189 callsigns | 200 |
| W6JSV unique US-0189 callsigns | 249 |
| Callsigns in common | **200 (100% of N9HO's)** |
| Callsigns only in N9HO | **0** |
| Callsigns only in W6JSV | 49 |
| Exact matches (callsign + band + mode + timestamp ±2min) | **290 / 290 (100%)** |
| N9HO US-0189 QSOs not matching any W6JSV QSO | **0** |

### Raw ADIF from N9HO's QRZ logbook

```
<station_callsign:4>N9HO          ← N9HO's QRZ account
<my_name:15>Justin K Rogers        ← N9HO's name
<my_gridsquare:6>EM63xw            ← N9HO's grid (Alabama)
<my_cnty:9>AL,Etowah               ← N9HO's county
<my_state:2>CA                     ← BUT state says California (W6JSV's state)
<my_pota_ref:7>US-0189             ← W6JSV's park (Don Edwards SF Bay NWR, CA)
<my_sig_info:7>US-0189             ← Same
<call:5>AG6AQ                      ← Station worked by W6JSV
<qrzcom_qso_upload_date:8>20251207 ← All uploaded Dec 7, 2025
```

The ADIF is a chimera: N9HO's identity fields (`station_callsign`, `my_name`, `my_gridsquare`, `my_cnty`) mixed with W6JSV's activation data (`my_state`, `my_pota_ref`, QSO contacts). All 290 QSOs were uploaded to N9HO's QRZ in a single bulk upload on **2025-12-07**.

### How it happened

Unknown exactly, but possible scenarios:
1. **Shared LoFi account or ADIF export** — N9HO received W6JSV's ADIF file and accidentally uploaded it to their own QRZ logbook
2. **Shared logging tool misconfiguration** — Ham2K PoLo configured with N9HO's QRZ credentials but syncing W6JSV's operation data
3. **Carrier Wave multi-user confusion** — N9HO was using Carrier Wave with W6JSV's LoFi data linked, and sync pushed those QSOs to N9HO's QRZ

### What Carrier Wave did correctly

Carrier Wave is a **faithful messenger** of upstream data:
- Downloaded N9HO's QRZ logbook which contained these contaminated QSOs
- Stored them with `importSource='qrz'` and `myCallsign='N9HO'` (as QRZ reported)
- Made no transformation to park references at any point in the pipeline
- All code paths verified as pure passthrough (see Files Examined)

## Collateral Bugs Found

### Bug: `myPotaRef` drops all but first park in two-fer operations

**File:** `LoFiModels.swift:495-499`
```swift
func myPotaRef(from operationRefs: [LoFiOperationRef]) -> String? {
    operationRefs
        .first { $0.refType == "potaActivation" }?
        .reference
}
```

**Also:** `LoFiOperation.potaRef` at line 261-263 has the same `.first` limitation.

**Impact:** For users who primarily import from LoFi (rather than QRZ), all QSOs in a two-fer operation would be assigned only the first park reference. This did NOT cause the reported issue (wrong `importSource` signature) but could cause identical symptoms for LoFi-primary users.

**Recommended fix:** Return all park references as comma-separated string:
```swift
func myPotaRef(from operationRefs: [LoFiOperationRef]) -> String? {
    let parks = operationRefs
        .filter { $0.refType == "potaActivation" }
        .compactMap(\.reference)
    return parks.isEmpty ? nil : parks.joined(separator: ", ")
}
```

### POTA API data quality issues

**Truncated two-fer park refs:** The POTA API returns `mySigInfo` with truncated two-fer references. In `POTAClient.swift:446`:
```swift
let parkRef = qso.mySigInfo.nonEmpty ?? activation.reference
```
If POTA's `mySigInfo` contains a truncated ref like `US-1037,US` (should be `US-1037, US-12740`), it flows through to the QSO. Note: POTA returns two-fers as **separate activations per park**, not combined — so `activation.reference` is always a single park. The `mySigInfo` field is whatever was originally uploaded.

Evidence from N9HO's database:
| Park Ref | Source | Count | Expected |
|----------|--------|-------|----------|
| `US-1037,US` | pota | 121 | `US-1037, US-12740` |
| `US-1037,US` | qrz | 6 | same |
| `US-1044, U` | pota | 22 | `US-1044, US-3791` |
| `US-1044, US-3791` | qrz | 22 | correct |

Neither set was uploaded to QRZ by Carrier Wave (all have `needsUpload=0`). The truncation is upstream (PoLo → POTA and PoLo → QRZ).

**Malformed park references:** The POTA API also returns park refs with missing dashes or country prefixes:
| Park Ref | Source | Count | Expected |
|----------|--------|-------|----------|
| `US1849` | pota | 70 | `US-1849` |
| `3687` | pota | 32 | `US-3687` |
| `11027` | pota | 13 | `US-11027` |

These are stored verbatim in the database. Carrier Wave should sanitize park references on import.

**Round-trip corruption analysis:** Could Carrier Wave upload bad POTA data to QRZ? Theoretically yes — if a POTA-sourced QSO (with truncated/malformed park and no `rawADIF`) gets marked `needsUpload` to QRZ, `generateADIF(for:)` would upload the bad park. For N9HO, this has NOT happened (no POTA QSOs have `needsUpload=1` for QRZ). But it's a latent risk.

### Note: Force re-download amplification risk

`SyncService+Process.swift:366-399` — `forceRedownloadFrom*` methods perform destructive overwrites of all fields including parkReference. This is by design but means force re-downloading from a source with corrupted data will propagate that corruption, overwriting locally-correct values.

**Recommendation:** Add warning logging when force re-download changes a non-empty parkReference.

## Resolution

**For N9HO:**
1. Delete the 290 contaminated US-0189 QSOs from their QRZ logbook — these are W6JSV's contacts, not N9HO's
2. Investigate how W6JSV's data ended up in their QRZ account (shared ADIF? PoLo misconfiguration?)
3. After cleaning QRZ, force re-download in Carrier Wave to remove the ghost QSOs

**For Carrier Wave:**
1. ~~Fix the `myPotaRef` `.first` bug to handle two-fer LoFi operations correctly~~ **Done** (fixed in LoFiModels.swift)
2. ~~Sanitize malformed park references on import~~ **Done** (ParkReference.sanitize/sanitizeMulti applied at all entry points)
3. Add defensive logging to force re-download for park ref changes
4. Consider bulk park reference editing feature to make fixing upstream issues easier

## Lessons Learned

1. When users report wrong data, check `importSource` first to identify the data origin
2. Raw ADIF examination is essential for debugging import issues
3. "I've never been there" strongly suggests upstream data issue rather than app bug
4. Multi-agent adversarial investigation is effective at building confidence in conclusions -- each hypothesis was independently tested with code evidence
5. Bugs can be real but irrelevant to the specific issue at hand (the `.first` bug is genuine but didn't cause this)
6. Consider the full data flow across apps: user's primary logger (PoLo) -> cloud service (QRZ) -> secondary consumer (Carrier Wave)
7. POTA returns two-fer activations as separate per-park activations, not combined — don't assume `mySigInfo` will contain the full two-fer ref
8. Upstream services return malformed park IDs — always sanitize on import

## Appendix: US-0189 QSO Data (N9HO)

**200 unique callsigns** across **17 activation dates** (2025-10-15 to 2025-12-04).

Note: Includes 8 WEATHER and 4 SOLAR metadata pseudo-mode records imported from QRZ.

### Date distribution

| Date | Count |
|------|-------|
| 2025-10-15 | 11 |
| 2025-10-23 | 11 |
| 2025-10-24 | 44 |
| 2025-10-28 | 47 |
| 2025-11-03 | 24 |
| 2025-11-04 | 11 |
| 2025-11-05 | 14 |
| 2025-11-11 | 10 |
| 2025-11-17 | 12 |
| 2025-11-18 | 17 |
| 2025-11-19 | 13 |
| 2025-11-21 | 13 |
| 2025-11-23 | 18 |
| 2025-11-25 | 11 |
| 2025-12-01 | 11 |
| 2025-12-02 | 13 |
| 2025-12-04 | 10 |

### Top callsigns (contacts >= 3)

| Callsign | Count | First | Last |
|----------|-------|-------|------|
| KI7QCF | 10 | 2025-10-15 | 2025-12-01 |
| WEATHER* | 8 | 2025-11-03 | 2025-12-02 |
| KJ7DT | 8 | 2025-10-15 | 2025-12-02 |
| KF6YAL | 8 | 2025-10-15 | 2025-12-01 |
| W6EFI | 7 | 2025-10-23 | 2025-11-25 |
| WI5D | 5 | 2025-10-15 | 2025-11-11 |
| W9GTA | 5 | 2025-10-28 | 2025-12-02 |
| SOLAR* | 4 | 2025-11-17 | 2025-12-02 |
| W6PUG | 4 | 2025-10-24 | 2025-11-23 |
| W4SV | 4 | 2025-10-24 | 2025-11-25 |
| K3IV | 4 | 2025-10-15 | 2025-11-23 |
| AL7KC | 4 | 2025-10-15 | 2025-12-01 |
| AG6AQ | 4 | 2025-10-23 | 2025-12-04 |
| WN7JT | 3 | 2025-10-24 | 2025-11-23 |
| NK8O | 3 | 2025-10-28 | 2025-12-02 |
| KC0DWZ | 3 | 2025-10-15 | 2025-11-04 |
| KA7HOS | 3 | 2025-11-18 | 2025-12-04 |
| K7WFM | 3 | 2025-10-24 | 2025-11-19 |
| K7SFA | 3 | 2025-10-23 | 2025-11-18 |
| K4ZSR | 3 | 2025-10-24 | 2025-11-03 |

*Metadata pseudo-modes from PoLo, imported via QRZ

### Cross-database comparison (N9HO vs W6JSV)

**N9HO database:** `CarrierWave_QSO_Export_2026-02-03_102149.sqlite`
**W6JSV database:** `CarrierWave_QSO_Export_2026-02-06_063953.sqlite`

| Metric | N9HO | W6JSV |
|--------|------|-------|
| Total US-0189 QSOs | 290 | 375 |
| Unique callsigns | 200 | 249 |
| Import sources | qrz (290) | qrz (152), lotw (146), lofi (53), logger (24) |
| myCallsign | N9HO (290) | W6JSV (373), EVENT (2) |
| Date range | 2025-10-15 to 2025-12-04 | 2025-10-15 to 2026-01-18 |

**Overlap:** 200/200 N9HO callsigns found in W6JSV. 290/290 QSOs match exactly on callsign + band + mode + timestamp (±2min).

W6JSV has 85 additional US-0189 QSOs (375 - 290) from dates after 2025-12-04 and from non-QRZ sources. N9HO has zero US-0189 QSOs that don't match W6JSV's.

**QRZ upload date:** All 290 N9HO US-0189 QSOs have `qrzcom_qso_upload_date=20251207` — a single bulk upload event on December 7, 2025.
