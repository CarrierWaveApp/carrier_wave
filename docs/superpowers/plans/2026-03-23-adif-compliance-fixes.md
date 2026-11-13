# ADIF 3.1.7 Compliance Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all 10 ADIF compliance issues found in the 2026-03-23 audit (`docs/investigations/2026-03-23-adif-compliance-audit.md`).

**Architecture:** All changes are isolated fixes to existing code — no new files, no new abstractions. Each task targets one audit issue and can be committed independently. Tests exist in `CarrierWaveCore/Tests/CarrierWaveCoreTests/ADIFParserTests.swift` and `CarrierWaveCore/Tests/CarrierWaveCoreTests/ModeEquivalenceTests.swift`.

**Tech Stack:** Swift, SwiftData, CarrierWaveCore SPM package

---

### Task 1: Fix FT4 mode encoding (Audit Issue #1 — HIGH)

**Files:**
- Modify: `CarrierWaveCore/Sources/CarrierWaveCore/ModeEquivalence.swift:123-134`
- Test: `CarrierWaveCore/Tests/CarrierWaveCoreTests/ModeEquivalenceTests.swift`

- [ ] **Step 1: Write failing test for FT4 submode split**

Add to ModeEquivalenceTests.swift after the existing `adifModeSubmodeFM` test:

```swift
@Test("FT4 splits to MFSK + FT4")
func adifModeSubmodeFT4() {
    let result = ModeEquivalence.adifModeSubmode("FT4")
    #expect(result.mode == "MFSK")
    #expect(result.submode == "FT4")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path CarrierWaveCore --filter adifModeSubmodeFT4`
Expected: FAIL — result.mode is "FT4", not "MFSK"

- [ ] **Step 3: Implement FT4 case in adifModeSubmode**

In `ModeEquivalence.swift`, add a case to the switch in `adifModeSubmode`:

```swift
case "FT4":
    return ("MFSK", "FT4")
```

Add it between the `"LSB"` case and the `"PSK31"` case.

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --package-path CarrierWaveCore --filter ModeEquivalence`
Expected: All pass including new FT4 test

- [ ] **Step 5: Commit**

```
git add CarrierWaveCore/Sources/CarrierWaveCore/ModeEquivalence.swift CarrierWaveCore/Tests/CarrierWaveCoreTests/ModeEquivalenceTests.swift
git commit -m "fix: export FT4 as MFSK+FT4 submode per ADIF 3.1.7"
```

---

### Task 2: Fix eQSL RST field inversion (Audit Issue #2 — HIGH)

**Files:**
- Modify: `CarrierWave/Services/EQSLClient+Helpers.swift:91-105`

- [ ] **Step 1: Swap RST fields in eQSL parser**

In `EQSLClient+Helpers.swift`, in `parseADIFRecord`, change:

```swift
            rstSent: fields["rst_sent"],
            rstReceived: fields["rst_rcvd"],
```

to:

```swift
            // eQSL InBox records are from the OTHER station's perspective:
            // their RST_SENT = what they sent us = our RST_RCVD
            // their RST_RCVD = what they received from us = our RST_SENT
            rstSent: fields["rst_rcvd"],
            rstReceived: fields["rst_sent"],
