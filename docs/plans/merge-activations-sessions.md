# Plan: Merge POTA Activations and Sessions

## Goal

Remove the separate "POTA Activations" and "Sessions" tabs from LogsContainerView, replacing them with a single unified "Sessions" list that is as content-rich as the current POTA Activations view.

## Current State

### POTA Activations row shows:
- Date (headline), park reference, callsign
- Custom title (from ActivationMetadata)
- QSO timeline bar (colored by band, with gap breaks)
- Upload status icon + text (e.g., "10 QSOs accepted", "3/5 submitted")
- Power badge (e.g., "5W"), WPM badge (e.g., "18 WPM")
- Solar/weather condition gauges
- Upload button for pending activations
- Context menu: Edit Metadata, View Map, Export ADIF, Share Card, Reject Upload
- Swipe to reject
- NavigationLink to POTAActivationDetailView

### Sessions row shows:
- Activation type icon + display title (e.g., "AJ7CM at K-1234")
- Date (abbreviated)
- QSO count + duration
- Recording badge (red waveform icon)
- Photo count badge
- NavigationLink to SessionDetailView or RecordingPlayerView

## Design

### Approach: Enrich Sessions list to match POTA Activations, then remove the POTA Activations tab

The unified list will show **all sessions** (POTA, SOTA, casual) with rich content. POTA sessions get the full activation experience (timeline, upload status, conditions). Non-POTA sessions get timeline + equipment badges.

### Step 1: Create a unified session row component

New file: `CarrierWave/Views/Sessions/SessionRow.swift`

The `SessionRow` view renders a rich card for any session type:
- **Line 1:** Date (headline) + activation reference (if any) + callsign
- **Line 2:** Custom title (if set)
- **Line 3:** QSO timeline bar (reuses `QSOTimelineView`)
- **Line 4:** Status chips row:
  - For POTA: upload status icon + text (reuse POTAActivation display helpers)
  - For all: power badge, WPM badge, mode badge, band(s)
  - Recording indicator, photo count indicator
- **Line 5:** Solar/weather condition gauges (for POTA with metadata)
- **POTA only:** Upload button when there are pending QSOs

This row needs:
- The `LoggingSession` model
- QSOs for the session (loaded by parent)
- The matching `POTAActivation` (if POTA type, for upload status)
- `ActivationMetadata` (if available)
- Recording flag

### Step 2: Update SessionsView to load rich data

Enhance `SessionsView` to:
- Load QSOs per session (batch, using `.task`)
- For POTA sessions, compute POTAActivation groupings to get upload status
- Load ActivationMetadata for POTA sessions
- Load recordings (already does this)
- Accept `potaClient`, `potaAuth`, `tourState` dependencies for POTA upload functionality
- Support POTA upload, reject, share, export, map actions (same as POTAActivationsContentView)
- Support context menus and swipe actions

### Step 3: Update LogsContainerView

- Change `LogsSegment` to only have `.qsos` and `.sessions`
- Remove `.potaActivations` case
- Pass required POTA dependencies to `SessionsView`

### Step 4: Handle POTA sessions that don't have a LoggingSession

Some older POTA activations may not have corresponding LoggingSession records (imported QSOs, or QSOs logged before sessions were added). These need to still appear.

Strategy: After loading sessions, also compute "orphan" POTA activations (activations whose QSOs don't reference any session) and display them in the list as virtual session entries, interleaved by date.

### Step 5: Navigation destinations

- POTA sessions navigate to `POTAActivationDetailView` (same as before)
- Non-POTA sessions navigate to `SessionDetailView` (same as before)
- Sessions with recordings navigate to `RecordingPlayerView` (same as before)

## Files to Change

| File | Change |
|------|--------|
| `CarrierWave/Views/Sessions/SessionRow.swift` | **NEW** - Unified rich session row |
| `CarrierWave/Views/Sessions/SessionsView.swift` | Major rewrite - load rich data, POTA actions |
| `CarrierWave/Views/Logs/LogsContainerView.swift` | Remove POTA Activations segment, pass deps to Sessions |
| `docs/FILE_INDEX.md` | Add new file, note changes |
| `CHANGELOG.md` | Add entry |

## Files NOT Changed (reused as-is)

- `POTAActivationLabel.swift` / `ActivationLabel` - Won't be used directly; the new SessionRow inlines similar content
- `QSOTimelineView.swift` - Reused directly in SessionRow
- `ActivationConditionsComponents.swift` - Reused directly
- `POTAActivationsHelperViews.swift` - Upload display helpers reused
- `POTAActivationDetailView.swift` - Still the detail destination for POTA sessions
- `POTAActivationsView.swift` - Kept for now (the content view logic for uploads, jobs, etc. moves into SessionsView)

## Out of Scope

- Changing POTAActivationDetailView
- Changing SessionDetailView
- Bulk selection (can add later)
- Share card generation (keep existing activation share)
