# SDR Recording Interactive View — Design Document

## Overview

Enrich the recording player from a basic waveform+QSO-list into an immersive, time-aligned playback experience with live CW transcription, segment labeling, and one-tap audio sharing.

## Current State

The `RecordingPlayerView` today provides:
- Amplitude waveform with thin vertical QSO start markers
- Transport controls (prev/next QSO, ±15s skip, play/pause)
- Speed picker (0.5x–2.0x)
- Plain QSO list (callsign, RST, band, mode) synced to playback position
- "Share Clip" sheet with manual range selection

## Design Goals

1. **QSO Spans** — Visualize QSO *duration* on the waveform (not just a start tick)
2. **Live Transcript** — Karaoke-style scrolling CW transcription, time-aligned to playback
3. **Segment Labels** — Show frequency/mode/park changes as section headers
4. **Tap-to-Share** — Tap a callsign to share its audio clip annotated with metadata

---

## Data Model Additions

### 1. `SDRTranscriptWord` — atomic unit of time-aligned text

```swift
struct SDRTranscriptWord: Codable, Sendable, Identifiable {
    let id: UUID
    let startOffset: TimeInterval   // seconds from recording start
    let endOffset: TimeInterval
    let text: String                // "CQ", "DE", "W3ABC", "599", etc.
    let isCallsign: Bool            // highlighted differently
    let confidence: Float           // 0.0–1.0 from cw-swl decoder
}
```

### 2. `SDRTranscriptLine` — a visual row in the transcript

```swift
struct SDRTranscriptLine: Codable, Sendable, Identifiable {
    let id: UUID
    let startOffset: TimeInterval   // first word's start
    let endOffset: TimeInterval     // last word's end
    let words: [SDRTranscriptWord]
    let speakerCallsign: String?    // attributed station if identifiable
}
```

### 3. `SDRRecordingTranscript` — per-recording transcript envelope

```swift
struct SDRRecordingTranscript: Codable, Sendable {
    let recordingId: UUID
    let lines: [SDRTranscriptLine]
    let generatedAt: Date
    let decoderVersion: String      // cw-swl version string
    let averageWPM: Int
    let averageConfidence: Float
}
```

Storage: Serialized JSON alongside the recording as `[sessionId]-transcript.json` in `WebSDRRecordings/`. Loaded lazily by the playback engine.

### 4. QSO Time Ranges

Each QSO already has a `timestamp` (when it was logged). We derive approximate start/end:

```swift
extension QSO {
    /// Estimated QSO start: midpoint between previous QSO and this one (or recording start)
    /// Estimated QSO end: midpoint between this QSO and next one (or recording end)
}
```

This is computed in `RecordingPlaybackEngine` from the sorted QSO timestamps, not stored. The engine already has `qsoOffsets`; we add `qsoRanges: [(start: TimeInterval, end: TimeInterval)]`.

---

## View Layout

```
┌─────────────────────────────────────────────┐
│ Kenya KiwiSDR                               │  Header
│ 14.060 MHz · CW · Feb 21, 2026 14:23z      │
├─────────────────────────────────────────────┤
│                                             │
│  ▁▃▅██▇▅▃▁▁▃▅██▇▅▃▁▁▃▅██▇▅▃▁▃▅██▇▅▃▁    │  Waveform with:
│  ╠═W3ABC═╣╠═K4DEF═══╣  ╠══N5GHI═══╣       │   • colored QSO spans
│  ▔▔▔▔▔▔▔▔▔▔▔│▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔    │   • playback head (│)
│  14:23:05z              ▲           15:45z  │   • segment frequency labels
│                    14.062 MHz               │
├─────────────────────────────────────────────┤
│        ⏮  ⏪15   ▶   ⏩15  ⏭              │  Transport
│         0.5x  [1x]  1.5x  2.0x             │  Speed
├─────────────────────────────────────────────┤
│                                             │
│  ┌ W3ABC ─────────────────────────────┐     │  Transcript panel:
│  │ CQ CQ CQ DE W3ABC W3ABC K         │     │   • chat-bubble per station
│  └────────────────────────────────────┘     │   • words highlight as
│  ┌────────────────────────── K4DEF ──┐      │     playback passes them
│  │ W3ABC DE K4DEF UR 559 559 BK      │      │   • auto-scrolls to keep
│  └────────────────────────────────────┘     │     active line centered
│  ┌ W3ABC ─────────────────────────────┐     │   • faded past / upcoming
│  │ R UR 579 579 73 DE W3ABC K         │     │     bright current line
│  └────────────────────────────────────┘     │
│                                             │
├── 14.062 MHz · CW ─── K-1234 ──────────────┤  Segment divider (on freq change)
│                                             │
│  ┌ N5GHI ─────────────────────────────┐     │
│  │ CQ POTA DE N5GHI N5GHI K          │     │
│  └────────────────────────────────────┘     │
│                                             │
├─────────────────────────────────────────────┤
│ QSOs (3)                          ∧ expand  │  Collapsible QSO summary
│ 🔊 14:25z  W3ABC    559  20m CW   [↗]     │   • [↗] = share this QSO's clip
│    14:28z  K4DEF    559  20m CW   [↗]     │   • tap row = seek to QSO
│    14:31z  N5GHI    579  20m CW   [↗]     │
└─────────────────────────────────────────────┘
```

