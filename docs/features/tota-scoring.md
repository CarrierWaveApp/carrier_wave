# TOTA Scoring & Session Summary

Carrier Wave's Tiles on the Air (TOTA) integration estimates the activator's score
locally so the operator can see where they stand without uploading. The official
score lives on `tilesontheair.org` after ADIF submission; the in-app score is a
faithful client-side mirror that defers to the server once an activation is
uploaded.

This doc captures the formula, the four-tier ledger, the model fields, and where
the enrichment surfaces in the UI.

## Surfaces

The TOTA enrichment renders on three surfaces, all driven from `LoggingSession`:

| Surface | Detail | Audience |
| --- | --- | --- |
| `SessionDetailView` | Full ledger, path map with track polyline + tile boundaries, T3 candidate list, GPX export, refresh-spots button. Primary surface. | Operator, post-end |
| `EndSessionFlowView` (summary step) | Condensed ledger + bonus chips + last-chance edits (winter override, first-ever-tile checkbox). | Operator, at end |
| `SessionBragSheetCard` (`ActivityDetails`) | Tile name + total + bonus chip row. Travels to clubmates via the activities server. | Clubmates |

Live in-session scoring is intentionally **not** surfaced — the logger must stay
fast and offline-friendly (see PERFORMANCE.md). The score appears at the end of
the session and is recomputable from the cached inputs whenever a TOTA session is
opened.

## Formula

Sourced from `TOTA_Rules.pdf` (rev. 01/27/2025, updated 04/22/2026), encoded in
the `tota-rules` skill.

### Standard category

```
effective_qsos = sum over qsos of mode_weight(qso)
                       × t3_weight(qso)
mode_weight    = 0.2 if mode in {FT8, FT4} else 1
t3_weight      = 2 if QSO has a T3 spot match else 1
                 (applied after the mode weight, so an FT8 T3 contact is 0.4)

distance       = max(activationDistanceMiles, 0.25)   # only if > 0
                 × personalEffortFactor (if set)
base           = effective_qsos × distance

qso_subtotal   = base × (2 if qrpActivation else 1)

percentage_bonuses = qso_subtotal × (
    0.20 if isWinter
  + 0.05 × floor(ruckWeightPounds / 5)
  + 0.02 × floor(activationElevationGainFeet / 200)
  + 0.15 if withPets
  + 0.20 if withKids
)

flat_bonuses   = (10 if firstActivationOfTileEver)
               + (10 if firstActivationOfGridInQuarter, server-confirmed)
               + (5  if winlinkSent)
               + (5  if aprsSent)
               + (5  if varacSent)

total = qso_subtotal + percentage_bonuses + flat_bonuses
```

PEF scales the **distance** term, which means it scales the QSO subtotal AND the
percentage bonuses (which are computed against that subtotal). PEF does **not**
scale the flat bonuses. PEF is opt-in (`personalEffortFactor: Int? in 1...10`).
Standard leaderboard ranking ignores PEF; a separate Personal Effort leaderboard
applies it.

### Mobile category

Mobile is a separate category with a separate leaderboard. The formula collapses:

```
mobile_total = effective_qsos × (2 if qrpActivation else 1)
             + flat_bonuses
```

No distance multiplier, no winter/ruck/elev/pets/kids percentages, no PEF. T3
boost still applies in `effective_qsos`. The model expresses this via
`totaCategoryRawValue == "mobile"`.

### Defensive QSO exclusions

The session-level flags `winlinkSent` / `aprsSent` / `varacSent` count as flat
bonuses that *replace* a QSO. Some operators log the actual transmission as a
QSO row anyway. To avoid double-counting, the engine excludes any QSO whose
`mode` is `WINLINK`, `APRS`, or `VARAC` from `effective_qsos` whenever the
matching session flag is set.

The repeater cap (max 2 repeater QSOs per activation, on different repeaters) is
**not** enforced locally — we have no `isRepeater` field on `QSO`. The summary
log notes this with "Repeater contacts beyond 2 won't credit on official score."

### Worked example (verifies the engine)

