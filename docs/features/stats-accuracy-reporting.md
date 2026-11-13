# Stats Accuracy Reporting

Debugging feature that lets users report stats inaccuracies and generates a structured diagnostic bundle for developer investigation.

## Goals

1. Let users identify and report when a statistic looks wrong
2. Auto-collect all relevant context so developers can reproduce and diagnose
3. Provide lightweight inline explanations that resolve most confusion without a full report

## User Flow

### Entry Points

| Location | Action | Context Provided |
|----------|--------|------------------|
| Dashboard stat card | Context menu → "Report Inaccuracy" | Category + top-level count |
| `StatDetailView` item row | Context menu → "Report Inaccuracy" | Category + specific identifier + count |

Both entry points open the same `ReportInaccuracyView` modal, pre-filled with available context.

### Report Form

1. **Stat type** — pre-filled from context (e.g., "DXCC Entities" or "DXCC Entities → Japan")
2. **Computed value** — pre-filled from current stats
3. **Expected value** — user enters what they believe the number should be
4. **Flagged callsigns** — optional list of specific callsigns the user believes are miscounted or missing
5. **Comment** — free-text description of what seems wrong
6. **Generate & Send** — builds diagnostic bundle, opens share/send flow

## "Explain This Number" Popover

Standalone lightweight feature available on any stat count. Tap the count on a stat item to see a brief breakdown:

> **247 QSOs**
> 3 hidden (excluded) · 2 metadata (excluded) · 1 deduplicated

For activation counts:
> **Park K-1234 on 2026-03-15**
> 9 QSOs (need 10 for successful activation)
> 1 excluded: mode=WEATHER (metadata)

This resolves most "why is my number wrong?" questions without needing a full report.

### Implementation

- Computed alongside stats in `StatsComputationActor`, stored as lightweight `StatExplanation` structs
- Per-category summaries: total matched, excluded by reason (hidden, metadata, deduplicated)
- Per-activation: QSO count, threshold, excluded QSOs with reasons
- Displayed in a popover anchored to the count label

## Diagnostic Bundle

### A. User-Provided Context

| Field | Type | Description |
|-------|------|-------------|
| `statCategory` | `StatCategoryType` | Which stat (entities, parks, bands, etc.) |
| `statIdentifier` | `String?` | Specific item (e.g., "JA", "K-1234", "20m") — nil for top-level card reports |
| `expectedValue` | `Int` | What user thinks count should be |
| `computedValue` | `Int` | What app computed |
| `userComment` | `String` | Free-text explanation |
| `flaggedCallsigns` | `[String]` | Specific callsigns user believes are wrong |

### B. Computed Stats Snapshot

- Full `QSOStatistics` output for the reported category — all grouped items with counts
- `realQSOs` count vs total snapshot count (verifies metadata filtering)
- Computation generation number + timestamp
- For the specific stat item: the complete `StatCategoryItem` with all QSO IDs

### C. Relevant QSO Data

For the specific stat item in question, dump every QSO that was or should have been included.

**Included QSOs** — all QSOs matching the stat's grouping key:

| Field | Purpose |
|-------|---------|
| `id` | Persistent model ID |
| `callsign` | Contact callsign |
| `mode` | Transmission mode |
| `band` | Operating band |
| `frequency` | Exact frequency |
| `timestamp` | QSO date/time |
| `parkReference` | POTA park reference |
| `gridSquare` | Maidenhead grid |
| `isHidden` | Hidden state |
| `qrzConfirmed` | QRZ confirmation |
| `lotwConfirmed` | LoTW confirmation |
| `loggingSessionId` | Associated session |
| `callsignPrefix` | Extracted prefix |
| `dxccEntity` | Resolved entity name |

**Flagged QSOs** — if user provided callsigns, include those QSOs even if they didn't match the grouping key.

**Entity resolution detail** — for entity-related stats, include the `callsignPrefix → entity` mapping for each QSO. This is where most DXCC bugs live.

### D. Filter Trace

A structured decision log showing why QSOs were included or excluded. Generated on-demand during report creation only (not during normal computation).

**For high-count categories** (bands, frequencies, best friends): summarized trace.
```
Band 20m: 247 QSOs matched
  Excluded: 2 metadata (WEATHER×1, SOLAR×1), 1 hidden
  Net counted: 244
```

