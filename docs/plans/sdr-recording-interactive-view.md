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
    let detectedQSORanges: [DetectedQSORange]  // exchange boundaries from decoder
    let generatedAt: Date
    let decoderVersion: String      // cw-swl version string
    let averageWPM: Int
    let averageConfidence: Float
}
```

Storage: Serialized JSON alongside the recording as `[sessionId]-transcript.json` in `WebSDRRecordings/`. Loaded lazily by the playback engine. Cached after first server fetch.

### 4. QSO Time Ranges — Dual Strategy

**Heuristic (always available):** Derive ranges from sorted QSO timestamps:
- Start: midpoint between previous QSO's trail-out and this QSO's lead-in (or recording start)
- End: midpoint between this QSO's trail-out and next QSO's lead-in (or recording end)

**Transcript-derived (when transcript exists):** The transcript includes `DetectedQSORange` entries that identify actual CQ/exchange boundaries from the decoded text. These are more accurate and override the heuristic ranges.

```swift
struct DetectedQSORange: Codable, Sendable {
    let callsign: String
    let startOffset: TimeInterval   // first CQ or callsign mention
    let endOffset: TimeInterval     // final 73/SK/end of exchange
    let loggedQSOId: UUID?          // matched to a logged QSO if possible
}
```

Both are computed in `RecordingPlaybackEngine`. The engine exposes `qsoRanges: [(start: TimeInterval, end: TimeInterval)]` — populated from transcript ranges when available, falling back to the heuristic.

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

**Sizing:** Waveform shrinks from 80pt to 60pt to give the transcript panel more vertical space.

**Implementation:**
- Add `qsoRanges: [(start: TimeInterval, end: TimeInterval)]` parameter
- Render as background rectangles in the ZStack, behind amplitude bars
- Keep existing QSO start tick markers but make them thinner (accent border of the span)

### B. Transcript Panel (`RecordingTranscriptView` — new view)

**Core Interaction: Lyrics-Style Scrolling**

The transcript is a `ScrollViewReader` containing `SDRTranscriptLine` rows. As playback advances:

1. **Active word highlighting** — The word whose `[startOffset, endOffset]` contains `currentTime` gets `.foregroundStyle(.primary)` + `.fontWeight(.bold)`. All other words in the active line are `.foregroundStyle(.primary)`. Past lines are `.foregroundStyle(.secondary)`. Future lines are `.foregroundStyle(.tertiary)`.

2. **Auto-scroll** — The active line is kept vertically centered using `scrollTo(lineId, anchor: .center)` with `.animation(.easeInOut(duration: 0.3))`.

3. **Speaker attribution** — Parse POTA exchange patterns ("DE [callsign]", "CQ POTA DE [callsign]") to identify speakers. When confident, render as chat bubbles (left-aligned for "them", right-aligned for "me"/activator) using the existing chat bubble design language pattern. When not confident, render as a single-stream monospaced text flow without speaker labels — never guess.

4. **Tap interaction** — Tapping any transcript line seeks playback to that line's `startOffset`.

5. **Empty state** — When no transcript is available, show a "Transcribe" button that uploads to the cw-swl server. While processing, show progress. If server is unreachable, explain that transcription requires the cw-swl server.

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
3. Creates metadata in two formats:
   - **M4A chapter markers** embedded in the exported clip (callsign, freq, mode at appropriate timestamps)
   - **Companion `.txt` file** with full human-readable annotation
4. Presents `ShareLink` with both files

**Companion text annotation format:**
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

**M4A chapter markers** (via `AVMutableMetadataItem` with chapter track):
- Chapter at QSO start: "W3ABC — 14.060 MHz CW"
- Chapter at exchange start (if transcript available): "W3ABC DE K4DEF"
- Chapter at QSO end: "73 / End"

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

### Source: cw-swl Server

The remote `cw-swl` server processes recordings and produces time-aligned transcripts. The app uploads the recording audio and receives a transcript JSON response.

### API Contract (draft)

```
POST /api/v1/transcribe
Content-Type: multipart/form-data
Body: audio file (.caf or .m4a)

