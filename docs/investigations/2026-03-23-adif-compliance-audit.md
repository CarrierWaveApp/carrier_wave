# ADIF 3.1.7 Compliance Audit

**Date:** 2026-03-23
**Scope:** All ADIF parsing, export, and upload code across CarrierWave, CarrierWaveCore, CarrierWaveData, and CWSweep
**Reference:** ADIF 3.1.7 specification (https://adif.org.uk/317/ADIF_317.htm) with service integration appendix

## Executive Summary

Overall ADIF handling is solid. Field names, date/time formats, and record structure are correct across the board. Found **10 issues** (2 high, 3 medium, 5 low) and confirmed the reported QTH/grid bug does not exist in current code.

---

## Issues Found

### 1. FT4 exported as standalone MODE instead of MFSK+SUBMODE (HIGH)

**File:** `CarrierWaveCore/Sources/CarrierWaveCore/ModeEquivalence.swift:123-134`

Per ADIF 3.1.7, FT4 is a **submode of MFSK** — the correct encoding is `<MODE:4>MFSK<SUBMODE:3>FT4`. Currently `adifModeSubmode("FT4")` returns `("FT4", nil)`, so all FT4 QSOs are exported with `<MODE:3>FT4` and no SUBMODE.

This affects every export and upload path that uses `ModeEquivalence.adifModeSubmode()`: QRZ, POTA, activation ADIF, and full log export. ClubLog and eQSL don't call this function, so they also export bare `FT4`.

**Practical impact:** Most services accept bare FT4 as a de facto standard, but loggers that strictly follow the spec (and the spec itself) say MFSK+FT4. Any app importing our ADIF that only checks MODE will see "FT4" and likely handle it, but apps that check the mode table may flag it.

**Fix:** Add `case "FT4": return ("MFSK", "FT4")` to `adifModeSubmode()`. Import side already handles this correctly — `ADIFParser.buildRecord` prefers SUBMODE over MODE, so importing `MFSK+FT4` from other apps already works.

### 2. eQSL inbox download RST fields are inverted (HIGH)

**File:** `CarrierWave/Services/EQSLClient+Helpers.swift:97-98`

Per the ADIF service integration notes, eQSL's InBox download inverts RST fields: `RST_SENT` in the downloaded record contains what the **other station** sent (which is your received report), and `RST_RCVD` contains what they received (which is your sent report).

The current parser maps them directly without swapping:
```swift
rstSent: fields["rst_sent"],      // Actually their RST_SENT = our RST_RCVD
rstReceived: fields["rst_rcvd"],  // Actually their RST_RCVD = our RST_SENT
```

This means when eQSL data merges into existing QSOs, RST values get swapped.

**Fix:** Swap the mapping in `parseADIFRecord`:
```swift
rstSent: fields["rst_rcvd"],      // Their RST_RCVD = what we sent them
rstReceived: fields["rst_sent"],  // Their RST_SENT = what they sent us
```

### 3. `QRZ_QSO_UPLOAD_STATUS` is not a valid ADIF field (MEDIUM)

**Files:**
- `CarrierWave/Services/ADIFExportService.swift:376`
- `CarrierWaveData/Sources/CarrierWaveData/FullADIFExportActor.swift:441`

The standard ADIF 3.1.7 field is `QRZCOM_QSO_UPLOAD_STATUS`. `QRZ_QSO_UPLOAD_STATUS` is not in the spec. Other applications importing these ADIF files will ignore this field.

**Fix:** Change to `QRZCOM_QSO_UPLOAD_STATUS` in both export paths.

### 4. Contest fields missing from all ADIF exports (MEDIUM)

**Files:**
- `CarrierWave/Services/ADIFExportService.swift` (no contest fields)
- `CarrierWaveData/Sources/CarrierWaveData/FullADIFExportActor.swift` (no contest fields)
- All per-service upload generators (QRZ, POTA, ClubLog, eQSL)

The QSO model has `contestName`, `contestSerialSent`, `contestSerialReceived`, `contestExchangeSent`, and `contestExchangeReceived`, but none of the ADIF export paths write the corresponding fields:

| QSO Property | ADIF Field |
|---|---|
| `contestName` | `CONTEST_ID` |
| `contestSerialSent` | `STX` |
| `contestSerialReceived` | `SRX` |
| `contestExchangeSent` | `STX_STRING` |
| `contestExchangeReceived` | `SRX_STRING` |

`FullExportQSOSnapshot` also doesn't capture these fields from the QSO model. This means contest QSOs exported from Carrier Wave lose all exchange data.

**Fix:** Add contest fields to `FullExportQSOSnapshot` and both export paths. At minimum, the full log export should include them. Per-service uploads may not need them (ClubLog and QRZ would benefit).

### 5. Inconsistent ADIF_VER across export paths (MEDIUM)

| Location | ADIF_VER |
|----------|----------|
| `ADIFExportService.swift` (POTA activation export) | 3.1.6 |
| `FullADIFExportActor.swift` (full log export) | 3.1.6 |
| `PendingUploadExporter.swift` | 3.1.6 |
| `POTAClient+ADIF.swift` (POTA upload) | **3.1.5** |
| `EQSLClient+Helpers.swift` (eQSL upload) | **3.1.4** |

The current spec is 3.1.7. The eQSL upload claims 3.1.4 while using fields introduced in 3.1.5+ (`MY_POTA_REF`, `POTA_REF`).

**Fix:** Standardize to `3.1.7` everywhere, or at minimum ensure no export claims a version older than the features it uses.

### 6. ClubLog and eQSL uploads don't split MODE/SUBMODE (LOW)

**Files:**
- `CarrierWave/Services/ClubLogClient+Helpers.swift:57`
- `CarrierWave/Services/EQSLClient+Helpers.swift:150`

These two upload generators write `MODE` directly from `qso.mode` without calling `ModeEquivalence.adifModeSubmode()`. If the QSO stores `USB`, they emit `<MODE:3>USB` — technically invalid per ADIF which requires `<MODE:3>SSB<SUBMODE:3>USB`.

The QRZ, POTA, activation export, and full export paths all correctly use `ModeEquivalence.adifModeSubmode()`.

**Fix:** Add `ModeEquivalence.adifModeSubmode()` to `ClubLogClient.generateADIF()` and `EQSLClient.generateADIF()`.

### 7. ClubLog and eQSL parsers uppercase BAND (should be lowercase) (LOW)

**Files:**
- `CarrierWave/Services/ClubLogClient+Helpers.swift:146`
- `CarrierWave/Services/EQSLClient+Helpers.swift:93`

Both parsers store `band.uppercased()` (e.g., `20M`), but ADIF band enumeration values are lowercase (e.g., `20m`). The core `ADIFParser` and QRZ parser correctly use `.lowercased()`.

**Practical impact:** Could cause deduplication mismatches if a QSO arrives from ClubLog/eQSL with `20M` and from QRZ with `20m` — the deduplication key includes band and would not match.

**Fix:** Change to `band.lowercased()` in both parsers.

### 8. `formatField` uses character count instead of byte count (LOW)

**Files:** All `formatField` implementations across the codebase.

ADIF spec says LENGTH is the **byte count**, not character count. For pure ASCII this is identical, but multi-byte UTF-8 characters would produce wrong lengths. The `FullADIFExportActor` mitigates this with `asciiSafe()` transliteration; other export paths do not sanitize.

**Practical risk:** Low — callsigns, bands, modes, grid squares are all ASCII. Only NAME, QTH, COUNTRY, and COMMENT could contain non-ASCII.

**Fix:** Either ASCII-sanitize in all export paths, or use `.utf8.count` instead of `.count`.

### 9. QRZ upload missing contacted-station metadata fields (LOW)

**File:** `CarrierWave/Services/QRZClient+ADIF.swift:107-158`

The QRZ upload includes the required fields (CALL, STATION_CALLSIGN, QSO_DATE, TIME_ON, BAND, MODE) and useful fields (FREQ, RST_SENT, RST_RCVD, OPERATOR, MY_GRIDSQUARE, GRIDSQUARE, SIG/SIG_INFO, COMMENT). However, it omits several contacted-station fields that are available on the QSO model and included in other export paths:

| Field | QSO Property | In QRZ Upload? | In Full Export? |
|-------|-------------|----------------|-----------------|
| DXCC | `qso.dxcc` | No | Yes |
| COUNTRY | `qso.country` | No | Yes |
| STATE | `qso.state` | No | Yes |
| NAME | `qso.name` | No | Yes |
| QTH | `qso.qth` | No | Yes |
| TX_PWR | `qso.power` | No | Yes |

Since QRZ is lossless (preserves all uploaded fields), including these would mean the data round-trips correctly. Currently they're lost on upload and only recovered if QRZ's own lookup populates them on download.

**Fix:** Add DXCC, COUNTRY, STATE, NAME, QTH, and TX_PWR to `QRZClient.generateADIF()`.

### 10. LoTW parser doesn't use length-based field extraction (LOW)

**File:** `CarrierWave/Services/LoTWClient+Parsing.swift:53-63`

The `parseHeaderField` and `extractField` methods use regex `<FIELD:(\d+)>([^<]*)` which reads up to the next `<` instead of reading exactly LENGTH bytes. Works in practice because LoTW data is clean, but technically non-compliant.

The core `ADIFParser` in CarrierWaveCore correctly uses length-based extraction.

**Fix:** Use `ADIFParser.extractField()` or `ADIFParser.extractFields()` from CarrierWaveCore instead of the custom regex. Also removes duplicated parsing logic.

---

## Compliant Patterns (Things Done Right)

### Parsing
- Case-insensitive field names (`ADIFParser.parseFields()` lowercases all field names)
- Length-based value extraction in core parser (reads exactly LENGTH bytes after `>`)
- `<EOH>` handling: all parsers correctly skip header content
- Unknown fields ignored (forward compatibility)
- SUBMODE preference on import: all download parsers (QRZ, ClubLog, eQSL, LoTW) prefer SUBMODE over MODE — correctly handles other apps encoding FT4 as MFSK+FT4
- Metadata pseudo-modes filtered: both export paths correctly exclude WEATHER/SOLAR/NOTE

### Export Field Formatting
- **QSO_DATE:** `yyyyMMdd` — correct (Type D)
- **TIME_ON:** `HHmmss` (6-digit) in most exporters, `HHmm` (4-digit) in QRZ upload — both valid per spec
- **FREQ:** MHz with 6 decimal places — correct (Number type, in MHz)
- **BAND:** Lowercase with unit (e.g., `20m`) — matches spec enumeration
- **CREATED_TIMESTAMP:** `yyyyMMdd HHmmss` — correct
- **RST fields:** String type — correct (spec says String to support `59+`)
- **DXCC:** Integer — correct
- **TX_PWR:** Watts as Number — correct
- **GRIDSQUARE/MY_GRIDSQUARE:** Uppercased — valid per spec (case-insensitive)

### POTA Fields
- MY_SIG + MY_SIG_INFO + MY_POTA_REF: triple-written for maximum compatibility (POTA currently uses SIG/SIG_INFO mechanism, but dedicated fields are the future direction)
- SIG + SIG_INFO + POTA_REF: same triple pattern for contacted station's park
- QSLMSG: informational field with park reference
- Park references stripped from COMMENT to prevent double-counting

### Station Fields
- STATION_CALLSIGN + OPERATOR: both emitted — correct per spec and required by QRZ
- LOTW_QSL_RCVD + LOTW_QSLRDATE: correct field names and date format

### APP Fields
- Format `APP_CARRIERWAVE_*` matches PROGRAMID — correct per spec
- Used for app-specific metadata (import source, activity log flag, session ID)

### Import Robustness
- `<EOR>` splitting handles both `<eor>` and `<EOR>` cases
- Missing fields gracefully return nil
- Timestamp parsing handles both 4-digit and 6-digit TIME_ON
- APP_LoTW_MODE fallback when standard MODE absent (LoTW quirk)
- APP_LoTW_OWNCALL fallback when STATION_CALLSIGN missing (LoTW quirk)

### Service-Specific Required Fields

Verified each upload path includes all required fields per service:

| Service | Required | Status |
|---------|----------|--------|
| QRZ.com | CALL, STATION_CALLSIGN, QSO_DATE, TIME_ON, BAND, MODE | All present |
| POTA | CALL, QSO_DATE, TIME_ON, BAND, MODE | All present |
| ClubLog | CALL, QSO_DATE, TIME_ON, BAND/FREQ, MODE | All present |
| eQSL | CALL, MODE, QSO_DATE, TIME_ON, BAND/FREQ | All present |

---

## Observations (Not Bugs)

1. **`<EOR>` case sensitivity in core parser:** `ADIFParser.parse()` splits on `<eor>` then `<EOR>` via `flatMap`. Could miss mixed-case like `<Eor>`. The eQSL parser uses a proper case-insensitive regex. Low practical risk.

2. **Frequency precision inconsistency:** QRZ/POTA/activation exports use `%.6f` (6 decimal places), ClubLog and eQSL use `%.4f` (4 decimal places). Both valid per spec but inconsistent.

3. **Missing PROGRAMVERSION in eQSL header:** `EQSLClient.buildADIFForUpload()` omits `PROGRAMVERSION`. Not required by spec but included everywhere else.

4. **No SOTA_REF in per-service uploads:** QRZ and ClubLog uploads don't include `SOTA_REF` even if present on the QSO. Only activation export and full export include it. SOTA doesn't have a dedicated upload service here, so this is acceptable.

5. **LoTW strips most fields:** LoTW only stores call/date/time/mode/band/freq/prop/sat. All other fields uploaded to LoTW are discarded. Our upload doesn't need to include them, but it's harmless that we do.

6. **QRZ is lossless:** QRZ.com preserves all uploaded fields including unknown ones. This makes QRZ a good "backup" of the full ADIF record. Our QRZ upload includes most useful fields.

7. **ClubLog DXCC override:** ClubLog recalculates DXCC from its own database, ignoring our value. Our upload includes DXCC anyway, which is fine — ClubLog just ignores it.

8. **QSO matching time tolerances:** Services use different windows (LoTW ±30min, QRZ ±30min, eQSL ±60min, ClubLog ±15min). Our deduplication uses 120-second windows, which is much tighter. This is correct — we want tight local dedup while services handle their own broader matching.

---

## Investigated: QTH Set to Grid Bug Report (NOT CONFIRMED)

**Report:** QTH field is being set to the other person's grid square instead of their grid field.

**Finding:** The bug does not exist in current code. Every code path was traced:

- `CallsignInfo` has separate `.qth` (city) and `.grid` (Maidenhead) fields
- Logger: `lookupResult?.qth` -> `qso.qth`, `lookupResult?.grid` -> `qso.theirGrid` (separate params)
- Post-log enrichment: `qso.theirGrid = info.grid` and `qso.qth = info.qth` independently
- ADIF parser: `GRIDSQUARE` -> `gridsquare`, `QTH` -> `qth` separately
- All sync merge paths keep them distinct
- CloudKit sync maps `theirGrid` and `qth` as separate CKRecord fields
- QSO model init has separate `theirGrid:` and `qth:` parameters

**Possible explanations:**
1. Bug existed in older version and was already fixed — affected QSOs remain with stale data
2. External app (HAMRS, N3FJP, etc.) wrote grid into QTH field in its ADIF export, Carrier Wave imported it faithfully
3. Specific to a service not yet identified — checking `importSourceRawValue` on affected QSOs would narrow it down

---

## Files Audited

### Parsing
- `CarrierWaveCore/Sources/CarrierWaveCore/ADIFParser.swift`
- `CarrierWave/Services/LoTWClient+Parsing.swift`
- `CarrierWave/Services/QRZClient+ADIF.swift` (parseADIFRecords)
- `CarrierWave/Services/ClubLogClient+Helpers.swift` (parseADIFRecords)
- `CarrierWave/Services/EQSLClient+Helpers.swift` (parseADIFRecords)
- `CWSweep/CWSweep/Services/Import/ADIFImportActor.swift`

### Export / Upload
- `CarrierWave/Services/ADIFExportService.swift` (POTA activation export)
- `CarrierWave/Services/ADIFExportService+Split.swift`
- `CarrierWaveData/Sources/CarrierWaveData/FullADIFExportActor.swift` (full log export)
- `CarrierWave/Services/PendingUploadExporter.swift`
- `CarrierWave/Services/QRZClient+ADIF.swift` (generateADIF)
- `CarrierWave/Services/POTAClient+ADIF.swift`
- `CarrierWave/Services/ClubLogClient+Helpers.swift` (generateADIF)
- `CarrierWave/Services/EQSLClient+Helpers.swift` (generateADIF, buildADIFForUpload)

### Mode Mapping
- `CarrierWaveCore/Sources/CarrierWaveCore/ModeEquivalence.swift` (adifModeSubmode)

### Import / Sync / Merge
- `CarrierWave/Services/ImportService.swift`
- `CarrierWave/Services/ImportService+External.swift`
- `CarrierWave/Services/QSOProcessingActor+Merge.swift`
- `CarrierWave/Services/FetchedQSO.swift`
- `CarrierWave/Services/SyncService+ProcessLegacy.swift`

### Model / CloudKit
- `CarrierWaveData/Sources/CarrierWaveData/Models/QSO.swift`
- `CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncEngine+FieldApplication.swift`
- `CarrierWaveData/Sources/CarrierWaveData/CloudSync/CKRecordMapper.swift`

### Callsign Lookup -> QSO Flow
- `CarrierWave/Models/CallsignInfo.swift`
- `CarrierWave/Services/CallsignLookupService.swift`
- `CarrierWave/Services/CallsignLookupService+QRZ.swift`
- `CarrierWave/Services/LoggingSessionManager+QSOManagement.swift`
- `CarrierWave/Views/Logger/LoggerView+QSOLogging.swift`
- `CarrierWave/Views/Logger/LoggerView+HelperViews.swift`
- `CarrierWave/Views/ActivityLog/ActivityLogView.swift`