**For excluded/borderline QSOs**: full per-QSO detail.
```
QSO abc-123 (JD1BMH, 2026-03-10):
  ✓ isHidden=false → included
  ✓ mode=CW → not metadata → included
  ✗ callsignPrefix=JD1 → entity=Ogasawara → does NOT match Japan
  → COUNTED in DXCC:Ogasawara (not Japan)
```

**For activation threshold issues**: full breakdown.
```
Park K-1234 on 2026-03-15 UTC:
  Total QSOs with this park+date: 11
  Excluded: 1 metadata (WEATHER), 1 hidden
  Counted: 9 → BELOW threshold (10) → attempted, not successful
  QSOs:
    - W1ABC SSB 14.260 13:01Z ✓
    - K2DEF CW  7.030  13:15Z ✓
    - ...
    - [WEATHER] 14:00Z ✗ metadata
    - W3GHI FT8 7.074  14:30Z ✗ hidden
```

### E. Environment Context

| Field | Purpose |
|-------|---------|
| `appVersion` | App version + build number |
| `totalQSOCount` | All QSOs in database |
| `realQSOCount` | Post-metadata-filter count |
| `hiddenQSOCount` | Number of hidden QSOs |
| `deduplicationCount` | Dupes removed in last computation |
| `iCloudSyncStatus` | Pending changes? |
| `lastSyncTimestamps` | Per-service (QRZ, LoTW, POTA) |
| `computationTimestamp` | When stats were last computed |
| `computationGeneration` | Generation number |

### F. Raw Data Extract

Optional section — filtered SQLite extract for matching records only (not a full dump):

- QSO rows matching the stat's grouping key
- SwiftData `persistentModelID` for exact record identification
- Schema version info
- Associated `LoggingSession` rows if relevant (activation stats)

## Export Format

JSON file with structured sections:

```json
{
  "version": 1,
  "generatedAt": "2026-03-23T14:30:00Z",
  "appVersion": "2.4.0 (142)",
  "report": {
    "category": "entities",
    "identifier": "Japan",
    "computedValue": 13,
    "expectedValue": 15,
    "flaggedCallsigns": ["JD1BMH", "JR6ABC"],
    "comment": "I have 15 Japan QSOs confirmed on LoTW but app shows 13"
  },
  "statsSnapshot": {
    "totalRealQSOs": 1247,
    "totalSnapshots": 1253,
    "categoryItems": [...]
  },
  "matchingQSOs": [...],
  "excludedQSOs": [...],
  "flaggedQSODetails": [...],
  "filterTrace": {
    "summary": "13 matched, 2 excluded (1 different entity, 1 hidden)",
    "details": [...]
  },
  "environment": {...},
  "rawDataExtract": {...}
}
```

## Delivery Mechanism

In-app "Send to Developer" flow:

- Pre-composes a message with the JSON bundle attached
- Channels: email (pre-filled with support address) or Discord (deep link to support channel)
- Bundle is also saved locally in case the send fails
- User sees a confirmation with summary of what was collected

## Architecture

| Component | Package | Responsibility |
|-----------|---------|----------------|
| `StatsReport` | CarrierWaveData | Codable struct for the full diagnostic bundle |
| `StatsReportBuilder` | CarrierWaveData | Collects data from ModelContext + QSOStatistics, runs targeted trace |
| `StatExplanation` | CarrierWaveData | Lightweight struct for "explain this number" popover |
| `ReportInaccuracyView` | CarrierWave | SwiftUI form modal |
| `StatExplanationPopover` | CarrierWave | Inline count explanation UI |
| Dashboard/detail entry points | CarrierWave | Context menu items on cards and rows |

### Performance Considerations

- Filter trace runs **only** during report generation, not during normal stats computation
- Trace targets a single category/identifier — processes only relevant QSOs, not the full table
- Uses the same batched fetch pattern as `StatsComputationActor`
- Report generation runs on a background actor; UI shows progress indicator
- "Explain this number" data is computed alongside normal stats (minimal overhead — just counters)

## Related

- [Statistics](statistics.md)
- [Statistics Drilldown Design](../plans/2026-01-21-statistics-drilldown-design.md)
