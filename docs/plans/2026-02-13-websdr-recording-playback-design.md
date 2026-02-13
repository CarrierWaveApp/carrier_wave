# Design: WebSDR Recording Playback & Sessions Tab

**Date:** 2026-02-13
**Status:** Approved

## Overview

Add playback, scrubbing, and QSO-synced navigation for WebSDR recordings. Surface recordings in activation details (compact player that expands to full-screen) and in a new Sessions segment in the Logs tab.

## Goals

- Play back WebSDR recordings with seeking, speed control, and amplitude waveform visualization
- Dynamically highlight the active QSO based on playback position
- Bidirectional navigation: scrubbing highlights QSOs, tapping QSOs seeks audio
- Trim recordings and share audio clips around specific QSOs
- Browse all logging sessions (POTA, SOTA, casual) with recording indicators

## Non-Goals (Future)

- Background audio playback (AVAudioSession category changes)
- Audio analysis for smarter QSO boundary detection
- Waveform zoom/pinch gestures

## Data Layer

### Time Alignment

Recordings have `startedAt`/`endedAt`. QSOs have `timestamp`. Position of a QSO in the recording:

```
qsoOffset = qso.timestamp - recording.startedAt  (seconds)
```

A QSO is "active" when the playback head is within a window around it:
- **Active window:** `qsoOffset - 90s` to `qsoOffset + 15s`
- Rationale: QSO timestamp is when the contact was logged (end of exchange). The actual exchange audio is mostly before the timestamp.
- These values are adjustable — recordings may not run continuously and timestamps may be offset from reality.

### Recording-to-Activation Linking

Connection path: `WebSDRRecording.loggingSessionId` -> `LoggingSession.id` -> `LoggingSession.parkReference + startedAt date` -> `POTAActivation` (grouped by park+date).

No model changes required. Add query helpers to `WebSDRRecording` to find recordings matching a given activation's park reference and date.

## Audio Playback Engine

`RecordingPlaybackEngine` — an `@Observable` class wrapping `AVAudioPlayer`.

### State

- `currentTime: TimeInterval` — updated via CADisplayLink (~15fps)
- `duration: TimeInterval` — from the audio file
- `isPlaying: Bool`
- `playbackRate: Float` — 0.5, 1.0, 1.5, 2.0
- `activeQSOIndex: Int?` — computed from currentTime vs QSO timestamps
- `amplitudeEnvelope: [Float]` — downsampled peak amplitudes for waveform display

### Amplitude Envelope

On load, scan the CAF file on a background task. Compute one peak value per 0.5s of audio using `AVAudioFile` to read PCM Int16 samples. For a 2-hour recording that's ~14,400 floats — trivial in memory.

### Seeking

- `seek(to: TimeInterval)` — for scrubber drag
- `seekToQSO(at index: Int)` — seeks to `qsoOffset - 90s`, clamped to 0

### Speed Control

`AVAudioPlayer.enableRate = true` + `.rate` property.

### Clip Export

`exportClip(from: TimeInterval, to: TimeInterval) async -> URL?` — uses `AVAssetExportSession` to write a trimmed M4A to a temp directory for sharing.

## UI: Compact Player

Inline card shown in `POTAActivationDetailView` and in the Sessions list when a recording exists.

```
+---------------------------------------------+
| Recording                         >  0:00   |
| [amplitude waveform with QSO tick marks]     |
|                                     1:23:45  |
| KiwiSDR: W3ADO  14.060 CW  1h 24m       >   |
+---------------------------------------------+
```

Components:
- **Mini waveform** (~40pt tall) — amplitude envelope with QSO marker tick marks and playback position indicator
- **Play/pause button** — inline playback. Tapping waveform also seeks.
- **Time labels** — current time / total duration
- **Receiver info** — KiwiSDR name, frequency, mode, duration
- **Tap card** -> navigates to full-screen RecordingPlayerView

Playback continues when scrolling the parent list. Same `RecordingPlaybackEngine` instance is shared with full-screen view (no interruption on navigation).

