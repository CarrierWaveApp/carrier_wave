# Band Scope Redesign — Research & Mockups

**Status:** Design exploration, 2026-04-07
**Branch:** `claude/band-scope-redesign`
**Mockups:** see [`mockups/`](mockups/) — open `mockups/index.html` in a browser

---

## Why we are doing this

Two motivating use cases:

1. **Multi-band situational awareness.** The "should I QSY to 15 m?" question. Today, answering it means clicking the band picker, waiting for the view to repopulate, eyeballing it, then clicking back. There is no way to see two bands at once. The `BandSummaryBar` at the bottom of the existing scope shows per-band mult counts as tiny chips, but you can't see *what* is on those bands without switching.
2. **Contest S&P.** Find new mults, new stations, on the current band fast. The current scope can do this — barely — but the interactions are fighting you the whole time.

The pain point is **clunky interactions**, specifically click-to-tune, zoom/pan, and cursor tracking. The current scope has the right *information density* but the wrong *interaction model*.

---

## What is actually broken right now

I read the code carefully (`ContestBandScopeView.swift`, `+Waterfall`, `BandScopeFilterBar`, `BandSummaryBar`, `BandEdges`). What follows is concrete, not vibes.

### Click-to-tune

- **The zoom-aware coordinate math is wrong.** `handleTap` falls back to a "snap to nearest spot within 2 kHz" computation that uses `band.upperKHz - (location.y / canvasHeight) * band.widthKHz`. This formula does **not** account for `panOffset` or `zoomScale`. As soon as the operator zooms in or pans, every click-on-empty-space resolves to the wrong frequency. The hit-rect path (clicking directly on a callsign label) still works because hit rects are computed from the same `yPosForFreq` the labels were drawn at — but the moment the operator misses a label by a few pixels, they're tuned somewhere else entirely.
- **No mode-aware snap.** The 2 kHz snap radius is arbitrary. A CW operator wants ~250 Hz tolerance; an FM operator on 10 m needs 5 kHz. The radio's own filter width (which the code already knows about — see `drawVFOCursor`) should drive snap.
- **No "click to tune to this exact frequency."** Empty space outside the snap radius is dead space. The operator who wants to park on a clear spot to call CQ has to drag the radio dial instead.
- **Click does two things at once.** Clicking a spot label both selects it and tunes immediately. There is no "select to inspect, then tune" pattern, which contest operators sometimes want when comparing two adjacent spots.

### Zoom and pan

- **No keyboard zoom.** Pinch-to-zoom and scroll-wheel zoom only. Power users want `+`/`-` or `Cmd-+`/`Cmd--`.
- **Scroll wheel does the wrong thing when zoomed.** Right now scroll = zoom always. The natural expectation is scroll = zoom when *not* zoomed, scroll = pan when zoomed in. (Modifier keys can flip this.)
- **No "fit band" / reset.** No keystroke or button to return to 1.0× zoom. The operator has to pinch-out or magic the scroll wheel until they get there.
- **No saved zoom regions.** The CW DX window (14.000–14.040), the SSB DX window, the digital sub-bands — these are all "zoom presets" the operator wants by name. None exist.
- **No mini-map / overview when zoomed.** Once you zoom in, you lose the sense of where you are in the band. There is no thumbnail showing the full band with a viewport rectangle.
- **Band switching nukes zoom state.** `autoSwitchBand` resets to 1.0× implicitly because zoom state is per-band-canvas, not per-band. Move to 15 m, come back to 20 m — your saved zoom is gone.

### Cursor / tracking

- **The hover tooltip is pinned to the right edge.** It does not follow the cursor. On a wide window the operator's eye has to jump from the cursor to the right margin to read what they're hovering.
- **No persistent crosshair.** There is a hover tooltip and a red VFO line, but no horizontal line that follows the *cursor* showing the frequency under the pointer.
- **The VFO frequency label overlaps the axis.** `drawVFOCursor` draws the red label at `x: plotX - 4`, anchored trailing — it sits directly on top of the axis tick labels in zoomed-out mode.
- **No "watch this frequency."** No way to drop a marker at a frequency you're listening for activity on. The contest operator who hears a weak signal at 14.023 wants to mark it without tuning, then come back later.
- **No second VFO cursor.** Modern contest radios with sub-receivers (K3, IC-7610, FTDX-101) have two independent VFOs. The scope doesn't know about VFO B.
- **No band-edge guide rails.** When zoomed deep, you can drift past the band edge without realizing it.

### Information that is missing or hidden

- **Cross-band activity is a footer chip strip.** `BandSummaryBar` shows per-band mult counts as tiny capsule chips below the scope. They are easy to miss and the scope itself wastes vertical space repeating the same information for the active band.
- **No aging gradient on the waterfall.** The waterfall has a fixed time depth with no per-line aging hint. Old lines and new lines look the same once they leave the leftmost column.
- **Filter state is buried.** The filter bar is collapsible but the *current* filter state is summarized only as "N sources hidden, M continents hidden" — you can't see *which* without expanding.
- **Sub-band shading is too subtle.** Digital and SSB sub-bands are drawn at 4% opacity. On a typical macOS display you can't see them at all.