### Layout Hierarchy (top to bottom)

1. **Header** — SDR name, initial frequency/mode, date (unchanged)
2. **Enhanced Waveform** — amplitude bars + QSO span regions + segment boundaries + playback head
3. **Time Labels** — current/total time in UTC
4. **Transport + Speed** — unchanged
5. **Transcript Panel** — NEW: scrolling karaoke-style transcript (takes majority of space)
6. **QSO Summary** — collapsed/expandable QSO list at bottom with share buttons

---

## Component Details

### A. Enhanced Waveform (`RecordingWaveformView` updates)

**QSO Span Regions:**
- Colored translucent rectangles behind the amplitude bars
- Each QSO gets a band of `Color.accentColor.opacity(0.08)` spanning its time range
- Active QSO span uses `Color.accentColor.opacity(0.15)`
- Callsign label positioned at the start of each span, small `.caption2` font

**Segment Boundaries:**
- Dashed vertical lines at frequency/mode change points
- Tiny frequency label at the top of each boundary: "14.062"

**Implementation:**
- Add `qsoRanges: [(start: TimeInterval, end: TimeInterval)]` parameter
- Render as background rectangles in the ZStack, behind amplitude bars
- Keep existing QSO start tick markers but make them thinner (accent border of the span)

### B. Transcript Panel (`RecordingTranscriptView` — new view)

**Core Interaction: Lyrics-Style Scrolling**

The transcript is a `ScrollViewReader` containing `SDRTranscriptLine` rows. As playback advances:

1. **Active word highlighting** — The word whose `[startOffset, endOffset]` contains `currentTime` gets `.foregroundStyle(.primary)` + `.fontWeight(.bold)`. All other words in the active line are `.foregroundStyle(.primary)`. Past lines are `.foregroundStyle(.secondary)`. Future lines are `.foregroundStyle(.tertiary)`.

2. **Auto-scroll** — The active line is kept vertically centered using `scrollTo(lineId, anchor: .center)` with `.animation(.easeInOut(duration: 0.3))`.

3. **Chat-bubble attribution** — If `speakerCallsign` is identified, the line renders as a chat bubble (left-aligned for "them", right-aligned for "me"/activator). Uses the existing chat bubble design language pattern.

4. **Tap interaction** — Tapping any transcript line seeks playback to that line's `startOffset`.

5. **Empty state** — When no transcript is available: "No transcription available. Process this recording with cw-swl to generate a time-aligned transcript." with a "Learn More" link.

**Visual Design:**
```swift
// Active line
HStack(alignment: .top, spacing: 8) {
    Text(line.speakerCallsign ?? "")
        .font(.caption.monospaced().weight(.semibold))
        .foregroundStyle(.accentColor)
        .frame(width: 70, alignment: .leading)

    // Words with per-word highlighting
    WrappingHStack(words) { word in
        Text(word.text)
            .font(.subheadline.monospaced())
            .fontWeight(isActiveWord(word) ? .bold : .regular)
            .foregroundStyle(wordColor(word))
            .background(
                isActiveWord(word)
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
            )
    }
}
```

### C. Segment Labels

When the playback crosses a frequency/mode change boundary (from `SDRRecordingSegment`), a divider label appears in the transcript:

```swift
HStack(spacing: 8) {
    VStack { Divider() }
    Text("14.062 MHz · CW")
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    if let parkRef = activeParkRef {
        Text(parkRef)  // "K-1234"
            .font(.caption.weight(.medium))
            .foregroundStyle(.green)
    }
    VStack { Divider() }
}
```

These are interleaved with transcript lines at the appropriate offsets.

### D. QSO List with Share Buttons

The QSO list moves to the bottom and becomes collapsible:

**Collapsed state** (default during playback): Shows a summary bar "3 QSOs" with the active QSO inline.

**Expanded state**: Full list with a share button per row.

**Share button behavior:**
1. Tap the share icon `[↗]` on a QSO row
2. System extracts the QSO's audio clip (timestamp ± lead-in/trail-out)
3. Creates a metadata annotation (callsign, frequency, mode, RST, park ref, UTC time)
4. Presents `ShareLink` with the clip + metadata text

**Metadata annotation format** (included as a companion text file or embedded in the share item):
```
QSO: W3ABC
Frequency: 14.060 MHz
Mode: CW
RST: 559/579
UTC: 2026-02-21 14:25z
Park: K-1234 (Shenandoah NP)
Duration: 2m 15s
Recorded via Kenya KiwiSDR
```

### E. Playback Engine Additions

