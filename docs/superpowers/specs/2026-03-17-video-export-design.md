# Video Export — Design Spec

Export a polished, YouTube-ready video from a completed logging session. Combines a live map replay with synced WebSDR audio and event toast cards.

## Requirements

- **Post-session only** — export from session detail after all data is collected
- **Two modes:** highlight reel (2-5 min compressed) or full-length real-time replay
- **1080p landscape** (1920x1080, 30fps, H.264/AAC `.mp4`)
- **Audio optional** — WebSDR recording synced when available, video-only otherwise
- **Toast cards** for QSO, spot, POTA note, and QSY events
- **Spot visualization** — pulse/ripple animation (not markers/arcs like QSOs)
- **AVAssetWriter** — native Apple framework, no ffmpeg dependency
- **Portrait mode deferred** to a future iteration

## Pipeline Architecture

Three-stage pipeline running on a background actor:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Event Sequencer │───▶│ Frame Compositor │───▶│  Video Writer   │
│                  │    │                  │    │                 │
│ Sorts all events │    │ MKMapSnapshotter │    │ AVAssetWriter   │
│ into a timeline, │    │ + Core Graphics  │    │ H.264 + AAC    │
│ decides frame    │    │ overlays per     │    │ muxing          │
│ timing & pacing  │    │ frame            │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

Orchestrated by `VideoExportActor`, which owns progress reporting and cancellation.

## Event Sequencer

Takes raw session data and produces a frame-by-frame plan.

### Input

- `TimelineMapEvent`s (QSOs + spots with timestamps and coordinates)
- `SDRParameterEvent`s (QSY, mode changes with offsets)
- POTA notes from `ActivityItem` records (NOT from `QSO` rows — filter out metadata pseudo-modes using `QSOMode.isMetadata(_:)`)
- Session start/end times
- Selected mode (highlight vs. real-time)

### Output

A `VideoTimeline` — an array of `VideoMoment` structs:

```swift
struct VideoMoment: Sendable {
    let realTime: Date              // when it happened in the session
    let videoTime: TimeInterval     // when it appears in the video
    let events: [VideoEvent]        // what happens at this moment
    let cameraTarget: CLLocationCoordinate2D?  // camera pan target
    let cameraZoom: Double?         // camera zoom level
    let audioSourceOffset: TimeInterval?  // position in source recording (nil = silence)
}
```

### Event Merging

Events with the same `realTime` (within 1s tolerance) are merged into a single `VideoMoment` with multiple entries in `events`. Toast cards for merged events are queued and shown sequentially.

### Highlight Mode Compression

1. Collect all event timestamps into a sorted list (after merging)
2. For each gap between events:
   - Gap < 30s: keep at real-time (action is continuous)
   - Gap 30s–5min: compress to 3-5 seconds
   - Gap > 5min: compress to 5-8 seconds
3. Minimum screen time per event:
   - QSO: ~4-5s (toast slide in, hold, fade)
   - Spot: ~2s (pulse animation)
   - QSY: ~3s (card + camera pan)
4. Target duration: `(event_count * avg_screen_time) + compressed_gaps`, naturally 2-5 min for a typical 20-40 QSO activation

### Real-Time Mode

`videoTime == realTime - sessionStart`. No compression. Audio plays back 1:1.

### Camera Behavior

Map camera starts centered on the operator's location, zoomed to show all QSOs so far. On each new QSO, the camera smoothly interpolates over ~1s of frames to include the new contact. No jarring jumps.

## Frame Compositor

Renders each frame as a composited image using Core Graphics. Six layers, bottom to top:

### Layer 1 — Map Snapshot

`MKMapSnapshotter` at the current camera position/zoom. User-selectable style: standard, satellite, or hybrid (default: standard). Cached and reused when the camera hasn't moved between frames.