## UI: Full-Screen Recording Player

Navigated to from the compact player.

### Layout (top to bottom)

1. **Header** — activation info, receiver name. Speed selector in nav bar trailing as a menu.

2. **Waveform scrubber** (~80pt tall) — larger amplitude waveform. QSO markers as vertical lines with callsign labels. Draggable playback head. Time labels show UTC times (recording start + offset) to match QSO timestamps.

3. **Transport controls** — skip back 15s | previous QSO | play/pause | next QSO | skip forward 15s

4. **Speed picker** — segmented or pill buttons: 0.5x, 1.0x, 1.5x, 2.0x

5. **QSO list** — scrollable, sorted chronologically. Active QSO highlighted with accent color and marker. Auto-scrolls to keep active QSO visible. Tapping a QSO seeks audio to that QSO's timestamp minus 90s lead-in.

6. **Action bar** — "Trim Recording" and "Share Clip" buttons.

### Trim Flow

- Draggable start/end handles overlaid on the waveform
- Preview the trimmed region
- "Save" overwrites original (with confirmation) or "Save Copy" exports new file

### Share Clip Flow

- Default range: 90s before to 15s after active QSO's timestamp
- Adjustable range handles
- Export as M4A, present system share sheet

## UI: Sessions Tab

New third segment in `LogsContainerView` (alongside "QSOs" and "POTA Uploads").

### Layout

Sessions grouped by month, sorted by date descending.

```
February 2026
+---------------------------------------------+
| POTA  KI7QCF @ K-1234    Feb 8   12 QSOs   |
| [mini waveform]          1h 24m   Recording |
+---------------------------------------------+
| Casual  KI7QCF           Feb 5    3 QSOs   |
|                           42m               |
+---------------------------------------------+
```

### Behavior

- Lists all completed `LoggingSession` records
- Sessions with a `WebSDRRecording` show mini waveform and recording badge
- Sessions without recordings still appear (useful session history)
- Tapping a session with a recording -> full-screen RecordingPlayerView
- Tapping without a recording -> simple SessionDetailView (QSO list, metadata)
- POTA sessions can link through to activation detail for upload controls

### Data Loading

Following project performance rules: `@State` + `.task` with `FetchDescriptor` and `fetchLimit`, paginated. No `@Query`.

## New Files

| File | Purpose |
|------|---------|
| `RecordingPlaybackEngine.swift` | @Observable AVAudioPlayer wrapper with amplitude, seeking, speed, export |
| `RecordingWaveformView.swift` | Reusable amplitude waveform with QSO markers, playback head, drag-to-seek |
| `CompactRecordingPlayer.swift` | Inline card for activation detail / sessions list |
| `RecordingPlayerView.swift` | Full-screen player with transport, QSO list, trim, share |
| `RecordingPlayerView+Actions.swift` | Trim and clip export logic (split for SwiftLint 500-line limit) |
| `SessionsView.swift` | Sessions list with month grouping and recording previews |
| `SessionDetailView.swift` | Non-POTA session detail (QSO list, metadata, recording player) |

## Modified Files

| File | Change |
|------|--------|
| `POTAActivationDetailView.swift` | Add compact recording player section when recording exists |
| `LogsContainerView.swift` | Add "Sessions" segment to picker |
| `WebSDRRecording.swift` | Add query helpers for finding recordings by activation |
| `FILE_INDEX.md` | Add new files |

## Key Design Decisions

1. Single `RecordingPlaybackEngine` instance shared between compact and full-screen via environment or binding — no playback interruption on navigation
2. Amplitude envelope computed once on load, cached in memory (not persisted)
3. UTC timestamps throughout to match QSO log times
4. Active QSO window of -90s/+15s from timestamp, adjustable later
5. Sessions tab as third segment in LogsContainerView, not a new top-level tab
6. AVAudioPlayer over AVAudioEngine — purpose-built for local file seek/scrub/rate
