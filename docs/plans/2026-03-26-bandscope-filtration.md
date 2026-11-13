# Band Scope & Filtration Feature Spec — CW Sweep

**Date:** 2026-03-26
**Status:** Draft — research complete, ready for design review

---

## Research Summary

Deep analysis of bandmap/band scope implementations across 10+ amateur radio logging applications:

- **N1MM Logger+** — Gold standard for contest bandmaps. Three-tier cascading filter architecture, spectrum display with signal detection, keyboard-driven S&P navigation, SO2R dual bandmaps.
- **N3FJP** — Beginner-friendly. Time-based color aging (yellow→gray), 200-spot buffer, fixed 30-min decay, no filter width display. Simpler but beloved for ease of use.
- **Win-Test** — Serious contesting. Summary stats bar (available mults/QSOs/points), dual BANDMAP/LIST toggle, double-mult color.
- **DXLab SpotCollector** — SQL expression filtering, three-layer filter architecture (pre-filter → database → display), award-need color coding on waterfall overlay.
- **SkookumLogger** (Mac-native) — Activity tables per band + panadapter overlays for K4/IC-7610. Closest Mac-native precedent for CW Sweep.
- **RUMlogNG** (Mac-native) — Spectrum scope with left/right click for VFO-A/B. No callsign overlay on waterfall.
- **Logger32** — Independent "Monitor BandMap" windows for any band, including an all-band view.
- **TR4W** — Elegant gradient color fade for spot aging (white→yellow→background). Bandmap persistence across sessions.
- **Ham Radio Deluxe** — Up to 10 simultaneous band views. Two-tier aging (bold red < 10min, faded > 10min).

---

## Competitive Landscape: Filtration Taxonomy

### 1. Spot Source Filtering

| Filter | Who Does It | How |
|--------|-------------|-----|
| Spotter source (RBN, cluster, skimmer) | N1MM, DXLab | Checkboxes or cluster-level commands |
| Spotter blacklist | N1MM, DXLab | Per-callsign, persists across sessions |
| Preferred/trusted spotters | N1MM | 1-3 highlighted spotters |
| Spot validation quality (busted/confirmed) | N1MM (AR Cluster V6) | V/Q/B tags |
| RBN consensus (2+ skimmers confirm) | AR Cluster V6 | `SET DX FILTER Skimvalid` |

**CW Sweep opportunity:** We already have 7+ spot sources in SpotAggregator with `SpotSource` enum. Per-source toggle is natural. Spotter trust/blacklist is a gap.

### 2. Band & Mode Filtering

| Filter | Who Does It | How |
|--------|-------------|-----|
| Per-band toggles | Everyone | Checkboxes |
| Per-mode toggles (CW/SSB/FT8/etc) | N1MM, N3FJP, HRD | Checkboxes or segmented control |
| WARC/HF/VHF group toggles | N1MM, DXLab | Quick-select buttons |
| Sub-band boundaries | N1MM | Configurable CW/digital/SSB edges |
| Contest-valid modes only | N1MM, Win-Test | Contest-aware toggle |

**CW Sweep opportunity:** BandMapView already has a `SpotModeFilter` segmented control. Band selection exists. Sub-band visualization with `BandEdge.digitalBoundaryKHz` and `ssbBoundaryKHz` is already in the model — just needs visual rendering.

### 3. Status Filtering (Worked/Needed/Dupe)

| Filter | Who Does It | How |
|--------|-------------|-----|
| Dupe de-emphasis (gray) | Everyone | Color coding |
| Dupe hiding | N1MM, Win-Test | Optional toggle |
| Multiplier highlighting | N1MM (red/green), Win-Test (green/blue) | Color coding |
| DXCC need status | DXLab, N3FJP (italic), Logger32 | Award tracking integration |
| LoTW user indicator | N3FJP (red), DXLab | Overlaid on need status |
| "Show only multipliers" | Win-Test | Toggle in list mode |

**CW Sweep opportunity:** `DXCCNeededChecker` already exists. `ClusterWorkedBeforeChecker` handles dupe detection. These just need to flow into color coding on the bandmap.

### 4. Temporal Filtering (Decay/Aging)