**Threading note:** `MKMapSnapshotter` must be called from the main thread. The compositor hops to `@MainActor` for each snapshot request via `await MainActor.run { ... }`, receives the resulting `UIImage`, then returns to the background actor for CG overlay compositing. When cancelled, call `snapshotter.cancel()` on any in-flight request.

### Layer 2 — Geodesic Arcs

QSO arcs drawn as solid, semi-transparent blue lines. Fade in over ~0.5s when their QSO appears. Persist for the rest of the video once visible.

### Layer 3 — QSO Markers

Colored pins at contact locations. Fade in with their arc. Persist. Callsign labels shown for the most recent 3-4 QSOs only — older labels fade out, markers remain.

### Layer 4 — Spot Pulses

Concentric rings expanding outward from the spotter's location. Ring expands from 0 to ~40pt radius over 1.5s, opacity fading from 0.8 to 0. Two rings staggered 0.5s apart for a ripple effect. A small dot remains for ~5s after the animation, then fades.

### Layer 5 — Toast Cards

Bottom of frame. Cards slide up over 0.3s, hold 3-4s, slide down over 0.3s. One card visible at a time; rapid events are queued.

Card design:
- Rounded rect, ~85% opacity dark background
- White text, SF Pro, ~18pt
- Event icon on the left (antenna for QSO, radio waves for spot, arrow for QSY, note icon for POTA comment)
- Format examples:
  - QSO: `QSO with KM4CFT · 1,247 mi · RST 599 / 579`
  - Spot: `Spotted by TI7W at 23dB via RBN`
  - Note: `KM4CFT noted on POTA: "UR mom does CW"`
  - QSY: `QSY to 7.043.5 CW`

### Layer 6 — HUD

Top bar with session info: callsign, park reference, frequency/mode, elapsed time. Semi-transparent strip. Updates on QSY events.

## Video Writer

### Video Track

`AVAssetWriter` configured for H.264 at 1920x1080, 30fps. Frames submitted via `AVAssetWriterInputPixelBufferAdaptor` from a reusable `CVPixelBufferPool`. Presentation timestamps from `videoTime`. Writer backpressure respected via `isReadyForMoreMediaData`.

### Audio — Real-Time Mode

WebSDR recording (PCM/CAF) read via `AVAssetReader`, written to a separate `AVAssetWriterInput` with AAC encoding. Timestamps mapped directly (1:1). Gaps in recording (late start, disconnects) filled with silence.

### Audio — Highlight Mode

Audio segments cut and stitched to match compressed timeline. Each `VideoMoment` stores an `audioSourceOffset: TimeInterval?` — the position in the source recording corresponding to `realTime`. This lets `VideoAudioMixer` seek precisely into the PCM file.

**Segment extraction:** A single `AVAssetReader` reads sequentially through the source file. For each preserved real-time cluster, it reads the corresponding sample range and writes to the output. For compressed gaps, it skips ahead in the source and writes silence (or a short crossfade) to the output.

Rules:
1. Event clusters where real-time is preserved: copy audio segment directly
2. Compressed gaps: silence with ~100ms crossfade at boundaries
3. No time-stretching (would distort CW/SSB audio). Clean cuts only.

### Audio — No Recording

No audio track. Video-only `.mp4`.

### Output

Saved to a temp directory, presented via `UIActivityViewController` for sharing (YouTube, Files, AirDrop). Not persisted unless the user explicitly saves.

## User Interface

### Entry Point

"Export Video" button on the session detail screen. Only enabled for sessions with at least 1 QSO that has coordinates.

### Export Configuration Sheet

- **Mode toggle:** "Highlight Reel" vs "Full Replay"
- **Estimated duration** (calculated by sequencer)
- **Audio toggle:** "Include WebSDR Audio" — shown only if a recording exists, on by default
- **Map style:** Standard / Satellite / Hybrid (segmented picker)
- **Export button**

No advanced settings for v1.

### Export Progress View

Replaces sheet content during rendering:
- Progress bar with frame count (`Frame 1,247 / 5,400`)
- Estimated time remaining
- Preview thumbnail updated every ~100 frames
- Cancel button

