# Antenna Propagation Check ("How's My Antenna?") — Design Brief

**Date:** 2026-05-03
**Branch:** `worktree-antenna-propagation`
**Status:** Design locked, ready for implementation
**Linear:** _(to file as separate CAR ticket on implementation)_

## Summary

A new iOS-only diagnostic mode that, while the user transmits CQ on the air, watches RBN (CW/digital) and PSK Reporter (FT8/FT4) for spots of the user's callsign and produces a saved artifact with per-band stats, geographic breakdown, and side-by-side / map-overlay comparison against prior checks.

In-app surface: **"Propagation Check"**. Marketing/devlog name: _"How's my antenna?"_.

Ships behind a new `ExperimentalFeature.propagationCheck` (alpha, hidden by default).

## User Flow

1. **Entry:** More tab → Propagation Check (experiment-gated, with `ExperimentalBadge`).
2. **List screen:** prior checks, sorted recent-first; "+" to start a new one; multi-select to compare.
3. **Start sheet:** band-of-interest multi-picker (defaults to all HF), callsign field (defaults to user's, suffix-tolerant), optional duration cap, mode selector (Auto / Passive). If user has no grid in `UserProfile`, prompt for it before allowing Start.
4. **Live view (map-first):** world map with band-colored pins, size = SNR, opacity fades over 60s. Header strip shows elapsed, total spots, unique skimmers, bands-with-activity. Pull-up sheet for chronological feed. Toggle for "freshness fade" vs "cumulative."
5. **Stop:** triggers grace tail (CW: 30s, FT8: 5min) to catch lagging spots, then prompts label with auto-name suggestion (`"20m+40m · 2026-05-03 14:32"`).
6. **Results screen (R3 two-tier):** headline counters + static cumulative map; "Show details" expands per-band table, continent/CQ-zone breakdown, spots-per-minute timeline, distance histogram.
7. **Compare:** from list, multi-select two checks → Compare. Tabs: **Stats** (side-by-side numbers + deltas) and **Map** (overlay, two pin colors).

## Mode Decision Matrix

|                | CW                              | FT8 / FT4                              |
|----------------|---------------------------------|----------------------------------------|
| Spot source    | RBN                             | PSK Reporter                           |
| Granularity    | Real-time                       | ~15 min windows                        |
| Min duration   | None (suggest 15 min)           | Enforced 15 min, default 30 min        |
| Active mode TX | Delegates to existing CW TX     | Delegates to existing FT8 TX           |
| Grace tail     | 30s after Stop                  | 5 min after Stop                       |

## Transmit Control (Hybrid)

- **Passive (default):** App does not touch CAT. User transmits via Field's CW/FT8 features, an external rig, or a paddle. App polls/streams RBN + PSK Reporter for the configured callsign.
- **Active "Auto-CQ" (opt-in, gated on controllable radio):** Button visible only when a controllable radio is connected (CW Bridge / CAT / FT8-capable). Delegates to existing in-app CW or FT8 TX features set to CQ mode for the session duration. No new keyer or FT8 engine inside this feature.
- **Safety abort:** SWR fault, PA over-temp, or CAT disconnect during auto-CQ → kill TX immediately, mark artifact `auto-stopped (radio fault)`, retain collected spots.

## Data Model

Following `ActivityItem`'s opaque-blob precedent (memory: `feedback_activityitem_patterns`, `swiftdata-gotchas`).

```swift
@Model
final class PropagationCheck {
    @Attribute(.unique) var id: UUID
    var label: String                 // user-editable
    var startedAt: Date
    var endedAt: Date
    var callsignUsed: String          // captured at start
    var userGridUsed: String          // captured at start (Maidenhead)
    var bandsRequested: [Int]         // band lower-edges in kHz
    var transmitMode: String          // "passive" | "auto-cw" | "auto-ft8"
    var stopReason: String            // "user" | "duration" | "radio-fault"

    // Headline stats (denormalized for fast list rendering)
    var totalSpots: Int
    var uniqueSkimmers: Int
    var bandsWithActivity: [Int]
    var maxDistanceKm: Double
    var peakSNRdB: Double

    // Opaque blob: schema-versioned + lzfse-compressed JSON of all raw spots
    var spotsBlob: Data
    var spotsBlobSchemaVersion: Int   // 1
}
```

**Spot blob entry shape (versioned):**

```swift
struct PropagationSpotEntry: Codable {
    let source: String      // "rbn" | "pskr"
    let skimmerCall: String
    let skimmerGrid: String?
    let skimmerLat: Double?
    let skimmerLon: Double?
    let freqHz: Int
    let band: Int           // band lower-edge kHz, derived
    let mode: String        // "CW" | "FT8" | etc.
    let snrDB: Double?
    let timestamp: Date
}
```

**Dedup key per spot:** `(source, skimmerCall, freqHz, timestampSec)`. RBN re-emits and PSK Reporter rounds — collapse on this key.

**CloudKit sync:** ON, matching the rest of CW data. One row per check, no relational children — clean for sync.

**Storage estimate:** A busy hour CW session ≈ 500 spots × ~150 bytes JSON = ~75 KB → ~10 KB after lzfse. Negligible.

## Statistics Surface

**Headline (always visible on results card):**
- Total spots
- Unique skimmers
- Bands worked
- Max distance (km/mi per user pref)
- Peak SNR (dB)

**Show-details expansion:**
- **Per-band table:** spots, unique RX, max km, median SNR, peak SNR.
- **Geographic:** segmented control switches between **Continent** and **CQ Zone** breakdowns (both supported per user preference).
- **Spots-per-minute timeline:** small Swift Charts line.
- **Distance histogram:** bucketed bar chart.

All stats computed lazily on detail-view open from the spots blob — no precomputation beyond headlines.

## Comparison

- Compare picker filters by band (e.g., "show me my 20m checks").
- Two views, toggled at top of Compare screen:
  - **Stats:** two-column layout, deltas highlighted (green better / red worse).
  - **Map:** overlay; check A = blue pins, check B = orange pins.
- Smart label nudge: when entering Compare for the first time, if either check still uses the auto-name, show a one-line tip suggesting they rename.

## Live UI Encoding (Map-first)

- **Pin color:** band (via existing `BandColors.swift`).
- **Pin size:** SNR (small/medium/large buckets).
- **Pin opacity / freshness:** last 60s = full; linear fade to ~30% over the next 5 min; toggle to disable fade and show cumulative.
- **Clustering:** MapKit's annotation clustering — unbounded sessions can produce dense regional clusters.
- **Header strip:** elapsed | total | unique skimmers | bands active.
- **Pull-up sheet:** newest-first feed; tap → receiver detail (callsign, grid, distance, this-session count, last SNR).

## Edge Cases & UX Rules

- **No grid in `UserProfile`:** start sheet cannot proceed. Inline prompt with `GridLocationService` "use current location" affordance, or manual Maidenhead entry.
- **Callsign matching:** `^<base>(\/[A-Z0-9]+)?$`, case-insensitive. Catches `/P`, `/M`, `/MM`, `/QRP`. Multi-call / club call → user types into the per-session callsign field.
- **0–2 spots in 15 min ("nobody heard you"):** show calm summary stating RBN + PSK Reporter were reachable (so the user knows the network worked), list common causes (band dead, antenna issue, callsign typo, wrong band CQ'd, propagation), offer "Try again" CTA.
- **Network drop mid-session:** continue session; reconnect with backoff; mark a banner on the live view; persist a `connectivity_gap` annotation in the artifact for transparency.
- **PSK Reporter rate limit:** poll cadence 60s; back off on HTTP 429; document in artifact. Public PSKR API caps roughly 1 req/min.
- **App backgrounded:** sessions are foreground-only for v1; backgrounding stops ingestion (kept simple — background task budget is precious). On return, if still within configured duration cap, resume polling and annotate gap.

## Existing Primitives to Reuse

| Primitive | File | Use |
|-----------|------|-----|
| RBN client | `swift/ios/CarrierWave/Services/RBNClient.swift` | Spot source for CW/digital |
| PSK Reporter client | `swift/packages/CarrierWaveCore/Sources/CarrierWaveCore/PSKReporterClient.swift` | Spot source for FT8/FT4 |
| PSK Reporter spot model | `…/CarrierWaveCore/PSKReporterSpot.swift` | Decode shape |
| User grid | `UserProfile.grid` | Distance math |
| Grid → coords | `MaidenheadConverter.swift` | Distance math |
| One-shot GPS → grid | `GridLocationService.swift` | First-run grid prompt |
| Band colors | `BandColors.swift` | Map pin coloring |
| Band derivation | `BandUtilities.swift` | Spot → band lookup |
| Distance pref | existing user prefs (km/mi) | Display |
| Experiment gate | `ExperimentalFeature.propagationCheck` | New case |
| Experiment badge | `ExperimentalBadge` | Entry in More tab |
| In-app log | `RadioService.shared.addLog(.info, …)` for ingest diagnostics | Per logging rule |
| Auto-CQ (CW) | existing CW TX feature | Delegate target |
| Auto-CQ (FT8) | existing FT8 TX feature (`ExperimentalFeature.ft8`) | Delegate target |

## Implementation Milestones

1. **Model + experiment registration**
   - Add `ExperimentalFeature.propagationCheck` (alpha, hidden).
   - Add `PropagationCheck` SwiftData model + spot blob codable + schema version.
   - In-memory tests for blob round-trip, dedup, headline-stat denormalization.

2. **Ingestion service (passive only)**
   - `PropagationCheckSession` actor. Ingests RBN + PSKR concurrently. Filters by callsign regex + bands-of-interest. Emits `Sendable` spot snapshots to the live view.
   - Connectivity-gap annotations on disconnect.

3. **Start sheet + live view**
   - More-tab entry, list view (empty state), start sheet, live map view with header + pull-up feed, stop flow with grace tail and label prompt.
   - Map: band-colored pins + SNR-sized + freshness fade + clustering.

4. **Results + persistence**
   - Save artifact on stop (compress blob, denormalize headlines).
   - Results screen with R3 two-tier layout, per-band table, geo segmented control, charts.

5. **Compare**
   - Multi-select on list view, Compare screen with Stats / Map toggle, deltas highlighting.

6. **Auto-CQ integration (opt-in)**
   - Button visibility gated on radio capability detection.
   - CW: delegate to existing CW TX feature in CQ mode.
   - FT8: delegate to existing FT8 TX feature in CQ mode.
   - Safety abort path on radio fault.

7. **Empty / sparse / network-fault polish**
   - "Nobody heard you" view.
   - Network reconnect banner + persisted gap annotations.
   - PSKR rate-limit backoff.

8. **Tests + dogfood**
   - Unit tests on dedup, regex, stat computation, distance math.
   - Manual on-air dogfood: 20m + 40m simultaneous CQ, verify spot ingestion, save, reopen, compare with a synthetic prior session.

## Out of Scope (Future)

- macOS Sweep parity.
- Watch / widget surfaces.
- Multi-callsign per session (club + personal in one).
- "Skimmer hall of fame" / cross-session aggregates.
- Background-mode ingestion.
- Antenna pattern overlay (compass + map azimuthal projection).
- Sharing / export (ADIF doesn't fit; would need custom JSON or PDF).
- Per-spot map heatmap density layer.
- Audio-band SDR-side propagation tests (Sweep concern).

## Open Implementation Questions (decide during build, not blocking)

- Map renderer: MapKit (native, free clustering) vs MapLibre (more control). **Default MapKit** unless clustering UX is unacceptable.
- Charts: Swift Charts (iOS 16+). No question — that's the default.
- Whether to seed the spot blob with a `connectivity_gap` typed entry inline, or store gaps in a sibling field. **Default inline** with a `kind` discriminator on the blob entry (allows future mixing of typed events).
- Per-band color override if more than ~12 bands collide on the spectrum (HF + 6m + 2m + 70cm) — `BandColors` already covers this, just verify saturation distinguishability on map.