```

- [ ] **Step 2: Commit**

```
git add CarrierWave/Services/EQSLClient+Helpers.swift
git commit -m "fix: swap eQSL inbox RST fields (other station's perspective)"
```

---

### Task 3: Fix QRZ upload status field name (Audit Issue #3 — MEDIUM)

**Files:**
- Modify: `CarrierWave/Services/ADIFExportService.swift:376`
- Modify: `CarrierWaveData/Sources/CarrierWaveData/FullADIFExportActor.swift:441`

- [ ] **Step 1: Fix field name in ADIFExportService**

In `ADIFExportService.swift`, in `appendConfirmationFields`, change:

```swift
fields.append(formatField("QRZ_QSO_UPLOAD_STATUS", "Y"))
```

to:

```swift
fields.append(formatField("QRZCOM_QSO_UPLOAD_STATUS", "Y"))
```

- [ ] **Step 2: Fix field name in FullADIFExportActor**

In `FullADIFExportActor.swift`, in `appendConfirmationFields`, make the same change:

```swift
fields.append(formatField("QRZ_QSO_UPLOAD_STATUS", "Y"))
```

to:

```swift
fields.append(formatField("QRZCOM_QSO_UPLOAD_STATUS", "Y"))
```

- [ ] **Step 3: Commit**

```
git add CarrierWave/Services/ADIFExportService.swift CarrierWaveData/Sources/CarrierWaveData/FullADIFExportActor.swift
git commit -m "fix: use standard QRZCOM_QSO_UPLOAD_STATUS field name per ADIF 3.1.7"
```

---

### Task 4: Add contest fields to ADIF exports (Audit Issue #4 — MEDIUM)

**Files:**
- Modify: `CarrierWaveData/Sources/CarrierWaveData/FullADIFExportActor.swift` (FullExportQSOSnapshot + record builder)
- Modify: `CarrierWave/Services/ADIFExportService.swift` (QSOExportSnapshot + record builder)

- [ ] **Step 1: Add contest fields to FullExportQSOSnapshot**

In `FullADIFExportActor.swift`, add to `FullExportQSOSnapshot`:

Properties (after `loggingSessionId`):

```swift
public let contestName: String?
public let contestSerialSent: Int?
public let contestSerialReceived: Int?
public let contestExchangeSent: String?
public let contestExchangeReceived: String?
```

In the `init(from qso: QSO)`, add after `loggingSessionId = qso.loggingSessionId`:

```swift
contestName = qso.contestName
contestSerialSent = qso.contestSerialSent
contestSerialReceived = qso.contestSerialReceived
contestExchangeSent = qso.contestExchangeSent
contestExchangeReceived = qso.contestExchangeReceived
```

- [ ] **Step 2: Add contest field export in FullADIFExportActor**

Add a new method to the `FullADIFExportActor` extension (after `appendAppFields`):

```swift
private func appendContestFields(
    to fields: inout [String],
    snapshot: FullExportQSOSnapshot
) {
    if let contestId = snapshot.contestName, !contestId.isEmpty {
        fields.append(formatField("CONTEST_ID", contestId))
    }
    if let stx = snapshot.contestSerialSent {
        fields.append(formatField("STX", String(stx)))
    }
    if let srx = snapshot.contestSerialReceived {
        fields.append(formatField("SRX", String(srx)))
    }
    if let stxStr = snapshot.contestExchangeSent,
       !stxStr.isEmpty
    {
        fields.append(formatField("STX_STRING", stxStr))
    }
    if let srxStr = snapshot.contestExchangeReceived,
       !srxStr.isEmpty
    {
        fields.append(formatField("SRX_STRING", srxStr))
    }
}
```

Call it in `buildFullRecord` before the COMMENT field:

```swift
appendContestFields(to: &fields, snapshot: snapshot)
```

- [ ] **Step 3: Add contest fields to QSOExportSnapshot (activation export)**

In `ADIFExportService.swift`, add to `QSOExportSnapshot`:

Properties (after `parkReference`):

```swift
let contestName: String?
let contestSerialSent: Int?
let contestSerialReceived: Int?
let contestExchangeSent: String?
let contestExchangeReceived: String?
```

In the `@MainActor init(from qso: QSO)`, add after `parkReference = qso.parkReference`:

```swift
contestName = qso.contestName
contestSerialSent = qso.contestSerialSent
contestSerialReceived = qso.contestSerialReceived
contestExchangeSent = qso.contestExchangeSent
contestExchangeReceived = qso.contestExchangeReceived
```

- [ ] **Step 4: Add contest field export in ADIFExportService**

Add a method (after `appendConfirmationFields`):

```swift
private func appendContestFields(
    to fields: inout [String],
    snapshot: QSOExportSnapshot
) {
    if let contestId = snapshot.contestName, !contestId.isEmpty {
        fields.append(formatField("CONTEST_ID", contestId))
    }
    if let stx = snapshot.contestSerialSent {
        fields.append(formatField("STX", String(stx)))
    }
    if let srx = snapshot.contestSerialReceived {
        fields.append(formatField("SRX", String(srx)))
    }
    if let stxStr = snapshot.contestExchangeSent, !stxStr.isEmpty {
        fields.append(formatField("STX_STRING", stxStr))
    }
    if let srxStr = snapshot.contestExchangeReceived, !srxStr.isEmpty {
        fields.append(formatField("SRX_STRING", srxStr))
    }
}
```

Call it in `buildQSORecord` before the COMMENT section:

```swift
appendContestFields(to: &fields, snapshot: snapshot)
```

- [ ] **Step 5: Commit**

```
git add CarrierWaveData/Sources/CarrierWaveData/FullADIFExportActor.swift CarrierWave/Services/ADIFExportService.swift
git commit -m "feat: include contest fields in ADIF exports (CONTEST_ID, STX, SRX, STX_STRING, SRX_STRING)"
```

---

### Task 5: Standardize ADIF_VER to 3.1.7 (Audit Issue #5 — MEDIUM)

**Files:**
- Modify: `CarrierWave/Services/ADIFExportService.swift` (two locations: `buildHeader` and `generateBulkADIF`)
- Modify: `CarrierWaveData/Sources/CarrierWaveData/FullADIFExportActor.swift`
- Modify: `CarrierWave/Services/PendingUploadExporter.swift`
- Modify: `CarrierWave/Services/POTAClient+ADIF.swift`
- Modify: `CarrierWave/Services/EQSLClient+Helpers.swift`

- [ ] **Step 1: Update all ADIF_VER strings**

Search-and-replace in each file. The values to change:

| File | Old | New |
|------|-----|-----|
| `ADIFExportService.swift` (2 locations) | `3.1.6` | `3.1.7` |
| `FullADIFExportActor.swift` | `3.1.6` | `3.1.7` |
| `PendingUploadExporter.swift` | `3.1.6` | `3.1.7` |
| `POTAClient+ADIF.swift` | `3.1.5` | `3.1.7` |
| `EQSLClient+Helpers.swift` | `3.1.4` | `3.1.7` |

- [ ] **Step 2: Add PROGRAMVERSION to eQSL header**

In `EQSLClient+Helpers.swift`, in `buildADIFForUpload`, change:

```swift
var lines = [
    "Carrier Wave eQSL Upload",
    "<ADIF_VER:5>3.1.4",
    "<PROGRAMID:11>CarrierWave",
    "<EOH>",
]
```

to:

```swift
let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
var lines = [
    "Carrier Wave eQSL Upload",
    "<ADIF_VER:5>3.1.7",
    "<PROGRAMID:11>CarrierWave",
    "<PROGRAMVERSION:\(version.utf8.count)>\(version)",
    "<EOH>",
]
```

- [ ] **Step 3: Commit**

```
git add CarrierWave/Services/ADIFExportService.swift CarrierWaveData/Sources/CarrierWaveData/FullADIFExportActor.swift CarrierWave/Services/PendingUploadExporter.swift CarrierWave/Services/POTAClient+ADIF.swift CarrierWave/Services/EQSLClient+Helpers.swift
git commit -m "fix: standardize ADIF_VER to 3.1.7 across all export paths"
```

---

### Task 6: Add MODE/SUBMODE splitting to ClubLog and eQSL uploads (Audit Issue #6 — LOW)

**Files:**
- Modify: `CarrierWave/Services/ClubLogClient+Helpers.swift:44-90`
- Modify: `CarrierWave/Services/EQSLClient+Helpers.swift:138-172`

- [ ] **Step 1: Fix ClubLog generateADIF**

In `ClubLogClient+Helpers.swift`, in `generateADIF(for:)`, change:

```swift
addField("BAND", qso.band)
addField("MODE", qso.mode)
```

to:

```swift
addField("BAND", qso.band)
let modeSubmode = ModeEquivalence.adifModeSubmode(qso.mode)
addField("MODE", modeSubmode.mode)
if let submode = modeSubmode.submode {
    addField("SUBMODE", submode)
}
```

Verify the file already imports `CarrierWaveCore` (it does — line 1).

- [ ] **Step 2: Fix eQSL generateADIF**

In `EQSLClient+Helpers.swift`, in `generateADIF(for:)`, change:

```swift
addField("CALL", qso.callsign)
addField("BAND", qso.band)
addField("MODE", qso.mode)
```

to:

```swift
addField("CALL", qso.callsign)
addField("BAND", qso.band)
let modeSubmode = ModeEquivalence.adifModeSubmode(qso.mode)
addField("MODE", modeSubmode.mode)
if let submode = modeSubmode.submode {
    addField("SUBMODE", submode)
}
```

Verify the file already imports `CarrierWaveCore` (it does — line 1).

- [ ] **Step 3: Commit**

```
git add CarrierWave/Services/ClubLogClient+Helpers.swift CarrierWave/Services/EQSLClient+Helpers.swift
git commit -m "fix: split MODE/SUBMODE in ClubLog and eQSL uploads"
```

---

### Task 7: Fix ClubLog/eQSL band case to lowercase (Audit Issue #7 — LOW)

**Files:**
- Modify: `CarrierWave/Services/ClubLogClient+Helpers.swift:146`
- Modify: `CarrierWave/Services/EQSLClient+Helpers.swift:93`

- [ ] **Step 1: Fix ClubLog parser**

In `ClubLogClient+Helpers.swift`, in `parseADIFRecord`, change:

```swift
band: band.uppercased(),
```

to:

```swift
band: band.lowercased(),
```

- [ ] **Step 2: Fix eQSL parser**

In `EQSLClient+Helpers.swift`, in `parseADIFRecord`, change:

```swift
band: band.uppercased(),
```

to:

```swift
band: band.lowercased(),
```

- [ ] **Step 3: Commit**

```
git add CarrierWave/Services/ClubLogClient+Helpers.swift CarrierWave/Services/EQSLClient+Helpers.swift
git commit -m "fix: lowercase BAND from ClubLog/eQSL downloads (matches ADIF enumeration)"
```

---

### Task 8: Use UTF-8 byte count in formatField (Audit Issue #8 — LOW)

**Files:**
- Modify: `CarrierWave/Services/ADIFExportService.swift` (formatField)
- Modify: `CarrierWaveData/Sources/CarrierWaveData/FullADIFExportActor.swift` (formatField)
- Modify: `CarrierWave/Services/POTAClient+ADIF.swift` (formatField)
- Modify: `CarrierWave/Services/PendingUploadExporter.swift` (adifField)
- Modify: `CarrierWave/Services/QRZClient+ADIF.swift` (addField closure in generateADIF)
- Modify: `CarrierWave/Services/ClubLogClient+Helpers.swift` (addField closure in generateADIF)
- Modify: `CarrierWave/Services/EQSLClient+Helpers.swift` (addField closure in generateADIF)

- [ ] **Step 1: Fix all formatField / adifField implementations**

In every `formatField` or `adifField` function, change `.count` to `.utf8.count`:

Before (pattern appears in multiple files):
```swift
"<\(name.uppercased()):\(value.count)>\(value)"
```

After:
```swift
"<\(name.uppercased()):\(value.utf8.count)>\(value)"
```

For the inline `addField` closures in QRZClient, ClubLog, and eQSL:

Before:
```swift
fields.append("<\(name):\(value.count)>\(value)")
```

After:
```swift
fields.append("<\(name):\(value.utf8.count)>\(value)")
```

- [ ] **Step 2: Commit**

```
git add CarrierWave/Services/ADIFExportService.swift CarrierWaveData/Sources/CarrierWaveData/FullADIFExportActor.swift CarrierWave/Services/POTAClient+ADIF.swift CarrierWave/Services/PendingUploadExporter.swift CarrierWave/Services/QRZClient+ADIF.swift CarrierWave/Services/ClubLogClient+Helpers.swift CarrierWave/Services/EQSLClient+Helpers.swift
git commit -m "fix: use UTF-8 byte count for ADIF field LENGTH per spec"
```

---

### Task 9: Add metadata fields to QRZ upload (Audit Issue #9 — LOW)

**Files:**
- Modify: `CarrierWave/Services/QRZClient+ADIF.swift:107-158`

- [ ] **Step 1: Add missing fields to QRZ generateADIF**

In `QRZClient+ADIF.swift`, in `generateADIF(for:)`, add after the `addField("comment", cleanedNotes)` line:

```swift
addField("name", qso.name)
addField("qth", qso.qth)
addField("state", qso.state)
addField("country", qso.country)
if let dxcc = qso.dxcc {
    addField("dxcc", String(dxcc))
}
if let power = qso.power {
    addField("tx_pwr", String(power))
}
```

- [ ] **Step 2: Commit**

```
git add CarrierWave/Services/QRZClient+ADIF.swift
git commit -m "feat: include NAME, QTH, STATE, COUNTRY, DXCC, TX_PWR in QRZ uploads"
```

---

### Task 10: Switch LoTW parser to use core ADIFParser (Audit Issue #10 — LOW)

**Files:**
- Modify: `CarrierWave/Services/LoTWClient+Parsing.swift`

- [ ] **Step 1: Replace custom extractField with ADIFParser.extractField**

In `LoTWClient+Parsing.swift`, replace the custom `extractField` method body:

```swift
func extractField(_ name: String, from record: String) -> String? {
    ADIFParser.extractField(name, from: record)
}
```

This delegates to the core parser which uses proper length-based extraction. The method signature stays the same so all call sites continue to work.

- [ ] **Step 2: Replace custom parseHeaderField with ADIFParser.extractField**

Replace the `parseHeaderField` method body:

```swift
func parseHeaderField(_ header: String, field: String) -> String? {
    ADIFParser.extractField(field, from: header)
}
```

- [ ] **Step 3: Replace parseQSORecord to use ADIFParser.extractFields**

Replace `parseQSORecord` to use the centralized field extraction:

```swift
func parseQSORecord(_ record: String) -> LoTWFetchedQSO? {
    let fields = ADIFParser.extractFields(record)

    guard let callsign = fields["call"],
          let band = fields["band"],
          let qsoDateStr = fields["qso_date"],
          let timestamp = parseQSOTimestamp(
              dateStr: qsoDateStr, timeStr: fields["time_on"]
          )
    else {
        return nil
    }

    // LoTW may emit APP_LoTW_MODE instead of MODE
    guard let mode = fields["mode"] ?? fields["app_lotw_mode"] else {
        return nil
    }

    let qslReceived = fields["qsl_rcvd"]?.uppercased() == "Y"
    let qslDate = fields["qslrdate"].flatMap { parseQSLDateString($0) }

    return LoTWFetchedQSO(
        callsign: callsign,
        band: band,
        mode: mode,
        frequency: fields["freq"].flatMap { Double($0) },
        timestamp: timestamp,
        rstSent: fields["rst_sent"],
        rstReceived: fields["rst_rcvd"],
        myCallsign: fields["station_callsign"]
            ?? fields["app_lotw_owncall"],
        myGrid: fields["my_gridsquare"],
        theirGrid: fields["gridsquare"],
        state: fields["state"],
        country: fields["country"],
        dxcc: fields["dxcc"].flatMap { Int($0) },
        qslReceived: qslReceived,
        qslReceivedDate: qslDate,
        rawADIF: record
    )
}
```

Note: The existing `parseQSLReceivedDate` calls `extractField` internally — since that now delegates to `ADIFParser.extractField`, it still works. But the above rewrite uses `fields["qslrdate"]` directly from the dict, so rename the helper to avoid confusion:

```swift
private func parseQSLDateString(_ dateStr: String) -> Date? {
    let dateFormatter = DateFormatter()
    dateFormatter.timeZone = TimeZone(identifier: "UTC")
    dateFormatter.dateFormat = "yyyyMMdd"
    return dateFormatter.date(from: dateStr)
}
```

The old `parseQSLReceivedDate` method is only called from `parseQSORecord` (verified — no other callers). Remove it.

- [ ] **Step 4: Commit**

```
git add CarrierWave/Services/LoTWClient+Parsing.swift
git commit -m "refactor: use core ADIFParser for LoTW field extraction (length-based)"
```

---

### Task 11: Update CHANGELOG.md

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add entries under [Unreleased]**

```markdown
### Fixed
- Export FT4 as MFSK+FT4 submode per ADIF 3.1.7 spec
- Swap eQSL inbox RST fields (were inverted from other station's perspective)
- Use standard QRZCOM_QSO_UPLOAD_STATUS field name in ADIF exports
- Standardize ADIF_VER to 3.1.7 across all export paths
- Split MODE/SUBMODE in ClubLog and eQSL uploads (USB→SSB+USB, FT4→MFSK+FT4)
- Lowercase BAND from ClubLog/eQSL downloads to match ADIF enumeration
- Use UTF-8 byte count for ADIF field LENGTH per spec
- Delegate LoTW field extraction to core ADIFParser (length-based)

### Added
- Include contest fields (CONTEST_ID, STX, SRX, STX_STRING, SRX_STRING) in ADIF exports
- Include NAME, QTH, STATE, COUNTRY, DXCC, TX_PWR in QRZ uploads
```

- [ ] **Step 2: Commit**

```
git add CHANGELOG.md
git commit -m "docs: add ADIF compliance fixes to changelog"
```