From the rules: EM73wt in January, with one dog, 5 lb ruck, 191 ft elevation
gain, first activation of tile in quarter, 5.17 mi roundtrip. 10 P2P digital
VarAC QSOs + 1 SSB simplex + 1 FM repeater = 12 effective QSOs. All > 10 W.
No T3.

```
effective_qsos      = 12
distance            = 5.17
base                = 12 × 5.17 = 62.04
qso_subtotal        = 62.04 × 1 = 62.04
percentage_bonuses  = 62.04 × (0.20 + 0.05 + 0.15) = 62.04 × 0.40 = 24.816
flat_bonuses        = 10 (first-in-quarter)
total               = 62.04 + 24.816 + 10 = 96.856 ≈ 96.8 pts
```

`TOTAScoringEngineTests` replicates this case as a regression target.

## The four-tier ledger

Several inputs aren't knowable from local state alone. The ledger separates the
score by confidence tier:

| Tier | Inputs | Source |
| --- | --- | --- |
| **Confirmed** | base, QRP, winter, ruck, elev, pets, kids, winlink/APRS/VarAC flats | Local model fields |
| **Estimated** | T3 boost | TOTA spots feed correlation |
| **Asserted** | first-activation-of-tile-ever (+10) | User checkbox |
| **Pending** | first-activation-of-grid-in-quarter (+10 per qualifying tile) | Server-only ("by anyone"); shown as eligibility, never added pre-upload |

The headline **Total** displayed pre-upload is `Confirmed + Estimated + Asserted`
— a pessimistic estimate. After upload, the server-returned `points` value
replaces the headline and a diff line shows what bonuses were credited.

### T3 spot correlation

The TOTA spots feed (`TOTAClient.fetchSpots`) is queried at session end with a
window covering the session start through end + 6h buffer. For each QSO, the
service finds spots where `callSign == qso.theirCallsign` and `createdAt` falls
in `[qso.timestamp - 6h, qso.timestamp]`. The closest preceding spot is taken
as authoritative; its `maidenheadGrid` (when present) becomes the chaser's tile
for the T3 record.

Snapshots are persisted on the session (`totaT3CandidatesData`,
`totaT3SnapshotAt`) so re-opening an old session doesn't depend on the spots
feed (which has a rolling ~168h window). The detail view offers a "Refresh
spots" button that lazy-refreshes if the snapshot is older than 5 minutes.

When the device is offline, the Estimated tier shows
"Estimated tier unavailable offline" rather than silently deferring.

## Tiles activated

A "tile" in TOTA is a 6-character Maidenhead subsquare (e.g. `EM73uu`, ~5×7 km).
The summary log lists every tile activated by the session. Multi-tile outings
appear as one summary row listing all tiles (the upload layer splits into N
submissions per the rules).

### QSO-anchored detection

Per the rules, an activation requires "≥1 valid Tiles QSO." We mirror this in
the auto-detection algorithm: a tile counts as activated only if at least one
QSO's timestamp falls within a track segment inside that tile.

Algorithm (computed at session end, cached in `tilesActivatedData`):

1. For each `QSO`, find the two nearest `TrackPoint`s by timestamp, linearly
   interpolate position, derive the 6-char Maidenhead tile.
2. Always include the tile containing `activationLatitude/Longitude` (the
   declared site) — covers session-start rendering before any QSO.
3. Anything in the track that wasn't QSO-anchored becomes the **candidate set**:
   tiles the operator passed through but didn't log from. The detail view
   surfaces these with a "tap to add" affordance so the operator can claim them
   manually if they want.

Sessions without a track fall back to the single tile of
`activationLatitude/Longitude`. Sessions without coords show a CTA.

## Winter detection

The rules give +20% if winter but don't define winter precisely. The auto-detect
heuristic:

- Hemisphere from `activationLatitude` (defaults to northern when absent).
- Northern hemisphere: months 12, 1, 2.
- Southern hemisphere: months 6, 7, 8.
- Equator-adjacent (|lat| < 5°): no winter regardless.
- Anchor on `startedAt` for cross-month sessions.