---

## Reference points

Drawn from the references called out in the planning session.

### N1MM Logger+ stacked bandmaps

N1MM's killer move is showing **multiple bandmaps side by side**, each one narrow (a few hundred pixels wide), each one a vertical list of spots on that band. No waterfall, no spectrum — just spot text at frequency position, color-coded by mult/dupe state. You can see five bands at once on a wide monitor and instantly answer "where are the mults right now?"

What N1MM gets right:
- One column per band, each totally independent.
- Click-to-tune jumps both the band and the frequency in a single action.
- Mults are visually loud (color + bold) and dupes are faded.
- "Available Mults & Qs" is a separate window listing what you still need on each band — strategic context, not chrome.

What N1MM gets wrong (for our purposes):
- It is text-only — no spectrum, no waterfall, no cursor showing actual radio activity.
- The columns are not synchronized — you can't have a horizontal cursor at "right now" across all bands.
- No keyboard navigation between columns.
- The visual style is dated (Win32 controls).

### Modern SDR consoles (SDR#, HDSDR, SDRConsole, Console v3)

These are the gold standard for spectrum + waterfall interactions. What they get right:

- **Click anywhere = tune there.** Empty space, on a signal, between signals — all tune the VFO instantly. No "snap to spot" because there is no spot list, but the principle is "click is tune."
- **Drag the spectrum to pan, scroll wheel to zoom.** Modifier keys vary by console but the convention is consistent.
- **Persistent crosshair.** The cursor projects a vertical line down through the spectrum and waterfall, with the frequency under the cursor displayed in the corner.
- **Bandwidth indicator on the VFO.** A translucent rectangle on the spectrum shows the current filter passband, not just a line. (CW Sweep already has this — keep it.)
- **Markers / bookmarks.** Click to drop a named marker at a frequency. The marker persists until you delete it.
- **Mini-map.** Console v3 shows a thin overview strip above the main spectrum with a draggable viewport rectangle.
- **Mouse-wheel-over-VFO-digit fine tune.** Hover the mouse over a digit of the frequency display, scroll wheel adjusts that digit. Sounds gimmicky, is incredibly useful.

What they don't do, but we should:
- They have no notion of a "spot." There is no concept of "a callsign is here" — it's just RF.
- They are single-band only, by design (each instance follows one SDR receiver).

### Trading platform multi-chart layouts (Bloomberg / TradingView)

The relevant pattern is the **synchronized multi-chart grid**. TradingView lets you have a 2×2 grid of charts, each on a different symbol, all sharing a time axis cursor. Move the mouse on chart A and the crosshair appears on chart B at the same time. Click into a chart to "expand" it to full width temporarily.

What this teaches us:
- **A grid of small scopes is a viable layout** if the cursor / time axis is shared across them.
- **Drill-down is essential.** No one operates from the small grid view — they operate from the big single view, and use the grid for context.
- **The grid view has lower interaction density.** It is for *scanning*, not for *acting*. Acting happens in the expanded view.

---

## Design space

Five mockup variants live in [`mockups/`](mockups/). Each one tests a different point in the design space. None of them are "the answer" — they are five thought experiments to react to.

### 0. [Current state, annotated](mockups/00-current.html)
The existing scope, drawn to spec from the code, with the pain points highlighted in callouts. Reference for the rest.

