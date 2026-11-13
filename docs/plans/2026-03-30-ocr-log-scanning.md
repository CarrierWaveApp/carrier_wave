# CAR-219: OCR Scanning of Handwritten Logs

**Date:** 2026-03-30
**Status:** Feasibility plan
**Linear:** CAR-219

## Goal

Let users photograph handwritten log pages and import the QSOs. Each row of text is fed through the existing `QuickEntryParser` — no new parsing grammar needed. The user configures RST order (sent-first vs received-first) before import, same as the existing quick entry setting.

## Architecture

```
VNDocumentCameraViewController
        │
        ▼
  Vision OCR (on-device)
  VNRecognizeTextRequest(.accurate)
        │
        ▼
  Row Grouper (cluster text by Y-coordinate)
        │
        ▼
  QuickEntryParser.parse(row, rstOrder:)   ← existing parser, no changes
        │
        ▼
  Review/Edit Sheet (table of parsed QSOs)
        │
        ▼
  Import into SwiftData (reuse ImportService)
```

All processing is on-device. No network required.

## Pipeline Detail

### 1. Capture — `VNDocumentCameraViewController`

UIKit document scanner wrapped in `UIViewControllerRepresentable`. Handles multi-page capture, perspective correction, and cropping. Returns `[VNDocumentCameraScan]` with one `UIImage` per page.

**File:** `CarrierWave/Views/Import/LogScannerView.swift`

### 2. OCR — Vision Framework

For each page image:

```swift
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false   // callsigns aren't words
let handler = VNImageRequestHandler(cgImage: image, options: [:])
try handler.perform([request])
let observations: [VNRecognizedTextObservation] = request.results ?? []
```

Each observation has a bounding box (normalized coordinates) and recognized text candidates ranked by confidence.

**Key decision:** Disable language correction. Callsigns like `W1AW` and RSTs like `579` get mangled by English dictionaries.

### 3. Row Grouping

OCR returns individual text blocks, not rows. Group observations into rows by Y-coordinate proximity:

1. Sort observations by `boundingBox.origin.y` (descending — Vision uses bottom-left origin).
2. Cluster observations whose Y-centers are within a threshold (e.g., 2% of image height).
3. Within each cluster, sort by `boundingBox.origin.x` (left to right).
4. Join tokens with spaces to form one string per row.

This naturally handles columnar layouts — tokens in the same row get joined regardless of column spacing.

**File:** `CarrierWaveCore/Sources/CarrierWaveCore/OCR/TextRowGrouper.swift`

### 4. Header Detection & Stripping

Many log sheets have a header row ("DATE", "TIME", "CALL", "FREQ", "MODE", "RST"). Detect and strip it:

- If the first row contains 3+ known header keywords, skip it.
- Header keywords: `DATE`, `TIME`, `CALL`, `CALLSIGN`, `FREQ`, `FREQUENCY`, `MODE`, `RST`, `BAND`, `REMARKS`, `NOTES`, `SENT`, `RCVD`, `NAME`, `QTH`.

### 5. Timestamp Handling

The quick entry parser does not handle dates/times — it's designed for live logging where the timestamp is "now." For scanned logs we need to extract date and time from each row.

**Approach:** Before feeding a row to `QuickEntryParser`, scan tokens for date/time patterns and extract them:

- Date patterns: `MM/DD/YY`, `MM/DD/YYYY`, `YYYY-MM-DD`, `DD-MMM-YY` (e.g., `30-MAR-26`)
- Time patterns: `HHMM`, `HH:MM` (assumed UTC unless user overrides)
- Extract and remove date/time tokens from the row string
- Pass remaining tokens to `QuickEntryParser.parse()`
- Attach extracted timestamp to the result

If no date is found on a row, inherit from the previous row (common in logs where the date is written once at the top). If no time is found, leave it nil for user review.

**File:** `CarrierWaveCore/Sources/CarrierWaveCore/OCR/TimestampExtractor.swift`

### 6. Parsing — Existing `QuickEntryParser`

After timestamp extraction, the remaining row text looks like a normal quick entry string:

```
W1AW 14.250 SSB 59 59
K1TTT 7.035 CW 599 579 ME
```

Feed directly to `QuickEntryParser.parse(row, rstOrder: userSelection)`.

The parser already handles: callsign detection, frequency/band, mode, RST with ordering, park references, grid squares, state/region, and notes (unrecognized tokens).

