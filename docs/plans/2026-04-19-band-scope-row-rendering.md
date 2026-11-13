# Band Scope Row Rendering Redesign

**Date:** 2026-04-19
**Scope:** `ContestBandScopeView` and its extensions in CW Sweep

## Summary

Redesign the band scope from floating callsign labels to structured rows with diagonal leader lines connecting each row to its true frequency position on a linear axis. Add right-click context menu, vim-style keyboard navigation, shortcut help overlay, and fit-to-spots zoom.

## Design Decisions

### 1. Three-Column Layout

The scope canvas is divided into three visual zones (all drawn in a single Canvas):

- **Frequency axis** (~56px, left): Linear frequency scale with tick marks at spot positions and at regular intervals. VFO cursor, sub-band boundaries, and bookmarks drawn here. This axis is always true to scale.
- **Leader line gutter** (~60px, middle): Diagonal lines connecting each axis tick to its corresponding row. Line color matches spot color. Thickness/opacity scales with priority (new entity/band slot = thicker, brighter).
- **Spot rows** (remaining width, right): Evenly-spaced rows, each showing: callsign, priority badge (NEW ENTITY / NEW BAND), source + age. No frequency numbers in rows. Rows have hover highlights and are click/right-click targets.

### 2. Row Layout Algorithm

When spots are spread out, rows sit at their true frequency y-position and leader lines are horizontal. When spots cluster tightly (row height > frequency gap), rows push apart to avoid overlap:

1. Sort spots by frequency (ascending, matching current `sortedSpots`).
2. Compute true y-position for each spot using existing `yPosForFreq()`.
3. Walk top-to-bottom: if a row's true y-position would overlap the previous row (less than `rowHeight` gap), push it down to `previousRowBottom + spacing`.
4. Draw diagonal leader line from axis tick (at true y) to row left edge (at displaced y).
5. If a row is not displaced, no leader line is needed (or draw a horizontal one for consistency).

Row height: ~26px (enough for 12-13px callsign + padding). Spacing between rows: 1px.

### 3. Right-Click Context Menu

Native macOS context menu (SwiftUI `.contextMenu`) on each spot row:
- **Tune to [freq]** — tunes radio (same as click)
- **Copy Callsign** — copies to clipboard
- **Lookup on QRZ** — opens `https://www.qrz.com/db/[callsign]` in default browser
- **Add Watch Marker** — adds a `FrequencyBookmark` at the spot's frequency
- **Show in Spot List** — sets `selectionState.selectedSpot` to scroll SpotListView

### 4. Vim-Style Keyboard Navigation

Replace current arrow-key bindings:

| Action | Key |
|--------|-----|
| Next spot (down) | `j` |
| Prev spot (up) | `k` |
| Next mult | `J` (shift+j) |
| Prev mult | `K` (shift+k) |
| Tune selected | `⏎` (keep) |
| Watch marker | `m` (keep) |
| Zoom in | `+` or `=` |
| Zoom out | `-` |
| Fit/reset | `0` |
| Pan down (lower freq) | `l` |
| Pan up (higher freq) | `h` |
| Help overlay | `?` |

Arrow keys no longer handled (return `.ignored` to let them propagate).

### 5. Keyboard Shortcut Help Overlay

- Remove all shortcut hints from the footer
- Footer keeps: spot/new/mult counts, zoom controls, FIT button, `?` button
- Pressing `?` toggles a floating overlay (ZStack layer above canvas) showing all shortcuts in a two-column grid
- Overlay dismisses on any keypress, click, or pressing `?` again

### 6. Fit-to-Spots Zoom

New "FIT" button (already in footer) and keyboard shortcut `0`:
- Computes the frequency range containing all visible spots on the current band
- Adds 5% padding on each end
- Sets zoom and pan to frame that range
- If no spots, resets to 1× (full band view)

This replaces the current `resetZoom()` behavior of `0` which always goes to 1×. The button label changes from "FIT" to "FULL" when already fitted, toggling between fit-to-spots and full-band views.

## Files to Modify

| File | Changes |
|------|---------|
| `ContestBandScopeView.swift` | Remove `hitRects` state, add `showHelp` state, update `body` layout, add context menu |
| `ContestBandScopeView+Rendering.swift` | Rewrite `scopeCanvas` and `drawSpotLabels` → new three-column rendering with row layout algorithm and leader lines. Update `drawFrequencyAxis` to draw spot ticks. |
| `ContestBandScopeView+Interaction.swift` | Rewrite `handleKeyPress` for vim keys, add `?` toggle, update `handleTap` for row hit testing, add `fitToSpots()` |
| `ContestBandScopeView+MiniMap.swift` | No changes expected |
| `ContestBandScopeView+Waterfall.swift` | No changes expected |

## What's NOT Changing

- Mini-map rail (left sidebar)
- Waterfall rendering
- Zoom/pan gestures (pinch, scroll wheel, drag)
- Band switching and auto-switch on VFO change
- Color modes and aging
- Filter bar and header controls
- `BandScopeContainerView` layout switching
- Per-band zoom state preservation

## Rendering Approach

All rendering stays in Canvas (not SwiftUI views per row). This is critical for performance with 30+ spots. The three-column layout is drawn in a single Canvas pass:

1. Draw sub-band shading (existing)
2. Draw waterfall (existing)
3. Draw frequency axis with spot ticks
4. Compute row layout (displacement algorithm)
5. Draw leader lines (axis tick → row position)
6. Draw VFO cursor (spans axis + gutter)
7. Draw spot rows with hit rects
8. Draw bookmarks on axis

Hit testing uses the same `hitRects` array pattern, but rects now cover full row width.