```swift
// RecordingPlaybackEngine additions:

/// Time ranges for each QSO (derived from sorted timestamps)
private(set) var qsoRanges: [(start: TimeInterval, end: TimeInterval)] = []

/// Currently active transcript line index
private(set) var activeTranscriptLineIndex: Int?

/// Currently active transcript word index within the active line
private(set) var activeTranscriptWordIndex: Int?

/// Loaded transcript (nil if none available)
private(set) var transcript: SDRRecordingTranscript?

/// Load transcript from sidecar JSON file
func loadTranscript(recordingId: UUID) async { ... }

/// Called by display link — updates active word/line indices
private func updateActiveTranscript() { ... }
```

**QSO Range Computation:**
```swift
private func computeQSORanges() {
    guard qsoOffsets.count > 0 else { return }

    var ranges: [(start: TimeInterval, end: TimeInterval)] = []
    for i in 0..<qsoOffsets.count {
        let qsoTime = qsoOffsets[i]
        // Start: midpoint to previous QSO (or recording start)
        let prevEnd = i > 0 ? qsoOffsets[i-1] + activeTrailOut : 0
        let start = max(prevEnd, qsoTime - activeLeadIn)

        // End: midpoint to next QSO (or recording end)
        let nextStart = i < qsoOffsets.count - 1
            ? qsoOffsets[i+1] - activeLeadIn
            : duration
        let end = min(nextStart, qsoTime + activeTrailOut)

        ranges.append((start: start, end: end))
    }
    qsoRanges = ranges
}
```

---

## Transcript Data Pipeline

### Source: cw-swl

The `cw-swl` project produces time-aligned transcripts from audio files. The integration point is a JSON sidecar file:

```
WebSDRRecordings/
├── [sessionId].caf          # audio file
└── [sessionId]-transcript.json  # time-aligned transcript
```

### Generation Options

**Option A — On-device (future):** Run a stripped-down CW decoder from `CarrierWaveCore` over the recording file on a background thread. Reuses `MorseDecoder` + `CWSignalProcessor` from the existing live transcription service but fed from file instead of microphone.

**Option B — External (immediate):** User runs `cw-swl` on their Mac, transfers the transcript JSON to the device (AirDrop, iCloud Drive, or a companion Mac app). The recording view checks for the sidecar file on load.

**Option C — Server-side (future):** Upload recording to the Rust backend, process with cw-swl, return transcript JSON via API.

For v1, support Option B (import from file) and design the UI to gracefully handle missing transcripts. Build the on-device pipeline as a fast-follow.

### Import Flow

1. Recording view checks for `[sessionId]-transcript.json` alongside the audio file
2. If found, parse and load into `RecordingPlaybackEngine.transcript`
3. If not found, show empty state with instructions
4. Future: "Generate Transcript" button for on-device processing

---

## Interaction Details

### Waveform Scrubbing
- Unchanged: drag anywhere on waveform to seek
- QSO span regions are purely visual, not individually tappable on the waveform
- The waveform remains the primary scrub target

### Transcript Tap-to-Seek
- Tap any transcript line → seek to `line.startOffset`
- Tap any word → seek to `word.startOffset` (more precise)
- Long-press a callsign word → copy callsign to clipboard

### QSO Share Flow
1. Tap share icon on QSO row
2. Brief export spinner (reuses `RecordingClipExporter`)
3. System share sheet with: audio clip (.m4a) + metadata text
4. Clip range: `qsoRange.start` to `qsoRange.end`

### Segment Navigation
- When playback crosses a segment boundary, the segment label scrolls into view in the transcript
- The header section updates to show current frequency/mode (already partially supported via `activeSegment`)

---

## File Breakdown

| File | Purpose | Lines (est.) |
|------|---------|-------------|
| `Models/SDRTranscriptModels.swift` | Word, Line, Transcript structs | ~60 |
| `RecordingPlaybackEngine.swift` | Add transcript + QSO range tracking | +80 |
| `RecordingWaveformView.swift` | Add QSO span regions + segment boundaries | +50 |
| `Views/RecordingPlayer/RecordingTranscriptView.swift` | Karaoke-style transcript panel | ~200 |
| `Views/RecordingPlayer/RecordingPlayerView.swift` | Restructure layout, add transcript section | ~50 delta |
| `Views/RecordingPlayer/RecordingPlayerView+Actions.swift` | QSO share action, transcript loading | +60 |
| `Services/WebSDR/RecordingClipExporter.swift` | Add metadata annotation to exports | +40 |

---

## Open Questions

1. **Transcript source for v1:** Should we build the on-device CW decoder pipeline first, or start with sidecar JSON import? (Recommendation: sidecar import first, it's simpler and lets us validate the UI independently of the decoder.)

2. **Speaker attribution:** The CW decoder can try to attribute text to stations based on "DE [callsign]" patterns, but this is imperfect. Should we show unattributed text as a single stream, or always try to split into speakers?

3. **QSO range heuristic:** The midpoint-between-QSOs approach is rough. Should we use the transcript to detect actual CQ/exchange boundaries instead? (Better but requires transcript.)

4. **Waveform height:** With the transcript panel taking significant space, should the waveform shrink (60pt instead of 80pt) or stay the same?

5. **Share format:** Should shared clips include the metadata as an embedded text track (chapter markers in M4A), as a separate .txt file, or both?