| Approach | Who Does It | Details |
|----------|-------------|---------|
| Configurable timeout (minutes) | N1MM (default 60), Win-Test (up to 99) | Right-click to set |
| Fixed timeout | N3FJP (30 min), HRD (60 min) | Not user-adjustable |
| RBN hard cap | N1MM | 20 min regardless of setting |
| Color gradient aging | N3FJP (5-tier), TR4W (smooth fade) | Visual freshness signal |
| "NEW" label | N1MM (< 2 min) | Emphasis on fresh spots |
| Re-spot timer reset | Everyone | Fresh re-spot resets the clock |

**CW Sweep opportunity:** Gradient aging is the clear winner for UX. A smooth fade from bright→dim with a configurable total lifetime. RBN spots should age faster than cluster spots (they're inherently transient).

### 5. Geographic Filtering

| Filter | Who Does It | How |
|--------|-------------|-----|
| Continent | N3FJP, N1MM, DXLab | Checkboxes |
| Country/prefix | N1MM, DXLab | Prefix entry |
| Spotter region | N1MM (AR Cluster) | `spotterstate=XX` |
| CQ/ITU zone | DXLab | SQL filter |
| Distance radius | — | Nobody does this well |

**CW Sweep opportunity:** `SpotRegion` (14 regions) already exists on `EnrichedSpot`. Region-based filtering is natural. Distance filtering using existing haversine would be novel.

### 6. Signal Quality Filtering

| Filter | Who Does It | How |
|--------|-------------|-----|
| SNR threshold | N1MM (spectrum display only) | "Show only spots you can hear" |
| CW speed (WPM) | RBN data | Available but rarely filtered |
| Signal count (# skimmers) | AR Cluster V6 | Consensus threshold |

**CW Sweep opportunity:** RBN spots from our Vail ReRBN API include SNR. Could filter or visually scale spot markers by SNR.

---

## Visual Presentation: Design Patterns

### Axis Orientation

| Orientation | Used By | Best For |
|-------------|---------|----------|
| **Vertical frequency** (y-axis = freq) | N1MM, N3FJP, Win-Test, TR4W | Contest S&P — matches tuning dial motion |
| **Horizontal frequency** (x-axis = freq) | Current CW Sweep BandMapView | Overview/casual — matches spectrum analyzers |
| Table/list | SkookumLogger, DXLab | Data-dense — sortable, searchable |

**Recommendation:** CW Sweep should support **both** vertical (for Contest/S&P layouts) and horizontal (for overview). `VerticalBandMapView` already exists for the activator role.

### Color Coding Strategies

**Contest-optimized (N1MM/Win-Test pattern):**
```
Green  → Double multiplier (DROP EVERYTHING)
Red    → Single multiplier (high priority)
Blue   → New station (normal unworked)
Gray   → Dupe (already worked)
```

**DX/award-optimized:**
```
Red    → Needed DXCC entity (never worked)
Orange → Needed band/mode slot (worked, not on this band/mode)
Blue   → Worked but unconfirmed
Gray   → Confirmed
```

**Time-optimized (N3FJP pattern):**
```
Yellow bold → < 3 minutes (HOT)
Yellow      → 3-5 minutes (fresh)
White       → 5-10 minutes (recent)
Light gray  → 10-20 minutes (aging)
Gray        → 20+ minutes (stale)
```

**Recommendation:** Role-dependent color coding. CW Sweep's `OperatingRole` (Contester, Hunter, Activator, DXer, Casual) should drive which color axis is primary:
- **Contester** → Mult/dupe status (N1MM pattern)
- **DXer** → DXCC need status
- **Hunter/Activator** → Source type + freshness
- **Casual** → Freshness (N3FJP pattern)

### VFO Position & Filter Width

**N1MM approach (gold standard):**
- Blue arrow → RX VFO frequency
- Red arrow → TX frequency (when split)
- Dark band → IF filter width
- Light band → Tuning tolerance zone (auto-populate callsign when within range)

**CW Sweep has:** `RadioManager` with frequency/mode state. No filter width info from CI-V/Kenwood/Yaesu protocols yet (would need additional CAT commands). VFO position marker is implementable immediately.

### Information Density Per Spot

| Element | Priority | Who Shows It |
|---------|----------|-------------|
| Callsign | Critical | Everyone |
| Frequency position | Critical | Everyone (via axis) |
| Worked/needed color | Critical | N1MM, Win-Test, DXLab |
| Age indicator | High | N3FJP (color), N1MM (NEW tag) |
| Country/DXCC | High | N1MM (tooltip), DXLab |
| Source type | Medium | N1MM (# for RBN), CW Sweep already has SpotSource |
| SNR/signal strength | Medium | RBN spots only |
| Bearing | Medium | N1MM (outside own country) |
| Distance | Low | — |
| Spotter callsign | Low | N1MM (tooltip), Win-Test |
| Spot comment | Low | N1MM (tooltip) |

---

## Contester Workflows

### Run vs S&P Mode

The bandmap is primarily an **S&P tool**. During Run (CQ) mode, it serves as:
1. A multiplier alert display (watch for red/green spots)
2. A "bookmark" for the CQ frequency
3. Band activity indicator (is this band alive?)

During S&P, the workflow is:
1. **Jump to next spot**: Ctrl+Down/Up (any), Ctrl+Alt+Down/Up (mults only)
2. **Auto-populate callsign**: When VFO enters tuning tolerance of a spot
3. **Work the station**: Space to confirm call, exchange, Enter to log
4. **Jump to next**: Repeat

**CW Sweep implication:** Keyboard navigation through spots is essential for Contest role. Need "next spot" and "next multiplier" keybindings that tune the radio via RadioManager.

### SO2R Integration

CW Sweep's `RadioManager` already supports multiple radio sessions. For SO2R:
- Two independent bandmaps, one per radio
- Shift+Click on inactive bandmap tunes inactive radio
- Cross-radio multiplier passing

### Spot Management

| Action | How Others Do It | CW Sweep |
|--------|------------------|----------|
| Manual spot entry | Alt+O (N1MM) | Cmd+K command palette? |
| Remove spot at freq | Alt+D (N1MM) | Right-click context menu |
| Mark freq "in use" | Alt+M (N1MM) | Not needed initially |
| Bookmark CQ freq | Auto (N1MM) | Tag current freq as "mine" |

---

## What Others Show Beyond Spots

### Summary Statistics (Win-Test pattern)
- Available QSOs on this band
- Available multipliers on this band
- Estimated points available
- "Is it worth changing bands?" decision support

### Band Activity Indicators
- Spot density as propagation proxy
- Sunrise/sunset markers on stations near grayline (N1MM `¤`)
- Geographic distribution of spots → "which paths are open?"

### CQ Frequency Finder (N1MM Spectrum Display)
- Recommends clear frequencies based on signal gaps
- "Up to 5 recommended CQ frequencies" showing least signal content

---

## Proposed CW Sweep Band Scope Architecture

### Filter System Design

Three-level approach inspired by DXLab's architecture but simplified:

```
Level 1: Source toggles (SpotSource enum — already exists)
    → RBN, POTA, SOTA, WWFF, DX Summit, DX Heat, DX Watch, Cluster
    → Each can be on/off independently

Level 2: Content filters (new)
    → Band (auto-follows radio, or manual select)
    → Mode (CW/SSB/Digital/All — already exists as SpotModeFilter)
    → Region (SpotRegion toggles — 14 regions)
    → Status (New/Needed/Worked/All)
    → Age (slider: 5-120 minutes, default by role)
    → SNR threshold (RBN spots only, optional)

Level 3: Display filters (cosmetic, don't remove data)
    → Dupe de-emphasis (gray, or hide entirely)
    → Source badge visibility
    → Callsign label density (show all vs declutter overlaps)
```

### Data Model

```swift
/// Persisted filter configuration per operating role
struct BandScopeFilterConfig: Codable {
    // Source toggles
    var enabledSources: Set<SpotSource>

    // Content filters
    var modeFilter: SpotModeFilter
    var enabledRegions: Set<SpotRegion>
    var statusFilter: SpotStatusFilter  // .all, .newOnly, .neededOnly, .newAndNeeded
    var maxAgeMinutes: Int              // 5-120, role-dependent default
    var minSNR: Int?                    // nil = no filter, else dB threshold

    // Display options
    var hideDupes: Bool
    var showSourceBadges: Bool
    var declutterLabels: Bool
    var colorScheme: SpotColorScheme    // .contest, .dxcc, .freshness, .source

    // Aging
    var rbnAgeFactor: Double            // 0.5 = RBN spots age 2x faster
}

enum SpotStatusFilter: String, Codable, CaseIterable {
    case all
    case newOnly          // Not worked today
    case neededOnly       // Needed for DXCC/award
    case newAndNeeded     // Either new or needed
    case multipliersOnly  // Contest mult value
}

enum SpotColorScheme: String, Codable, CaseIterable {
    case contest    // Green=double-mult, Red=single-mult, Blue=new, Gray=dupe
    case dxcc       // Red=needed, Orange=new-slot, Blue=unconfirmed, Gray=confirmed
    case freshness  // Yellow→Gray gradient by age
    case source     // Color by SpotSource (already exists)
}
```

### Visual Components

#### 1. Band Scope View (enhanced BandMapView)

**Horizontal mode** (current — for overview):
- Frequency on x-axis, spots as vertical markers
- Sub-band shading (CW | Digital | SSB) using existing `BandEdge` boundaries
- VFO position as blue vertical line with filter width shading
- TX position as red vertical line (when split)
- Color-coded by active `SpotColorScheme`
- Hover tooltip: callsign, frequency, source, age, DXCC, distance, bearing

**Vertical mode** (new — for contest S&P):
- Frequency on y-axis (low at bottom, configurable)
- Callsign text labels at their frequency position
- Wider layout allows more info per spot
- Keyboard navigation: ↓/↑ jump between spots, ⌥↓/↑ jump to mults only
- Click-to-tune via RadioManager

#### 2. Filter Bar (collapsible, above bandmap)

```
[Source: ■RBN ■Cluster ■POTA ☐SOTA ☐WWFF ■DX Summit ☐DX Heat ☐DX Watch]
[Mode: CW | SSB | Digital | All]  [Status: All | New | Needed | Mults]
[Age: ——●—— 30 min]  [Regions: ▼ 12/14 selected]
```

Compact single-line when collapsed, expandable to multi-row for full control.

#### 3. Spot Detail Popover (on hover/click)

```
┌─────────────────────────┐
│ JA1ABC          14.025  │
│ Japan (JA)      CW 25wpm│
│ ─────────────────────── │
│ Spotted: 3 min ago      │
│ Source: RBN (W3LPL)     │
│ SNR: 22 dB              │
│ Distance: 6,840 mi      │
│ Bearing: 334°           │
│ Status: New mult (Zone) │
│ ─────────────────────── │
│ [Tune] [Blacklist] [Pin]│
└─────────────────────────┘
```

#### 4. Band Summary Bar (optional, Win-Test inspired)

```
┌──────────────────────────────────────────┐
│ 20m: 47 spots │ 12 new │ 3 mults │ ~180 pts │
└──────────────────────────────────────────┘
```

Shows at-a-glance whether the current band is worth staying on.

### Keyboard Navigation (Contest Role)

| Key | Action |
|-----|--------|
| `↓` / `↑` | Jump to next/previous spot on band |
| `⌥↓` / `⌥↑` | Jump to next/previous multiplier |
| `⇧↓` / `⇧↑` | Jump to next/previous spot (inactive radio, SO2R) |
| `Space` | Confirm callsign from auto-populated spot |
| `⌘⌥O` | Manual spot entry at current frequency |
| `⌘⌥D` | Remove spot at current frequency |
| `Escape` | Return to CQ frequency |
| `⌘+` / `⌘-` | Zoom bandmap in/out |

### Integration Points

| CW Sweep Service | Band Scope Usage |
|------------------|-----------------|
| `SpotAggregator` | Primary data source — already has EnrichedSpot with distance, region, DXCC |
| `RadioManager` | VFO position, click-to-tune, split info |
| `DXCCNeededChecker` | Needed status for DXCC color coding |
| `ClusterWorkedBeforeChecker` | Dupe/worked-before status |
| `BandEdges` | Frequency axis rendering, sub-band boundaries |
| `SelectionState` | Selected spot → inspector panel |
| `OperatingRole` | Default filter config + color scheme per role |

### Spot Aging Algorithm

```
effectiveAge = actualAge × ageFactor(source)

ageFactor:
  RBN     → 2.0 (ages twice as fast — transient by nature)
  Cluster → 1.0 (standard)
  POTA    → 0.5 (activators hold freq longer)
  SOTA    → 0.5
  WWFF    → 0.5
  DX Web  → 1.0

opacity = max(0.2, 1.0 - (effectiveAge / maxAgeMinutes))

Spot removed when effectiveAge > maxAgeMinutes
Re-spot resets the timer
```

---

## Role-Based Defaults

| Setting | Contester | Hunter | DXer | Activator | Casual |
|---------|-----------|--------|------|-----------|--------|
| Color scheme | Contest | Source | DXCC | Source | Freshness |
| Max age | 15 min | 30 min | 45 min | 30 min | 60 min |
| Default status | All | New | Needed | All | All |
| Hide dupes | No (gray) | No | Yes | No | No |
| Default sources | RBN+Cluster | All | RBN+Cluster+DX | POTA+SOTA+Cluster | All |
| Declutter | Off | On | Off | On | On |
| Show source badges | No | Yes | No | Yes | Yes |

---

## Implementation Phases

### Phase 1: Enhanced Horizontal Band Scope
- Color scheme system (contest/dxcc/freshness/source) on existing `BandMapView`
- Gradient aging (opacity fade based on spot age)
- VFO + TX position markers with filter width shading
- Sub-band boundary visualization (CW/Digital/SSB shading)
- Spot detail popover on hover

### Phase 2: Filter Bar
- Source toggles (SpotSource checkboxes)
- Status filter (new/needed/mults/all) integrated with DXCCNeededChecker + WorkedBeforeChecker
- Age slider with configurable max
- Region filter dropdown
- Filter persistence per OperatingRole via @AppStorage

### Phase 3: Vertical Band Scope
- New `ContestBandScopeView` with vertical frequency axis
- Callsign text labels positioned by frequency
- Keyboard navigation (↓/↑ for spots, ⌥↓/↑ for mults)
- Click-to-tune integration with RadioManager
- Auto-populate callsign when VFO enters tuning tolerance

### Phase 4: Contest Intelligence
- Band summary bar (spots/new/mults/points available)
- Cross-band mult indicators
- CQ frequency bookmark
- SO2R dual bandmap layout

---

## Decisions (resolved 2026-03-26)

1. **Filter width from radio — YES.** Add CAT commands to read IF filter bandwidth. Start with Elecraft (`BW`) and FlexRadio (`filter_lo`/`filter_hi` already in slice subscriptions), then CI-V (`0x1A 0x06`) and Yaesu (`SH`). 2-3 commands per handler. Enables VFO passband shading and tuning tolerance in Phase 3.

2. **Snap-to-nearest-spot — YES, default on.** Snap to nearest spotted frequency when clicking the bandmap. 2 kHz tolerance for CW, 5 kHz for SSB. Prefer fresh spots when equidistant. ⌥+click overrides for exact frequency. No spectrum data needed.

3. **Spot persistence — MANUAL/PINNED ONLY.** Don't cache RBN/HTTP spots — they reload in 30 seconds and would be misleadingly stale on launch. Persist only user-pinned/bookmarked spots. Cluster replays recent spots via `SH/DX` on reconnect.

4. **Callsign decluttering — PRIORITY + ZOOM-ADAPTIVE.** Full-band zoom: colored dots for all spots, callsign labels only for mults and fresh spots (ranked by existing `spotPriority()`). Zoom in → progressively reveal more labels. Dupes get labels last. Win-Test-style LIST toggle as escape valve for extreme density.

5. **Local CW Skimmer — YES, but Phase 2+.** Reuse `TelnetClusterClient` as a second instance connecting to localhost:7300. Tag as `.localSkimmer` source. Highest priority in dedup (above RBN and cluster). Non-blocking — most users won't have one.

6. **Canvas performance — TEST FIRST.** Profile with realistic contest load before optimizing. SwiftUI Canvas is hardware-accelerated — expect 200-300 spots to be fine. If degradation found: add spatial bucketing (1 kHz bins), render budget (cap ~200 labels), debounce SpotAggregator to 1-2 Hz, binary search hitRects.