### 1. [Single-band, refined](mockups/01-single-band-refined.html)
Same layout as today, but with every interaction pain point fixed:
- Persistent cursor crosshair tracking the mouse with frequency readout
- Mini-map overview rail on the left edge with draggable viewport
- Mode-aware click-to-tune snap (uses radio's filter width)
- Click empty space to tune to that exact frequency
- Keyboard zoom/pan/reset (`+`/`-`/`0`/arrow keys)
- Tooltip follows cursor instead of pinning to the right edge
- Sub-band shading at a visible opacity
- Active filter chips inline in the header
- Per-band zoom state preserved across band switches
- Bandwidth marker on VFO matches active mode visibly
- "Watch frequency" markers (drop a flag without tuning)

This is the **lowest-risk option**. It does not change the layout, just removes the friction. If we ship only this, the scope is meaningfully better.

### 2. [Stacked bands (N1MM-inspired)](mockups/02-stacked-bands.html)
Five band columns side by side: 80 / 40 / 20 / 15 / 10 m. Each column is a narrow vertical list of spot labels at frequency position, no waterfall. The active band has a green outline. Click any spot in any column to tune both the band and the frequency. Keyboard `←` / `→` switches active column, `↑` / `↓` navigates spots within the column.

This is **the contest answer**. Maximum cross-band situational awareness. Trades the live spectrum for the ability to see five bands at once. Best on a wide monitor (≥1600 pt) — laptop screens can show three or four columns comfortably.

### 3. [Grid overview (TradingView-inspired)](mockups/03-grid-overview.html)
A 4×3 grid of small per-band cells, each showing a tiny vertical density histogram of spots on that band, mult count, new-mult count, and a "heat" indicator for activity over the last 5 minutes. Click a cell to expand it into the main scope view (variant 1) below the grid. The grid is for scanning, the expanded view is for acting.

This is the **scanning answer**. Lowest interaction density per band, but the only layout where you can see all 11 HF bands at once. Useful for the "is anything happening on 6 m right now?" question.

### 4. [Hybrid: active band wide + rail (Recommended)](mockups/04-hybrid-active-with-rail.html)
The big active-band scope on the left (variant 1, full width minus a column), with a thin **band rail** down the right side. The rail is one row per band: band label, mult count (color-coded), new-spot count, last-spot age dot, and a 12-pixel wide spot density sparkline for that band. Click any rail row to QSY the radio to that band's last-tuned frequency (or the strongest spot on it).

This is **the recommended starting point**. It keeps the live spectrum experience contesters and DXers expect, gives them cross-band situational awareness as peripheral context, and the rail interaction mirrors the main scope's click-to-tune model. It is also the smallest delta from today's layout — the rail can replace the existing `BandSummaryBar` chip strip.

### 5. [Multi-VFO + watch list](mockups/05-multi-vfo-watchlist.html)
Variant 1 plus a second VFO cursor (for radios with sub-receivers), a watch-list strip below the scope showing dropped frequency markers, and a "history trail" line showing where the radio has been in the last few minutes. This is a power-user variant for K3 / IC-7610 / FTDX-101 operators running both VFOs in a contest.

This is **forward-looking**. Most users don't have a sub-receiver radio. Worth mocking up because the architecture decisions for cursor tracking should leave room for a second cursor; otherwise we'll repaint the whole interaction layer in a year.

---

## Recommendation

Build in this order:

1. **Variant 1 (single-band refined) first.** Every fix in it is a bug-fix, not a redesign. Each one stands alone and ships independently. Land them as they're ready. Specific commits I'd want:
   - Fix zoom-aware click-to-tune coordinate math (the wrong-frequency-when-zoomed bug)
   - Cursor crosshair + frequency readout
   - Mini-map overview rail
   - Keyboard zoom/pan/reset
   - Mode-aware snap radius
   - Per-band zoom state preservation
   - Tooltip follows cursor
2. **Variant 4 (hybrid with rail) next.** Replace the existing `BandSummaryBar` chip strip with the band rail. This is the multi-band situational awareness unlock and it leaves the active scope alone.
3. **Variant 2 (stacked bands) as an opt-in layout** for contesters with wide monitors. Not the default. Tied to a layout preset.
4. **Variant 5 (multi-VFO)** when a user with a sub-receiver-capable radio asks for it.
5. **Variant 3 (grid overview)** is interesting but I'm least sure it's worth the build cost. It addresses scanning, which the rail in variant 4 mostly already covers.

---

## Open questions

These are tractable but I want input before any code lands:

- **Variant 4 rail width.** The mockup uses 180 pt. That eats meaningful horizontal space on a 1280-wide laptop. Should it be collapsible?
- **Variant 2 column count.** On a 1440 pt laptop screen we fit 4 columns comfortably (≈ 320 pt each). The N1MM operator wants 6+. Do we hide some bands by default? Configurable per role?
- **Click-empty-space tuning.** This is a behavior change with no current equivalent. Some operators will hate it because it makes errant clicks expensive. Modifier-keyed (Option-click)?
- **Watch markers persistence.** Per-session? Per-day? Stored in SwiftData? Decoupled from QSO log?
- **Cross-radio scope data.** We currently get waterfall from one connected SDR. If a user has two radios connected (HF + VHF), do we show both spectrums or only the active one?

---

## Implementation notes (for whoever picks this up)

The current scope is 499 lines in one file. Variant 1's fixes are all localized to:
- `handleTap` and the inverse-Y math
- `panGesture`, `zoomGesture`, `handleScrollWheel` — add keyboard counterparts
- `drawVFOCursor` — split label and line, add cursor crosshair
- `scopeCanvas` — add mini-map overlay
- A new `@State private var bookmarks: [FrequencyBookmark]` for watch markers
- A new `@AppStorage("bandScopeZoomPerBand") var zoomStates: Data` for preserving zoom

Variant 4's rail is a new SwiftUI view (`BandRailView`) that replaces `BandSummaryBar`. It reads from the same `SpotAggregator`. Each row is a `Button` that calls `radioManager.tuneTo(...)`. Sparkline rendering can be a small `Canvas` per row, computed from `spotAggregator.spots.filter { $0.spot.bandId == band.id }`.

Variant 2 (stacked) is the biggest change — it's a new top-level view (`StackedBandScopeView`) that holds N `ContestBandScopeColumn` children. Each column is a stripped-down version of the current view: no waterfall, no mini-map, just labels and selection. The architecture should let `ContestBandScopeView` remain a single-band view used by both the standalone scope and as a column inside `StackedBandScopeView`.
