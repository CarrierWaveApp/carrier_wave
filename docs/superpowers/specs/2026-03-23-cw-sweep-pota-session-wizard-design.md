# CW Sweep POTA Session Wizard

**Date:** 2026-03-23
**Status:** Draft
**App:** CW Sweep (macOS)

## Overview

A POTA-focused session setup wizard for CW Sweep that replaces the ActivatorLayout empty state with an inline setup panel. Designed for a field radio operator at a laptop with a connected radio — optimized for fast launch with optional depth, visual frequency selection, and rove planning.

## Goals

- Get on the air in under 10 seconds for a standard activation (park search → confirm → Start)
- Show band activity visually so operators pick clear frequencies before keying up
- Leverage the connected radio to auto-detect frequency and mode
- Support rove planning with a map-based stop planner
- Enforce operator class band privileges to prevent out-of-band operation
- Provide spotting commands adapted for keyboard-driven macOS operation

## Non-Goals

- Generalizing to all session types (contest, casual, SOTA-only) — POTA-first, generalize later
- Replacing the iOS session start flow — this is a macOS-native design
- SDR auto-start (iOS feature, not needed when laptop is the primary)

## Architecture: Inline Panel in ActivatorLayout

The wizard is **not** a modal sheet. When no session is active, the ActivatorLayout content area **is** the setup wizard. Starting a session transitions the same space to the logger/spots view. This means:

- Non-modal: sidebar, radio controls, and spot feeds remain accessible during setup
- Seamless transition from "setting up" to "operating"
- The existing `NewSessionSheet` in `SessionsListView` (CW Sweep's basic session creation form) is superseded for POTA activations

### State Flow

```
ActivatorLayout
  ├─ No active session → POTASetupView (the wizard)
  └─ Active session → Logger + Spots (existing ActivatorLayout content)
```

## Layout: Two-Phase Design

### Phase 1: Essentials (Always Visible)

A single row at the top containing everything needed for a quick launch:

| Element | Behavior |
|---------|----------|
| **Park search** | Primary interaction. Search by name, state, or reference number. Shows recent parks. Auto-resolves grid square. |
| **Callsign** | Auto-filled from settings. Expandable prefix/suffix controls (click "+ prefix/suffix" to disclose). |
| **Operators** | Chip list starting with the user's callsign. Text field to add operators — auto-commits on comma/space/Enter. |
| **Start button** | Disabled with reason label until park is selected. Enabled state shows "Start ▶". |

Radio connection status shown in the top bar (radio name + green dot when connected).

### Band Map (Always Visible, Below Essentials)

Two-tier frequency visualization:

**Full band overview strip:**
- Shows entire band (e.g., 7.000–7.300 MHz for 40m)
- Mode segments color-coded: CW/Digital (purple), Phone (green)
- Operator class boundaries enforced from settings:
  - Extra-only zones shown with hatched overlay pattern
  - Red dashed boundary line between Extra and General privilege areas
  - Clicking in a restricted zone shows a warning instead of tuning
- Band quick-switch pills below (160m through 6m)

**Zoomed view (below overview):**
- Centered on radio's current VFO frequency
- Scroll to zoom, drag to pan
- Individual spots shown with callsigns and exact frequencies
- Spot source color coding:
  - Amber: RBN / DX Cluster
  - Green (with 🌲): POTA activators
  - Blue (with ⛰): SOTA activators
  - Blue (with 🌿): WWFF activators
- Current VFO position: red vertical line with "▼" marker
- Clear-zone indicator: dashed green border showing clear space around VFO
- **Click to tune**: clicking an open frequency tunes the radio via CAT

**Data sources:** SpotAggregator (all sources: RBN, POTA, DX cluster, SOTA, WWFF). No filtering — show the full picture.

### Phase 2: Full Setup (Expandable)

Collapsed by default, toggled with disclosure control or `⌘⇧S`. Two-column layout:

**Left Column — Equipment & Details:**

| Field | Behavior |
|-------|----------|
| Radio | Auto-detected from RadioManager. Shows name + "Connected" badge. Not editable. |
| Antenna | Dropdown from saved equipment list. |
| Key | Dropdown, shown only when mode is CW. |
| Mic | Dropdown, shown only for voice modes (SSB/AM/FM). |
| Extra equipment | Free text field. |
| Power | Numeric field in watts. |
| Grid square | Auto-resolved from selected park reference. Editable override. |
| Attendees | Comma-separated callsigns. |
| Session notes | Multi-line text field. |

**Right Column — Rove Planner:**

| Element | Behavior |
|---------|----------|
| Rove toggle | "This is a rove" switch. When off, column shows single park on map. |
| Map | MapKit map showing numbered park markers with dashed route lines between stops. Click map to search nearby parks. |
| Stop list | Ordered list below map. Each stop shows: number, park reference, park name, grid, distance from previous stop. Drag handles to reorder. |
| Add stop | Search field or click map. Dashed-border "+" row at bottom. |
| Summary | "3 stops · ~20 mi total" with "Drag to reorder" hint. |

## Post-Start Behaviors

### On Session Start

1. **Tune radio** to the selected frequency and mode via RadioManager CAT commands
2. **Start spot feeds** — ensure SpotAggregator and RBN client are connected. Auto-connect if not running.
3. **Self-spot** — if auto-spot on start is enabled in settings, post a POTA self-spot
4. **Create LoggingSession** in SwiftData with all fields from the wizard
5. **Transition view** — ActivatorLayout switches from POTASetupView to the logger/spots layout

### Commands

| Command | Shortcut | Behavior |
|---------|----------|----------|
| Return to My Frequency | `⌘⇧R` | Tunes radio back to activation frequency and mode. Available in menu, command palette, and keyboard. |
| Edit Spot Comment | `⌘⇧C` | Opens popover to edit the spot comment for the current session. |
| Spot Now | `SPOT` in command palette | Post a POTA self-spot. `SPOT [comment]` overrides the session comment for this spot. Just `SPOT` uses the current session comment. |

All commands wired through `CWSweepCommands` via `FocusedValues`.

### P2P (Park to Park) Highlighting

- When a POTA spot appears for an activator near the operator's frequency, the spot list highlights it with a "P2P" badge showing distance and park info
- Double-clicking the P2P spot tunes the radio to their frequency

### Spotting System

**Manual spotting:**
- `SPOT` command in command palette (no dedicated keyboard shortcut — `⌘⇧P` is already command palette)
- `SPOT [comment]` posts with the given comment; bare `SPOT` uses session comment
- Edit Spot Comment (`⌘⇧C`) changes the persistent session comment

**Auto-spotting (all toggles in Settings → POTA, all default off):**
- Auto self-spot on session start
- Re-spot interval: 15 / 30 / 45 / 60 minutes (default 30 when enabled)
- Auto-spot on rove stop change
- Spot comment template with token substitution (e.g., `CW [BAND] [PARK]`)
- Subtle timer in ActivationHeader showing time until next auto-spot

**QSY behavior:** When the operator changes band/frequency, the spot comment auto-updates the band token but preserves custom text.

**Rove spotting:** Advancing to the next rove stop posts a new self-spot with the new park reference and resets the re-spot timer.

## Settings Additions

New settings under a "POTA" tab (or section in existing settings):

| Setting | Type | Default |
|---------|------|---------|
| License class | Picker: Technician / General / Extra | General |
| Auto self-spot on session start | Toggle | Off |
| Re-spot interval | Picker: 15 / 30 / 45 / 60 min | 30 min |
| Auto-spot on rove stop change | Toggle | Off |
| Spot comment template | Text | `[MODE] [BAND]` |

License class is used by the band map to enforce operator privilege boundaries.

## Data Model

Uses the existing `LoggingSession` model from CarrierWaveData — no schema changes needed. All fields map:

| Wizard Field | LoggingSession Property |
|-------------|------------------------|
| Park reference | `parkReference` |
| Callsign | `myCallsign` |
| Mode | `mode` (from radio) |
| Frequency | `frequency` (from radio or band map pick) |
| Programs | `programs` (always includes "pota") |
| Activation type | `activationType` (.pota) |
| Grid | `myGrid` (from park lookup) |
| Power | `power` |
| Radio | `myRig` (from RadioManager) |
| Antenna | `myAntenna` |
| Key | `myKey` |
| Mic | `myMic` |
| Extra equipment | `extraEquipment` |
| Attendees | `attendees` |
| Notes | `notes` |
| Rove | `isRove` |
| Operators | `operatorCallsigns` |
| Rove stops | Stored as `RoveStop` entries on LoggingSession |

## Key Implementation Notes

- **Band plan data**: `BandPlan` currently lives in `CarrierWave/Models/BandPlan.swift` (iOS app target). It needs to be moved to CarrierWaveCore (shared SPM package) so CW Sweep can use it. Additionally, operator class privilege boundaries (Extra/General/Technician sub-band edges per band) are new data that must be added.
- **Band map rendering**: CW Sweep already has `BandMapView` with Canvas rendering in the Hunter layout. The regulated band map for the wizard should extend this existing view with mode segment overlays, privilege boundaries, and zoom/pan — not a parallel implementation.
- **Park search**: Reuse `ParkEntryField` search logic from iOS (POTA API park lookup). Adapt for macOS text field conventions (no `textInputAutocapitalization`).
- **Rove planner map**: MapKit `Map` view with `Annotation` markers for stops. Route lines via `MapPolyline`.
- **Radio tuning on click**: Use existing `RadioManager.tuneToSpot(frequencyMHz:mode:autoXITEnabled:autoXITOffsetHz:)` for combined frequency+mode tuning. Individual `tuneToFrequency(_:)` and `setMode(_:)` are also available.
- **SPOT command**: Handle in the command palette action layer (not `RadioCommandParser`, which is in CarrierWaveCore and shouldn't contain POTA-specific spotting logic). Parse `SPOT [comment]` as a command palette text input pattern.
- **Return to My Frequency**: Store activation frequency/mode on session start, command reads it back and calls `RadioManager.tuneToSpot`.
- **Operator callsigns**: `LoggingSession.operatorCallsignsRawValue` is a JSON-encoded string array. The wizard's chip UI must serialize/deserialize via the model's `operatorCallsigns` computed property.