**No changes to `QuickEntryParser` needed.**

### 7. RST Order Prompt

Before processing, show a configuration sheet:

- **RST Order:** Toggle between "Sent first" (contest convention) and "Received first" (POTA convention). Default matches the user's existing quick entry RST order preference.
- **Default Date:** Optional date picker for logs that don't have dates on every row.
- **My Callsign:** Pre-filled from active station profile, editable.

This is a simple form shown after the camera dismisses and before OCR processing begins.

**File:** `CarrierWave/Views/Import/ScanConfigSheet.swift`

### 8. Review UI

Table showing parsed results with per-row editing:

| # | Conf | Time | Call | Freq | Mode | RST S | RST R | Notes |
|---|------|------|------|------|------|-------|-------|-------|
| 1 | 🟢 | 1430 | W1AW | 14.250 | SSB | 59 | 59 | |
| 2 | 🟡 | 1435 | K1?TT | 7.035 | CW | 599 | 579 | ME |
| 3 | 🔴 | — | (unparsed) | | | | | raw text shown |

- **Green:** All tokens parsed, high OCR confidence.
- **Yellow:** Parsed but some tokens had low OCR confidence (< 0.7) or had `unrecognized` tokens. Show the original OCR text on tap for comparison.
- **Red:** Row failed to parse (no valid callsign found). Show raw OCR text. User can edit inline or delete.

Each row is tappable to edit individual fields. "Import All" button at the bottom (with count). Option to deselect rows.

**File:** `CarrierWave/Views/Import/ScanReviewView.swift`

### 9. Import

Reuse `ImportService` with `importSource: .scanned`. Create QSOs with:
- Fields from `QuickEntryResult`
- Timestamp from `TimestampExtractor`
- `myCallsign` from config sheet
- Current logging session (if active) or standalone

## Entry Point

Add "Scan Log" option to the existing import flow. Two possible placements:

1. **Import menu** (Settings > Import) — alongside ADIF import
2. **FAB / quick action** on the Sessions tab — more discoverable

Recommend option 1 for MVP since it's a bulk import operation, not a live logging action.

## New Files

| File | Package | Purpose |
|------|---------|---------|
| `OCR/TextRowGrouper.swift` | CarrierWaveCore | Group OCR observations into text rows |
| `OCR/TimestampExtractor.swift` | CarrierWaveCore | Extract date/time tokens before quick entry parsing |
| `OCR/LogPageScanner.swift` | CarrierWaveCore | Orchestrator: image → OCR → group → extract timestamps → parse |
| `Views/Import/LogScannerView.swift` | CarrierWave | `VNDocumentCameraViewController` wrapper |
| `Views/Import/ScanConfigSheet.swift` | CarrierWave | RST order + default date + callsign config |
| `Views/Import/ScanReviewView.swift` | CarrierWave | Review table with confidence indicators |

## What We Get for Free

- **All quick entry token types:** callsign, frequency, band, mode, RST, park reference, grid, state, notes
- **RST ordering logic:** suffix detection (`579S`, `559R`), unsuffixed ordering by user preference
- **Multi-callsign rows:** `QuickEntryParser.parseMulti()` could handle rows like `W1AW K1TTT 59 59 20M SSB` as two QSOs
- **Token preview UI:** `QuickEntryPreview` and `TokenBadge` can be reused in the review screen to show color-coded parse results
- **Import pipeline:** `ImportService` handles duplicate detection, session association, sync marking

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Handwriting OCR accuracy varies | Callsigns misread (0/O, 1/I) | Confidence-based flagging; optional QRZ validation pass |
| Row grouping fails on cramped logs | Tokens assigned to wrong rows | Tunable Y-threshold; manual row correction in review UI |
| Timestamps in unexpected formats | QSOs get wrong time or no time | Fallback to user-provided default date; editable in review |
| Very large logs (100+ QSOs) | Memory pressure from images | Process one page at a time; release images after OCR |

## Experimental Feature

Gate behind `ExperimentalFeature.logScanning` (alpha). Add to `ExperimentalFeature.swift` and the experiments table in CLAUDE.md.

## Out of Scope (Future)

- Printable template PDF generation
- Foundation Models on-device LLM for fuzzy parsing
- Automatic QRZ validation of scanned callsigns
- Photo attachment (linking scan image to imported QSOs)
