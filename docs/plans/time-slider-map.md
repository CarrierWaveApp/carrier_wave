# Time Slider Map View — Session Replay

Interactive map view in session detail that replays RBN spots and QSOs chronologically with a time slider, optionally synced to an available WebSDR recording.

## Data Model

### `TimelineMapEvent` (new, in-memory struct)
Unified event type combining QSOs and SessionSpots for the timeline:
```swift
struct TimelineMapEvent: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let kind: Kind // .qso or .rbnSpot
    let callsign: String
    let band: String
    let mode: String
    let coordinate: CLLocationCoordinate2D? // resolved from grid
    let snr: Int? // RBN only
    let spotter: String? // RBN only
    let spotterCoordinate: CLLocationCoordinate2D? // RBN skimmer location

    enum Kind { case qso, rbnSpot }
}
```

### `TimelineMapDataActor` (new background actor)
Loads QSOs + SessionSpots for a session, resolves grid squares to coordinates, and returns sorted `[TimelineMapEvent]`. Follows the existing `MapDataLoadingActor` pattern with `FetchDescriptor` + `fetchLimit`.

## New Files

| File | Purpose |
|------|---------|
| `CarrierWave/Views/Sessions/TimelineMapView.swift` | Main view: Map + time slider + controls |
| `CarrierWave/Views/Sessions/TimelineMapDataActor.swift` | Background data loading actor |
| `CarrierWave/Views/Sessions/TimelineSliderView.swift` | Custom slider with event tick marks and recording waveform underlay |

## View Structure — `TimelineMapView`

```
NavigationLink from SessionDetailView.mapSection
├── Map (top ~60% of screen)
│   ├── User location marker (myGrid)
│   ├── QSO markers (blue pins, appear as time progresses)
│   ├── RBN spot markers (green dots with SNR labels, fade after 10min)
│   ├── Geodesic arcs (user → QSO/spot)
│   └── Heatmap-style density for accumulated RBN spots
├── Timeline Slider (bottom ~40%)
│   ├── Time scrubber bar
│   │   ├── QSO tick marks (blue, taller)
│   │   ├── RBN tick marks (green, shorter)
│   │   └── Optional: recording waveform underlay (if recording exists)
│   ├── Current time label + elapsed/remaining
│   ├── Playback controls: Play/Pause, 1x/2x/4x speed
│   └── Optional: recording audio sync toggle
└── Legend (compact, collapsible)
```

### Playback Behavior
- **Scrub mode**: Dragging the slider jumps to that point in time; map shows all events up to that moment
- **Play mode**: Timer advances automatically; new events animate onto the map
- **RBN spot decay**: Spots appear green, fade to gray after 5 minutes of session time, disappear after 10 minutes (configurable)
- **QSO persistence**: QSOs stay on the map once they appear (solid markers)
- **Speed**: 1x (real-time), 2x, 4x, 8x playback speed

### Recording Integration
- When a `WebSDRRecording` exists for the session, show the amplitude waveform as a backdrop behind the timeline slider (reuse `RecordingWaveformView` rendering logic)
- Toggle button to enable audio sync: when enabled, seeking the map slider also seeks the recording, and vice versa
- Uses existing `RecordingPlaybackEngine` for audio playback
- Time alignment: `recording.startedAt` aligns to session time; slider position maps to `recording.startedAt + offset`

## Integration Points

### SessionDetailView Changes
- Add a NavigationLink in `mapSection` (or a new section below it) labeled "Session Replay" with a play icon
- Only show when session has ≥ 1 QSO with a valid grid AND session has spots or recording
- Pass `session`, `recording` (if available), and `engine` to `TimelineMapView`

### Data Flow
1. `.task` on `TimelineMapView` calls `TimelineMapDataActor.loadEvents(container:sessionId:)`
2. Actor fetches QSOs with `loggingSessionId == sessionId` predicate + SessionSpots with same session ID
3. Resolves grids to coordinates via `MaidenheadConverter`
4. Returns sorted `[TimelineMapEvent]` + session metadata (myGrid, startedAt, endedAt)
5. View stores events in `@State`, computes visible subset based on slider position

### Performance
- All data loading on background actor (existing pattern)
- Events array is pre-sorted by timestamp; visible subset computed with binary search / `prefix(while:)`
- Map annotations limited to visible events only (no unbounded iteration)
- RBN spot decay computed by comparing event timestamp to current slider position

## Implementation Order

1. **TimelineMapDataActor** — data loading and event model
2. **TimelineSliderView** — custom slider with tick marks
3. **TimelineMapView** — map + slider + playback logic
4. **Recording integration** — waveform underlay + audio sync
5. **SessionDetailView integration** — NavigationLink + conditional display
6. **FILE_INDEX.md** — update with new files