Response 202 Accepted:
{ "job_id": "uuid", "status": "processing" }

GET /api/v1/transcribe/{job_id}
Response 200 (when complete):
{
  "status": "complete",
  "transcript": { <SDRRecordingTranscript JSON> }
}

Response 200 (still processing):
{ "status": "processing", "progress": 0.45 }
```

### Integration Flow

1. User taps "Transcribe" button on recording player
2. App uploads recording audio to cw-swl server
3. Shows progress indicator while processing
4. On completion, saves transcript as sidecar JSON: `[sessionId]-transcript.json`
5. Playback engine loads transcript and enables lyrics view

### Local Cache

```
WebSDRRecordings/
├── [sessionId].caf                 # audio file
└── [sessionId]-transcript.json     # cached transcript from server
```

Once transcribed, the result is cached locally. Re-transcription only needed if decoder version improves.

### Fallback: Sidecar Import

For offline/manual workflows, the app also checks for a pre-existing `[sessionId]-transcript.json` file (e.g., transferred via AirDrop or iCloud Drive from a local cw-swl run).

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
| `Models/SDRTranscriptModels.swift` | Word, Line, Transcript, DetectedQSORange structs | ~80 |
| `Services/WebSDR/CWSWLClient.swift` | Actor: upload recording, poll status, download transcript | ~120 |
| `Services/WebSDR/RecordingPlaybackEngine.swift` | Add transcript + QSO range tracking | +80 |
| `Views/RecordingPlayer/RecordingWaveformView.swift` | Add QSO span regions + segment boundaries | +50 |
| `Views/RecordingPlayer/RecordingTranscriptView.swift` | Karaoke-style transcript panel | ~200 |
| `Views/RecordingPlayer/RecordingPlayerView.swift` | Restructure layout, add transcript section | ~50 delta |
| `Views/RecordingPlayer/RecordingPlayerView+Actions.swift` | QSO share action, transcript loading | +60 |
| `Services/WebSDR/RecordingClipExporter.swift` | Add chapter markers + metadata companion file | +60 |

---

## Resolved Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | Transcript source | Remote cw-swl server. Upload recording, poll for result, cache locally. Sidecar JSON import as offline fallback. |
| 2 | Speaker attribution | Parse POTA exchange patterns for identity. Single unattributed stream when confidence is low — never guess. |
| 3 | QSO range heuristic | Both: heuristic from timestamps (always available) + transcript-derived `DetectedQSORange` (when transcript exists, overrides heuristic). |
| 4 | Waveform height | Shrink from 80pt → 60pt to maximize transcript panel space. |
| 5 | Share format | Both: M4A chapter markers embedded in clip + companion `.txt` file with full metadata. |

---

## Implementation Phases

### Phase 1 — Data Models + Enhanced Waveform
- `SDRTranscriptModels.swift` (Word, Line, Transcript, DetectedQSORange)
- QSO range computation in `RecordingPlaybackEngine`
- Waveform span regions + segment boundaries in `RecordingWaveformView`
- Waveform height → 60pt

### Phase 2 — Transcript Panel UI
- `RecordingTranscriptView` with lyrics-style scrolling
- Active word/line tracking in the playback engine
- Segment divider labels interleaved in transcript
- Player view layout restructure (transcript replaces QSO list as primary)

### Phase 3 — cw-swl Server Integration
- `CWSWLClient` actor for upload/poll/download
- "Transcribe" button with progress UI
- Sidecar JSON caching
- Empty state → transcribe flow

### Phase 4 — QSO Share with Metadata
- Annotated clip export (chapter markers + companion text)
- Per-QSO share button in collapsible QSO list
- `RecordingClipExporter` metadata enrichment