### Completion

On success: dismiss progress, present share sheet with `.mp4`.
On cancel/error: alert, clean up temp file.

## Performance & Thermal

- Throttle to ~10-15 map snapshots/sec max; batch frames sharing the same snapshot
- Monitor `ProcessInfo.thermalState`, pause rendering if critical
- Warn if battery below 20%

## Module Structure

All code in the iOS app, not the SPM packages (depends on MapKit + AVFoundation):

```
CarrierWave/
├── Services/VideoExport/
│   ├── VideoExportActor.swift          # Orchestrator: pipeline setup, public API
│   ├── VideoExportActor+Pipeline.swift # Frame loop, snapshot coordination
│   ├── VideoExportActor+Progress.swift # Progress stream, cancellation
│   ├── VideoEventSequencer.swift       # Builds VideoTimeline from session data
│   ├── VideoFrameCompositor.swift      # MKMapSnapshotter + CG layering
│   ├── VideoWriter.swift               # AVAssetWriter wrapper
│   ├── VideoAudioMixer.swift           # Audio segment extraction, crossfade, silence
│   ├── VideoOverlayRenderer.swift      # Toast cards, HUD, spot pulses (CG drawing)
│   └── VideoExportTypes.swift          # VideoMoment, VideoEvent, VideoTimeline, config
├── Views/Sessions/
│   ├── VideoExportButton.swift         # Entry point on session detail
│   ├── VideoExportSheet.swift          # Configuration + progress UI
│   └── VideoExportSheet+Progress.swift # Progress view extension
```

## Data Dependencies (Read-Only)

| Model | Used For |
|-------|----------|
| `LoggingSession` | Session metadata, start/end, park reference, callsign |
| `QSO` | Contacts with timestamps, callsign, RST, grid/coordinates, band, mode |
| `SessionSpot` | RBN/POTA spots with spotter callsign, coordinates, SNR, timestamp |
| `SDRParameterEvent` | Freq/mode/QSY changes (stored as JSON on `WebSDRRecording`) |
| `WebSDRRecording` | Audio file path, duration, session link |
| `LoggingSession.spotComments` | POTA notes/comments (decoded from `spotCommentsData` JSON blob on session) |

### Sendable Snapshots

All SwiftData `@Model` objects are converted to `Sendable` value-type snapshots immediately after fetching in the actor's `ModelContext`. These snapshots (e.g., `VideoQSOSnapshot`, `VideoSpotSnapshot`) are plain structs containing only the fields needed for video rendering. No `@Model` references cross actor boundaries.

## Threading Model

`VideoExportActor` is the sole actor. Creates its own `ModelContext` from the container, converts all SwiftData models to `Sendable` snapshots, then discards the context. Map snapshotter calls hop to `@MainActor` and return `UIImage` results. All CG compositing and AVAssetWriter work runs on the actor.

### Progress Reporting

The actor exposes an `AsyncStream<VideoExportProgress>` consumed by the UI:

```swift
struct VideoExportProgress: Sendable {
    let framesCompleted: Int
    let totalFrames: Int
    let estimatedSecondsRemaining: TimeInterval?
    let latestThumbnail: CGImage?  // updated every ~100 frames (CGImage is Sendable)
}
```

The UI converts `CGImage` to `UIImage` on the main actor for display.

`VideoExportSheet` observes this stream with `.task` and updates `@State` properties on the main actor.

### Cancellation

The frame loop checks a cancellation flag at the top of each iteration. On cancel: `snapshotter.cancel()` for any in-flight request, `AVAssetWriter.cancelWriting()`, temp file cleanup.

## Future Work

- **Portrait mode** (1080x1920) for Instagram Reels / TikTok / YouTube Shorts
- **4K output** option with render time warning
- **Custom title/outro cards** with activation summary stats
- **Watermark** with callsign/app branding