The auto-detect result feeds the start-sheet pre-checked toggle. The operator
can override (`winterActivationOverride: Bool?`); the three-state nil keeps
"haven't decided" distinct from "explicitly no."

## Schema additions

All eight fields are additive on `LoggingSession`. SwiftData handles additive
optional fields without explicit migration plumbing.

```swift
public var totaCategoryRawValue: String?       // "standard" | "mobile"; nil → standard
public var personalEffortFactor: Int?          // 1...10; nil → not opted in
public var firstActivationOfTileEver: Bool = false   // user-asserted
public var winterActivationOverride: Bool?     // nil = use auto-detect
public var tilesActivatedData: Data?           // [String] of 6-char tiles, JSON-encoded
public var totaT3CandidatesData: Data?         // [T3Candidate], JSON-encoded
public var totaT3SnapshotAt: Date?             // when correlation last ran
public var totaOfficialPoints: Double?         // server-returned points; nil pre-upload
```

`TOTACategory` enum (`.standard` / `.mobile`) wraps `totaCategoryRawValue`.
`T3Candidate` (callsign, theirTile, qsoId) is a small Codable struct, JSON-blob
in `totaT3CandidatesData`.

The score itself is **not** stored — it's recomputed from inputs whenever the
view renders. Storing the score would make it stale the moment any input
changes.

## Editability post-session

| Field | Mutability |
| --- | --- |
| `personalEffortFactor` | Frozen at session end (rules requirement) |
| `totaCategoryRawValue` | Pre-upload only (changes leaderboard belonging) |
| `firstActivationOfTileEver` | Pre-upload only (server's verdict supersedes) |
| `winterActivationOverride` | Pre-upload only |
| `tilesActivatedData` | Pre-upload only (operator can add candidates) |
| `totaT3CandidatesData` | Always refreshable |
| `totaOfficialPoints` | Server-written only |

A "Locked: submitted to TOTA" notice surfaces in the detail view when
`totaOfficialPoints != nil`.

## Brag sheet (cross-user)

`ActivityDetails` for `sessionCompleted` activities gains TOTA-specific fields:

- `totaTiles: [String]` — 6-char tiles activated
- `totaCategoryRawValue: String?`
- `totaScore: Double?` — in-app estimate or `totaOfficialPoints` if available
- `totaScoreConfidence: String?` — `"estimated"` or `"official"`
- `totaDistanceMiles: Double?`
- `totaElevationGainFt: Double?`
- `totaBonusFlags: [String]` — `["winter", "ruck5", "pets", "winlink", ...]`
- `totaPersonalEffortFactor: Int?`

Explicitly **not** shipped: track points (privacy + size), raw T3 list,
first-ever-tile assertion (operator-claimed, not server-confirmed), individual
bonus toggles (collapsed into the flag list).

When upload completes, the corresponding `ActivityItem` is updated with
`totaScore = totaOfficialPoints` and `totaScoreConfidence = "official"` so
clubmates' brag-sheet cards reflect the official score.

## Files

| Concern | File |
| --- | --- |
| Scoring engine (pure) | `swift/packages/CarrierWaveCore/Sources/CarrierWaveCore/TOTAScoringEngine.swift` |
| Maidenhead 6-char tile | `swift/packages/CarrierWaveCore/Sources/CarrierWaveCore/MaidenheadConverter.swift` (existing) |
| Schema | `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Models/LoggingSession.swift` |
| Tile + T3 services | `swift/ios/CarrierWave/Services/TOTAEnrichmentService.swift` |
| Detail view section | `swift/ios/CarrierWave/Views/Sessions/SessionDetailView+TOTA.swift` |
| End-flow integration | `swift/ios/CarrierWave/Views/Logger/EndSessionFlowView.swift` |
| Brag sheet | `swift/ios/CarrierWave/Models/ActivityItem.swift` + `Views/Activity/SessionBragSheetCard.swift` |
| Start-sheet inputs | `swift/ios/CarrierWave/Views/Logger/SessionStartSheet+TOTA.swift` |
| PEF profile setting | `swift/ios/CarrierWave/Views/Settings/TOTASettingsView.swift` |
